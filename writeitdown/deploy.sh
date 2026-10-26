#!/usr/bin/env bash
# Deploy a tested writeitdown.app bundle to the host that serves it, verify the live result, and roll
# back automatically when anything disagrees.
# [INPUT] --bundle <tarball> (from bundle.sh) and --host <ssh target> are required. Optional:
#         --manifest <path> (default: MANIFEST beside the tarball), --sha256 <hex> (the expected
#         bundle hash; it must agree with the manifest when both are given), --live-root,
#         --snapshot-dir, --staging-dir, --url, --ssh, --dry-run. No environment variables; no
#         credential is read, stored, printed, or passed on a command line.
# [OUTPUT] A step log, one verified sha256 line per deployed file, the snapshot path, the published
#          URL checks, and one outcome line. Exit 0 when the site is deployed and verified (or a dry
#          run changed nothing); 1 for a usage or precondition error; 2 for a bundle or manifest
#          integrity failure with the host untouched; 3 when a remote step or the install itself
#          failed (rolled back); 4 when post-install verification found a mismatch (rolled back and
#          re-verified); 5 when the rollback did not reproduce the pre-deploy tree.
# [POS] writeitdown/deploy.sh - the operator's instrument for the writeitdown.app host. It automates
#       the manual sequence in README.md "Deploy" (extract the tested bundle, run install.sh as root)
#       and adds the two guarantees that sequence lacks: a snapshot taken before any write, and a
#       per-file hash comparison against the bundle manifest afterwards. It is run by hand from a
#       machine with host access; agents never run it against a live host.
# [PROTOCOL] Remote work goes through one ssh channel in BatchMode (keys or an agent only), so a
#            host that wants a password fails immediately instead of prompting. The remote side is a
#            small helper uploaded to the staging directory; its subcommands only touch the staging
#            directory, the snapshot directory, and - during install and rollback - the live tree.
#            The live tree is never removed wholesale: rollback extracts the snapshot over it and
#            deletes only files this run introduced. install.sh owns the production file list and the
#            live root, so this script cross-checks --live-root against its TARGET line instead of
#            duplicating either. The manifest format is shared with bundle.sh.
set -euo pipefail

PROG=writeitdown-deploy
DEFAULT_LIVE_ROOT=/var/www/writeitdown.app
DEFAULT_SNAPSHOT_DIR=/var/backups/writeitdown.app
DEFAULT_STAGING_DIR=/var/tmp/writeitdown-deploy
DEFAULT_URL=https://writeitdown.app

bundle=''
host=''
manifest=''
expected_sha=''
live_root=$DEFAULT_LIVE_ROOT
snapshot_dir=$DEFAULT_SNAPSHOT_DIR
staging_dir=$DEFAULT_STAGING_DIR
base_url=$DEFAULT_URL
ssh_cmd=ssh
dry_run=0

work=''
bundle_sha=''
snapshot_path='none taken'
verified_lines=''
http_lines=''
outcome=''

