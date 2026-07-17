# First Line — License and Payment Spec

This spec describes the first paid direct-download launch path for First Line. It assumes a Mole-style hosted checkout and a macOS app distributed outside the Mac App Store.

## Decisions

| Area | Decision |
|---|---|
| Payment provider target | Dodo Payments first |
| Price | USD $5 early-bird |
| Model | One-time purchase. No subscription. |
| License seats | 2 Macs per license |
| Refund | 14 days |
| Web trial | Unlimited 1-minute browser trial; do not market this as the headline |
| Mac trial | 3 writing sessions |
| App Store | Not in scope for first launch |

## Why Dodo-first

Mole’s public FAQ states that checkout billing/address is handled by Dodo Payments and license keys are delivered from the Dodo email. Dodo’s public docs also match First Line’s needs:

- One-time products for lifetime access / software licenses.
- Hosted checkout sessions and payment links.
- Merchant-of-record style billing / tax handling.
- License-key entitlement with activation limits.
- Public license `activate` and `validate` endpoints that do not require exposing private API credentials in the app.
- Webhooks for entitlement delivery and revocation.
- Refund API and payment lifecycle webhooks.

## Launch flow

```text
Landing
  -> Buy early-bird license
  -> Dodo hosted checkout
  -> Dodo payment success
  -> Dodo issues license key
  -> customer receives license key by email
  -> customer downloads First Line
  -> app asks for license key after 3 Mac sessions
  -> app activates / validates key with Dodo
  -> local settings cache full access
```

The first version should not require a First Line account.

## Dodo dashboard setup

Create one product:

- Name: `First Line Early Bird`
- Price: `USD $5`
- Type: one-time payment
- Entitlement: license key
- Activation limit: `2`
- License duration: no expiry, unless Dodo requires an explicit lifetime setting
- Customer email: required
- Refund policy copy: 14-day refund
- Success URL: First Line `/download` or `/checkout/success`

Unknowns that require Dodo account access:

- Exact dashboard naming for license-key entitlements.
- Whether Dodo email alone is enough for key delivery, or if First Line should add its own email later.
- Exact webhook event names available in the account; public docs mention `entitlement_grant.delivered` and `entitlement_grant.revoked`.

## Mac app behavior

### Trial gate

Current state:

- `AppState.trialSessionLimit = 3`
- `AppSettings.trialSessionsUsed`
- `AppSettings.hasUnlockedFullAccess`
- `UpgradeView` currently says full access is not wired yet

Required behavior:

1. User can start up to 3 Mac writing sessions without a license.
2. Starting a Mac session consumes one trial use.
3. After 3 sessions, app routes to Upgrade.
4. Upgrade offers:
   - Buy early-bird license
   - Enter license key
   - Back to Home
5. Settings also offers license status and license entry.
6. A valid activated license sets full access locally.
7. Full access bypasses trial count.

### License entry

User input:

- License key text field.
- Activate button.
- Clear success / failure message.

Validation rules:

- Trim whitespace and line breaks.
- Preserve original key case unless Dodo says keys are case-insensitive.
- Do not log license keys.

### Device identity

Do not use invasive hardware identifiers for v1.

Use a generated install ID stored under `AppPaths.configDirectory`, for example:

```text
~/Library/Application Support/First Line/Config/install-id.json
```

Use that install ID as the Dodo activation `name`, or include it in a human-readable name such as:

```text
First Line Mac <short-install-id>
```

This is enough to enforce the 2-Mac activation limit without collecting serial numbers.

### Local cache

Extend settings with a license cache, for example:

```text
licenseKey: encrypted-or-plain-string?   # decide during implementation
licenseStatus: trial | active | invalid | refunded | unknown
licenseActivatedAt: timestamp?
licenseLastValidatedAt: timestamp?
licenseInstanceID: string?
```

For v1, storing the key in the existing config file is acceptable if the app never logs it and the key can be revoked server-side. A Keychain migration can come later if needed.

### Online / offline behavior

