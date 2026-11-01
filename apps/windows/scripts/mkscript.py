#!/usr/bin/env python3
"""Generate drv scripts. usage: mkscript.py ime EXE TITLE OUTNAME TIP   (TIP: pinyin|wetype)"""
import sys
kind, exe, title, out, tip = sys.argv[1:6]
img = exe.split('\\')[-1]
L = []
def w(*a): L.append(' '.join(str(x) for x in a))
def shot(n, wait=500): w('sleep', wait); w('shot', n)
w('setenv', f'WID_PROBE_LOG=C:\\wid\\out\\{out}\\app.log')
w('killall', img)
w('launch', exe)
w('sleep 3500')
w('focus', title); w('move', title, 100, 10, 1500, 960); w('focus', title); w('sleep', 800)
shot('00-rest')
w('tip', tip); shot('01-zh-selected', 900)
w('mark', 'ZH nihao'); w('type nihao'); shot('02-compose-nihao')
w('vk space'); shot('03-commit-nihao')
w('mark', 'ZH shijie 2'); w('type shijie'); shot('04-compose-shijie')
w('vk 2'); shot('05-commit-pick2')
w('mark', 'ZH women enter'); w('type women'); shot('06-compose-women'); w('vk enter'); shot('07-enter-commits-raw')
w('mark', 'ZH zhongwen bksp bksp ng'); w('type zhongwen'); shot('08-compose-zhongwen')
w('vk backspace'); w('sleep 300'); w('vk backspace'); shot('09-backspace-edits-preedit')
w('type ng'); w('vk space'); shot('10-commit-after-edit')
w('mark', 'ZH wrap phrases')
for ph in ['jintian', 'tianqi', 'zhenhao', 'womenyiqi', 'xiezuo', 'bukeyihuitou']:
    w('type', ph); w('sleep 250'); w('vk space'); w('sleep 250')
w('type fanyiruanjian'); shot('11-compose-wrapped-line-candidate-position')
w('vk space'); shot('12-after-wrap')
w('mark', 'DENY backspace left ctrl-z ctrl-a shift-left home')
w('vk backspace'); w('vk left'); w('vk z ctrl'); w('vk a ctrl'); w('vk left shift'); w('vk home'); w('vk delete'); shot('13-after-denied-keys')
w('mark', 'DENY click in text'); w('click 700 400'); w('sleep 300'); w('vk backspace'); shot('14-after-click')
w('mark', 'JA nihongo'); w('tip ja'); w('vk kanji'); shot('15-ja-selected', 900)
w('type nihongo'); shot('16-compose-ja'); w('vk space'); w('sleep 300'); shot('17-ja-converted'); w('vk enter'); shot('18-commit-ja')
w('mark', 'EN typing'); w('tip en'); w('sleep 600'); w('typefast hello'); shot('19-en')
w('killall', img)
print('\n'.join(L))
