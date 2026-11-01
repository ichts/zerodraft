#!/usr/bin/env python3
"""Side-by-side measurement of one Mac state against its Windows twin, from pixels, in DIPs: the same detector runs on both
images, so a difference is a difference in the rendering and not in how it was read. It lists the text/ink rows and the
white or ink pills of each (top, bottom, left, right) and prints one PASS/FAIL line per matched feature.

  usage: compare_mac.py MAC.png WIN.png [--scale S] [--region paper|card] [--tol T] [--chrome]
  MAC.png   the Mac's content snapshot (SnapshotTests, WID_SNAPSHOT_DIR): 1040 x 720 at 1x, window content only
  WIN.png   a Windows window crop (drv shotwin, any scale S: 1.0, 1.25, 1.5) or a headless tester frame (S = 1)
  --region  paper: the Wheat sheet 32 DIP in from the window (the room); card: the white card centred on the page
  --tol     allowed difference in DIPs for a vertical or horizontal position (default 2.5)
  --drop-win-rows N  ignore the last N rows of the Windows image (rows the Mac does not have)
  --chrome  also compare rows made of system-sans chrome (the Mac's SF against Segoe UI Variable): positions only, text widths differ

Needs numpy and Pillow. Exit 1 on any FAIL. It reads ink as luminance below 130 with at least two dark pixels on a row,
which ignores the paper's flecks and keeps the 13 pt quiet text (about 70) and the ladder's lightest readable step."""
import sys
import numpy as np
from PIL import Image

PAGE = (247, 247, 245)


def args():
    a = sys.argv[1:]
    opt = {'scale': 1.0, 'region': 'paper', 'tol': 2.5, 'chrome': False, 'drop': 0}
    pos = []
    i = 0
    while i < len(a):
        if a[i] == '--scale': opt['scale'] = float(a[i + 1]); i += 2
        elif a[i] == '--region': opt['region'] = a[i + 1]; i += 2
        elif a[i] == '--tol': opt['tol'] = float(a[i + 1]); i += 2
        elif a[i] == '--chrome': opt['chrome'] = True; i += 1
        elif a[i] == '--drop-win-rows': opt['drop'] = int(a[i + 1]); i += 2   # Windows rows with no Mac twin (the picker's Settings link)
        else: pos.append(a[i]); i += 1
    return pos[0], pos[1], opt


def load(p): return np.asarray(Image.open(p).convert('RGB')).astype(int)


def client(im):
    """The window's client area. A Windows crop includes its title bar and frame, a Mac snapshot and a headless frame are the
    client alone. The page colour fills the top margin and the outer columns (the sheet's shadow falls down and inward, so the
    bottom margin is not page colour): the origin is the first dense row and column, the width the last dense column, and the
    height runs to the bottom of the image (a crop ends at the window's bottom edge)."""
    m = np.abs(im - np.array(PAGE)).sum(axis=2) <= 6
    rowd, cold = m.sum(axis=1), m.sum(axis=0)
    y = np.where(rowd > im.shape[1] * 0.3)[0]
    x = np.where(m[y.min() + 3])[0]
    return x.min(), y.min(), x.max() + 1, im.shape[0]


def lum(im): return im @ np.array([0.299, 0.587, 0.114])


