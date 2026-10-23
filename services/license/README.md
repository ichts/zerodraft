# Write It Down license service

The existing Waffo sections describe the default `LICENSE_PROVIDER=waffo` TEST-only posture. The separate environment-selected Stripe adapter below does not change that verifier, private-vector suite or Waffo checkout gate.

## Stripe adapter

Select `LICENSE_PROVIDER=stripe` with `LICENSE_ENVIRONMENT=test|live`. Startup requires `STRIPE_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_PRICE_ID`, a stable `LICENSE_PRODUCT_ID`, and the existing Ed25519 token key/database settings. The API key must start with `sk_test_` in test mode or `sk_live_` in live mode. `STRIPE_API_BASE` defaults to `https://api.stripe.com`; HTTP is permitted only for a loopback test API. No Waffo key is needed in Stripe mode, and the Waffo route is unavailable in that mode. Keep the same database, app product, Ed25519 key and token format across TEST/LIVE switching. `STRIPE_PRODUCT_ID` is accepted only as a fallback for the stable app product when `LICENSE_PRODUCT_ID` is unset; it is not a second billing-product filter and must not change on the switch. The exact configured price is the billing authority, so TEST and LIVE may use different Stripe billing products without changing the Mac app's pinned product.

- `GET /api/v1/health` returns `ok` without database access. All routes retain no-store headers and bounded admission; both callback routes share the callback budget and 64 KiB body limit.
- `POST /api/v1/checkout` creates a server-side card-only, one-time Checkout Session for exactly one configured price. Its success URL is `https://writeitdown.app/mac.html?session_id={CHECKOUT_SESSION_ID}` and cancel URL is `https://writeitdown.app/mac.html`. It returns `{"url":"https://checkout.stripe.com/..."}` only when the response mode matches the configured environment and the URL is on Stripe's hosted-checkout domain. It never logs the URL, API credentials or buyer data. Waffo-selected checkout still returns its unchanged 503.
- `POST /api/v1/webhooks/stripe` authenticates the untouched body with HMAC-SHA256 over `<t>.<raw body>`, using `Stripe-Signature`. It requires one numeric timestamp, one or more well-formed hex `v1` signatures and a timestamp within 300 seconds of the injected clock. All `v1` candidates are compared in constant time; any matching candidate authenticates the body. Legacy `v0` and unknown keys are ignored, while missing/duplicate timestamps, missing `v1`, malformed `v1` hex and stale timestamps still fail closed. The adapter keeps the existing standard-library HMAC verifier rather than adding stripe-go solely for header parsing; HTTP regression tests cover actual rotation-style header shapes without weakening business gates. Signature failures return generic `401 invalid signature`.
- Both event and object must explicitly have `livemode:false` in test mode or `livemode:true` in live mode. A mismatch returns 401 without mutation. Completion requires `mode:payment`, `amount_total:499`, `currency:usd`, a paid/complete session, one unit of the exact configured price with a Stripe product reference, and a payment intent. Because Stripe normally omits `line_items` from callbacks, the adapter retrieves `/v1/checkout/sessions/{id}/line_items` with the selected API key when not included. Unverifiable sessions fail closed without issuing or revoking anything.
- Completion stores the Checkout session ID as the existing activation `orderId` and atomically binds the payment intent to its license. Expiration issues nothing. `charge.refunded` requires a matching-environment charge for USD 4.99 and a positive refunded amount, and revokes only a known payment-intent binding whose stored price, stable app product, amount, currency and payment mode match. Partial refunds also revoke. An unknown binding fails closed without recording a receipt so Stripe can retry after completion arrives. No buyer/address data is stored.
- `GET /api/v1/license?session_id=<id>` returns `{"licenseKey":"<exact Checkout session id>"}` only for an active license bound by a completed, paid session. Unknown, unpaid, expired and revoked sessions return the same neutral 404. One session issues exactly one credential; repeated reads return that same key, not a new key or a one-shot consumption marker. Submit it unchanged as `orderId` to `/api/v1/licenses/activate`; activation/validation/deactivation are unchanged. The session ID is the only bearer protection, so never log it or its URL/query. Checkout and key retrieval allow browser reads only from the exact `https://writeitdown.app` origin, without cookie credentials. The success page must also prevent query logging, analytics/referrer leakage and unnecessary URL retention.
- Separate SQLite `stripe_events` receipts deduplicate Stripe `event.id` with a raw-body hash, atomically with mutations. A changed body with the same ID returns 409. Delayed completion cannot restore a revoked license. Refund-before-completion needs a successful redelivery after the binding exists; it is not a Waffo-style tombstone.

