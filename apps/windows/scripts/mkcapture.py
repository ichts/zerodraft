#!/usr/bin/env python3
"""drv script: every room state at one display scale. usage: mkcapture.py SCALE(100|125|150) OUTNAME EXE [home]
Two launches: the 60 s room (empty, first char, typing with history fade, warn 3/2/1, stopped, restart, exit
confirmation, deny) and a 15 s room that reaches the kept sheet (kept, COPIED, focus ring)."""
import sys
scale, out, exe = sys.argv[1:4]
home = sys.argv[4] if len(sys.argv) > 4 else '150'
img = exe.split('\\')[-1]
L = []
def w(*a): L.append(' '.join(str(x) for x in a))
def shot(n, wait=250): w('sleep', wait); w('shotwin', f'{scale}-{n}', 'Write It Down')
w('dpi', scale)
w('tip ja'); w('sleep 300'); w('tip en'); w('sleep 600')
# ---- run 1: the 60 s room
w('setenv', 'WID_ROOM_ONLY=1'); w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app-{scale}-a.log'); w('killall', img); w('launch', exe); w('sleep 4500')
w('focus Write It Down'); w('sleep 700')
shot('00-empty', 600)
w('typefast T'); shot('01-first-char', 120)
w('typefast his is the first line of a longer draft, written forward only, so every word stays where it landed. ')
w('sleep 400'); w('typefast The room fades what is behind you, one line at a time, and nothing can be undone or deleted. ')
w('sleep 400'); w('typefast A third line follows the second, then a fourth, and the oldest lines quietly leave the sheet. ')
w('sleep 400'); w('typefast Keep going until the lines have wrapped around the measure several times over and over again.')
shot('02-typing', 60)
w('mark', 'SILENCE-START')
w('frames', f'rec-{scale}', 8)
w('sleep 11000')
w('framesstop')
shot('06-stopped', 0)
w('typefast R'); shot('07-restarted', 200)
w('vk esc'); shot('08-exit-armed', 150)
w('vk backspace'); shot('09-deny', 40)
w('sleep 2300'); shot('10-exit-expired', 0)
w('vk esc'); w('sleep 300'); w('vk esc'); w('sleep 1200')
w('mem', 'after-exit', img.replace('.exe', ''))
w('killall', img)
# ---- run 2: the 15 s room reaches the kept sheet
w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app-{scale}-b.log'); w('setenv', 'WID_SESSION_SECONDS=15'); w('launch', exe); w('sleep 4500')
w('focus Write It Down'); w('sleep 700')
for i in range(3):
    w('typefast', 'A line of kept writing number %d goes into the draft, then another one follows it.' % (i + 1)); w('sleep 1800')
w('sleep 3500')   # past the 15 s deadline with no key after it: the kept sheet carries no focus ring yet
shot('11-kept', 600)
w('vk enter'); shot('12-kept-copied', 300)
w('vk tab'); shot('13-kept-focus-run', 300)
w('mem', 'kept', img.replace('.exe', ''))
w('killall', img)
w('dpi', home)
print('\n'.join(L))
