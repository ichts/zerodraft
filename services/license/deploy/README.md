# Test deployment preparation

These are review templates, not a deployed service or an installer. No host, DNS name, product ID or Waffo credential is selected here. Do not run them against a VPS until firstmate supplies the approved host and configuration through a safe channel. Production mode is not implemented.

## Gates before deployment

- Confirm the approved Hetzner host, SSH identity, test DNS name and Caddy ownership. Do not replace an existing Caddy configuration wholesale.
- Obtain the verified Waffo test checkout and callback contract from the reference product. The current callback fixture is not provider evidence, and checkout always returns 503.
- Confirm a dedicated Write It Down one-time $4.99 product and 14-day refund policy in the correct test account. The outward seller brand is Trefoil Studio; Write It Down remains the product. GB is preparing a dedicated Trefoil Studio Waffo store. Verify legal merchant identity separately rather than deriving it from the brand.
- If the dedicated store is delayed, the existing shared store is an authorized fallback only with exact Write It Down product-ID filtering on every callback, including refunds. An event without the verified product ID must not grant or revoke a license. The local handler already rejects missing or mismatched product IDs, but the real provider envelope still needs verification. Do not borrow another product's credentials or change the translation site's API/webhook keys. Obtain verified current merchant configuration through the approved safe channel; keep checkout unavailable until then.
- Obtain the pinned Waffo test callback public key by a trusted channel. Provision the Ed25519 signing private key outside git. Send only its public key to the Mac worker.
- Run the repository acceptance command and build a Linux binary matching the approved VPS architecture. Keep the build artifact and checksum outside git.

## Host layout

After authorization, provision a dedicated `writeitdown-license` system account with no login shell. Install the reviewed binary and `backup.sh` under `/opt/writeitdown-license/`, owned by root and not writable by the service. The binary needs mode 0755; the backup script can be 0644 because its unit invokes `/bin/sh`.

Create `/etc/writeitdown-license/` as root, group `writeitdown-license`, mode 0750. Copy `service.env.example` to `service.env` and fill the verified test product ID. The environment file is root-owned, group `writeitdown-license`, mode 0640. Provision `token.pem` owned by `writeitdown-license`, mode 0600. The service rejects group/world-readable private keys. Install the pinned Waffo public key as root-owned mode 0644. Keep all keys out of shell history, command output, CI artifacts and logs. Never use `set -x` around provisioning.

Systemd creates `/var/lib/writeitdown-license/` as mode 0700. The service's umask is 0077; the database, WAL and backups contain order credentials and need that protection. Use one service process per database. Do not share the database across products or environments.

Install the service, backup service and timer units from this directory. Review them with `systemd-analyze verify` on the target before enabling them. `sqlite3` must be installed for the backup unit. Review Caddy's version and validate the merged site stanza with `caddy validate`; this repository has not validated it on Linux. Use the approved public test hostname in place of `example.invalid`, with automatic HTTPS. Preserve `/api/` paths unchanged. Never publish port 8060; the binary also rejects non-loopback bind addresses. If Caddy itself sits behind another proxy, review the client-IP trust boundary rather than passing forwarded headers blindly.

The service trusts `X-Real-IP` only when `LICENSE_TRUST_LOOPBACK_PROXY=true` and its immediate peer is loopback. The Caddy template overwrites that header with the direct client address. Other local processes are therefore part of the trusted host boundary. Keep request-body and credential logging disabled, including proxy tracing.

## Backups and recovery

The daily timer runs SQLite's online backup, checks integrity, and retains about 14 days of dated local snapshots. It does not copy a live database file. Each backup contains bearer order IDs. Provision encrypted off-host copies with restricted access separately; the template does not claim off-host protection. Back up the token signing key separately, encrypted, through the approved secret channel. Loss of that key invalidates existing offline tokens.

Before launch, restore a snapshot into a separate restricted directory and run SQLite integrity and license-count checks there. Do not print order IDs. Prove the restored test database can activate and reject a revoked order. Replacing the running database requires an authorized maintenance stop and a consistent restore; stale WAL/SHM files must not be mixed with another snapshot. A snapshot taken before a refund can resurrect its license. Reconcile all refunds since the backup before serving a restored database. Do not roll back across an unknown schema migration without a restore plan.

## Required test-order record

After the provider adapter is verified and implemented, the operator must record, without credentials:

1. Test hostname and deployment revision, with HTTPS and loopback-only listener checks.
2. Waffo test-mode checkout creating the dedicated $4.99 order, not a fixture or another product.
3. The actual callback's signature verification, event delivery and duplicate delivery result.
4. Buyer-visible receipt/order credential availability and activation on the Mac app.
5. Successful first and second installs, third-install denial, and slot reuse after deactivation.
6. A genuine test refund followed by callback revocation and failed online validation/activation. Note that an already-issued offline token remains valid for at most seven days.
7. Backup execution, off-host copy and isolated restore result.

Until that record exists, the real payment path is blocked. Local HTTP tests prove only the local contract. Enabling live payments requires a separate explicit release decision; these templates and this binary do not enable production mode.
