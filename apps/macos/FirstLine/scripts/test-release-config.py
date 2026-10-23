"""Execute the release packager's configuration gate without building or signing."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

module = Path(__file__).resolve().parents[1]
config = plistlib.loads((module / 'Sources/FirstLine/Info.plist').read_bytes())
keys = ['WIDCheckoutURL', 'WIDLicenseServiceURL', 'WIDLicenseProductID', 'WIDLicensePublicKey']

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

    def run(values, *args):
        (root / 'Sources/FirstLine/Info.plist').write_bytes(plistlib.dumps(values))
        return subprocess.run(['bash', str(root / 'scripts/release-dmg.sh'), *args],
                              env=env, capture_output=True, text=True)

    accepted = run(config)
    assert accepted.returncode == 42 and 'CONFIGURATION_ACCEPTED' in accepted.stdout, accepted.stderr
    for missing in [keys, *[[key] for key in keys]]:
        values = {**config, **dict.fromkeys(missing, '')}
        rejected = run(values)
        assert rejected.returncode == 1 and 'Release blocked:' in rejected.stderr, rejected.stderr
        assert 'CONFIGURATION_ACCEPTED' not in rejected.stdout
    for key, value in [('WIDLicenseServiceURL', 'http://licenses.writeitdown.app'),
                       ('WIDLicensePublicKey', 'invalid'),
                       ('WIDCheckoutURL', 'https://localhost/mac.html')]:
        rejected = run({**config, key: value})
        assert rejected.returncode == 1 and 'Release blocked:' in rejected.stderr, rejected.stderr
    staging = run(config, '--staging')
    assert staging.returncode == 1 and 'Staging requires empty' in staging.stderr, staging.stderr
    staging = run({**config, **dict.fromkeys(keys, '')}, '--staging')
    assert staging.returncode == 42, staging.stderr
print('PASS: release requires complete safe configuration; staging cannot carry checkout credentials.')
