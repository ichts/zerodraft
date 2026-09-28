# Write It Down - Direct Distribution Release Checklist

This checklist is for the signed and notarized DMG. Current product and pricing decisions live in `WRITEITDOWN_PLAN.md`; license implementation details live in `LICENSE_PAYMENT_SPEC.md`. `LAUNCH_PLAN.md` is historical.

## Commercial readiness
- [ ] Confirm purchase copy matches the price in `WRITEITDOWN_PLAN.md`
- [ ] Confirm 2 Macs per license
- [ ] Confirm 14-day refund policy
- [ ] Confirm Dodo merchant account is ready
- [ ] Create Dodo one-time product draft
- [ ] Enable 2-Mac license-key entitlement
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
- [ ] Account Holder installs a valid Developer ID Application identity with private key in the login keychain. The certificates API rejected creation for the current API key with a 403 Account Holder-only error.
- [x] Assemble the local release app with `scripts/package-app.sh --adhoc`; the packaged resource bundle is under `Contents/Resources/` and the icon is compiled to `.icns`.
- [ ] Set the live checkout URL and product ID in `Sources/FirstLine/Info.plist` after Dodo setup; keep both empty until then. `scripts/release-dmg.sh` refuses to ship without them.
- [ ] Run `scripts/release-dmg.sh` to sign the app with hardened runtime and timestamp, verify recursively, build the DMG, notarize, staple, validate, and write the SHA-256 checksum.

## Notarization
- [ ] Create DMG containing the app bundle
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
- [ ] Test-mode license activates through the real app client; a different product key is refused
- [ ] No known blocker remains for license activation or purchase
- [ ] Confirm support mailbox and copyright holder before publishing; `support@writeitdown.app` is proposed, not verified. Review the current `writeitdown` plist attribution against the `LICENSE` placeholder.
- [ ] Upload the DMG and install the tested site bundle separately; neither release script deploys.
