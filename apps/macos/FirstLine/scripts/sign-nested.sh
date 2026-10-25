#!/usr/bin/env bash
# [INPUT] <app> <identity>; identity '-' means ad-hoc, any other value is a Developer ID
#         identity in the login keychain.
# [OUTPUT] An inside-out signed bundle: every plain Mach-O executable first, then nested
#          frameworks/apps/XPC services deepest-first, then the app itself; exit 0 only when
#          `codesign --verify --deep --strict` passes, and for a Developer ID identity only
#          when every executable inside carries the app's TeamIdentifier.
# [POS] apps/macos/FirstLine/scripts/sign-nested.sh - the one signing loop shared by
#       package-app.sh (ad-hoc QA builds) and release-dmg.sh (Developer ID releases).
# [PROTOCOL] Sparkle ships `Sparkle.framework/Versions/B/Autoupdate` as a plain Mach-O file,
#            not a bundle. The old loop only matched *.framework/*.app/*.xpc, so Autoupdate
#            stayed ad-hoc signed (Sparkle's distribution signature) and notarization rejected
#            the app. Plain executables are therefore signed before the bundles that seal them.
set -euo pipefail

if (( $# != 2 )); then
  echo 'Usage: scripts/sign-nested.sh <app> <identity|->' >&2
  exit 2
fi
app="$1"
identity="$2"
if [[ ! -d "$app" || -z "$identity" ]]; then
  echo 'Usage: scripts/sign-nested.sh <app> <identity|->' >&2
  exit 2
fi

if [[ "$identity" == '-' ]]; then
  flags=(--force --sign -)
else
  flags=(--force --options runtime --timestamp --sign "$identity")
fi

# Commands are captured before grepping: under `pipefail`, a `grep -q` that exits on its first
# match sends SIGPIPE back to codesign/file and turns a match into a pipeline failure.
is_mach_o() {
  local kind
  kind="$(file -b "$1")"
  [[ "$kind" == *Mach-O* ]]
}

signature_info() {
  codesign -dvv "$1" 2>&1 || true
}

mach_o_executables() {
  find "$app" -type f -perm -u+x -print0
}

# 1) Plain executables (Autoupdate and any other helper) get their own signature; the
#    enclosing bundles are re-sealed over them in step 2.
while IFS= read -r -d '' executable; do
  is_mach_o "$executable" || continue
  codesign "${flags[@]}" "$executable"
done < <(mach_o_executables)

# 2) Nested code bundles, leaf-to-root, so each parent seals a stable child.
while IFS= read -r -d '' nested; do
  codesign "${flags[@]}" "$nested"
done < <(find "$app/Contents" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0 \
           | sort -rz --zero-terminated)

# 3) The outer bundle.
codesign "${flags[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

# 4) Release gate: notarization rejects a single ad-hoc or foreign-signed executable, and that
#    failure only surfaces after the long notarytool wait. Prove the team here instead.
if [[ "$identity" != '-' ]]; then
  app_info="$(signature_info "$app")"
  team="$(sed -n 's/^TeamIdentifier=//p' <<<"$app_info" | head -n 1)"
  if [[ -z "$team" || "$team" == 'not set' ]]; then
    echo 'The signed app carries no TeamIdentifier; use a Developer ID Application identity.' >&2
    exit 1
  fi
  while IFS= read -r -d '' executable; do
    is_mach_o "$executable" || continue
    if ! grep -qx "TeamIdentifier=$team" <<<"$(signature_info "$executable")"; then
      echo "Unsigned or foreign-signed executable: $executable" >&2
      exit 1
    fi
  done < <(mach_o_executables)
fi
