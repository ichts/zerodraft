# Write It Down for Windows

The Windows app: the writing room and the product around it (home, three free sessions, purchase hand-off, licence
activation against the existing Stripe licence service, MSIX), built on [mygo](https://github.com/egoist/mygo) native UI
(GPU-drawn, Direct3D 11) with [CrychicUI](https://github.com/ELY-Open-Source/CrychicUI) controls. It matches the Mac app
(`../macos/FirstLine`): same price (USD 4.99 once), same two-device licence pool, same licence service. `SYNC.md` is the
parity ledger. Module: `github.com/ichts/zerodraft/apps/windows`, Go 1.27.3.

## Layout

```
cmd/wid          the app (main.go: fonts, test switches, window); flavour_release.go is the production build,
                 flavour_qa.go (-tags widqa) points at a local TEST service
app/             home, rules, activation and settings screens, routing, background network calls
room/            the writing room: state (room.go), painter (draw.go), pure geometry (geometry.go), pills
ime/             the one risky layer: the forward-only ui.TextInputClient (IMM32 on Windows)
session/         the pure session clock and word count (port of SessionEngine.swift)
paper/           the Wheat paper texture (port of PaperField)
licence/         the client of services/license: token verifier, activate/validate/deactivate, checkout, trial, vault
tokens/          GENERATED from the Mac sources by scripts/gen_tokens.py; never edit
fonts/           Zhuque Fangsong (a byte copy of the Mac app's file; go:embed cannot leave the module) and three static Newsreader
                 faces derived from the Mac's variable fonts with the optical size the Mac draws each role at (scripts/gen_fonts.py)
cmd/qaserver     QA only: runs the real services/license behind a loopback fake Stripe + a control port
cmd/drv          Windows desktop driver (SendInput, TSF IME switching, DPI switching, window captures)
cmd/imecheck     judges one IME suite run
packaging/       MSIX manifest, assets, make-msix.ps1, install-msix.ps1, STORE.md
scripts/         generators, drift gate, the Mac comparison, and the vivobook-1 scripts below
```

## Build and test (any OS, no window)

```
go build ./...                      # release flavour; GOOS=windows GOARCH=amd64 for the Windows exe
go vet ./... && go test ./...       # session clock, forward-only contract, paper, geometry, room behaviour through
                                    # mygo's headless tester, licence client against fakeservice, app flows
sh scripts/check_tokens.sh          # the drift gate (below; needs python3 and `pip install fonttools==4.68.0`)
```

CI (`.github/workflows/windows.yml`) runs exactly this on GitHub's Windows runner, plus `gofmt`, `go mod tidy -diff`
and `go mod verify`, and builds the QA flavour and the `-H=windowsgui` exe. It also runs when the Mac sources under
`apps/macos/FirstLine/Sources/FirstLine` change.

The release exe is `mygo build -platform windows/amd64` (icon, DPI manifest and version resources come from
`mygo.json`): `go run github.com/egoist/mygo/cmd/mygo build -platform windows/amd64 -o build`.

### Licence tests never touch a live service

Unit tests use `licence/fakeservice` (an in-process signing stand-in). `TestRealServiceTestMode` (build tag
`realservice`, skipped by default and not in CI because it stops `qaserver` with a POSIX signal) drives the real,
unmodified `services/license` binary in Stripe TEST mode behind the loopback fake Stripe in `cmd/qaserver`; keys, the
webhook secret and the Stripe API are generated placeholders on loopback:

```
(cd ../../services/license && go build -o /tmp/wid-license-service .) && go build -o /tmp/wid-qaserver ./cmd/qaserver
WID_SERVICE_BIN=/tmp/wid-license-service WID_QASERVER_BIN=/tmp/wid-qaserver \
  go test -tags realservice -run TestRealServiceTestMode -v ./licence
```

The release flavour has no way to point elsewhere: no environment variable, file or flag changes the service, product
or public key (`cmd/wid/flavour_release.go`, values generated from the Mac `Info.plist`). No secret of any kind lives
in this module; the licence token, order number, status and trial counter are stored in the Windows Credential Manager
(`mygo.Secrets`), never in a file.

## Tokens, strings and the drift gate

`tokens/tokens_gen.go` (colour roles, spacing, session constants, the kept block's rhythm, the rules sheet's type scale, the
chip lockup's sizes, every Mac sentence the Windows screens reuse, the licence service URL, product id and public key) is
generated from the Mac sources at their real paths:

```
python3 scripts/gen_tokens.py | gofmt > tokens/tokens_gen.go     # regenerate, from apps/windows
python3 scripts/gen_fonts.py                                     # the derived Newsreader faces (fonttools 4.68.0)
sh scripts/check_tokens.sh                                       # fails when stale, or when a font or the lockup differs from the Mac's
```

The lockup SVG (`app/lockup.svg`) and Zhuque Fangsong are byte-compared with the Mac's, and the three Newsreader faces are
re-derived and compared byte for byte (the Mac sets the font's optical size to the point size on every run, mygo on Windows
keeps the default, so the Windows room pins the Mac's value per role; SYNC.md row 22). Every Mac sentence is searched for verbatim before it is emitted, so a changed Mac sentence fails the generator instead
of drifting. When the gate fails: regenerate, run `go test ./...`, then update the parity row in `SYNC.md` in the same
PR.

## CrychicUI pin

CrychicUI has no release tags, so `go.mod` pins the commit as a pseudo-version
(`v0.0.0-20261027050735-bf15ddf6600a`, upstream `bf15ddf`). To move it: `go get github.com/ELY-Open-Source/CrychicUI@<commit>`
then `go mod tidy`, run the tests, and re-run the IME suite and `scripts/capture.sh` on the Windows test PC.

## Real hardware: the Windows test PC (vivobook-1)

These run by hand over ssh and a scheduled task in the interactive desktop session; they need a real Windows 11 PC,
real input and the Microsoft IMEs, so they are not CI. Host and desktop user come from `WID_HOST` (default
`vivobook-1`) and `WID_USER` (default `zyz10`); evidence goes to `WID_EVIDENCE` (default
`$TMPDIR/wid-windows-evidence`), outside the repository. Needs `python3`, `ssh`/`scp` and the Go toolchain on the Mac.

- `scripts/ime-suite.sh [pinyin] [wetype] [ja]` - the scripted IME regression suite with real keystrokes (Microsoft
  Pinyin, WeType, Japanese Microsoft IME); prints PASS/FAIL per check, 33 checks. Known-broken proofs that must fail:
  `WID_BREAK=nodeny scripts/ime-suite.sh pinyin`, `WID_BREAK=keepeditor scripts/ime-suite.sh pinyin`.
- `scripts/capture.sh 100|125|150` - every room state at that display scale, then `measure.py` (33 geometry/timing
  checks, including the kept caption and silent corner count and the first refused delete's notice). Known-broken proofs that
  must fail: `WID_BREAK=anchor35 scripts/capture.sh 150` (anchor), `WID_BREAK=keptcount` and `WID_BREAK=nonotice`
  (`-tags imebreak` builds), and `WID_BREAK=armedexit` (the script arms the exit first, so the notice must not show).
- `scripts/pair.sh` and `scripts/screens.sh` - the Mac pair: every room state and the picker/activation cards in the Mac's own
  1040 x 720 page area at 100% (`WID_WINDOW=1040x720`), compared with the Mac's `SnapshotTests` PNGs by
  `scripts/compare_mac.py` (one detector over both images, rows of ink and pills in DIPs). Produce the Mac side with
  `cd ../macos/FirstLine && WID_SNAPSHOT_DIR=$MAC_SNAPSHOTS swift test --filter SnapshotTests` and pass `MAC_SNAPSHOTS`.
  `go test ./room ./app -run MacPair` renders the same states headless (its chrome face is a fallback: only Newsreader rows
  and geometry mean anything there).
- `scripts/e2e.sh 150|100 [0]` - the whole product against the real `services/license` (built from this repository,
  unmodified) in Stripe TEST mode behind the loopback fake Stripe: first launch, three trial sessions, activation card,
  Buy hand-off, a paid test session, the two-PC limit, activation, relaunch, refund and revocation. It runs the QA flavour as a
  plain exe pushed to the PC (`WID_E2E_MSIX=1` runs the installed QA MSIX instead). `scripts/measure_screens.py` measures its
  captures.
- `scripts/package-msix.sh release|qa|store` - builds, test-signs and installs the MSIX on the test PC with the Windows SDK
  build tools (`packaging/make-msix.ps1`, `packaging/STORE.md` for the Store identity). Test signing uses a
  throw-away `CN=WID Test Signing` certificate; no production certificate or Store submission lives here. `store` instead packs
  the release binary unsigned under the reserved Store identity (never installed); `scripts/check_manifest.sh` asserts the identities.

**Smart App Control on vivobook-1** (state `On`, `HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState`)
blocks the test-signed MSIX and the `mygo build` exe ("could not verify its publisher") and, since 2026-11-01 about 19:40, every
other binary it has not run before ("An Application Control policy has blocked this file", Code Integrity event 3077): a rebuilt
`wid` exe no longer starts there, an identical one that ran before still does. The scripts therefore take
`WID_PREBUILT_EXE='C:\wid\stage\wid-cap.exe'` to run an exe already on the PC; turning Smart App Control off is the captain's call
(it is one-way) and is what unblocks building on the PC again. The dialog a blocked launch leaves open on the desktop must be
dismissed before the next run.

Last run (2026-11-01, vivobook-1, the QA build of 19:36 that the PC could still run, identical to the branch head except the
`WID_BREAK=keptcount` and `nonotice` switches and a comment):

| run | result |
|---|---|
| IME suite, Microsoft Pinyin / WeType / Japanese IME | 11 + 11 + 11 = 33 of 33 pass (the rewritten `vcall` activates each text service: `activate hr=0x0 active hr=0x0`) |
| `capture.sh 150` and `100` | 33 of 33 pass at each scale |
| `capture.sh 150` with `WID_BREAK=armedexit` | 32 of 33: the D-077 notice check fails, as it must |
| `pair.sh` against the Mac snapshots (7 room states) | every Newsreader row within 1 DIP of the Mac's (heading 1 to 2); footer row baseline 660 = 660; chrome-face widths and the oldest line's thin strokes are the documented differences (SYNC.md rows 18, 22) |
| `screens.sh` (picker, activation card) | every row within 2 DIP except the picker's title ink (+4 at the bottom, a taller bold) and the focused Begin's ring |
| `measure_screens.py` on the e2e captures | 51 of 51 at 150 and at 100 |
| `e2e.sh 150` and `100 0` | pass: three trial charges, Buy to `checkout.stripe.com`, paid session, two-PC limit, licensed session, relaunch validated, refund revoked, Stripe down falls back to the public page |

Test switches (never set by the shortcut): `WID_SESSION_SECONDS`, `WID_SILENCE_SECONDS`, `WID_LOG`, `WID_SOUND=1`,
`WID_WINDOW=WIDTHxHEIGHT` (the page area, for the Mac pair), `WID_BREAK` (only in `-tags imebreak` builds).

`scripts/mke2e.py`, `mkscript.py`, `mksuite.py`, `mkcapture.py` and `mkpair.py` generate the `cmd/drv` scripts those runs push;
`winrun.sh`, `run-drv.sh` and `clearcred.ps1` are the ssh plumbing.
