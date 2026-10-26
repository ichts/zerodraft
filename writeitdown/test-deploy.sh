#!/usr/bin/env bash
# Exercise writeitdown/deploy.sh and writeitdown/bundle.sh against a local fixture host, with no
# network, no ssh daemon, and no write outside a temporary directory.
# [INPUT] Nothing. Optional: --keep (keep the temporary fixture root and print its path) and
#         WID_DEPLOY_TEST_ROOT (use that directory as the fixture root instead of mktemp).
# [OUTPUT] One PASS/FAIL line per check, then a summary. Exit 0 only when every check passed.
# [POS] writeitdown/test-deploy.sh - the regression suite for the operator deploy tooling. The host
#       is a fake ssh command that runs deploy.sh's remote commands locally inside the fixture, so
#       the real deploy script, the real install.sh, and the real bundle flow are all executed.
# [PROTOCOL] The fixture is a sandbox copy of the production files; its install.sh has only its two
#       hardcoded host facts rewritten (TARGET and the /var/www existence check), the same rewrite
#       writeitdown/qa/test-install.py already uses. Root is simulated by an `id` shim on the fake
#       host's PATH. The published-site checks run against a local python http.server serving the
#       fixture's live tree, so llms.txt and the four page classes answer with real bytes and real
#       content types. Failing-first proof is part of the suite: every check that can be removed is
#       removed in a mutated copy of deploy.sh, and the matching case must then fail.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd -P)
DEPLOY=$HERE/deploy.sh
BUNDLE_SH=$HERE/bundle.sh
keep=0
for arg in "$@"; do
  case $arg in
    --keep) keep=1 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done
if [ -n "${WID_DEPLOY_TEST_ROOT:-}" ]; then
  mkdir -p "$WID_DEPLOY_TEST_ROOT"
  ROOT=$(cd -- "$WID_DEPLOY_TEST_ROOT" && pwd -P)
else
  ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wid-deploy-test.XXXXXX")
  ROOT=$(cd -- "$ROOT" && pwd -P)
fi
MUTANTS=$ROOT/mutants
mkdir -p "$MUTANTS"

# The production file list is read from install.sh, the same source bundle.sh uses.
PROD_FILES=$(sed -n "s/^FILES='\(.*\)'\$/\\1/p" "$HERE/install.sh" | head -1)

checks=0
failures=0
SERVER_PID=''
cleanup() {
  stop_server
  if [ "$keep" -eq 0 ]; then
    rm -rf -- "$ROOT"
  else
    printf 'fixture root kept: %s\n' "$ROOT"
  fi
}
trap cleanup EXIT

pass() { checks=$((checks + 1)); printf 'PASS %s\n' "$1"; }
fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'FAIL %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '     %s\n' "$2"; fi
}
check_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}
check_contains() {
  if grep -Fq -- "$3" "$2"; then pass "$1"; else fail "$1" "no '$3' in $(basename -- "$2")"; fi
}
check_absent() {
  if grep -Fq -- "$3" "$2" 2>/dev/null; then fail "$1" "'$3' unexpectedly in $(basename -- "$2")"; else pass "$1"; fi
}
check_true() {
  local name=$1
  shift
  if "$@"; then pass "$name"; else fail "$name" "$*"; fi
}
check_file() {
  if [ -f "$2" ]; then pass "$1"; else fail "$1" "missing file $2"; fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  else
    shasum -a 256 -- "$1" | cut -d' ' -f1
  fi
}

# "<sha256>  <path>" for every file under a directory, sorted by path
tree_listing() {
  ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r rel; do
    printf '%s  %s\n' "$(sha256_of "$rel")" "$rel"
  done )
}

# the fixture's own state, without the test's command log
fixture_state() {
  tree_listing "$CASE/live"
  tree_listing "$CASE/snapshots"
  if [ -d "$CASE/staging" ]; then
    printf 'staging: present\n'
    tree_listing "$CASE/staging" | sed 's|^|staging |'
  else
    printf 'staging: absent\n'
  fi
}

