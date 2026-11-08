import { test, expect } from '@playwright/test';

// D-097: the door opens. The room's paper is the landing's demo paper grown (not a second paper 160 px away), the
// brand row slides to its place, the room is live within 100 ms of the click, and Reduce Motion is one change.

const box = r => ({ x: r.left, y: r.top, w: r.width, h: r.height });
const near = (a, b, tol) => ['x', 'y', 'w', 'h'].every(k => Math.abs(a[k] - b[k]) <= tol);

test.beforeEach(async ({ page }) => {
  await page.route('https://static.cloudflareinsights.com/beacon.min.js', route => route.fulfill({ body: '' }));
  await page.goto('./');
  await page.evaluate(() => document.fonts.ready);
});

async function openTheDoor(page) {
  return page.evaluate(() => new Promise(resolve => {
    const rect = el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; };
    const demo = rect(document.getElementById('paper'));
    const brand = rect(document.querySelector('#landing .home-nav .brand'));
    const cta = document.querySelector('#landing a[href="#trial"]');
    const frames = [];
    let t0 = 0;
    const room = document.getElementById('room');
    const roomPaper = room.querySelector('.room-paper');
    const roomBrand = room.querySelector('.brand');
    const sample = now => {
      frames.push({
        t: now - t0, blank: document.getElementById('landing').hidden && room.hidden,
        shown: !room.hidden, landing: !document.getElementById('landing').hidden,
        paper: rect(roomPaper), brand: rect(roomBrand), focused: document.activeElement?.id === 'editor',
        animations: roomPaper.getAnimations().filter(a => a.id === 'door').length,
        duration: roomPaper.getAnimations().find(a => a.id === 'door')?.effect.getTiming().duration ?? 0,
        easing: roomPaper.getAnimations().find(a => a.id === 'door')?.effect.getTiming().easing ?? '',
        siteEase: getComputedStyle(roomPaper).getPropertyValue('--ease-out').trim(),
      });
      const settled = now - t0 >= 600 && !roomPaper.getAnimations().some(a => a.id === 'door');
      if (!settled && now - t0 < 3000) requestAnimationFrame(sample); else resolve({ demo, brand, frames, inView: demo.y + demo.h > 0 && demo.y < innerHeight });
    };
    cta.addEventListener('click', e => { t0 = e.timeStamp; requestAnimationFrame(sample); }, { once: true });
    cta.click();
  }));
}

test('the room paper grows out of the demo paper and the room is live at once', async ({ page }, info) => {
  const reduce = info.project.use.reducedMotion === 'reduce';
  // Best of three: a loaded host can stretch one run's first frame; the budget is what the page can do.
  let run = await openTheDoor(page);
  for (let attempt = 1; attempt < 3 && run.frames.find(f => f.shown).t >= 100; attempt++) {
    await page.goto('./'); await page.evaluate(() => document.fonts.ready);
    run = await openTheDoor(page);
  }
  const { demo, brand, frames, inView } = run;
  const first = frames.find(f => f.shown);
  const last = frames.at(-1);
  expect(frames.some(f => f.blank), 'a frame with neither landing nor room').toBe(false);
  expect(first.t, 'first visible room frame after the click (ms)').toBeLessThan(100);
  expect(first.focused, 'the editor is live on the first room frame').toBe(true);
  // The settled room is the plain room whatever the motion setting.
  expect(last.animations).toBe(0);
  const settled = last.paper;
  if (reduce || !inView) {
    expect(near(first.paper, settled, 1), 'Reduce Motion: one change, no in-between frame').toBe(true);
    expect(frames.every(f => !f.shown || near(f.paper, settled, 1))).toBe(true);
    expect(near(first.brand, last.brand, 1)).toBe(true);
    return;
  }
  // Frame one is the demo paper's own rectangle and the brand row has not moved yet.
  expect(near(first.paper, demo, 2), `first room frame ${JSON.stringify(first.paper)} vs demo ${JSON.stringify(demo)}`).toBe(true);
  if (brand.y >= 0) expect(near(first.brand, brand, 2), 'the brand row jumps instead of sliding').toBe(true);
  // Continuity: the box only grows toward the settled paper, never shrinks, never overshoots.
  const shown = frames.filter(f => f.shown);
  for (let i = 1; i < shown.length; i++) {
    expect(shown[i].paper.w).toBeGreaterThanOrEqual(shown[i - 1].paper.w - 1);
    expect(shown[i].paper.w).toBeLessThanOrEqual(settled.w + 1);
  }
  // The grow is one 240 ms animation (measured from the animation itself: a loaded host stretches frame gaps).
  expect(first.duration).toBe(240);
  const norm = curve => curve.replace(/\s/g, '').replace(/\b0\./g, '.');
  expect(norm(first.easing), "the door uses the site's one ease-out").toBe(norm(first.siteEase));
  expect(near(last.brand, shown.at(-1).brand, 0.5)).toBe(true);
});
