# License service module

`README.md` owns the HTTP, Mac token and operational contract. `service.go` owns provisional business-event processing, SQLite licenses and activations, and offline Ed25519 tokens; `waffo.go` owns documented t/v1 callback authentication and SDK replay freshness; `migrations.go` upgrades local callback receipts for replay-conflict checks. `http.go` owns bounded request admission, proxy-address trust and the fail-closed checkout route. `capture.go` owns opt-in bounded, atomic private callback evidence, oldest-record eviction and expiry cleanup. Capture is best-effort before verification: failures never bypass or block authorization. `main.go` owns test-only configuration, key-file checks, capture configuration, loopback binding and shutdown. `admin.go` owns offline manual revocation. Default tests cover synthetic signed events and a real local HTTP listener. The explicit `wafforeal` suite uses private external captures plus a committed hash manifest; it proves transport signatures, not business mapping or a completed provider integration. `deploy/README.md` and its templates prepare an authorized test deployment; they do not deploy anything.

`README.md` owns merchant configuration, capture handling and the unverified provider contract. Treat private captures as restricted evidence, never logs or public fixtures; do not infer provider behavior from local tests. This module never contacts Waffo or stores application drafts. Keep private keys and order credentials out of logs, committed fixtures and source. Run `go test ./... && go vet ./... && go build .` here, with `go test -race ./...` for request/storage changes. Follow the README's test-order gates before enabling payments.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
