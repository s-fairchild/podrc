#!/usr/bin/env bash
# Validate every quadlet file under home/config/containers/systemd/
# without touching any real systemd search path, by pointing the local
# quadlet binary's dry-run mode at this repo via QUADLET_UNIT_DIRS.
#
# Usage: hack/lint.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# run_shellcheck
#
# Runs shellcheck over hack/*.sh, home/bin/*.sh, and home/lib/*.sh (the
# latter two if any exist yet) if available; warns and skips otherwise.
run_shellcheck() {
    log_info "shellcheck hack/*.sh home/bin/*.sh home/lib/*.sh"

    if ! command -v shellcheck >/dev/null 2>&1; then
        log_fatal "failed to lint shell scripts: shellcheck not installed."
        return
    fi

    local -a targets=("${SCRIPT_DIR}"/*.sh)
    shopt -s nullglob
    targets+=("${HOME_BIN_SRC_DIR}"/*.sh "${HOME_LIB_SRC_DIR}"/*.sh)
    shopt -u nullglob

    shellcheck -x "${targets[@]}"
}

# dryrun_quadlets quadlet_bin out_dir
#
# Dry-runs every unit under QUADLET_SRC_DIR through quadlet_bin, writing
# its throwaway output to out_dir. Exits with quadlet's status on failure.
dryrun_quadlets() {
    local quadlet_bin="$1" out_dir="$2"

    log_info "${quadlet_bin} -dryrun -user (source: ${QUADLET_SRC_DIR})"
    if QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" \
        "${quadlet_bin}" -dryrun -user "${out_dir}"; then
        log_info "OK: all quadlet units parsed cleanly"
    else
        local status=$?
        log_error "quadlet reported errors parsing units under ${QUADLET_SRC_DIR}"
        exit "${status}"
    fi
}

main() {
    init_logging

    local quadlet_bin
    quadlet_bin="$(resolve_quadlet_bin)"
    local out_dir
    out_dir="$(mktemp -d)"
    # out_dir is local to main(), but the EXIT trap fires after main()
    # returns (once the whole script exits), so the path is embedded into
    # the trap command directly (intentionally expanded now) rather than
    # referenced as a variable that would already be out of scope.
    # shellcheck disable=SC2064
    trap "rm -rf -- '${out_dir}'" EXIT

    run_shellcheck
    dryrun_quadlets "${quadlet_bin}" "${out_dir}"
}

main "$@"
