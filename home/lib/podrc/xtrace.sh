#!/bin/bash
# Suspend and restore the calling shell's `set -o xtrace` state around a
# sensitive operation (e.g. one that prints or handles a secret), without
# a global variable -- the caller keeps the saved state in its own local
# and passes it back to xtrace_restore.
#
# Usage:
#   local xtrace_state
#   xtrace_state="$(xtrace_save)"
#   xtrace_off
#   ...sensitive operation...
#   xtrace_restore "$xtrace_state"

set -euo pipefail

# xtrace_save
#
# Prints "on" if the calling shell currently has xtrace enabled, "off"
# otherwise. Call this before xtrace_off/xtrace_toggle so the prior state
# can be restored later via xtrace_restore.
xtrace_save() {
  case "$-" in
    *x*) echo "on" ;;
    *) echo "off" ;;
  esac
}

# xtrace_off
#
# Disables xtrace. A no-op if it's already off.
xtrace_off() {
  set +o xtrace
}

# xtrace_toggle
#
# Flips xtrace: disables it if currently on, enables it if currently off.
xtrace_toggle() {
  case "$-" in
    *x*) set +o xtrace ;;
    *) set -o xtrace ;;
  esac
}

# xtrace_restore state
#
# Re-enables xtrace if state (as returned by a prior xtrace_save call) is
# "on"; a no-op for any other value.
xtrace_restore() {
  local -r state="${1?state=\$1 must be provided.}"

  if [[ "${state}" == "on" ]]; then
    set -o xtrace
  fi

  return 0
}
