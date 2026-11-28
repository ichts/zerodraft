#!/usr/bin/env python3
"""Derives the Windows writing faces from the Mac app's own Allo and Resource Han Rounded files (derived assets, never
edited by hand; D-125).

The Mac draws every writing role in Allo (ROND already pinned at 30 in the bundled file) at one weight per role. mygo
picks a face by family, so each role gets a static instance with the Mac's weight pinned, saved as TrueType because
mygo does not read woff2:

  Allo-Text.ttf               wght 410   the draft and the kept draft
  Allo-Display.ttf            wght 540   the kept heading and the stopped headline
  Allo-Numeral.ttf            wght 360   the warning numeral (upright, tabular digits)
  ResourceHanRounded.ttf      as is      the same roles in Chinese (GB2312 subset, the Mac's own file)

usage: gen_fonts.py [MAC_RESOURCES_DIR] [OUT_DIR]   (needs fonttools and brotli; CI pins them in .github/workflows/windows.yml)"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

here = os.path.dirname(os.path.abspath(__file__))
mac = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(here, '..', '..', 'macos', 'FirstLine', 'Sources', 'FirstLine', 'Resources'))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'fonts')
FACES = [
    ('Allo-Text.ttf', {'wght': 410}),
    ('Allo-Display.ttf', {'wght': 540}),
    ('Allo-Numeral.ttf', {'wght': 360}),
]
for dst, loc in FACES:
    font = TTFont(os.path.join(mac, 'allo-latin.woff2'), recalcTimestamp=False)
    inst = instancer.instantiateVariableFont(font, loc, inplace=False)
    inst.flavor = None
    inst.save(os.path.join(out, dst))
    print('wrote', dst, loc)
cjk = TTFont(os.path.join(mac, 'resource-han-rounded-gb2312.woff2'), recalcTimestamp=False)
cjk.flavor = None
cjk.save(os.path.join(out, 'ResourceHanRounded.ttf'))
print('wrote ResourceHanRounded.ttf')
