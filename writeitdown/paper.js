/* Write It Down - the Note sheet.
   [INPUT] every element marked data-paper, its laid-out size, devicePixelRatio, and the resolved
           theme on :root (light / dark).
   [OUTPUT] one static texture painted into a canvas child behind that element's content: the Note
            sheet's two-scale mottle and its grain (tooth, pulp, fibres, flecks).
            The tone itself stays in CSS so a state wash can still tint the sheet.
   [POS] the single place on the web surface that defines what the paper looks like; the room, the
         failure sheet, the kept sheet and the landing demo sheet all mount it.
   [PROTOCOL] paint once per size/theme/DPR and never again while writing; type always sits above
              the canvas (z-index:-1 inside an isolated stacking context); values are D-056.

   The field is deterministic: the same seed yields the same sheet, so the room, the demo and the
   Mac read as one paper. Nothing here animates, loops, or listens to typing. */
(function () {
  'use strict';

  /* The locked sheet (D-056): tone Note, grain 70 of 100 at size 1.00. */
  const TONES = { light: '#dbe6ec', dark: '#21272a' };
  const GRAIN = 0.70;
  const SIZE = 1.00;
  const TOOTH = 44;
  const PULP = 24;

  const hexToRgb = hex => {
    const h = hex.replace('#', '');
    return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16));
  };
  const rgbToHex = rgb => '#' + rgb.map(v => Math.max(0, Math.min(255, Math.round(v)))
    .toString(16).padStart(2, '0')).join('');
  const averageTone = tone => (tone[0] + tone[1] + tone[2]) / 3;

  const prng = seed => () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  const seedFrom = text => {
    let h = 2166136261;
    for (const ch of text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
    return h >>> 0;
  };

  /* A luminance delta becomes an alpha over black or white, so pale and dark deviations stay
     symmetric and the sheet's own tone never drifts as the grain is layered on. */
  const alphaFor = (delta, tone) => {
    const pale = delta > 0;
    const room = pale ? 255 - averageTone(tone) : averageTone(tone);
    return Math.min(1, Math.abs(delta) / Math.max(10, room));
  };

  const canvasWith = (width, height) => {
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, width);
    canvas.height = Math.max(1, height);
    return canvas;
  };

  const contextWith = (canvas, alpha) => canvas.getContext('2d', { alpha: alpha !== false });

  const noiseLayer = (width, height, amount, tone, rnd) => {
    const image = new ImageData(width, height);
    const pixels = image.data;
    for (let i = 0; i < width * height; i += 1) {
      const value = ((rnd() + rnd() + rnd()) - 1.5) / 1.5 * amount;
      const grey = value < 0 ? 0 : 255;
      pixels[i * 4] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = grey;
      pixels[i * 4 + 3] = Math.round(255 * alphaFor(value, tone));
    }
    return image;
  };

  /* Low-frequency mottle: a coarse cloud and a fine one, each generated small and upscaled with
     smoothing. One scale alone reads as sponge. */
  const mottleLayer = (ctx, width, height, dpr, tone, cellCss, amplitude, salt) => {
    const cell = Math.max(2, Math.round(cellCss * dpr));
    const small = canvasWith(Math.max(2, Math.ceil(width / cell)), Math.max(2, Math.ceil(height / cell)));
    const smallCtx = contextWith(small);
    smallCtx.putImageData(noiseLayer(small.width, small.height, amplitude, tone, prng(seedFrom(salt + rgbToHex(tone)))), 0, 0);
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(small, 0, 0, width, height);
  };

  /* Short pulp fibres: a dense, low-contrast hair mat rather than a few long scratches. */
  const drawFibres = (ctx, width, height, dpr, tone, rnd, dark) => {
    const count = Math.round((width * height) / (dpr * dpr) * 0.0026);
    ctx.lineCap = 'round';
    for (let i = 0; i < count; i += 1) {
      const pale = rnd() < (dark ? 0.2 : 0.44);
      const delta = (pale ? 1 : -1) * (12 + rnd() * 34) * (dark ? 0.32 : 1) * (pale ? 0.7 : 1);
      ctx.globalAlpha = alphaFor(delta, tone) * (0.55 + rnd() * 0.45);
      ctx.strokeStyle = pale ? '#ffffff' : '#000000';
      ctx.lineWidth = (0.5 + rnd() * 0.7) * dpr;
      const x = rnd() * width;
      const y = rnd() * height;
      const length = (2 + rnd() * 7) * SIZE * dpr;
      const angle = rnd() * Math.PI * 2;
      const bow = (rnd() - 0.5) * 2.2 * dpr;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.quadraticCurveTo(
        x + Math.cos(angle) * length * 0.5 - Math.sin(angle) * bow,
        y + Math.sin(angle) * length * 0.5 + Math.cos(angle) * bow,
        x + Math.cos(angle) * length,
        y + Math.sin(angle) * length
      );
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  };

  /* Flecks: pigment, not shading. Sparse, crisp, irregular, mostly dark, a few pale chalk ones. */
  const drawFlecks = (ctx, width, height, dpr, tone, rnd, dark) => {
    const count = Math.round((width * height) / (dpr * dpr) * 0.0030 * (dark ? 0.22 : 1));
    for (let i = 0; i < count; i += 1) {
      const x = rnd() * width;
      const y = rnd() * height;
      const pale = rnd() < 0.14;
      ctx.fillStyle = pale ? '#fffaf0' : (rnd() < 0.7 ? '#241d15' : '#5b4327');
      ctx.globalAlpha = (pale ? 0.16 + rnd() * 0.24 : 0.26 + rnd() * 0.46) * (dark ? 0.5 : 1);
      const radius = (0.4 + rnd() * 1.0) * dpr * Math.max(0.7, SIZE * 0.85);
      const lobes = rnd() < 0.7 ? 1 : 2;
      for (let lobe = 0; lobe < lobes; lobe += 1) {
        const offsetX = (rnd() - 0.5) * radius * 1.6;
        const offsetY = (rnd() - 0.5) * radius * 1.6;
        ctx.beginPath();
        ctx.ellipse(x + offsetX, y + offsetY, radius * (0.45 + rnd() * 0.7),
          radius * (0.28 + rnd() * 0.5), rnd() * Math.PI, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  };

  /* Grain sits on its own layer and is composited once at the locked strength, so the sheet's
     tone is decided by the base layer alone. */
  const drawGrain = (ctx, width, height, dpr, tone, dark) => {
    const layer = canvasWith(width, height);
    const grain = contextWith(layer);
    const rnd = prng(seedFrom('tooth' + rgbToHex(tone) + SIZE));
    const lift = dark ? 0.4 : 1;
    /* Two scales of surface: tooth at device-pixel size, then a coarser pulp cloud upscaled with
       smoothing. One scale alone reads as dither or as sponge. */
    grain.putImageData(noiseLayer(width, height, TOOTH * lift, tone, rnd), 0, 0);
    const cell = Math.max(2, Math.round(dpr * 0.8));
    const pulp = canvasWith(Math.max(2, Math.ceil(width / cell)), Math.max(2, Math.ceil(height / cell)));
    contextWith(pulp).putImageData(noiseLayer(pulp.width, pulp.height, PULP * lift, tone, rnd), 0, 0);
    grain.imageSmoothingEnabled = true;
    grain.drawImage(pulp, 0, 0, width, height);
    drawFibres(grain, width, height, dpr, tone, rnd, dark);
    drawFlecks(grain, width, height, dpr, tone, rnd, dark);

    ctx.save();
    ctx.globalAlpha = GRAIN;
    ctx.drawImage(layer, 0, 0);
    ctx.restore();
  };

  const currentTheme = () => (document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light');

  const sheets = new WeakMap();
  let resizeObserver = null;

  /* The renderer: texture only, for a given CSS size, pixel ratio and theme. The canvas stays
     transparent - the sheet's tone is the element's own CSS background, so a state wash can still
     tint the paper and the sheet never shows a colour the texture cannot be laid over. */
  /* The texture's own mean, alpha-weighted: what the canvas adds to the sheet's CSS tone. */
  const textureDelta = (ctx, width, height, tone) => {
    const data = ctx.getImageData(0, 0, width, height).data;
    const count = width * height;
    const shift = [0, 0, 0];
    for (let i = 0; i < data.length; i += 4) {
      const a = data[i + 3] / 255;
      shift[0] += a * (data[i] - tone[0]);
      shift[1] += a * (data[i + 1] - tone[1]);
      shift[2] += a * (data[i + 2] - tone[2]);
    }
    return shift.map(total => total / count);
  };

  /* The locked tone wins over the texture (D-069): the sheet's own tone is shifted by exactly what the grain
     moves its mean, so the pixels on screen measure the token and not a slightly warmer or greyer paper. The
     correction rides on the sheet's tone property, so a state wash still mixes from the same base. */
  function render(canvas, width, height, dpr, theme) {
    const dark = theme === 'dark';
    const tone = hexToRgb(TONES[theme]);
    const canvasWidth = Math.max(1, Math.round(width * dpr));
    const canvasHeight = Math.max(1, Math.round(height * dpr));
    canvas.width = canvasWidth;
    canvas.height = canvasHeight;
    const ctx = contextWith(canvas);
    ctx.clearRect(0, 0, canvasWidth, canvasHeight);
    mottleLayer(ctx, canvasWidth, canvasHeight, dpr, tone, 34, 9.0, 'coarse');
    mottleLayer(ctx, canvasWidth, canvasHeight, dpr, tone, 9, 4.5, 'fine');
    drawGrain(ctx, canvasWidth, canvasHeight, dpr, tone, dark);
    const shift = textureDelta(ctx, canvasWidth, canvasHeight, tone);
    const corrected = tone.map((channel, index) => Math.max(0, Math.min(255, channel - shift[index])));
    return { width: canvasWidth, height: canvasHeight, theme, dpr, at: performance.now(), base: rgbToHex(corrected) };
  }

  /* Repaint only when the sheet itself changed: a new size, theme or pixel ratio. Typing changes
     none of them, so the texture is never regenerated under the writer's hands.

     The canvas stays transparent under the texture: the sheet's tone is the element's own CSS
     background, so the warn wash and the ink-in-the-paper step still tint the paper, and the
     sheet never shows a colour the texture cannot be laid over. */
  function paint(sheet) {
    const width = sheet.element.clientWidth;
    const height = sheet.element.clientHeight;
    if (width < 2 || height < 2) return;
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    const theme = currentTheme();
    const painted = sheet.painted;
    if (painted && painted.width === Math.round(width * dpr)
      && painted.height === Math.round(height * dpr)
      && painted.theme === theme && painted.dpr === dpr) return;
    const next = render(sheet.canvas, width, height, dpr, theme);
    if (next.base && next.base !== sheet.base) {
      sheet.base = next.base;
      sheet.element.style.setProperty('--paper-tone', next.base);
    }
    sheet.painted = next;
  }

  function mount(element) {
    if (!element || !element.dataset) return null;
    const existing = sheets.get(element);
    if (existing) return existing;
    const canvas = document.createElement('canvas');
    canvas.className = 'sheet-paper';
    canvas.setAttribute('aria-hidden', 'true');
    element.insertBefore(canvas, element.firstChild);
    const sheet = { element, canvas, painted: null, redraw: () => paint(sheet) };
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
