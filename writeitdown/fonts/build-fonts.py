#!/usr/bin/env python3
"""Build the webfonts writeitdown.app serves from its own files.

[INPUT] Two upstream font releases, pinned by SHA-256 (see SOURCES): Allo 1.0.3's variable woff2 (npm
        package `allo-font`, SIL OFL 1.1, no Reserved Font Name) and Resource Han Rounded CN Normal
        (GitHub CyanoHao/Resource-Han-Rounded release RHR-CN.7z, SIL OFL 1.1). Neither source is
        committed: pass their paths with --allo and --rhr.
[OUTPUT] writeitdown/fonts/allo-latin.woff2 and writeitdown/fonts/resource-han-rounded-gb2312.woff2,
        and the generated writeitdown/fonts.css (the face every page links) and
        writeitdown/fonts-cjk.css (the Chinese face, linked by index.html alone).
[POS]   The one font build step for the static site; the committed woff2 files are its product. The
        licence texts the files ship under are committed beside them as upstream wrote them:
        fonts/OFL-Allo.txt (allo-font 1.0.3's OFL.txt) and fonts/OFL-ResourceHanRounded.txt (the
        release's LICENSE.md: the fonts under SIL OFL 1.1, Reserved Font Name 'Source').
[PROTOCOL] Run `python3 fonts/build-fonts.py --allo PATH --rhr PATH` after a face changes (needs
        fonttools + brotli); commit the files and the generated CSS together. Never hand-edit
        fonts.css, fonts-cjk.css or a .woff2. `--list` prints the shipped files without sources.

The site serves every face itself: a third-party font host that fails must not decide what a page
renders (D-057). Allo is the one face of every role (D-119): what the writer writes, the headings and
everything the tool says. It is subset to the Latin ranges a writer types (Latin-1, Extended-A/B,
the Vietnamese block, combining marks, punctuation, currency, letterlike symbols, arrows) and pinned
at ROND 30, the roundness world A uses everywhere, with `wght` cut to 300-700 (the weights the site
sets: numeral 360, writing 410, headings 540, labels 400-600) and `opsz` kept. Chinese is Resource
Han Rounded, the rounded CJK face that pairs with Allo, subset to GB2312 as ONE file: the room takes
any character, so a sliced set only moves the bytes into the middle of a draft, where every late
slice repaints a character already on screen. The file is never requested on first paint: room.js
asks for it when Chinese input begins - an IME composition or a typed Chinese character (D-119), `font-display:swap` keeps text visible,
and room.js fixes the face at a draft's first Chinese character so a drawn character never changes
face (D-109).

The subset must keep the source's vertical metrics: the room's pitch is fixed in CSS, but where the
glyph sits inside that pitch comes from hhea/OS-2. A 1px shift would break the writing anchor.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SITE = Path(__file__).resolve().parents[1]
OUT = SITE / 'fonts'

SOURCES = {
    'allo': ('AlloVariable.woff2 from allo-font@1.0.3 (fonts/webfonts/)',
             '482bec1444dabaf1a493b34aa926bb7751ef5edc3e5a9f90a4111c7bb1e0c0ec'),
    'rhr': ('ResourceHanRoundedCN-Normal.ttf from Resource-Han-Rounded RHR-CN.7z',
            '33c26dd81ff65e9027a3628dc586fe59a2ed3c082c09e5b0836f1e1f389ee2f3'),
}

LATIN_RANGES = (
    'U+0000-024F,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-21FF,'
    'U+2212,U+2215,U+FEFF,U+FFFD'
)
ALLO_AXES = {'ROND': 30, 'wght': (300, 700)}

# GB2312's Chinese: 6763 hanzi and the CJK symbol rows, one file, with the CJK punctuation block and the
# full-width forms. The Latin, Greek and Cyrillic rows GB2312 also carries stay out: Allo draws Latin, and
# a Greek letter must never pull 1.2 MB of Chinese onto the page.
CJK_EXTRA_RANGES = 'U+3000-303F,U+FF01-FF60'


def gb2312_charset():
    """Every CJK character GB2312 can decode (codepoints from U+2E80 up)."""
    characters = []
    for row in range(0xA1, 0xFF):
        for cell in range(0xA1, 0xFF):
            try:
                character = bytes([row, cell]).decode('gb2312')
            except UnicodeDecodeError:
                continue
            if ord(character) >= 0x2E80:
                characters.append(character)
    return characters


def unicode_range(characters):
    """The shortest `unicode-range` covering these characters, as compressed codepoint runs."""
    runs, start, previous = [], None, None
    for codepoint in sorted(ord(character) for character in characters):
        if start is None:
            start = previous = codepoint
        elif codepoint == previous + 1:
            previous = codepoint
        else:
            runs.append((start, previous))
            start = previous = codepoint
    if start is not None:
        runs.append((start, previous))
    return ','.join(f'U+{first:04X}' if first == last else f'U+{first:04X}-{last:04X}' for first, last in runs)


def vertical_metrics(font):
    os2 = font['OS/2']
    return (font['head'].unitsPerEm, font['hhea'].ascent, font['hhea'].descent,
            os2.sTypoAscender, os2.sTypoDescender, os2.usWinAscent, os2.usWinDescent)


def pinned(name, path):
    label, expected = SOURCES[name]
    digest = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    if digest != expected:
        raise SystemExit(f'--{name}: expected {label} ({expected}), got {digest}')
    return Path(path)


def subset(source, destination, unicodes, flavor='woff2'):
    subprocess.run([sys.executable, '-m', 'fontTools.subset', str(source),
                    f'--output-file={destination}', f'--flavor={flavor}' if flavor else '--no-hinting',
                    '--layout-features=*', '--name-IDs=*', '--name-languages=*', '--notdef-outline',
                    f'--unicodes={unicodes}'], check=True)
    return destination


def check(destination, source, unicodes):
    """Refuse a subset that moved the em box or dropped a character it was asked to carry."""
    built, original = TTFont(destination), TTFont(source)
    if vertical_metrics(built) != vertical_metrics(original):
        raise SystemExit(f'{destination.name}: vertical metrics moved '
                         f'{vertical_metrics(original)} -> {vertical_metrics(built)}')
    covered = set(built.getBestCmap())
    missing = [f'U+{codepoint:04X}' for codepoint in sorted(original.getBestCmap())
               if codepoint not in covered and _in_ranges(codepoint, unicodes)]
    if missing:
        raise SystemExit(f'{destination.name}: subset dropped {missing[:8]}')
    return destination.stat().st_size


def _in_ranges(codepoint, ranges):
    for item in ranges.split(','):
        item = item.strip().removeprefix('U+')
        low, _, high = item.partition('-')
        if int(low, 16) <= codepoint <= int(high or low, 16):
            return True
    return False


def face(family, weight, file, ranges):
    return (f"@font-face{{font-family:'{family}';font-style:normal;font-weight:{weight};"
            f"font-display:swap;src:url(fonts/{file.name}) format('woff2');unicode-range:{ranges}}}\n")


def build_allo(source):
    """Subset first (the variable tables still name every glyph), then pin ROND and cut wght."""
    destination = OUT / 'allo-latin.woff2'
    with tempfile.TemporaryDirectory() as scratch:
        latin = subset(source, Path(scratch) / 'allo-latin.ttf', LATIN_RANGES, flavor=None)
        # The source's head.modified is kept, so the same inputs always build the same bytes.
        font = instancer.instantiateVariableFont(TTFont(latin, recalcTimestamp=False), ALLO_AXES)
        font.flavor = 'woff2'
        font.save(destination)
    return destination, check(destination, source, LATIN_RANGES)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--list', action='store_true', help='print the shipped font files and sizes')
    parser.add_argument('--allo', help=SOURCES['allo'][0])
    parser.add_argument('--rhr', help=SOURCES['rhr'][0])
    arguments = parser.parse_args()
    if arguments.list:
        for path in sorted(OUT.glob('*.woff2')):
            print(f'{path.stat().st_size:>9} B  fonts/{path.name}')
        return
    if not (arguments.allo and arguments.rhr):
        parser.error('a rebuild needs both --allo and --rhr (see SOURCES for the pinned files)')

    OUT.mkdir(exist_ok=True)
    allo, allo_size = build_allo(pinned('allo', arguments.allo))
    rhr_source = pinned('rhr', arguments.rhr)
    cjk_ranges = unicode_range(gb2312_charset()) + ',' + CJK_EXTRA_RANGES
    rhr = subset(rhr_source, OUT / 'resource-han-rounded-gb2312.woff2', cjk_ranges)
    rhr_size = check(rhr, rhr_source, cjk_ranges)

    (SITE / 'fonts.css').write_text(
        '/* GENERATED by fonts/build-fonts.py - do not hand-edit.\n'
        '   The face writeitdown.app serves from its own files (D-057, D-119): Allo, pinned at ROND 30, for\n'
        '   every role on every page. Every page links this sheet. Licence texts sit beside the files in\n'
        '   fonts/. Rebuild: python3 fonts/build-fonts.py --allo PATH --rhr PATH */\n'
        + face('Allo', '300 700', allo, LATIN_RANGES))
    (SITE / 'fonts-cjk.css').write_text(
        '/* GENERATED by fonts/build-fonts.py - do not hand-edit.\n'
        '   Resource Han Rounded, the Chinese face that pairs with Allo, GB2312-subset as one file and\n'
        '   linked by index.html alone, the only page that can render Chinese. Nothing asks for the file\n'
        '   on first paint: room.js requests it when Chinese input begins (D-119).\n'
        '   font-display:swap keeps text visible; room.js fixes the face at a draft\'s first Chinese\n'
        '   character and keeps it until the sheet is empty again, so a drawn character never changes\n'
        '   face (D-109). Rebuild: python3 fonts/build-fonts.py --allo PATH --rhr PATH */\n'
        + face('Resource Han Rounded', '400', rhr, cjk_ranges))

    for name, size in ((allo.name, allo_size), (rhr.name, rhr_size)):
        print(f'{size:>9} B  fonts/{name}')


if __name__ == '__main__':
    main()
