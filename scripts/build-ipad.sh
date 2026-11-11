#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage: build-ipad.sh [--out NEW_DIRECTORY]

Builds an unsigned universal iPad Wizard .app for armv7 and arm64.
The output directory must not already exist. By default, creates a private
directory under .private-audit/ in the source workspace.

Set IOS_SDK to an iPhoneOS SDK directory. The original private workspace may
fall back to its local iPhoneOS9.3.sdk when IOS_SDK is unset; exported source
does not contain an SDK and requires IOS_SDK.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT_ARG=""
while (($#)); do
  case "$1" in
    --out)
      (($# >= 2)) || { usage >&2; exit 2; }
      OUT_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "${APP_SOURCE_DIR:-}" ]]; then
  SOURCE_DIR="$APP_SOURCE_DIR"
elif [[ -f "$WORKSPACE_ROOT/App/main.m" ]]; then
  SOURCE_DIR="$WORKSPACE_ROOT/App"
else
  printf 'ERROR: could not locate the current App/main.m. Set APP_SOURCE_DIR only for an explicit source audit.\n' >&2
  exit 2
fi

[[ -f "$SOURCE_DIR/main.m" ]] || { printf 'ERROR: APP_SOURCE_DIR must contain main.m.\n' >&2; exit 2; }
[[ -f "$SOURCE_DIR/Info.plist" ]] || { printf 'ERROR: app source is missing Info.plist.\n' >&2; exit 2; }
LOCAL_IMPORTS="$(sed -nE 's/^[[:space:]]*#[[:space:]]*(import|include)[[:space:]]+"([^"]+)".*/\2/p' "$SOURCE_DIR/main.m")"
while IFS= read -r HEADER; do
  [[ -n "$HEADER" ]] || continue
  case "$HEADER" in
    IWMediaCatalog.h|IWHTTPTransport.h|IWWeatherService.h|IWFrameProbe.h) [[ -f "$SOURCE_DIR/$HEADER" ]] || { printf 'ERROR: a reviewed local header is missing.\n' >&2; exit 2; } ;;
    *) printf 'ERROR: main.m references an unreviewed local header; update the reviewed build allowlist first.\n' >&2; exit 2 ;;
  esac
done <<< "$LOCAL_IMPORTS"

SDK_FROM_ENV=0
if [[ -n "${IOS_SDK:-}" ]]; then
  SDK_PATH="$IOS_SDK"
  SDK_FROM_ENV=1
else
  PRIVATE_SDK="$WORKSPACE_ROOT/.local/toolchains/iPhoneOS9.3.sdk"
  PRIVATE_SOURCE="$WORKSPACE_ROOT/App/main.m"
  if [[ -f "$PRIVATE_SOURCE" && -d "$PRIVATE_SDK" && "$SOURCE_DIR" == "$WORKSPACE_ROOT/App" ]]; then
    SDK_PATH="$PRIVATE_SDK"
  else
    printf 'ERROR: set IOS_SDK to an iPhoneOS SDK directory; exported source does not include an SDK.\n' >&2
    exit 2
  fi
fi

[[ -d "$SDK_PATH/System/Library/Frameworks" && -d "$SDK_PATH/usr/lib" ]] || {
  printf 'ERROR: IOS_SDK is not a usable iPhoneOS SDK directory.\n' >&2
  exit 2
}

CLANG_BIN="${CLANG:-/usr/bin/clang}"
LIPO_BIN="${LIPO:-/usr/bin/lipo}"
NM_BIN="${NM:-/usr/bin/nm}"
[[ -x "$CLANG_BIN" ]] || { printf 'ERROR: clang not found; set CLANG to a compiler executable.\n' >&2; exit 2; }
[[ -x "$LIPO_BIN" ]] || { printf 'ERROR: lipo not found; set LIPO to a compatible executable.\n' >&2; exit 2; }
[[ -x "$NM_BIN" ]] || { printf 'ERROR: nm not found; set NM to a compatible executable.\n' >&2; exit 2; }

if [[ -n "$OUT_ARG" ]]; then
  OUT_IS_DEFAULT=0
  case "$OUT_ARG" in
    /*) OUT_DIR="$OUT_ARG" ;;
    *) OUT_DIR="$PWD/$OUT_ARG" ;;
  esac
else
  OUT_IS_DEFAULT=1
  PRIVATE_BASE="$WORKSPACE_ROOT/.private-audit"
  OUT_DIR="$PRIVATE_BASE/ipad-build-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi

if [[ -e "$OUT_DIR" || -L "$OUT_DIR" ]]; then
  printf 'ERROR: output directory already exists; choose a new path.\n' >&2
  exit 2
fi
TMP_ROOT="${TMPDIR:-/tmp}"
WORK_DIR="$(mktemp -d "${TMP_ROOT%/}/wizard-ipad-build.XXXXXX")"
cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'ERROR: shasum or sha256sum is required to bind build inputs.\n' >&2
    return 2
  fi
}

INPUTS=(main.m Info.plist IWMediaCatalog.h IWHTTPTransport.h IWWeatherService.h IWWeatherService.m IWFrameProbe.h)
RESOURCE_FILES=(Icon-76.png Icon-76@2x.png Icon-83.5@2x.png Default-Landscape.png Default-Landscape@2x.png ViceCity.jpg)
if [[ -d "$SOURCE_DIR/Resources" ]]; then
  for RESOURCE in "${RESOURCE_FILES[@]}"; do INPUTS+=("Resources/$RESOURCE"); done
fi
INPUT_HASHES_BEFORE=()
for INDEX in "${!INPUTS[@]}"; do
  INPUT="${INPUTS[$INDEX]}"
  [[ -f "$SOURCE_DIR/$INPUT" ]] || { printf 'ERROR: required reviewed input is missing: %s\n' "$INPUT" >&2; exit 2; }
  INPUT_HASHES_BEFORE[$INDEX]="$(sha256_file "$SOURCE_DIR/$INPUT")"
done

APP_DIR="$WORK_DIR/WizardSystem.app"
mkdir -m 700 "$APP_DIR"
cp "$SOURCE_DIR/Info.plist" "$APP_DIR/Info.plist"
if [[ -d "$SOURCE_DIR/Resources" ]]; then
  for RESOURCE in "${RESOURCE_FILES[@]}"; do cp "$SOURCE_DIR/Resources/$RESOURCE" "$APP_DIR/$RESOURCE"; done
fi
for INDEX in "${!INPUTS[@]}"; do
  printf '%s %s\n' "${INPUTS[$INDEX]}" "${INPUT_HASHES_BEFORE[$INDEX]}"
done > "$WORK_DIR/INPUTS.sha256"
SOURCE_FINGERPRINT="$(sha256_file "$WORK_DIR/INPUTS.sha256")"
/usr/libexec/PlistBuddy -c "Add :WizardSourceFingerprint string $SOURCE_FINGERPRINT" "$APP_DIR/Info.plist"

FRAMEWORKS=(UIKit Foundation AVFoundation MediaPlayer CoreMotion CoreMedia QuartzCore CoreGraphics CoreLocation CoreFoundation)
FRAMEWORK_FLAGS=()
for FRAMEWORK in "${FRAMEWORKS[@]}"; do
  FRAMEWORK_FLAGS+=(-framework "$FRAMEWORK")
done
run_clang_for_arch() {
  local arch="$1"
  shift
  if [[ "$arch" == armv7 ]]; then
    "$CLANG_BIN" -mno-thumb "$@"
  else
    "$CLANG_BIN" "$@"
  fi
}
WARNING_COUNTS=()
for ARCH in armv7 arm64; do
  mkdir -m 700 "$WORK_DIR/$ARCH"
  LOG_FILE="$WORK_DIR/$ARCH/clang.stderr"
  if ! run_clang_for_arch "$ARCH" \
    -target "$ARCH-apple-ios9.0" \
    -miphoneos-version-min=9.0 \
    -fobjc-arc \
    -isysroot "$SDK_PATH" \
    -I"$SOURCE_DIR" \
    -F"$SDK_PATH/System/Library/Frameworks" \
    -L"$SDK_PATH/usr/lib" \
    "$SOURCE_DIR/main.m" \
    "$SOURCE_DIR/IWWeatherService.m" \
    "${FRAMEWORK_FLAGS[@]}" \
    -Wl,-undefined,dynamic_lookup \
    -o "$WORK_DIR/$ARCH/WizardSystem" \
    2>"$LOG_FILE"; then
    mkdir -p "$WORKSPACE_ROOT/.private-audit"
    FAILURE_DIR="$(mktemp -d "$WORKSPACE_ROOT/.private-audit/build-failure.XXXXXX")"
    cp "$LOG_FILE" "$FAILURE_DIR/$ARCH.stderr"
    chmod 600 "$FAILURE_DIR/$ARCH.stderr"
    printf 'ERROR: %s compilation failed; local diagnostics: %s/%s.stderr\n' "$ARCH" "$FAILURE_DIR" "$ARCH" >&2
    exit 1
  fi
  NM_LOG="$WORK_DIR/$ARCH/nm.stderr"
  UNDEFINED_LOG="$WORK_DIR/$ARCH/undefined-symbols.txt"
  if ! "$NM_BIN" -u -j "$WORK_DIR/$ARCH/WizardSystem" >"$UNDEFINED_LOG" 2>"$NM_LOG"; then
    mkdir -p "$WORKSPACE_ROOT/.private-audit"
    FAILURE_DIR="$(mktemp -d "$WORKSPACE_ROOT/.private-audit/build-failure.XXXXXX")"
    cp "$LOG_FILE" "$FAILURE_DIR/$ARCH.stderr"
    cp "$NM_LOG" "$FAILURE_DIR/$ARCH.nm.stderr"
    printf 'ERROR: %s symbol inspection failed; local diagnostics: %s\n' "$ARCH" "$FAILURE_DIR" >&2
    exit 1
  fi
  if grep -E '^[[:space:]]*(_OBJC_(CLASS|METACLASS|IVAR)_[$]_IW|_IW)' "$UNDEFINED_LOG" >"$WORK_DIR/$ARCH/undefined-app-symbols.txt"; then
    mkdir -p "$WORKSPACE_ROOT/.private-audit"
    FAILURE_DIR="$(mktemp -d "$WORKSPACE_ROOT/.private-audit/build-failure.XXXXXX")"
    cp "$LOG_FILE" "$FAILURE_DIR/$ARCH.stderr"
    cp "$WORK_DIR/$ARCH/undefined-app-symbols.txt" "$FAILURE_DIR/$ARCH.undefined-app-symbols.txt"
    printf 'ERROR: %s has undefined Wizard IW symbols; local diagnostics: %s\n' "$ARCH" "$FAILURE_DIR" >&2
    exit 1
  elif [[ $? -ne 1 ]]; then
    printf 'ERROR: %s undefined-symbol matching failed; no output candidate was published.\n' "$ARCH" >&2
    exit 1
  fi
  COUNT="$(grep -c 'warning:' "$LOG_FILE" || true)"
  WARNING_COUNTS+=("$ARCH=$COUNT")
done

"$LIPO_BIN" -create \
  "$WORK_DIR/armv7/WizardSystem" \
  "$WORK_DIR/arm64/WizardSystem" \
  -output "$APP_DIR/WizardSystem"
chmod 755 "$APP_DIR/WizardSystem"
ARCHITECTURES="$("$LIPO_BIN" "$APP_DIR/WizardSystem" -archs)"
if [[ " $ARCHITECTURES " != *" armv7 "* || " $ARCHITECTURES " != *" arm64 "* ]]; then
  printf 'ERROR: universal binary is missing a required architecture (lipo reported: %s).\n' "$ARCHITECTURES" >&2
  exit 3
fi

INPUT_HASHES_AFTER=()
for INDEX in "${!INPUTS[@]}"; do
  INPUT="${INPUTS[$INDEX]}"
  INPUT_HASHES_AFTER[$INDEX]="$(sha256_file "$SOURCE_DIR/$INPUT")"
  if [[ "${INPUT_HASHES_BEFORE[$INDEX]}" != "${INPUT_HASHES_AFTER[$INDEX]}" ]]; then
    printf 'ERROR: build input changed while compiling (%s); no output candidate was published.\n' "$INPUT" >&2
    exit 3
  fi
done

HASH_ARMV7="$(sha256_file "$WORK_DIR/armv7/WizardSystem")"
HASH_ARM64="$(sha256_file "$WORK_DIR/arm64/WizardSystem")"
HASH_UNIVERSAL="$(sha256_file "$APP_DIR/WizardSystem")"
CLANG_VERSION="$("$CLANG_BIN" --version 2>/dev/null | head -n 1)"
SDK_NAME="$(basename "$SDK_PATH")"

{
  printf 'artifact: WizardSystem.app/WizardSystem\n'
  printf 'architectures: %s\n' "$ARCHITECTURES"
  printf 'minimum_ios: 9.0\n'
  printf 'sdk: %s (path intentionally omitted)\n' "$SDK_NAME"
  if ((SDK_FROM_ENV)); then
    printf 'sdk_source: IOS_SDK environment variable\n'
  else
    printf 'sdk_source: private-workspace fallback; do not include SDK in exports\n'
  fi
  printf 'compiler: %s\n' "$CLANG_VERSION"
  printf 'compile_command_template: CLANG -target <ARCH>-apple-ios9.0 -miphoneos-version-min=9.0 [armv7: -mno-thumb] -fobjc-arc -isysroot <IOS_SDK> -I<APP_SOURCE> -F<SDK_FRAMEWORKS> -L<SDK_LIBS> <APP_SOURCE>/main.m <APP_SOURCE>/IWWeatherService.m -framework UIKit -framework Foundation -framework AVFoundation -framework MediaPlayer -framework CoreMotion -framework CoreMedia -framework QuartzCore -framework CoreGraphics -framework CoreLocation -framework CoreFoundation -Wl,-undefined,dynamic_lookup\n'
  printf 'link_command_template: LIPO -create <armv7-binary> <arm64-binary> -output WizardSystem.app/WizardSystem\n'
  printf 'source_hash_snapshot_before:\n'
  for INDEX in "${!INPUTS[@]}"; do printf '  %s: %s\n' "${INPUTS[$INDEX]}" "${INPUT_HASHES_BEFORE[$INDEX]}"; done
  printf 'source_hash_snapshot_after:\n'
  for INDEX in "${!INPUTS[@]}"; do printf '  %s: %s\n' "${INPUTS[$INDEX]}" "${INPUT_HASHES_AFTER[$INDEX]}"; done
  printf 'source_fingerprint: %s\n' "$SOURCE_FINGERPRINT"
  printf 'sha256_armv7: %s\n' "$HASH_ARMV7"
  printf 'sha256_arm64: %s\n' "$HASH_ARM64"
  printf 'sha256_universal: %s\n' "$HASH_UNIVERSAL"
  printf 'compiler_warnings: %s\n' "${WARNING_COUNTS[*]}"
  printf 'linkage_policy: dynamic_lookup retained for legacy private symbols; undefined IW functions and IW Objective-C classes/metaclasses/ivars rejected per architecture; runtime system symbol resolution is not proven by this host build\n'
  printf 'code_signing: not performed\n'
  printf 'icons: reviewed Wizard Resources copied when present; owned Wizard launch images included; no third-party media bundled\n'
} > "$WORK_DIR/BUILD-METADATA.txt"

if [[ -e "$OUT_DIR" || -L "$OUT_DIR" ]]; then
  printf 'ERROR: output path appeared during the build; no existing path was changed.\n' >&2
  exit 2
fi
mkdir -p "$(dirname "$OUT_DIR")"
mkdir -m 700 "$OUT_DIR"
cp -R "$APP_DIR" "$OUT_DIR/WizardSystem.app"
cp "$WORK_DIR/BUILD-METADATA.txt" "$OUT_DIR/BUILD-METADATA.txt"
[[ "$(sha256_file "$OUT_DIR/WizardSystem.app/WizardSystem")" == "$HASH_UNIVERSAL" ]] || {
  printf 'ERROR: staged app hash differs after copy. Output retained for inspection but is invalid.\n' >&2
  exit 3
}

case "$OUT_DIR" in
  "$WORKSPACE_ROOT"/*) DISPLAY_OUT=".${OUT_DIR#"$WORKSPACE_ROOT"}" ;;
  *)
    if ((OUT_IS_DEFAULT)); then DISPLAY_OUT="<private-output>/$(basename "$OUT_DIR")";
    else DISPLAY_OUT="<custom-output>/$(basename "$OUT_DIR")"; fi
    ;;
esac
printf 'Build complete: %s/WizardSystem.app (armv7 + arm64; unsigned).\n' "$DISPLAY_OUT"
printf 'Build record: %s/BUILD-METADATA.txt\n' "$DISPLAY_OUT"
