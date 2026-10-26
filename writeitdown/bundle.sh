#!/usr/bin/env bash
# Build the deployment bundle, and the manifest deploy.sh verifies it against, from a tested tree.
# [INPUT] --tree <dir> (default: the directory holding this script), --out <dir> (default: the
#         current directory). The bundle carries exactly the production files install.sh lists plus
#         install.sh itself; other files in the tree (README, qa, tests, node_modules) are not packed.
# [OUTPUT] <out>/writeitdown-deploy.tar.gz, <out>/MANIFEST, and one line each with the bundle path,
#          its sha256, and the deployed file count. Exit 0 when both are written; 1 on a usage error,
#          a missing or symlinked production file, or an unreadable file list in install.sh.
# [POS] writeitdown/bundle.sh - the operator's packaging step before writeitdown/deploy.sh. It reads
#       the production list from install.sh, so it cannot drift from what the installer deploys.
# [PROTOCOL] MANIFEST is the contract shared with deploy.sh: a 'bundle:' line naming the tarball, a
#            'bundle-sha256:' line, and one '<sha256>  <path>' line per deployed file, path relative
#            to the live root, in the installer's own order. install.sh is deliberately absent from
#            the manifest: it runs from the staging directory and is never installed to the site.
set -euo pipefail

PROG=writeitdown-bundle
script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
tree=$script_dir
out=$PWD
bundle_name=writeitdown-deploy.tar.gz

usage() {
  cat <<'USAGE'
Usage: sh writeitdown/bundle.sh [--tree <dir>] [--out <dir>]

Builds writeitdown-deploy.tar.gz and MANIFEST from a tested tree.

  --tree <dir>  tree to pack (default: the directory holding this script)
  --out <dir>   directory for the tarball and MANIFEST (default: the current directory)
  -h, --help    show this help
USAGE
}

die_usage() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  printf 'Run %s --help for usage.\n' "$PROG" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tree) [ "$#" -ge 2 ] || die_usage 'missing value for --tree'; tree=$2; shift 2 ;;
    --out) [ "$#" -ge 2 ] || die_usage 'missing value for --out'; out=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -d "$tree" ] || die_usage "not a directory: $tree"
tree=$(cd -- "$tree" && pwd -P)
[ -f "$tree/install.sh" ] || die_usage "no install.sh in $tree"
mkdir -p -- "$out"
out=$(cd -- "$out" && pwd -P)

# install.sh is the single owner of the production file list; refuse to guess it.
files=$(sed -n "s/^FILES='\(.*\)'\$/\\1/p" "$tree/install.sh" | head -1)
[ -n "$files" ] || die_usage "cannot read the FILES='...' line from $tree/install.sh"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | cut -d' ' -f1
  else
    openssl dgst -sha256 -r -- "$1" | cut -d' ' -f1
  fi
}

tarball=$out/$bundle_name
manifest=$out/MANIFEST
rm -f -- "$tarball" "$manifest"

# Every deployed file must exist as a plain file in the tested tree.
packed=''
for rel in $files; do
  path=$tree/$rel
  [ -e "$path" ] || die_usage "production file is missing from $tree: $rel"
  [ -f "$path" ] || die_usage "production file is not a regular file: $rel"
  [ ! -L "$path" ] || die_usage "production file is a symlink: $rel"
  packed="$packed $rel"
done

# Pack in the installer's own order, through `gzip -n` so the archive carries no timestamp and the
# same tested tree always produces the same bytes.
(cd "$tree" && tar -cf - install.sh $packed) | gzip -n >"$tarball"
bundle_sha=$(sha256_of "$tarball")
count=$(printf '%s\n' $packed | wc -l | tr -d ' ')

{
  printf '# writeitdown.app deploy bundle\n'
  printf 'bundle: %s\n' "$bundle_name"
  printf 'bundle-sha256: %s\n' "$bundle_sha"
  printf '# files: %s deployed, plus install.sh from staging\n' "$count"
  for rel in $packed; do
    printf '%s  %s\n' "$(sha256_of "$tree/$rel")" "$rel"
  done
} >"$manifest"
printf 'bundle: %s\n' "$tarball"
printf 'sha256: %s\n' "$bundle_sha"
printf 'files:  %s deployed, plus install.sh\n' "$count"
