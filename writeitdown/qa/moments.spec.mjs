// The three landing moment cards (#core .mo: writing, warning, deleted) measured as rendered text.
// Every text element on a card is checked against the card's own ground, in light and dark, at 1440 and 390.
// Floors follow WCAG 2.x: 4.5:1 for normal text, 3:1 for large text (24 px, or 18.66 px bold).
import { test, expect } from '@playwright/test';

const CAPTURE_DIR = process.env.WID_CAPTURE_DIR;

// The text roles each card carries, in document order. A new text element must be added here on purpose.
const ROLES = {
  writing: ['small', 't'],
  warning: ['small', 'n'],
  deleted: ['small', 't', 'r'],
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

const readCard = (page, name) => page.evaluate(index => {
  const card = document.querySelectorAll('#core .mo')[index];
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
}, Object.keys(ROLES).indexOf(name));

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

// D-124: the three cards are one neutral ground; the warning is told by the numeral, not by a tinted card.
test('the three moment cards share the sheet ground, with no wash and no gradient', async ({ page }) => {
  await page.goto('index.html');
  const cards = await page.evaluate(() => {
    const read = name => getComputedStyle(document.querySelector('.home')).getPropertyValue(name).trim();
    const probe = value => { const i = document.createElement('i'); i.style.color = value; document.body.append(i); const c = getComputedStyle(i).color; i.remove(); return c; };
    return {
      grounds: [...document.querySelectorAll('#core .mo')].map(card => {
        const style = getComputedStyle(card);
        return { colour: style.backgroundColor, image: style.backgroundImage };
      }),
      sheet: probe(read('--sheet')),
      washes: [probe(read('--paper-wash')), probe(read('--paper-wash-deep'))],
    };
  });
  expect(cards.grounds).toHaveLength(3);
  for (const ground of cards.grounds) {
    expect(ground.image, 'no gradient on a moment card').toBe('none');
    expect(ground.colour, 'every moment card is the sheet').toBe(cards.sheet);
    expect(cards.washes, 'no moment card wears a wash').not.toContain(ground.colour);
  }
});