start_server() { # start_server <directory>: sets BASE_URL and SERVER_PID
  local port i
  port=$(python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()') || return 1
  python3 -m http.server --bind 127.0.0.1 --directory "$1" "$port" >/dev/null 2>&1 &
  SERVER_PID=$!
  BASE_URL="http://127.0.0.1:$port"
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS -o /dev/null --max-time 1 "$BASE_URL/" 2>/dev/null; then return 0; fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

stop_server() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    SERVER_PID=''
  fi
}

# ---------------------------------------------------------------------------
# fixture: the production files plus a fake host
# ---------------------------------------------------------------------------
fixture() { # fixture <case name>
  CASE=$ROOT/$1
  rm -rf -- "$CASE"
  mkdir -p "$CASE/bin" "$CASE/live" "$CASE/snapshots" "$CASE/varwww" "$CASE/out" "$CASE/tree"
  stop_server

  local rel
  for rel in $PROD_FILES; do
    mkdir -p "$CASE/tree/$(dirname "$rel")"
    cp "$HERE/$rel" "$CASE/tree/$rel"
  done
  # Only the two hardcoded host facts change, as in writeitdown/qa/test-install.py.
  sed -e "s|^TARGET=/var/www/writeitdown.app\$|TARGET=$CASE/live|" \
      -e "s|/var/www|$CASE/varwww|g" \
      "$HERE/install.sh" >"$CASE/tree/install.sh"

  # The fake host runs deploy.sh's remote commands locally; root is simulated by an id shim.
  cat >"$CASE/bin/id" <<SHIM
#!/bin/sh
if [ "\${1:-}" = "-u" ]; then printf '%s\\n' "\${FX_FAKE_UID:-0}"; exit 0; fi
exec /usr/bin/id "\$@"
SHIM
  chmod +x "$CASE/bin/id"

  cat >"$CASE/fake-ssh" <<FAKE
#!/bin/sh
set -u
log=\${FX:-}/commands.log
while [ \$# -gt 0 ]; do
  case \$1 in
    -o) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
host=\${1:-}
shift || true
[ "\$host" = "\$FX_HOST" ] || { printf 'fake host: unexpected target %s\n' "\$host" >&2; exit 64; }
cmd=\${1:-}
[ -n "\$cmd" ] || { printf 'fake host: empty command\n' >&2; exit 64; }
printf '%s\n' "\$cmd" >>"\$log"
export PATH="\$FX/bin:\$PATH"
case \$cmd in
  *"'install'"*)
    if [ -n "\${FX_INSTALL_FAIL:-}" ]; then
      printf 'fake host: the installer refused to run\n' >&2
      exit 1
    fi
    rc=0
    sh -c "\$cmd" || rc=\$?
    if [ "\$rc" -eq 0 ] && [ -n "\${FX_POST_INSTALL:-}" ]; then
      sh -c "\$FX_POST_INSTALL" || exit \$?
    fi
    exit \$rc
    ;;
esac
sh -c "\$cmd"
FAKE
  chmod +x "$CASE/fake-ssh"

  export FX=$CASE
  export FX_HOST=deploy@fixture.example
  unset FX_POST_INSTALL FX_INSTALL_FAIL FX_FAKE_UID FX_SERVER_PID

  "$BUNDLE_SH" --tree "$CASE/tree" --out "$CASE/out" >"$CASE/bundle.log" 2>&1
  if [ $? -ne 0 ]; then
    fail 'fixture bundles the tested tree' "$(cat "$CASE/bundle.log")"
    return 1
  fi

  seed_live
  if ! start_server "$CASE/live"; then
    fail 'fixture http server starts' "for $1"
    return 1
  fi
  export FX_SERVER_PID=$SERVER_PID
  DEPLOY_ARGS=(
    --bundle "$CASE/out/writeitdown-deploy.tar.gz"
    --host "$FX_HOST"
    --live-root "$CASE/live"
    --snapshot-dir "$CASE/snapshots"
    --staging-dir "$CASE/staging"
    --url "$BASE_URL"
    --ssh "$CASE/fake-ssh"
  )
  return 0
}

