# Stripe TEST receiver deployment

Maintainer-only instructions for the existing `licenses.writeitdown.app` host. This bundle does not deploy itself. No tunnel is needed. The existing host already proxies `/api/*` to `127.0.0.1:8060`; preserve other sites and paths. This release enables TEST only, not LIVE. Existing Waffo transport verification and its private-vector posture are unchanged.

## 1. Verify the bundle and preserve the current service

Transfer the bundle privately to the approved Linux amd64 host. Set `BUNDLE` to its absolute directory. Run these commands on that host, not on the build machine:

```sh
set -eu
BUNDLE=/absolute/path/to/deploy-bundle-REVISION
cd "$BUNDLE"
sha256sum -c SHA256SUMS
sudo install -d -m 0700 /var/lib/writeitdown-license
sudo install -d -m 0750 -o root -g writeitdown-license /etc/writeitdown-license
sudo install -d -m 0755 /opt/writeitdown-license
# A previous rollback set must be archived privately first, never overwritten.
sudo test ! -e /opt/writeitdown-license/license.pre-stripe-test
sudo cp -p /opt/writeitdown-license/license /opt/writeitdown-license/license.pre-stripe-test
sudo cp -p /etc/writeitdown-license/service.env /etc/writeitdown-license/service.env.pre-stripe-test
sudo chmod 0600 /etc/writeitdown-license/service.env.pre-stripe-test
sudo cp -p /etc/systemd/system/writeitdown-license.service /etc/systemd/system/writeitdown-license.service.pre-stripe-test
sudo cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.pre-stripe-test
sudo cp -p /opt/writeitdown-license/backup.sh /opt/writeitdown-license/backup.sh.pre-stripe-test
sudo cp -p /etc/systemd/system/writeitdown-license-backup.service /etc/systemd/system/writeitdown-license-backup.service.pre-stripe-test
```

These commands assume the existing service account, binary and configuration are present, as on the chosen host. Stop if that assumption is false. Do not invent a new host or overwrite another service. Preserve any active Waffo database; Stripe uses a new database below. Do not copy a live SQLite file for backup. The updated backup service reads the protected environment file and backs up the selected `LICENSE_DB` through SQLite's online backup. Its script retains each database's dated backups separately. The timer schedule is unchanged.

## 2. Provision secrets outside the bundle

Use the approved secret channel for GB's TEST API secret key and TEST webhook signing secret. Never echo them, pass them on the command line, use `set -x`, put them in shell history, or include populated files in the bundle. Register only these events in TEST mode:

- `checkout.session.completed`
- `checkout.session.expired`
- `charge.refunded`

The exact endpoint is `https://licenses.writeitdown.app/api/v1/webhooks/stripe`. Confirm that URL with GB. A random local fixture secret is not the Stripe endpoint secret.

Create a separate Stripe token signing key without replacing a prior key:

```sh
sudo test ! -e /etc/writeitdown-license/stripe-token.pem
sudo sh -c 'umask 077; openssl genpkey -algorithm ED25519 -out /etc/writeitdown-license/stripe-token.pem'
sudo chown writeitdown-license:writeitdown-license /etc/writeitdown-license/stripe-token.pem
sudo chmod 0600 /etc/writeitdown-license/stripe-token.pem
sudo install -m 0600 -o root -g root "$BUNDLE/service.env.example" /etc/writeitdown-license/service.env
sudoedit /etc/writeitdown-license/service.env
```

Set these nonsecret values in the editor and fill only the two secret fields through the secret channel:

```text
LICENSE_PROVIDER=stripe
LICENSE_ENVIRONMENT=test
LICENSE_DB=/var/lib/writeitdown-license/stripe-test.db
LICENSE_LISTEN_ADDR=127.0.0.1:8060
LICENSE_TRUST_LOOPBACK_PROXY=true
LICENSE_PRODUCT_ID=prod_VUeTDTehcGAqJK
LICENSE_TOKEN_PRIVATE_KEY_FILE=/etc/writeitdown-license/stripe-token.pem
STRIPE_PRODUCT_ID=prod_VUeTDTehcGAqJK
STRIPE_PRICE_ID=price_1UTfAfRs8qwanmEvfAEXBx8i
STRIPE_API_BASE=https://api.stripe.com
```

`STRIPE_WEBHOOK_SECRET` and `STRIPE_SECRET_KEY` must be populated privately. Only a TEST `sk_test_` API key is accepted. The Waffo public key field is unused in Stripe mode. Leave callback capture disabled. Give the Mac integration worker only the Ed25519 public key, never this private key. A disposable build-machine token key is not suitable for that deployment.

