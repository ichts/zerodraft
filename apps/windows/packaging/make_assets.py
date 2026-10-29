#!/usr/bin/env python3
"""Generates the MSIX visual assets (every scale and target size a Store listing and the shell ask for) from icon.png,
the W tile. Wide and large tiles carry the tile centred on a transparent field, so the shell's own plate shows."""
from PIL import Image
import os
src = Image.open(os.path.join(os.path.dirname(__file__), 'icon.png')).convert('RGBA')
out = os.path.join(os.path.dirname(__file__), 'assets')
os.makedirs(out, exist_ok=True)
def tile(w, h, pad=0.0):
    """The W tile scaled to fit (w, h) with `pad` of the short side as margin, centred on a transparent canvas."""
    side = int(min(w, h) * (1 - pad))
    t = src.resize((side, side), Image.LANCZOS)
    c = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    c.paste(t, ((w - side) // 2, (h - side) // 2), t)
    return c
SCALES = {100: 1.0, 125: 1.25, 150: 1.5, 200: 2.0, 400: 4.0}
def scaled(name, w, h, pad=0.0):
    # makeappx wants the plain file the manifest names; the shell uses it when no resources.pri qualifies scales.
    # A Store build runs makepri over the scale-qualified set.
    tile(w, h, pad).save(os.path.join(out, f'{name}.png'))
    if os.environ.get('WID_SCALES'):
        for s, f in SCALES.items():
            tile(round(w * f), round(h * f), pad).save(os.path.join(out, f'{name}.scale-{s}.png'))
scaled('Square44x44Logo', 44, 44)
scaled('Square71x71Logo', 71, 71)
scaled('Square150x150Logo', 150, 150)
scaled('Square310x310Logo', 310, 310)
scaled('Wide310x150Logo', 310, 150, 0.08)
scaled('StoreLogo', 50, 50)
for n in (16, 24, 32, 48, 256):
    tile(n, n).save(os.path.join(out, f'Square44x44Logo.targetsize-{n}.png'))
    tile(n, n).save(os.path.join(out, f'Square44x44Logo.targetsize-{n}_altform-unplated.png'))
    tile(n, n).save(os.path.join(out, f'Square44x44Logo.targetsize-{n}_altform-lightunplated.png'))
print(len(os.listdir(out)), 'assets')
