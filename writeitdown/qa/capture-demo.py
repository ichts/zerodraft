"""Freeze observed preview frames for legible evidence, never change its deadlines."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/zd-writeitdown-polish-s2'
ENV = {**os.environ, 'CHROME_DEVTOOLS_AXI_SESSION': 'zd-s2'}

def axi(*args):
    result = subprocess.run(['chrome-devtools-axi', *args], env=ENV, text=True, capture_output=True, check=True)
    with (OUT / 'demo.txt').open('a') as log:
        log.write(args[0] + '\n' + result.stdout + result.stderr + '\n')
    return result.stdout

def ev(body):
    return axi('eval', 'async () => {' + body + '}')

for width,height,theme in [(1440,900,'dark'),(390,844,'light')]:
    axi('open','http://localhost:8033/writeitdown/')
    axi('emulate','--viewport',f'{width}x{height}x1'+(',mobile,touch' if width==390 else ''))
    ev(f"if(document.documentElement.dataset.theme!=='{theme}') document.querySelector('[data-theme-toggle]').click(); window.qaDate=Date.now; window.qaSounds=[]; const start=OscillatorNode.prototype.start; OscillatorNode.prototype.start=function(...args){{qaSounds.push(this.context.state);return start.apply(this,args);}};return 'ready';")
    # A real keyboard gesture unlocks AudioContext, without entering the trial.
    axi('press','Tab')
    for name,condition in [
        ('key', "document.querySelector('#cur').textContent==='my n'"),
        ('backspace', "document.querySelector('#demo-key').textContent==='BACKSPACE - BLOCKED'"),
        ('warn', "document.querySelector('#paper').classList.contains('warn')"),
        ('cut', "document.querySelector('#paper').classList.contains('cut')"),
        ('report', "document.querySelector('#paper').classList.contains('report')")
    ]:
        ev("Date.now=qaDate; document.querySelector('#paper').getAnimations().forEach(a=>a.cancel()); await new Promise((resolve,reject)=>{const began=performance.now();const timer=setInterval(()=>{if("+condition+"){clearInterval(timer);const held=qaDate();Date.now=()=>held;document.querySelector('#paper').getAnimations().forEach(a=>{a.pause();a.currentTime=80;});resolve();}else if(performance.now()-began>27000){clearInterval(timer);reject(new Error('preview frame timeout'));}},10);});return {phase:document.querySelector('#paper').className,key:document.querySelector('#demo-key').textContent,text:document.querySelector('#cur').textContent,sounds:qaSounds};")
        axi('screenshot',str(OUT/f'demo-{name}-{theme}-{width}.png'))
    ev("Date.now=qaDate;return qaSounds;")
print('Observed key, deny, warn, cut and report preview frames captured.')
