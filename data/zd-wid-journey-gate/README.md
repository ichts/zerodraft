# Write It Down release journey gate

Rule: the release is done only when these pass on the real target.

## Web (writeitdown/)
```
cd writeitdown && npm ci && npm run journey -- --base https://writeitdown.app [--out <dir>]
```
Plays a brand-new visitor (fresh context, light, video on) at phone 390x844 and desktop 1440x900. Exit 0 = pass, 1 = any failed step, 2 = bad usage. Videos: `<out>/{phone,desktop}/journey-*.webm`, results in `<out>/results.json`.
Asserts: H1 without final period, handwritten line, deck below demo, demo >=60% of first viewport, no buy/checkout/sign-in offered (those do not exist yet; reported SKIP), real room starts and types, nav DOWNLOAD -> /download/ (checks page content, since the live host answers 200 on /download/ with the landing page), trial terms, canonical DMG href, published SHA-256, DMG 200 + diskimage type + size >=1 MB + not HTML + sha equals published, support/privacy/terms, waitlist form, no console errors (cloudflareinsights beacon and favicon excluded).

Pre-deploy local run (FIXTURE dmg, proves the sha logic only, not the real release file):
```
node writeitdown/journey/serve-local.mjs --root <release-web>/writeitdown --fixture-dmg --port 8016 &
cd writeitdown && npm run journey -- --base http://127.0.0.1:8016
```

## DMG (apps/macos/FirstLine/scripts/dmg-journey.sh [dmg-path] [out-dir])
Download (or take given) DMG, size + sha vs published, codesign/stapler/spctl on DMG and app, mount, Applications shortcut, ditto copy with quarantine, real-window first launch via cua-driver, 3 free sessions ("Free trial: N of 3 sessions left."), then activation page. Exit 0 pass, 1 failure, 2 = automated steps passed but the physical clean-user run is still manual (script prints exactly what; set WID_DMG_CLEAN_USER_EVIDENCE=<file> to clear). The launch/trial half is UNVERIFIED here: no real DMG exists yet, only the failure path was run. Strings come from branch fm/zd-wid-free-trial-launch.

## How main runs it
Release gate for writeitdown.app: after deploy run `cd writeitdown && npm ci && npx playwright install webkit && npm run journey:live` (base https://writeitdown.app, expects the published SHA-256 96c0...62cd; add `-- --out <dir>` for videos). Pre-deploy, serve the tree and the real DMG locally: `node journey/serve-local.mjs --root writeitdown --dmg-file <Write-It-Down-1.0.dmg> --port 8025 &` then `npm run journey -- --base http://127.0.0.1:8025 --expect-sha <sha>`. Phone = WebKit iPhone 14 at 390x844, desktop = Chromium 1440x900, one continuous human-paced video each (`WID_JOURNEY_PACE=fast` skips pauses); exit 0 only if every assertion passes. Assertions live in `writeitdown/journey/journey.mjs`, one `block()` per page section (seo, core-rule, how-it-works, facts, mac-block, faq, callback, footer, download, room, legal, waitlist, console): add a block for any new section and a step for every user-visible bug found.

## Live after deploy (a4a201c + DMG 96c0c0a3): exit 0, 72 pass, 0 fail, 2 skip, phone 89.0 s, desktop 89.2 s; release-check --download --live exit 0

## Gate proof (main a4a201c, headless)
| Run | Target | Exit | Assertions | Durations |
|---|---|---|---|---|
| live-before | https://writeitdown.app (old site, not yet deployed) | 1 | 18 pass, 54 fail, 2 skip | phone 138.9 s, desktop 140.8 s |
| local-release | main a4a201c local + real DMG release-fc4fbb22 | 0 | 72 pass, 0 fail, 2 skip | phone 86.8 s, desktop 86.6 s |

Videos (not committed): <dir>/{local-release,live-before}/{phone,desktop}/journey-*.webm; copied to ~/Desktop/WID journey gate videos.

## Findings
- Live /download/ answers 200 with the landing page (host fallback): a status-only check would pass the broken state. Asserted by content.
- Live landing still shows a "BUY MAC USD 4.99 - COMING SOON" link; the new journey asserts no buy offer, release-web removes it (passes).
- Local server logs a favicon 404 (no favicon declared); excluded from the console-error assertion, bounded follow-up.
- Old live H1 ends with a period and the demo covers only 34% (phone) / 25% (desktop) of the viewport.
- Repo AGENTS.md still says Mac has no native trial; release-web copy and the trial-launch branch say 3 free sessions. Needs doc alignment.
- Legal pages (support/privacy/terms/mac.html) still use the old bone/mono look; /download is restyled in PR B.
