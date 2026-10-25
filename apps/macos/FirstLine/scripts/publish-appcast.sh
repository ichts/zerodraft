#!/usr/bin/env bash
# [INPUT] Environment overrides: WID_SPARKLE_BIN (Sparkle's bin directory; by default the pinned
#         Sparkle 2.10.0 tools under .build/artifacts/sparkle/Sparkle/bin, materialised with
#         `swift package resolve` when missing, then /Applications/Sparkle-2.10.0/bin),
#         WID_SPARKLE_ACCOUNT (Keychain account for the update signing key; default writeitdown),
#         WID_SPARKLE_KEY_FILE (use an exported private key file instead of the Keychain, for a
#         disposable test feed), WID_UPDATES_DIR (archives directory; default dist/updates).
# [OUTPUT] dist/updates/appcast.xml plus a .delta per previous release archive, verified after
#          generation: the signing key matches SUPublicEDKey, the newest item is this build, and
#          both the feed signature and the enclosure signature verify. Exit 0 only when every
#          assertion holds. This script never uploads and never touches the host; the upload order
#          and routing checks are owned by writeitdown/README.md.
# [POS] apps/macos/FirstLine/scripts/publish-appcast.sh - the step after release-dmg.sh; it only
#       writes and verifies the signed feed and payloads on the release machine.
# [PROTOCOL] The update signing key never enters this repository: it stays in the release Mac's
#            login Keychain (docs/RELEASE_KEY.md). The bundle opts into a signed feed
#            (SURequireSignedFeed + SUVerifyUpdateBeforeExtraction), so generate_appcast embeds the
#            feed signature and sign_update --verify <appcast.xml> can prove the feed was not
#            rewritten after signing. Archive names are space-free so the appcast URLs stay readable.
set -euo pipefail

cd "$(dirname "$0")/.."
sparkle_bin="${WID_SPARKLE_BIN:-}"
if [[ -z "$sparkle_bin" ]]; then
  pinned="$PWD/.build/artifacts/sparkle/Sparkle/bin"
  if [[ ! -x "$pinned/generate_appcast" ]] && command -v swift >/dev/null 2>&1; then
    swift package resolve >/dev/null 2>&1 || true
  fi
  for candidate in "$pinned" /Applications/Sparkle-2.10.0/bin; do
    if [[ -x "$candidate/generate_appcast" && -x "$candidate/sign_update" ]]; then
      sparkle_bin="$candidate"
      break
    fi
  done
fi
account="${WID_SPARKLE_ACCOUNT:-writeitdown}"
updates_dir="${WID_UPDATES_DIR:-$PWD/dist/updates}"
appcast_url_prefix='https://writeitdown.app/download/updates/'
product_link='https://writeitdown.app/mac.html'
plist=Sources/FirstLine/Info.plist

tools=(generate_appcast sign_update)
if [[ -z "${WID_SPARKLE_KEY_FILE:-}" ]]; then
  tools+=(generate_keys)
fi
for tool in "${tools[@]}"; do
  if [[ ! -x "${sparkle_bin:-/nonexistent}/$tool" ]]; then
    echo "Missing Sparkle tool $tool. Run 'swift package resolve' in this directory, or set WID_SPARKLE_BIN to a Sparkle 2.10.0 bin directory." >&2
    exit 1
  fi
done
if [[ ! -d "$updates_dir" ]]; then
  echo "No archives directory at $updates_dir; run scripts/release-dmg.sh first." >&2
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
archive="WriteItDown-$version.zip"
if [[ ! -f "$updates_dir/$archive" ]]; then
  echo "Missing update payload $updates_dir/$archive; scripts/release-dmg.sh writes it from the stapled app." >&2
  exit 1
fi

key_args=(--account "$account")
if [[ -n "${WID_SPARKLE_KEY_FILE:-}" ]]; then
  key_args=(--ed-key-file "$WID_SPARKLE_KEY_FILE")
  python3 scripts/sparkle-key.py --plist "$plist" --key-file "$WID_SPARKLE_KEY_FILE"
else
  python3 scripts/sparkle-key.py --plist "$plist" --generate-keys "$sparkle_bin/generate_keys" --account "$account"
fi

"$sparkle_bin/generate_appcast" \
  "${key_args[@]}" \
  --download-url-prefix "$appcast_url_prefix" \
  --link "$product_link" \
  --maximum-versions 3 \
  --maximum-deltas 3 \
  "$updates_dir"

# Verify what was written instead of trusting the tool: the newest item must be this build, and
# both the enclosure and the feed itself must verify against the key the bundle trusts.
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
"$sparkle_bin/sign_update" --verify "${key_args[@]}" "$updates_dir/appcast.xml"

deltas="$(find "$updates_dir" -maxdepth 1 -name '*.delta' -print | wc -l | tr -d ' ')"
printf 'Appcast: %s (signed feed and enclosure verified)\n' "$updates_dir/appcast.xml"
printf 'Archive: %s (%s bytes), delta files: %s\n' "$archive" "$(wc -c < "$updates_dir/$archive" | tr -d ' ')" "$deltas"
