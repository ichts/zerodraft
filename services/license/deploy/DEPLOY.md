# Stripe receiver replacement and mode switch

Maintainer-only instructions for the existing `licenses.writeitdown.app` host. Build `dc2dff5` is already deployed. This bundle is a full replacement binary fixing Stripe rotation-header verification and adding the environment switch and buyer credential route, not a patch. It does not deploy itself, contact Stripe LIVE or authorize a live charge. Prove the genuine TEST purchase first. No tunnel is needed; the host already proxies `/api/*` to `127.0.0.1:8060`.

## 1. Verify the bundle and the existing signing key

Transfer the bundle privately to the approved Linux amd64 host. It contains no private signing key, webhook secret or API key. Run all blocks in the same operator shell, with `BUNDLE` set to its absolute directory:

```sh
set -eu
BUNDLE=/absolute/path/to/deploy-bundle-REVISION
cd "$BUNDLE"
sha256sum -c SHA256SUMS
TOKEN_KEY=/etc/writeitdown-license/stripe-token.pem
EXPECTED_PUBLIC='ZjyVb5Twq4UPWjattEuyWZdSr0nsAYslV41RJtFtBsw='
verify_token_key() {
    actual=$(sudo openssl pkey -in "$TOKEN_KEY" -pubout -outform DER | python3 -c '
import base64, sys
value = sys.stdin.buffer.read()
prefix = bytes.fromhex("302a300506032b6570032100")
assert value.startswith(prefix) and len(value) == len(prefix) + 32
print(base64.b64encode(value[len(prefix):]).decode())')
    test "$actual" = "$EXPECTED_PUBLIC"
}
verify_token_key
test "$(sudo stat -c '%a' "$TOKEN_KEY")" = 600
```

This is the host's existing authoritative Ed25519 key. Its raw public key above is public and must be pinned in the Mac release configuration before genuine activation acceptance; the source `Info.plist` still leaves that configuration empty. **Never regenerate or replace the private key.** That silently invalidates every installed app. Never paste, print, commit or copy it into a deployment bundle. Verify the public key before and after every deployment and mode switch. Keep `LICENSE_TOKEN_PRIVATE_KEY_FILE` pointed at this existing file.

## 2. Preserve the current deployment

Create a new restricted rollback directory. Do not overwrite earlier rollback sets, copy a live SQLite file, or replace the signing key:

```sh
ROLLBACK=/opt/writeitdown-license/rollback-$(date -u +%Y%m%dT%H%M%SZ)
sudo mkdir -m 0700 "$ROLLBACK"
sudo cp -p /opt/writeitdown-license/license "$ROLLBACK/license"
sudo cp -p /etc/writeitdown-license/service.env "$ROLLBACK/service.env"
sudo chmod 0600 "$ROLLBACK/service.env"
sudo cp -p /etc/systemd/system/writeitdown-license.service "$ROLLBACK/writeitdown-license.service"
sudo cp -p /etc/systemd/system/writeitdown-license-backup.service "$ROLLBACK/writeitdown-license-backup.service"
sudo cp -p /opt/writeitdown-license/backup.sh "$ROLLBACK/backup.sh"
sudo cp -p /etc/caddy/Caddyfile "$ROLLBACK/Caddyfile"
sudo systemctl start writeitdown-license-backup.service
```

Record the rollback directory path privately. The backup unit uses SQLite's online backup for the configured `LICENSE_DB`. Retain the database across this replacement and future mode switches. Do not restore an old database across refunds. The bundle's backup script keeps separate dated prefixes for different database filenames.

## 3. Keep the existing TEST environment

GB created TEST endpoint `we_1UTg3oRs8qwanmEvF0C457ya` at `https://licenses.writeitdown.app/api/v1/webhooks/stripe` for `checkout.session.completed`, `checkout.session.expired` and `charge.refunded`. The TEST `STRIPE_WEBHOOK_SECRET` and `STRIPE_SECRET_KEY` already live on the maintainer machine and go directly into the server environment. They never reach the build worker or bundle. Never echo them, use `set -x`, put them in shell history or pass their values on a command line.

Review the existing protected environment file in an editor. Do not install the blank example over its secrets:

```sh
sudoedit /etc/writeitdown-license/service.env
sudo chmod 0600 /etc/writeitdown-license/service.env
```

Keep these nonsecret settings, the existing database path and the existing signing key:

```text
LICENSE_PROVIDER=stripe
LICENSE_ENVIRONMENT=test
LICENSE_DB=/var/lib/writeitdown-license/stripe-test.db
LICENSE_LISTEN_ADDR=127.0.0.1:8060
LICENSE_TRUST_LOOPBACK_PROXY=true
LICENSE_PRODUCT_ID=prod_VUeTDTehcGAqJK
LICENSE_TOKEN_PRIVATE_KEY_FILE=/etc/writeitdown-license/stripe-token.pem
STRIPE_PRICE_ID=price_1UTfAfRs8qwanmEvfAEXBx8i
STRIPE_API_BASE=https://api.stripe.com
```