usage() {
  cat <<'USAGE'
Usage: sh writeitdown/deploy.sh --bundle <tarball> --host <ssh target> [options]

Deploys a tested writeitdown.app bundle: verifies the bundle hash, snapshots the live tree,
uploads, installs, verifies every live hash against the bundle manifest, and rolls back on a
mismatch.

Required:
  --bundle <path>        tarball produced by writeitdown/bundle.sh
  --host <user@host>     ssh target for the host that serves writeitdown.app

Options:
  --manifest <path>      manifest to verify against (default: MANIFEST beside the tarball)
  --sha256 <hex>         expected bundle sha256 (must agree with the manifest when both are given)
  --live-root <path>     live tree on the host (default: /var/www/writeitdown.app)
  --snapshot-dir <path>  where the pre-deploy snapshot is kept (default: /var/backups/writeitdown.app)
  --staging-dir <path>   upload and extract directory (default: /var/tmp/writeitdown-deploy)
  --url <base>           published base URL for the HTTP checks (default: https://writeitdown.app)
  --ssh <program>        ssh program to use (default: ssh)
  --dry-run              perform every read-only step and print what would happen
  -h, --help             show this help

Exit codes:
  0 deployed and verified (or a clean dry run)
  1 usage or precondition error
  2 bundle or manifest integrity failure; the host was not touched
  3 remote step or install failure; the snapshot was restored when one existed
  4 post-install verification failed; the snapshot was restored and re-verified
  5 the rollback did not reproduce the pre-deploy tree; the host needs attention
USAGE
}

log() { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
note() { printf '   %s\n' "$*"; }
die() {
  local code=$1
  shift
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit "$code"
}
die_usage() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  printf 'Run %s --help for usage.\n' "$PROG" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
need_value() {
  [ "$#" -ge 2 ] && [ -n "${2:-}" ] || die_usage "missing value for $1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundle) need_value "$@"; bundle=$2; shift 2 ;;
    --host) need_value "$@"; host=$2; shift 2 ;;
    --manifest) need_value "$@"; manifest=$2; shift 2 ;;
    --sha256) need_value "$@"; expected_sha=$2; shift 2 ;;
    --live-root) need_value "$@"; live_root=$2; shift 2 ;;
    --snapshot-dir) need_value "$@"; snapshot_dir=$2; shift 2 ;;
    --staging-dir) need_value "$@"; staging_dir=$2; shift 2 ;;
    --url) need_value "$@"; base_url=$2; shift 2 ;;
    --ssh) need_value "$@"; ssh_cmd=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
[ "$#" -eq 0 ] || die_usage "unexpected argument: $1"

