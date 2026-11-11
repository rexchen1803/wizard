#!/bin/sh
# Installed by wizard-system's Debian package. Do not run against stock iOS.
set -eu

PACKAGE_ROOT=/
DRY_RUN=0
DRY_MODEL=
DRY_IOS_VERSION=
DRY_UID=

fail() {
  printf 'Wizard installer: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat <<'USAGE'
Usage:
  install-wizard.sh configure BUILD
  install-wizard.sh remove BUILD
  install-wizard.sh rollback /Applications/WizardSystem.rollback-*.app
  install-wizard.sh --dry-run --root TEST_ROOT --model MODEL --ios-version VERSION --uid 0 configure|remove BUILD

The dry-run form only validates a fixture tree and prints the planned action.
USAGE
}

if [ "${1:-}" = --dry-run ]; then
  DRY_RUN=1
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root)
        [ "$#" -ge 2 ] || fail '--root requires a fixture directory'
        PACKAGE_ROOT=$2
        shift 2
        ;;
      --model)
        [ "$#" -ge 2 ] || fail '--model requires a value'
        DRY_MODEL=$2
        shift 2
        ;;
      --ios-version)
        [ "$#" -ge 2 ] || fail '--ios-version requires a value'
        DRY_IOS_VERSION=$2
        shift 2
        ;;
      --uid)
        [ "$#" -ge 2 ] || fail '--uid requires a value'
        DRY_UID=$2
        shift 2
        ;;
      *) break ;;
    esac
  done
fi

model_version() {
  if [ "$DRY_RUN" -eq 1 ]; then
    [ -n "$DRY_MODEL" ] && [ -n "$DRY_IOS_VERSION" ] || fail 'dry-run requires --model and --ios-version'
    printf '%s:%s\n' "$DRY_MODEL" "$DRY_IOS_VERSION"
  else
    MODEL=$(sysctl -n hw.machine 2>/dev/null) || fail 'could not read the hardware model'
    IOS_VERSION=$(sw_vers -productVersion 2>/dev/null) || fail 'could not read the iOS version'
    printf '%s:%s\n' "$MODEL" "$IOS_VERSION"
  fi
}

check_device_scope() {
  case "$(model_version)" in
    iPad2,4:9.3.5|iPad3,4:10.3.3|iPad4,1:12.5.8) ;;
    *) fail 'unsupported model or OS; see docs/INSTALL.md for the allowlist' ;;
  esac
  if [ "$DRY_RUN" -eq 1 ]; then
    [ "$DRY_UID" = 0 ] || fail 'root access is required'
  else
    [ "$(id -u 2>/dev/null)" = 0 ] || fail 'package installation must run as root'
  fi
  APP_ROOT="${PACKAGE_ROOT%/}/Applications"
  [ -d "$APP_ROOT" ] && [ ! -L "$APP_ROOT" ] && [ -w "$APP_ROOT" ] || fail 'a writable rootful /Applications directory is required'
  if [ "$DRY_RUN" -eq 0 ]; then
    command -v dpkg >/dev/null 2>&1 || fail 'a rootful Debian package environment is required'
  fi
}

require_command() {
  if [ "$DRY_RUN" -eq 0 ]; then
    command -v "$1" >/dev/null 2>&1 || fail "$2"
  fi
}

bundle_id_is_wizard() {
  BUNDLE_INFO=$1/Info.plist
  BUNDLE_EXECUTABLE=$1/WizardSystem
  [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$BUNDLE_INFO" ] && [ ! -L "$BUNDLE_INFO" ] &&
    [ -f "$BUNDLE_EXECUTABLE" ] && [ ! -L "$BUNDLE_EXECUTABLE" ] &&
    grep -Fq '<string>com.rex.wizardsystem</string>' "$BUNDLE_INFO"
}

bundle_build_is() {
  awk -v expected="$2" '
    /<key>CFBundleVersion<\/key>/ {
      if (getline <= 0) exit 1
      gsub(/[[:space:]]/, "", $0)
      if ($0 == "<string>" expected "</string>") found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$1/Info.plist"
}

safe_build() {
  case "$1" in
    ''|*[!0-9.]*|.*|*.) return 1 ;;
    *..*) return 1 ;;
    *) return 0 ;;
  esac
}

