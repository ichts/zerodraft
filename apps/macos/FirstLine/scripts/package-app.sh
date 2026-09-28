#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mode="${1:---adhoc}"
if [[ "$mode" != "--adhoc" && "$mode" != "--unsigned" ]]; then
  echo 'Usage: scripts/package-app.sh [--adhoc|--unsigned]' >&2
  exit 2
fi

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="${WID_APP_OUTPUT:-$PWD/dist/Write It Down.app}"
if [[ "$app" != */'Write It Down.app' || "$app" == '/Write It Down.app' ]]; then
  echo 'WID_APP_OUTPUT must end in Write It Down.app under a parent directory.' >&2
  exit 2
fi
mkdir -p "$(dirname "$app")"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/WriteItDown" "$app/Contents/MacOS/WriteItDown"
cp -R "$bin_dir/WriteItDown_WriteItDown.bundle" "$app/Contents/Resources/"
cp Sources/FirstLine/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.0' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string WriteItDown' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$plist"

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
trap 'rm -rf "$(dirname "$iconset")"' EXIT
for png in Sources/FirstLine/Assets.xcassets/AppIcon.appiconset/AppIcon_*.png; do
  cp "$png" "$iconset/icon_${png##*AppIcon_}"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

if [[ "$mode" == "--adhoc" ]]; then
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
printf 'Packaged: %s (%s)\n' "$app" "$mode"
