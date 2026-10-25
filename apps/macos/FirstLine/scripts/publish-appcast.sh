#!/usr/bin/env bash
# [INPUT] Environment overrides: WID_SPARKLE_BIN (Sparkle's bin directory holding generate_appcast
#         and sign_update; default /Applications/Sparkle-2.10.0/bin), WID_SPARKLE_ACCOUNT (Keychain
#         account for the update signing key; default writeitdown), WID_SPARKLE_KEY_FILE (use an
#         exported private key file instead of the Keychain, for a disposable test feed),
#         WID_UPDATES_DIR (archives directory; default dist/updates).
# [OUTPUT] dist/updates/appcast.xml plus a .delta per previous release archive, verified after
#          generation (build number, marketing version, enclosure signature), and the exact
#          upload commands. Exit 0 only when every assertion holds. This script never uploads and
#          never touches the host.
# [POS] apps/macos/FirstLine/scripts/publish-appcast.sh — the step after release-dmg.sh; the
#       archive and its deltas are uploaded before the feed, so a user never sees a feed that
#       points at a missing payload.
# [PROTOCOL] The update signing key never enters this repository: it stays in the release Mac's
#            login Keychain (docs/RELEASE_KEY.md). Archive names are space-free so the appcast
#            URLs stay readable.
set -euo pipefail

cd "$(dirname "$0")/.."
sparkle_bin="${WID_SPARKLE_BIN:-/Applications/Sparkle-2.10.0/bin}"
account="${WID_SPARKLE_ACCOUNT:-writeitdown}"
updates_dir="${WID_UPDATES_DIR:-$PWD/dist/updates}"
appcast_url_prefix='https://writeitdown.app/download/updates/'
product_link='https://writeitdown.app/mac.html'

for tool in generate_appcast sign_update; do
  if [[ ! -x "$sparkle_bin/$tool" ]]; then
    echo "Missing $sparkle_bin/$tool. Download Sparkle 2.10.0 (Sparkle-2.10.0.tar.xz) and set WID_SPARKLE_BIN to its bin directory." >&2
    exit 1
  fi
done
if [[ ! -d "$updates_dir" ]]; then
  echo "No archives directory at $updates_dir; run scripts/release-dmg.sh first." >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/FirstLine/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/FirstLine/Info.plist)"
archive="WriteItDown-$version.zip"
if [[ ! -f "$updates_dir/$archive" ]]; then
  echo "Missing update payload $updates_dir/$archive; scripts/release-dmg.sh writes it from the stapled app." >&2
  exit 1
fi

key_args=(--account "$account")
if [[ -n "${WID_SPARKLE_KEY_FILE:-}" ]]; then
  key_args=(--ed-key-file "$WID_SPARKLE_KEY_FILE")
fi

"$sparkle_bin/generate_appcast" \
  "${key_args[@]}" \
  --download-url-prefix "$appcast_url_prefix" \
  --link "$product_link" \
  --maximum-versions 3 \
  --maximum-deltas 3 \
  "$updates_dir"

# Verify what was written instead of trusting the tool: the newest item must be this build, and
# its enclosure signature must verify against the same key that signed it.
signature="$(python3 - "$updates_dir/appcast.xml" "$version" "$build" <<'PY'
import sys, xml.etree.ElementTree as ET

path, version, build = sys.argv[1:4]
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(path).getroot().findall('./channel/item')
matches = [item for item in items
           if item.findtext('sparkle:version', namespaces=ns) == build
           and item.findtext('sparkle:shortVersionString', namespaces=ns) == version]
if len(matches) != 1:
    sys.exit(f'appcast.xml must carry exactly one item for version {version} (build {build}), found {len(matches)}')
item = matches[0]
if not item.findtext('sparkle:minimumSystemVersion', namespaces=ns):
    sys.exit('appcast.xml item has no sparkle:minimumSystemVersion')
if item.findtext('sparkle:hardwareRequirements', namespaces=ns):
    sys.exit('appcast.xml item restricts hardware; the release must stay one universal app')
enclosure = item.find('enclosure')
signature = enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
if not signature or not enclosure.get('url', '').startswith('https://writeitdown.app/download/updates/'):
    sys.exit('appcast.xml item has no EdDSA-signed HTTPS enclosure')
print(signature)
PY
)"
"$sparkle_bin/sign_update" --verify "${key_args[@]}" "$updates_dir/$archive" "$signature"

deltas="$(find "$updates_dir" -maxdepth 1 -name '*.delta' -print | wc -l | tr -d ' ')"
printf 'Appcast: %s\n' "$updates_dir/appcast.xml"
printf 'Archive: %s (%s bytes), delta files: %s\n' "$archive" "$(wc -c < "$updates_dir/$archive" | tr -d ' ')" "$deltas"
cat <<EOF

Upload from the release machine, payload first and feed last. Nothing in this repository deploys.
  rsync -av '$updates_dir'/*.zip '$updates_dir'/*.delta host:/var/www/writeitdown.app/download/updates/
  rsync -av '$updates_dir'/appcast.xml host:/var/www/writeitdown.app/download/appcast.xml

Then prove the routing before announcing the release:
  curl -sSI https://writeitdown.app/download/appcast.xml | grep -Ei '^(HTTP|content-type)'
  curl -sSI $appcast_url_prefix$archive | head -1
  curl -sSI ${appcast_url_prefix}missing.zip | head -1   # must be 404, never 200 HTML
EOF
