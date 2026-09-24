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
- [ ] Install Apple Developer ID Application certificate
- [ ] Build release app bundle with stable bundle identifier
- [ ] Codesign app with hardened runtime enabled
- [ ] Verify codesign recursively

## Notarization
- [ ] Create DMG containing the app bundle
- [ ] Submit DMG for notarization using notarytool
- [ ] Wait for Accepted status
- [ ] Staple notarization ticket to DMG
- [ ] Verify stapled artifact locally

## Release packaging
- [ ] Name release artifact consistently
- [ ] Include short installation instructions
- [ ] Include known limitations if any remain
- [ ] Publish checksum alongside DMG

## Final ship gate
- [ ] No known blocker remains for English keyboard input
- [ ] No known blocker remains for Chinese IME
- [ ] No known blocker remains for license activation or purchase
