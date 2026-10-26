#!/usr/bin/env python3
"""Build the webfonts writeitdown.app serves from its own files.

[INPUT] The Mac app's bundled faces (apps/macos/FirstLine/Sources/FirstLine/Resources): Newsreader
        upright and italic variable, Zhuque Fangsong, and writeitdown/reenie-beanie.woff2.
[OUTPUT] writeitdown/fonts/*.woff2 plus the generated writeitdown/fonts.css (the faces every page
        links) and writeitdown/fonts-cjk.css (the Chinese slices, linked by index.html alone).
[POS]   The one font build step for the static site; the committed woff2 files are its product.
[PROTOCOL] Run `python3 fonts/build-fonts.py` after a face changes (needs fonttools + brotli); commit
        both the files and the generated CSS. Never hand-edit fonts.css, fonts-cjk.css or a .woff2.

The site serves every face itself: a third-party font host that fails must not decide what a page
renders (D-057). Latin is Newsreader subset to the Latin ranges the pages use, with its `wght` and
`opsz` axes intact, so the web writes in the same variable font the Mac bundles. Chinese is Zhuque
Fangsong, the Mac room's CJK face, subset to GB2312 and sliced by `unicode-range` so a visitor
downloads only the slices their text touches. The landing's hand accent is one face with one glyph
set and is declared here so every webfont face on the site has one owner.

The subset must keep the source's vertical metrics: the room's 1.6 pitch is fixed in CSS, but where
the glyph sits inside that pitch comes from hhea/OS-2. A 1px shift would break the writing anchor.
"""

import argparse
import math
import shutil
import subprocess
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

SITE = Path(__file__).resolve().parents[1]
MAC_RESOURCES = SITE.parent / 'apps' / 'macos' / 'FirstLine' / 'Sources' / 'FirstLine' / 'Resources'
OUT = SITE / 'fonts'

# The Latin ranges the pages use. This is the range Google served for the same face, so the rendered
# advance stays identical to the live site; anything outside it is punctuation the pages do not set.
LATIN_RANGES = (
    'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,'
    'U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD'
)

# GB2312 is the common simplified set: 6763 hanzi plus the symbol rows. Level 1 (rows 0xB0-0xD7) is
# its 3755 everyday characters, level 2 (0xD8 and up) the 3008 rarer ones, so slicing by level keeps
# a draft's first characters in the small half. Slice counts trade one request's size against the
# number of files: at 8 + 4, a slice is 165-350 KB and the symbol slice 47 KB.
SYMBOL_SLICES = 1
LEVEL1_SLICES = 8
LEVEL2_SLICES = 4
# Full-width punctuation and the CJK punctuation block travel with the symbol slice, not the hanzi.
CJK_EXTRA_RANGES = 'U+00B7,U+2018-201D,U+2014,U+2026,U+3000-303F,U+FF01-FF60'

CATALOG = {
    'newsreader-latin': ('Newsreader-Variable.ttf', 'normal', 'Newsreader', LATIN_RANGES),
    'newsreader-latin-italic': ('Newsreader-Italic-Variable.ttf', 'italic', 'Newsreader', LATIN_RANGES),
}


def gb2312_charset():
    """Every character GB2312 can decode: 682 symbols and 6763 hanzi, with their row byte."""
    symbols, level1, level2 = [], [], []
    for row in range(0xA1, 0xFF):
        for cell in range(0xA1, 0xFF):
            try:
                character = bytes([row, cell]).decode('gb2312')
            except UnicodeDecodeError:
                continue
            if not 0x4E00 <= ord(character) <= 0x9FFF:
                symbols.append(character)
            elif row <= 0xD7:
                level1.append(character)
            else:
                level2.append(character)
    return symbols, level1, level2


def chunked(characters, count):
    if count == 1:
        return [characters]
    per = math.ceil(len(characters) / count)
    return [characters[start:start + per] for start in range(0, len(characters), per)]


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


def subset(source, destination, unicodes):
    subprocess.run([sys.executable, '-m', 'fontTools.subset', str(source),
                    f'--output-file={destination}', '--flavor=woff2',
                    '--layout-features=*', '--name-IDs=*', '--name-languages=*',
                    f'--unicodes={unicodes}'], check=True)
    return destination


