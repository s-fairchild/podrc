#!/usr/bin/env bash
# Materialize the systemd unit files quadlet would generate from
# config/containers/systemd/, writing them to .generated/ for inspection
# (e.g. to eyeball the resulting ExecStart before installing). Does not
# touch any real systemd search path.
#
# Usage: scripts/generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# dryrun_generate quadlet_bin out_dir
#
# Dry-runs QUADLET_SRC_DIR through quadlet_bin, writing the generated
# unit dump to out_dir/dryrun-output.txt.
dryrun_generate() {
    local quadlet_bin="$1" out_dir="$2"

    rm -rf "${out_dir}"
    mkdir -p "${out_dir}"
    QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" "${quadlet_bin}" -dryrun -user "${out_dir}" >"${out_dir}/dryrun-output.txt"
}

# report_generated out_dir
#
# Logs the dump location and every generated *.service unit found in it.
report_generated() {
    local out_dir="$1"

    log_info "Generated unit dump: ${out_dir}/dryrun-output.txt"
    local line
    while IFS= read -r line; do
        log_info "found: ${line}"
    done < <(grep -- '---.*\.service---' "${out_dir}/dryrun-output.txt")
}

main() {
    init_logging

    local quadlet_bin
    quadlet_bin="$(resolve_quadlet_bin)"
    local out_dir="${REPO_ROOT}/.generated"

    dryrun_generate "${quadlet_bin}" "${out_dir}"
    report_generated "${out_dir}"
}

main "$@"
