#!/usr/bin/env bash
# [INPUT] Mode: (none) release or --staging. Empty checkout/license configuration is the
#         three-session free trial; a non-empty one must be a complete Waffo configuration
#         (--staging accepts only the empty one).
# [OUTPUT] dist/Write-It-Down-<version>[-staging].dmg containing the notarized, stapled
#          universal app, an Applications symlink and the WID volume icon, plus a .sha256 sidecar.
#          The app is notarized and stapled on its own before the DMG, so it keeps a ticket
#          after it is copied out of the disk image.
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
python3 - "$plist" "$mode" <<'PY'
import base64, plistlib, sys
from urllib.parse import urlsplit

with open(sys.argv[1], 'rb') as f:
    config = plistlib.load(f)
keys = ('WIDCheckoutURL', 'WIDLicenseServiceURL', 'WIDLicenseProductID', 'WIDLicensePublicKey')
values = [config.get(key, '') for key in keys]
if sys.argv[2] == '--staging':
    if any(values):
        sys.exit('Staging requires empty checkout and license configuration; this DMG cannot be sold.')
    sys.exit(0)
if not any(values):
    sys.exit(0)  # free trial: three local sessions, no checkout or license configuration
try:
    checkout, service = map(urlsplit, values[:2])
    for url in (checkout, service):
        if (url.scheme != 'https' or not url.hostname or url.username or url.password
                or url.fragment or url.hostname in ('localhost', '127.0.0.1', '::1')):
            raise ValueError('HTTPS production URLs required')
    if service.path not in ('', '/') or service.query:
        raise ValueError('service URL must be an origin, without an API path')
    if not values[2].strip() or len(base64.b64decode(values[3], validate=True)) != 32:
        raise ValueError('product and raw Ed25519 public key required')
except (ValueError, TypeError) as error:
    sys.exit(f'Release blocked: configure Waffo checkout and license service in Info.plist: {error}')
PY

WID_APP_OUTPUT="$app" scripts/package-app.sh --unsigned
while IFS= read -r -d '' nested; do
  codesign --force --options runtime --timestamp --sign "$identity" "$nested"
done < <(find "$app/Contents" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0 \
           | sort -rz --zero-terminated)
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile writeitdown-notary \
    --keychain "$HOME/Library/Keychains/login.keychain-db" --wait
}
# Notarize and staple the app itself first, so a copy dragged out of the DMG carries its own ticket.
work="$(mktemp -d "${TMPDIR:-/tmp}/wid-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/app.zip"
notarize "$work/app.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
suffix=''
if [[ "$mode" == '--staging' ]]; then suffix='-staging'; fi
dmg="$PWD/dist/Write-It-Down-$version$suffix.dmg"
rm -f "$dmg" "$dmg.sha256"

# Stage app + Applications symlink + volume icon; hdiutil seals that layout.
stage="$work/stage"
mkdir "$stage"
ditto "$app" "$stage/Write It Down.app"
ln -s /Applications "$stage/Applications"
cp packaging/VolumeIcon.icns "$stage/.VolumeIcon.icns"
rw="$work/rw.dmg"
vol="$work/volume"
mkdir "$vol"
trap 'hdiutil detach "$vol" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
hdiutil create -volname 'Write It Down' -srcfolder "$stage" -format UDRW -ov "$rw"
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$vol" "$rw"
xcrun SetFile -a C "$vol"
hdiutil detach "$vol"
hdiutil convert "$rw" -format UDZO -ov -o "$dmg"
rm -f "$rw"

codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
spctl -a -t exec -v "$app"
codesign --verify --deep --strict --verbose=2 "$app"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
printf 'Release artifact: %s\nChecksum: %s.sha256\n' "$dmg" "$dmg"
