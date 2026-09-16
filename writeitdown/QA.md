# Phase-two acceptance

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

Screenshots in `qa/` cover both widths and themes, plus warning recovery, reduced motion, legal pages, exit, and composition. Images were inspected individually and in contact sheets. Paper stays brighter than wall; the mobile nav fits; the warning numeral does not overprint the editor. A wrapping mobile word count found during review was fixed with `white-space: nowrap`.

The CLI's `wait` and script `run` APIs failed in this environment. Approval was obtained to use shell timing and `eval` promises instead. Browser insertion at two-second intervals kept the real sixty-second sessions alive; the model clock was never patched.

## Remaining limits

- No deployment was attempted: the supplied brief states SSH credentials are unavailable. The install bundle is the handoff, not proof of a live release.
- Real iOS Safari, its virtual keyboard, and physical IME candidate selection were not exercised. Mobile evidence is isolated Chrome emulation.
- Clipboard read permission was denied by headless Chrome. Validation checked the actual write call's complete payload and success, and the fallback's selected full text and successful copy result.
- The public contact address remains explicitly unconfigured, as requested. Hosting log retention has not been independently audited; Privacy does not claim otherwise.
