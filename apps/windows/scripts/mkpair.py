#!/usr/bin/env python3
"""drv script: the room states the Mac's SnapshotTests render, in the Mac's window size, at 100%: rest, typing, exit hint,
warning (5.6 s idle), deleted, kept, copied. Same draft as the Mac fixtures. usage: mkpair.py OUTNAME EXE"""
import sys
out, exe = sys.argv[1:3]
img = exe.split('\\')[-1]
L = []
def w(*a): L.append(' '.join(str(x) for x in a))
def shot(n, wait=250): w('sleep', wait); w('shotwin', f'100-{n}', 'Write It Down')
def launch(extra=()):
    w('killall', img)
    for e in extra: w('setenv', e)
    w('launch', exe); w('sleep 4500'); w('focus Write It Down'); w('sleep 700')
def draft():
    w('typefast cant say this out loud but'); w('vk enter'); w('typefast i dont want the promotion'); w('vk enter')
    w('typefast promotion. i want time')
w('dpi 100'); w('tip en'); w('sleep 600')
w('setenv', 'WID_ROOM_ONLY=1'); w('setenv', 'WID_WINDOW=1040x720')
w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app-a.log')
launch(); shot('room-rest', 500)
draft(); shot('room-typing', 120)
w('vk esc'); shot('room-exit-hint', 150)
w('killall', img)
w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app-b.log')
launch(); draft(); w('sleep 5500'); shot('room-warning', 0)
w('killall', img)
launch(); w('typefast one sentence'); w('sleep 8800'); shot('room-deleted', 400)
w('killall', img)
w('setenv', 'WID_SESSION_SECONDS=15'); w('setenv', 'WID_SILENCE_SECONDS=30')
w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app-c.log')
launch(); draft(); w('sleep 15500'); shot('room-kept', 600)
w('vk enter'); shot('room-copied', 300)
w('killall', img)
w('dpi 150')
print('\n'.join(L))