Proven locally: deterministic signature/business rejection, session/payment-intent binding, replay/conflict handling, expiration, refund/retry, buyer key retrieval and log silence, signed-token activation and post-refund validation denial, a fake HTTP Stripe Checkout/line-item API, and database-free health. Deterministic tests and loopback restarts change only the four environment values, verify no schema change, reject cross-mode events and accept both token types with the same public key/product/format. The loopback proof also verifies both synthetic token signatures independently with OpenSSL, exercises LIVE-shaped completion/refund fixtures and rollback, and checks that keys/tokens/secrets never enter service logs. No request in that proof contacts Stripe. A loopback TEST receiver was also exercised with curl: health 200, locally signed synthetic completion 200 creating exactly one license, tampered body 401 and replay 200 with one license remaining. This is synthetic local transport evidence, not a Stripe payment. The permanent webhook target is `https://licenses.writeitdown.app/api/v1/webhooks/stripe`; deployment there belongs to the maintainer, not this worker. Its disposable signing key, secret, database and logs live outside Git under `/var/tmp/wid-stripe-test/` with private permissions.

Unproven by this worker: real Stripe TEST Checkout/card payment, genuine webhook delivery/refund, buyer receipt-page integration and native Mac activation. The maintainer has already deployed `dc2dff5`; this branch supplies a full replacement including the rotation-header regression fix, mode switch and buyer retrieval. Reported genuine callback 401s were reproduced locally with `t=...,v1=<bad>,v1=<good>,v0=...`; the regression failed before the fix and passes with the new parser. No private genuine event bytes or provider secrets were supplied to this worker. GB has registered TEST endpoint `we_1UTg3oRs8qwanmEvF0C457ya` at the permanent webhook URL. The maintainer provisions `STRIPE_WEBHOOK_SECRET` and `STRIPE_SECRET_KEY` directly into the server environment; their values never reach the worker or deployment bundle and are not a build blocker. No real Stripe secrets have been used by this worker. The Mac client is a separate follow-up, and LIVE keys, payments and deployment remain forbidden until the genuine TEST loop is green and the required reviews pass. `deploy/README.md` owns the maintainer's permanent receiver commands.

Acceptance:

```sh
go test ./... && go vet ./... && go build ./...
go test -race ./...
go test -run 'Stripe' -count=1 -v ./...
```

This is a test-mode-only service, not a complete Waffo payment integration. Its documented callback signature scheme has been verified offline against nine genuine TEST deliveries, but business-event mapping and checkout remain incomplete. It has not granted or revoked a license from those real deliveries. `POST /api/v1/checkout` fails closed with HTTP 503. No request from this service contacts Waffo. Do not connect production money or claim the purchase path works. The approved client model is a free download with three trial sessions, followed by a one-time USD 4.99 unlock for two installations, a 14-day refund policy and free updates; Windows will use the same model. The Mac client permits three local writing sessions before activation is required; see [`LICENSE_PAYMENT_SPEC.md`](../../apps/macos/FirstLine/docs/LICENSE_PAYMENT_SPEC.md) for the trial gate. A genuine TEST checkout, buyer credential delivery, signed completion, activation and refund revocation are gates for the paid path; local fixtures alone do not satisfy them.

The callback signature format below is verified against the private TEST evidence; the business envelope remains a local skeleton contract, not verified provider mapping. Do not infer signature encoding, checkout response shape or receipt order-number visibility from fixtures. A buyer cannot activate until a signed completion creates the license; there is no GraphQL fallback or receipt lookup.

