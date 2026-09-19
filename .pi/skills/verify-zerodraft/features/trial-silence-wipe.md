# Trial silence wipe + rearm

**What it is:** the failure path and the product's core consequence. Inside the trial, 5 seconds of silence starts the warn (bone/paper wash ramps, step numeral 3-2-1); at 8 seconds of silence the draft is wiped and the machine report lands: `Draft wiped - M:SS unused. Type to restart.` (rendered uppercase by CSS). The editor stays armed: the next keystroke starts a fresh session with no navigation. The forward-only contract also lives here: Backspace/Delete, paste, cut, drop, undo, and selection replacement are denied (2px shake + 90ms red hairline + SR line) and the text does not change.

**How to reach it:** `/index.html` -> `a.door`, type anything, then stop.

**How to drive it:** this is exactly what `helpers/drive-trial.mjs` runs (see `../SKILL.md`):

```bash
node .pi/skills/verify-zerodraft/helpers/drive-trial.mjs --url http://127.0.0.1:8000 --evidence tmp/verify-zerodraft/<run>
```

The helper types a sentence, presses Backspace (asserts the text is unchanged and the deny body fired), then waits in real time for the wipe.

**Observable end state that proves it works:**

- `.report-line` becomes visible matching `Draft wiped - \d+:\d{2} unused` (case-insensitive; CSS uppercases the display) within ~10s of the last keystroke, alongside `.report-rearm` (`Type to restart.`).
- The wiped draft text is gone from the editor.
- The Backspace denial is proven: editor text before and after the keypress is identical.
- Typing again rearms: the report hides, `.chrome-br` word count resumes from the new text, `.trial-timer` restarts at 1:00.
- `localStorage.length === 0` afterwards.
