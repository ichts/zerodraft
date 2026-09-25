# Current acceptance

This pass centers the trial writing aperture on the paper instead of pinning it to the upper third. The active-line center is y=450 at 1440x900 and y=422 at 390x844, matching the paper center at both widths. The editor's computed mask keeps mirrored alpha stops around the 40%-60% clear band in both themes.

The landing demo now loads its module graph from the deploy bundle, including `demo-timeline.mjs`; a hard-load browser regression proves that `#cur` receives the first typed character. The shortened timeline completes in about 12.7 seconds, uses two quick backspaces for the correction, and holds the wipe report for one second before looping. Deny feedback is a lighter 280ms beat and reduced motion still removes spatial movement.

`cd writeitdown && npm ci && npx playwright test` passes 44 tests and skips the four expected reduced-motion correction snapshots across eight viewport/theme/motion projects. The suite checks center geometry, mirrored mask stops, hard-load demo typing, correction pacing, shortened deny feedback, warning, recovery, wipe, kept, copy, Escape, console errors and failed assets. `node --test writeitdown/session.test.mjs`, `sh -n writeitdown/install.sh`, and `git diff --check` also pass.

Real OS IME, iOS Safari/virtual keyboard and human audio evaluation remain unverified. This is a local-only handoff, not a deployment.

# Phase-four acceptance (historical)

Phase four is a local-only tested bundle, not a live deployment. Final acceptance is executable: from `writeitdown/`, run `npx playwright test`. All 24 specs pass across eight viewport/theme/motion projects in 20.8 seconds; 108 screenshots are captured by the specs and inspected in contact sheets. The suite asserts the native input paths, no writing scrollbar/page overflow, three visible text lines, opaque active band, writing line near 39% of viewport height, historical sample, absent subtitles, centered report, 600ms deny with its final still hold, and reduced-motion behavior. Eight mocked sixty-second sessions reach kept and verify clipboard contents and Escape. Script exceptions, failed application assets, and non-GET requests fail acceptance. Google Chrome and `npm ci` are the prerequisites; there is no runtime dependency change.

The phase-four handoff includes `REPORT.html`, executable specs, contact sheets, individual screenshots, and command logs. Earlier real-time browser runs below remain supporting reproduction evidence, not the final acceptance workflow.

- Reproduced the textarea scrollbar with native insertion of 378 multilingual writing units: 342px client height versus 765px content. Short drafts hid the overflow. Fixed-height masked text and symmetric padding replace content-driven growth, keeping the active line centered and two previous lines faded.
- Restored the sample verbatim from `4bef933:writeitdown/demo.js`; removed all key subtitles and centered the demo report.
- Deny feedback lasts 600ms (420ms shake, 180ms still hold). Input and deadline clocks are never paused. Repeats do not restart the shake; reduced motion retains the hairline without movement.
- Eight session unit tests pass. Run `qa/input-regression.js` and `qa/zen-regression.js` as browser evaluation functions while in `#trial`: 15 input-path and 14 zen checks pass across 1440x900/390x844, both themes, normal/reduced motion.
- Browser matrix covers empty, focused, long Latin/CJK/emoji text, denied deletion/cut, warn, real recovery, wipe, exit, and kept. Four real full-minute sessions cover both widths and motion preferences; each kept result is captured in both themes. Copy and Escape pass. Demo typing/warn/cut/report frames are captured in both sizes and themes.
- Presentation frames freeze an observed clock or animation to survive CLI screenshot latency. Real wipe/recovery and full-minute checks use unchanged session clocks. Initial stale typing/recovery captures were replaced after visual inspection caught CLI delays.
- Real OS IME, iOS Safari/virtual keyboard, and human audio evaluation remain unverified. Synthetic composition and Chrome viewport tests are not substitutes for those checks.

# Phase-three acceptance (historical)

Phase three was validated locally on September 16, 2026. See [`data/zd-writeitdown-polish-s2/REPORT.md`](../data/zd-writeitdown-polish-s2/REPORT.md) for the multilingual counting rule, all eight requested changes, checks, screenshots and limits. There are now 8 deterministic tests and 10 installed production files. Browser evidence covers 1440x900 and 390x844, both themes and reduced motion, with real full-minute kept runs. The deployment handoff is `writeitdown-phase3-deploy-bundle.tar.gz`; local validation does not claim a live release.

