# First Line — Launch TODO

This is the execution checklist for turning First Line into a paid direct-download Mac product while Dodo Payments and Apple Developer access are still in progress.

Related references:

- `docs/LAUNCH_PLAN.md` — launch strategy and constraints.
- `docs/LICENSE_PAYMENT_SPEC.md` — Dodo/license behavior and app activation rules.
- `docs/RELEASE_CHECKLIST.md` — final signed/notarized DMG release gate.
- `docs/MANUAL_QA.md` — manual app verification checklist.

## Current status

- Dodo account is in Test Mode.
- Dodo Product Information is under review.
- Dodo Identity Verification is verified.
- Dodo Bank Verification is under review.
- Live payments are blocked until Dodo approval completes.
- Apple Developer enrollment is blocked, so Developer ID signing and notarized public DMG are blocked.
- `index.html` is the canonical landing page.
- `kami-landing.html` is reference only; do not edit it.

## Fixed product rules

Use these constants everywhere:

| Area | Value |
|---|---|
| Product | First Line |
| Offer | Early-bird license |
| Price | USD $5 |
| Payment model | One-time purchase. No subscription. |
| License seats | 2 Macs |
| Refund | 14 days |
| Mac trial | 3 writing sessions |
| Payment provider | Dodo Payments |
| Distribution | Direct download Mac app, outside the Mac App Store |

Do not headline the web trial as unlimited on the landing page.

## Hard rules for agents

- Keep the landing minimal. Do not add FAQ or footer back to `index.html` unless the user explicitly asks.
- All web pages must use the Kami visual system: parchment canvas, ink-blue accent, serif-led hierarchy, warm neutrals, restrained document sections.
- Do not claim the Mac app is downloadable until a real artifact exists.
- Do not claim the Mac app is signed or notarized until Developer ID signing and notarization are complete.
- Do not add GitHub as a primary trust/navigation element for the paid product.
- Do not put private Dodo API keys, webhook secrets, Apple credentials, bank details, or identity data in code or docs.
- Do not put private API keys in the Mac app.
- If Dodo license activation requires a private key from the app, stop and ask whether to add a backend.
- Do not invent support email, copyright owner, company name, final domain, or app icon source. Use `Unknown / to fill`.

## Phase 1 — Dodo review waiting work

Goal: use Test Mode to prepare the product and learn the exact license flow without touching live payments.

### 1.1 Brand cleanup

- [ ] Check whether the user-facing Dodo brand/storefront name is still `Dodo Games`.
- [ ] Rename visible brand/storefront to `First Line` if Dodo shows it to buyers.
- [ ] Keep legal/business identity accurate if Dodo separates legal name from storefront brand.

Acceptance:

- Buyer-facing checkout, receipt, and license emails should say `First Line`, not `Dodo Games`.

### 1.2 Create Test Mode product

- [ ] Create one-time product in Dodo Test Mode.
- [ ] Product name: `First Line Early Bird License`.
- [ ] Category: software / digital product / digital downloadable content, whichever Dodo offers.
- [ ] Price: `USD $5`.
- [ ] Billing: one-time.
- [ ] Customer email: required.
- [ ] Delivery: email delivery.
- [ ] Refund copy: 14-day refund.

Product description:

```text
First Line is a forward-only writing app for finishing first drafts.

Stop typing for eight seconds and the draft disappears. No deleting. No editing backward. Just keep the line moving.

One-time purchase. No subscription. Includes a license for 2 Macs.
```

Acceptance:

- Product exists in Test Mode.
- Product does not use subscription, recurring billing, credits, or account seats language.

### 1.3 Configure license entitlement

- [ ] Enable license-key entitlement for the product.
- [ ] Set activation limit to `2`.
- [ ] Set expiration to lifetime / no expiry if available.
- [ ] Confirm Dodo can email the license key after checkout.

Acceptance:

- Test purchase creates a license key.
- The license key has a 2-activation limit.
- The buyer can receive the key by Dodo email.

### 1.4 Test checkout

- [ ] Create a Test Mode hosted checkout or payment link.
- [ ] Complete a test purchase with Dodo test payment details.
- [ ] Confirm receipt email arrives.
- [ ] Confirm license key email arrives.
- [ ] Confirm entitlement/license record appears in Dodo dashboard.
- [ ] Record non-secret findings in `docs/LICENSE_PAYMENT_SPEC.md`.

Safe to record:

```text
DODO_TEST_CHECKOUT_URL=<test checkout URL>
DODO_TEST_PRODUCT_ID=<product id if safe and useful>
DODO_LICENSE_DOCS_URL=<docs URL>
```

