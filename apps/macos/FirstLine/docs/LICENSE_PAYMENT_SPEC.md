# writeitdown macOS - License and Payment

The native AppKit tool is sold as a Developer ID signed, notarized DMG downloaded from writeitdown.app, not through the Mac App Store. The one-time price is USD $4.99. Dodo's product owns the charged amount; `WIDDisplayPrice` in `Sources/FirstLine/Info.plist` owns the app's displayed price. Change both and the site's Mac copy together. `WIDCheckoutURL` is intentionally empty until the owner supplies a hosted checkout URL; Buy remains disabled until a valid HTTPS URL is configured. `WIDDodoProductID` is also empty until the owner supplies the actual Dodo product ID; activation refuses to grant access until it matches the activation response's product ID. No checkout credentials belong in the app.

## Entitlement

- One license covers two Macs, with a 14-day refund policy and no subscription.
- Three Mac writing sessions are free. A session consumes a trial use when the first committed or marked keystroke starts its clock; entering and leaving an untouched room costs nothing. After the third session's wipe, a restart passes the gate and routes to Upgrade. Active licenses bypass it.
- The install's random UUID in `install-id.json` supplies a stable non-hardware activation name. The key, instance ID, status, and validation timestamps are cached in `settings.json`; draft text never is.
- Activation requires network and the configured product ID to match the activation response. The accepted product ID is persisted locally. On launch, cached keyed access is held until product identity is checked against current configuration and public validation completes. Successful validation refreshes the timestamp; explicit invalidation revokes access. A previously active license gets seven days of offline grace after its last successful validation; the writing gate checks that deadline even while the app stays open or resumes from sleep, then requires online validation again. A missing or different configured product ID never receives keyed access, even during offline grace. Legacy unlocked records without a key retain their migration entitlement.
- A legacy `hasUnlockedFullAccess` settings field still migrates read-only to active status within the current configuration root. The app does not import the old First Line folder.

## Dodo public API

`DodoLicenseClient` uses `URLSession` and only the public endpoints `POST /licenses/activate`, `/licenses/validate`, and `/licenses/deactivate`. No developer API key or Authorization header is sent. Requests contain only the entered license key and, for activation, the install name; deactivate also sends the instance ID. The writing is never transmitted. Debug defaults to `https://test.dodopayments.com`, release to `https://live.dodopayments.com`; tests inject a stub `URLProtocol` and send no requests outside the machine.

The activation response's `id` is stored for future deactivation. If an activation is rejected for the wrong product or cannot be saved locally, the new remote instance is deactivated; an already accepted instance is never cleaned up. A failed cleanup is shown as a support action to free the device slot. `LICENSE_KEY_LIMIT_REACHED` maps to the 2-Mac message; `LICENSE_KEY_NOT_FOUND` and `INACTIVE_LICENSE_KEY` map to invalid key; network and server failures remain retryable. Validation's documented response only supplies `{ "valid": true|false }`, not product identity. It cannot independently authenticate product ownership: the cached product ID originates from a previously accepted activation and is compared with local configuration before access. `{ "valid": false }` or documented inactive/not-found errors revoke; network failure uses offline grace. Do not log license keys or request bodies.

API references: https://docs.dodopayments.com/api-reference/licenses/activate-license, https://docs.dodopayments.com/api-reference/licenses/validate-license, https://docs.dodopayments.com/api-reference/licenses/deactivate-license, https://docs.dodopayments.com/api-reference/error-codes.

## Owner checklist before release

- Create a Dodo one-time USD $4.99 product with license keys, two activations, and the 14-day refund policy; supply the hosted checkout URL and set the real product ID in `WIDDodoProductID` (leave it empty until known). Confirm license email delivery and support address.
- Create and install a Developer ID Application certificate and notarization credentials; approve final icon and site copy. See `WRITEITDOWN_PLAN.md` section 8.1 and `RELEASE_CHECKLIST.md`. None block local build/test. No test-mode key has been supplied, so real activation remains unverified.
