#!/usr/bin/env bash
# [INPUT] Mode: (none) configured release or --staging (empty checkout/license config only).
#         Release requires the complete HTTPS license service, product and raw Ed25519
#         public key in Info.plist, plus the Sparkle feed URL, the real (non-placeholder)
#         update signing key and the signed-feed policy (SURequireSignedFeed,
#         SUVerifyUpdateBeforeExtraction and a zero SUSignedFeedFailureExpirationInterval).
#         TEST and LIVE use the same app configuration. A release also requires
#         dist/updates/last-build.txt to hold exactly the last released CFBundleVersion.
# [OUTPUT] dist/Write-It-Down-<version>[-staging].dmg containing the notarized, stapled
#          universal app, an Applications symlink and the WID volume icon, plus a .sha256 sidecar.
#          A release run also writes dist/updates/WriteItDown-<version>-<build>.zip (the Sparkle
#          update payload, made from the same stapled app) and records dist/updates/last-build.txt.
#          The app is notarized and stapled on its own before the DMG, so it keeps a ticket
#          after it is copied out of the disk image.
# [POS] apps/macos/FirstLine/scripts/release-dmg.sh - release packaging on top of
#       scripts/package-app.sh; both modes require the owner's Developer ID. The appcast is a
#       separate step: scripts/publish-appcast.sh.
# [PROTOCOL] Signing is scripts/sign-nested.sh (plain Mach-O first, then nested bundles, then
#            the app, then the same-team gate), which is what makes Sparkle's Autoupdate helper
#            pass notarization. The update ZIP is written after notarization and stapling only,
#            so the payload users receive carries its own ticket; staging runs skip it.
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
if not all(values):
    sys.exit('Release blocked: configure checkout, license service, product and public key in Info.plist.')
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
    sys.exit(f'Release blocked: configure checkout and license service in Info.plist: {error}')

# Sparkle: no release may ship a placeholder update key, and the feed must be real HTTPS.
PLACEHOLDER_UPDATE_KEY = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
try:
    feed = urlsplit(str(config.get('SUFeedURL', '')))
    if feed.scheme != 'https' or not feed.hostname or feed.username or feed.fragment:
        raise ValueError('HTTPS appcast URL required')
    update_key = str(config.get('SUPublicEDKey', ''))
    if update_key == PLACEHOLDER_UPDATE_KEY:
        raise ValueError('SUPublicEDKey is still the build placeholder; run Sparkle generate_keys on the release Mac and put the printed key in Info.plist')
    if len(base64.b64decode(update_key, validate=True)) != 32:
        raise ValueError('SUPublicEDKey must be the raw 32-byte Ed25519 public key')
    if config.get('SUEnableAutomaticChecks') is not False:
        raise ValueError('SUEnableAutomaticChecks must be false: no check runs until the writer turns it on')
    if config.get('SURequireSignedFeed') is not True:
        raise ValueError('SURequireSignedFeed must be true: installed copies must refuse a rewritten feed')
    if config.get('SUVerifyUpdateBeforeExtraction') is not True:
        raise ValueError('SUVerifyUpdateBeforeExtraction must be true: Sparkle requires it together with a signed feed')
    interval = config.get('SUSignedFeedFailureExpirationInterval')
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or interval != 0:
        raise ValueError('SUSignedFeedFailureExpirationInterval must be 0: no grace period may accept an unverified feed')
    build = str(config.get('CFBundleVersion', '')).strip()
    if not build.isdigit() or int(build) <= 0:
        raise ValueError('CFBundleVersion must be a positive integer: Sparkle compares it, not the marketing version')
except (ValueError, TypeError) as error:
    sys.exit(f'Release blocked: configure the update feed in Info.plist: {error}')
PY

# Sparkle compares CFBundleVersion; a reused or lower number reaches no installed copy. Staging
# neither enters the update feed nor records a build, so it is not held to the last release.
last_build_file="$PWD/dist/updates/last-build.txt"
if [[ "$mode" != '--staging' ]]; then
  build="$(python3 scripts/plist-value.py "$plist" CFBundleVersion)"
  if [[ ! -e "$last_build_file" && ! -L "$last_build_file" ]]; then
    printf 'Release blocked: %s is missing. Record the last released CFBundleVersion there; on a fresh release machine write the last shipped build number (1 for the 1.0 release) first.\n' "$last_build_file" >&2
    exit 1
  fi
  if [[ ! -f "$last_build_file" || ! -r "$last_build_file" ]]; then
    printf 'Release blocked: %s is unreadable; it must record the last released CFBundleVersion.\n' "$last_build_file" >&2
    exit 1
  fi
  last_build=''
  IFS= read -r -d '' last_build < "$last_build_file" || true
  last_build="${last_build%$'\n'}"
  if [[ ! "$last_build" =~ ^[0-9]+$ ]]; then
    printf 'Release blocked: %s must hold one build number, found "%s".\n' "$last_build_file" "${last_build//$'\n'/\\n}" >&2
    exit 1
  fi
  if (( build <= 10#$last_build )); then
    echo "Release blocked: CFBundleVersion $build is not greater than the last release ($last_build in dist/updates/last-build.txt)." >&2
    exit 1
  fi
fi

WID_APP_OUTPUT="$app" scripts/package-app.sh --unsigned
scripts/sign-nested.sh "$app" "$identity"

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

version="$(python3 scripts/plist-value.py "$app/Contents/Info.plist" CFBundleShortVersionString)"
suffix=''
if [[ "$mode" == '--staging' ]]; then suffix='-staging'; fi

# The update payload: the same notarized, stapled app users get from the DMG. Never create it
# before stapling, and never for staging, so a staging build can never enter the feed.
if [[ "$mode" != '--staging' ]]; then
  mkdir -p dist/updates
  update_zip="$PWD/dist/updates/$(scripts/update-payload-name.sh "$plist")"
  rm -f "$update_zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$update_zip"
fi

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
# Custom-icon bit belongs on the mounted volume; -srcfolder drops folder FinderInfo.
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
if [[ "$mode" != '--staging' ]]; then
  printf '%s\n' "$build" > "$last_build_file"
  printf 'Update payload: %s\n' "$update_zip"
fi
printf 'Release artifact: %s\nChecksum: %s.sha256\n' "$dmg" "$dmg"
