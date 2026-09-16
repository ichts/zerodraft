"""Local browser QA through standalone chrome-devtools-axi commands only."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/zd-writeitdown-polish-s2'
ENV = {**os.environ, 'CHROME_DEVTOOLS_AXI_SESSION': os.environ.get('CHROME_DEVTOOLS_AXI_SESSION', 'zd-s2')}
SUFFIX = os.environ.get('QA_SUFFIX', '')

def axi(*args):
    result = subprocess.run(['chrome-devtools-axi', *args], env=ENV, text=True, capture_output=True, check=True)
    with (OUT / 'matrix.txt').open('a') as log:
        log.write(' '.join(args[:1]) + '\n' + result.stdout + result.stderr + '\n')
    return result.stdout

def evaluate(body, asynchronous=False):
    return axi('eval', ('async ' if asynchronous else '') + '() => {' + body + '}')

def shot(name):
    axi('screenshot', str(OUT / (name + SUFFIX + '.png')))

INSERT = "const e=document.querySelector('#editor'); e.value+='你好 world '; e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'你好 world '}));"
for width, height in [(1440, 900), (390, 844)]:
    axi('emulate', '--viewport', f'{width}x{height}x1' + (',mobile,touch' if width == 390 else ''))
    for theme in ['light', 'dark']:
        tag = f'{theme}-{width}'
        evaluate(f"document.querySelector('#exit').click(); if(document.documentElement.dataset.theme!=='{theme}') document.querySelector('[data-theme-toggle]').click(); return innerWidth;")
        shot('landing-' + tag)
        evaluate("document.querySelector('.door').click(); return location.hash;")
        shot('rest-' + tag)
        axi('eval', (ROOT / 'writeitdown/qa/input-regression.js').read_text())
        evaluate(INSERT + "return document.querySelector('#room-count').textContent;")
        shot('typing-' + tag)
        # Run real deadlines; freeze only presentation time after warn for its screenshot.
        evaluate("document.querySelector('#restart').click();" + INSERT + "await new Promise(r=>setTimeout(r,5500)); window.qaNow=performance.now.bind(performance); const held=qaNow(); performance.now=()=>held; return {phase:room.dataset.phase,numeral:document.querySelector('#room-numeral').textContent};", True)
        shot('warn-' + tag)
        evaluate(INSERT + "return {phase:room.dataset.phase,count:document.querySelector('#room-count').textContent};")
        shot('recovery-' + tag)
        evaluate("performance.now=qaNow; document.querySelector('#restart').click();" + INSERT + "await new Promise(r=>setTimeout(r,8300)); return {phase:room.dataset.phase,text:e.value,report:document.querySelector('#room-report').textContent};", True)
        shot('wipe-' + tag)
        evaluate("document.querySelector('#exit').click();return {focus:document.activeElement.className,empty:document.querySelector('#editor').value==='',overflow:document.documentElement.scrollWidth>innerWidth};")
        shot('exit-' + tag)
print('Four theme/viewport event paths and real warn/wipe deadlines captured.')
