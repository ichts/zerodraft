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
- [ ] The update signing key exists on the release Mac and `SUPublicEDKey` in `Sources/FirstLine/Info.plist` is the printed public key, not the placeholder, and the private key is backed up per [`docs/RELEASE_KEY.md`](RELEASE_KEY.md).
- [x] Account Holder installed a valid Developer ID Application identity in the login keychain. Configured DMG signing and notarization evidence, and the pending installed-DMG acceptance, are recorded in `MANUAL_QA.md`.
- [x] Assemble the local release app with `scripts/package-app.sh --adhoc`; the packaged resource bundle is under `Contents/Resources/` and the icon is compiled to `.icns`.
- [ ] Verify the release configuration against [Release configuration](LICENSE_PAYMENT_SPEC.md#release-configuration); that section owns required fields and staging restrictions.
- [ ] Run `scripts/release-dmg.sh` (configured release, not `--staging`; this does not select LIVE payments). Its header owns signing, app-then-DMG notarization and stapling, the WID volume icon, Gatekeeper checks, and the SHA-256 sidecar.

## Notarization
- [x] Save validated App Store Connect API credentials in the login keychain as `writeitdown-notary` (no app-specific password)
- [ ] Confirm the live artifacts from `scripts/release-dmg.sh` match its header: stapled app and DMG, WID volume icon, and checksum sidecar.
- [ ] Confirm the signed app's nested code all carries one TeamIdentifier (`scripts/sign-nested.sh` proves it before the notary wait) and that `Sparkle.framework/Versions/B/Autoupdate` is Developer ID signed, not ad-hoc. This is what fails notarization if the plain-Mach-O pass is ever removed.

## Updates (Sparkle)

Owned by `scripts/release-dmg.sh` (payload and gates) and `scripts/publish-appcast.sh` (feed). The
key procedure is `docs/RELEASE_KEY.md`; hosting and routing are owned by
[`writeitdown/README.md`](../../../../writeitdown/README.md#mac-download-release).

- [ ] `CFBundleVersion` is a positive integer greater than `dist/updates/last-build.txt`; `release-dmg.sh` refuses otherwise. Delete that file only for a deliberate rebuild of the same build number.
- [ ] `dist/updates/WriteItDown-<version>.zip` exists and contains the stapled app (the script writes it after `stapler validate`). Staging runs must produce no ZIP.
- [ ] `scripts/publish-appcast.sh` exits 0: the feed carries exactly one item for the new build, names a minimum system version, carries no `sparkle:hardwareRequirements` (the release must stay one universal app), and its enclosure signature verifies with `sign_update --verify`.
- [ ] The archive and every `.delta` are uploaded before `appcast.xml`. A feed that points at a missing payload shows every user a failed update.
- [ ] `curl -sSI https://writeitdown.app/download/appcast.xml` returns 200 `application/xml`, and a missing file under `/download/updates/` returns 404, never 200 HTML from the site's catch-all.
- [ ] `lipo -info` on `Contents/MacOS/WriteItDown` and on `Sparkle.framework/Versions/B/Sparkle` shows `x86_64 arm64`.
- [ ] The download page's DMG name and published SHA-256 are updated in the same deploy as the DMG upload, and `npm run release-check -- --download` passes (`--live` after the install).
- [ ] Real-window evidence for the first Sparkle release (update alert not shown inside a running session, deferred alert after the session, consent-free default with the toggle off) is recorded in `MANUAL_QA.md`. Until then the room guard is proven by unit tests only.

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
