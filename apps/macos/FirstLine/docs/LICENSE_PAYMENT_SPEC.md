# writeitdown macOS - License and Payment

The AppKit app is sold as a Developer ID signed, notarized DMG downloaded from writeitdown.app. The one-time price is USD $4.99. Polar owns the charged amount; `WIDDisplayPrice` in `Sources/FirstLine/Info.plist` owns the displayed price. Change both and the site's Mac copy together. `WIDCheckoutURL`, `WIDPolarOrganizationID`, and `WIDPolarBenefitID` stay empty until the live Polar product exists; Buy and keyed activation remain unavailable. No Polar access token belongs in the app.

## Entitlement

- One license covers two Macs, with a 14-day refund policy and no subscription. Three Mac writing sessions are free, charged on first input rather than room entry.
- The install's random UUID in `install-id.json` supplies a stable non-hardware activation label. The key, activation ID, status, benefit ID and validation timestamps are cached in `settings.json`; draft text never is.
- Activation requires network and a configured organization and benefit. If the Polar organization ID is missing, keyed activation reports a configuration error and cached keyed access remains locked, even within offline grace; the legacy unlocked migration is separate. The Polar activation response must identify that organization and benefit; a mismatched benefit is rejected and its remote activation deactivated. Keyed access needs a cached activation ID, matching configured benefit and successful public validation; validation passes both benefit ID and activation ID. A refunded, revoked, expired, rotated or deactivated key fails public validation. Re-entering the same cached key validates the existing activation first rather than consuming another slot.
- Keyed licenses get seven days of offline grace after activation or last successful validation; that gate also runs after sleep. A timestamp more than one day in the future does not grant grace. Network failure does not revoke access while inside grace; an explicit 404 invalidation does. Old Dodo product IDs cannot match a Polar benefit UUID, so their cached keyed access fails closed. The existing legacy `hasUnlockedFullAccess` migration remains read-only and independent of this keyed path.

## Polar public API

`PolarLicenseClient` uses `URLSession` and only `POST /v1/customer-portal/license-keys/activate`, `/validate`, and `/deactivate`, without an Authorization header. Debug defaults to `https://sandbox-api.polar.sh/v1`, release to `https://api.polar.sh/v1`. Activation sends the key, organization ID and random install label. Validation sends the key, organization ID, cached activation ID and expected benefit ID; its response must be `granted`, match both IDs and identify the same activation. Deactivation sends the key, organization ID and activation ID. A 403 activation-limit response shows the 2-Mac message; revoked/refunded/expired and not-found keys refuse access. A 404 validation revokes the cache; 5xx/429 and transport errors use the offline grace. Never log license keys or request bodies.

Public API references: [activate](https://polar.sh/docs/api-reference/customer-portal/license-keys/activate), [validate](https://polar.sh/docs/api-reference/customer-portal/license-keys/validate), [deactivate](https://polar.sh/docs/api-reference/customer-portal/license-keys/deactivate). Polar explicitly requires client-side benefit scoping beyond organization ID. A test-only URLProtocol verifies the payloads without network; an opt-in live sandbox test reads `~/.config/writeitdown/polar-sandbox.env` and never runs in CI by default.

## Release configuration

Follow `POLAR_PRODUCT_CHECKLIST.md` for sandbox and live products, and `POLAR_OWNER_STEPS.md` for owner-only signup, KYC and payout. Run `swift build`, `swift test`, and the real sandbox proof before publishing. The DMG packaging instructions live in `RELEASE_CHECKLIST.md`.
