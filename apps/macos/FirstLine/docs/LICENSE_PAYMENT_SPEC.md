# Write It Down for Mac: license and payment

The Mac app uses the signed-token service in `services/license/`, not a processor API. Its client type retains the historical `WaffoLicenseClient` name; the service now selects Waffo or Stripe independently. Price: USD $4.99 once, two installations per license. Mac offers three free writing sessions, then requires activation; the full web trial remains at https://writeitdown.app/. The refund window is 14 days. The selected payment adapter owns the charged amount; `WIDDisplayPrice` owns the app's displayed price.

Purchase-page integration and its installed-DMG TEST acceptance boundary are owned by [`writeitdown/README.md`](../../../../writeitdown/README.md#mac-page-release-order). HTTP stubs and the window fixture are not purchase evidence. Service readiness and provider-specific gates belong to [`services/license/README.md`](../../../../services/license/README.md).

## Release configuration

`Sources/FirstLine/Info.plist` pins the purchase page, deployed service origin, stable product and deployed public key:

- `WIDCheckoutURL`: the public Mac page (`https://writeitdown.app/mac.html`) used only as the error fallback when the in-app checkout request fails. It is never the Buy action and cannot point directly at the service's POST-only checkout API.
- `WIDLicenseServiceURL`: service HTTPS origin, without `/api/v1` or another path, used for activation, validation, deactivation and `POST /api/v1/checkout`. Loopback HTTP is allowed by the client for local QA only; the release script rejects it.
- `WIDLicenseProductID`: exact product identity from the service configuration.
- `WIDLicensePublicKey`: base64 of the raw 32-byte Ed25519 **public** key, not PEM and not a private key. This is the service's token-verification key, not Waffo's RSA webhook key.

No merchant credential belongs in the app. `scripts/release-dmg.sh` requires all four fields for a release and rejects incomplete or invalid configuration; `--staging` requires all four empty. TEST and LIVE use the same app configuration; the service environment selects the payment mode. `scripts/test-release-config.py` covers the packaging gate without building or signing. Configuration does not prove that a test purchase passed.

## Entitlement and persisted state

`AppState` still owns activation, validation, revision guards and persistence rollback. `SettingsStore` retains the historical `licenseKey` field name for the order number and adds `licenseToken`. The token, order number, activation ID, product, status and validation timestamps may persist; writing never does. `trialSessionsUsed` persists the three-session native trial budget and retains legacy usage, clamped to 0-3. A malformed counter exhausts only the trial budget; separately decoded signed-license metadata remains eligible for normal validation. An active license flag without a key remains a license record, not an inactive trial: it grants neither signed-license access nor new free sessions, including after settings are saved and reopened. The old `hasUnlockedFullAccess` flag is ignored and omitted when settings are saved. Trial usage is not a signed entitlement or a tamper-proof purchase boundary: deleting local app settings can reset it. The full random install UUID in `install-id.json` supplies the device binding, not a shortened label or hardware identifier.

Full access requires all of the following:

- Active status and a nonblank order number. The old `hasUnlockedFullAccess` flag is ignored.
- A configured service, matching product and activation ID, and a token signed by the pinned Ed25519 public key for this installation.
- Nonempty license and activation IDs, issuance no more than 60 seconds ahead of the clock, a seven-day signed lifetime and an expiration strictly later than now. The local validation timestamp cannot extend the signed expiration.
- Completion of the launch validation attempt. Only transport errors, HTTP 429 and 5xx preserve valid offline access. Explicit HTTP 403 revokes it; malformed tokens, invalid signatures and unexpected responses fail closed.

Fresh installs open Home with three free sessions. Entering an empty room or blocked/empty input spends nothing; the first nonempty committed input or IME activity atomically saves one usage before TextKit accepts it. A wipe, exit or quit does not return that usage. A wiped room's next input needs a new session. The last trial can recover, complete and copy normally; wipe itself never routes to checkout, but restarting or leaving after exhaustion opens the existing activation screen. Unreadable usage or a failed reservation closes trial access with a visible error rather than silently granting another session.

Home, Settings and writing menu actions share the same trial-or-license gate. There is no release-mode switch or parallel trial-ended controller. Existing license records, pending validation, expiry, invalid tokens and refunds never fall back to unused trial sessions. After exhaustion the screen offers order/code entry, in-app hosted checkout with the public Mac-page fallback, and the full web-trial link. Valid launch validation or signed offline grace opens Home. The signed-license predicate, client, token verifier, seven-day limit, activation rollback and refund handling are unchanged. The start and first-input gates enforce entitlement, so revocation before the first keystroke closes an already-opened empty room. A draft already being written is not erased by a license check.

Successful renewal replaces the persisted token only after checking signature, product, installation and activation ID. Older validation responses cannot overwrite a newer validation or activation. An activation persistence failure restores the previous settings and attempts to release only the new allocation; it never deactivates the previously accepted instance. Concurrent activation submissions are ignored while one is in flight.

## In-app checkout

The Buy action does not open `WIDCheckoutURL` directly. `HostedCheckoutClient` POSTs to `{WIDLicenseServiceURL}/api/v1/checkout` with `Accept: application/json`, no request body, no cookie jar and no buyer credential, and refuses HTTP redirects. A 200 response is accepted only when it contains a string `url` on `https://checkout.stripe.com` with no user or password; the app opens that URL in the system browser. Any transport error, non-200 status, malformed body or invalid destination opens `WIDCheckoutURL` (the public `mac.html`) instead. The hosted URL and buyer session identifier are never logged. Tests use URLProtocol fixtures and never create a real charge. Checkout success is not purchase evidence; the genuine TEST gate remains below.

## Service wire contract

`WaffoLicenseClient` uses `URLSession`, POST and JSON, without an Authorization header. Redirects are refused so order numbers and tokens cannot be forwarded to another origin.

| Path | Request | Response |
| --- | --- | --- |
| `/api/v1/licenses/activate` | `{ "orderId": "...", "installLabel": "full UUID", "platform": "macos" }` | `{ "token": "..." }` |
| `/api/v1/licenses/validate` | `{ "token": "..." }` | `{ "token": "renewed token" }` |
| `/api/v1/licenses/deactivate` | `{ "token": "..." }` | HTTP 200 |

The token is `base64url(JSON).base64url(signature)`, without padding. Ed25519 signs the **encoded payload text**, not the decoded JSON. Claims: `licenseId`, `activationId`, `installLabel`, `product`, `issuedAt`, `expiresAt`. Timestamps are Unix seconds. `LicenseTokenVerifier` checks this contract with CryptoKit; there is no new crypto dependency.

Activation 403/404 means unavailable, including missing webhook, refund or revocation. HTTP 409 with `device limit reached` is the two-install limit; other 409 responses are not misreported as that limit. The service currently refuses expired tokens even at `/validate`. After seven days offline, re-enter the same order number while online to activate again; the service reuses that installation's active slot.

A signed offline token cannot learn about a refund. The next launch validation enforces revocation; while offline, access lasts no longer than the token's seven-day expiry. Do not promise immediate offline revocation.

## Acceptance

From `apps/macos/FirstLine/`:

```sh
swift build
swift test
WID_QA_LICENSE_ONLY=1 scripts/qa-window.sh "$PWD/dist/qa-license"
```

The window command requires Go, Python 3, jq and a permitted cua-driver daemon. The license-only mode starts with an empty home, verifies three trial sessions, an unspent empty room, exhaustion across restart and the full web-trial link, then activates a copied app against a disposable loopback fixture, writes in the real editor, restarts offline and restarts with a refund response. It verifies the exhausted trial counter stays at three after activation and refund. Without license-only mode the full-window motion checks run after fixture activation; deterministic Swift tests cover their timing separately. The fixture uses a fresh in-memory Ed25519 key; no Waffo request is made and the distributable app's configuration stays unchanged. `WaffoLicenseClientTests` verifies HTTP payloads, signature failures, persisted legacy denial, renewal, refund rejection and exact offline deadlines. `CheckoutClientTests` verifies the POST/no-body contract, redirect refusal, Stripe-destination validation, success opening the hosted URL and every error falling back to `mac.html`. `LicenseFlowTests` retains concurrency and rollback coverage.

The service's local contract accepts an opaque 8-100-byte credential in the existing `orderId` field. The app trims only leading and trailing whitespace and newline characters from the pasted activation field (spaces, tabs, newlines, carriage returns), because a key copied from an email or terminal carries that noise; everything inside the credential stays byte-for-byte as entered, with no case folding, Unicode aliasing or code translation. A key that is empty or all whitespace is rejected before any request. Stripe credential delivery is defined in the [service contract](../../../../services/license/README.md#stripe-adapter); the app submits the trimmed credential unchanged. Genuine receipt-to-app acceptance is still required; the client does not invent issuance or another endpoint.

For genuine acceptance, follow the [selected provider's TEST purchase procedure](../../../../services/license/deploy/DEPLOY.md#6-prove-the-genuine-test-purchase-before-live), configure a test build with the verified service public configuration, confirm the signed callback reached the service, then enter the delivered buyer credential in the real app. Record only a redacted pass/fail result and screenshots without buyer credentials in `MANUAL_QA.md`. Never log or commit order numbers, tokens, private keys or request bodies from real purchases. Production purchase and deployment require separate authorization.
