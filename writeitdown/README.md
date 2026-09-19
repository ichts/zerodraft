# WRITE_IT_DOWN

A static browser writing room. Open `index.html#trial` over HTTP to enter directly, or use the landing CTA.

```sh
python3 -m http.server 8000
# http://localhost:8000/writeitdown/
node --test writeitdown/session.test.mjs
cd writeitdown && npm ci && npx playwright test
```

The browser suite uses installed Google Chrome, starts its own local server, and accelerates the session/demo clocks. It captures all acceptance states across two viewport sizes, both themes, and both motion preferences. Playwright is a development-only dependency; installation does not ship Node or npm assets. Set `WID_QA_OUTPUT` to choose the evidence directory.

The first input starts sixty seconds. Five seconds of silence warns; eight wipes the draft. The earlier deadline wins, and a tie wipes. Kept text remains available to copy until the user leaves. No draft is stored or sent anywhere.

The watch-only preview has its own clock. It types the original private messy draft at a human rhythm - uneven keystrokes, word and punctuation pauses - catches its own typo, deletes it with three visible backspaces, and retypes it correctly before stopping and wiping. No keystroke subtitles appear. The wipe report is centered in the paper. The pacing script lives in `demo-timeline.mjs`: a seeded, deterministic timeline shared with the qa specs, so fake-clock tests seek exact beats. `feedback.js` powers the trial's deny shake and tone: 420ms movement, then a 180ms still hold, with the hairline visible throughout. Repeated blocked keys do not restart the feedback. The pause is visual, not an input lock or a timer extension. Sound needs a prior browser gesture. Reduced motion keeps a static draft and disables spatial shaking.

The writing viewport shows the active line at full opacity in the center of a fixed aperture, with two previous lines fading above it. The aperture sits at 32% of the paper height, matching the demo's upper-third placement rather than the trial's midpoint. Native textarea padding and a CSS mask provide this without a mirrored draft or a custom text layout engine. It follows the end automatically but cannot be manually scrolled. The full draft remains available in the kept result.

`session.mjs` owns the real deadline rules and the count: Unicode words, with Han characters counted individually. Punctuation, emoji and whitespace do not count. This is a writing-unit count, not a linguistic Chinese word count. The room counter's tooltip and accessible description explain it. `room.js` connects the session to the browser editor. `theme.js` stores only the appearance preference. The default follows the system.

## Deploy

Transfer and extract the tested deployment bundle on the target host, then run `sh writeitdown/install.sh` as root. It writes only the ten production files under `/var/www/writeitdown.app/`, preserves an existing `index.html.dc-bak2`, and creates that backup from the current index if absent. It does not touch server configuration or remove other files.

The legal pages disclose Google Fonts requests and possible hosting access logs. A public support/privacy contact is deliberately marked as not configured, not replaced with an invented address.

See `QA.md` for validation evidence and limits.