Never record:

```text
DODO_API_KEY
Webhook secret
Bank details
Identity details
Private screenshots
```

Acceptance:

- Test purchase path is understood.
- Any gap in license delivery is documented as a blocker.
- Test Mode URLs are clearly marked as test-only.

## Phase 2 — Web readiness pages

Goal: create the small support/legal/download surfaces needed for launch without bloating the landing.

### 2.1 Inspect before editing

- [ ] Read root `CLAUDE.md`.
- [ ] Read `design/DESIGN.md`.
- [ ] Read `index.html`.
- [ ] Read `docs/LAUNCH_PLAN.md`.
- [ ] Read `docs/LICENSE_PAYMENT_SPEC.md`.

### 2.2 Add static pages

Create these root-level static pages unless deployment routing says otherwise:

- [ ] `download.html`
- [ ] `checkout-success.html`
- [ ] `help.html`
- [ ] `privacy.html`
- [ ] `refund.html`
- [ ] `terms.html`
- [ ] `release-notes.html`

Acceptance:

- Pages use Kami visual system.
- Pages are useful and short.
- Pages do not add noise to `index.html`.

### 2.3 `download.html`

Required behavior before public DMG exists:

- [ ] Say the Mac download is being prepared.
- [ ] Say public download waits for Developer ID signing and notarization.
- [ ] Include placeholders for version, file, checksum, and signing status.
- [ ] Tell license buyers to keep the Dodo email with their license key.
- [ ] Do not expose an unsigned build as public release.

Suggested copy:

```text
The Mac download is being prepared.
First Line will be available here after Developer ID signing and notarization are complete.
```

Acceptance:

- No fake download button.
- No false signed/notarized claim.

### 2.4 `checkout-success.html`

- [ ] Tell buyer to check email for Dodo receipt and license key.
- [ ] Link to `download.html`.
- [ ] Include support placeholder: `Unknown / to fill`.
- [ ] Do not add account/login flow.

Acceptance:

- Dodo success URL can safely point here.

### 2.5 `privacy.html`

- [ ] Say writing stays local in the Mac app.
- [ ] Say browser trial content is not sent to a server by the current static page.
- [ ] Say license activation/validation contacts Dodo.
- [ ] Say Dodo processes checkout, tax, receipts, and license delivery.
- [ ] Say no analytics if no analytics are present.
- [ ] Say no AI processing.

Acceptance:

- Privacy copy matches actual implementation.

### 2.6 `refund.html`

- [ ] State 14-day refund policy.
- [ ] Ask user to send purchase email and license key to support.
- [ ] Use support placeholder if support email is unknown.

Acceptance:

- Refund copy matches the 14-day decision.

### 2.7 `terms.html`

- [ ] State one license covers 2 Macs.
- [ ] State one-time purchase, no subscription.
- [ ] State license key cannot be resold or shared publicly.
- [ ] State app is provided as-is.
- [ ] Link refund policy.
- [ ] Use `Unknown / to fill` for legal owner if unknown.

Acceptance:

- No invented company/legal details.

### 2.8 `help.html`

- [ ] Explain buying First Line.
- [ ] Explain finding the Dodo license key email.
- [ ] Explain activating the Mac app.
- [ ] Explain 2-Mac limit.
- [ ] Say activation-limit issues require support until deactivation exists.
- [ ] Link refund page.

Acceptance:

- Help page does not promise self-serve deactivation unless it is implemented.

### 2.9 `release-notes.html`

- [ ] Add placeholder release notes for first public build.
- [ ] Mark version as `Unknown / to fill` until release version is chosen.

Acceptance:

- Release notes do not claim a shipped public build before it exists.

### 2.10 Landing link update

- [ ] Change `Download for Mac` links in `index.html` from `#download` to `download.html`.
- [ ] Preserve trial selectors:
  - `.demo-writing-surface`
  - `.live-demo-editor`
  - `.trial-overlay`
  - `.trial-writing-surface`
  - `.trial-editor`
  - `[data-trial-launch]`
- [ ] Do not add FAQ, footer, or GitHub nav.

Acceptance:

- Landing remains short.
- Download links go somewhere real and truthful.

## Phase 3 — Mac license UI

Goal: make the native app ready to accept a Dodo license key after the 3-session trial.

### 3.1 Inspect before editing