[ -n "$bundle" ] || die_usage '--bundle is required'
[ -n "$host" ] || die_usage '--host is required'
case "$host" in
  -*) die_usage "--host may not start with '-': $host" ;;
  *[[:space:]]* | *\'* | *\"* | *';'* | *'&'* | *'|'* | *'$'* | *'`'*)
    die_usage "unusable --host value: $host" ;;
esac
if [ ! -x "$ssh_cmd" ]; then
  command -v "$ssh_cmd" >/dev/null 2>&1 || die_usage "ssh program not found: $ssh_cmd"
fi
[ -f "$bundle" ] && [ -r "$bundle" ] || die_usage "bundle not readable: $bundle"
bundle=$(cd -- "$(dirname -- "$bundle")" && pwd -P)/$(basename -- "$bundle")
if [ -z "$manifest" ]; then
  manifest=$(dirname -- "$bundle")/MANIFEST
fi
[ -f "$manifest" ] && [ -r "$manifest" ] || die_usage "manifest not readable: $manifest"
manifest=$(cd -- "$(dirname -- "$manifest")" && pwd -P)/$(basename -- "$manifest")
if [ -n "$expected_sha" ]; then
  case "$expected_sha" in
    *[!0-9a-f]*) die_usage '--sha256 must be 64 lowercase hex characters' ;;
  esac
  [ "${#expected_sha}" -eq 64 ] || die_usage '--sha256 must be 64 lowercase hex characters'
fi

# Remote paths are single-quoted into a remote shell command, so they must be boring and absolute.
check_remote_path() {
  local name=$1 value=$2
  case "$value" in
    /*) ;;
    *) die_usage "--$name must be an absolute path: $value" ;;
  esac
  case "$value" in
    *[[:space:]]* | *\'* | *\"* | *'$'* | *'`'* | *'..'* | */)
      die_usage "--$name contains an unusable path: $value" ;;
  esac
  [ "$value" != / ] || die_usage "--$name may not be /"
}
check_remote_path live-root "$live_root"
check_remote_path snapshot-dir "$snapshot_dir"
check_remote_path staging-dir "$staging_dir"
case "$staging_dir/" in "$live_root"/*) die_usage '--staging-dir may not sit inside --live-root' ;; esac
case "$live_root/" in "$staging_dir"/*) die_usage '--live-root may not sit inside --staging-dir' ;; esac
case "$snapshot_dir/" in "$live_root"/*) die_usage '--snapshot-dir may not sit inside --live-root' ;; esac
case "$base_url" in
  http://* | https://*) ;;
  *) die_usage "--url must be an http or https base URL: $base_url" ;;
esac
base_url=${base_url%/}
command -v curl >/dev/null 2>&1 || die_usage 'curl is required for the published URL checks'

work=$(mktemp -d "${TMPDIR:-/tmp}/wid-deploy.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | cut -d' ' -f1
  else
    openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1
  fi
}

# quote a value for the remote shell
rq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

remote() { "$ssh_cmd" -o BatchMode=yes "$host" "$1"; }

helper_path() { printf '%s/wid-deploy-remote.sh' "$staging_dir"; }

helper() {
  local sub=$1
  shift
  local args='' arg
  for arg in "$@"; do args="$args $(rq "$arg")"; done
  remote "sh $(rq "$(helper_path)") $(rq "$sub")$args"
}

upload() { # upload <local file> <remote path>; the remote parent must exist
  "$ssh_cmd" -o BatchMode=yes "$host" "cat > $(rq "$2")" <"$1"
}

# "hash  path" lines -> "path<TAB>hash" lines, sorted
pairs_from_hash_lines() {
  awk '{ hash = $1; sub(/^[0-9a-f]+ +/, "", $0); print $0 "\t" hash }' "$1" | LC_ALL=C sort
}

paths_only() { awk -F'\t' '{ print $1 }' "$1" | LC_ALL=C sort; }

summary_and_exit() {
  local code=$1
  log ''
  log '== writeitdown deploy summary =='
  log "host:        $host"
  log "bundle:      $bundle"
  log "bundle sha:  ${bundle_sha:-not verified}"
  log "live root:   $live_root"
  log "snapshot:    $snapshot_path"
  log "files:       ${installed_count:-0} in the manifest, ${verified_count:-0} verified live"
  if [ -n "${live_extras:-}" ]; then
    log "untouched:   $live_extras other file(s) in the live tree (DMG, feed, backups, extras)"
  fi
  if [ -n "$verified_lines" ]; then
    log 'verified hashes:'
    printf '%s' "$verified_lines"
  fi
  if [ -n "$http_lines" ]; then
    log 'published checks:'
    printf '%s' "$http_lines"
  fi
  log "outcome:     $outcome"
  exit "$code"
}

fail_before_writes() { # integrity or precondition failure: nothing on the host was changed
  printf '%s: %s\n' "$PROG" "$1" >&2
  outcome="ABORTED BEFORE ANY WRITE - $1"
  summary_and_exit 2
}

die_remote() { # a remote step failed before anything on the host changed
  printf '%s: %s\n' "$PROG" "$1" >&2
  outcome="ABORTED BEFORE ANY WRITE - $1"
  summary_and_exit 3
}

# ---------------------------------------------------------------------------
# remote helper (uploaded once every read-only check has passed)
# ---------------------------------------------------------------------------
read -r -d '' REMOTE_HELPER <<'HELPER' || true
#!/bin/sh
# Uploaded by writeitdown/deploy.sh into the staging directory. It is a remote command surface for
# that script, never an installed site file.
set -eu

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | cut -d' ' -f1
  else
    openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1
  fi
}

list_tree() { # list_tree <root>: "<sha256>  <path>" for every regular file, sorted by path
  root=$1
  [ -d "$root" ] || { echo "no such directory: $root" >&2; return 1; }
  listing=$(mktemp "${TMPDIR:-/tmp}/wid-list.XXXXXX")
  ( cd "$root" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > "$listing"
  while IFS= read -r rel; do
    printf '%s  %s\n' "$(hash_file "$root/$rel")" "$rel"
  done < "$listing"
  rm -f -- "$listing"
}

snapshot_tree() { # snapshot_tree <live> <snapshot dir>: prints the archive path
  live=$1
  snapdir=$2
  case $live in /*) ;; *) echo "live root must be absolute: $live" >&2; return 1 ;; esac
  case $live in /|*/..|*/../*) echo "unusable live root: $live" >&2; return 1 ;; esac
  [ -d "$live" ] || { echo "live root does not exist: $live" >&2; return 1; }
  parent=$(dirname "$live")
  base=$(basename "$live")
  mkdir -p -- "$snapdir"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  archive="$snapdir/$base-$stamp.tar.gz"
  n=1
  while [ -e "$archive" ]; do
    archive="$snapdir/$base-$stamp-$n.tar.gz"
    n=$((n + 1))
  done
  tar -czf "$archive" -C "$parent" "$base"
  printf '%s\n' "$archive"
}

extract_bundle() { # extract_bundle <staging>: replaces <staging>/tree only
  staging=$1
  case $staging in ''|/|*/..|*/../*) echo "unusable staging directory: $staging" >&2; return 1 ;; esac
  [ -f "$staging/bundle.tar.gz" ] || { echo "no uploaded bundle in $staging" >&2; return 1; }
  rm -rf -- "$staging/tree"
  mkdir -p -- "$staging/tree"
  tar -xzf "$staging/bundle.tar.gz" -C "$staging/tree"
  [ -f "$staging/tree/install.sh" ] || { echo 'bundle has no install.sh at its root' >&2; return 1; }
}

install_site() { # install_site <staging> <sudo:0|1>
  staging=$1
  use_sudo=$2
  installer="$staging/tree/install.sh"
  [ -f "$installer" ] || { echo "no installer in $staging/tree" >&2; return 1; }
  if [ "$use_sudo" = 1 ]; then
    sudo -n sh "$installer"
  else
    sh "$installer"
  fi
}

restore_tree() { # restore_tree <archive> <live> <pre-install inventory: "hash  path" lines>
  archive=$1
  live=$2
  inventory=$3
  case $live in /|*/..|*/../*) echo "unusable live root: $live" >&2; return 1 ;; esac
  [ -f "$archive" ] || { echo "snapshot is missing: $archive" >&2; return 1; }
  [ -f "$inventory" ] || { echo "pre-install inventory is missing: $inventory" >&2; return 1; }
  parent=$(dirname "$live")
  scratch=$(dirname "$inventory")
  keep=$(mktemp "$scratch/restore-keep.XXXXXX")
  have=$(mktemp "$scratch/restore-have.XXXXXX")
  drop=$(mktemp "$scratch/restore-drop.XXXXXX")
  snap_dirs=$(mktemp "$scratch/restore-snapdirs.XXXXXX")
  live_dirs=$(mktemp "$scratch/restore-livedirs.XXXXXX")
  drop_dirs=$(mktemp "$scratch/restore-dropdirs.XXXXXX")
  awk '{ sub(/^[0-9a-f]+ +/, "", $0); print }' "$inventory" | LC_ALL=C sort > "$keep"
  list_tree "$live" | awk '{ sub(/^[0-9a-f]+ +/, "", $0); print }' | LC_ALL=C sort > "$have"
  # Files this deploy introduced are removed one by one; the live tree is never removed wholesale.
  LC_ALL=C comm -13 "$keep" "$have" > "$drop"
  while IFS= read -r rel; do
    case $rel in
      ''|/*|.|..|../*|*/../*|*/..) echo "refusing to remove suspicious path: $rel" >&2; return 1 ;;
    esac
    rm -f -- "$live/$rel"
  done < "$drop"
  # Only directories that the deploy itself introduced are pruned, and only when empty, so a
  # pre-existing empty directory (such as a fresh download/updates/) survives the rollback.
  tar -tzf "$archive" | while IFS= read -r entry; do
    case $entry in
      "$base"/) continue ;;
      "$base"/*/) printf '%s\n' "${entry#"$base"/}" ;;
    esac
  done | sed 's|/$||' | LC_ALL=C sort > "$snap_dirs"
  ( cd "$live" && find . -mindepth 1 -type d | sed 's|^\./||' | LC_ALL=C sort ) > "$live_dirs"
  LC_ALL=C comm -13 "$snap_dirs" "$live_dirs" | LC_ALL=C sort -r > "$drop_dirs"
  while IFS= read -r rel; do
    case $rel in
      ''|/*|.|..|../*|*/../*|*/..) continue ;;
    esac
    rmdir -- "$live/$rel" 2>/dev/null || true
  done < "$drop_dirs"
  rm -f -- "$keep" "$have" "$drop" "$snap_dirs" "$live_dirs" "$drop_dirs"
  tar -xzf "$archive" -C "$parent"
}

