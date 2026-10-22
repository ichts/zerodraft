# WRITE_IT_DOWN

A static browser writing room. Open `index.html#trial` over HTTP to enter directly, or choose Give it 60 seconds on the landing. The landing nav's Download for Mac pill opens the Mac free-trial download page.

```sh
python3 -m http.server 8000
# http://localhost:8000/writeitdown/
node --test writeitdown/session.test.mjs
cd writeitdown && npm ci && npx playwright test
```

The browser suite uses installed Google Chrome, starts its own local server, and accelerates the session/demo clocks. It captures all acceptance states across two viewport sizes, both themes, and both motion preferences. Playwright is a development-only dependency; installation does not ship Node or npm assets. Set `WID_QA_OUTPUT` to choose the evidence directory.

The first input starts sixty seconds. Five seconds of silence warns; eight wipes the draft. The earlier deadline wins, and a tie wipes. Kept text remains available to copy until the user leaves. No draft is stored or sent anywhere.

The watch-only preview has its own clock. It types the original private messy draft at a human rhythm - uneven keystrokes, word and punctuation pauses - catches its own typo, deletes it with three visible backspaces, and retypes it correctly before stopping and wiping. No keystroke subtitles appear. The wipe report is centered in the paper. The pacing script lives in `demo-timeline.mjs`: a seeded, deterministic timeline shared with the qa specs, so fake-clock tests seek exact beats. `feedback.js` powers the trial's deny shake and tone: 420ms movement, then a 180ms still hold, with the hairline visible throughout. Repeated blocked keys do not restart the feedback. The pause is visual, not an input lock or a timer extension. Sound needs a prior browser gesture. Reduced motion keeps a static draft and disables spatial shaking.

The writing viewport shows the active line at full opacity in the center of a fixed aperture, with two previous lines fading above it. The trial anchors the writing line at about 39% of the viewport height, leaving room for the clock in short windows; earlier lines rise as the draft grows. Native textarea padding and a CSS mask provide this without a mirrored draft or a custom text layout engine. It follows the end automatically but cannot be manually scrolled. The full draft remains available in the kept result.

`session.mjs` owns the real deadline rules and the count: Unicode words, with Han characters counted individually. Punctuation, emoji and whitespace do not count. This is a writing-unit count, not a linguistic Chinese word count. The room counter's tooltip and accessible description explain it. `room.js` connects the session to the browser editor. `theme.js` stores only the appearance preference. Light is the default; dark is a stored toggle choice.

## Deploy

Transfer and extract the tested deployment bundle on the target host, then run `sh writeitdown/install.sh` as root. It writes only the production files listed in `install.sh` under `/var/www/writeitdown.app/`, preserves an existing `index.html.dc-bak2`, and creates that backup from the current index if absent. It does not touch server configuration or remove other files.

The legal pages disclose Google Fonts requests, possible hosting access logs, and the Mac waitlist. The public contact is contact@trefoilstudio.com (Trefoil Studio).

### Mac download release

`download/index.html` (served at `/download/`) offers the free-trial DMG at `https://writeitdown.app/download/Write-It-Down-1.0.dmg`. That disk image must be the Mac trial PR 42 build (3 free sessions, then the license gate). Do not install this site against a paid-only binary. Upload the signed DMG into `/var/www/writeitdown.app/download/` first, replace the pending SHA-256 line with the published checksum (one line; the template sits in the comment above it), and pass `npm run release-check -- --download --live` before installing the site. Checkout stays closed; that gate is below.

### Mac page release order

`mac.html` describes the Mac app (3 free sessions, then a USD 4.99 one-time license for 2 Macs with a 14-day refund, whose purchase is not open yet): the free-trial download and the web room are its working CTAs, Buy is a visible "coming soon" notice, and the waitlist form posts to `/api/waitlist` (`services/waitlist/`). `waitlist.js` only enhances the form; without JavaScript the collector's 303 fragment is revealed by `:target`.

1. Deploy the Go collector using [`services/waitlist/README.md`](../services/waitlist/README.md) behind the site's reverse proxy. `install.sh` refuses to install the site until `https://writeitdown.app/api/waitlist/health` (override with `WAITLIST_HEALTH_URL`) answers `ok`. This is only a preflight: submit one real test address from the page, confirm its stored line, then remove it. Neither the collector's presence in this repository nor a local test proves deployment.
2. Send a test email to and from contact@trefoilstudio.com: the consent text promises unsubscribe by email and refunds go through it.
3. Keep the sale closed until paid checkout is integrated and independently verified. Then replace each `data-launch-pending` notice on `mac.html` (checkout, license steps) with its verified element, set the same checkout URL in the app's `Info.plist`, and pass `npm run release-check -- --live`. A pass does not replace a real Waffo TEST order through checkout, callback, license email, activation and refund, and explicit approval to open.

See `QA.md` for validation evidence and limits.
