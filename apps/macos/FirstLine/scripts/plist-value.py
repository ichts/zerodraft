"""[INPUT] <Info.plist> <key>
[OUTPUT] stdout: the text value of that plist key, without surrounding whitespace. Exit 1 when the
         file cannot be read or the key holds no string or integer.
[POS] apps/macos/FirstLine/scripts/plist-value.py - the one plist field reader shared by
      release-dmg.sh, update-payload-name.sh and publish-appcast.sh.
[PROTOCOL] plistlib, never /usr/libexec/PlistBuddy: scripts/test-release-config.py runs these
           release gates from the Linux CI runner, where PlistBuddy does not exist, so a gate that
           read the plist through it could only be checked on the packing Mac.
"""
import plistlib
import sys

if len(sys.argv) != 3:
    sys.exit('usage: plist-value.py <Info.plist> <key>')
path, key = sys.argv[1:3]
try:
    with open(path, 'rb') as handle:
        values = plistlib.load(handle)
except (OSError, plistlib.InvalidFileException) as error:
    sys.exit(f'cannot read {path}: {error}')
value = values.get(key) if isinstance(values, dict) else None
if isinstance(value, bool) or not isinstance(value, (int, str)):
    sys.exit(f'{path} has no string or integer {key}')
print(str(value).strip())
