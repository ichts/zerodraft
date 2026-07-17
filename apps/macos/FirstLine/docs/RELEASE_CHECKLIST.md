# First Line — Direct Distribution Release Checklist

This checklist is for signed + notarized DMG release preparation. It does not assume App Store distribution.

Commercial launch rules live in `docs/LAUNCH_PLAN.md`.
License/payment implementation rules live in `docs/LICENSE_PAYMENT_SPEC.md`.

## Commercial readiness
- [ ] Confirm early-bird USD $5 one-time purchase copy
- [ ] Confirm 2 Macs per license
- [ ] Confirm 14-day refund policy
- [ ] Choose payment provider / merchant of record
- [ ] Create Dodo one-time product draft
- [ ] Enable 2-Mac license-key entitlement
- [ ] Create license activation support path
- [ ] Publish help / privacy / refund / terms / download pages

## Metadata and assets
- [ ] Finalize `build/darwin/Info.plist`
- [ ] Export production app icon set into `build/darwin/AppIcon/`
- [ ] Confirm bundle name, version, build number, copyright

## Build and QA
- [ ] `swift build`
- [ ] `swift test`
- [ ] Complete `docs/MANUAL_QA.md`
- [ ] Confirm library / config paths behave correctly on a clean machine

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
- [ ] No known blocker remains for library delete / reveal / open actions
