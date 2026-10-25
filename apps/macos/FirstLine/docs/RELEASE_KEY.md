# The update signing key (captain, Mac mini release machine only)

Write It Down 1.1 ships Sparkle 2.10.0. Every update archive carries an EdDSA (Ed25519)
signature, and the app verifies it against `SUPublicEDKey` in `Sources/FirstLine/Info.plist`.
The private half of that key never exists in this repository, on the web host, or in CI: it lives
in the login Keychain of the Mac mini release machine. This file is the exact, complete procedure.

The repository ships a deliberate placeholder (`AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`):
a well-formed 32-byte key whose private key nobody holds, so the app starts cleanly and no update
can ever verify against it. `scripts/release-dmg.sh` refuses to build a release while that value is
unchanged, so the placeholder cannot reach a shipped DMG.

## 1. Get Sparkle's tools on the Mac mini

Download `Sparkle-2.10.0.tar.xz` from
https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0 and unpack it (for example to
`/Applications/Sparkle-2.10.0`). The tools are `bin/generate_keys`, `bin/generate_appcast` and
`bin/sign_update`. Nothing else from that archive is needed; the framework the app embeds comes
from SwiftPM (`Package.resolved` pins 2.10.0).

## 2. Create the key pair

From the unpacked Sparkle directory, on the Mac mini release machine, in the captain's own login
session:

```sh
./bin/generate_keys --account writeitdown
```

It prints the public key and stores the private key in the login Keychain as a generic password:
service `https://sparkle-project.org`, account `writeitdown`. Accept the Keychain prompts. Run this
once, only on the Mac mini. Never run it on another machine and never let it overwrite this key.

## 3. Put the public key in the build

Replace the placeholder in `apps/macos/FirstLine/Sources/FirstLine/Info.plist` with the printed
value:

```xml
<key>SUPublicEDKey</key>
<string>THE_PRINTED_BASE64_KEY</string>
```

Commit it. The public key is public; it is what installed copies pin their trust to.

## 4. Back up the private key, then remove the export

```sh
./bin/generate_keys --account writeitdown -x ~/writeitdown-update-key.txt
```

That file is the base64 seed. Move it into the captain's password manager (1Password), verify the
entry, then delete the file with `rm -P ~/writeitdown-update-key.txt`. Never leave it on the Desktop,
in iCloud Drive or in any synced folder, and never put it in a shell history line, a commit, a chat,
a report, or a server.

## 5. Prove both halves agree

```sh
./bin/generate_keys --account writeitdown -p     # prints the same public key again
cd apps/macos/FirstLine && python3 scripts/test-release-config.py
```

`test-release-config.py` asserts that the tracked `Info.plist` still carries the placeholder (so no
one commits a key by accident) and that a release refuses it; once your real key is in place, run
`scripts/release-dmg.sh` and confirm it no longer stops with `SUPublicEDKey is still the build
placeholder`.

## 6. Rules that protect the key

- Losing the private key stops delivery of further updates until a rotate-out release ships; treat
  it like the Developer ID certificate.
- One release may change either the Developer ID certificate or the EdDSA key, never both. Keep the
  ZIP enclosure and the default `SUVerifyUpdateBeforeExtraction = NO`, so a lost key is recoverable
  by shipping a new key inside a release signed with the same Developer ID certificate.
- A compromised web host can rewrite the feed but cannot forge an archive, because it has no
  private key. A compromised release Mac can sign anything, exactly as with the Developer ID key.
- For a disposable test feed (not production), pass `WID_SPARKLE_KEY_FILE` to
  `scripts/publish-appcast.sh` with an exported seed of a throwaway key, and point the test build's
  `SUFeedURL` at a test path. Never let a test key into `Info.plist` of a released build.
