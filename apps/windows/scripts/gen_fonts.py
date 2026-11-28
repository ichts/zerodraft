#!/usr/bin/env python3
"""Derives the Windows writing faces from the Mac app's own Allo and Resource Han Rounded files (derived assets, never
edited by hand; D-125).

The Mac draws every writing role in Allo (ROND already pinned at 30 in the bundled file) at one weight per role, and
CoreText sets the optical size to the point size (the file's opsz axis runs 9 to 32). mygo picks a face by family and
DirectWrite by the font's own name table, so each role gets a fully static instance - weight and optical size pinned,
no fvar left - with its own family name, saved as TrueType because mygo does not read woff2:

  Allo-Text.ttf               Allo           wght 410, opsz 28   the draft and the kept draft (28 pt)
  Allo-Display.ttf            Allo Display   wght 540, opsz 32   the kept heading and the stopped headline (32-48 pt)
  Allo-Numeral.ttf            Allo Numeral   wght 360, opsz 32   the warning numeral (upright, tabular digits)
  ResourceHanRounded.ttf      as is                              the same roles in Chinese (GB2312 subset, the Mac's own file)

usage: gen_fonts.py [MAC_RESOURCES_DIR] [OUT_DIR]   (needs fonttools and brotli; CI pins them in .github/workflows/windows.yml)"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

here = os.path.dirname(os.path.abspath(__file__))
mac = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(here, '..', '..', 'macos', 'FirstLine', 'Sources', 'FirstLine', 'Resources'))
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'fonts')
FACES = [
    ('Allo-Text.ttf', 'Allo', {'wght': 410, 'opsz': 28}),
    ('Allo-Display.ttf', 'Allo Display', {'wght': 540, 'opsz': 32}),
    ('Allo-Numeral.ttf', 'Allo Numeral', {'wght': 360, 'opsz': 32}),
]
for dst, family, loc in FACES:
    font = TTFont(os.path.join(mac, 'allo-latin.woff2'), recalcTimestamp=False)
    inst = instancer.instantiateVariableFont(font, loc, inplace=False)
    assert 'fvar' not in inst, f'{dst} still has variation axes'
    name = inst['name']
    for nid in (16, 17, 25):
        name.removeNames(nameID=nid)
    for nid in (1, 2, 4, 6):
        name.removeNames(nameID=nid, platformID=1)
    name.setName(family, 1, 3, 1, 0x409); name.setName('Regular', 2, 3, 1, 0x409)
    name.setName(family, 4, 3, 1, 0x409); name.setName(family.replace(' ', '') + '-Regular', 6, 3, 1, 0x409)
    inst['OS/2'].usWeightClass = loc['wght']
    inst.flavor = None
    inst.save(os.path.join(out, dst))
    print('wrote', dst, family, loc)
cjk = TTFont(os.path.join(mac, 'resource-han-rounded-gb2312.woff2'), recalcTimestamp=False)
cjk.flavor = None
cjk.save(os.path.join(out, 'ResourceHanRounded.ttf'))
print('wrote ResourceHanRounded.ttf')