case ${1:-} in
  list) list_tree "$2" ;;
  snapshot) snapshot_tree "$2" "$3" ;;
  extract) extract_bundle "$2" ;;
  install) install_site "$2" "$3" ;;
  restore) restore_tree "$2" "$3" "$4" ;;
  *)
    echo "unknown remote helper command: ${1:-}" >&2
    exit 64
    ;;
esac
HELPER

# ---------------------------------------------------------------------------
# step 1: local bundle and manifest integrity
# ---------------------------------------------------------------------------
step "verify bundle $(basename -- "$bundle")"
bundle_sha=$(sha256_of "$bundle")
manifest_sha=$(sed -n 's/^bundle-sha256:[[:space:]]*\([0-9a-fA-F]\{64\}\)[[:space:]]*$/\1/p' "$manifest" | head -1 | tr 'A-F' 'a-f')
manifest_name=$(sed -n 's/^bundle:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$manifest" | head -1)
[ -n "$manifest_sha" ] || fail_before_writes "manifest $manifest carries no 'bundle-sha256:' line"
[ -n "$manifest_name" ] || fail_before_writes "manifest $manifest carries no 'bundle:' line"
[ "$manifest_name" = "$(basename -- "$bundle")" ] \
  || fail_before_writes "manifest names bundle $manifest_name but the given bundle is $(basename -- "$bundle")"
want_sha=$manifest_sha
if [ -n "$expected_sha" ]; then
  [ "$expected_sha" = "$manifest_sha" ] \
    || fail_before_writes "--sha256 $expected_sha disagrees with the manifest value $manifest_sha"
  want_sha=$expected_sha
fi
[ "$bundle_sha" = "$want_sha" ] \
  || fail_before_writes "bundle sha256 mismatch: expected $want_sha, got $bundle_sha"
note "sha256 $bundle_sha matches $(basename -- "$manifest")"

: >"$work/manifest.want"
while IFS= read -r line; do
  case $line in '' | '#'* | 'bundle:'* | 'bundle-sha256:'*) continue ;; esac
  hash=${line%%[[:space:]]*}
  rel=${line#"$hash"}
  rel=${rel#"${rel%%[![:space:]]*}"}
  rel=${rel%"${rel##*[![:space:]]}"}
  case "$hash" in *[!0-9a-f]*) fail_before_writes "manifest line is not 'sha256  path': $line" ;; esac
  [ "${#hash}" -eq 64 ] || fail_before_writes "manifest line carries a short hash: $line"
  [ -n "$rel" ] || fail_before_writes "manifest line carries no path: $line"
  case "$rel" in /* | .. | ../* | */..) fail_before_writes "manifest path is not relative to the site root: $rel" ;; esac
  printf '%s\t%s\n' "$rel" "$hash" >>"$work/manifest.want"
