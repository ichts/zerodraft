# writeitdown.app Mac waitlist collector

A stdlib-only Go service behind the writeitdown.app reverse proxy. It collects addresses from the waitlist form on the writeitdown.app Mac page for one email when Write It Down for Mac can be bought. It is not deployed from this repository.

## HTTP contract

`POST /api/waitlist`, `application/x-www-form-urlencoded`, body at most 4 KB:

| Field | Rule |
| --- | --- |
| `email` | one bare address, at most 254 characters, dotted domain |
| `consent` | must be `yes` (the form's required checkbox) |
| `website` | honeypot; must be empty. A filled value answers `joined` and stores nothing |

Outcomes: `joined`, `invalid`, `limited` (rate limit), `error` (file write failed). A request with `Accept: application/json` gets `{"status":"<outcome>"}` with 200/400/429/500. Any other request gets `303` to `WAITLIST_RETURN_URL#waitlist-<outcome>`, which the page shows without JavaScript. A duplicate address (case-insensitive) answers `joined` and is not stored twice. A request whose `Origin` header is present and differs from `WAITLIST_ORIGIN` gets 403. `GET /api/waitlist/health` answers `ok`.

Rate limits: 5 submissions per client address and 120 overall per 10-minute window. The client address is the last `X-Forwarded-For` hop, which is sound only because the service refuses to bind anything but loopback. It is kept in memory for the window and never written.

## Storage

One line per new address appended to `WAITLIST_FILE` (mode 0600, fsync per write): `<UTC RFC3339 time>\t<email>`. Nothing else is stored. To remove an address on request, stop the service, delete its line, and start it again (the duplicate set is loaded at start).

## Environment

| Variable | Default |
| --- | --- |
| `WAITLIST_ADDR` | `127.0.0.1:8091` (loopback only) |
| `WAITLIST_FILE` | `/var/lib/writeitdown-waitlist/waitlist.tsv` |
| `WAITLIST_RETURN_URL` | `https://writeitdown.app/mac.html` |
| `WAITLIST_ORIGIN` | `https://writeitdown.app` |

## Deploy (operator, by hand)

1. `GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o writeitdown-waitlist .` (use the host's architecture), copy it to `/usr/local/bin/` (root, 0755).
2. Install `deploy/writeitdown-waitlist.service` to `/etc/systemd/system/`, then `systemctl daemon-reload && systemctl enable --now writeitdown-waitlist`.
3. Add `deploy/Caddyfile.snippet` (or `deploy/nginx.snippet`) to the writeitdown.app site and reload the proxy.
4. Check `curl -fsS https://writeitdown.app/api/waitlist/health`, submit one real test address from the page, confirm its line in the file, then remove it.

Back up `/var/lib/writeitdown-waitlist/` with the host's other state. Validate code changes with `go vet ./... && go test -race ./...`.
