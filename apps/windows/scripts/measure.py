#!/usr/bin/env python3
"""Measures the real-window captures of one scale and prints one PASS/FAIL line per geometry rule (the numbers,
not the eye). usage: measure.py EVIDENCE_DIR SCALE   (needs numpy + Pillow)
Reads <dir>/<scale>-*.png (window crops from drv shotwin), rec-<scale>/ frames and app-<scale>-a.log."""
import sys, os, re, glob, json
import numpy as np
from PIL import Image

D, S = sys.argv[1], int(sys.argv[2])
s = S / 100.0            # device pixels per DIP
rows = []
def check(name, ok, detail):
    ok = bool(ok)
    rows.append((ok, name, detail))
    print(('PASS' if ok else 'FAIL'), f'[{S}%]', name, '-', detail)

def load(n):
    return np.asarray(Image.open(os.path.join(D, f'{S}-{n}.png')).convert('RGB')).astype(int)

PAGE = np.array([247, 247, 245]); WHEAT = np.array([233, 226, 206])

SIZE = None
for l in open(os.path.join(D, f'app-{S}-a.log')):
    m = re.search(r'SIZE ([\d.]+)x([\d.]+)@', l)
    if m: SIZE = (float(m.group(1)), float(m.group(2))); break

def client(im):
    m = (np.abs(im - PAGE).sum(axis=2) <= 6)
    ys, xs = np.where(m)
    # the page colour also appears outside the window; take the biggest bounding box of dense rows/cols
    rowd, cold = m.sum(axis=1), m.sum(axis=0)
    y = np.where(rowd > im.shape[1] * 0.3)[0]; x = np.where(cold > im.shape[0] * 0.3)[0]
    return x.min(), y.min(), x.max() + 1, y.max() + 1

def paper_rect(im, cl):
    x0, y0, x1, y1 = cl
    d = ((im[:, :, 0] - im[:, :, 2]) >= 14) & ((im[:, :, 0] - im[:, :, 2]) <= 48) & (im[:, :, 0] > 200)  # wheat is warm (R-B ~27), the page and its shadow are neutral
    sub = d[y0:y1, x0:x1]
    r = np.where(sub.mean(axis=1) > 0.5)[0]; c = np.where(sub.mean(axis=0) > 0.5)[0]
    return x0 + c.min(), y0 + r.min(), x0 + c.max() + 1, y0 + r.max() + 1

def ink_rows(im, box, thresh=110):
    x0, y0, x1, y1 = box
    g = im[y0:y1, x0:x1].mean(axis=2)
    dark = g < thresh
    return dark, y0, x0

def bands(mask):
    """vertical runs of rows containing ink"""
    r = mask.sum(axis=1) >= 4       # a paper fleck is a few pixels; a text row has many
    out, start = [], None
    for i, v in enumerate(r):
        if v and start is None: start = i
        if not v and start is not None: out.append((start, i)); start = None
    if start is not None: out.append((start, len(r)))
    return [b for b in out if b[1] - b[0] >= 5]

ref = load('02-typing')
cl = (0, 0, ref.shape[1], ref.shape[0])
pr = paper_rect(ref, cl)
pw, ph = pr[2] - pr[0], pr[3] - pr[1]
check('paper is the client minus a 32 DIP inset on every side', SIZE is not None and abs(pw - (SIZE[0] - 64) * s) <= 3 * s and abs(ph - (SIZE[1] - 64) * s) <= 3 * s,
      f'paper {pw}x{ph}px, client {SIZE} DIP -> want {(SIZE[0]-64)*s:.0f}x{(SIZE[1]-64)*s:.0f}px')