done <"$manifest"
LC_ALL=C sort -o "$work/manifest.want" "$work/manifest.want"
installed_count=$(wc -l <"$work/manifest.want" | tr -d ' ')
[ "$installed_count" -gt 0 ] || fail_before_writes "manifest $manifest lists no files"

step 'check the bundle against its manifest'
mkdir -p "$work/tree"
tar -xzf "$bundle" -C "$work/tree" || fail_before_writes "bundle $bundle is not a readable tarball"
installers=$(find "$work/tree" -mindepth 1 -maxdepth 2 -name install.sh -type f | LC_ALL=C sort)
[ -n "$installers" ] || fail_before_writes 'bundle contains no install.sh'
[ "$(printf '%s\n' "$installers" | wc -l | tr -d ' ')" -eq 1 ] \
  || fail_before_writes "bundle contains more than one install.sh: $installers"
site_source=$(dirname "$installers")

(cd "$site_source" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) >"$work/bundle.files"
{ awk -F'\t' '{ print $1 }' "$work/manifest.want"; printf 'install.sh\n'; } | LC_ALL=C sort >"$work/bundle.expected"
absent=$(LC_ALL=C comm -23 "$work/bundle.expected" "$work/bundle.files")
extra=$(LC_ALL=C comm -13 "$work/bundle.expected" "$work/bundle.files")
[ -z "$absent" ] || fail_before_writes "manifest lists files the bundle does not carry: $(printf '%s' "$absent" | tr '\n' ' ')"
[ -z "$extra" ] || fail_before_writes "bundle carries files missing from the manifest: $(printf '%s' "$extra" | tr '\n' ' ')"