# Phase-two acceptance (historical)

Validated locally on September 16, 2026. Deployment and HTTPS acceptance remain the supervisor's responsibility.

## Automated checks

- `node --test writeitdown/session.test.mjs`: 7 passing tests. Covers idle, 5s warning, recovery, 8s wipe/restart, real 60s deadline, delayed ticks, wipe-winning ties, late input, whitespace-only drafts, and labels.
- `node --check` on all browser JavaScript: passed.
- `sh -n writeitdown/install.sh` and `git diff --check`: passed.
- Installer exercised in a temporary sandbox with its target path substituted. All nine production files copied; original index backed up; repeat installation preserved the backup; a destination symlink was rejected without writing its target.
- All four public HTML pages and five assets returned HTTP 200 from the local server.

## Browser acceptance

Used separate headless Chrome profiles through `chrome-devtools-axi`, never the desktop browser. Exact viewports were 1440x900 and 390x844. The latter used mobile/touch emulation, not window resize: Chrome's minimum ordinary window width is 500px.

- CTA enters the actual `#trial` room and focuses its editor. Direct `#trial` entry also works.
- Native browser text insertion starts the independent clock. Multiple full 60-second runs at both widths reached `kept`, with no clock overrides or shortened deadlines.
- `You wrote it down.`, the full draft, the receipt, and COPY TEXT appear. Clipboard writes received the exact full draft and resolved; the button became COPIED. Forcing the Clipboard API to reject exercised successful `execCommand('copy')` fallback with the same full text.
- Warning starts at five seconds. Typing during warning preserves the original text and removes the warning. Eight seconds of silence clears the editor and displays the real unused-time report. Typing restarts with a new minute.
- Actual Backspace was blocked. Browser event checks covered Delete, undo/redo, cut, paste, drop, replacement text, and selection replacement. Selection typing appended rather than replacing prior text.
- Synthetic composition events retained Chinese text and reset silence through a warning. This is not a claim of physical OS IME testing.
- ESC and EXIT discard the active/kept text and return focus to the CTA.
- Both modes were inspected on landing, room, warning, wipe, and kept/copied surfaces. Stored preference survived page navigation. With empty storage, system appearance selected the default and subsequent system changes were followed. The only storage key was `writeitdown-theme`.
- Privacy, Terms, and Support opened. Legal-page theme switching worked. Measured document width equaled viewport width at 1440 and 390.
- A second isolated Chrome instance with reduced motion forced on showed a static preview and a full, non-transitioning warning wash at five seconds.
- Final product-page console had no errors. Network requests were limited to static site assets and the disclosed Google Fonts resources; no writing requests were made.

Screenshots in `qa/` covered both widths and themes, plus warning recovery, reduced motion, legal pages, exit, and composition; images were inspected individually and in contact sheets at QA time. The PNG binaries were stripped before this history entered the repository, so they survive only in the pre-transplant local commits. Paper stays brighter than wall; the mobile nav fits; the warning numeral does not overprint the editor. A wrapping mobile word count found during review was fixed with `white-space: nowrap`.

The CLI's `wait` and script `run` APIs failed in this environment. Approval was obtained to use shell timing and `eval` promises instead. Browser insertion at two-second intervals kept the real sixty-second sessions alive; the model clock was never patched.

## Remaining limits

- No deployment was attempted: the supplied brief states SSH credentials are unavailable. The install bundle is the handoff, not proof of a live release.
- Real iOS Safari, its virtual keyboard, and physical IME candidate selection were not exercised. Mobile evidence is isolated Chrome emulation.
- Clipboard read permission was denied by headless Chrome. Validation checked the actual write call's complete payload and success, and the fallback's selected full text and successful copy result.
- The public contact address remains explicitly unconfigured, as requested. Hosting log retention has not been independently audited; Privacy does not claim otherwise.
