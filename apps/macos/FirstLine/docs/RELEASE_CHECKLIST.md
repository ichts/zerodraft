# Write It Down - Direct Distribution Release Checklist

This checklist is for the signed and notarized DMG. Current product and pricing decisions live in `WRITEITDOWN_PLAN.md`; license implementation details live in `LICENSE_PAYMENT_SPEC.md`. `LAUNCH_PLAN.md` is historical.

## Commercial readiness
- [ ] Confirm purchase copy matches the price in `WRITEITDOWN_PLAN.md`
- [ ] Confirm 2 Macs per license
- [ ] Confirm 14-day refund policy
- [ ] Confirm Waffo merchant onboarding and payout are ready
- [ ] Verify a genuine Waffo test order, signed callback and buyer-visible order number before configuring production
- [ ] Verify the service's two-install limit and refund revocation
- [ ] Create license activation support path
- [ ] Publish help / privacy / refund / terms / download pages

## Metadata and assets
- [ ] Finalize `Sources/FirstLine/Info.plist`
- [ ] Export production app icon set into `Sources/FirstLine/Assets.xcassets/AppIcon.appiconset/`
- [ ] Confirm bundle name, version, build number, copyright

## Build and QA
- [ ] `swift build`
- [ ] `swift test`
- [ ] Run batch 7 window QA from `WRITEITDOWN_PLAN.md` and record results in `MANUAL_QA.md`
- [ ] Confirm config path and absence of draft files on a clean machine

## Signing
- [x] Account Holder installed a valid Developer ID Application identity in the login keychain. Staging signing and notarization were verified; see `MANUAL_QA.md`. A production DMG is still pending.
- [x] Assemble the local release app with `scripts/package-app.sh --adhoc`; the packaged resource bundle is under `Contents/Resources/` and the icon is compiled to `.icns`.
- [ ] Set the verified Waffo checkout URL, license-service HTTPS origin, product ID and raw Ed25519 public key in `Sources/FirstLine/Info.plist`; keep them empty until then. Field formats are in `LICENSE_PAYMENT_SPEC.md`. `scripts/release-dmg.sh` refuses to ship without them; `--staging` notarizes a non-sellable build only.
- [ ] Run `scripts/release-dmg.sh` to sign the app with hardened runtime and timestamp, verify recursively, build the DMG, notarize, staple, validate, and write the SHA-256 checksum.

## Notarization
- [ ] Create production DMG containing the app bundle and an Applications symlink
- [x] Save validated App Store Connect API credentials in the login keychain as `writeitdown-notary` (no app-specific password)
- [ ] Submit DMG for notarization using notarytool
- [ ] Wait for Accepted status
- [ ] Staple notarization ticket to DMG
- [ ] Verify stapled artifact locally

## Release packaging
- [ ] Name release artifact consistently
- [ ] Include short installation instructions: open the DMG, drag Write It Down to Applications, then eject the disk image
- [ ] Include known limitations if any remain
- [ ] Publish checksum alongside DMG

## Final ship gate
- [ ] No known blocker remains for English keyboard input
- [ ] No known blocker remains for Chinese IME
- [ ] `WID_QA_LICENSE_ONLY=1 scripts/qa-window.sh` passes real-window fresh activation-only launch, signed-token activation, offline restart and refund denial, with no persisted trial counter. This is synthetic evidence only; menu/legacy-state denial and animation timing are covered by their focused Swift tests.
- [ ] A genuine Waffo test order activates in the real app through AppState + WaffoLicenseClient; refund then refuses access. Record redacted evidence in `MANUAL_QA.md`, never the order number or token. Wrong-product/device/signature and seven-day boundaries must also pass `swift test`.
- [ ] No known blocker remains for license activation or purchase
- [ ] Confirm support mailbox and copyright holder before publishing; `support@writeitdown.app` is proposed, not verified. Review the current `writeitdown` plist attribution against the `LICENSE` placeholder.
- [ ] Upload the DMG and install the tested site bundle separately; neither release script deploys.
