#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/App/WizardPowerTweak"
if [[ "${1:-}" != --out || $# != 2 ]]; then
  printf 'Usage: build-power.sh --out NEW_DIRECTORY\n' >&2
  exit 2
fi
OUTPUT="$2"
[[ "$OUTPUT" == /* ]] || OUTPUT="$PWD/$OUTPUT"
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || { printf 'Output already exists.\n' >&2; exit 2; }
SDK="${IOS_SDK:-$ROOT/.local/toolchains/iPhoneOS9.3.sdk}"
[[ -d "$SDK/System/Library/Frameworks" ]] || { printf 'Set IOS_SDK to your own iPhoneOS SDK.\n' >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wizard-power-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
BEFORE="$(shasum -a 256 "$SOURCE/Tweak.xm" "$SOURCE/WizardPower.plist")"
compile_arch() {
  local arch="$1"
  shift
  if [[ "$arch" == armv7 ]]; then /usr/bin/clang -mno-thumb "$@";
  else /usr/bin/clang "$@"; fi
}
for ARCH in armv7 arm64; do
  compile_arch "$ARCH" -target "$ARCH-apple-ios9.0" -fobjc-arc \
    -isysroot "$SDK" -F"$SDK/System/Library/Frameworks" -L"$SDK/usr/lib" \
    -x objective-c "$SOURCE/Tweak.xm" -dynamiclib -framework UIKit -framework Foundation \
    -Wl,-undefined,dynamic_lookup -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/WizardPower.dylib \
    -o "$WORK/WizardPower.$ARCH.dylib" 2>"$WORK/$ARCH.stderr"
done
[[ "$BEFORE" == "$(shasum -a 256 "$SOURCE/Tweak.xm" "$SOURCE/WizardPower.plist")" ]] || { printf 'Source changed during build.\n' >&2; exit 3; }
/usr/bin/lipo -create "$WORK/WizardPower.armv7.dylib" "$WORK/WizardPower.arm64.dylib" -output "$WORK/WizardPower.dylib"
[[ "$(/usr/bin/lipo -archs "$WORK/WizardPower.dylib")" == 'armv7 arm64' ]] || { printf 'Unexpected architectures.\n' >&2; exit 3; }
mkdir -p "$(dirname "$OUTPUT")"
mkdir -m 700 "$OUTPUT"
cp "$WORK/WizardPower.dylib" "$SOURCE/WizardPower.plist" "$OUTPUT/"
cp "$WORK/armv7.stderr" "$WORK/arm64.stderr" "$OUTPUT/"
{
  printf 'component: optional experimental WizardPower addon\narchitectures: armv7 arm64\nminimum_ios: 9.0\n'
  printf 'source_sha256: %s\n' "$(shasum -a 256 "$SOURCE/Tweak.xm" | awk '{print $1}')"
  printf 'binary_sha256: %s\n' "$(shasum -a 256 "$OUTPUT/WizardPower.dylib" | awk '{print $1}')"
  printf 'signed: no\ninstalled: no\ndevice_acceptance: not established by this build\n'
} > "$OUTPUT/BUILD-METADATA.txt"
printf 'Built optional WizardPower for armv7 + arm64. No signing, installation or device operation performed.\n'