## Merchant configuration and pending evidence

Trefoil Studio is the outward seller brand; Write It Down remains the product. The reported dedicated store is `STO_1p1XpirhbkmZIfDkXzGCok` and product is `PROD_4YM4NKcWOOqsBOIuKbBDcy`, named "Write It Down for Mac", one-time USD 4.99, two Macs and a 14-day refund offer. These are configuration facts, not proof of a purchase or refund. Only this dedicated store is in scope. The previous shared-store fallback is withdrawn. Do not borrow or rotate any translation-site credentials. Waffo keys are merchant-scoped, so a dedicated store does not remove the need for exact product-ID filtering on every callback, including refunds. Missing or mismatched product IDs must fail closed.

The canonical callback target is `https://licenses.writeitdown.app/api/v1/webhooks/waffo`, matching this code and its Caddy template. The approved capture-only TEST receiver received the private evidence on this canonical route. The earlier `/waffo/webhook` path is retired. This verifier change has not been deployed by this repository. LIVE is unset.

The official [webhook documentation](https://docs.waffo.ai/api-reference/webhooks), in the supplied 2026-10-20 snapshot, specifies RSA-SHA256 PKCS#1 v1.5 over `${t}.${rawBody}`, with `X-Waffo-Signature: t=<milliseconds>,v1=<base64>`. `waffo.go` requires exactly one signature header in that exact order and spelling, with no extra whitespace, a positive decimal millisecond timestamp without leading zeros and strict standard base64. Reversed, duplicate or unknown parameters, unsupported versions, malformed headers and the old bare-base64 format fail closed. The original timestamp text participates in the signature; the body is never parsed or reserialized before verification.

Freshness follows `@waffo/pancake-ts@0.26.0`: at most 45 minutes old and at most one minute ahead, with inclusive millisecond boundaries and no runtime bypass. The manual examples use a symmetric 45-minute window; this service uses the narrower SDK future allowance. Retried deliveries must still be fresh. The server uses its existing injected clock, `time.Now` in production; only tests fix the clock to the original receipt time. Signature failures return a generic `401 invalid signature` response. Event deduplication remains a separate database responsibility, not a replacement for freshness.

The official documentation describes platform-level TEST and Production webhook public keys shared across stores, distinct from merchant-level outbound API signing keys. This service pins the RSA key loaded from its configured file at startup; it does not embed or enforce a known provider fingerprint. An operator must compare that key's SPKI DER SHA-256 fingerprint with the trusted TEST source before deployment. The privately supplied deployed TEST public key matched the SDK SPKI fingerprint recorded in `testdata/waffo-real-vector-hashes.json`. All nine real signatures verify under that key in both Go and an independent offline OpenSSL check; raw-body-only input and tampered body/timestamp do not. This proves those exact signed bytes, not a working purchase path.

The real envelopes have `mode:test`, not the skeleton's `environment:test`, and lack `data.productId`. They therefore pass transport authentication at their receipt clock but still return `401 invalid environment or event` at the unchanged business gate. Trusted exact-product binding and event identity (`id` versus `eventType` plus `eventId`) remain unresolved. Do not weaken product filtering, substitute a product name, invent a store-only fallback or treat RSA success as permission to issue a license.

Before enabling TEST checkout, obtain through the approved safe channel:

- An approved business adapter based on the authenticated TEST envelopes, with authoritative exact-product/order binding, event identity, mode and final completion/refund semantics. The signature proof does not resolve these business fields. No private-key values belong in evidence reports.
- Keep the genuine completion/refund captures restricted. They contain buyer data and order credentials; only their hashes are committed. Do not redact and re-sign them while calling the result vendor evidence.
- A genuine dedicated-product TEST checkout and buyer-visible receipt credential, followed by signed callback processing, activation, third-install denial and genuine TEST refund revocation. This requires a separately authorized, verified receiver first; a configured URL alone is not a deployment.
- Separately approved deployment and fresh signed-delivery acceptance of the completed adapter on the canonical `/api/v1/webhooks/waffo` route. The earlier capture-only deployment and offline verification do not authorize this release.

Paid-release priority does not authorize production deployment, LIVE requests or real charges. TEST receiver deployment still requires a specifically approved host and safe configuration. TEST and LIVE keys being provisioned does not itself authorize their use.

## Run and validate

From this directory:

```sh
go test ./... && go vet ./... && go build .
go test -race ./...
```

Default tests generate disposable keys and synthetic events signed with the documented scheme. `TestHTTPLicenseLifecycle` exercises a real local HTTP listener for signature rejection, provisional completion, replay, activation, third-install denial, refund revocation and checkout rejection. It is deterministic local integration coverage, not proof of provider business mapping. SQLite uses the existing pure-Go `modernc.org/sqlite` driver.

The real captures contain `buyerEmail` and bearer order identifiers, so none of their bytes, signatures or public-key PEM are committed. `testdata/waffo-real-vector-hashes.json` records only nine body/metadata hash pairs and public-key fingerprints. Run the private opt-in suite with explicit external fixture paths:

```sh
WAFFO_REAL_CAPTURE_DIR=/absolute/private/capture-copy \
WAFFO_REAL_TEST_PUBLIC_KEY_FILE=/absolute/private/deployed-test-public.pem \
go test -tags wafforeal -run '^TestWaffoRealCallbackVectors$' -count=1 ./...
```

This suite requires all nine hash-matched vectors and the actual public-key copy; missing, unsafe or changed evidence fails, never silently skips. It verifies each original signature at a fixed receipt clock; tests body/timestamp tampering, a wrong public key and stale delivery as HTTP 401 **at the signature gate**; and confirms unchanged business-envelope rejection without database effects. Production freshness is never relaxed. The default public suite does not run these private vectors and must not be reported as vendor verification. Keep fixture directories outside Git and public CI; `.gitignore` also guards common private-capture/key locations.

Configure these environment variables, then run `go run . serve`:

| Variable | Requirement |
| --- | --- |
| `LICENSE_DB` | Writable SQLite file in a restricted directory |
| `LICENSE_ENVIRONMENT` | Must equal `test`; production is rejected |
| `LICENSE_PRODUCT_ID` | Exact dedicated test product ID, not a fixture ID |
| `LICENSE_TOKEN_PRIVATE_KEY_FILE` | PEM PKCS#8 Ed25519 private key, mode 0600 or stricter |
| `WAFFO_TEST_PUBLIC_KEY_FILE` | Pinned PEM PKIX RSA public key, at least 2048 bits |
| `LICENSE_LISTEN_ADDR` | Loopback IP and port, default `127.0.0.1:8060` |
| `LICENSE_TRUST_LOOPBACK_PROXY` | Optional boolean, default false; trust `X-Real-IP` only from a loopback peer |
| `LICENSE_CALLBACK_CAPTURE_DIR` | Optional absolute dedicated directory outside every web root; unset disables capture. Its existing parent and the capture directory must both be real directories with mode 0700 |

Provision keys outside the repository. Distribute only the Ed25519 public key to clients. Never log bodies, tokens or order IDs. Bind only to loopback behind a trusted TLS proxy. The proxy must preserve `/api/` paths and overwrite `X-Real-IP` with its direct client's IP if proxy trust is enabled. Never reuse a database for another product or environment.

The server has bounded HTTP headers, bodies, connection timeouts and graceful shutdown. Client routes and the callback route have separate budgets: each permits 30 requests per IP per minute, 300 requests globally per minute and 16 concurrent handlers. Each IP table is capped at 4096 entries. Quota exhaustion returns 429 with `Retry-After: 60`; concurrency exhaustion returns 503 with `Retry-After: 1`. Limits are in-memory and reset on restart. They bound process work, not distributed attacks; the TLS proxy and host still need network-level abuse protection. Responses use `Cache-Control: no-store`.

## Private TEST callback capture

Capture is opt-in and independent of Waffo verification. When enabled, complete callback bodies admitted by the existing request limits are archived before signature verification runs, including malformed JSON, rejected signatures and duplicate deliveries. A capture is untrusted evidence until authenticated, not an accepted business event. Capture does not replace any verifier or business rejection with 2xx or create a license.

Each `capture-<Unix-nanoseconds>-<random-id>/` directory contains `body.bin`, the exact application-received body bytes, and `request.json`. Metadata records UTC receipt time, method, request URI, protocol, Host, content length, transfer encoding, all parsed header names with every value, and trailers after the body has been read. Header/trailer values, Host and request URI are base64-encoded byte slices in JSON so non-UTF-8 bytes survive. Base64 is not encryption. Header spelling/order and HTTP framing have already been parsed by Go; headers rewritten or removed by a reverse proxy cannot be reconstructed. This is not a byte-for-byte wire-header capture.

The dedicated directory and each record directory use mode 0700; files use 0600. The configured parent must already exist with mode 0700. Symlinks at these directory paths and existing permissive directories are rejected rather than silently repaired. Place it in the private service state directory, never in a served site tree; there is no capture download endpoint. The operator must verify the actual proxy/web-root configuration. Captures include all application-visible headers, potentially including credentials, so never print, commit, serve, or upload them to public CI.

A record is published by an atomic directory rename after both files and the staging directory are synced. Failed writes leave no published partial record; a final directory-sync failure may leave a complete published record whose crash durability is uncertain. Interrupted staging records do not count toward the 128-record limit and are removed on startup or cleanup. Each body is limited to 64 KiB, serialized metadata to 32 KiB, and the archive to 128 published records, at most 12 MiB of payload plus filesystem overhead. At capacity, the oldest record is removed before publishing the next one, regardless of authentication status; timestamp ties use record-name order. Unsigned traffic cannot reserve all slots and deny capture space to a new signed callback. This is a rolling evidence buffer, not a guaranteed delivery history: sustained traffic can evict genuine evidence before expiry, and a failed replacement can leave fewer records.

Capture is best-effort and independent of authorization. Header-limit, capacity-management and IO failures emit only a fixed content-free alert and then continue through the unchanged signature verification and license transaction. Capture failure never grants access, returns an early 2xx or suppresses a valid refund. Unsafe capture configuration still rejects startup. Incomplete and oversized bodies keep the existing 400 response and are not saved as if complete. Requests rejected by transport, rate or concurrency limits are not captured.

Records have a maximum intended retention of 24 hours and may be evicted earlier at capacity. Cleanup runs at startup, before each capture, and every minute while capture is enabled and the service is running; idle expiry can lag by one timer interval plus scheduling delay, not a hard deletion SLA. Cleanup never removes event deduplication records or refund tombstones from SQLite. Unknown archive entries fail closed rather than being deleted. If the service stops or capture is disabled, the timer stops; the operator must arrange expiry cleanup of remaining evidence. Do not include raw captures in long-lived backups. Generic cleanup failures may be logged, never bodies or headers. Run only one service process per capture directory, as with the database.

`capture_test.go`, `capture_config_test.go` and `capture_regression_test.go` exercise byte preservation over HTTP, repeated headers and trailers, permissions, rolling capacity, observed atomic publication, expiry/restart cleanup, configuration, content-free failure alerts and unchanged local license behavior after unsigned traffic fills the archive or capture storage fails. These tests use generated keys and synthetic callbacks, not real Waffo deliveries.

## HTTP contract

All routes use `POST` under `/api/v1/`. Client requests use JSON. There is no public administration endpoint.

- `/checkout`: returns `503 {"error":"checkout_not_configured"}`. It cannot create a payment, redirect to an unverified provider URL or activate a license. Verified provider facts must precede an implementation.
- `/webhooks/waffo`: the documented `t=<milliseconds>,v1=<base64>` signature authenticates `${t}.${rawBody}` using RSA-SHA256 PKCS#1 v1.5 and the pinned TEST public key, with the freshness rules above. The unchanged provisional business envelope is `{ "id": "...", "eventType": "order.completed", "environment": "test", "data": { "orderId": "...", "productId": "..." } }`. Only `order.completed` and `refund.succeeded` are accepted. Product, environment and bounded identifiers must match. Invalid signatures return 401. Authenticated real envelopes still fail the legacy business gate; this is not a claim that provider events can grant licenses.
- `/licenses/activate`: `{ "orderId": "...", "installLabel": "random stable install UUID", "platform": "macos|windows" }`. Order ID is a bearer credential. Returns `{ "token": "..." }`. At most two active installations; repeating the same installation reuses its slot. A third installation returns 409. Unknown and revoked orders return 403.
- `/licenses/validate`: `{ "token": "..." }`. Checks license and installation state and returns a renewed `{ "token": "..." }`. Invalid, expired, deactivated or revoked credentials return 403.
- `/licenses/deactivate`: `{ "token": "..." }`. Frees the installation slot and returns `{ "status": "deactivated" }`.

Callback receipt and license changes commit together. A replay with the same event ID and exact body is acknowledged once. Reusing an ID with a different body returns 409, rather than silently discarding a refund. Startup adds a body-hash column to older skeleton databases. Old receipts have no provable hash, so their replays return 409 and need operator review. Refunds create terminal tombstones even before completion; a delayed completion cannot restore a revoked license. Refund business events have no order-age cutoff here, but their delivery signatures must still pass the replay-freshness window; stale signatures are never exempted. Waffo's verified merchant configuration and operator process, not this service, must implement the 14-day refund policy.

## Mac token contract

The token is `base64url(payload).base64url(signature)`, both unpadded. Ed25519 signs the ASCII base64url payload segment, not decoded JSON. Payload keys are `licenseId`, `activationId`, `installLabel`, `product`, `issuedAt` and `expiresAt`; timestamps are Unix seconds. The product is the configured test product ID. Expiration is seven days after activation or online validation.

An offline client must verify the signature with the embedded public key, product, stable installation binding, issue time and expiry. Server verification permits at most 60 seconds of future issuance and requires an exact seven-day validity interval. The fourth-session barrier belongs in the native client; this service does not track writing sessions. An expired token cannot renew through `/validate`; the buyer must activate again with the order credential, reusing the same installation slot.

An offline token cannot learn about a refund. Revocation takes effect on the next online validation or activation, or when the token expires, at most seven days later. Do not promise immediate offline revocation.

For Mac integration, configure the service origin, exact product ID and base64-encoded raw 32-byte Ed25519 public key. These are distinct from the Waffo RSA callback key. The current credential input is `orderId`, an opaque 8-100 byte string matched exactly against the stored callback order ID. The service does not trim, case-fold, translate an order number or look up aliases. `TestActivationRequiresExactOrderCredential` proves that local behavior only. No separately generated purchase-code issuance or delivery mechanism exists.

A buyer-visible order number is usable only if genuine TEST receipt and signed callback evidence establish its exact mapping to the stored credential, and it is suitable as a bearer secret rather than a predictable public reference. The current merchant configuration provides neither proof. A separate code is not inherently required if the receipt already delivers a suitable credential; it may be needed if it does not. Do not decide from field names or synthetic fixtures. Compare the actual buyer receipt, completion and refund fields through the restricted evidence channel first, then coordinate any credential-field change with the Mac client.

## Operations

An authorized operator can revoke a disputed order offline. Set `LICENSE_DB` and `LICENSE_ORDER_ID` in a protected operator environment and run `go run . revoke`. Coordinate with the service and avoid shell history containing credentials. Revocation remains terminal after late callbacks.

Run one server against the database. Back up with SQLite's online backup API or `sqlite3 .backup`, not by copying a live database file. Keep encrypted off-host copies and test restoration. Database backups contain order credentials. A restore must reconcile refunds received since the snapshot before serving buyers.

`deploy/README.md` owns the unexecuted Hetzner/Caddy/systemd test deployment plan, key permissions, backup templates and genuine test-order evidence checklist. No host is selected or changed by this repository. Payment enablement remains blocked on the evidence listed above, safe test configuration, a genuine test order and refund proof. These are blockers for the paid activation path. Live payments require a separate explicit release decision.
