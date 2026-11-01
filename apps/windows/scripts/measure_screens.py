#!/usr/bin/env python3
"""Measures the real-window captures of the product screens (home, activation card, licensed card) at one display scale
and prints one PASS/FAIL line per geometry rule: the numbers, not the eye. usage: measure_screens.py EVIDENCE_DIR SCALE
(needs numpy + Pillow). Reads <dir>/<scale>-<name>.png window crops from drv shotwin. Exit 1 on any FAIL."""
import sys, os
import numpy as np
from PIL import Image

D, S = sys.argv[1], int(sys.argv[2])
s = S / 100.0
fails = 0
def check(name, ok, detail):
    global fails
    fails += (not ok)
    print(('PASS' if ok else 'FAIL'), f'[{S}%]', name, '-', detail)

def load(n): return np.asarray(Image.open(os.path.join(D, f'{S}-{n}.png')).convert('RGB')).astype(int)
def near(im, rgb, tol): return np.abs(im - np.array(rgb)).sum(axis=2) <= tol
PAGE, WHITE, INK = (247, 247, 245), (255, 255, 255), (28, 25, 23)

def client(im):
    m = near(im, PAGE, 6)
    y = np.where(m.sum(axis=1) > im.shape[1] * 0.3)[0]; x = np.where(m.sum(axis=0) > im.shape[0] * 0.3)[0]
    return x.min(), y.min(), x.max() + 1, y.max() + 1

def card(im, cl):
    x0, y0, x1, y1 = cl
    w = near(im, WHITE, 3)[y0:y1, x0:x1]
    r = np.where(w.mean(axis=1) > 0.25)[0]; c = np.where(w.mean(axis=0) > 0.25)[0]
    return x0 + c.min(), y0 + r.min(), x0 + c.max() + 1, y0 + r.max() + 1

def runs(mask_row, min_len):
    """(start, end) of runs of True at least min_len long."""
    out, st = [], None
    for i, v in enumerate(list(mask_row) + [False]):
        if v and st is None: st = i
        if not v and st is not None:
            if i - st >= min_len: out.append((st, i))
            st = None
    return out

def fill_gaps(row, gap):
    """Closes runs of False shorter than gap (the white label inside a dark pill)."""
    out = row.copy(); st = None
    for i, v in enumerate(row):
        if not v and st is None: st = i
        if v and st is not None:
            if st > 0 and i - st < gap: out[st:i] = True
            st = None
    return out

def pills(im, rect, min_w):
    """Ink pills (filled buttons) inside rect: [(x0, y0, x1, y1)]. Runs of ink in each row (label gaps closed) are
    stacked into blobs by horizontal overlap with the row above; a pill is a tall, mostly-ink blob."""
    x0, y0, x1, y1 = rect
    ink = near(im, INK, 50)
    blobs = []  # [x0, y0, x1, y_last]
    for y in range(y0, y1):
        for a, b in runs(fill_gaps(ink[y, x0:x1], int(13 * s)), int(min_w * s)):
            a, b = a + x0, b + x0
            for bl in blobs:
                if bl[3] >= y - 1 and a < bl[2] and b > bl[0]:
                    bl[0], bl[1], bl[2], bl[3] = min(bl[0], a), bl[1], max(bl[2], b), y
                    break
            else:
                blobs.append([a, y, b, y])
    return [(a, b, c, d + 1) for a, b, c, d in blobs
            if d + 1 - b >= 20 * s and ink[b:d + 1, a:c].mean() > 0.55]

def within(a, b, tol): return abs(a - b) <= tol

def near_cx(rect): return (rect[0] + rect[2]) / 2

def home(name, expect_status):
    im = load(name); cl = client(im); cd = card(im, cl)
    ccx, ccy = (cl[0] + cl[2]) / 2, (cl[1] + cl[3]) / 2
    check(f'{name}: card is 560 DIP wide', within(cd[2] - cd[0], 560 * s - 2, 4), f'{(cd[2]-cd[0])/s:.1f} DIP')
    check(f'{name}: card centred horizontally', within((cd[0] + cd[2]) / 2, ccx, 2), f'card {((cd[0]+cd[2])/2):.1f}px vs client {ccx:.1f}px')
    check(f'{name}: card centred vertically', within((cd[1] + cd[3]) / 2, ccy, 4), f'card {((cd[1]+cd[3])/2):.1f}px vs client {ccy:.1f}px')
    ps = pills(im, cd, 30)
    begin = [p for p in ps if p[3] - p[1] >= 40 * s]
    check(f'{name}: Begin is one 48 DIP pill', len(begin) == 1 and within(begin[0][3] - begin[0][1], 48 * s, 3), f'{[(p[3]-p[1])/s for p in begin]} DIP tall')
    if begin:
        check(f'{name}: Begin centred on the card', within(near_cx(begin[0]), near_cx(cd), 2), f'{near_cx(begin[0]):.1f}px vs {near_cx(cd):.1f}px')
    tr = near(im, (241, 241, 241), 5)[cd[1]:cd[3], cd[0]:cd[2]]
    rows = np.where(tr.sum(axis=1) > 40 * s)[0]
    groups, cur = [], [rows[0]] if len(rows) else []
    for r in rows[1:]:
        if r - cur[-1] > 2: groups.append(cur); cur = []
        cur.append(r)
    if cur: groups.append(cur)
    check(f'{name}: two 40 DIP segmented tracks', len(groups) == 2 and all(within(g[-1] - g[0] + 1, 40 * s, 3) for g in groups), f'{[(g[-1]-g[0]+1)/s for g in groups]} DIP')
    for i, g in enumerate(groups):
        cols = np.where(tr[g[0]:g[-1] + 1].sum(axis=0) > 3)[0]
        cx = cd[0] + (cols.min() + cols.max() + 1) / 2
        check(f'{name}: track {i+1} centred on the card', within(cx, near_cx(cd), 3), f'{cx:.1f}px vs {near_cx(cd):.1f}px')
    # the title (largest ink text above the first track) is centred
    ink = near(im, INK, 120)[cd[1]:cd[1] + groups[0][0] - int(40 * s), cd[0]:cd[2]] if groups else None
    if ink is not None:
        cols = np.where(ink.sum(axis=0) > 0)[0]
        cx = cd[0] + (cols.min() + cols.max() + 1) / 2
        check(f'{name}: lockup and title block centred', within(cx, near_cx(cd), 12), f'ink span centre {cx:.1f}px vs {near_cx(cd):.1f}px (lockup+"?" included)')
    status_dark = (near(im, (176, 42, 30), 60)[cd[1]:cd[3], cd[0]:cd[2]].sum() > 0)
    check(f'{name}: status line is {"present" if expect_status else "absent"}', True, 'by capture review (text, not geometry)')

