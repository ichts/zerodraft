# Write It Down license service

This is a test-mode-only service, not a verified Waffo integration. It has no working checkout adapter and has not processed a real Waffo test order, callback or receipt. `POST /api/v1/checkout` fails closed with HTTP 503. No request from this service contacts Waffo. Do not connect production money or claim the purchase path works. The Mac release now requires the paid Waffo path. The separate free Mac trial release is canceled. A genuine TEST checkout, buyer credential delivery, signed completion, Mac activation and refund revocation are release gates; local fixtures alone do not satisfy them.

The existing callback envelope and signature format below are local skeleton assumptions, not verified provider facts. Do not infer signature encoding, checkout response shape or receipt order-number visibility from fixtures. A buyer cannot activate until a signed completion creates the license; there is no GraphQL fallback or receipt lookup.

## Merchant configuration and pending evidence

Trefoil Studio is the outward seller brand; Write It Down remains the product. The reported dedicated store is `STO_1p1XpirhbkmZIfDkXzGCok` and product is `PROD_4YM4NKcWOOqsBOIuKbBDcy`, named "Write It Down for Mac", one-time USD 4.99, two Macs and a 14-day refund offer. These are configuration facts, not proof of a purchase or refund. Only this dedicated store is in scope. The previous shared-store fallback is withdrawn. Do not borrow or rotate any translation-site credentials. Waffo keys are merchant-scoped, so a dedicated store does not remove the need for exact product-ID filtering on every callback, including refunds. Missing or mismatched product IDs must fail closed.

The canonical callback target is `https://licenses.writeitdown.app/api/v1/webhooks/waffo`, matching this code and its Caddy template. The merchant operator has been asked to update TEST from the earlier `/waffo/webhook` path; the remote change and receiver deployment remain unverified. LIVE is unset.

The reported provider scheme is RSA-SHA256 over `${t}.${rawBody}`, with `X-Waffo-Signature: t=<milliseconds>,v1=<base64>`, a 45-minute timestamp tolerance and event-ID deduplication. This is a prose description, not an observed contract. The skeleton instead base64-decodes the whole signature header and verifies raw body alone, so it is incompatible with that description. Do not change the verifier from prose or manufacture fixtures as proof. First capture genuine TEST callback headers and exact raw bytes through a restricted channel, compare them with the implementation, and only then implement and test the observed format.

Before enabling TEST checkout, obtain through the approved safe channel:

- The exact timestamp/signature headers, signature encoding and RSA padding, signed-byte construction, replay-time policy and mode-specific callback public-key provenance. No private-key values belong in evidence reports.
- Authentic TEST completion and refund callbacks with exact event names and product/order identifiers. Confirm what the merchant's configured event set sends; do not infer fields from fixtures. Keep raw credential-bearing captures restricted, not in source or chat.
- A genuine dedicated-product TEST checkout and buyer-visible receipt credential, followed by signed callback processing, activation, third-install denial and genuine TEST refund revocation. This requires a separately authorized, verified receiver first; a configured URL alone is not a deployment.
- Proof that TEST now targets the canonical `/api/v1/webhooks/waffo` route, plus separately approved receiver deployment and key-handling verification.

Paid-release priority does not authorize production deployment, LIVE requests or real charges. TEST receiver deployment still requires a specifically approved host and safe configuration. TEST and LIVE keys being provisioned does not itself authorize their use.

## Run and validate

From this directory:

```sh
go test ./... && go vet ./... && go build .
go test -race ./...
```

Tests generate disposable keys and fake signed events. `TestHTTPLicenseLifecycle` exercises a real local HTTP listener for signature rejection, signed completion, replay, activation, third-install denial, refund revocation and checkout rejection. It is deterministic local integration coverage, not a Waffo test purchase. SQLite uses the existing pure-Go `modernc.org/sqlite` driver.

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

Provision keys outside the repository. Distribute only the Ed25519 public key to clients. Never log bodies, tokens or order IDs. Bind only to loopback behind a trusted TLS proxy. The proxy must preserve `/api/` paths and overwrite `X-Real-IP` with its direct client's IP if proxy trust is enabled. Never reuse a database for another product or environment.

The server has bounded HTTP headers, bodies, connection timeouts and graceful shutdown. Client routes and the callback route have separate budgets: each permits 30 requests per IP per minute, 300 requests globally per minute and 16 concurrent handlers. Each IP table is capped at 4096 entries. Quota exhaustion returns 429 with `Retry-After: 60`; concurrency exhaustion returns 503 with `Retry-After: 1`. Limits are in-memory and reset on restart. They bound process work, not distributed attacks; the TLS proxy and host still need network-level abuse protection. Responses use `Cache-Control: no-store`.

