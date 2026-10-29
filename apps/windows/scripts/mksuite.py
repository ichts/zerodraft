#!/usr/bin/env python3
"""Builds the drv script of the IME regression suite for one input method.
usage: mksuite.py TIP(pinyin|wetype|ja) OUTNAME EXE   -> drv script on stdout. Marks `M <id> <what>` are the
assertion windows cmd/imecheck reads."""
import sys
tip, out, exe = sys.argv[1:4]
img = exe.split('\\')[-1]
ja = tip == 'ja'
L = []
def w(*a): L.append(' '.join(str(x) for x in a))
def shot(n, wait=450): w('sleep', wait); w('shotwin', f'{tip}-{n}', 'Write It Down')
def mark(i, d): w('mark', 'M', i, d)
w('setenv', 'WID_ROOM_ONLY=1'); w('setenv', f'WID_LOG=C:\\wid\\out\\{out}\\app.log')
w('setenv', 'WID_SESSION_SECONDS=300')
w('killall', img)
w('launch', exe)
w('sleep 3500')
w('focus Write It Down'); w('sleep 600')
w('tip', tip); 
if ja: w('vk kanji')
w('sleep 500'); shot('00-selected', 600)
# 1 commit by space (zh) or convert+enter (ja)
mark('commit_space', 'compose then Space (zh) / Space+Enter (ja)')
w('type nihao' if not ja else 'type nihon'); shot('01-compose')
w('vk space')
if ja: w('sleep 400'); shot('01b-convert'); w('vk enter')
w('sleep 300'); shot('02-committed')
# 2 commit by candidate number (zh only; ja converts with Space)
mark('commit_number', 'compose then candidate number 2')
if not ja:
    w('type shijie'); shot('03-compose-number'); w('vk 2')
else:
    w('type sekai'); w('vk space'); w('sleep 300'); w('vk space'); w('sleep 300'); w('vk enter')
w('sleep 300')
# 3 commit by Enter (raw letters in zh, text in ja)
mark('commit_enter', 'compose then Enter')
w('type women' if not ja else 'type arigatou'); shot('04-compose-enter'); w('vk enter'); w('sleep 300')
# 4 edit the preedit with Backspace, forward-only must not interfere
mark('preedit_edit', 'type, two Backspaces inside the preedit, type, commit')
w('type zhongwen' if not ja else 'type konnichiwa'); w('sleep 300')
w('vk backspace'); w('sleep 300'); w('vk backspace'); shot('05-preedit-edited')
w('type ng' if not ja else 'type wa'); w('sleep 200'); w('vk space'); 
if ja: w('sleep 300'); w('vk enter')
w('sleep 300')
# 5 wrap: candidates follow the caret onto the second row
mark('wrap', 'phrases until the line wraps, then compose on the wrapped row')
for ph in (['jintian', 'tianqi', 'zhenhao', 'womenyiqi', 'xiezuo', 'bukeyihuitou', 'jintian', 'tianqi'] if not ja else ['kyou', 'wa', 'ii', 'tenki', 'desu', 'ne', 'asobi', 'ni', 'ikimasu']):
    w('type', ph); w('sleep 250'); w('vk space'); 
    if ja: w('sleep 250'); w('vk enter')
    w('sleep 250')
w('type fanyiruanjian' if not ja else 'type nihongo'); shot('06-wrapped-candidate', 700)
w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 300')
# 6 caret/selection keys while composing belong to the IME and must not break the append
mark('keys_while_composing', 'compose, press Left/Home/Ctrl+A inside the preedit, commit: the text lands at the end')
w('type nihao' if not ja else 'type nihon'); w('sleep 300')
w('vk left'); w('vk home'); w('vk a ctrl'); w('sleep 300'); shot('07-keys-while-composing')
w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 400')
# 7 after commit these are all refused and change nothing
mark('denied_after_commit', 'Backspace, Delete, Left, Right, Home, End, Ctrl+Z, Ctrl+Y, Ctrl+A, Ctrl+X, Ctrl+V, Shift+Left')
for k in ['backspace', 'delete', 'left', 'right', 'home', 'end', 'up', 'down']: w('vk', k)
for k in ['z', 'y', 'a', 'x', 'v']: w('vk', k, 'ctrl')
w('vk left shift'); w('sleep 500'); shot('08-denied')
# 8 a click cannot place the caret; the next input still lands at the end
mark('click_denied', 'click inside the draft, then type: no caret move, text lands at the end')
w('click 700 330'); w('sleep 300'); w('type nihao' if not ja else 'type nihon'); w('sleep 300'); w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 400'); shot('09-after-click')
# 9 the wipe lands while a composition is open; the next input starts a fresh session
mark('wipe_during_preedit', 'open a preedit, leave it for 9 s (wipe), then type again')
w('type nihao' if not ja else 'type nihon'); w('sleep 9500'); shot('10-wiped-with-open-preedit', 100)
w('vk esc') if False else None
w('type ni' if not ja else 'type ka'); w('sleep 300'); w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 500'); shot('11-restarted')
# 10 plain silence wipe, then the first IME key restarts in place
mark('wipe_restart', 'commit, 9 s of silence, then compose: only the new text remains')
w('type nihao' if not ja else 'type nihon'); w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 9500'); shot('12-stopped', 100)
w('type shijie' if not ja else 'type sekai'); w('sleep 300'); w('vk space')
if ja: w('sleep 300'); w('vk enter')
w('sleep 500'); shot('13-restarted-2')
mark('end', 'end')
w('mem', 'after-suite', img.replace('.exe', ''))
w('killall', img)
print('\n'.join(L))