# --- writing line on the 33% anchor
area = (pr[0] + int(40 * s), pr[1] + int(72 * s), pr[2] - int(40 * s), pr[3] - int(72 * s))
dark, oy, ox = ink_rows(ref, area, 95)
b = bands(dark)
lines = [x for x in b if x[1] - x[0] > 6 * s]
check('three writing lines visible (current + two history steps)', len(lines) >= 3, f'{len(lines)} ink bands')
cur = lines[-1]
anchor = pr[1] + round(0.33 * (ph / s)) * s
curmid = oy + (cur[0] + cur[1]) / 2
# The Mac sets the glyphs at the bottom of their 1.6 line box and puts the line's box on the anchor, so the live line's ink
# centre is 14.5 DIP under the anchor (measured on the Mac room at 1040 x 720: x-height 257..269 on an anchor of 249, SYNC row 20)
check('current line sits on the 33% anchor the way the Mac sets it (ink centre 14.5 DIP under it)', abs(curmid - (anchor + 14.5 * s)) <= 2.5 * s,
      f'ink centre {curmid:.1f}px vs anchor {anchor:.1f}px + {14.5*s:.1f}px (line pitch {44.8*s:.1f}px)')
if len(lines) >= 2:
    pitch = ((lines[-1][0] + lines[-1][1]) - (lines[-2][0] + lines[-2][1])) / 2
    check('line pitch is 1.6 x 28 pt', abs(pitch - 44.8 * s) <= 2.5 * s, f'{pitch:.1f}px vs {44.8*s:.1f}px')
    # history ladder: darkness of each band (min channel average) must step 1 > .847 > .769
    def depth(bd):
        seg = ref[oy + bd[0]: oy + bd[1], ox: ox + (area[2] - area[0])].mean(axis=2)
        return 255 - np.percentile(seg, 2)
    # the ladder's unit is the line ended by Return (D-088): the oldest visible row is the one that must be fainter
    # than the live row
    d0, d1 = depth(lines[-1]), (depth(lines[-3] if len(lines) > 2 else lines[-2]) if len(lines) > 1 else 0)
    check('the oldest visible line is fainter than the writing line', d1 < d0 - 5, f'ink depth {d0:.0f} -> {d1:.0f}')

if len(lines) >= 2:   # Q-04: a full history line is centred on the sheet (ink edges of a centred line are within a few px)
    full = lines[-2]
    xs_ = np.where(dark[full[0]:full[1]].sum(axis=0) > 0)[0]
    cmid = ox + (xs_.min() + xs_.max()) / 2
    check('Q-04: a centred writing line is centred on the sheet', abs(cmid - (pr[0] + pr[2]) / 2) <= 7 * s,
          f'line ink centre {cmid:.1f}px vs sheet centre {(pr[0]+pr[2])/2:.1f}px')

