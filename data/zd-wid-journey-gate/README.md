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

## Gate proof (v3 landing, main cd81645, runs headless)
Command: `cd writeitdown && npm run journey -- --base <url> --expect-sha 96c0c0a34733f92c1b47b1231c3243612c71614074dd6179ac3d61c80d5462cd --out <dir>`
Phone = WebKit + iPhone 14 profile 390x844; desktop = Chromium 1440x900. Assertions are one `block()` per page section in `writeitdown/journey/journey.mjs`; PR B sections add blocks.
| Run | Target | Exit | Assertions | Durations |
|---|---|---|---|---|
| live-before | https://writeitdown.app (old site, not deployed) | 1 | 14 pass, 34 fail, 2 skip | phone 84.3 s, desktop 83.9 s |
| local-release | main cd81645 served locally with the real DMG release-fc4fbb22 (sha 96c0...62cd; page sha line is injected by serve-local.mjs until PR B lands) | 0 | 48 pass, 0 fail, 2 skip | phone 62.7 s, desktop 63.9 s |

Videos (not committed): live-before/{phone,desktop}/journey-*.webm, local-release/{phone,desktop}/journey-*.webm under this directory.

## Findings
- Live /download/ answers 200 with the landing page (host fallback): a status-only check would pass the broken state. Asserted by content.
- Live landing still shows a "BUY MAC USD 4.99 - COMING SOON" link; the new journey asserts no buy offer, release-web removes it (passes).
- Local server logs a favicon 404 (no favicon declared); excluded from the console-error assertion, bounded follow-up.
- Old live H1 ends with a period and the demo covers only 34% (phone) / 25% (desktop) of the viewport.
- Repo AGENTS.md still says Mac has no native trial; release-web copy and the trial-launch branch say 3 free sessions. Needs doc alignment.
- v3 /download/ and legal pages still use the old bone/mono look while the landing is the new light sans; visual inconsistency to decide on (PR B).