`LICENSE_PRODUCT_ID` is the stable app/token product, not the LIVE Stripe billing-product ID. Do not change it on a mode switch. `STRIPE_PRODUCT_ID` is an optional fallback only when `LICENSE_PRODUCT_ID` is absent; if present, leave it fixed as well. Exact price-ID verification is the billing boundary. TEST and LIVE Stripe products/prices may differ without changing the token product or DMG. The same database preserves licenses from both modes.

Startup refuses an absent webhook secret, API key, price or stable app product. The API key must be `sk_test_` in TEST and `sk_live_` in LIVE. Both the event and its object must explicitly match the configured `livemode`; a mismatch returns 401 and changes nothing. The Waffo route and its TEST-only verifier remain independent and unchanged.

## 4. Install and verify the replacement binary

```sh
sudo install -m 0755 -o root -g root "$BUNDLE/license-linux-amd64" /opt/writeitdown-license/license.new
sudo mv /opt/writeitdown-license/license.new /opt/writeitdown-license/license
sudo install -m 0644 -o root -g root "$BUNDLE/writeitdown-license.service" /etc/systemd/system/writeitdown-license.service
sudo install -m 0644 -o root -g root "$BUNDLE/writeitdown-license-backup.service" /etc/systemd/system/writeitdown-license-backup.service
sudo install -m 0644 -o root -g root "$BUNDLE/backup.sh" /opt/writeitdown-license/backup.sh
sudo systemd-analyze verify /etc/systemd/system/writeitdown-license.service /etc/systemd/system/writeitdown-license-backup.service
sudo systemctl daemon-reload
sudo systemctl restart writeitdown-license
sudo systemctl is-active --quiet writeitdown-license
verify_token_key
curl --fail --silent --show-error http://127.0.0.1:8060/api/v1/health
sudo systemctl start writeitdown-license-backup.service
sudo systemctl enable --now writeitdown-license-backup.timer
sudo ss -ltnp 'sport = :8060'
```

The listener must remain loopback-only and health must return `ok`. The health route does not touch the database and is not purchase acceptance. Retain the source revision and binary SHA-256 as deployment evidence. Linux systemd verification belongs to the maintainer; the build machine does not claim it ran those units.

## 5. Verify the permanent proxy and buyer route

The permanent-site stanza in [`Caddyfile.example`](Caddyfile.example) routes `/api/v1/*` to `127.0.0.1:8060`. A prepared bundle may extract it as `Caddyfile.stripe`. Keep the host's existing broader `/api/*` route if already correct. Do not append a duplicate hostname or replace other sites. Use `handle`, not `handle_path`, so the path survives. Overwrite `X-Real-IP` with the direct client address.

Never enable request-body, Checkout URL, session-ID, query-string, licence-key or buyer-address logging. `session_id` is the only bearer protection for buyer key retrieval. The success page must also suppress analytics/referrer/query leakage and remove the credential from its visible URL when no longer needed. Only the exact `https://writeitdown.app` origin receives browser CORS permission for checkout/retrieval; there are no cookies or credentialed CORS.

Validate the existing or safely merged Caddy configuration:

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl --fail --silent --show-error https://licenses.writeitdown.app/api/v1/health
```

The Checkout return URLs, buyer retrieval response and activation credential are defined in [`../README.md`](../README.md#stripe-adapter). The current `writeitdown/mac.html` has not yet implemented the buyer receipt flow; complete that integration before the genuine purchase acceptance below.

## 6. Prove the genuine TEST purchase before LIVE

Create a TEST Checkout without printing the hosted URL:

```sh
umask 077
EVIDENCE=$(mktemp -d /var/tmp/wid-stripe-acceptance.XXXXXX)
curl --fail --silent --show-error --request POST \
  --output "$EVIDENCE/checkout.json" \
  https://licenses.writeitdown.app/api/v1/checkout
chmod 0600 "$EVIDENCE/checkout.json"
```

Open the returned URL privately in a browser. Verify Trefoil Studio, Write It Down for Mac, USD 4.99 one-time and TEST mode. Use a Stripe TEST card, never a real card. Check that the receipt page receives the substituted session ID and displays its key only after the genuine completion webhook. Before payment, that session must return 404. Save a session ID only into a mode-0600 file, never a command argument or report. An operator can test retrieval without placing its value in shell history:

```sh
# Populate this private file in an editor from the buyer's substituted return URL.
: > "$EVIDENCE/session-id.txt"
chmod 0600 "$EVIDENCE/session-id.txt"
vi "$EVIDENCE/session-id.txt"
python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.write_bytes(p.read_bytes().removesuffix(b"\n"))' "$EVIDENCE/session-id.txt"
curl --fail --silent --show-error --get \
  --data-urlencode "session_id@$EVIDENCE/session-id.txt" \
  --output "$EVIDENCE/license.json" \
  https://licenses.writeitdown.app/api/v1/license
