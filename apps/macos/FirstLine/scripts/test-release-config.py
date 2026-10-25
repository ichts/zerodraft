"""Execute the release packager's configuration gate without building or signing."""
from pathlib import Path
import base64
import os
import plistlib
import shutil
import subprocess
import tempfile

module = Path(__file__).resolve().parents[1]
config = plistlib.loads((module / 'Sources/FirstLine/Info.plist').read_bytes())
keys = ['WIDCheckoutURL', 'WIDLicenseServiceURL', 'WIDLicenseProductID', 'WIDLicensePublicKey']
update_keys = ['SUFeedURL', 'SUPublicEDKey']
PLACEHOLDER_UPDATE_KEY = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
# The tracked Info.plist holds the build placeholder until the captain creates the key and the real
# public key afterwards (docs/RELEASE_KEY.md). Either value must be a raw 32-byte Ed25519 key, and the
# release gate below must refuse the placeholder in both cases.
tracked_update_key = config['SUPublicEDKey']
assert len(base64.b64decode(tracked_update_key, validate=True)) == 32, 'SUPublicEDKey must be the raw 32-byte Ed25519 public key'
real_update_key = (tracked_update_key if tracked_update_key != PLACEHOLDER_UPDATE_KEY
                   else base64.b64encode(bytes(range(32))).decode())

with tempfile.TemporaryDirectory(prefix='release-config-', dir=module) as directory:
    root = Path(directory)
    (root / 'scripts').mkdir()
    (root / 'Sources/FirstLine').mkdir(parents=True)
    (root / 'bin').mkdir()
    shutil.copyfile(module / 'scripts/release-dmg.sh', root / 'scripts/release-dmg.sh')
    package = root / 'scripts/package-app.sh'
    package.write_text('#!/bin/sh\necho CONFIGURATION_ACCEPTED\nexit 42\n')
    package.chmod(0o755)
    security = root / 'bin/security'
    security.write_text('#!/bin/sh\necho \'1) "Developer ID Application: Release Gate Fixture"\'\n')
    security.chmod(0o755)
    env = {**os.environ, 'PATH': f"{root / 'bin'}:{os.environ['PATH']}",
           'WID_SIGNING_IDENTITY': 'Developer ID Application: Release Gate Fixture'}
    signed = {**config, 'SUPublicEDKey': real_update_key}

    def run(values, *args):
        (root / 'Sources/FirstLine/Info.plist').write_bytes(plistlib.dumps(values))
        return subprocess.run(['bash', str(root / 'scripts/release-dmg.sh'), *args],
                              env=env, capture_output=True, text=True)

    accepted = run(signed)
    assert accepted.returncode == 42 and 'CONFIGURATION_ACCEPTED' in accepted.stdout, accepted.stderr
    for missing in [keys, *[[key] for key in keys], update_keys, *[[key] for key in update_keys]]:
        values = {**signed, **dict.fromkeys(missing, '')}
        rejected = run(values)
        assert rejected.returncode == 1 and 'Release blocked:' in rejected.stderr, rejected.stderr
        assert 'CONFIGURATION_ACCEPTED' not in rejected.stdout
    for key, value in [('WIDLicenseServiceURL', 'http://licenses.writeitdown.app'),
                       ('WIDLicensePublicKey', 'invalid'),
                       ('WIDCheckoutURL', 'https://localhost/mac.html'),
                       ('SUFeedURL', 'http://writeitdown.app/download/appcast.xml'),
                       ('SUFeedURL', 'https://writeitdown.app/download/appcast.xml#frag'),
                       ('SUPublicEDKey', PLACEHOLDER_UPDATE_KEY),
                       ('SUPublicEDKey', 'invalid'),
                       ('SUEnableAutomaticChecks', True),
                       ('CFBundleVersion', 'abc'),
                       ('CFBundleVersion', '0')]:
        rejected = run({**signed, key: value})
        assert rejected.returncode == 1 and 'Release blocked:' in rejected.stderr, rejected.stderr
        assert 'CONFIGURATION_ACCEPTED' not in rejected.stdout
    placeholder = run({**config, 'SUPublicEDKey': PLACEHOLDER_UPDATE_KEY})
    assert placeholder.returncode == 1 and 'placeholder' in placeholder.stderr, placeholder.stderr
    staging = run(config, '--staging')
    assert staging.returncode == 1 and 'Staging requires empty' in staging.stderr, staging.stderr
    staging = run({**config, **dict.fromkeys(keys, '')}, '--staging')
    assert staging.returncode == 42, staging.stderr

    # A build number that is not greater than the last release reaches no installed copy.
    updates = root / 'dist/updates'
    updates.mkdir(parents=True)
    (updates / 'last-build.txt').write_text('7\n')
    repeated = run(signed)
    assert repeated.returncode == 1 and 'not greater than the last release' in repeated.stderr, repeated.stderr
    (updates / 'last-build.txt').write_text('1\n')
    advanced = run(signed)
    assert advanced.returncode == 42, advanced.stderr
print('PASS: release requires complete license and update configuration; a placeholder update key,')
print('      an unsafe feed, an unchecksummed build number, and staging with sale config are refused.')