```sh
sudo chown writeitdown-license:writeitdown-license /var/lib/writeitdown-license
sudo chmod 0700 /var/lib/writeitdown-license
sudo chmod 0600 /etc/writeitdown-license/service.env
```

## 3. Install and start the reviewed TEST build

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
sudo systemctl start writeitdown-license-backup.service
sudo systemctl enable --now writeitdown-license-backup.timer
curl --fail --silent --show-error http://127.0.0.1:8060/api/v1/health
```

A missing webhook secret, price, matching product or unsafe token key must fail startup. An unset API key permits health/signature testing but checkout returns 503 and real session line-item verification cannot proceed. Do not treat health as purchase acceptance.

## 4. Verify the permanent proxy

`Caddyfile.stripe` contains only the permanent site's stanza. The bundle also contains `Caddyfile.example` for context. Merge the permanent stanza into the existing site only if needed. Do not append a duplicate hostname, replace the whole configuration or remove unrelated sites. `handle`, not `handle_path`, preserves `/api/v1/*`; the proxy overwrites `X-Real-IP` with its direct client address. Do not enable request-body, buyer, token or Checkout URL logging.

```sh
sudoedit /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl --fail --silent --show-error https://licenses.writeitdown.app/api/v1/health
```

Both health checks must return `ok`. Verify the listener is loopback-only with `sudo ss -ltnp 'sport = :8060'`. A public URL cannot prove which build is running, so retain the bundle revision/checksum as deployment evidence.

## 5. Prove the genuine TEST purchase path before LIVE

Create a TEST Checkout without printing its hosted URL:

```sh
umask 077
EVIDENCE=$(mktemp -d /var/tmp/wid-stripe-acceptance.XXXXXX)
curl --fail --silent --show-error --request POST \
  --output "$EVIDENCE/checkout.json" \
  https://licenses.writeitdown.app/api/v1/checkout
chmod 0600 "$EVIDENCE/checkout.json"
```

Open the returned URL privately in a browser. Verify Trefoil Studio, Write It Down for Mac, USD 4.99 one-time and TEST mode. Pay using Stripe's TEST card, never a real card. Keep the Checkout URL, session ID and buyer address out of reports. Confirm a genuine signed `checkout.session.completed` creates one license and one binding. Redeliver the same event and confirm aggregate counts do not change. Save only nonsecret results, revision and event type in the report.

Verify exact buyer credential delivery separately. The service currently uses the Checkout session ID as `orderId`; no delivery mechanism is implemented in this adapter. Activate the native Mac client using the deployment's public signing key and matching product. Confirm two installations, third-install denial, and a genuine TEST refund followed by failed online validation. Offline tokens remain valid for at most seven days. The native client migration and buyer delivery are follow-up gates, not proven by this bundle.

Synthetic HMAC fixtures must use a locally generated secret on a disposable local receiver, never the real Stripe webhook secret. Local signature tests are not a substitute for the genuine TEST card/webhook/refund path. No LIVE key, mode, real charge or paid release is authorized by these commands. Sol review and Opus final read are still required for the money path.

## Rollback

Roll back immediately on failed startup or verification. This restores the previous binary/environment/unit and proxy, not the Stripe database. Do not overwrite a database snapshot across refunds. Preserve the new Stripe database privately for reconciliation, even if the adapter is disabled.

```sh
sudo systemctl stop writeitdown-license
sudo cp -p /opt/writeitdown-license/license.pre-stripe-test /opt/writeitdown-license/license
sudo cp -p /etc/writeitdown-license/service.env.pre-stripe-test /etc/writeitdown-license/service.env
sudo cp -p /etc/systemd/system/writeitdown-license.service.pre-stripe-test /etc/systemd/system/writeitdown-license.service
sudo cp -p /etc/caddy/Caddyfile.pre-stripe-test /etc/caddy/Caddyfile
sudo cp -p /opt/writeitdown-license/backup.sh.pre-stripe-test /opt/writeitdown-license/backup.sh
sudo cp -p /etc/systemd/system/writeitdown-license-backup.service.pre-stripe-test /etc/systemd/system/writeitdown-license-backup.service
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl daemon-reload
sudo systemctl start writeitdown-license
sudo systemctl reload caddy
sudo systemctl is-active --quiet writeitdown-license
```

Coordinate this rollback with the maintainer so no concurrent Caddy edits are lost. Stop TEST Checkout traffic and ask GB to pause the endpoint if the Stripe adapter is disabled; reconcile undelivered refunds before re-enabling it. The earlier build may not expose `/health`; its absence after rollback alone is not a license failure.
