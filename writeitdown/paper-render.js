/* Write It Down - the sheet's texture synthesis (D-103 split it out of paper.js; D-123 made the light sheet plain white).
   [INPUT] a canvas (a page canvas or an OffscreenCanvas), a CSS size, a pixel ratio and a theme.
   [OUTPUT] the dark sheet's fine grain painted into that canvas (the light sheet is plain white and leaves it
            transparent), plus the grain-corrected tone to put under it (`render`); in a worker, the same result as
            an ImageBitmap for each request message.
   [POS] the pure half of the paper: no DOM, no layout, no timing. paper.js loads it as a classic script and
         starts it as a worker so the room's sheet can be textured off the main thread before the door is
         clicked; the deterministic field and every locked value (D-069, D-073, D-093) live here and nowhere else.
   [PROTOCOL] same seed, same sheet, in the page or in the worker. Touches no global but WriteItDownPaperRender. */
(function (scope) {
  'use strict';

  /* The sheet tones: plain white in light (D-123, the sheet of the first white-and-ink identity), warm charcoal in dark. */
  const TONES = { light: '#ffffff', dark: '#342e24' };
  const SIZE = 1.00;
  /* The dark sheet is flat warm charcoal with one very fine grain and nothing else (D-093): peak +-3 levels,
     no mottle, pulp, fibres or flecks, so no pixel lifts far enough to cost a text role its 7:1. */
  const DARK_GRAIN = 3;

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
    const canvas = typeof document === 'undefined' ? new OffscreenCanvas(1, 1) : document.createElement('canvas');
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

  /* The dark sheet's whole texture: tooth at device-pixel size, at the full layer strength. */
  const drawDarkGrain = (ctx, width, height, tone) => {
    const rnd = prng(seedFrom('tooth' + rgbToHex(tone) + SIZE));
    const layer = canvasWith(width, height);
    contextWith(layer).putImageData(noiseLayer(width, height, DARK_GRAIN, tone, rnd), 0, 0);
    ctx.drawImage(layer, 0, 0);
  };

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

  /* The locked tone wins over the texture (D-073): the sheet's own tone is shifted by exactly what the grain
     moves its mean, so the pixels on screen measure the token and not a slightly warmer or greyer paper. The
     correction rides on the sheet's tone property, so a state wash still mixes from the same base. */
  function render(canvas, width, height, dpr, theme) {
    const tone = hexToRgb(TONES[theme]);
    const canvasWidth = Math.max(1, Math.round(width * dpr));
    const canvasHeight = Math.max(1, Math.round(height * dpr));
    canvas.width = canvasWidth;
    canvas.height = canvasHeight;
    const ctx = contextWith(canvas);
    ctx.clearRect(0, 0, canvasWidth, canvasHeight);
    if (theme === 'dark') drawDarkGrain(ctx, canvasWidth, canvasHeight, tone);
    const shift = theme === 'dark' ? textureDelta(ctx, canvasWidth, canvasHeight, tone) : [0, 0, 0];
    const corrected = tone.map((channel, index) => Math.max(0, Math.min(255, channel - shift[index])));
    return { width: canvasWidth, height: canvasHeight, theme, dpr, at: performance.now(), base: rgbToHex(corrected) };
  }


  const api = { TONES, SIZE, render };
  scope.WriteItDownPaperRender = api;

  /* As a worker: one message in, one texture out. The bitmap is transferred, never copied. */
  if (typeof document === 'undefined' && typeof scope.postMessage === 'function') {
    scope.onmessage = event => {
      const { id, width, height, dpr, theme } = event.data;
      try {
        const canvas = new OffscreenCanvas(1, 1);
        const info = render(canvas, width, height, dpr, theme);
        const bitmap = canvas.transferToImageBitmap();
        scope.postMessage({ id, info, bitmap }, [bitmap]);
      } catch (error) {
        scope.postMessage({ id, error: String(error && error.message || error) });
      }
    };
  }
})(typeof self !== 'undefined' ? self : this);