chmod 0600 "$EVIDENCE/license.json"
```

The session-ID file must have no trailing newline. Keep these private files out of reports and ordinary logs. Confirm one licence/binding per session; redelivery and repeat receipt reads must not issue a second key. An unknown or expired session must return the neutral 404. Record only aggregate results and revision, never a buyer credential.

Activate the actual Mac app with that key. It must pin the existing host public key and the fixed product above. Confirm two installations, third-install denial, and a genuine TEST refund followed by failed online validation and 404 from buyer retrieval. Offline tokens remain usable for at most seven days. Local Go tests and signed synthetic fixtures do not prove this real purchase/app path. Sol review and Opus final read remain money-path gates.

## Switch TEST to LIVE

Only after the genuine TEST loop and required reviews are green, the maintainer can switch the same binary by changing exactly these four environment values:

| Variable | TEST | LIVE |
| --- | --- | --- |
| `LICENSE_ENVIRONMENT` | `test` | `live` |
| `STRIPE_SECRET_KEY` | Maintainer's TEST API secret | Maintainer's LIVE API secret |
| `STRIPE_WEBHOOK_SECRET` | TEST endpoint signing secret | LIVE endpoint's own signing secret |
| `STRIPE_PRICE_ID` | TEST $4.99 one-time price | Verified LIVE $4.99 one-time price |

The webhook URL stays `https://licenses.writeitdown.app/api/v1/webhooks/stripe`. The LIVE endpoint has its own signing secret; never reuse the TEST endpoint secret. Do not change `LICENSE_PRODUCT_ID`, `LICENSE_TOKEN_PRIVATE_KEY_FILE`, the database, API base, token format or claims. TEST and LIVE use **one Ed25519 key, one pinned public key and one app product ID**. A DMG configured with that public key and product can verify either mode's issued token. There is no rebuild, code edit or mode-specific migration.

Keep the four TEST values privately for rollback, edit the existing environment file through the secret channel, then restart:

```sh
sudo cp -p /etc/writeitdown-license/service.env "$ROLLBACK/service.env.test-mode"
sudo chmod 0600 "$ROLLBACK/service.env.test-mode"
sudoedit /etc/writeitdown-license/service.env
sudo systemctl restart writeitdown-license
sudo systemctl is-active --quiet writeitdown-license
verify_token_key
curl --fail --silent --show-error https://licenses.writeitdown.app/api/v1/health
```

Post-switch acceptance must prove health `ok`, a correctly signed LIVE completion with both `livemode:true` values creating one licence, replay without duplication, and a correctly signed TEST event returning 401 without mutation. The build worker proves these gates only with local generated HMAC secrets and loopback fixtures, never real LIVE secrets or charges. Genuine LIVE execution is a separate operator action after TEST proof; do not forge fixtures with a real webhook signing secret. Configuration capability alone is not permission to charge a customer or evidence of a working LIVE purchase.

Rollback to TEST changes those same four values back, without replacing the key, binary or database:

```sh
sudo cp -p "$ROLLBACK/service.env.test-mode" /etc/writeitdown-license/service.env
sudo systemctl restart writeitdown-license
sudo systemctl is-active --quiet writeitdown-license
verify_token_key
curl --fail --silent --show-error https://licenses.writeitdown.app/api/v1/health
```

TEST completion must again succeed and LIVE envelopes must be rejected. Existing issued tokens from either mode still verify with the same key/product/format. Online validation also preserves existing active licences across modes. Coordinate webhook delivery during rollback and reconcile any refunds rejected while the other mode was active before re-enabling that mode.

## Roll back the replacement build

If replacement startup or checks fail, restore the saved binary/environment/units and, only if changed, Caddy configuration. Never restore an old database over new refunds or replace the host token key:

```sh
sudo systemctl stop writeitdown-license
sudo cp -p "$ROLLBACK/license" /opt/writeitdown-license/license
sudo cp -p "$ROLLBACK/service.env" /etc/writeitdown-license/service.env
sudo cp -p "$ROLLBACK/writeitdown-license.service" /etc/systemd/system/writeitdown-license.service
sudo cp -p "$ROLLBACK/writeitdown-license-backup.service" /etc/systemd/system/writeitdown-license-backup.service
sudo cp -p "$ROLLBACK/backup.sh" /opt/writeitdown-license/backup.sh
sudo cp -p "$ROLLBACK/Caddyfile" /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl daemon-reload
sudo systemctl start writeitdown-license
sudo systemctl reload caddy
sudo systemctl is-active --quiet writeitdown-license
verify_token_key
```

Coordinate rollback so concurrent host changes are not lost. The old TEST-only binary lacks buyer retrieval and LIVE switching; do not present it as the new purchase path. Preserve the current database and reconcile pending payment/refund events before resuming checkout.
