# License service module

`README.md` owns the HTTP, Mac token and operational contract. `service.go` owns provisional signed callback processing, SQLite licenses and activations, and offline Ed25519 tokens; `migrations.go` upgrades local callback receipts for replay-conflict checks. `http.go` owns bounded request admission, proxy-address trust and the fail-closed checkout route. `main.go` owns test-only configuration, key-file checks, loopback binding and shutdown. `admin.go` owns offline manual revocation. Tests cover local signed fixtures and a real local HTTP listener, not provider integration. `deploy/README.md` and its templates prepare an authorized test deployment; they do not deploy anything.

The Waffo wire format, dedicated product and buyer receipt credential remain unverified. Checkout stays unavailable until those facts arrive. Never infer them from fixtures. This module never contacts Waffo or stores application drafts. Keep private keys and order credentials out of logs, fixtures and source. Run `go test ./... && go vet ./... && go build .` here, with `go test -race ./...` for request/storage changes. Follow the README's genuine test-order gates before launch.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
