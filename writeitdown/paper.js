/* Write It Down - the Wheat sheet.
   [INPUT] every element marked data-paper, its laid-out size, devicePixelRatio, and the resolved
           theme on :root (light / dark); paper-render.js (loaded first) for the texture itself.
   [OUTPUT] one static texture painted into a canvas child behind that element's content: the light Wheat
            sheet's two-scale mottle and its grain (tooth, pulp, fibres, flecks); the dark sheet's one fine grain.
            The tone itself stays in CSS so a state wash can still tint the sheet.
   [POS] the single place on the web surface that mounts what the paper looks like; the room, the
         failure sheet, the kept sheet and the landing demo sheet all mount it. The room's sheet is hidden
         until the door opens, so `warm` textures it ahead of time in a worker (D-103): the click never waits
         for a 4 MP texture.
   [PROTOCOL] paint once per size/theme/DPR and never again while writing; type always sits above
              the canvas (z-index:-1 inside an isolated stacking context); values are D-069 (D-056's grain and ink).

   The field is deterministic: the same seed yields the same sheet, so the room, the demo and the
   Mac read as one paper. Nothing here animates, loops, or listens to typing. */
(function () {
  'use strict';

  const { TONES, GRAIN, SIZE, render } = window.WriteItDownPaperRender;
  const workerUrl = document.currentScript ? new URL('paper-render.js', document.currentScript.src).href : 'paper-render.js';

  const currentTheme = () => (document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light');
  const pixelRatio = () => Math.min(3, window.devicePixelRatio || 1);
  /* What a sheet of this size is painted as: the key a painted or pending texture is compared with. */
  const keyOf = (width, height, dpr, theme) =>
    `${Math.max(1, Math.round(width * dpr))}x${Math.max(1, Math.round(height * dpr))}@${dpr}/${theme}`;

  const sheets = new WeakMap();
  let resizeObserver = null;

  /* The texture worker: created on the first warm request, absent where OffscreenCanvas is (the sheet then
     paints on the page as it always has). */
  let worker;
  let nextJob = 0;
  const jobs = new Map();

  function textureWorker() {
    if (worker !== undefined) return worker;
    worker = null;
    if (typeof Worker !== 'function' || typeof OffscreenCanvas !== 'function') return worker;
    try {
      worker = new Worker(workerUrl);
      worker.onmessage = event => finish(event.data);
      worker.onerror = () => { worker.terminate(); worker = null; for (const id of [...jobs.keys()]) finish({ id, error: 'worker failed' }); };
    } catch (error) { worker = null; }
    return worker;
  }

  function finish({ id, info, bitmap, error }) {
    const job = jobs.get(id);
    jobs.delete(id);
    if (!job) { bitmap?.close(); return; }
    const { sheet, key } = job;
    if (sheet.pending !== job) { bitmap?.close(); return; }
    sheet.pending = null;
    if (error || !bitmap) { sheet.redraw(); return; }
    if (sheet.key !== key) {
      sheet.canvas.width = bitmap.width;
      sheet.canvas.height = bitmap.height;
      const ctx = contextWith(sheet.canvas);
      ctx.clearRect(0, 0, bitmap.width, bitmap.height);
      ctx.drawImage(bitmap, 0, 0);
      adopt(sheet, info, key);
    }
    bitmap.close();
  }

  const contextWith = canvas => canvas.getContext('2d');

  function adopt(sheet, painted, key) {
    if (painted.base && painted.base !== sheet.base) {
      sheet.base = painted.base;
      sheet.element.style.setProperty('--paper-tone', painted.base);
    }
    sheet.painted = painted;
    sheet.key = key;
  }

  /* Repaint only when the sheet itself changed: a new size, theme or pixel ratio. Typing changes
     none of them, so the texture is never regenerated under the writer's hands.

     The canvas stays transparent under the texture: the sheet's tone is the element's own CSS
     background, so the warn wash and the ink-in-the-paper step still tint the paper, and the
     sheet never shows a colour the texture cannot be laid over. A texture already on its way from
     the worker for exactly this size is waited for, never painted a second time on the page. */
  function paint(sheet) {
    const width = sheet.element.clientWidth;
    const height = sheet.element.clientHeight;
    if (width < 2 || height < 2) return;
    const key = keyOf(width, height, pixelRatio(), currentTheme());
    if (sheet.key === key || sheet.pending?.key === key) return;
    adopt(sheet, render(sheet.canvas, width, height, pixelRatio(), currentTheme()), key);
  }

  /* Texture a sheet that is not on screen yet, for the size it will have when it is: the worker paints it,
     the page only copies the finished bitmap. A request that is already painted or in flight is a no-op. */
  function warm(element, width, height) {
    if (!(width >= 2 && height >= 2)) return;
    const host = textureWorker();
    if (!host) return;
    const sheet = mount(element);
    const dpr = pixelRatio();
    const theme = currentTheme();
    const key = keyOf(width, height, dpr, theme);
    if (sheet.key === key || sheet.pending?.key === key) return;
    const id = nextJob += 1;
    sheet.pending = { id, key, sheet };
    jobs.set(id, sheet.pending);
    host.postMessage({ id, width, height, dpr, theme });
  }

  function mount(element) {
    if (!element || !element.dataset) return null;
    const existing = sheets.get(element);
    if (existing) return existing;
    const canvas = document.createElement('canvas');
    canvas.className = 'sheet-paper';
    canvas.setAttribute('aria-hidden', 'true');
    element.insertBefore(canvas, element.firstChild);
    const sheet = { element, canvas, painted: null, key: '', pending: null, redraw: () => paint(sheet) };
    sheets.set(element, sheet);
    if (resizeObserver) resizeObserver.observe(element);
    paint(sheet);
    return sheet;
  }

  const repaintAll = () => {
    for (const element of document.querySelectorAll('[data-paper]')) mount(element).redraw();
  };

  function mountAll() {
    for (const element of document.querySelectorAll('[data-paper]')) mount(element);
  }

  /* A size change (window resize, entering the room, a font that changes the sheet's height)
     repaints; typing never does, because typing does not change the sheet. */
  function watch() {
    resizeObserver = new ResizeObserver(repaintAll);
    for (const element of document.querySelectorAll('[data-paper]')) resizeObserver.observe(element);
    window.addEventListener('resize', repaintAll);
    new MutationObserver(repaintAll)
      .observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  }

  const api = {
    TONES,
    GRAIN,
    SIZE,
    render,
    mount,
    warm,
    mountAll,
    paintAll: repaintAll,
    canvasFor(element) { const sheet = sheets.get(element); return sheet ? sheet.canvas : null; },
    /* What the sheet was painted as, and when: size, pixel ratio, theme, and the moment it was textured. */
    paintInfo(element) { const sheet = sheets.get(element); return sheet ? sheet.painted : null; }
  };

  window.WriteItDownPaper = api;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { mountAll(); watch(); }, { once: true });
  } else {
    mountAll();
    watch();
  }
})();