- Activation requires network.
- App validates on activation and periodically after launch.
- If validation cannot reach Dodo after a previously valid activation, keep full access for a short grace period.
- Suggested grace period: 7 days.
- If validation returns invalid / revoked, turn full access off and show Upgrade.

## Dodo API usage

Verified against Dodo Payments public documentation (last verified 2026-06-21).

**Reference docs**

- License keys feature overview: https://docs.dodopayments.com/features/license-keys
- API reference index: https://docs.dodopayments.com/api-reference/introduction
- Activate: https://docs.dodopayments.com/api-reference/licenses/activate-license
- Validate: https://docs.dodopayments.com/api-reference/licenses/validate-license
- Deactivate: https://docs.dodopayments.com/api-reference/licenses/deactivate-license
- Error codes: https://docs.dodopayments.com/api-reference/error-codes
- Documentation index: https://docs.dodopayments.com/llms.txt

**Base URLs**

- Test Mode: `https://test.dodopayments.com`
- Live Mode: `https://live.dodopayments.com`

The Mac app uses Test Mode during development and Live Mode in shipped builds. Switching is a build-time decision, not a runtime toggle.

**Public endpoints (no API key required)**

Dodo documents three public license endpoints. Authentication is the license key itself, supplied in the request body. No `Authorization` header, no bearer token, no developer API key is needed — these endpoints are designed to be called from desktop apps, CLIs, and browser clients without exposing secrets.

1. `POST /licenses/activate`
   - Request body:
     ```json
     {
       "license_key": "PRO-AAAA-BBBB-CCCC-DDDD",
       "name": "First Line Mac <short-install-id>"
     }
     ```
   - `license_key` (string, required): the key the customer pasted, trimmed.
   - `name` (string, required): identifies this activation instance. Use the install ID format from `AppPaths.configDirectory` so Dodo's dashboard shows a stable, non-PII identifier per Mac.
   - Success response (200):
     ```json
     {
       "business_id": "...",
       "created_at": "2024-01-01T00:00:00.000Z",
       "customer": {
         "customer_id": "...",
         "email": "...",
         "name": "...",
         "metadata": {},
         "phone_number": "..."
       },
       "id": "lki_123",
       "license_key_id": "lic_123",
       "name": "First Line Mac abcd1234",
       "product": { "product_id": "...", "name": "First Line Early Bird License" }
     }
     ```
   - Persist `id` (license_key_instance_id). Required for `/licenses/deactivate`.
   - Failure modes: HTTP 4xx with error body. Activation-limit-reached returns a specific error code (verify exact code against `error-codes` page during Phase 4 implementation).

2. `POST /licenses/validate`
   - Request body:
     ```json
     { "license_key": "PRO-AAAA-BBBB-CCCC-DDDD" }
     ```
   - Success response (200):
     ```json
     { "valid": true }
     ```
   - Response shape is intentionally minimal. The Mac app treats `valid: false` (or any non-200 / network failure) as "do not grant full access" but applies the offline grace period before revoking an existing activation.

3. `POST /licenses/deactivate`
   - Request body:
     ```json
     {
       "license_key": "PRO-AAAA-BBBB-CCCC-DDDD",
       "license_key_instance_id": "lki_123"
     }
     ```
   - Returns 200 on success. Not used in v1 user-facing flow, but the API exists — useful when adding self-serve device management later.

**SDK availability**

Dodo ships official SDKs for TypeScript, Python, Go, PHP, Java, Kotlin, C#, Ruby, and React Native. **No Swift / macOS SDK exists.** The Mac app uses `URLSession` with hand-rolled JSON encoding. Keep the request/response models in a single `LicenseModels.swift` file so contract changes are visible in one place.

**Rules for the Mac app**

- Never embed the Dodo developer API key, webhook signing key, or any dashboard credential.
- Treat the license key (entered by the user) as the only secret the app handles. Store it in `AppPaths.configDirectory`; never log it.
- Trim license key input. Preserve original case unless Dodo documents case-insensitivity.
- All activation/validation errors must surface a clear message: invalid key, activation-limit-reached, network failure. Use error codes from https://docs.dodopayments.com/api-reference/error-codes.

