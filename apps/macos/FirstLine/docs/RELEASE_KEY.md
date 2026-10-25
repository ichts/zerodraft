# The update signing key (captain, Mac mini release machine only)

Write It Down 1.1 ships Sparkle 2.10.0. Two EdDSA (Ed25519) signatures protect every update, and
the app checks both against `SUPublicEDKey` in `Sources/FirstLine/Info.plist`:

- every update archive carries an enclosure signature, verified before extraction;
- the appcast feed carries its own embedded signature (`SURequireSignedFeed`), so a rewritten feed
  cannot point at an older archive, a different release-notes page or a critical update.

Sparkle 2.10.0 refuses to start an updater that sets `SURequireSignedFeed` without
`SUVerifyUpdateBeforeExtraction`, so `Info.plist` enables both together. It also sets
`SUSignedFeedFailureExpirationInterval` to 0: Sparkle's 20-day default would otherwise start accepting
an unverified feed after that long, and this product has no safe-mode window. `scripts/release-dmg.sh`
refuses a release where any of the three is missing or has another value, and
`scripts/publish-appcast.sh` verifies the signed feed and the enclosure after generating them.

The private half of the key never exists in this repository, on the web host, or in CI: it lives in
the login Keychain of the Mac mini release machine. This file is the exact, complete procedure.

`Info.plist` carries the captain's real public key. Until it existed, the build shipped a deliberate
placeholder (`AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`, a well-formed 32-byte key whose private
half nobody holds), so the app started cleanly and no update could verify. Both
`scripts/release-dmg.sh` and `scripts/test-release-config.py` still refuse that exact placeholder, so
a reverted or forgotten key cannot reach a shipped DMG and cannot pass QA silently.

## 1. Get Sparkle's tools on the Mac mini

The release scripts find the pinned tools without any configuration: `swift package resolve` inside
`apps/macos/FirstLine/` materialises Sparkle 2.10.0 (the version `Package.resolved` pins) under
`.build/artifacts/sparkle/Sparkle/bin`, which holds `generate_keys`, `generate_appcast` and
`sign_update`. Set `WID_SPARKLE_BIN` only to point at a different Sparkle 2.10.0 `bin` directory, for
example the one from the `Sparkle-2.10.0.tar.xz` release archive. Nothing else from that archive is
needed; the framework the app embeds comes from SwiftPM.

## 2. Create the key pair

On the Mac mini release machine, in the captain's own login session, from the repository root:

```sh
apps/macos/FirstLine/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account writeitdown
```

It prints the public key and stores the private key in the login Keychain as a generic password:
service `https://sparkle-project.org`, account `writeitdown`. Accept the Keychain prompts. Run this
once, only on the Mac mini. Never run it on another machine and never let it overwrite this key.

## 3. Put the public key in the build

Put the printed value in `apps/macos/FirstLine/Sources/FirstLine/Info.plist` (this was done on
2026-10-25 for the 1.1 key):

```xml
<key>SUPublicEDKey</key>
<string>THE_PRINTED_BASE64_KEY</string>
```

Commit it. The public key is public; it is what installed copies pin their trust to.

## 4. Back up the private key, then remove the export

```sh
apps/macos/FirstLine/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account writeitdown -x ~/writeitdown-update-key.txt
```

That file is the base64 seed. Move it into the captain's password manager (1Password), verify the
entry, then delete the file with `rm -P ~/writeitdown-update-key.txt`. Never leave it on the Desktop,
in iCloud Drive or in any synced folder, and never put it in a shell history line, a commit, a chat,
a report, or a server. This backup is the only copy besides the Keychain.

## 5. Prove the key, the feed and the bundle agree

```sh
apps/macos/FirstLine/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account writeitdown -p
cd apps/macos/FirstLine && python3 scripts/sparkle-key.py --plist Sources/FirstLine/Info.plist \
  --generate-keys .build/artifacts/sparkle/Sparkle/bin/generate_keys --account writeitdown
```

`scripts/sparkle-key.py` derives the public half of the signing key and compares it byte for byte
with `SUPublicEDKey`: the Keychain path asks `generate_keys -p`, and an exported seed file is wrapped
as PKCS#8 and exported by `openssl pkey` (no hand-written curve code). It is the gate
`scripts/publish-appcast.sh` runs before generating a feed, because `generate_appcast` only prints a
warning on a mismatch and `sign_update --verify` would confirm the key against itself. Then run
`python3 scripts/test-release-config.py`, `scripts/release-dmg.sh` and `scripts/publish-appcast.sh`;
the last one also fails if the feed was not signed.

## 6. What this means for rotation

- One release may change either the Developer ID certificate or the EdDSA key, never both. The
  `SUVerifyUpdateBeforeExtraction` fallback is what lets an older copy install an archive signed with
  a new EdDSA key when that archive is Developer ID signed by the same team; the fallback is not a
  rotation plan by itself.
- The EdDSA key is the permanent trust anchor for 1.1 and later: an installed copy only accepts a
  feed and an archive signed with this key, so losing the private key ends update delivery to it. The
  DMG stays the distribution path for new installs. Treat the key exactly like the Developer ID
  certificate and never plan on "shipping a new key" to recover a lost one.
- Key rotation needs its own reviewed procedure (a feed signed with the outgoing key, an archive
  signed with the new key, and the bundle's new `SUPublicEDKey`). It is not one of the steps above,
  and `scripts/publish-appcast.sh` refuses a feed that does not verify against the key the shipping
  bundle declares, so that procedure must be merged before any rotation starts.
- A compromised web host can rewrite neither the feed nor an archive, because it has no private key.
  A compromised release Mac can sign anything, exactly as with the Developer ID key.
- For a disposable test feed (not production), pass `WID_SPARKLE_KEY_FILE` to
  `scripts/publish-appcast.sh` with an exported seed of a throwaway key, and point the test build's
  `SUFeedURL`/`SUPublicEDKey` at that test pair. Never let a test key into `Info.plist` of a released
  build.
