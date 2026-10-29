#!/usr/bin/env python3
"""drv script: the whole product end to end on vivobook-1 at one display scale, against the REAL licence service in
Stripe TEST mode (through the reverse tunnel): first launch, the three free sessions, the activation card, Buy (the
hosted-checkout hand-off), a paid test session, the two-PC limit and its release, activation, a licensed session,
relaunch, settings, refund and revocation. usage: mke2e.py SCALE OUTNAME"""
import sys
scale, out = sys.argv[1:3]
BROWSER = len(sys.argv) > 3 and sys.argv[3] == '1'   # the real default browser takes the hand-off (150% run); otherwise only the log
CTL = 'http://127.0.0.1:18061'
AUMID = r'shell:AppsFolder\TrefoilStudio.WriteItDownQA_5gka8kek26b2r!App'
L = []
def w(*a): L.append(' '.join(str(x) for x in a))
def shot(n, wait=350): w('sleep', wait); w('shotwin', f'{scale}-{n}', 'Write It Down')
def ctl(path, method='GET'): w('http', method, CTL + path)
def launch():
    w('killall wid.exe'); w('sleep 600'); w('launch', r'C:\Windows\explorer.exe', AUMID); w('sleep 5000'); w('focus Write It Down'); w('sleep 700')
def trial_session(n, last=False):
    w('vk enter'); w('sleep 900')                       # Begin
    if n == 1: shot('02-room-empty', 300)
    w('typefast', f'Trial session number {n} goes onto the paper, forward only, and then it stops.')
    if n == 1: shot('03-room-typing', 100)
    w('mark', f'SILENCE-{n}'); w('sleep 9600')          # 8 s of silence wipes the draft
    shot(f'0{3+n}-room-stopped-{n}', 0)
    if last: return
    w('vk esc'); w('sleep 300'); w('vk esc'); w('sleep 900')   # two-act exit back to Home
    shot(f'0{6+n}-home-after-session-{n}', 200)

w('dpi', scale); w('tip en'); w('sleep 600')
w('run', r'powershell -NoProfile -ExecutionPolicy Bypass -File C:\wid\qa\clearcred.ps1')
w('run', 'cmdkey /list | findstr /i WriteItDown.qa')
w('mark', 'PHASE first launch'); ctl('/qa/status')
launch()
shot('01-home-first-launch', 300)
w('clickwin Write It Down 718 109'); shot('01b-rules', 500)              # the "?" with a real mouse click
w('vk enter'); w('sleep 500')                                                # Done
trial_session(1); trial_session(2)
w('mark', 'PHASE third session: the last free one, wipe does not route to checkout')
trial_session(3, last=True)
w('vk enter'); shot('09-upgrade-exhausted', 700)                           # restart after exhaustion opens activation
w('vk enter'); shot('09b-upgrade-empty-submit', 400)                       # an empty field is refused locally
w('mark', 'PHASE buy'); w('vk tab'); w('vk tab'); shot('10-upgrade-buy-focus', 200)
w('vk enter')
if BROWSER:   # the real hand-off: the default browser (Edge) opens the hosted checkout URL; close what the hand-off started
    w('sleep 6000'); w('shot', f'{scale}-11a-browser-checkout'); w('killall msedge.exe'); w('sleep 1500'); w('focus Write It Down'); w('sleep 600')
shot('11-upgrade-after-buy', 1000); ctl('/qa/status')
w('mark', 'PHASE paid, both other PCs already active: the third meets the limit')
ctl('/qa/complete'); ctl('/qa/fill?n=2')
w('vk tab shift'); w('vk tab shift'); w('typehttp', CTL + '/qa/key'); shot('12-upgrade-key-typed', 300)
w('vk enter'); shot('13-upgrade-limit', 2500)
w('mark', 'PHASE one PC released: same entry succeeds'); ctl('/qa/free')
w('vk enter'); shot('14-upgrade-licensed', 2800)
w('vk enter'); shot('15-home-licensed', 700)                               # Start writing -> Home, no access line
w('vk enter'); w('sleep 900'); w('typefast Licensed session, nothing is spent.'); w('sleep 9600'); shot('16-room-stopped-licensed', 0)
w('vk enter'); shot('17-room-restarted-in-place', 700)                     # licensed: restarts in place, no card
w('vk esc'); w('sleep 300'); w('vk esc'); w('sleep 900')
w('mark', 'PHASE relaunch'); launch(); shot('18-home-relaunch-licensed', 200)
w('vk comma ctrl'); shot('19-settings-licensed', 600); w('vk esc'); w('sleep 400')
w('mark', 'PHASE refund'); ctl('/qa/refund')
launch(); w('sleep 2500'); shot('20-upgrade-revoked', 200)
w('vk tab'); w('vk tab'); shot('20b-revoked-buy-focus', 100)
if BROWSER:   # Stripe unavailable: Buy falls back to the public purchase page, opened in the real browser
    ctl('/qa/stripe-down?on=1'); w('focus Write It Down'); w('sleep 400'); w('vk enter')
    w('sleep 6000'); w('shot', f'{scale}-21-browser-fallback-page'); w('killall msedge.exe'); w('sleep 1500')
w('run', 'cmdkey /list | findstr /i WriteItDown.qa')
w('run', r'powershell -NoProfile -ExecutionPolicy Bypass -File C:\wid\qa\clearcred.ps1')
w('killall wid.exe'); w('dpi 150'); w('mark done')
print('\n'.join(L))