configure() {
  BUILD=$1
  safe_build "$BUILD" || fail 'invalid package build number'
  check_device_scope
  require_command ldid 'ldid is required to sign this unsigned build'
  require_command uicache 'uicache is required to register or refresh Wizard'
  require_command killall 'killall is required for a controlled Wizard update'
  TARGET="$APP_ROOT/WizardSystem.app"
  PAYLOAD="$APP_ROOT/.wizard-package-payload-$BUILD.app"
  bundle_id_is_wizard "$PAYLOAD" || fail 'package payload is missing or is not a Wizard app bundle'
  if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    bundle_id_is_wizard "$TARGET" || fail 'existing /Applications/WizardSystem.app is not a valid Wizard bundle'
    ACTION=update
  else
    ACTION=install
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN: %s /Applications/WizardSystem.app (build %s)\n' "$ACTION" "$BUILD"
    printf 'DRY RUN: preserve /var/mobile/Media/iPadWizard/app and Wizard preferences\n'
    printf 'DRY RUN: no signing, package writes, process stop, registration, or app launch performed\n'
    return 0
  fi

  ldid -S "$PAYLOAD/WizardSystem" || fail 'ldid signing failed; the existing app was not replaced'
  STAMP=$(date -u +%Y%m%dT%H%M%SZ) || fail 'could not create a rollback timestamp'
  BACKUP="$APP_ROOT/WizardSystem.rollback-$BUILD-$STAMP.app"
  FAILED="$APP_ROOT/WizardSystem.failed-$BUILD-$STAMP.app"
  [ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] || fail 'rollback path already exists'
  [ ! -e "$FAILED" ] && [ ! -L "$FAILED" ] || fail 'failure-recovery path already exists'

  if [ "$ACTION" = update ]; then
    killall -TERM WizardSystem >/dev/null 2>&1 || true
    sleep 1
    mv "$TARGET" "$BACKUP" || fail 'could not preserve the existing app as rollback'
  fi
  if ! mv "$PAYLOAD" "$TARGET"; then
    if [ "$ACTION" = update ]; then mv "$BACKUP" "$TARGET" || fail 'app move failed and automatic rollback also failed'; fi
    fail 'could not place the candidate app'
  fi
  if ! uicache -p "$TARGET"; then
    if [ "$ACTION" = update ]; then
      mv "$TARGET" "$FAILED" || fail 'registration failed and candidate could not be retained for recovery'
      mv "$BACKUP" "$TARGET" || fail 'registration failed and automatic rollback also failed'
      uicache -p "$TARGET" >/dev/null 2>&1 || true
    else
      mv "$TARGET" "$PAYLOAD" || fail 'registration failed and the new app could not be moved back to its package payload path'
    fi
    fail 'uicache registration failed; the prior app was restored when one existed'
  fi

  printf 'Wizard %s completed. The app was not launched.\n' "$ACTION"
  if [ "$ACTION" = update ]; then
    printf 'Rollback bundle: %s\n' "$BACKUP"
  fi
}

