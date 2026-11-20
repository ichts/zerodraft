// Hold a page's installed fake clock still, a little ahead of where it is now.
//
// `clock.pauseAt(time)` throws "Cannot fast-forward to the past" when the page's clock has already passed `time`.
// Reading `Date.now()` and then pausing is two round trips, so on a loaded host the clock moves on between them and
// a fixed margin (50 or 100 ms) loses the race. The margin doubles until the pause lands, and the clock only ever
// moves a few hundred milliseconds, far inside the room's five-second silence.
export async function freezeClock(page, margin = 100) {
  for (;; margin *= 2) {
    try {
      await page.clock.pauseAt(await page.evaluate(ahead => Date.now() + ahead, margin));
      return;
    } catch (error) {
      if (!/past/.test(String(error)) || margin > 1600) throw error;
    }
  }
}
