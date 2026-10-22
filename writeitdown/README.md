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

`download/index.html` (served at `/download/`) offers the free-trial DMG at `https://writeitdown.app/download/Write-It-Down-1.0.dmg`. That disk image must be the Mac trial PR 42 build (3 free sessions, then the license gate). Do not install this site against a paid-only binary. Upload the signed, notarized DMG into `/var/www/writeitdown.app/download/` first. The page now publishes its SHA-256 in the `data-launch="sha256"` slot; update that slot if the artifact changes. Pass `npm run release-check -- --download --live` against the uploaded artifact before installing the site. Checkout stays closed; that gate is below.

### Host routing (Caddy) and the release journey gate

Use mutually exclusive download and page handlers. Do not put a site-level `try_files` before these handlers: it would rewrite missing downloads into the home page before the DMG matcher runs. Preserve the host's existing API routes separately.

```caddyfile
writeitdown.app {
	root * /var/www/writeitdown.app
	@dmg path *.dmg
	handle @dmg {
		header Content-Type application/x-apple-diskimage
		file_server
	}
	handle {
		try_files {path} {path}/index.html /index.html
		file_server
	}
}
```

The DMG branch has no fallback: `file_server` returns 404 when the image is absent. The page branch resolves `/download/` to `download/index.html` before trying the home page.

After any deploy run the journey gate against the live domain: `npm ci && npx playwright install webkit && npm run journey:live`, then `npm run release-check -- --download --live`. The gate plays a brand-new visitor with one continuous video per viewport on a WebKit iPhone profile (390x844) and Chromium desktop (1440x900). It completes a real sixty-second session, verifies the exact kept draft and COPY TEXT/COPIED action, then restarts and verifies deletion after nine seconds of silence. The browser's deletion receipt is `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` It also checks the DMG content type, size and SHA-256 against the page and a random missing DMG's 404. Sign-in and payment remain SKIPs, printed as `EXEMPT pending captain approval: not built`, not passes. A successful script exit does not approve those exemptions or authorize release.

Pre-deploy, serve the tree plus the real DMG with `node journey/serve-local.mjs --root . --dmg-file <dmg> --port 8025` and run `npm run journey -- --base http://127.0.0.1:8025 --expect-sha <sha>`. The server does not generate installers or rewrite the published checksum; use the release artifact matching the page. The assertions are one `block()` per page section in `journey/journey.mjs`.

Prove the gate rejects a known-broken room before accepting it. From `writeitdown/`, copy only production assets into a disposable directory inside the worktree, disable the room module there, and serve that copy:

```sh
mkdir -p .journey-broken
cp *.css *.js *.mjs *.html *.woff2 og.png .journey-broken/
cp -R download .journey-broken/
printf 'export {};\n' > .journey-broken/room.js
node journey/serve-local.mjs --root .journey-broken --dmg-file <real-dmg> --port 8026
# In another terminal, from writeitdown/:
npm run journey -- --base http://127.0.0.1:8026 --out journey-results/broken-room --expect-sha <sha>
```

Require exit 1 and a room failure in `results.json`; retain the videos and results. Then run the unchanged gate against the intact tree and finally the live domain. A broken-room run is negative evidence only, never a release pass.

### Shipped Mac journey

From the repository root, run `bash apps/macos/FirstLine/scripts/dmg-journey.sh <real-dmg> <worktree-evidence-directory>` on an approved GUI test machine. It exercises the shipped image, verifies each free session's full sentence through the editor AX value, and requires this run's nonempty `screen.mov`. Recorder startup failure, early exit, unsuccessful stop or missing output fails the gate. Do not run GUI journeys on the Mini screen.

The automated isolated home does not prove Finder installation and first launch under a physically clean macOS login. Until that manual evidence is supplied, successful automation exits 2. Set `WID_DMG_CLEAN_USER_EVIDENCE` to a directory containing both:

- A nonempty `.mov` or `.mp4` screen recording of Safari download, Finder drag to Applications, eject, first launch and Gatekeeper approval, and the three-session trial reaching activation.
- A nonempty `notes.md` or `notes.txt` identifying the clean login, date, macOS version, DMG SHA-256, steps and observed outcomes, including the Developer ID identity and absence of a damaged-app warning.

The script checks the directory, recording and notes before allowing exit 0. Their presence is an evidence prerequisite, not an automated judgment of their contents; captain review is still required.

### Mac page release order

`mac.html` describes the Mac app (3 free sessions, then a USD 4.99 one-time license for 2 Macs with a 14-day refund, whose purchase is not open yet): the free-trial download and the web room are its working CTAs, Buy is a visible "coming soon" notice, and the waitlist form posts to `/api/waitlist` (`services/waitlist/`). `waitlist.js` only enhances the form; without JavaScript the collector's 303 fragment is revealed by `:target`.

1. Deploy the Go collector using [`services/waitlist/README.md`](../services/waitlist/README.md) behind the site's reverse proxy. `install.sh` refuses to install the site until `https://writeitdown.app/api/waitlist/health` (override with `WAITLIST_HEALTH_URL`) answers `ok`. This is only a preflight: submit one real test address from the page, confirm its stored line, then remove it. Neither the collector's presence in this repository nor a local test proves deployment.
2. Send a test email to and from contact@trefoilstudio.com: the consent text promises unsubscribe by email and refunds go through it.
3. Keep the sale closed until paid checkout is integrated and independently verified. Then replace each `data-launch-pending` notice on `mac.html` (checkout, license steps) with its verified element, set the same checkout URL in the app's `Info.plist`, and pass `npm run release-check -- --live`. A pass does not replace a real Waffo TEST order through checkout, callback, license email, activation and refund, and explicit approval to open.

See `QA.md` for validation evidence and limits.
