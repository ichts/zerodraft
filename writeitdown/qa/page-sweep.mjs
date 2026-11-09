// The budget for a test that walks every shipped page.
//
// A sweep is a fixed sequence of navigations done inside one test body, so its budget has to scale with
// its page count instead of borrowing the harness's flat 30 s. With the flat budget a sweep fails as a
// *test* timeout whenever the machine is busy, and the error names nothing useful.
//
// Measured on this machine (2026-11-09, 390x844, a fresh browser context per test, which is what
// Playwright gives every test, with the eight suite projects and other agent work running):
//
//   create context + page                                0.6 s p50, 2.3 s in the run that timed out
//   one navigation, quiet machine                        0.02 - 0.13 s
//   one navigation, load average ~25                     0.7 s worst page
//   one navigation, load average ~160                    1.9 s worst page
//   one navigation, load average ~70                     5.8 s worst, and censored: 5 s was a ceiling
//   13 navigations, load average ~25                     2.5 s p50, 3.4 s max
//   13 navigations, load average ~160                    2.6 s p50, 4.3 s max
//   13 navigations + 13 link clicks, load average ~25     6.1 s p50, 9.0 s max
//   13 navigations + 13 link clicks, load average ~160    7.5 s p50, 10.8 s max
//   the same sweep in the run that failed, 31.6 s        53 steps, no single step above 1.7 s
//
// That last line is the whole problem: the sweep was slow in aggregate, not stuck, so the sum of its
// navigations is the thing to budget for and no per-step limit can express it. PER_PAGE_MS is that
// allowance per page of the walk, sized for the most expensive shape (a visit plus a click-through) and
// about five times the slowest sweep ever observed here, so a merely-slow machine cannot fail one.
//
// Deliberately no per-navigation timeout. At load average ~70 a single navigation already ran past 5.8 s,
// so any ceiling tight enough to catch a hang would reintroduce the intermittent failure this exists to
// remove. The sweep budget is the only gate; a stuck sweep still fails, with a retained trace naming the
// page it stopped on.
export const PER_PAGE_MS = 10_000;
export const SETUP_MS = 20_000;

export const sweepTimeout = pageCount => SETUP_MS + pageCount * PER_PAGE_MS;

// Every assertion in a sweep reads the parsed DOM, its computed style and its geometry. These pages ship
// no <img>, and across all thirteen the computed style and the footer geometry are identical at
// domcontentloaded and at load (measured over six passes), so waiting for the load event only waits for
// fonts the sweep does not read.
export const openPage = (page, path) => page.goto(path, { waitUntil: 'domcontentloaded' });

// A sweep that counts font requests must wait for the font loads it counts: `load` does not wait for
// webfonts, so the old sweep could read its request log before a face had been asked for.
export const fontsSettled = page => page.waitForFunction(() => document.fonts.status === 'loaded');
