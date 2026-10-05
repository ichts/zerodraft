# Write It Down license service (M1 skeleton)

A standalone Go + SQLite service for one Waffo one-time product. It has **not** been checked against a real Waffo test order or receipt. Do not connect production money or merge without the owner's explicit approval. The assumption that the Waffo receipt exposes `orderId` remains unverified. No fallback Waffo GraphQL lookup is implemented: an order cannot activate until its signed webhook arrives.

## Run locally

From this directory: `go test ./...`, `go vet ./...`, then `go build .`. No Waffo network access is used. Tests create RSA keys and fake signed Waffo test-mode events. SQLite uses the pure-Go `modernc.org/sqlite` driver.

Set `LICENSE_DB` to a writable SQLite file, `LICENSE_ENVIRONMENT=test`, `LICENSE_PRODUCT_ID` to the exact test-mode Waffo product ID, `LICENSE_TOKEN_PRIVATE_KEY_FILE` to a PEM PKCS#8 Ed25519 private key file, and `WAFFO_TEST_PUBLIC_KEY_FILE` to the pinned PEM RSA public key supplied for Waffo test-mode webhook verification. Set `LICENSE_LISTEN_ADDR=127.0.0.1:8060` (default). Run `go run . serve`. This service accepts only test-mode keys and events; production mode is not available. Provision keys outside the repository with restricted file permissions; distribute only the Ed25519 **public** key to clients. Do not log HTTP bodies, tokens, or order IDs. Keep the service behind TLS and a trusted reverse proxy; do not expose the HTTP listener directly. Ensure the proxy passes `/api/` paths unchanged and handles abuse controls. Back up SQLite with its online backup API or `sqlite3 .backup` (including off-host copies), not by copying a live database file.

An authenticated operator can revoke a disputed order offline: stop or coordinate with the service, set `LICENSE_DB` and `LICENSE_ORDER_ID` in the operator shell, and run `go run . revoke`. This is deliberately not a public API. A revoked order is terminal even if a delayed completion event arrives.

## HTTP contract

All routes use `POST`, JSON and `/api/v1/`:

- `/webhooks/waffo`: signed raw-body RSA-SHA256 `X-Waffo-Signature` (base64), matched against the configured environment public key. Accepts `order.completed` and `refund.succeeded`; enforces product ID and event ID; processes repeats once. Its expected event envelope is `{ "id": "...", "eventType": "order.completed", "environment": "test", "data": { "orderId": "...", "paymentId": "...", "productId": "..." } }`. Verify the exact envelope and signature encoding with a real **test-mode** callback before shipping.
- `/licenses/activate`: `{ "orderId": "...", "installLabel": "random stable install UUID", "platform": "macos|windows" }`. Order ID is a bearer credential. At most two active installations; a repeat installation reuses its slot. Returns `{ "token": "..." }`.
- `/licenses/validate`: `{ "token": "..." }`. Checks active license and installation; returns a renewed token. Waffo owns refund eligibility and processing; any valid `refund.succeeded` revokes the license.
- `/licenses/deactivate`: `{ "token": "..." }`. Frees the installation's slot.

Tokens are base64url JSON payload plus Ed25519 signature, containing license ID, activation ID, install label, product ID, issue and expiration timestamps. An offline client verifies signature, product, binding to its installation label, non-future issuance and expiry with the embedded public key. Expiry is seven days after the most recent activation or online validation. A signed token cannot learn about a refund while offline; reconnect to enforce revocation. The trusted proxy owns abuse controls; the service has no in-process rate limiter. SQLite serializes writers per process; run one server against this database.