# The "old site": every production file with different bytes, plus files an install must not touch.
seed_live() {
  local rel
  while IFS= read -r rel; do
    mkdir -p "$CASE/live/$(dirname "$rel")"
    { cat "$HERE/$rel"; printf '\nold deploy marker %s\n' "$rel"; } >"$CASE/live/$rel"
  done <<EOF
$(printf '%s\n' $PROD_FILES)
EOF
  mkdir -p "$CASE/live/download/updates" "$CASE/live/download/keep-empty"
  printf 'dmg placeholder\n' >"$CASE/live/download/Write-It-Down-1.0.dmg"
  printf '<rss/>\n' >"$CASE/live/download/appcast.xml"
  printf 'zip placeholder\n' >"$CASE/live/download/updates/Write-It-Down-1.0.zip"
  printf 'operator note\n' >"$CASE/live/OPERATOR.txt"
}

run_deploy() { # run_deploy [extra args...]: sets RC and writes $CASE/deploy.log
  "$DEPLOY" "${DEPLOY_ARGS[@]}" "$@" >"$CASE/deploy.log" 2>&1
  RC=$?
}

snapshot_files() { find "$CASE/snapshots" -type f -name '*.tar.gz' | LC_ALL=C sort; }

expect_untouched() { # expect_untouched <name> <listing before>
  tree_listing "$CASE/live" >"$CASE/live.now"
  check_true "$1: live tree unchanged" diff -q "$2" "$CASE/live.now"
}

expect_restored() { # expect_restored <name> <listing before>
  tree_listing "$CASE/live" >"$CASE/live.now"
  if diff -q "$2" "$CASE/live.now" >/dev/null 2>&1; then
    pass "$1: live tree restored to the pre-deploy state"
  else
    fail "$1: live tree restored to the pre-deploy state" "$(diff -u "$2" "$CASE/live.now" | sed -n '1,12p' | tr '\n' ' ')"
  fi
}