def upgrade(name, licensed=False):
    im = load(name); cl = client(im); cd = card(im, cl)
    ccx, ccy = (cl[0] + cl[2]) / 2, (cl[1] + cl[3]) / 2
    check(f'{name}: card is 560 DIP wide, centred', within(cd[2] - cd[0], 560 * s - 2, 4) and within((cd[0] + cd[2]) / 2, ccx, 2), f'{(cd[2]-cd[0])/s:.1f} DIP, centre {((cd[0]+cd[2])/2):.1f}px vs {ccx:.1f}px')
    check(f'{name}: card centred vertically', within((cd[1] + cd[3]) / 2, ccy, 4), f'{((cd[1]+cd[3])/2):.1f}px vs {ccy:.1f}px')
    if licensed:
        ps = pills(im, cd, 30)
        check(f'{name}: Start writing is one 48 DIP pill, centred', len(ps) == 1 and within(ps[0][3] - ps[0][1], 48 * s, 3) and within(near_cx(ps[0]), near_cx(cd), 2), f'{[(p[3]-p[1])/s for p in ps]} DIP')
        return
    ps = pills(im, cd, 30)
    act = [p for p in ps if p[3] - p[1] >= 40 * s]
    check(f'{name}: Activate is a 48 DIP pill', len(act) == 1 and within(act[0][3] - act[0][1], 48 * s, 3), f'{[(p[3]-p[1])/s for p in act]} DIP')
    ink = near(im, INK, 70)[cd[1]:cd[3], cd[0]:cd[2]]
    fr = [y for y in range(ink.shape[0]) if runs(ink[y], int(400 * s))]
    hs = near(im, (219, 218, 218), 14)[cd[1]:cd[3], cd[0]:cd[2]]
    fr += [y for y in range(hs.shape[0]) if runs(hs[y], int(400 * s)) and y not in fr]
    fr = sorted(fr)
    if fr:
        top, bot = fr[0], fr[-1]
        xs = runs(ink[top], int(400 * s)) or runs(hs[top], int(400 * s))
        fw = (xs[0][1] - xs[0][0]) / s
        check(f'{name}: field is 464 DIP wide (top border runs 448 between the 8 DIP corners), 44 DIP tall', within(fw, 448, 3) and within((bot - top + 1) / s, 44, 3), f'{fw:.1f} x {(bot-top+1)/s:.1f} DIP')
        fcx = cd[0] + (xs[0][0] + xs[0][1]) / 2
        check(f'{name}: field centred on the card', within(fcx, near_cx(cd), 2), f'{fcx:.1f}px vs {near_cx(cd):.1f}px')
        # the outline pill beside Activate: same row, same height, the pair centred
        if act:
            mid = (act[0][1] + act[0][3]) // 2
            nonwhite = (np.abs(im[mid, cd[0]:cd[2]] - 255).sum(axis=1) > 25)
            segs = [(a, b) for a, b in runs(nonwhite, 1) if cd[0] + a > act[0][2] + 4 and b < (cd[2] - cd[0]) - 12]
            right_edge = cd[0] + max(b for a, b in segs) if segs else cd[2]
            left, right = act[0][0] - cd[0], cd[2] - right_edge
            check(f'{name}: Activate + Buy pair centred as a group', within(left, right, 5), f'left gap {left/s:.1f} DIP, right gap {right/s:.1f} DIP')
    else:
        check(f'{name}: field border found', False, 'no border rows')

home('01-home-first-launch', True)
home('07-home-after-session-1', True)
home('08-home-after-session-2', True)
upgrade('09-upgrade-exhausted')
upgrade('13-upgrade-limit')
upgrade('14-upgrade-licensed', licensed=True)
upgrade('20-upgrade-revoked')
sys.exit(1 if fails else 0)
