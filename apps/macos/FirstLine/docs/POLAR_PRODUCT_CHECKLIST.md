# Polar direct-sale setup (writeitdown Mac)

Polar is the only payment and license provider for the Mac release. Do not ship a Dodo checkout or client. Complete this list in **sandbox first**, then repeat in production. The app stores no Polar access token; it calls only the public customer-portal license endpoints.

1. In [Polar sandbox](https://sandbox.polar.sh/), create an organization for writeitdown. Record its organization UUID outside git. A separate sandbox account/sign-in may be required.
2. Create a product named **Write It Down for Mac**, one-time **USD $4.99**, with a license-key benefit. Enable activations, limit **2**, no expiration, and customer self-service deactivation. Record the benefit UUID and hosted checkout URL. Do not use the product UUID as the app's license scope: Polar's public response identifies the *benefit*.
3. Set checkout success URL to `https://writeitdown.app/support.html#mac` until a dedicated success page is approved. State **14-day refunds** in the purchase copy; verify this agrees with the site's refund policy before publishing. Set a confirmed support email only after the mailbox is verified; `support@writeitdown.app` is a proposal, not a working address.
4. Generate a sandbox test license through a test purchase or an authorized sandbox issuance flow; keep it in `~/.config/writeitdown/polar-sandbox.env` (directory 0700, file 0600) alongside the sandbox organization ID and benefit ID. Run `WID_POLAR_E2E=1 swift test --filter LivePolarAcceptanceTests` from the Mac package. Never paste keys or tokens into source, logs or CI.
5. Repeat in [Polar production](https://polar.sh/), after the owner completes KYC and payout. Put the live organization UUID, benefit UUID and checkout URL in `Sources/FirstLine/Info.plist`; verify the production checkout displays USD $4.99 and a two-device license before `scripts/release-dmg.sh` (without `--staging`).
6. Run the signed/notarized DMG and window QA gates in `RELEASE_CHECKLIST.md`. The website bundle install and DMG upload are separate approved release steps, never done by the packaging script.

Public API contract: [activate](https://polar.sh/docs/api-reference/customer-portal/license-keys/activate), [validate](https://polar.sh/docs/api-reference/customer-portal/license-keys/validate), [deactivate](https://polar.sh/docs/api-reference/customer-portal/license-keys/deactivate). Sandbox base URL: `https://sandbox-api.polar.sh/v1`; production: `https://api.polar.sh/v1`. No Authorization header is used by these customer-portal endpoints.

## Sandbox status (2026-09-29)

Built in the sandbox organization `write-it-down-mac`: product **Write It Down for Mac** USD 4.99 one-time, license-key benefit (prefix `WID`, 2 activations, customer deactivation on, visible), checkout link with success URL `https://writeitdown.app/support.html#mac`. IDs and test keys live only in `~/.config/writeitdown/polar-sandbox.env` (0600). Real-client proof: `WID_POLAR_E2E=1 swift test --filter LivePolarAcceptanceTests` covers activation, wrong-benefit refusal, third-device refusal and offline grace; a revoked key is refused on validation (`WID_POLAR_PHASE=activate-revoke-key`, revoke in the dashboard, then `WID_POLAR_PHASE=verify-revoked`).

Operational notes: Polar rate-limits the public license endpoints (HTTP 429 with `Retry-After`; the app reports this as a network failure and retries later), and appends `customer_session_token` to the success URL, so the support page must not log or forward its query string.
