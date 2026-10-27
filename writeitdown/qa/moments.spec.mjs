// The three landing moment cards (#core .mo: writing, warning, deleted) measured as rendered text.
// Every text element on a card is checked against the card's own ground, in light and dark, at 1440 and 390.
// Floors follow WCAG 2.x: 4.5:1 for normal text, 3:1 for large text (24 px, or 18.66 px bold).
// Fails on the shipped `.mo .r` line (`--mute` on `--red-deep`: 3.72:1 light) before it was repainted (D-071).
import { test, expect } from '@playwright/test';

const CAPTURE_DIR = process.env.WID_CAPTURE_DIR;

// The text roles each card carries, in document order. A new text element must be added here on purpose.
const ROLES = {
  m1: ['small', 't'],
  m2: ['small', 'n'],
  m3: ['small', 't', 'r'],
};

const channels = colour => colour.match(/[\d.]+/g).slice(0, 3).map(Number);

const luminance = ([r, g, b]) => {
  const linear = value => {
    const s = value / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
};

const contrast = (a, b) => {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (light + 0.05) / (dark + 0.05);
};

const readCard = (page, name) => page.evaluate(cls => {
  const card = document.querySelector(`#core .mo.${cls}`);
  const style = getComputedStyle(card);
  const grounds = style.backgroundImage === 'none' ? [style.backgroundColor] : style.backgroundImage.match(/rgba?\([^)]*\)/g);
  const texts = [...card.querySelectorAll('*')]
    .filter(el => [...el.childNodes].some(node => node.nodeType === Node.TEXT_NODE && node.textContent.trim()))
    .map(el => {
      const text = getComputedStyle(el);
      return {
        tag: el.tagName.toLowerCase(),
        cls: el.className,
        text: el.textContent.replace(/\s+/g, ' ').trim(),
        colour: text.color,
        size: parseFloat(text.fontSize),
        weight: Number(text.fontWeight),
        visible: el.getClientRects().length > 0,
      };
    });
  return { grounds, texts };
}, name);

const floorFor = ({ size, weight }) => (size >= 24 || (size >= 18.66 && weight >= 700) ? 3 : 4.5);

test('every text role on the three landing moment cards clears its WCAG floor on its own ground', async ({ page }, info) => {
  await page.goto('index.html');
  await page.evaluate(() => document.fonts.ready);
  for (const cls of Object.keys(ROLES)) {
    const card = await readCard(page, cls);
    expect(card.grounds.length, `${cls}: has a readable ground`).toBeGreaterThan(0);
    for (const ground of card.grounds) expect(ground, `${cls}: ground is opaque`).toMatch(/^rgb\(/);
    const roles = card.texts.filter(text => text.visible).map(text => text.cls || text.tag);
    expect(roles, `${cls}: every text element is a known role`).toEqual(ROLES[cls]);
    for (const text of card.texts) {
      expect(text.colour, `${cls} ${text.tag}: text is opaque`).toMatch(/^rgb\(/);
      const foreground = channels(text.colour);
      const floor = floorFor(text);
      for (const ground of card.grounds) {
        const ratio = contrast(foreground, channels(ground));
        const label = `${cls} ${text.cls || text.tag} "${text.text}" ${text.size}px/${text.weight}`;
        expect(ratio, `${label} is ${ratio.toFixed(2)}:1 on ${ground}, floor ${floor}:1`).toBeGreaterThanOrEqual(floor);
      }
    }
  }
  if (CAPTURE_DIR) {
    await page.locator('#core .moments').screenshot({ path: `${CAPTURE_DIR}/${info.project.name}-moments.png` });
  }
});
