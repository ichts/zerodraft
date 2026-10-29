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
fonts/           Newsreader (+ italic), Zhuque Fangsong: byte copies of the Mac app's files (go:embed cannot leave the module)
cmd/qaserver     QA only: runs the real services/license behind a loopback fake Stripe + a control port
cmd/drv          Windows desktop driver (SendInput, TSF IME switching, DPI switching, window captures)
cmd/imecheck     judges one IME suite run
packaging/       MSIX manifest, assets, make-msix.ps1, install-msix.ps1, STORE.md
scripts/         generator, drift gate, and the vivobook-1 scripts below
```

## Build and test (any OS, no window)

```
go build ./...                      # release flavour; GOOS=windows GOARCH=amd64 for the Windows exe
go vet ./... && go test ./...       # session clock, forward-only contract, paper, geometry, room behaviour through
                                    # mygo's headless tester, licence client against fakeservice, app flows
sh scripts/check_tokens.sh          # the drift gate (below)
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

`tokens/tokens_gen.go` (colour roles, spacing, session constants, every Mac sentence the Windows screens reuse, the
licence service URL, product id and public key) is generated from the Mac sources at their real paths:

```
python3 scripts/gen_tokens.py | gofmt > tokens/tokens_gen.go     # regenerate, from apps/windows
sh scripts/check_tokens.sh                                       # fails when stale, or when a font differs from the Mac's
```

Every Mac sentence is searched for verbatim before it is emitted, so a changed Mac sentence fails the generator instead
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
- `scripts/capture.sh 100|125|150` - every room state at that display scale, then `measure.py` (27 geometry/timing
  checks). `WID_BREAK=anchor35 scripts/capture.sh 150` must fail the anchor check.
- `scripts/e2e.sh 150|100 [0]` - the whole product against the real `services/license` (built from this repository,
  unmodified) in Stripe TEST mode behind the loopback fake Stripe: first launch, three trial sessions, activation card,
  Buy hand-off, a paid test session, the two-PC limit, activation, relaunch, refund and revocation. Needs the QA MSIX
  installed (`scripts/package-msix.sh qa`). `scripts/measure_screens.py` measures its captures.
- `scripts/package-msix.sh release|qa` - builds, test-signs and installs the MSIX on the test PC with the Windows SDK
  build tools (`packaging/make-msix.ps1`, `packaging/STORE.md` for the Store identity). Test signing uses a
  throw-away `CN=WID Test Signing` certificate; no production certificate or Store submission lives here.

Test switches (never set by the shortcut): `WID_SESSION_SECONDS`, `WID_SILENCE_SECONDS`, `WID_LOG`, `WID_SOUND=1`,
`WID_BREAK` (only in `-tags imebreak` builds).

`scripts/mke2e.py`, `mkscript.py`, `mksuite.py` and `mkcapture.py` generate the `cmd/drv` scripts those runs push;
`winrun.sh`, `run-drv.sh` and `clearcred.ps1` are the ssh plumbing.
