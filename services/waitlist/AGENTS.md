# Waitlist service module

`README.md` owns the HTTP, privacy, deployment, and validation contract. `waitlist.go` owns form validation, timed in-memory rate limiting, storage, and responses; `main.go` owns environment configuration and the loopback-only server lifecycle; `waitlist_test.go` covers the handler and timer lifecycle; `deploy/` holds operator templates.
