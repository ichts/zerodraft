#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "${1:-}" != "" && "${1:-}" != "--staging" ]] || (( $# > 1 )); then
  echo 'Usage: scripts/release-dmg.sh [--staging]' >&2
  exit 2
fi
staging=false
if [[ "${1:-}" == "--staging" ]]; then staging=true; fi
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
if [[ "$staging" == false && ( ! "$checkout" =~ ^https://[^[:space:]]+$ || -z "$organization" || -z "$benefit" ) ]]; then
  echo 'Release blocked: configure the live Polar WIDCheckoutURL, WIDPolarOrganizationID, and WIDPolarBenefitID in Info.plist first.' >&2
  exit 1
fi
if [[ "$staging" == true && ( -n "$checkout" || -n "$organization" || -n "$benefit" ) ]]; then
  echo 'Staging requires an empty checkout URL and product ID, so this DMG cannot be sold.' >&2
  exit 1
fi

app="${WID_APP_OUTPUT:-$PWD/dist/Write It Down.app}"
WID_APP_OUTPUT="$app" scripts/package-app.sh --unsigned
codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
suffix=''
if [[ "$staging" == true ]]; then suffix='-staging'; fi
dmg="$PWD/dist/Write-It-Down-$version$suffix.dmg"
rm -f "$dmg" "$dmg.sha256"
hdiutil create -volname 'Write It Down' -srcfolder "$app" -format UDZO -ov "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile writeitdown-notary --keychain "$HOME/Library/Keychains/login.keychain-db" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
codesign --verify --deep --strict --verbose=2 "$app"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf 'Release artifact: %s\nChecksum: %s.sha256\n' "$dmg" "$dmg"