def check(destination, source, unicodes):
    """Refuse a subset that moved the em box or dropped a character it was asked to carry."""
    built, original = TTFont(destination), TTFont(source)
    if vertical_metrics(built) != vertical_metrics(original):
        raise SystemExit(f'{destination.name}: vertical metrics moved '
                         f'{vertical_metrics(original)} -> {vertical_metrics(built)}')
    wanted = set(TTFont(str(source), lazy=True).getBestCmap())
    covered = set(built.getBestCmap())
    missing = [f'U+{codepoint:04X}' for codepoint in sorted(wanted) if codepoint not in covered
               and _in_ranges(codepoint, unicodes)]
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


def faces(family, style, weight, file, ranges):
    return (f"@font-face{{font-family:'{family}';font-style:{style};font-weight:{weight};"
            f"font-display:swap;src:url(fonts/{file.name}) format('woff2');unicode-range:{ranges}}}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--list', action='store_true', help='print the shipped font files and sizes')
    arguments = parser.parse_args()
    if arguments.list:
        for path in sorted(OUT.glob('*.woff2')):
            print(f'{path.stat().st_size:>9} B  fonts/{path.name}')
        return

    OUT.mkdir(exist_ok=True)
    base, cjk, report = [], [], []

    # The hand accent is one static face, already subset and committed; it only needs its declaration,
    # which keeps every webfont face on the site in one generated place.
    hand = OUT / 'reenie-beanie.woff2'
    if not hand.exists():
        raise SystemExit(f'missing {hand.name}: the landing hand accent is a committed woff2')
    base.append(f"@font-face{{font-family:'Reenie Beanie';font-style:normal;font-weight:400;"
                f"font-display:swap;src:url(fonts/reenie-beanie.woff2) format('woff2')}}\n")
    report.append((hand.name, hand.stat().st_size))

    for slug, (source_name, style, family, ranges) in CATALOG.items():
        destination = OUT / f'{slug}.woff2'
        subset(MAC_RESOURCES / source_name, destination, ranges)
        report.append((destination.name, check(destination, MAC_RESOURCES / source_name, ranges)))
        # Both Newsreader files are variable on `wght` 200-800 and `opsz` 6-72; declaring the range is
        # what lets one file serve the 400 writing text, the 500 headings and the italic numeral.
        base.append(faces(family, style, '200 800', destination, ranges))

    symbols, level1, level2 = gb2312_charset()
    slices = (chunked(symbols, SYMBOL_SLICES) + chunked(level1, LEVEL1_SLICES)
              + chunked(level2, LEVEL2_SLICES))
    for index, characters in enumerate(slices, start=1):
        ranges = unicode_range(characters) + (',' + CJK_EXTRA_RANGES if index == 1 else '')
        destination = OUT / f'zhuque-fangsong-{index:02d}.woff2'
        subset(MAC_RESOURCES / 'ZhuqueFangsong-Regular.ttf', destination, ranges)
        report.append((destination.name, check(destination, MAC_RESOURCES / 'ZhuqueFangsong-Regular.ttf', ranges)))
        cjk.append(faces('Zhuque Fangsong', 'normal', '400', destination, ranges))

    for licence in ('OFL-Newsreader.txt', 'OFL-ZhuqueFangsong.txt'):
        shutil.copyfile(MAC_RESOURCES / licence, OUT / licence)

    (SITE / 'fonts.css').write_text(
        '/* GENERATED by fonts/build-fonts.py - do not hand-edit.\n'
        '   The faces writeitdown.app serves from its own files (D-057): Newsreader for what the writer writes\n'
        '   and for headings, Reenie Beanie for the landing\'s hand accent only. Every page links this sheet.\n'
        '   Licence texts sit beside the files in fonts/. Rebuild: python3 fonts/build-fonts.py */\n'
        + ''.join(base))
    (SITE / 'fonts-cjk.css').write_text(
        '/* GENERATED by fonts/build-fonts.py - do not hand-edit.\n'
        '   Zhuque Fangsong, the Mac room\'s Chinese face, GB2312-subset and sliced by unicode-range so a\n'
        '   draft downloads only the slices it touches. Linked by index.html alone, the only page that can\n'
        '   render Chinese. Rebuild: python3 fonts/build-fonts.py */\n'
        + ''.join(cjk))

    total = sum(size for _, size in report)
    for name, size in report:
        print(f'{size:>9} B  fonts/{name}')
    print(f'{total:>9} B  {len(report)} files, {len(slices)} of them Zhuque Fangsong slices')


if __name__ == '__main__':
    main()