# --- footer row: the exit label and the word count share a baseline; insets 22 DIP
foot_y = pr[3] - int(16 * s) - int(22 * s)
fb = (pr[0], foot_y - int(16 * s), pr[2], foot_y + int(16 * s))
fdark, fy, fx = ink_rows(ref, fb, 150)
left = fdark[:, : fdark.shape[1] // 2]; right = fdark[:, fdark.shape[1] // 2:]
lb, rb = bands(left), bands(right)
check('footer: exit link and count are on one baseline', bool(lb and rb) and abs(lb[-1][1] - rb[-1][1]) <= max(1.5, 0.12 * 13 * s),
      f'exit link bottom {lb[-1][1] if lb else None}, count bottom {rb[-1][1] if rb else None} (px in row)')
left_rows = np.zeros(left.shape[0], bool)
for a, z in lb: left_rows[a:z] = True
xs = np.where(left[left_rows].sum(axis=0) > 0)[0] if left_rows.any() else []
check('exit link inset is 22 DIP from the paper edge', bool(len(xs)) and abs((fx + xs.min() - pr[0]) - 22 * s) <= 3 * s,
      f'{fx + xs.min() - pr[0]}px vs {22*s:.0f}px')
right_rows = np.zeros(right.shape[0], bool)
for a, z in rb: right_rows[a:z] = True
xr = np.where(right[right_rows].sum(axis=0) > 0)[0] if right_rows.any() else []
check('count inset is 22 DIP from the paper edge', bool(len(xr)) and abs((pr[2] - (fx + fdark.shape[1] // 2 + xr.max() + 1)) - 22 * s) <= 3 * s,
      f'{pr[2] - (fx + fdark.shape[1]//2 + xr.max() + 1)}px vs {22*s:.0f}px')
# clock top right
cb = (pr[2] - int(120 * s), pr[1] + int(8 * s), pr[2], pr[1] + int(50 * s))
cdark, cy, cx = ink_rows(ref, cb, 120)
xc = np.where(cdark.sum(axis=0) > 0)[0]
check('clock inset is 22 DIP from the paper edge', bool(len(xc)) and abs((pr[2] - (cx + xc.max() + 1)) - 22 * s) <= 3 * s,
      f'{pr[2] - (cx + xc.max() + 1)}px vs {22*s:.0f}px')

# --- texture and tone on a blank patch of paper
patch = ref[pr[1] + int(0.6 * ph): pr[1] + int(0.6 * ph) + int(120 * s), pr[0] + int(0.3 * pw): pr[0] + int(0.3 * pw) + int(200 * s)]
mean, std = patch.reshape(-1, 3).mean(axis=0), patch.reshape(-1, 3).std(axis=0)
check('paper mean is the Wheat token #e9e2ce', np.abs(mean - WHEAT).max() <= 7, f'mean {mean.round(1).tolist()} vs {WHEAT.tolist()}')
check('paper carries the grain texture', std.mean() >= 3.5, f'std {std.round(1).tolist()}')

# --- stopped screen: one group at 33%
st = load('06-stopped')
cl2 = (0, 0, st.shape[1], st.shape[0]); pr2 = paper_rect(st, cl2)
white = (np.abs(st - np.array([255, 255, 255])).sum(axis=2) <= 6)
pw2 = pr2[2] - pr2[0]
sub = white[pr2[1]:pr2[3], pr2[0] + pw2 // 4: pr2[2] - pw2 // 4]
rr = np.where(sub.sum(axis=1) > 40)[0]
pill = (pr2[1] + rr.min(), pr2[1] + rr.max() + 1) if len(rr) else None
base = round(min(max(SIZE[0] * 0.05, 32), 48))
check('stopped: pill is one headline tall', pill is not None and abs((pill[1] - pill[0]) - base * s) <= 2 * s + 2, f'{pill} height {pill[1]-pill[0] if pill else None}px vs {base*s:.0f}px')
dk, y0, x0 = ink_rows(st, (pr2[0] + int(60 * s), pr2[1] + int(20 * s), pr2[2] - int(60 * s), pr2[1] + int(0.6 * (pr2[3] - pr2[1]))), 100)
bs = bands(dk)
if bs and pill:
    top = y0 + bs[0][0]
    mid = (top + pill[1]) / 2
    want = pr2[1] + round(0.33 * ((pr2[3] - pr2[1]) / s)) * s
    check('stopped: group midpoint on the 33% anchor', abs(mid - want) <= 5 * s, f'group {top}..{pill[1]} mid {mid:.1f}px vs {want:.1f}px')
    # headline horizontally centred
    xs = np.where(dk[: bs[0][1], :].sum(axis=0) > 0)[0]
    cxm = x0 + (xs.min() + xs.max()) / 2
    check('stopped: headline centred on the paper', abs(cxm - (pr2[0] + pr2[2]) / 2) <= 3 * s, f'{cxm:.1f} vs {(pr2[0]+pr2[2])/2:.1f}')
    # pill label optical centre: ink bbox of the label inside the pill (excluding the descender of g)
    lab = st[pill[0]:pill[1], pr2[0]: pr2[2]].mean(axis=2) < 110
    ly = np.where(lab.sum(axis=1) > 0)[0]
    if len(ly):
        # cap top to baseline: drop descender rows (rows with very little ink at the bottom)
        counts = lab.sum(axis=1)
        keep = np.where(counts > max(3, 0.18 * counts.max()))[0]
        c_ink = (keep.min() + keep.max() + 1) / 2
        check('stopped: pill label sits on the pill centre', abs(c_ink - (pill[1] - pill[0]) / 2) <= 1.5 * s + 0.5, f'label ink centre {c_ink:.1f}px vs pill centre {(pill[1]-pill[0])/2:.1f}px')

# --- kept screen
kp = load('11-kept')
cl3 = (0, 0, kp.shape[1], kp.shape[0]); pr3 = paper_rect(kp, cl3)
blk = (np.abs(kp - np.array([28, 25, 23])).sum(axis=2) <= 25)
sub = blk[pr3[1] + int(150 * s): pr3[1] + int(240 * s), pr3[0]: pr3[2]]
def longest_run(row):
    best = cur = 0
    for v in row:
        cur = cur + 1 if v else 0
        best = max(best, cur)
    return best
tight = (np.abs(kp - np.array([28, 25, 23])).sum(axis=2) <= 6)[pr3[1] + int(150 * s): pr3[1] + int(240 * s), pr3[0]: pr3[2]]
full = np.where(tight.sum(axis=1) >= 60 * s)[0]
if len(full):
    cols = np.where(tight[full.min(): full.max() + 1].sum(axis=0) >= 3)[0]
    px0, px1 = cols.min(), cols.max() + 1
    rowsany = np.where(tight[:, px0:px1].sum(axis=1) >= 3)[0]
    top_i, bot_i = rowsany.min(), rowsany.max() + 1
    pill_h = bot_i - top_i
    check('kept: COPY TEXT pill is 48 DIP tall', abs(pill_h - 48 * s) <= 1.5 * s + 1, f'{pill_h}px vs {48*s:.0f}px')
    lab = (kp[pr3[1] + int(150 * s) + top_i: pr3[1] + int(150 * s) + bot_i, pr3[0] + px0 + int(20 * s): pr3[0] + px1 - int(20 * s)].mean(axis=2) > 200)
    ly = np.where(lab.sum(axis=1) > 0)[0]
    if len(ly):
        c_ink = (ly.min() + ly.max() + 1) / 2
        check('kept: COPY TEXT label sits on the pill centre', abs(c_ink - pill_h / 2) <= 1.5 * s + 0.5, f'label ink centre {c_ink:.1f}px vs pill centre {pill_h/2:.1f}px')
    # the two pills are one row centred on the paper: ink pill left edge .. outlined pill right edge
    wide = ((kp[pr3[1] + int(150 * s) + top_i + pill_h // 2, pr3[0]: pr3[2]]).mean(axis=1) > 250) | tight[top_i + pill_h // 2]
    rowx = np.where(wide)[0]
    if len(rowx):
        check('kept: action row is centred on the paper', abs((rowx.min() + rowx.max()) / 2 - (pr3[2] - pr3[0]) / 2) <= 6 * s, f'row centre {(rowx.min()+rowx.max())/2:.0f}px vs paper centre {(pr3[2]-pr3[0])/2:.0f}px')
else:
    check('kept: COPY TEXT pill found', False, 'no ink pill in the header band')

# --- Q-06: chrome does not move between states (clock, exit link, count keep one place)
def chrome_marks(name):
    im = load(name)
    p = paper_rect(im, (0, 0, im.shape[1], im.shape[0]))
    out = {}
    cb = (p[2] - int(120 * s), p[1] + int(8 * s), p[2], p[1] + int(50 * s))
    dk, cy, cx = ink_rows(im, cb, 120)
    ys, xs = np.where(dk)
    rows_ = [b for b in bands(dk)]
    if rows_ and len(xs):
        out['clock_right'] = p[2] - (cx + xs.max() + 1); out['clock_top'] = cy + rows_[0][0] - p[1]
    foot = p[3] - int(16 * s) - int(22 * s)
    fb = (p[0], foot - int(16 * s), p[2], foot + int(16 * s))
    fd, fy, fx = ink_rows(im, fb, 150)
    half = fd.shape[1] // 2
    def baseline(m):   # the row where the ink density falls away: descenders (Type to begin) do not count
        prof = m.sum(axis=1)
        return int(np.where(prof >= 0.5 * prof.max())[0].max()) + 1 if prof.max() > 0 else None
    be, bc = baseline(fd[:, :half]), baseline(fd[:, half:])
    if be: out['exit_baseline'] = fy + be - p[1]
    if bc: out['count_baseline'] = fy + bc - p[1]
    return out
marks = {n: chrome_marks(n) for n in ('00-empty', '02-typing', '07-restarted')}
base = marks['02-typing']
ok = all(abs(v - base[k]) <= 1.5 * s for m in marks.values() for k, v in m.items() if k in base)
check('Q-06: clock, exit link and count do not move between empty, typing and restarted', ok and len(base) >= 4, json.dumps({n: {k: int(v) for k, v in m.items()} for n, m in marks.items()}))

# --- Q-25: the stopped sheet takes the clock and the bar off
clk = st[pr2[1] + int(8 * s): pr2[1] + int(50 * s), pr2[2] - int(120 * s): pr2[2]].mean(axis=2) < 120
bar = st[pr2[1] + 1: pr2[1] + int(3 * s), pr2[0] + int(40 * s): pr2[2] - int(40 * s)].mean(axis=2) < 80
check('Q-25: stopped sheet shows no clock and no session bar', (bands(clk) == []) and bar.mean() < 0.02, f'clock ink rows {len(bands(clk))}, bar dark share {bar.mean():.3f}')

# --- Q-29: the exit confirmation shares the footer baseline and the exit link's type
ea = load('08-exit-armed')
pe = paper_rect(ea, (0, 0, ea.shape[1], ea.shape[0]))
foot = pe[3] - int(16 * s) - int(22 * s)
fd, fy, fx = ink_rows(ea, (pe[0], foot - int(16 * s), pe[2], foot + int(16 * s)), 150)
cols = np.where(fd.sum(axis=0) > 0)[0]
mid = pe[0] + (pe[2] - pe[0]) // 2
left_end = [c for c in cols if fx + c < mid]
hint_ok = False; detail = 'no hint ink'
if left_end:
    seg = fd[:, : max(left_end) + 1]
    b2 = bands(seg)
    # the link and the hint are one row: a single ink band, ink reaching well past the 22 + link width
    hint_ok = len(b2) == 1 and (max(left_end) + 1) > 300 * s
    detail = f'{len(b2)} ink band(s), row ink reaches {max(left_end)+1}px from the paper edge'
check('Q-29: exit confirmation sits on the exit row, one baseline', hint_ok, detail)
red = (np.abs(ea - np.array([99, 20, 11])).sum(axis=2) <= 90)[pe[3] - int(70 * s): pe[3] - int(20 * s), pe[0]: pe[2]]
check('Q-29: the confirmation is set in the pen red', red.sum() > 40, f'{int(red.sum())} pen-red pixels in the footer row')

# --- timing from the logs: warn at 5 s of silence, wipe at 8 s
logp = os.path.join(D, f'app-{S}-a.log')
drv = open(os.path.join(D, 'drv.log')).read().splitlines()
typed = [float(l.split()[0]) for l in drv if ' typed "Keep going until' in l or 'typed "Keep' in l]
if not typed:
    typed = [float(l.split()[0]) for l in drv if ' typed ' in l]
mk = [float(l.split()[0]) for l in drv if 'mark SILENCE-START' in l]
last_key = mk[0] - 0.0 if mk else typed[-1]
ev = {}
for l in open(logp):
    m = re.match(r'(\d+\.\d+) .*(PHASE writing -> danger|PHASE danger -> failure|NUMERAL (\d))', l)
    if m:
        ev.setdefault(m.group(2), []).append(float(m.group(1)))
if mk and 'PHASE writing -> danger' in ev:
    # the log timestamps of the keystrokes themselves are exact: last STATE before the silence mark
    last = 0
    for l in open(logp):
        m = re.match(r'(\d+\.\d+) .*STATE ', l)
        if m and float(m.group(1)) <= mk[0] + 0.5:
            last = float(m.group(1))
    warn, wipe = ev['PHASE writing -> danger'][0] - last, ev['PHASE danger -> failure'][0] - last
    check('warn begins 5.0 s after the last key', abs(warn - 5.0) <= 0.12, f'{warn:.3f} s')
    check('wipe lands 8.0 s after the last key', abs(wipe - 8.0) <= 0.12, f'{wipe:.3f} s')

# --- pick the warn frames and measure the wash and the numeral
frames = sorted(glob.glob(os.path.join(D, f'rec-{S}', '*.jpg')))
def frame_at(t):
    best = None
    for f in frames:
        ms = int(os.path.basename(f).split('_')[1].split('.')[0]) / 1000.0
        if ms >= t and (best is None or ms < best[0]): best = (ms, f)
    return best[1] if best else None
rect = None
for l in drv:
    m = re.search(r'shotwin 02-typing rect=(\d+),(\d+),(\d+),(\d+)', l.replace(f'{S}-02-typing', '02-typing'))
    if m: rect = tuple(map(int, m.groups()))
saved = {}
for n, key in ((3, 'NUMERAL 3'), (2, 'NUMERAL 2'), (1, 'NUMERAL 1')):
    if key in ev and rect:
        f = frame_at(ev[key][0] + 0.30)
        if f:
            im = Image.open(f).convert('RGB').crop(rect)
            im.save(os.path.join(D, f'{S}-0{2 + n if False else 6 - n}-warn-{n}.png'))
            saved[n] = np.asarray(im).astype(int)
if 3 in saved and 1 in saved:
    def blank(im):
        return im[pr[1] + int(0.62 * ph): pr[1] + int(0.62 * ph) + int(100 * s), pr[0] + int(0.3 * pw): pr[0] + int(0.3 * pw) + int(160 * s)].reshape(-1, 3).mean(axis=0)
    c3, c1 = blank(saved[3]), blank(saved[1])
    check('warn wash warms the paper towards #e8cfbb over the three seconds', c1[2] < c3[2] - 8 and abs(c1[2] - 187) < 25,
          f'blue channel {c3[2]:.0f} (3) -> {c1[2]:.0f} (1), target 187')
    red = (np.abs(saved[3] - np.array([99, 20, 11])).sum(axis=2) <= 60)
    reg = red[pr[1] + int(0.4 * ph): pr[3] - int(60 * s), pr[0] + int(0.3 * pw): pr[2] - int(0.3 * pw)]
    ys, xs = np.where(reg); xs = xs + int(0.3 * pw)
    if len(ys):
        # the Mac puts the numeral's ink top 44 pt under the writing line's baseline (D-020)
        seg = saved[3][int(anchor - 0.6 * 44.8 * s): int(anchor + 0.6 * 44.8 * s), pr[0] + int(40 * s): pr[2] - int(40 * s)].mean(axis=2) < 95
        prof = seg.sum(axis=1)
        base_row = np.where(prof >= 0.5 * prof.max())[0].max() + int(anchor - 0.6 * 44.8 * s) + 1
        top = pr[1] + int(0.4 * ph) + ys.min()
        check('numeral ink top is 44 DIP under the writing baseline', abs((top - base_row) - 44 * s) <= 4 * s,
              f'baseline row {base_row}px, numeral ink top {top}px -> {(top-base_row)/s:.1f} DIP (want 44)')
        check('numeral is centred on the paper (its advance box; the italic ink leans)', abs(((xs.min() + xs.max()) / 2 + pr[0]) - (pr[0] + pr[2]) / 2) <= 14 * s, f'{(xs.min()+xs.max())/2+pr[0]:.0f} vs {(pr[0]+pr[2])/2:.0f}')
    else:
        check('numeral appears under the writing line', False, 'no pen-red ink found')

# --- D-074: the kept receipt owns the count, so the corner is silent; one caption sits under the action row
if len(full):
    kfoot = pr3[3] - int(16 * s) - int(22 * s)
    kd, ky, kx = ink_rows(kp, (pr3[0], kfoot - int(16 * s), pr3[2], kfoot + int(16 * s)), 150)
    check('D-074 kept: the corner count is silent', not bands(kd[:, kd.shape[1] // 2:]), f'{len(bands(kd[:, kd.shape[1] // 2:]))} ink band(s) in the right half of the footer row')
    pill_bottom = pr3[1] + int(150 * s) + bot_i
    cd, cy, cx = ink_rows(kp, (pr3[0] + int(40 * s), pill_bottom + int(4 * s), pr3[2] - int(40 * s), pill_bottom + int(48 * s)), 150)
    cb_ = [b for b in bands(cd) if b[1] - b[0] >= 6 * s]
    if cb_:
        xs_ = np.where(cd[cb_[0][0]:cb_[0][1]].sum(axis=0) >= 2)[0]   # two dark pixels in a column: the paper's flecks are single
        gap_ = (cy + cb_[0][0] - pill_bottom) / s
        mid_ = cx + (np.percentile(xs_, 2) + np.percentile(xs_, 98)) / 2   # the paper's flecks must not stretch the extent
        check('D-074 kept: one caption under the action row (the Mac sets it 25 DIP of ink under the pills), centred', 20 <= gap_ <= 30 and abs(mid_ - (pr3[0] + pr3[2]) / 2) <= 6 * s,
              f'caption ink {gap_:.1f} DIP under the pills, centre {mid_:.0f}px vs paper {(pr3[0]+pr3[2])/2:.0f}px')
    else:
        check('D-074 kept: one caption under the action row', False, 'no ink under the pills')

# --- D-077: the first refused delete names the rule in the footer slot, in the quiet role, and the slot returns
def slot_extent(name):
    im = load(name); p = paper_rect(im, (0, 0, im.shape[1], im.shape[0]))
    ft = p[3] - int(16 * s) - int(22 * s)
    fd_, fy_, fx_ = ink_rows(im, (p[0], ft - int(16 * s), p[0] + (p[2] - p[0]) // 2, ft + int(16 * s)), 150)
    cols_ = np.where(fd_.sum(axis=0) >= 2)[0]   # two dark pixels in a column: the paper's flecks are single
    red_ = (np.abs(im - np.array([99, 20, 11])).sum(axis=2) <= 90)[p[3] - int(70 * s): p[3] - int(20 * s), p[0]: p[2]]
    end = 0
    for c in cols_:                      # the link and the notice are one run of ink; a stray fleck 24 DIP past it is not text
        if end and c - end > 24 * s: break
        end = c
    return (end + 1) / s if len(cols_) else 0, int(red_.sum())
if os.path.exists(os.path.join(D, f'{S}-10b-refusal-notice.png')):
    w1, r1 = slot_extent('10b-refusal-notice'); w2, r2 = slot_extent('10c-notice-gone')
    check('D-077: the first refused delete names the rule in the footer slot, in the quiet role (not the pen)', w1 > 200 and r1 < 40, f'footer ink reaches {w1:.0f} DIP, {r1} pen-red pixels')
    check('D-077: the slot returns after two seconds with nothing moved', w2 < 100, f'footer ink reaches {w2:.0f} DIP')
    mb = chrome_marks('10b-refusal-notice'); mc = chrome_marks('10c-notice-gone')
    check('D-077: exit link, count and clock stay put while the notice shows', all(abs(mb[k] - base[k]) <= 1.5 * s for k in base if k in mb) and all(abs(mc[k] - base[k]) <= 1.5 * s for k in base if k in mc),
          json.dumps({'notice': {k: int(v) for k, v in mb.items()}, 'gone': {k: int(v) for k, v in mc.items()}}))

fails = [r for r in rows if not r[0]]
json.dump([{'ok': r[0], 'check': r[1], 'detail': r[2]} for r in rows], open(os.path.join(D, f'measure-{S}.json'), 'w'), indent=1)
print(f'{len(rows) - len(fails)}/{len(rows)} passed at {S}%')
sys.exit(1 if fails else 0)
