#!/usr/bin/env bash
# [INPUT] Mode argument: --adhoc (default, ad-hoc signed) or --unsigned; optional
#         WID_APP_OUTPUT override for the .app destination.
# [OUTPUT] A universal (arm64 + x86_64) dist/Write It Down.app bundle carrying
#          Contents/Frameworks/Sparkle.framework; exit 0 only when the bundle builds,
#          assembles, and (in --adhoc mode) verifies.
# [POS] apps/macos/FirstLine/scripts/package-app.sh — the single packager every
#       release and QA path calls; release-dmg.sh drives it with --unsigned.
# [PROTOCOL] Signing is delegated to scripts/sign-nested.sh (inside-out, plain Mach-O
#            first) so the ad-hoc QA build and the Developer ID release cannot drift.
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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/WriteItDown" "$app/Contents/MacOS/WriteItDown"
cp -R "$bin_dir/WriteItDown_WriteItDown.bundle" "$app/Contents/Resources/"

# Sparkle lives beside the executable's ../Frameworks (the rpath Package.swift adds). ditto, not
# cp -R: the framework carries Versions/Current symlinks and breaking them breaks the signature.
framework="$bin_dir/Sparkle.framework"
if [[ ! -d "$framework" ]]; then
  framework="$(find .build -maxdepth 6 -type d -name Sparkle.framework -print -quit 2>/dev/null || true)"
fi
if [[ ! -d "$framework" ]]; then
  echo "Sparkle.framework was not found next to $bin_dir/WriteItDown; run swift package resolve first." >&2
  exit 1
fi
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
linked="$(otool -L "$app/Contents/MacOS/WriteItDown")"
if [[ "$linked" != *'@rpath/Sparkle.framework'* ]]; then
  echo 'The built executable does not link @rpath/Sparkle.framework; the linkerSettings rpath is missing.' >&2
  exit 1
fi
test -d "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" || {
  echo 'The embedded Sparkle.framework has no Versions/B/Updater.app; the framework copy is incomplete.' >&2
  exit 1
}
# One universal app: a single-architecture framework would drop Intel Macs silently.
case "$(lipo -info "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle")" in
  *x86_64*arm64*) ;;
  *) echo 'The embedded Sparkle binary is not universal (x86_64 + arm64); check the SwiftPM artifact.' >&2
     exit 1 ;;
esac

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
  scripts/sign-nested.sh "$app" -
fi
printf 'Packaged: %s (%s, universal)\n' "$app" "$mode"
