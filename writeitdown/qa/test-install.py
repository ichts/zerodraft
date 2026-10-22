"""Exercise the fixed-target installer in a worktree-local sandbox, not /var/www."""
from pathlib import Path
import shutil
import subprocess
import os
import re
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='install-check-') as temp:
    base = Path(temp)
    payload = base / 'payload'
    payload.mkdir()
    target = base / 'www' / 'writeitdown.app'
    target.mkdir(parents=True)
    files = re.search(r"^FILES='([^']*)'", (source / 'install.sh').read_text(), re.M).group(1).split()
    assert 'mac.html' in files and 'index.html' in files
    assert 'download/index.html' in files
    for name in files:
        (payload / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, payload / name)
    script = (source / 'install.sh').read_text()
    script = script.replace('TARGET=/var/www/writeitdown.app', f'TARGET={target}')
    script = script.replace('[ "$(id -u)" -eq 0 ]', '[ "0" -eq 0 ]')
    script = script.replace('[ -d /var/www ]', f'[ -d {target.parent} ]')
    (payload / 'install.sh').write_text(script)
    (target / 'index.html').write_text('original')
    health = base / 'health'
    env = {**os.environ, 'WAITLIST_HEALTH_URL': health.as_uri()}
    down = subprocess.run(['sh', str(payload / 'install.sh')], capture_output=True, text=True, env=env)
    assert down.returncode != 0 and 'waitlist collector' in down.stderr, down.stderr
    assert not (target / 'mac.html').exists() and (target / 'index.html').read_text() == 'original'
    health.write_text('ok\n')
    subprocess.run(['sh', str(payload / 'install.sh')], check=True, env=env)
    for name in files:
        assert (target / name).read_bytes() == (source / name).read_bytes(), name
    assert (target / 'index.html.dc-bak2').read_text() == 'original'
    subprocess.run(['sh', str(payload / 'install.sh')], check=True, env=env)
    assert (target / 'index.html.dc-bak2').read_text() == 'original'
    victim = base / 'untouched'
    victim.write_text('protected')
    (target / 'room.js').unlink()
    (target / 'room.js').symlink_to(victim)
    rejected = subprocess.run(['sh', str(payload / 'install.sh')], capture_output=True, text=True, env=env)
    assert rejected.returncode != 0
    assert 'Refusing symlink' in rejected.stderr
    assert victim.read_text() == 'protected'
print(f'PASS: refused while the waitlist collector is down; {len(files)} exact production files, preserved backup, repeat installation, rejected symlink.')
