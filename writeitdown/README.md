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

The watch-only preview has its own clock. It types a short private draft (the Gemini demo script picked blind, option 1) at a human rhythm - uneven keystrokes, word and punctuation pauses - makes a false start, tries Backspace once (the sheet shakes silently and a Backspace keycap with a no-sign appears; nothing is deleted), carries on forward, then stops mid-sentence so the silence warning, the 3-2-1 and the wipe play before the loop restarts. The demo never deletes a character. No keystroke subtitles appear. The wipe report is centered in the paper. The pacing script lives in `demo-timeline.mjs`: a seeded, deterministic timeline shared with the qa specs, so fake-clock tests seek exact beats. `feedback.js` powers the deny shake (the trial, and the demo's blocked Backspace with sound off) and the trial's tone: 420ms movement, then a 180ms still hold, with the hairline visible throughout. Repeated blocked keys do not restart the feedback. The pause is visual, not an input lock or a timer extension. Sound needs a prior browser gesture. Reduced motion keeps a static draft and disables spatial shaking.

The writing viewport shows the active line at full opacity in the center of a fixed aperture, with two previous lines fading above it. The trial and landing demo share writing size and an above-centre start line through `--t-write` and `--write-anchor` in `tokens.css`, which owns the values and mobile override. Short trial windows push the line down only as far as needed to keep the aperture below the clock. Earlier lines rise as the draft grows. Native textarea padding and a CSS mask provide this without a mirrored draft or a custom text layout engine. It follows the end automatically but cannot be manually scrolled. The full draft remains available in the kept result.

Demo and trial sheets use dynamic viewport minimum heights in `site.css`, with `vh` fallbacks for older browsers. The trial sheet accounts for its header and bottom gutter, keeping EXIT and the word count inside the visible viewport as browser toolbars expand or collapse. The `.room.home` boundary clears the landing's minimum height so it cannot override that sizing.

`session.mjs` owns the real deadline rules and the count: Unicode words, with Han characters counted individually. Punctuation, emoji and whitespace do not count. This is a writing-unit count, not a linguistic Chinese word count. The room counter's tooltip and accessible description explain it. `room.js` connects the session to the browser editor. `theme.js` stores only the appearance preference. Light is the default; dark is a stored choice made with the sun/moon icon button at the right end of every page header (landing, `#trial`, `/download/`, Mac, legal and support pages).

## Deploy

Transfer and extract the tested deployment bundle on the target host, then run `sh writeitdown/install.sh` as root. It writes only the production files listed in `install.sh` under `/var/www/writeitdown.app/`, preserves an existing `index.html.dc-bak2`, and creates that backup from the current index if absent. It does not touch server configuration or remove other files.

The legal pages disclose Google Fonts requests, possible hosting access logs, and the Mac waitlist. The public contact is contact@trefoilstudio.com (Trefoil Studio).

### Discovery files and answer pages

`llms.txt` ships at `/llms.txt` as a hand-written plain-text file in llmstxt form: what the product is, who it is for, the 3 free Mac sessions, the closed USD 4.99 sale, and the canonical URLs. It never names an AI provider or model. It must be a real installed file: the host page handler (`try_files {path} {path}/index.html /index.html`) returns the homepage HTML with HTTP 200 for any missing path, which is why `/llms.txt` used to answer with the landing page. Caddy already maps `.txt` to `text/plain; charset=utf-8`. Check after every deploy:

```sh
curl -sI https://writeitdown.app/llms.txt | grep -i '^content-type:'
```

Expect `text/plain`. If a future proxy change serves another type, add this inside the site block and reload Caddy:

```caddyfile
@llmstxt path /llms.txt
header @llmstxt Content-Type "text/plain; charset=utf-8"
```

The six answer pages (`what-is-write-it-down.html`, `write-it-down-mac-vs-web.html`, `write-it-down-free-trial.html`, `write-it-down-price.html`, `delete-a-draft.html`, `is-my-writing-saved.html`) answer one question each, are self-canonical, listed in `sitemap.xml`, and linked from `support.html`. Each names Write It Down in the title, H1 and first body sentence, has at least 120 visible words and a visible FAQ, and carries an Ask ChatGPT self-description line, also present on `support.html`.

Each answer page's `Article.headline` matches its H1 and `Article.description` matches its entire first paragraph, not just the first sentence. Its `BreadcrumbList` names match the visible breadcrumb, and its `FAQPage` questions and answers match the visible FAQ word for word. `qa/seo.spec.mjs` enforces these contracts, the landing FAQ equality, the `llms.txt` content type and URL coverage, and sitemap order and canonicals. `robots.txt` allows OAI-SearchBot, ChatGPT-User, GPTBot, PerplexityBot and ClaudeBot and lists the sitemap. Add a new answer page to the sitemap, `install.sh`, the `llms.txt` link list and the spec together.

Attribution stays on the existing Cloudflare Web Analytics beacon's referrer reporting. A chatgpt.com arrival is attributable only when the browser supplies that referrer; the beacon does not establish ChatGPT-User crawler attribution. There is no custom tracker or server-side attribution, and ChatGPT-referred visitors get no extra trial sessions. Actual analytics records have not been independently verified.

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

After any deploy run the journey gate against the live domain: `npm ci && npx playwright install webkit && npm run journey:live`, then `npm run release-check -- --download --live`. The gate plays a brand-new visitor with one continuous video per viewport on a WebKit iPhone profile (390x844) and Chromium desktop (1440x900). Its single fixed pace uses a two-second reading pause after every step and 90 ms keystrokes; there is no fast mode. The named `full-session` scenario completes a real sixty-second session and verifies the exact kept draft, COPY TEXT/COPIED action and real clipboard contents. The independent `silence-wipe` scenario enters a fresh room and verifies deletion after eight seconds of silence (100 ms scheduling allowance). Chromium grants clipboard read/write permissions; WebKit grants clipboard read permission and uses its gesture-authorized write path because Playwright WebKit does not accept a clipboard-write permission. The browser's deletion receipt is `DRAFT DELETED AT M:SS. TYPE TO START AGAIN.` It also checks the DMG content type, size and SHA-256 against the page and a random missing DMG's 404. Sign-in, checkout, test payment and post-payment output do not exist in this release. `journey/waivers.json` records each exemption, its reason and the approval source: captain release decision 2026-10-22 (relayed by main). The captain can revoke it. The gate requires every unasserted step to have a valid waiver, prints them under `WAIVED (feature does not exist yet)`, and records WAIVED rather than PASS. A missing or invalid approval fails the gate before browser work. After every executed step, a shared guard rejects checkout, buy, payment or sign-in controls and links, including accessible roles, input controls and form targets. When a feature ships, remove its waiver and replace its unasserted-step declaration with real journey assertions; a waiver cannot hide a newly offered feature. A gate pass still does not itself authorize deployment.

Pre-deploy, serve the tree plus the real DMG with `node journey/serve-local.mjs --root . --dmg-file <dmg> --port 8025` and run `npm run journey -- --base http://127.0.0.1:8025 --expect-sha <sha>`. The server does not generate installers or rewrite the published checksum; use the release artifact matching the page. The assertions are one `block()` per page section in `journey/journey.mjs`.

Prove the room assertions reject broken behavior before accepting them. From `writeitdown/`, run:

```sh
node journey/verify-room.mjs
```

It copies production assets into disposable sites under the worktree's `tmp/journey-controls/`, leaving production source unchanged. Three `room.js` mutations disable completion, disable the silence wipe, or show COPIED without writing anything. It executes the same named journey scenarios headlessly against each local site on WebKit iPhone and Chromium desktop, requires exit 1 and the expected failing assertion on both viewports, then requires both scenarios to pass on the intact site with exit 0. Each run retains continuous videos, `results.json` and a log; `report.json` records exit codes and failing assertion names. A missing browser or unrelated failure does not count as a successful negative control.

Run `node --test journey/waivers.test.mjs` for focused waiver validation: it revokes each approval through the real CLI and checks forbidden controls in headless WebKit iPhone and Chromium. It does not exercise the Mac GUI.

For a focused reproduction against a running local site, use `npm run journey -- --base http://127.0.0.1:8025 --scenarios full-session,silence-wipe`. Omitting `--scenarios` runs the complete release journey. Focused room checks do not validate downloads or the remaining marketing/support journey, and never replace the full gate against the live domain.

### Shipped Mac journey

From the repository root, run `bash apps/macos/FirstLine/scripts/dmg-journey.sh <real-dmg> <worktree-evidence-directory>` on an approved GUI test machine. It exercises the shipped image and verifies each free session's full sentence through the editor AX value. Session 1 exits to the remaining-trial count. Session 2 goes silent for nine seconds and requires an empty editor and the `DRAFT DELETED AT… TYPE TO START AGAIN.` receipt. Session 3 writes through the real one-minute deadline, requires the exact kept draft, kept receipt and COPY TEXT affordance, then clicks COPY TEXT and checks COPIED and the exact clipboard contents. RUN IT AGAIN must then reach activation after the exhausted free sessions. This run's nonempty `screen.mov` is mandatory: recorder startup failure, early exit, unsuccessful stop or missing output fails the gate. Do not run GUI journeys on the Mini screen.

The Mac journey has not been executed; static checks do not establish GUI acceptance. A deliberately broken build proof for completion, deletion and copy remains pending a permitted GUI run, followed by the intact shipped-DMG journey. No Mac release acceptance is claimed.

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