def white_rect(im, box):
    """The biggest pure-white blob inside box (the card): (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    w = (im[y0:y1, x0:x1].min(axis=2) >= 253)
    rows = np.where(w.mean(axis=1) > 0.25)[0]
    cols = np.where(w.mean(axis=0) > 0.25)[0]
    return x0 + cols.min(), y0 + rows.min(), x0 + cols.max() + 1, y0 + rows.max() + 1


def clusters(mask_rows, gap):
    out, st, last = [], None, None
    for y, v in enumerate(mask_rows):
        if v:
            if st is None: st = y
            last = y
        elif st is not None and y - last > gap:
            out.append((st, last + 1)); st = None
    if st is not None: out.append((st, last + 1))
    return out


def features(im, scale, region):
    cx0, cy0, cx1, cy1 = client(im)
    if region == 'paper':
        m = int(round(32 * scale)) + 2
        box = (cx0 + m, cy0 + m, cx1 - m, cy1 - m)
    else:
        box = white_rect(im, (cx0, cy0, cx1, cy1))
        cardrect = box
        pad = int(round(4 * scale))
        box = (box[0] + pad, box[1] + pad, box[2] - pad, box[3] - pad)
    x0, y0, x1, y1 = box
    sub = im[y0:y1, x0:x1]
    dark = lum(sub) < 130
    rowhas = dark.sum(axis=1) >= 2
    rows = []
    for a, b in clusters(rowhas, max(1, int(round(4 * scale)))):
        if b - a < 4 * scale: continue   # a fleck of the paper, not text
        cols = np.where(dark[a:b].sum(axis=0) >= 2)[0]   # two dark pixels in a column: the paper's flecks are single
        if len(cols) == 0: continue
        rows.append({'y0': (y0 + a - cy0) / scale, 'y1': (y0 + b - cy0) / scale,
                     'x0': (x0 + cols.min() - cx0) / scale, 'x1': (x0 + cols.max() + 1 - cx0) / scale})
    # white pills on the paper (the outlined secondary): a pure-white run at least 40 wide and 40 tall
    pills = []
    if region == 'paper':
        wm = sub.min(axis=2) >= 253
        colsw = wm.sum(axis=0) >= int(30 * scale)
        if colsw.any():
            for a, b in clusters(colsw, 2):
                rr = np.where(wm[:, a:b].sum(axis=1) >= (b - a) * 0.5)[0]
                if len(rr) >= 36 * scale and (b - a) >= 40 * scale:
                    pills.append({'y0': (y0 + rr.min() - cy0) / scale, 'y1': (y0 + rr.max() + 1 - cy0) / scale,
                                  'x0': (x0 + a - cx0) / scale, 'x1': (x0 + b - cx0) / scale})
    out = {'client': ((cx1 - cx0) / scale, (cy1 - cy0) / scale), 'rows': rows, 'pills': pills,
           'box': ((x1 - x0) / scale, (y1 - y0) / scale)}
    if region == 'card':
        # a card is centred in the window, so its content is compared from the card's own top edge, and the card's size is
        # a feature of its own
        out['card'] = ((cardrect[2] - cardrect[0]) / scale, (cardrect[3] - cardrect[1]) / scale)
        top = (cardrect[1] - cy0) / scale
        for f in rows + pills:
            f['y0'] -= top; f['y1'] -= top
    return out


def main():
    mac_p, win_p, o = args()
    mac, win = features(load(mac_p), 1.0, o['region']), features(load(win_p), o['scale'], o['region'])
    fails = 0
    if o['drop']: win['rows'] = win['rows'][:-o['drop']]

    def check(name, ok, detail):
        nonlocal fails
        fails += (not ok)
        print(('PASS' if ok else 'FAIL'), name, '-', detail)

    print(f"client  mac {mac['client'][0]:.0f}x{mac['client'][1]:.0f}   win {win['client'][0]:.0f}x{win['client'][1]:.0f} DIP")
    # a real Windows crop ends in the window's invisible resize frame, so only the width must match exactly; the height is
    # the page area plus that frame (8 DIP at 100 percent, scaled)
    check('window width', abs(mac['client'][0] - win['client'][0]) <= 1, 'the two surfaces are measured at the same width')
    if 'card' in mac:
        check('card width', abs(mac['card'][0] - win['card'][0]) <= 1, f"{mac['card'][0]:.1f} -> {win['card'][0]:.1f}")
        check('card height', abs(mac['card'][1] - win['card'][1]) <= o['tol'], f"{mac['card'][1]:.1f} -> {win['card'][1]:.1f} (rows are measured from the card's top edge)")
    for kind in ('rows', 'pills'):
        a, b = mac[kind], win[kind]
        if len(a) != len(b):
            check(f'{kind} count', False, f"mac {len(a)} vs win {len(b)}")
            for tag, lst in (('mac', a), ('win', b)):
                for f in lst: print(f"   {tag} {kind[:-1]} y {f['y0']:.1f}-{f['y1']:.1f}  x {f['x0']:.1f}-{f['x1']:.1f}")
            continue
        for i, (m, w) in enumerate(zip(a, b)):
            d = {k: w[k] - m[k] for k in m}
            dim = f"h {w['y1'] - w['y0']:.1f}/{m['y1'] - m['y0']:.1f}"
            ok = abs(d['y0']) <= o['tol'] and abs(d['y1']) <= o['tol']
            text_row = kind == 'rows'
            wid = abs((w['x0'] + w['x1']) / 2 - (m['x0'] + m['x1']) / 2) <= o['tol'] or not text_row
            wide = abs((w['x1'] - w['x0']) - (m['x1'] - m['x0'])) <= o['tol'] * 2
            check(f"{kind[:-1]} {i} vertical", ok, f"top {m['y0']:.1f}->{w['y0']:.1f} ({d['y0']:+.1f}) bottom {m['y1']:.1f}->{w['y1']:.1f} ({d['y1']:+.1f}) {dim}")
            check(f"{kind[:-1]} {i} centred x", wid, f"centre {(m['x0'] + m['x1']) / 2:.1f}->{(w['x0'] + w['x1']) / 2:.1f}")
            if o['chrome'] and text_row:
                check(f"{kind[:-1]} {i} width", wide, f"{m['x1'] - m['x0']:.1f}->{w['x1'] - w['x0']:.1f}")
            elif not text_row:
                # a pill hugs its label, and the label is SF on the Mac and Segoe UI Variable here (SYNC.md row 22): the width is a note
                print(f"NOTE {kind[:-1]} {i} width (system face) - {m['x1'] - m['x0']:.1f} -> {w['x1'] - w['x0']:.1f}, centre {(m['x0'] + m['x1']) / 2:.1f} -> {(w['x0'] + w['x1']) / 2:.1f}")
    sys.exit(1 if fails else 0)


main()
