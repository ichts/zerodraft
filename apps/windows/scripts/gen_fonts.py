#!/usr/bin/env python3
"""Derives the Windows writing faces from the Mac app's own variable Newsreader files (a derived asset, never edited by hand).

The Mac sets the font's optical size axis to the point size on every run it draws (CoreText applies `opsz` automatically), so
its 28 pt draft is the opsz 28 cut and its 48 pt heading the opsz 48 cut. mygo's text on Windows keeps the font's default
opsz (18) whatever the size, which made the Windows heading 6 percent narrower and its strokes finer than the Mac's (measured
side by side in scripts/compare_mac.py: heading 372 against 395 DIP wide). The room's roles have one size each, so each
role gets a static instance with the Mac's own axis values pinned:

  Newsreader-Text.ttf       wght 400, opsz 28   the draft, the kept draft (writing size 28 pt, the Mac default)
  Newsreader-Display.ttf    wght 500, opsz 48   the kept heading and the stopped headline (their base size, clamp 32..48)
  Newsreader-Numeral.ttf    italic 400, opsz 72 the warning numeral (min(18 percent of the window, 170) pt, past the axis top)

usage: gen_fonts.py [MAC_RESOURCES_DIR] [OUT_DIR]   (needs fonttools; CI pins the version in .github/workflows/windows.yml)"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

here = os.path.dirname(os.path.abspath(__file__))
mac = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(here, '..', '..', 'macos', 'FirstLine', 'Sources', 'FirstLine', 'Resources'))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'fonts')
FACES = [
    ('Newsreader-Variable.ttf', 'Newsreader-Text.ttf', {'wght': 400, 'opsz': 28}),
    ('Newsreader-Variable.ttf', 'Newsreader-Display.ttf', {'wght': 500, 'opsz': 48}),
    ('Newsreader-Italic-Variable.ttf', 'Newsreader-Numeral.ttf', {'wght': 400, 'opsz': 72}),
]
for src, dst, loc in FACES:
    font = TTFont(os.path.join(mac, src), recalcTimestamp=False)
    inst = instancer.instantiateVariableFont(font, loc, inplace=False)
    inst.save(os.path.join(out, dst))
    print('wrote', dst, loc)
