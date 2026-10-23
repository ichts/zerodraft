# Write It Down - Direct Distribution Release Checklist

This checklist is for the signed and notarized DMG. Current product and pricing decisions live in `WRITEITDOWN_PLAN.md`; license implementation details live in `LICENSE_PAYMENT_SPEC.md`. `LAUNCH_PLAN.md` is historical.

## Commercial readiness

Required before opening LIVE sales, not before releasing the free trial. Current journey waivers and their approval source are recorded in [`writeitdown/journey/waivers.json`](../../../../writeitdown/journey/waivers.json).

- [ ] Confirm purchase copy matches the price in `WRITEITDOWN_PLAN.md`
- [ ] Confirm 2 Macs per license
- [ ] Confirm 14-day refund policy
- [ ] Confirm the selected processor's merchant account and payout are ready
- [ ] Complete genuine TEST purchase acceptance from `LICENSE_PAYMENT_SPEC.md` before configuring production
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
- [x] Account Holder installed a valid Developer ID Application identity in the login keychain. Configured DMG signing and notarization evidence, and the pending installed-DMG acceptance, are recorded in `MANUAL_QA.md`.
- [x] Assemble the local release app with `scripts/package-app.sh --adhoc`; the packaged resource bundle is under `Contents/Resources/` and the icon is compiled to `.icns`.
- [ ] Verify the release configuration against [Release configuration](LICENSE_PAYMENT_SPEC.md#release-configuration); that section owns required fields and staging restrictions.
- [ ] Run `scripts/release-dmg.sh` (configured release, not `--staging`; this does not select LIVE payments). Its header owns signing, app-then-DMG notarization and stapling, the WID volume icon, Gatekeeper checks, and the SHA-256 sidecar.

## Notarization
- [x] Save validated App Store Connect API credentials in the login keychain as `writeitdown-notary` (no app-specific password)
- [ ] Confirm the live artifacts from `scripts/release-dmg.sh` match its header: stapled app and DMG, WID volume icon, and checksum sidecar.

## Release packaging
- [ ] Name release artifact consistently
- [ ] Include short installation instructions: open the DMG, drag Write It Down to Applications, then eject the disk image
- [ ] Include known limitations if any remain
- [ ] Publish checksum alongside DMG

## Final ship gate
- [ ] Pass the live-site and shipped-DMG journeys, including negative controls and required manual evidence, following [`writeitdown/README.md`](../../../../writeitdown/README.md#host-routing-caddy-and-the-release-journey-gate). Local checks below do not replace them.
- [ ] No known blocker remains for English keyboard input
- [ ] No known blocker remains for Chinese IME
- [ ] `WID_QA_LICENSE_ONLY=1 scripts/qa-window.sh` passes real-window three-session trial, exhaustion across restart, signed-token activation, offline restart and refund denial, with the exhausted trial counter unchanged. This is synthetic evidence only; menu/legacy-state denial and animation timing are covered by their focused Swift tests.
- [ ] Before opening LIVE sales, complete the real-app purchase/refund acceptance in `LICENSE_PAYMENT_SPEC.md` and record redacted evidence in `MANUAL_QA.md`, never the buyer credential or token. Wrong-product/device/signature and seven-day boundaries must also pass `swift test`.
- [ ] Before opening LIVE sales, no known blocker remains for license activation or purchase
- [ ] Verify the support mailbox listed in [`writeitdown/README.md`](../../../../writeitdown/README.md#mac-page-release-order) and confirm the copyright holder before publishing.
- [ ] Upload the DMG and install the tested site bundle separately; neither release script deploys.