- [ ] `apps/macos/FirstLine/CLAUDE.md`
- [ ] `Package.swift`
- [ ] `Sources/FirstLine/App/AppState.swift`
- [ ] `Sources/FirstLine/Infrastructure/SettingsStore.swift`
- [ ] `Sources/FirstLine/Infrastructure/AppPaths.swift`
- [ ] `Sources/FirstLine/Upgrade/UpgradeView.swift`
- [ ] `Sources/FirstLine/Settings/SettingsView.swift`
- [ ] `Tests/FirstLineTests/SettingsStoreTests.swift`
- [ ] `Tests/FirstLineTests/SmokeFlowTests.swift`

### 3.2 Persist license state

- [ ] Add license status model: `trial`, `active`, `invalid`, `revoked`, `unknown`.
- [ ] Persist license key only if needed; never log it.
- [ ] Persist activation timestamp.
- [ ] Persist last validation timestamp.
- [ ] Persist license instance ID if Dodo returns one.
- [ ] Add generated install ID stored under Application Support config.

Suggested install ID path:

```text
~/Library/Application Support/First Line/Config/install-id.json
```

Acceptance:

- Existing settings migrate safely.
- No hardware serial number or invasive device identifier is used.

### 3.3 Add license service layer

- [ ] Add a small protocol for activation and validation.
- [ ] Add models for activation result, validation result, and license errors.
- [ ] Add a mock/test client for tests.
- [ ] Do not implement real Dodo API until exact endpoint and auth requirements are confirmed.

Stop condition:

- If Dodo requires private API credentials for activation from the app, stop and ask whether to add a backend.

Acceptance:

- App can be tested without real Dodo network.
- No private secrets appear in source.

### 3.4 Upgrade UI

- [ ] Add buy button for early-bird license.
- [ ] Add license key input.
- [ ] Add activate button.
- [ ] Add loading, success, invalid-key, and network-error messages.
- [ ] Keep copy sparse and Kami-native.
- [ ] If checkout URL is not ready, show honest disabled/placeholder state.

Required copy facts:

```text
One-time purchase.
No subscription.
Early bird: $5.
Includes 2 Macs.
```

Acceptance:

- Trial-exhausted user can see how to buy and where to paste a key.
- Invalid activation does not unlock the app.
- Successful activation unlocks immediately.

### 3.5 Settings license section

- [ ] Show current license status.
- [ ] Show trial/session status if not active.
- [ ] Allow license key entry from Settings.
- [ ] Link to buy license if checkout URL is ready.
- [ ] Do not build deactivation unless Dodo behavior is confirmed.

Acceptance:

- User can recover from closing Upgrade by opening Settings.

### 3.6 Trial gate integration

- [ ] Keep Mac trial limit at 3 sessions.
- [ ] Active license bypasses trial limit.
- [ ] Invalid/revoked license does not bypass trial limit.
- [ ] Revoked validation disables full access.

Acceptance:

- Existing trial behavior still works.
- Active license state is the only production unlock path.

### 3.7 Offline behavior

- [ ] Activation requires network.
- [ ] After valid activation, allow short offline grace period.
- [ ] Use 7 days as default grace period unless user changes it.
- [ ] If validation returns invalid/revoked, turn full access off.

Acceptance:

- Temporary network failure does not immediately lock out a valid user.

## Phase 4 — Real Dodo activation

Goal: wire the app to Dodo only after the API contract is verified.

### 4.1 Verify Dodo docs/account behavior

- [ ] Confirm exact activate endpoint.
- [ ] Confirm exact validate endpoint.
- [ ] Confirm request body.
- [ ] Confirm response body.
- [ ] Confirm error codes.
- [ ] Confirm whether endpoint is safe from a desktop client.
- [ ] Confirm whether product ID, public key, or entitlement ID is needed.

Acceptance:

- `docs/LICENSE_PAYMENT_SPEC.md` contains real, non-secret findings.

### 4.2 Implement real client

- [ ] Add `DodoLicenseClient` only after 4.1 is complete.
- [ ] Do not send private API key from app.
- [ ] Trim license key input.
- [ ] Do not log license keys or full response payloads containing keys.
- [ ] Handle invalid, activation-limit-reached, revoked/refunded, and network failures.

Acceptance:

- Dodo Test Mode license can activate the app.
- Invalid key is rejected.
- Activation-limit behavior is understood and documented.

## Phase 5 — Release packaging prep

Goal: prepare the Mac release pipeline without pretending final public distribution is ready.

### 5.1 Metadata cleanup

- [ ] Update `README.md` placeholders.
- [ ] Update `LICENSE` copyright owner only after user confirms owner.
- [ ] Confirm bundle identifier.
- [ ] Confirm version/build number.
- [ ] Confirm support email.

