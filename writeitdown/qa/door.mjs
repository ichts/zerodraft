// The door (D-097) grows the room paper for GROW_MS; geometry specs wait for it before they measure. The route
// runs on hashchange, a task after the click, so wait for the room to show before waiting on its animations.
export async function doorSettled(page) {
  await page.waitForFunction(() => !document.getElementById('room').hidden);
  await page.evaluate(() => Promise.all(document.getAnimations().filter(a => a.id === 'door').map(a => a.finished.catch(() => {}))));
}
