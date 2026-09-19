---
name: verify-zerodraft
description: "Drive and prove the Zero Draft web surfaces: the root static landing + browser trial (index.html and the supporting static pages) and the writeitdown Playwright harness. Use when a change touches index.html, the root static pages, or writeitdown/, or when a PR needs evidence that the landing, the trial flow, or the writeitdown suite still behave the way a user sees them."
---

# verify-zerodraft

Zero Draft's web surface is pure static HTML: no backend, no build step. Verification means serving the repo over HTTP and driving it the way a user does: open the landing, enter the trial through the door, type forward, stop, watch the wipe, finish a session, copy the text. This skill gives the exact commands; the feature map under `features/` lists what to cover.

## Surfaces

- **Root static surface (on the default branch):** `index.html` (Datastar landing + `#trial` browser trial) and the supporting pages `download.html`, `checkout-success.html`, `help.html`, `privacy.html`, `refund.html`, `terms.html`, `release-notes.html`. Serve the repo root; done.
- **writeitdown site (NOT yet on the default branch):** the site and its Playwright harness (`writeitdown/package.json`, `playwright.config.mjs`, `qa/phase4.spec.mjs`) exist only on the unmerged local branch `main` and the `fm/zd-writeitdown-*` branches (7 commits past `8e4abfd`). On `origin/main`, `writeitdown/` contains only an untracked `node_modules/`. The writeitdown sections below apply the moment that branch lands; until then, running `cd writeitdown && npm test` on the default branch fails with `ENOENT: no such file or directory, open 'writeitdown/package.json'` — that is a base-condition finding to report, not a failure of this skill.

## Launch

Root static surface, from the repository root:

```bash
python3 -m http.server 8000 --bind 127.0.0.1 &
ZVD_SERVER_PID=$!
```

Ready when this returns 200 AND the marker is present:

```bash
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/index.html
curl -s http://127.0.0.1:8000/index.html | grep -c 'Give it sixty seconds.'
```

writeitdown surface (once merged): no manual server. `writeitdown/playwright.config.mjs` declares its own `webServer` (`python3 -m http.server 8015 --bind 127.0.0.1 --directory ..`) and Playwright starts and stops it. Launch is `cd writeitdown && npm install && npm test`.

## Doctor

Run these read-only checks first whenever anything looks off, before driving:

```bash
# 1. The port answers and serves OUR page (marker must be 1):
curl -s http://127.0.0.1:8000/index.html | grep -c 'Give it sixty seconds.'

# 2. The server is the process we started (not a stranger's): 
kill -0 "$ZVD_SERVER_PID" && lsof -nP -iTCP:8000 -sTCP:LISTEN

# 3. The trial runtime is intact on the page (Datastar signals on <body>):
curl -s http://127.0.0.1:8000/index.html | grep -c 'data-signals='
curl -s http://127.0.0.1:8000/datastar-pro.js | head -c 100

# 4. Playwright is resolvable for the drive helper:
node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --doctor
```

If check 1 returns 0, another app owns the port: pick another port (`python3 -m http.server 8016 ...`) and pass `--url` accordingly. Never kill a process you did not start.

## Drive

Harness: Playwright, through the shipped helper `helpers/drive-trial.mjs` (see Helpers). It resolves the `playwright` module from `writeitdown/node_modules` (present in any checkout that has run the writeitdown harness) or from `$PLAYWRIGHT_NODE_MODULES`; if neither exists it exits with the exact install command instead of a stack trace. Browser: bundled chromium if downloaded, else system Chrome via `channel: 'chrome'`.

The one command that drives the flagship flow (enter trial, type forward, prove deletion is denied, stop, watch the 8s wipe, type to rearm):

```bash
node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs \
  --url http://127.0.0.1:8000 \
  --evidence tmp/verify-zerodraft/$(date +%Y%m%d-%H%M%S)
```

Real selectors on the root surface (stable handles, do not substitute coordinates):

