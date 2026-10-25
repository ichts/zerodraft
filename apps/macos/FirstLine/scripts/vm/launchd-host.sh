#!/bin/bash
# [INPUT] Sourced by the host half of the recorded acceptance rig. The caller hands
#         its own program path and arguments to wid_launchd_reexec.
# [OUTPUT] Re-runs the calling script as a one-shot user launchd job, streams that
#          job's output back to the caller's terminal, and exits with the job's
#          status. The job runs with WID_VM_LAUNCHD=1 so it does not re-exec again.
# [POS] apps/macos/FirstLine/scripts/vm/launchd-host.sh - host-side transport shim
#       shared by scripts/vm-journey.sh and scripts/vm/prepare-guest.sh.
# [PROTOCOL] macOS Local Network Privacy blocks traffic to a local-network address
#            from an app that was never granted it, and an agent harness is such an
#            app. The block is not a network fault: the VM is up, its ARP entry
#            resolves, and every connection fails with EHOSTUNREACH ("No route to
#            host") while the same command from a launchd job succeeds. Rather than
#            requiring each operator to grant a harness app local network access,
#            the rig runs itself as a launchd job. WID_VM_NO_LAUNCHD=1 keeps the
#            script in the caller's process tree for hosts or callers that already
#            hold the grant. A launchd job does not inherit the caller's environment,
#            so wid_launchd_forwarded lists what the job gets: the runtime basics, the
#            rig's own WID_* configuration (including every WID_PANEL_* input), Pi's
#            process configuration, the proxy settings and every provider credential or
#            endpoint name (suffixes _API_KEY, _AUTH_TOKEN, _OAUTH_TOKEN, _BASE_URL, and
#            AWS_*). Anything not listed stays out, so the job's reviewer route is the
#            one the operator configured.
set -uo pipefail

# The names a launchd job gets exported from the caller's environment.
wid_launchd_forwarded() {
  local name
  for name in PATH HOME TMPDIR USER LOGNAME \
    HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy ALL_PROXY all_proxy \
    PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_PACKAGE_DIR PI_OFFLINE \
    PI_SKIP_VERSION_CHECK PI_TELEMETRY PI_CACHE_RETENTION PI_RADIUS_GATEWAY \
    PI_SHARE_VIEWER_URL
  do
    [[ -n "${!name+set}" ]] && printf '%s\n' "$name"
  done
  while IFS= read -r name; do
    case "$name" in
      WID_*|*_API_KEY|*_AUTH_TOKEN|*_OAUTH_TOKEN|*_BASE_URL|AWS_*) printf '%s\n' "$name" ;;
    esac
  done < <(compgen -v)
}

# wid_launchd_reexec <program> [args...]
# Returns only when the caller should keep running in its own process tree;
# otherwise it never returns and the process exits with the job's status.
wid_launchd_reexec() {
  [[ "${WID_VM_NO_LAUNCHD:-0}" == '1' || "${WID_VM_LAUNCHD:-0}" == '1' ]] && return 0
  local program="$1"
  shift
  program="$(cd "$(dirname "$program")" && pwd -P)/$(basename "$program")"
  local dir log status tramp label bytes offset code name arg
  dir="$(mktemp -d "${TMPDIR:-/tmp}/wid-launchd.XXXXXX")" || return 2
  log="$dir/run.log"
  status="$dir/run.status"
  tramp="$dir/run.sh"
  label="wid-rig-$(basename "${program%.sh}" | tr -cd '[:alnum:]-')-$$"
  : >"$log"
  {
    printf '#!/bin/bash\nset -uo pipefail\n'
    # launchctl submit keeps the job alive and starts it again after every exit, so
    # the first statement makes a relaunch a no-op. The caller removes the job as
    # soon as the status file lands.
    printf '[[ -e %q ]] && exit 0\n' "$status"
    printf 'cd %q || exit 2\n' "$(pwd -P)"
    printf 'export WID_VM_LAUNCHD=1\n'
    while IFS= read -r name; do
      [[ "$name" == 'WID_VM_LAUNCHD' ]] && continue
      printf 'export %s=%q\n' "$name" "${!name}"
    done < <(wid_launchd_forwarded)
    printf '%q' "$program"
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf ' >>%q 2>&1\n' "$log"
    printf 'printf "%%s" "$?" >%q\n' "$status"
  } >"$tramp"
  chmod +x "$tramp"
  if ! launchctl submit -l "$label" -- /bin/bash "$tramp" 2>/dev/null; then
    printf 'wid-launchd: could not submit %s; running in this process tree instead\n' "$label" >&2
    rm -rf "$dir"
    return 0
  fi
  printf 'wid-launchd: running as launchd job %s\n' "$label" >&2
  offset=0
  while [[ ! -f "$status" ]]; do
    bytes="$(stat -f %z "$log" 2>/dev/null || printf 0)"
    if [[ "${bytes:-0}" -gt "$offset" ]]; then
      tail -c "+$((offset + 1))" "$log"
      offset="$bytes"
    fi
    sleep 1
  done
  bytes="$(stat -f %z "$log" 2>/dev/null || printf 0)"
  [[ "${bytes:-0}" -gt "$offset" ]] && tail -c "+$((offset + 1))" "$log"
  launchctl remove "$label" >/dev/null 2>&1
  code="$(cat "$status" 2>/dev/null)"
  rm -rf "$dir"
  [[ "$code" =~ ^[0-9]+$ ]] || code=2
  exit "$code"
}
