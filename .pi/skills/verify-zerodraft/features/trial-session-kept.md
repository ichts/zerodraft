# Trial session kept (60s deadline)

**What it is:** the browser trial's success path. The user clicks the door, types forward for the full 60 seconds without an 8-second silence, and the session completes: the paper returns to the bone wall with the draft, the receipt `0:00 - N words kept.` (rendered uppercase by CSS), one action `Copy text` (-> `Copied`), one link `RUN IT AGAIN`, and the caption `Nothing here is saved`.

**How to reach it:** `/index.html` -> click `a.door` (`Give it sixty seconds.`), or open `/#trial` directly.

**How to drive it:** Playwright, real time. Click `a.door`; assert `.trial-editor[role="textbox"]` is focused. Type continuously with `page.keyboard.type` (a short string every ~500ms for 60s; never pause longer than 4s or the warn/wipe path triggers). When `.trial-timer` reads `0:00`, the kept surface appears.

**Observable end state that proves it works:**

- `section.trial-kept` becomes visible; `.kept-text` contains exactly what was typed, in order.
- `.receipt-line` reads `0:00 - N words kept.` with N matching the typed word count.
- Click `.copy-door`: its text flips to `Copied`, and `navigator.clipboard.readText()` (permission granted via context) returns the draft.
- `localStorage.length === 0` afterwards - the trial persists nothing.
- ESC (or `.trial-exit`) from the kept surface returns to the landing with focus back on the door and `location.hash` cleared.
- This drive takes ~65s of real time; do not patch clocks, the kept/wipe adjudication is an absolute-deadline race.
