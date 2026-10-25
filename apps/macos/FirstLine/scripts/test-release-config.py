"""Execute the release gates without building or signing."""
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
# The tracked Info.plist carries the captain's real public key (docs/RELEASE_KEY.md). The release
# gate below still refuses the pre-key placeholder: a build signed with a throwaway key could never
# be updated by the captain's key.
tracked_update_key = config['SUPublicEDKey']
assert len(base64.b64decode(tracked_update_key, validate=True)) == 32, 'SUPublicEDKey must be the raw 32-byte Ed25519 public key'
real_update_key = (tracked_update_key if tracked_update_key != PLACEHOLDER_UPDATE_KEY
                   else base64.b64encode(bytes(range(32))).decode())
# RFC 8032 test vector: seed and the public key its Ed25519 key pair must produce.
seed = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
seed_public = bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')

with tempfile.TemporaryDirectory(prefix='release-config-', dir=module) as directory:
    root = Path(directory)
    (root / 'scripts').mkdir()
    (root / 'Sources/FirstLine').mkdir(parents=True)
    (root / 'bin').mkdir()
    for script in ['release-dmg.sh', 'publish-appcast.sh', 'sparkle-key.py']:
        shutil.copyfile(module / 'scripts' / script, root / 'scripts' / script)
    package = root / 'scripts/package-app.sh'
    package.write_text('#!/bin/sh\necho CONFIGURATION_ACCEPTED\nexit 42\n')
    package.chmod(0o755)
    security = root / 'bin/security'
    security.write_text('#!/bin/sh\necho \'1) "Developer ID Application: Release Gate Fixture"\'\n')
    security.chmod(0o755)
    plist_path = root / 'Sources/FirstLine/Info.plist'
    env = {**os.environ, 'PATH': f"{root / 'bin'}:{os.environ['PATH']}",
           'WID_SIGNING_IDENTITY': 'Developer ID Application: Release Gate Fixture'}
    env.pop('WID_SPARKLE_KEY_FILE', None)
    signed = {**config, 'SUPublicEDKey': real_update_key}

    def run(values, *args):
        plist_path.write_bytes(plistlib.dumps(values))
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
                       ('SURequireSignedFeed', False),
                       ('SUVerifyUpdateBeforeExtraction', False),
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

    # A build number that is not greater than the last release reaches no installed copy, while a
    # staging run neither enters the feed nor records a build, so it is not held to that number.
    updates = root / 'dist/updates'
    updates.mkdir(parents=True)
    (updates / 'last-build.txt').write_text('7\n')
    repeated = run(signed)
    assert repeated.returncode == 1 and 'not greater than the last release' in repeated.stderr, repeated.stderr
    staging = run({**config, **dict.fromkeys(keys, '')}, '--staging')
    assert staging.returncode == 42, staging.stderr
    (updates / 'last-build.txt').write_text('1\n')
    advanced = run(signed)
    assert advanced.returncode == 42, advanced.stderr

    # The feed gate: the signing key must be the pair the shipped bundle trusts, and it must be
    # proven before generate_appcast writes anything.
    key_plist = root / 'keygate.plist'
    key_plist.write_bytes(plistlib.dumps({'SUPublicEDKey': base64.b64encode(seed_public).decode()}))
    seed_file = root / 'seed.key'
    seed_file.write_text(base64.b64encode(seed).decode() + '\n')
    other_file = root / 'other.key'
    other_file.write_text(base64.b64encode(bytes(reversed(seed))).decode() + '\n')
    old_format = root / 'old.key'
    old_format.write_text(base64.b64encode(bytes(64) + seed_public).decode())

    def key_gate(*args):
        return subprocess.run(['python3', str(root / 'scripts/sparkle-key.py'), '--plist', str(key_plist), *args],
                              env=env, capture_output=True, text=True)

    matched = key_gate('--key-file', str(seed_file))
    assert matched.returncode == 0 and matched.stdout.strip() == base64.b64encode(seed_public).decode(), matched.stderr
    assert key_gate('--key-file', str(old_format)).returncode == 0
    mismatched = key_gate('--key-file', str(other_file))
    assert mismatched.returncode == 1 and 'does not match SUPublicEDKey' in mismatched.stderr, mismatched.stderr
    assert key_gate('--key-file', str(root / 'missing.key')).returncode == 1
    seed_file.write_text(base64.b64encode(seed[:5]).decode())
    assert key_gate('--key-file', str(seed_file)).returncode == 1

    sparkle = root / 'sparkle'
    sparkle.mkdir()
    generated = root / 'GENERATE_APPCAST_RAN'
    for tool, body in [('generate_appcast', f'#!/bin/sh\ntouch "{generated}"\nexit 1\n'),
                       ('sign_update', '#!/bin/sh\nexit 1\n'),
                       ('generate_keys', f'#!/bin/sh\necho "{base64.b64encode(seed_public).decode()}"\n')]:
        (sparkle / tool).write_text(body)
        (sparkle / tool).chmod(0o755)
    (updates / 'WriteItDown-1.1.zip').write_bytes(b'payload')
    publish_env = {**env, 'WID_SPARKLE_BIN': str(sparkle)}

    def publish(public_key):
        plist_path.write_bytes(plistlib.dumps({**signed, 'SUPublicEDKey': public_key}))
        generated.unlink(missing_ok=True)
        return subprocess.run(['bash', str(root / 'scripts/publish-appcast.sh')],
                              env=publish_env, capture_output=True, text=True)

    refused = publish(base64.b64encode(bytes(32)).decode())
    assert refused.returncode == 1 and 'does not match SUPublicEDKey' in refused.stderr, refused.stderr
    assert not generated.exists(), 'generate_appcast ran before the signing key was proven'
    reaching_tools = publish(base64.b64encode(seed_public).decode())
    assert reaching_tools.returncode == 1 and generated.exists(), reaching_tools.stderr
print('PASS: release requires complete license and update configuration including the signed-feed')
print('      policy; a placeholder update key, an unsafe feed, an unchecksummed build number and')
print('      staging with sale config are refused; staging ignores last-build.txt; publish refuses')
print('      a signing key whose public half is not the bundled SUPublicEDKey before generating.')
