#!/usr/bin/env bash
# [INPUT] Mode: (none) live release or --staging (empty checkout/product IDs).
# [OUTPUT] dist/Write-It-Down-<version>[-staging].dmg containing the
#          universal app and an Applications symlink, plus a .sha256 sidecar.
# [POS] apps/macos/FirstLine/scripts/release-dmg.sh — release packaging on top of
#       scripts/package-app.sh; both modes require the owner's Developer ID.
# [PROTOCOL] Code is signed inside-out (deepest nested bundle first, then the app,
#            then the DMG) instead of --deep, so embedded updater code (Sparkle
#            frameworks/XPC services) can be added later without reworking signing.
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "${1:-}" != "" && "${1:-}" != "--staging" ]] || (( $# > 1 )); then
  echo 'Usage: scripts/release-dmg.sh [--staging]' >&2
  exit 2
fi
mode="${1:-}"

app="${WID_APP_OUTPUT:-$PWD/dist/Write It Down.app}"

identity="${WID_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)"
fi
if [[ -z "$identity" ]] || ! security find-identity -v -p codesigning | grep -Fq "\"$identity\""; then
  echo 'No valid Developer ID Application identity with private key in the login keychain. Ask the Apple Account Holder to create/install it before release.' >&2
  exit 1
fi

plist=Sources/FirstLine/Info.plist
checkout="$(/usr/libexec/PlistBuddy -c 'Print :WIDCheckoutURL' "$plist")"
organization="$(/usr/libexec/PlistBuddy -c 'Print :WIDPolarOrganizationID' "$plist")"
benefit="$(/usr/libexec/PlistBuddy -c 'Print :WIDPolarBenefitID' "$plist")"
if [[ "$mode" == '' && ( ! "$checkout" =~ ^https://[^[:space:]]+$ || -z "$organization" || -z "$benefit" ) ]]; then
  echo 'Release blocked: configure the live Polar WIDCheckoutURL, WIDPolarOrganizationID, and WIDPolarBenefitID in Info.plist first.' >&2
  exit 1
fi
if [[ "$mode" == '--staging' && ( -n "$checkout" || -n "$organization" || -n "$benefit" ) ]]; then
  echo 'Staging requires an empty checkout URL and product ID, so this DMG cannot be sold.' >&2
  exit 1
fi

WID_APP_OUTPUT="$app" scripts/package-app.sh --unsigned
while IFS= read -r -d '' nested; do
  codesign --force --options runtime --timestamp --sign "$identity" "$nested"
done < <(find "$app/Contents" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0 \
           | sort -rz --zero-terminated)
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
suffix=''
if [[ "$mode" == '--staging' ]]; then suffix='-staging'; fi
dmg="$PWD/dist/Write-It-Down-$version$suffix.dmg"
rm -f "$dmg" "$dmg.sha256"

# Stage app + Applications symlink in a temp folder; hdiutil seals that layout.
stage="$(mktemp -d "${TMPDIR:-/tmp}/wid-dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname 'Write It Down' -srcfolder "$stage" -format UDZO -ov "$dmg"

codesign --force --timestamp --sign "$identity" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile writeitdown-notary --keychain "$HOME/Library/Keychains/login.keychain-db" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
codesign --verify --deep --strict --verbose=2 "$app"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf 'Release artifact: %s\nChecksum: %s.sha256\n' "$dmg" "$dmg"