while IFS=$'\t' read -r rel hash; do
  if [ ! -f "$site_source/$rel" ]; then
    fail_before_writes "bundle file is missing: $rel"
  fi
  got=$(sha256_of "$site_source/$rel")
  [ "$got" = "$hash" ] || fail_before_writes "bundle file $rel hashes to $got, manifest says $hash"
done <"$work/manifest.want"
note "$installed_count file(s) match the manifest, plus install.sh"

# --live-root must be the tree install.sh actually writes; otherwise verification would grade a
# different directory than the one that changed.
installer_target=$(sed -n 's/^TARGET=\(.*\)$/\1/p' "$site_source/install.sh" | head -1)
[ -n "$installer_target" ] || fail_before_writes 'install.sh carries no TARGET line to cross-check'
[ "$installer_target" = "$live_root" ] \
  || fail_before_writes "install.sh installs into $installer_target but --live-root is $live_root"
note "install.sh target $installer_target matches --live-root"

# ---------------------------------------------------------------------------
# step 2: read-only host checks
# ---------------------------------------------------------------------------
step "inspect host $host"
probe_script=$(
  cat <<PROBE
printf 'uid=%s\n' "\$(id -u)"
if [ -d $(rq "$live_root") ]; then
  printf 'live=present\n'
  printf 'live-files=%s\n' "\$(cd $(rq "$live_root") && find . -type f | wc -l | tr -d ' ')"
else
  printf 'live=absent\n'
fi
for tool in tar find; do
  if command -v \$tool >/dev/null 2>&1; then printf 'tool-%s=ok\n' \$tool; else printf 'tool-%s=missing\n' \$tool; fi
done
if command -v sha256sum >/dev/null 2>&1; then
  printf 'sha=sha256sum\n'
elif command -v shasum >/dev/null 2>&1; then
  printf 'sha=shasum\n'
elif command -v openssl >/dev/null 2>&1; then
  printf 'sha=openssl\n'
else
  printf 'sha=missing\n'
fi
if command -v sudo >/dev/null 2>&1; then printf 'sudo=present\n'; else printf 'sudo=absent\n'; fi
if [ -d $(rq "$snapshot_dir") ]; then printf 'snapshot=present\n'; else printf 'snapshot=absent\n'; fi
PROBE
)
probe_out=$(remote "$probe_script") || die_remote "cannot reach $host over ssh"
probe_field() { printf '%s\n' "$probe_out" | sed -n "s/^$1=//p" | head -1; }
remote_uid=$(probe_field uid)
[ -n "$remote_uid" ] || die_remote "host $host did not report its user id"
[ "$(probe_field tool-tar)" = ok ] || die_remote "tar is missing on $host"
[ "$(probe_field tool-find)" = ok ] || die_remote "find is missing on $host"
[ "$(probe_field sha)" != missing ] || die_remote "no sha256 tool (sha256sum, shasum, or openssl) on $host"
[ "$(probe_field live)" = present ] || die_remote "live root is missing on $host: $live_root"
live_before_count=$(probe_field live-files)
note "remote user id $remote_uid, sha256 via $(probe_field sha), $live_before_count file(s) live"
use_sudo=0
if [ "$remote_uid" != 0 ]; then
  [ "$(probe_field sudo)" = present ] || die_remote "install.sh needs root on $host and sudo is not installed"
  use_sudo=1
  note 'install.sh will run as root through sudo -n (no password is read)'
else
  note 'install.sh will run as root directly'
fi

