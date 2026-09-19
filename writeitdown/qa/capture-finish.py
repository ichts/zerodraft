"""Kept and preview evidence, using real deadlines and browser-generated feedback."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/zd-writeitdown-polish-s2'
ENV = {**os.environ, 'CHROME_DEVTOOLS_AXI_SESSION': os.environ.get('CHROME_DEVTOOLS_AXI_SESSION', 'zd-s2')}
SUFFIX = os.environ.get('QA_SUFFIX', '')

def axi(*args):
    result = subprocess.run(['chrome-devtools-axi', *args], env=ENV, text=True, capture_output=True, check=True)
    with (OUT / 'finish.txt').open('a') as log:
        log.write(args[0] + '\n' + result.stdout + result.stderr + '\n')
    return result.stdout

def ev(body, asynchronous=False):
    return axi('eval', ('async ' if asynchronous else '') + '() => {' + body + '}')

def shot(name):
    axi('screenshot', str(OUT / (name + SUFFIX + '.png')))

for width,height in [(1440,900),(390,844)]:
    axi('open', 'http://localhost:8033/writeitdown/#trial')
    axi('emulate','--viewport',f'{width}x{height}x1'+(',mobile,touch' if width==390 else ''))
    ev("document.querySelector('#restart').click(); const e=document.querySelector('#editor'); const add=()=>{e.value+='你好 world '; e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'你好 world '}));}; add(); window.qaStart=performance.now(); window.qaHeartbeat=setInterval(()=>{if(performance.now()-qaStart<57000)add();else clearInterval(qaHeartbeat);},3000); return 'real sixty-second trial started';")
    # Trusted key event; keep typing prevents CLI latency from expiring the draft.
    axi('press', 'Backspace')
    ev("return {text:document.querySelector('#editor').value,status:document.querySelector('#status').textContent};")
    ev("await new Promise(r=>setTimeout(r,Math.max(0,qaStart+60300-performance.now()))); if(room.dataset.phase!=='kept')throw new Error('Expected kept'); return {phase:room.dataset.phase,receipt:document.querySelector('#receipt').textContent,focused:document.activeElement.id};", True)
    for theme in ['light','dark']:
        ev(f"if(document.documentElement.dataset.theme!=='{theme}')document.querySelector('[data-theme-toggle]').click(); if(room.dataset.phase!=='kept')throw new Error('Kept lost during capture'); return {{width:innerWidth,overflow:document.documentElement.scrollWidth>innerWidth}};")
        shot(f'kept-{theme}-{width}')
ev("document.querySelector('#copy').click(); return 'copy';")
shot('copied-390')
axi('press','Escape')
ev("return {focused:document.activeElement.className,text:document.querySelector('#editor').value,kept:document.querySelector('#kept-text').textContent};")
shot('escape-390')
axi('console')
axi('network')
print('Real kept deadline, copy and escape captured at both sizes and themes.')
