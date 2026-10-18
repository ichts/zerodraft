# Write It Down for Mac: license and payment

The Mac app uses the Waffo-backed service in `services/license/`, not Polar. Price: USD $4.99 once, two installations per license, three free Mac writing sessions charged on first input. Waffo owns the charged amount; `WIDDisplayPrice` owns the app's displayed price.

**Public sale is blocked.** The local service contract is implemented, but its Waffo webhook envelope and the buyer-visible receipt order number have not been verified with a genuine Waffo test purchase. HTTP stubs and the window fixture are not purchase evidence. Do not publish checkout until that order, callback, real app activation and refund rejection pass. See `services/license/README.md` for service readiness.

## Release configuration

`Sources/FirstLine/Info.plist` leaves these values empty until verified:

- `WIDCheckoutURL`: Waffo checkout HTTPS URL, opened in the external browser.
- `WIDLicenseServiceURL`: service HTTPS origin, without `/api/v1` or another path. Loopback HTTP is allowed by the client for local QA only; the release script rejects it.
- `WIDLicenseProductID`: exact product identity from the service configuration.
- `WIDLicensePublicKey`: base64 of the raw 32-byte Ed25519 **public** key, not PEM and not a private key. This is the service's token-verification key, not Waffo's RSA webhook key.

No merchant credential belongs in the app. Missing or invalid configuration fails closed. `scripts/release-dmg.sh` validates these fields; `--staging` requires all four empty. Configuration does not prove that a test purchase passed.

## Entitlement and persisted state

`AppState` still owns activation, validation, revision guards and persistence rollback. `SettingsStore` retains the historical `licenseKey` field name for the order number and adds `licenseToken`. The token, order number, activation ID, product, status and validation timestamps may persist; writing never does. The full random install UUID in `install-id.json` supplies the device binding, not a shortened label or hardware identifier.

Full access requires all of the following:

- Active status and a nonblank order number. The old `hasUnlockedFullAccess` flag is ignored; active records without an order number are demoted to trial without changing trial usage or writing preferences.
- A configured service, matching product and activation ID, and a token signed by the pinned Ed25519 public key for this installation.
- Nonempty license and activation IDs, issuance no more than 60 seconds ahead of the clock, a seven-day signed lifetime and an expiration strictly later than now. The local validation timestamp cannot extend the signed expiration.
- Completion of the launch validation attempt. Only transport errors, HTTP 429 and 5xx preserve valid offline access. Explicit HTTP 403 revokes it; malformed tokens, invalid signatures and unexpected responses fail closed.

Legacy Polar/Dodo caches without a signed token do not unlock the app. Remaining free sessions still work, including during a pending validation. The start gate and the first-input gate both enforce entitlement; revocation before the first keystroke cannot turn an already-opened empty room into a fourth free session. A draft already being written is not erased by a license check.

Successful renewal replaces the persisted token only after checking signature, product, installation and activation ID. Older validation responses cannot overwrite a newer validation or activation. An activation persistence failure restores the previous settings and attempts to release only the new allocation; it never deactivates the previously accepted instance. Concurrent activation submissions are ignored while one is in flight.

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

The window command requires Go, Python 3, jq and a permitted cua-driver daemon. The license-only mode seeds three used trial sessions, proves the fourth start is blocked, then activates a copied app against a disposable loopback fixture, writes in the real editor, restarts offline and restarts with a refund response. It does not exercise the three prior trial sessions or motion timing in the window; deterministic Swift tests cover those behaviors. Without license-only mode the existing full-window motion checks remain available. The fixture uses a fresh in-memory Ed25519 key; no Waffo request is made and the distributable app's configuration stays unchanged. `WaffoLicenseClientTests` verifies HTTP payloads, signature failures, persisted legacy denial, renewal, refund rejection and exact offline deadlines. `LicenseFlowTests` retains concurrency and rollback coverage.

For genuine acceptance, configure a test build with the verified service public configuration, buy a Waffo **test-mode** order, confirm the signed callback reached the service, then enter the buyer-visible order number in the real app. Record only a redacted pass/fail result and screenshots without buyer credentials in `MANUAL_QA.md`. Never log or commit order numbers, tokens, private keys or request bodies from real purchases. Production purchase and deployment require separate authorization.