# ---------------------------------------------------------------------------
# case: good bundle
# ---------------------------------------------------------------------------
case_good() {
  local start=$failures rel bad=0
  fixture good || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  mkdir -p "$CASE/old"
  cp "$CASE/live/index.html" "$CASE/old/index.html"
  run_deploy
  check_eq 'good: exit code' 0 "$RC"
  check_contains 'good: outcome' "$CASE/deploy.log" 'DEPLOYED'
  check_contains 'good: reports the snapshot' "$CASE/deploy.log" "$CASE/snapshots/"

  for rel in $PROD_FILES; do
    cmp -s "$CASE/live/$rel" "$CASE/tree/$rel" || {
      bad=$((bad + 1))
      printf '     differs: %s\n' "$rel" >&2
    }
  done
  check_eq 'good: every deployed file matches the tested tree' 0 "$bad"

  local prod_count manifest_records last
  prod_count=$(printf '%s\n' $PROD_FILES | wc -l | tr -d ' ')
  manifest_records=$(awk 'NF && $1 !~ /^#/ && $1 !~ /^bundle/' "$CASE/out/MANIFEST" | wc -l | tr -d ' ')
  check_eq 'good: the manifest covers the whole production set' "$prod_count" "$manifest_records"
  last=$(awk 'NF && $1 !~ /^#/ && $1 !~ /^bundle/ { h = $1; sub(/^[0-9a-f]+ +/, ""); p = $0 } END { print h "  " p }' "$CASE/out/MANIFEST")
  check_contains 'good: the summary prints each verified hash' "$CASE/deploy.log" "  $last"

  local snap
  snap=$(find "$CASE/snapshots" -type f -name '*.tar.gz' | head -1)
  check_file 'good: a snapshot was kept' "$snap"
  if [ -n "$snap" ]; then
    mkdir -p "$CASE/snapshot.extract"
    tar -xzf "$snap" -C "$CASE/snapshot.extract" 2>/dev/null
    check_true 'good: the snapshot holds the pre-deploy bytes' \
      cmp -s "$CASE/snapshot.extract/live/index.html" "$CASE/old/index.html"
  fi
  check_file 'good: the published DMG survives' "$CASE/live/download/Write-It-Down-1.0.dmg"
  check_file 'good: the sparkle payload survives' "$CASE/live/download/updates/Write-It-Down-1.0.zip"
  check_file 'good: an operator file survives' "$CASE/live/OPERATOR.txt"
  check_file 'good: the previous index backup is created' "$CASE/live/index.html.dc-bak2"
  check_contains 'good: extras are reported, not verified' "$CASE/deploy.log" 'left untouched'
  check_absent 'good: no failure marker' "$CASE/deploy.log" 'ROLLED BACK'
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: tampered bundle (the bytes are not the tested bytes)
# ---------------------------------------------------------------------------
case_tampered_bundle() {
  local start=$failures
  fixture tampered-bundle || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  printf 'x' >>"$CASE/out/writeitdown-deploy.tar.gz"
  run_deploy
  check_eq 'tampered bundle: exit code' 2 "$RC"
  check_contains 'tampered bundle: names the mismatch' "$CASE/deploy.log" 'bundle sha256 mismatch'
  expect_untouched 'tampered bundle' "$CASE/live.before"
  check_eq 'tampered bundle: no snapshot taken' '' "$(snapshot_files)"
  check_eq 'tampered bundle: nothing uploaded' 'absent' "$([ -d "$CASE/staging" ] && echo present || echo absent)"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: an explicit --sha256 that disagrees with the manifest
# ---------------------------------------------------------------------------
case_sha_mismatch() {
  local start=$failures
  fixture sha-mismatch || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  run_deploy --sha256 0000000000000000000000000000000000000000000000000000000000000000
  check_eq 'explicit sha: exit code' 2 "$RC"
  check_contains 'explicit sha: names the disagreement' "$CASE/deploy.log" 'disagrees with the manifest'
  expect_untouched 'explicit sha' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: a file in the bundle that the manifest does not list
# ---------------------------------------------------------------------------
case_manifest_missing() {
  local start=$failures
  fixture manifest-missing || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  grep -v '^[0-9a-f]*  room.js$' "$CASE/out/MANIFEST" >"$CASE/out/MANIFEST.trimmed"
  mv "$CASE/out/MANIFEST.trimmed" "$CASE/out/MANIFEST"
  run_deploy
  check_eq 'manifest missing a file: exit code' 2 "$RC"
  check_contains 'manifest missing a file: names it' "$CASE/deploy.log" 'missing from the manifest: room.js'
  expect_untouched 'manifest missing a file' "$CASE/live.before"
  check_eq 'manifest missing a file: no snapshot taken' '' "$(snapshot_files)"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: bundle bytes that do not match the manifest's per-file hashes
# ---------------------------------------------------------------------------
case_file_hash() {
  local start=$failures new_sha
  fixture file-hash || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  mkdir -p "$CASE/repack"
  tar -xzf "$CASE/out/writeitdown-deploy.tar.gz" -C "$CASE/repack"
  printf '\nhand edit\n' >>"$CASE/repack/index.html"
  # shellcheck disable=SC2046 # the file list is deliberately split into arguments
  ( cd "$CASE/repack" && tar -czf "$CASE/out/writeitdown-deploy.tar.gz" $(find . -type f | sed 's|^\./||' | LC_ALL=C sort) )
  new_sha=$(sha256_of "$CASE/out/writeitdown-deploy.tar.gz")
  sed -e "s|^bundle-sha256: .*|bundle-sha256: $new_sha|" "$CASE/out/MANIFEST" >"$CASE/out/MANIFEST.new"
  mv "$CASE/out/MANIFEST.new" "$CASE/out/MANIFEST"
  run_deploy
  check_eq 'file hash mismatch: exit code' 2 "$RC"
  check_contains 'file hash mismatch: names the file' "$CASE/deploy.log" 'bundle file index.html hashes to'
  expect_untouched 'file hash mismatch' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: the live tree disagrees with the manifest after install (rollback)
# ---------------------------------------------------------------------------
case_live_mismatch() {
  local start=$failures
  fixture live-mismatch || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  export FX_POST_INSTALL='printf "corrupted after install\n" >>"$FX/live/room.js"'
  run_deploy
  unset FX_POST_INSTALL
  check_eq 'live mismatch: exit code' 4 "$RC"
  check_contains 'live mismatch: names the file' "$CASE/deploy.log" 'hash mismatch: room.js'
  check_contains 'live mismatch: reports the rollback' "$CASE/deploy.log" 'ROLLED BACK'
  expect_restored 'live mismatch' "$CASE/live.before"
  check_true 'live mismatch: the snapshot is kept' test -n "$(snapshot_files)"
  check_true 'live mismatch: the file install created is gone' test ! -e "$CASE/live/index.html.dc-bak2"
  check_true 'live mismatch: a pre-existing empty directory survives the rollback' test -d "$CASE/live/download/keep-empty"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: the published site stops answering after install (rollback)
# ---------------------------------------------------------------------------
case_publish_broken() {
  local start=$failures
  fixture publish-broken || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  export FX_POST_INSTALL='kill "$FX_SERVER_PID" 2>/dev/null; true'
  run_deploy
  unset FX_POST_INSTALL
  check_eq 'publish broken: exit code' 4 "$RC"
  check_contains 'publish broken: reports the dead site' "$CASE/deploy.log" 'unreachable'
  check_contains 'publish broken: reports the rollback' "$CASE/deploy.log" 'ROLLED BACK'
  expect_restored 'publish broken' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: the install itself fails (rollback)
# ---------------------------------------------------------------------------
case_install_fails() {
  local start=$failures
  fixture install-fails || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  export FX_INSTALL_FAIL=1
  run_deploy
  unset FX_INSTALL_FAIL
  check_eq 'install failure: exit code' 3 "$RC"
  check_contains 'install failure: names the step' "$CASE/deploy.log" 'install.sh failed on the host'
  expect_restored 'install failure' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: a site that already fails a published check is not deployed over
# ---------------------------------------------------------------------------
case_pre_broken() {
  local start=$failures
  fixture pre-broken || return 1
  rm -f "$CASE/live/llms.txt"
  tree_listing "$CASE/live" >"$CASE/live.before"
  run_deploy
  check_eq 'pre-broken site: exit code' 3 "$RC"
  check_contains 'pre-broken site: refuses to deploy' "$CASE/deploy.log" 'refusing to deploy over it'
  expect_untouched 'pre-broken site' "$CASE/live.before"
  check_eq 'pre-broken site: no snapshot taken' '' "$(snapshot_files)"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: dry run changes nothing
# ---------------------------------------------------------------------------
case_dry_run() {
  local start=$failures before after
  fixture dry-run || return 1
  before=$(fixture_state | sha256_of /dev/stdin)
  run_deploy --dry-run
  check_eq 'dry run: exit code' 0 "$RC"
  check_contains 'dry run: says so' "$CASE/deploy.log" 'DRY RUN - nothing changed'
  check_contains 'dry run: names the snapshot it would take' "$CASE/deploy.log" 'would snapshot'
  check_contains 'dry run: prints the published checks' "$CASE/deploy.log" 'llms.txt:'
  after=$(fixture_state | sha256_of /dev/stdin)
  check_eq 'dry run: the live tree, snapshots, and staging are untouched' "$before" "$after"
  check_eq 'dry run: no staging directory' 'absent' "$([ -d "$CASE/staging" ] && echo present || echo absent)"
  check_eq 'dry run: no snapshot taken' '' "$(snapshot_files)"
  check_absent 'dry run: never uploaded a bundle' "$CASE/commands.log" 'bundle.tar.gz'
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: usage and precondition errors never reach the host
# ---------------------------------------------------------------------------
case_usage() {
  local start=$failures
  fixture usage || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"

  run_deploy --bundle ''
  check_eq 'usage: an empty bundle is refused' 1 "$RC"
  run_deploy --live-root relative/path
  check_eq 'usage: a relative live root is refused' 1 "$RC"
  run_deploy --staging-dir "$CASE/live/staging"
  check_eq 'usage: staging inside the live tree is refused' 1 "$RC"
  run_deploy --snapshot-dir "$CASE/live/backups"
  check_eq 'usage: a snapshot inside the live tree is refused' 1 "$RC"
  run_deploy --host -oProxyCommand=bad
  check_eq 'usage: an ssh-option host is refused' 1 "$RC"
  run_deploy --url file:///etc/passwd
  check_eq 'usage: a non-http url is refused' 1 "$RC"
  run_deploy --nonsense
  check_eq 'usage: an unknown flag is refused' 1 "$RC"
  mv "$CASE/out/MANIFEST" "$CASE/out/MANIFEST.gone"
  run_deploy
  check_eq 'usage: a missing manifest is refused' 1 "$RC"
  mv "$CASE/out/MANIFEST.gone" "$CASE/out/MANIFEST"
  run_deploy --help
  check_eq 'usage: --help exits clean' 0 "$RC"
  check_contains 'usage: --help documents the exit codes' "$CASE/deploy.log" 'Exit codes:'

  expect_untouched 'usage' "$CASE/live.before"
  check_eq 'usage: nothing reached the host' 'absent' "$([ -d "$CASE/staging" ] && echo present || echo absent)"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: an unreachable host stops before any write
# ---------------------------------------------------------------------------
case_host_unreachable() {
  local start=$failures
  fixture host-unreachable || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  printf '#!/bin/sh\nprintf "ssh: connect to host: Connection refused\\\\n" >&2\nexit 255\n' >"$CASE/refusing-ssh"
  chmod +x "$CASE/refusing-ssh"
  run_deploy --ssh "$CASE/refusing-ssh"
  check_eq 'unreachable host: exit code' 3 "$RC"
  check_contains 'unreachable host: names the channel' "$CASE/deploy.log" 'cannot reach'
  expect_untouched 'unreachable host' "$CASE/live.before"
  check_eq 'unreachable host: no staging directory' 'absent' "$([ -d "$CASE/staging" ] && echo present || echo absent)"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: a non-root ssh user is told install.sh will use sudo -n
# ---------------------------------------------------------------------------
case_sudo_path() {
  local start=$failures
  fixture sudo-path || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  export FX_FAKE_UID=501
  run_deploy --dry-run
  unset FX_FAKE_UID
  check_eq 'non-root user: dry run exit code' 0 "$RC"
  check_contains 'non-root user: announces sudo -n' "$CASE/deploy.log" 'sudo -n'
  expect_untouched 'non-root user' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: install.sh's target and --live-root must agree
# ---------------------------------------------------------------------------
case_target_mismatch() {
  local start=$failures
  fixture target-mismatch || return 1
  tree_listing "$CASE/live" >"$CASE/live.before"
  run_deploy --live-root "$CASE/other-live"
  check_eq 'target mismatch: exit code' 2 "$RC"
  check_contains 'target mismatch: names both paths' "$CASE/deploy.log" "but --live-root is $CASE/other-live"
  expect_untouched 'target mismatch' "$CASE/live.before"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# case: bundle.sh refuses an incomplete or symlinked tested tree
# ---------------------------------------------------------------------------
case_bundle_gates() {
  local start=$failures
  fixture bundle-gates || return 1
  mv "$CASE/tree/room.js" "$CASE/tree/room.js.gone"
  "$BUNDLE_SH" --tree "$CASE/tree" --out "$CASE/out2" >"$CASE/bundle-missing.log" 2>&1
  check_eq 'bundle: a missing production file is refused' 1 "$?"
  check_contains 'bundle: names the missing file' "$CASE/bundle-missing.log" 'room.js'
  mv "$CASE/tree/room.js.gone" "$CASE/tree/room.js"
  mv "$CASE/tree/room.js" "$CASE/tree/room.real"
  ln -s room.real "$CASE/tree/room.js"
  "$BUNDLE_SH" --tree "$CASE/tree" --out "$CASE/out2" >"$CASE/bundle-symlink.log" 2>&1
  check_eq 'bundle: a symlinked production file is refused' 1 "$?"
  check_contains 'bundle: says symlink' "$CASE/bundle-symlink.log" 'symlink'
  rm -f "$CASE/tree/room.js"
  mv "$CASE/tree/room.real" "$CASE/tree/room.js"
  "$BUNDLE_SH" --tree "$CASE/tree" --out "$CASE/out3" >"$CASE/bundle-again.log" 2>&1
  check_eq 'bundle: a clean tree packs' 0 "$?"
  check_eq 'bundle: the same tree packs to the same bytes' \
    "$(sha256_of "$CASE/out/writeitdown-deploy.tar.gz")" "$(sha256_of "$CASE/out3/writeitdown-deploy.tar.gz")"
  "$BUNDLE_SH" --tree "$CASE/tree" --out "$CASE/out3" --bogus >/dev/null 2>&1
  check_eq 'bundle: an unknown flag is refused' 1 "$?"
  stop_server
  [ "$failures" -eq "$start" ]
}

# ---------------------------------------------------------------------------
# failing-first proof: remove one check and the matching case must fail
# ---------------------------------------------------------------------------
mutant() { # mutant <name> <sed expression>: an executable copy with one check removed
  sed "$2" "$DEPLOY" >"$MUTANTS/$1"
  chmod +x "$MUTANTS/$1"
}

mutation_proves() { # mutation_proves <name> <mutant script> <case function>
  local name=$1 script=$2 case_fn=$3
  if ( DEPLOY="$script"; "$case_fn" ) >"$MUTANTS/$name.log" 2>&1; then
    fail "mutation $name: $case_fn still passed without its check"
  else
    pass "mutation $name: $case_fn fails without its check"
  fi
}

case_mutations() {
  mutant no-sha-check 's@^  || fail_before_writes "bundle sha256 mismatch@  || true "bundle sha256 mismatch@'
  mutant no-manifest-set-check 's@^\[ -z "\$extra" \].*$@[ -z "$extra" ] || true "@'
  mutant no-file-hash-check 's@^  \[ "\$got" = "\$hash" \].*$@  true "$got $hash"@'
  mutant no-rollback 's@^  if ! helper restore .*$@  if false; then@'
  mutant no-publish-check 's@^  rollback 4 "\$http_failures published check.*$@  true@'

  mutation_proves no-sha-check "$MUTANTS/no-sha-check" case_tampered_bundle
  mutation_proves no-manifest-set-check "$MUTANTS/no-manifest-set-check" case_manifest_missing
  mutation_proves no-file-hash-check "$MUTANTS/no-file-hash-check" case_file_hash
  mutation_proves no-rollback "$MUTANTS/no-rollback" case_live_mismatch
  mutation_proves no-publish-check "$MUTANTS/no-publish-check" case_publish_broken
}

# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
printf 'fixture root: %s\n' "$ROOT"

case_good
case_tampered_bundle
case_sha_mismatch
case_manifest_missing
case_file_hash
case_live_mismatch
case_publish_broken
case_install_fails
case_pre_broken
case_dry_run
case_usage
case_host_unreachable
case_sudo_path
case_target_mismatch
case_bundle_gates
case_mutations

printf '\n%s checks, %s failed\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
printf 'PASS: every deploy and bundle path behaves\n'
