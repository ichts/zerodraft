#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
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
product="$(/usr/libexec/PlistBuddy -c 'Print :WIDDodoProductID' "$plist")"
if [[ ! "$checkout" =~ ^https://[^[:space:]]+$ || -z "$product" ]]; then
  echo 'Release blocked: configure the live Dodo WIDCheckoutURL and WIDDodoProductID in Info.plist first.' >&2
  exit 1
fi

app="${WID_APP_OUTPUT:-$PWD/dist/Write It Down.app}"
WID_APP_OUTPUT="$app" scripts/package-app.sh --unsigned
codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="$PWD/dist/Write-It-Down-$version.dmg"
rm -f "$dmg" "$dmg.sha256"
hdiutil create -volname 'Write It Down' -srcfolder "$app" -format UDZO -ov "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile writeitdown-notary --keychain "$HOME/Library/Keychains/login.keychain-db" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
codesign --verify --deep --strict --verbose=2 "$app"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf 'Release artifact: %s\nChecksum: %s.sha256\n' "$dmg" "$dmg"
