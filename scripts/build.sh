#!/usr/bin/env bash
# Builds dist/PulseBar.app (universal: arm64 + x86_64) and dist/PulseBar.zip.
# Needs only the Xcode Command Line Tools (xcode-select --install); full Xcode is not required.
#
#   scripts/build.sh              universal build
#   ARCHS=arm64 scripts/build.sh  faster single-arch build for local development
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$ROOT/package.json")"
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="13.0"
DIST="$ROOT/dist"
APP="$DIST/PulseBar.app"
BIN_DIR="$DIST/bin"

[ -n "$VERSION" ] || { echo "could not read version from package.json" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BIN_DIR"

slices=()
for arch in $ARCHS; do
  echo "→ compiling $arch"
  swiftc -O -swift-version 5 \
    -target "$arch-apple-macos$MIN_MACOS" \
    "$ROOT"/Sources/*.swift \
    -o "$BIN_DIR/PulseBar-$arch"
  slices+=("$BIN_DIR/PulseBar-$arch")
done

lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/PulseBar"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# Ad-hoc signature: required for arm64 binaries to run. Not a Developer ID signature.
codesign --force --sign - "$APP"
rm -rf "$BIN_DIR"

(cd "$DIST" && ditto -c -k --keepParent PulseBar.app PulseBar.zip)

echo "✓ PulseBar $VERSION → $APP ($(lipo -archs "$APP/Contents/MacOS/PulseBar"))"
echo "  $(du -sh "$APP" | cut -f1) app, $(du -h "$DIST/PulseBar.zip" | cut -f1) zip"
