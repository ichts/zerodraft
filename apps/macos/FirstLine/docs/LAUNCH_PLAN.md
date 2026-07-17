# First Line — Mole-Style Direct Launch Plan

This plan covers the paid direct-download macOS launch. Apple Developer enrollment is currently blocked, so work is split into what can be prepared now and what waits for Developer ID signing / notarization.

## Commercial decisions

| Area | Decision |
|---|---|
| Launch offer | Early-bird license |
| Price | USD $5 |
| Payment model | One-time purchase. No subscription. |
| License seats | 2 Macs per license |
| Refund | 14-day refund |
| Web trial | Unlimited 1-minute browser trial |
| Mac trial | 3 writing sessions |
| Checkout reference | Mole-style hosted checkout via merchant of record |

## Mole reference pattern

Mole’s public page uses a small direct-sale loop:

1. Short landing with `Download Trial` and `Buy`.
2. One-time price, no subscription.
3. Free trial before purchase.
4. License key delivered after checkout.
5. Merchant of record handles billing, tax, receipts, and payment methods.
6. Help / refund / privacy answers exist off the main landing.

Visible Mole evidence: its FAQ states checkout billing/address is handled by **Dodo Payments**, and users receive the license key from the Dodo email.

## Recommended payment direction

Start with Dodo Payments first, because Mole uses it publicly and Dodo has one-time product plus license-key entitlement docs that match First Line. Keep Lemon Squeezy and Paddle as backups.

- Dodo Payments
- Lemon Squeezy
- Paddle

Do not build Stripe billing first unless First Line needs custom account billing. The first launch needs license delivery, tax handling, refunds, and receipts more than billing flexibility.

Implementation details live in `docs/LICENSE_PAYMENT_SPEC.md`.

## Required web surfaces

Keep the landing minimal. Add small support pages instead of stuffing the landing.

- `/download` — latest Mac build, version, checksum, installation note.
- `/help` — buy, activate, switch Macs, license support.
- `/privacy` — local writing data, license check, email capture.
- `/refund` — 14-day refund policy and support email.
- `/terms` — license terms, permitted seats, no warranty.
- `/release-notes` — user-visible changes per version.

## License behavior

The current local `hasUnlockedFullAccess` flag is not a production license system. Production launch needs:

1. Upgrade screen links to hosted checkout.
2. Settings / Upgrade accepts a license key.
3. App calls Dodo public license activation / validation endpoints.
4. Dodo records license key, activated device count, and status.
5. License allows 2 active Macs.
6. Refunded / revoked licenses become inactive through Dodo status.
7. App caches successful activation locally.
8. App should tolerate short offline periods after activation.

## License system minimum

With Dodo-first integration, First Line can avoid a custom license backend for v1. Dodo can issue license keys, enforce activation limits, and expose public activate / validate endpoints for the desktop app.

Minimum responsibilities:

- Create Dodo one-time product for USD $5.
- Enable Dodo license-key entitlement with 2 activations.
- Let Dodo deliver license keys by email.
- Add Mac license entry UI.
- Activate / validate license keys through Dodo public endpoints.
- Cache activation locally with a short offline grace period.
- Add webhook handling later for support automation and revocation logs.

## Can do now, before Apple Developer enrollment

- Finalize price / trial / refund / license copy.
- Create support/legal/download pages.
- Choose payment provider and create product draft.
- Implement license entry UI in the Mac app.
- Implement Dodo-backed license activation in the Mac app.
- Add app bundle and unsigned DMG build scripts.
- Clean README, LICENSE, CHANGELOG, and release notes.
- Generate checksums for local release artifacts.
- Run `swift build`, `swift test`, and `docs/MANUAL_QA.md`.
- Prepare signed/notarized release scripts with credentials as environment variables.

## Blocked until Apple Developer is ready

- Developer ID Application certificate.
- Hardened-runtime codesign with real identity.
- Notarization with Apple notary credentials.
- Stapling notarization ticket.
- Final user-trusted public DMG.

## Open decisions

- Exact Dodo product / checkout setup.
- Whether Dodo email alone is enough for license delivery.
- Support email address.
- Copyright owner name.
- Final app icon source and export.
- Whether early-bird $5 is time-limited or quantity-limited.

## Suggested implementation order

1. Add support/legal/download pages with placeholder download state.
2. Create a Dodo draft product for USD $5 with 2-Mac license entitlement.
3. Implement Dodo-backed license activation.
4. Implement Mac license entry and cached unlock.
5. Add app bundle / unsigned DMG scripts.
6. Run full manual QA on a clean local profile.
7. When Apple Developer enrollment is fixed, add real signing and notarization.
8. Publish first signed DMG and checksum.
