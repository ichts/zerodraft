"""Exercise the fixed-target installer in a worktree-local sandbox, not /var/www."""
from html.parser import HTMLParser
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

source = Path(__file__).resolve().parents[1]
files = {
    'download/index.html', 'index.html', 'mac.html', 'privacy.html',
    'terms.html', 'support.html', 'site.css', 'tokens.css',
    'reenie-beanie.woff2', 'OFL-ReenieBeanie.txt', 'theme.js', 'paper.js', 'demo.js',
    'demo-timeline.mjs', 'feedback.js', 'status-slot.js', 'session.mjs', 'room.js', 'buy.js',
    'what-is-write-it-down.html', 'write-it-down-mac-vs-web.html',
    'write-it-down-free-trial.html', 'write-it-down-price.html',
    'delete-a-draft.html', 'is-my-writing-saved.html',
    'og.png', 'robots.txt', 'sitemap.xml', 'llms.txt', 'BingSiteAuth.xml',
    'google7787e5a0693832e8.html', '1bcb6b66144003eb070fe87774217f86.txt',
    'logo/write-it-down-lockup.svg', 'logo/write-it-down-lockup-plate.svg', 'favicon.svg', 'favicon-16.png', 'favicon-32.png',
    'favicon-dark.svg', 'favicon-dark-16.png', 'favicon-dark-32.png', 'apple-touch-icon.png',
}


class LocalReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in {'src', 'href'} and value:
                url = urlsplit(value)
                if not url.scheme and not url.netloc and url.path:
                    self.references.append(unquote(url.path))


with tempfile.TemporaryDirectory(prefix='install-check-', dir=source) as temp:
    base = Path(temp)
    payload = base / 'payload'
    payload.mkdir()
    target = base / 'www' / 'writeitdown.app'
    target.mkdir(parents=True)
    for name in files:
        (payload / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, payload / name)
    script = (Path(sys.argv[1]) if len(sys.argv) > 1 else source / 'install.sh').read_text()
    script = script.replace('TARGET=/var/www/writeitdown.app', f'TARGET={target}')
    script = script.replace('[ "$(id -u)" -eq 0 ]', '[ "0" -eq 0 ]')
    script = script.replace('[ -d /var/www ]', f'[ -d {target.parent} ]')
    (payload / 'install.sh').write_text(script)
    (target / 'index.html').write_text('original')
    subprocess.run(['sh', str(payload / 'install.sh')], check=True)
    for attempt in range(2):
        if attempt:
            subprocess.run(['sh', str(payload / 'install.sh')], check=True)
        installed = {path.relative_to(target).as_posix()
                     for path in target.rglob('*') if path.is_file()}
        assert installed == files | {'index.html.dc-bak2'}, installed ^ files
        for name in files:
            output = target / name
            assert output.read_bytes() == (source / name).read_bytes(), name
            assert stat.S_IMODE(output.stat().st_mode) == 0o644, name
        assert (target / 'index.html.dc-bak2').read_text() == 'original'
        for name in ['index.html', 'download/index.html']:
            page = target / name
            parser = LocalReferences()
            parser.feed(page.read_text())
            for reference in parser.references:
                asset = ((target / reference.lstrip('/')) if reference.startswith('/')
                         else page.parent / reference).resolve()
                if asset.is_dir():
                    asset /= 'index.html'
                assert asset.is_relative_to(target), (name, reference)
                assert asset.relative_to(target).as_posix() in files, (name, reference)
    victim = base / 'untouched'
    victim.write_text('protected')
    (target / 'room.js').unlink()
    (target / 'room.js').symlink_to(victim)
    rejected = subprocess.run(['sh', str(payload / 'install.sh')], capture_output=True, text=True)
    assert rejected.returncode != 0
    assert 'Refusing symlink' in rejected.stderr
    assert victim.read_text() == 'protected'
    (target / 'room.js').unlink()
    shutil.rmtree(target / 'logo')
    victim_logo = base / 'untouched-logo'
    victim_logo.mkdir()
    (target / 'logo').symlink_to(victim_logo, target_is_directory=True)
    rejected = subprocess.run(['sh', str(payload / 'install.sh')], capture_output=True, text=True)
    assert rejected.returncode != 0
    assert 'symlink logo directory' in rejected.stderr
    assert not any(victim_logo.iterdir())
print(f'PASS: {len(files)} exact production files, preserved backup, repeat installation, rejected symlinks.')
