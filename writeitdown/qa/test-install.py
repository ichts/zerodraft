"""Exercise the fixed-target installer in a worktree-local sandbox, not /var/www."""
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='install-check-', dir=source.parent / 'data') as temp:
    base = Path(temp)
    payload = base / 'payload'
    payload.mkdir()
    target = base / 'www' / 'writeitdown.app'
    target.mkdir(parents=True)
    files = ['index.html', 'site.css', 'theme.js', 'demo.js', 'feedback.js', 'session.mjs', 'room.js', 'privacy.html', 'terms.html', 'support.html']
    for name in files:
        shutil.copyfile(source / name, payload / name)
    script = (source / 'install.sh').read_text()
    script = script.replace('TARGET=/var/www/writeitdown.app', f'TARGET={target}')
    script = script.replace('[ "$(id -u)" -eq 0 ]', '[ "0" -eq 0 ]')
    script = script.replace('[ -d /var/www ]', f'[ -d {target.parent} ]')
    (payload / 'install.sh').write_text(script)
    (target / 'index.html').write_text('original')
    subprocess.run(['sh', str(payload / 'install.sh')], check=True)
    for name in files:
        assert (target / name).read_bytes() == (source / name).read_bytes(), name
    assert (target / 'index.html.dc-bak2').read_text() == 'original'
    subprocess.run(['sh', str(payload / 'install.sh')], check=True)
    assert (target / 'index.html.dc-bak2').read_text() == 'original'
    victim = base / 'untouched'
    victim.write_text('protected')
    (target / 'room.js').unlink()
    (target / 'room.js').symlink_to(victim)
    rejected = subprocess.run(['sh', str(payload / 'install.sh')], capture_output=True, text=True)
    assert rejected.returncode != 0
    assert 'Refusing symlink' in rejected.stderr
    assert victim.read_text() == 'protected'
print('PASS: ten exact production files, preserved backup, repeat installation, rejected symlink.')
