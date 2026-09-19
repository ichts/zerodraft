# Landing demo theater

**What it is:** the landing holds four objects - logotype (with the `MAC RELEASE ->` link), headline, the door (`Give it sixty seconds.`), and the demo paper. The demo paper is watch-only theater: a scripted loop at real speed types a sample draft (~7s), holds 5s of silence, runs the warn wash with the 3-2-1 step numeral, wipes at the eighth second, holds the machine report 2s, then rearms at 1:00.

**How to reach it:** serve the repo root (see Launch in `../SKILL.md`) and open `/index.html`. No interaction needed; the loop runs on its own below the fold of the hero.

**How to drive it:**

```bash
node - <<'EOF'  # with playwright resolved as in helpers/drive-trial.mjs
// goto /index.html, wait for .demo-text to gain text, then wait for
// .demo-report to unhide (wipe), screenshotting before and after.
EOF
```

With Playwright: `page.goto(url + '/index.html')`, `await page.locator('.demo-text').waitFor()`, poll until `.demo-text` has non-empty text (typing phase), then poll until `.demo-report:not([hidden])` appears (wipe phase). The full loop is about 20s of real time.

**Observable end state that proves it works:**

- `.demo-text` fills with the sample draft while `.demo-clock` counts down from 1:00.
- After the wipe, `.demo-report` is visible with a `Draft wiped - M:SS unused.` machine line (CSS-uppercased), then the clock rearms at 1:00 and the loop repeats.
- Pointer clicks and keystrokes anywhere on the landing outside `a.door` change nothing (the landing has no second entrance).
- Under `prefers-reduced-motion: reduce` the paper is fully static: sample text already typed, clock at 1:00.