Open values:

```text
Copyright owner: Unknown / to fill
Support email: Unknown / to fill
Final domain: Unknown / to fill
Final app icon source: Unknown / to fill
Bundle identifier: Unknown / to fill
```

Acceptance:

- No placeholder is silently shipped as final.

### 5.2 App icon

- [ ] Replace `build/darwin/AppIcon/README.md` placeholder with final icon assets when available.
- [ ] If final icon is unavailable, mark release blocked.

Acceptance:

- Release checklist truthfully reflects icon status.

### 5.3 Build/package scripts

- [ ] Add unsigned local app bundle build script if missing.
- [ ] Add DMG packaging script if missing.
- [ ] Add signing/notarization script placeholders using environment variables only.
- [ ] Do not hardcode Apple ID, app-specific password, team ID, or certificate secrets.

Suggested environment placeholders:

```text
APPLE_DEVELOPER_ID_APPLICATION
APPLE_NOTARY_PROFILE
```

Acceptance:

- Internal unsigned package can be built for QA.
- Public DMG remains blocked until Developer ID certificate and notarization work.

## Phase 6 — Live launch switch

Do this only after Dodo and Apple are ready.

- [ ] Dodo review approved.
- [ ] Bank verification approved.
- [ ] Live Mode product created with same settings as Test Mode.
- [ ] Live license entitlement configured with 2 activations.
- [ ] Live checkout tested with a real low-risk purchase if appropriate.
- [ ] Apple Developer ID Application certificate installed.
- [ ] App signed with hardened runtime.
- [ ] DMG notarized.
- [ ] Notarization ticket stapled.
- [ ] Checksum generated.
- [ ] `download.html` updated with real version, file, checksum, and signing status.
- [ ] `index.html` Buy button points to live Dodo checkout.
- [ ] Full manual QA completed.

Acceptance:

- Live checkout issues a license key.
- Downloaded DMG passes Gatekeeper.
- App activates with live license.
- No Test Mode URL remains in public pages.

## Verification commands

### Web changes

Run from repo root:

```bash
git diff --check -- index.html download.html checkout-success.html help.html privacy.html refund.html terms.html release-notes.html
python3 -m http.server 8766
```

Manual browser checks:

- [ ] Open `http://127.0.0.1:8766/index.html`.
- [ ] Click `Try 1 minute`.
- [ ] Type in browser trial.
- [ ] Confirm trial success/failure UI still works.
- [ ] Confirm `Download for Mac` opens `download.html`.
- [ ] Open every support/legal page.
- [ ] Check mobile width.
- [ ] Check browser console for errors.

### Swift changes

Run from `apps/macos/FirstLine`:

```bash
swift build
swift test
```

Manual app checks:

- [ ] Launch app.
- [ ] Start writing session.
- [ ] Confirm append-only still works.
- [ ] Confirm 8 seconds of silence fails current draft.
- [ ] Confirm success flow still works.
- [ ] Exhaust 3-session trial.
- [ ] Confirm Upgrade appears.
- [ ] Enter invalid license key and confirm app stays locked.
- [ ] Enter valid Test Mode license key and confirm app unlocks, if Dodo activation is implemented.

## Recommended execution order for another agent

1. Do Phase 2 web readiness pages first.
2. Stop and report browser QA results.
3. After user confirms Dodo Test Mode product/license behavior, update Phase 1 findings in `docs/LICENSE_PAYMENT_SPEC.md`.
4. Implement Phase 3 license UI with mock client.
5. Implement Phase 4 real Dodo activation only after API contract is verified.
6. Prepare Phase 5 packaging scripts and metadata.
7. Do Phase 6 only after Dodo live approval and Apple Developer signing are available.

## Immediate next task prompt

Use this prompt for the next coding agent:

```text
Execute Phase 2 from apps/macos/FirstLine/docs/LAUNCH_TODO.md.

Constraints:
- index.html is the canonical landing.
- Do not edit kami-landing.html.
- Keep landing minimal; no FAQ, no footer, no GitHub nav.
- All web pages must use Kami visual system.
- Do not fake a Mac download or signed/notarized status.
- Preserve trial selectors in index.html.

Deliverables:
- Add download.html, checkout-success.html, help.html, privacy.html, refund.html, terms.html, release-notes.html.
- Update index.html Download for Mac links to download.html.
- Verify with git diff --check and browser QA.
- Stop after Phase 2 and report.
```