published_checks='llms.txt:/llms.txt:text/plain landing:/:text/html support:/support.html:text/html answer:/what-is-write-it-down.html:text/html download:/download/:text/html'
http_check() { # http_check <label> <path> <expected content type prefix>
  local label=$1 path=$2 want=$3 out code type
  if ! out=$(curl -sS -o /dev/null --max-time 20 -w '%{http_code} %{content_type}' "$base_url$path" 2>"$work/curl.err"); then
    http_lines="$http_lines  $label: $base_url$path unreachable ($(tr '\n' ' ' <"$work/curl.err"))
"
    return 1
  fi
  code=${out%% *}
  type=${out#* }
  if [ "$code" != 200 ]; then
    http_lines="$http_lines  $label: $base_url$path answered $code
"
    return 1
  fi
  case "$type" in
    "$want"*) ;;
    *)
      http_lines="$http_lines  $label: $base_url$path answered $type, expected $want
"
      return 1
      ;;
  esac
  http_lines="$http_lines  $label: $base_url$path 200 $type
"
  return 0
}

step "check the published site at $base_url"
http_failures=0
for record in $published_checks; do
  label=${record%%:*}
  rest=${record#*:}
  http_check "$label" "${rest%%:*}" "${rest#*:}" || http_failures=$((http_failures + 1))
done
if [ "$http_failures" -gt 0 ] && [ "$dry_run" -eq 0 ]; then
  printf '%s' "$http_lines" >&2
  die_remote "the published site already fails $http_failures check(s); refusing to deploy over it"
fi
printf '%s' "$http_lines"
if [ "$http_failures" -gt 0 ]; then
  note "$http_failures published check(s) fail today; a deploy could not pass verification"
fi

if [ "$dry_run" -eq 1 ]; then
  step 'dry run: planned steps'
  note "would upload $(basename -- "$bundle") to $staging_dir/bundle.tar.gz"
  note "would snapshot $live_root into $snapshot_dir/$(basename -- "$live_root")-<UTC>.tar.gz"
  note "would extract the bundle into $staging_dir/tree and run install.sh as root"
  note "would verify $installed_count live hash(es) against $(basename -- "$manifest")"
  note 'would roll back from the snapshot on any mismatch'
  note 'nothing was written: dry run'
  outcome='DRY RUN - nothing changed'
  summary_and_exit 0
fi

# ---------------------------------------------------------------------------
# step 3: upload, snapshot, extract
# ---------------------------------------------------------------------------
step "upload the remote helper to $staging_dir"
printf '%s' "$REMOTE_HELPER" >"$work/wid-deploy-remote.sh"
remote "mkdir -p $(rq "$staging_dir")" || die_remote "cannot create $staging_dir on $host"
upload "$work/wid-deploy-remote.sh" "$(helper_path)" || die_remote 'cannot upload the remote helper'

step 'read the live tree before any write'
helper list "$live_root" >"$work/live.before.raw" || die_remote "cannot read the live tree on $host"
pairs_from_hash_lines "$work/live.before.raw" >"$work/live.before.pairs"

step 'upload the bundle'
upload "$bundle" "$staging_dir/bundle.tar.gz" || die_remote 'cannot upload the bundle'
uploaded_sha=$(remote "if command -v sha256sum >/dev/null 2>&1; then sha256sum -- $(rq "$staging_dir/bundle.tar.gz") | cut -d' ' -f1; else shasum -a 256 -- $(rq "$staging_dir/bundle.tar.gz") | cut -d' ' -f1; fi") \
  || die_remote 'cannot hash the uploaded bundle'
[ "$uploaded_sha" = "$bundle_sha" ] \
  || die_remote "uploaded bundle hashes to $uploaded_sha, expected $bundle_sha; the transfer was corrupt"
note "uploaded bundle sha256 $uploaded_sha"

step 'snapshot the live tree'
snapshot_path=$(helper snapshot "$live_root" "$snapshot_dir") || die_remote 'snapshot failed'
[ -n "$snapshot_path" ] || die_remote 'snapshot produced no path'
note "snapshot $snapshot_path"
upload "$work/live.before.raw" "$staging_dir/live-before.list" || die_remote 'cannot store the pre-deploy inventory'

step 'extract the bundle in staging'
helper extract "$staging_dir" || die_remote 'extract failed'
note "extracted into $staging_dir/tree"

# ---------------------------------------------------------------------------
# step 4: install
# ---------------------------------------------------------------------------
rollback() { # rollback <exit code when the restore verifies> <reason>
  local code=$1
  local reason=$2
  step 'roll back'
  printf '%s: %s\n' "$PROG" "$reason" >&2
  if ! helper restore "$snapshot_path" "$live_root" "$staging_dir/live-before.list"; then
    outcome="ROLLBACK FAILED - $reason - the live tree needs attention; snapshot $snapshot_path"
    summary_and_exit 5
  fi
  step 're-verify the restored tree'
  if ! helper list "$live_root" >"$work/live.after.raw"; then
    outcome="ROLLBACK UNVERIFIED - $reason - cannot read the live tree back; snapshot $snapshot_path"
    summary_and_exit 5
  fi
  pairs_from_hash_lines "$work/live.after.raw" >"$work/live.after.pairs"
  if diff -u "$work/live.before.pairs" "$work/live.after.pairs" >"$work/restore.diff" 2>&1; then
    note 'the restored tree matches the pre-deploy inventory file for file'
    outcome="ROLLED BACK - $reason - live tree restored from $snapshot_path"
    summary_and_exit "$code"
  fi
  printf '%s\n' 'the rollback did not reproduce the pre-deploy tree:' >&2
  cat "$work/restore.diff" >&2
  outcome="ROLLBACK MISMATCH - $reason - snapshot $snapshot_path kept; the live tree differs from the pre-deploy inventory"
  summary_and_exit 5
}

step 'install'
install_output=$(helper install "$staging_dir" "$use_sudo") \
  || rollback 3 'install.sh failed on the host'
[ -z "$install_output" ] || note "$install_output"

# ---------------------------------------------------------------------------
# step 5: verify the live tree against the manifest
# ---------------------------------------------------------------------------
step 'verify the live tree'
helper list "$live_root" >"$work/live.after.raw" || rollback 4 'cannot read the live tree after install'
pairs_from_hash_lines "$work/live.after.raw" >"$work/live.after.pairs"
mismatches=''
verified_count=0
while IFS=$'\t' read -r rel hash; do
  got=$(awk -F'\t' -v p="$rel" '$1 == p { print $2; exit }' "$work/live.after.pairs")
  if [ -z "$got" ]; then
    mismatches="$mismatches$(printf 'missing on the host: %s' "$rel")
"
  elif [ "$got" != "$hash" ]; then
    mismatches="$mismatches$(printf 'hash mismatch: %s live=%s manifest=%s' "$rel" "$got" "$hash")
"
  else
    verified_lines="$verified_lines$(printf '  %s  %s' "$hash" "$rel")
"
    verified_count=$((verified_count + 1))
  fi
done <"$work/manifest.want"
live_extras=$(LC_ALL=C comm -13 <(paths_only "$work/manifest.want") <(paths_only "$work/live.after.pairs") | wc -l | tr -d ' ')
if [ -n "$mismatches" ]; then
  printf '%s' "$mismatches" >&2
  rollback 4 "post-install verification failed: $(printf '%s' "$mismatches" | head -1)"
fi
note "$verified_count/$installed_count live hash(es) match $(basename -- "$manifest")"
if [ "$live_extras" -gt 0 ]; then
  note "$live_extras other file(s) in the live tree were left untouched"
fi

step "re-check the published site at $base_url"
http_lines=''
http_failures=0
for record in $published_checks; do
  label=${record%%:*}
  rest=${record#*:}
  http_check "$label" "${rest%%:*}" "${rest#*:}" || http_failures=$((http_failures + 1))
done
if [ "$http_failures" -gt 0 ]; then
  printf '%s' "$http_lines" >&2
  rollback 4 "$http_failures published check(s) failed after install"
fi
printf '%s' "$http_lines"

outcome="DEPLOYED - $verified_count file hash(es) verified; snapshot $snapshot_path kept as the rollback"
summary_and_exit 0