**Rules for the developer API key (server-side only, never in Mac app)**

The Dodo developer API key (dashboard → Developer → API Keys) is for:
- Dashboard automation scripts
- Refund / license management scripts
- Webhook signature verification on a backend
- Bulk license import / export

Store it in macOS Keychain (`security add-generic-password -s "dodo-test-api-key" -a "$USER" -w`) or a server-side secret manager. Never commit it. Never share it in chat, screenshots, or pastebins.

## Webhook path

Webhooks are not required to make v1 app activation work if the app validates keys against Dodo. They are still useful for support and later automation.

When a backend exists, listen for:

- Payment succeeded / failed events.
- Receipt / checkout completion events.
- `entitlement_grant.delivered` to know a license key was issued.
- `entitlement_grant.revoked` to disable refunded/revoked keys.
- `subscription.updated` / `subscription.plan_changed` if First Line ever adds subscription billing (not in v1 scope).

Webhook handling must verify signatures using the Dodo webhook signing key (dashboard → Webhooks). Use the official `standardwebhooks` library for the backend language, not hand-rolled HMAC. Headers documented by Dodo:

- `webhook-id`
- `webhook-signature`
- `webhook-timestamp`

## Web surfaces

Landing remains minimal. Add these pages separately:

- `/download` — current version, install steps, checksum, “signed/notarized” status.
- `/checkout/success` — check your email for license key, download link, support note.
- `/help` — buy, activate, switch Macs, failed activation.
- `/privacy` — writing stays local; license key validation contacts Dodo.
- `/refund` — 14-day refund and support email.
- `/terms` — one license covers 2 Macs, no subscription.

## Implementation slices

### Slice 1 — Product and support surfaces

Objective: publish the non-checkout web pages and copy.

Files to inspect:

- `index.html`
- `design/DESIGN.md`
- root `CLAUDE.md`

Acceptance:

- Landing stays minimal.
- Support pages use Kami visual system.
- `$5`, `2 Macs`, `14-day refund`, and `one-time purchase` are consistent.

### Slice 2 — License UI without live activation

Objective: replace preview-only Upgrade copy with real license entry UI.

Files to inspect:

- `Sources/FirstLine/Upgrade/UpgradeView.swift`
- `Sources/FirstLine/Settings/SettingsView.swift`
- `Sources/FirstLine/App/AppState.swift`
- `Sources/FirstLine/Infrastructure/SettingsStore.swift`
- `Tests/FirstLineTests/SmokeFlowTests.swift`
- `Tests/FirstLineTests/SettingsStoreTests.swift`

Acceptance:

- Upgrade shows buy and license entry.
- Settings shows license status and entry.
- No real network call yet.
- Existing trial tests still pass.

### Slice 3 — Dodo activation client

Objective: implement activation / validation through Dodo public license endpoints.

Files likely to add:

- `Infrastructure/LicenseClient.swift`
- `Infrastructure/InstallIDStore.swift`
- license tests under `Tests/FirstLineTests/`

Acceptance:

- Valid activation sets full access.
- Invalid activation does not unlock.
- Activation limit errors show useful copy.
- License key is not logged.

### Slice 4 — Checkout link and download flow

Objective: connect app and website to Dodo checkout/download pages once Dodo product exists.

Acceptance:

- Buy buttons point to configured checkout.
- Success URL explains download and license email.
- Download page can show placeholder until signed DMG exists.

### Slice 5 — Signed release

Objective: use Apple Developer ID to ship trusted DMG.

Blocked by:

- Apple Developer enrollment.
- Developer ID Application certificate.
- Notary credentials.

Acceptance:

- App bundle signed with hardened runtime.
- DMG notarized and stapled.
- Checksum published.

## Non-goals for first launch

- App Store distribution.
- Subscription billing.
- User accounts.
- Team licenses beyond 2 Macs.
- Stripe custom billing.
- Cloud sync.
- Collecting document content.

## Open decisions

- Support email address.
- Copyright owner name.
- Final app icon.
- Exact Dodo checkout URL / product ID.
- Whether early-bird `$5` is time-limited or quantity-limited.
