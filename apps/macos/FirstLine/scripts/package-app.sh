#!/usr/bin/env bash
# [INPUT] Mode argument: --adhoc (default, ad-hoc signed) or --unsigned; optional
#         WID_APP_OUTPUT override for the .app destination.
# [OUTPUT] A universal (arm64 + x86_64) dist/Write It Down.app bundle; exit 0 only
#          when the bundle builds, assembles, and (in --adhoc mode) verifies.
# [POS] apps/macos/FirstLine/scripts/package-app.sh — the single packager every
#       release and QA path calls; release-dmg.sh drives it with --unsigned.
# [PROTOCOL] --adhoc signs inside-out (nested code first, then the outer bundle)
#            so future embedded code (Sparkle frameworks/XPC services) slots in
#            without resurrecting the deprecated --deep flag.
set -euo pipefail

cd "$(dirname "$0")/.."
mode="${1:---adhoc}"
if [[ "$mode" != "--adhoc" && "$mode" != "--unsigned" ]]; then
  echo 'Usage: scripts/package-app.sh [--adhoc|--unsigned]' >&2
  exit 2
fi

# Universal build: same arch flags must go to the build AND to --show-bin-path,
# because a universal product lands in .build/apple/Products/Release, not the
# single-arch .build/<host-triple>/release the default bin path reports.
archs=(--arch arm64 --arch x86_64)
swift build -c release "${archs[@]}"
bin_dir="$(swift build -c release "${archs[@]}" --show-bin-path)"
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
  # Inside-out: sign the deepest nested code bundle first, then the outer app.
  # Nested code is signed in leaf-to-root order so each parent seals a stable child.
  while IFS= read -r -d '' nested; do
    codesign --force --sign - "$nested"
  done < <(find "$app/Contents" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0 \
             | sort -rz --zero-terminated)
  codesign --force --sign - "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
printf 'Packaged: %s (%s, universal)\n' "$app" "$mode"