remove() {
  BUILD=$1
  safe_build "$BUILD" || fail 'invalid package build number'
  check_device_scope
  TARGET="$APP_ROOT/WizardSystem.app"
  if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    printf 'Wizard app is already absent; package helper can be removed.\n'
    return 0
  fi
  bundle_id_is_wizard "$TARGET" || fail 'installed app path is not a valid Wizard bundle'
  if ! bundle_build_is "$TARGET" "$BUILD"; then
    printf 'Preserving /Applications/WizardSystem.app because its build does not match package build %s.\n' "$BUILD"
    return 0
  fi
  require_command uicache 'uicache is required to unregister Wizard'
  require_command killall 'killall is required for a controlled Wizard removal'
  STAMP=$(date -u +%Y%m%dT%H%M%SZ) || fail 'could not create an uninstall timestamp'
  ARCHIVE="$APP_ROOT/WizardSystem.uninstalled-$BUILD-$STAMP.app"
  [ ! -e "$ARCHIVE" ] && [ ! -L "$ARCHIVE" ] || fail 'recoverable uninstall path already exists'
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN: stop Wizard once, retain matching app at %s, and unregister /Applications/WizardSystem.app\n' "$ARCHIVE"
    printf 'DRY RUN: preserve /var/mobile/Media/iPadWizard/app, preferences, and existing rollback bundles\n'
    printf 'DRY RUN: no package writes, process stop, registration, or app launch performed\n'
    return 0
  fi
  killall -TERM WizardSystem >/dev/null 2>&1 || true
  sleep 1
  mv "$TARGET" "$ARCHIVE" || fail 'could not retain the installed app before removal'
  if ! uicache -u "$TARGET"; then
    mv "$ARCHIVE" "$TARGET" || fail 'app unregister failed and automatic recovery also failed'
    uicache -p "$TARGET" >/dev/null 2>&1 || true
    fail 'uicache could not unregister Wizard; the app was restored and package removal must be retried only after review'
  fi
  printf 'Wizard app unregistered and retained at: %s\n' "$ARCHIVE"
  printf 'Media, preferences, and previous rollback bundles were preserved.\n'
}

rollback() {
  ROLLBACK_PATH=$1
  check_device_scope
  require_command uicache 'uicache is required to register the restored app'
  require_command killall 'killall is required for a controlled Wizard rollback'
  case "$ROLLBACK_PATH" in
    "$APP_ROOT"/WizardSystem.rollback-*.app|"$APP_ROOT"/WizardSystem.uninstalled-*.app) ;;
    *) fail 'rollback path must be a retained /Applications/WizardSystem.rollback-*.app or WizardSystem.uninstalled-*.app bundle' ;;
  esac
  bundle_id_is_wizard "$ROLLBACK_PATH" || fail 'rollback bundle is missing or invalid'
  TARGET="$APP_ROOT/WizardSystem.app"
  if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    bundle_id_is_wizard "$TARGET" || fail 'installed app path is not a valid Wizard bundle'
  else
    fail 'there is no installed Wizard app to roll back'
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN: restore %s to /Applications/WizardSystem.app\n' "${ROLLBACK_PATH##*/}"
    printf 'DRY RUN: no package writes, process stop, registration, or app launch performed\n'
    return 0
  fi
  FAILED="$APP_ROOT/WizardSystem.failed-rollback-$(date -u +%Y%m%dT%H%M%SZ).app"
  [ ! -e "$FAILED" ] && [ ! -L "$FAILED" ] || fail 'failure-recovery path already exists'
  killall -TERM WizardSystem >/dev/null 2>&1 || true
  sleep 1
  mv "$TARGET" "$FAILED" || fail 'could not preserve the current app before rollback'
  if ! mv "$ROLLBACK_PATH" "$TARGET"; then
    mv "$FAILED" "$TARGET" || fail 'rollback move failed and automatic recovery also failed'
    fail 'could not restore the selected rollback bundle'
  fi
  if ! uicache -p "$TARGET"; then
    mv "$TARGET" "$ROLLBACK_PATH" || fail 'rollback registration failed and restored bundle could not be retained'
    mv "$FAILED" "$TARGET" || fail 'rollback registration failed and automatic recovery also failed'
    uicache -p "$TARGET" >/dev/null 2>&1 || true
    fail 'uicache registration failed; the current app was restored'
  fi
  printf 'Wizard rollback completed. The app was not launched.\n'
  printf 'Previous candidate retained: %s\n' "$FAILED"
}

if [ "$DRY_RUN" -eq 1 ]; then
  [ -n "$PACKAGE_ROOT" ] && [ -d "$PACKAGE_ROOT" ] || fail 'dry-run root must be an existing fixture directory'
  [ ! -L "$PACKAGE_ROOT" ] || fail 'dry-run root cannot be a symlink'
  [ "$#" -ge 1 ] || { usage >&2; exit 2; }
fi

case "${1:-}" in
  configure)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    configure "$2"
    ;;
  rollback)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    rollback "$2"
    ;;
  remove)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    remove "$2"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
