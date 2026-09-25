# writeitdown macOS - License and Payment

The native AppKit tool is sold as a Developer ID signed, notarized DMG downloaded from writeitdown.app, not through the Mac App Store. The one-time price is USD $4.99. Dodo's product owns the charged amount; `WIDDisplayPrice` in `Sources/FirstLine/Info.plist` owns the app's displayed price. Change both and the site's Mac copy together. `WIDCheckoutURL` is intentionally empty until the owner supplies a hosted checkout URL; Buy remains disabled until a valid HTTPS URL is configured. No checkout credentials belong in the app.

## Entitlement

- One license covers two Macs, with a 14-day refund policy and no subscription.
- Three Mac writing sessions are free. A session consumes a trial use when the first committed or marked keystroke starts its clock; entering and leaving an untouched room costs nothing. After the third session's wipe, a restart passes the gate and routes to Upgrade. Active licenses bypass it.
- The install's random UUID in `install-id.json` supplies a stable non-hardware activation name. The key, instance ID, status, and validation timestamps are cached in `settings.json`; draft text never is.
- Activation requires network. Successful validation refreshes the timestamp; explicit invalidation revokes access. A previously active license gets seven days of offline grace after its last successful validation; after that it returns to the gate until revalidated.
- A legacy `hasUnlockedFullAccess` settings field still migrates read-only to active status within the current configuration root. The app does not import the old First Line folder.

## Dodo public API

`DodoLicenseClient` uses `URLSession` and only the public endpoints `POST /licenses/activate`, `/licenses/validate`, and `/licenses/deactivate`. No developer API key or Authorization header is sent. Requests contain only the entered license key and, for activation, the install name; deactivate also sends the instance ID. The writing is never transmitted. Debug defaults to `https://test.dodopayments.com`, release to `https://live.dodopayments.com`; tests inject a stub `URLProtocol` and send no requests outside the machine.

The activation response's `id` is stored for future deactivation. `LICENSE_KEY_LIMIT_REACHED` maps to the 2-Mac message; `LICENSE_KEY_NOT_FOUND` and `INACTIVE_LICENSE_KEY` map to invalid key; network and server failures remain retryable. Validation's `{ "valid": false }` or documented inactive/not-found errors revoke; network failure uses offline grace. Do not log license keys or request bodies.

API references: https://docs.dodopayments.com/api-reference/licenses/activate-license, https://docs.dodopayments.com/api-reference/licenses/validate-license, https://docs.dodopayments.com/api-reference/licenses/deactivate-license, https://docs.dodopayments.com/api-reference/error-codes.

## Owner checklist before release

- Create a Dodo one-time USD $4.99 product with license keys, two activations, and the 14-day refund policy; supply the hosted checkout URL and product ID. Confirm license email delivery and support address.
- Create and install a Developer ID Application certificate and notarization credentials; approve final icon and site copy. See `WRITEITDOWN_PLAN.md` section 8.1 and `RELEASE_CHECKLIST.md`. None block local build/test. No test-mode key has been supplied, so real activation remains unverified.