- door (the only way in): `a.door` with text `Give it sixty seconds.` — href `#trial`
- trial editor: `.trial-editor[role="textbox"][aria-label="Zero Draft trial editor"]` (contenteditable)
- timer: `.chrome-tr .trial-timer`; word count: `.chrome-br .label` (`N words`); rules: `.chrome-tl`; exit: `.chrome-bl .trial-exit`
- wipe report: `.report-line` with DOM text `Draft wiped - M:SS unused.` plus `.report-rearm` `Type to restart.`
- kept state: `section.trial-kept` with `.kept-text`, receipt `.receipt-line` (DOM text `0:00 - N words kept.`), `.copy-door` (`Copy text` -> `Copied`), caption `Nothing here is saved`
- machine-voice lines render in uppercase via CSS `text-transform: uppercase` on the `.system`/label classes; match DOM text (sentence case), not the styled display
- landing demo theater: `.demo-paper`, `.demo-text`, `.demo-clock`, `.demo-report` (watch-only; pointer and keystrokes do nothing on the landing)

For the supporting static pages, drive is an HTTP check plus a marker grep per page (each page is self-contained vanilla HTML; there is nothing to click that changes state):

```bash
for p in download checkout-success help privacy refund terms release-notes; do
  printf '%s: ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8000/$p.html"
done
```

writeitdown surface (once merged): `cd writeitdown && npm test` runs `qa/phase4.spec.mjs` across 12 projects (1440/390 widths x dark/light x reduced-motion on/off) against `http://127.0.0.1:8015/writeitdown/`. Drive a single project while iterating: `npx playwright test --project=1440-light-no-preference`.

## Evidence

One directory per run, named by the skill, gitignored, surviving teardown:

```
tmp/verify-zerodraft/<YYYYMMDD-HHMMSS>/
```

The helper writes `01-landing.png`, `02-trial-rest.png`, `03-typed-deny.png`, `04-wiped.png`, `05-rearmed.png`, and `drive-trial.json` (every assertion with pass/fail, captured console errors, page errors, and failed requests). For manual or extended drives, add screenshots of the action AND the resulting state, not just the final screen.

Proof standards for this repo:

- Exercise the real user path: enter through `a.door`, type with `page.keyboard`, wait in real time. Never set `_session` signals, never call `FirstLineLandingDemo.*` directly, never touch contenteditable via `evaluate` to fake typing.
- The wipe and the kept receipt are absolute-deadline races; prove them in real time, not by patching clocks.
- Verify side effects alongside the visible state: clipboard content after `Copy text` (read it back with `navigator.clipboard.readText` under a granted permission), `location.hash` after ESC/EXIT, console errors and failed asset requests (must be zero).
- The trial must persist nothing: after any session, `localStorage.length === 0` is part of the proof.
- There are no mocks to configure: the surface has no backend and no network calls beyond Google Fonts. A proof that ran offline (fonts failed) is still valid if `drive-trial.json` reports the font failure as the only failed request.

## Cleanup

Kill only what you started, then confirm the evidence survived:

```bash
kill "$ZVD_SERVER_PID"           # the PID recorded at Launch; never pkill python or kill by port
ls tmp/verify-zerodraft/         # evidence directories must still be here
```

Cleanup removes the server process and any scratch you created outside `tmp/verify-zerodraft/`. It never deletes evidence. `tmp/` is gitignored, so proofs never leak into a diff.

## Helpers

- **`helpers/drive-trial.mjs`** (executable, `chmod +x` already set): drives the flagship wipe flow end to end and writes the evidence set named above. Invocations:
  - `node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --doctor` — read-only: reports playwright resolution and browser availability, exits nonzero with the fix command if either is missing.
  - `node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --url <base> --evidence <dir>` — full drive; exit 0 with a JSON summary on pass, exit 1 naming the failed assertion on fail.
  - `--url` defaults to `http://127.0.0.1:8000`, `--evidence` defaults to a fresh `tmp/verify-zerodraft/<timestamp>`.

## Maintenance

When the app changes (new page, new trial state, writeitdown merge), run `/maintain-verification-skill` to re-audit this skill and its feature map against the code.
