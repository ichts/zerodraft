#!/usr/bin/env bash
# [INPUT] Optional Info.plist path (default Sources/FirstLine/Info.plist, relative to
#         apps/macos/FirstLine).
# [OUTPUT] stdout: the Sparkle update payload file name,
#          WriteItDown-<CFBundleShortVersionString>-<CFBundleVersion>.zip
# [POS] apps/macos/FirstLine/scripts/update-payload-name.sh - the one definition of the payload name,
#       shared by the release packager (writer) and the feed generator (looker-up).
# [PROTOCOL] The name must change whenever the bytes may change: Sparkle derives the enclosure URL
#            from this file name, and the host serves /download/updates/* as immutable, so a rebuild
#            that only raises CFBundleVersion must still get a new name.
set -euo pipefail

plist="${1:-Sources/FirstLine/Info.plist}"
reader="$(dirname "$0")/plist-value.py"
version="$(python3 "$reader" "$plist" CFBundleShortVersionString)"
build="$(python3 "$reader" "$plist" CFBundleVersion)"
printf 'WriteItDown-%s-%s.zip\n' "$version" "$build"