## HTTP contract

All routes use `POST` under `/api/v1/`. Client requests use JSON. There is no public administration endpoint.

- `/checkout`: returns `503 {"error":"checkout_not_configured"}`. It cannot create a payment, redirect to an unverified provider URL or activate a license. Verified provider facts must precede an implementation.
- `/webhooks/waffo`: the provisional local contract is raw-body RSA-SHA256 PKCS#1 v1.5 with base64 `X-Waffo-Signature`, verified against the pinned test public key. The envelope is `{ "id": "...", "eventType": "order.completed", "environment": "test", "data": { "orderId": "...", "productId": "..." } }`. Only `order.completed` and `refund.succeeded` are accepted. Product, environment and bounded identifiers must match. Invalid signatures return 401. This is not a claim about Waffo's actual wire format.
- `/licenses/activate`: `{ "orderId": "...", "installLabel": "random stable install UUID", "platform": "macos|windows" }`. Order ID is a bearer credential. Returns `{ "token": "..." }`. At most two active installations; repeating the same installation reuses its slot. A third installation returns 409. Unknown and revoked orders return 403.
- `/licenses/validate`: `{ "token": "..." }`. Checks license and installation state and returns a renewed `{ "token": "..." }`. Invalid, expired, deactivated or revoked credentials return 403.
- `/licenses/deactivate`: `{ "token": "..." }`. Frees the installation slot and returns `{ "status": "deactivated" }`.

Callback receipt and license changes commit together. A replay with the same event ID and exact body is acknowledged once. Reusing an ID with a different body returns 409, rather than silently discarding a refund. Startup adds a body-hash column to older skeleton databases. Old receipts have no provable hash, so their replays return 409 and need operator review. Refunds create terminal tombstones even before completion; a delayed completion cannot restore a revoked license. A signed refund is honored regardless of age. Waffo's verified merchant configuration and operator process, not this service, must implement the 14-day refund policy.

## Mac token contract

The token is `base64url(payload).base64url(signature)`, both unpadded. Ed25519 signs the ASCII base64url payload segment, not decoded JSON. Payload keys are `licenseId`, `activationId`, `installLabel`, `product`, `issuedAt` and `expiresAt`; timestamps are Unix seconds. The product is the configured test product ID. Expiration is seven days after activation or online validation.

An offline client must verify the signature with the embedded public key, product, stable installation binding, issue time and expiry. Server verification permits at most 60 seconds of future issuance and requires an exact seven-day validity interval. The native client owns the fourth-use barrier; this service does not track writing sessions. An expired token cannot renew through `/validate`; the buyer must activate again with the order credential, reusing the same installation slot.

An offline token cannot learn about a refund. Revocation takes effect on the next online validation or activation, or when the token expires, at most seven days later. Do not promise immediate offline revocation.

For Mac integration, configure the service origin, exact product ID and base64-encoded raw 32-byte Ed25519 public key. These are distinct from the Waffo RSA callback key. The current credential input is `orderId`, an opaque 8-100 byte string matched exactly against the stored callback order ID. The service does not trim, case-fold, translate an order number or look up aliases. `TestActivationRequiresExactOrderCredential` proves that local behavior only. No separately generated purchase-code issuance or delivery mechanism exists.

A buyer-visible order number is usable only if genuine TEST receipt and signed callback evidence establish its exact mapping to the stored credential, and it is suitable as a bearer secret rather than a predictable public reference. The current merchant configuration provides neither proof. A separate code is not inherently required if the receipt already delivers a suitable credential; it may be needed if it does not. Do not decide from field names or synthetic fixtures. Compare the actual buyer receipt, completion and refund fields through the restricted evidence channel first, then coordinate any credential-field change with the Mac client.

## Operations

An authorized operator can revoke a disputed order offline. Set `LICENSE_DB` and `LICENSE_ORDER_ID` in a protected operator environment and run `go run . revoke`. Coordinate with the service and avoid shell history containing credentials. Revocation remains terminal after late callbacks.

Run one server against the database. Back up with SQLite's online backup API or `sqlite3 .backup`, not by copying a live database file. Keep encrypted off-host copies and test restoration. Database backups contain order credentials. A restore must reconcile refunds received since the snapshot before serving buyers.

`deploy/README.md` owns the unexecuted Hetzner/Caddy/systemd test deployment plan, key permissions, backup templates and genuine test-order evidence checklist. No host is selected or changed by this repository. Payment enablement remains blocked on the evidence listed above, safe test configuration, a genuine test order and refund proof. These are blockers for the paid Mac release. Live payments require a separate explicit release decision.
