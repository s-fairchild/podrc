#!/usr/bin/env bash
# Materialize the systemd unit files quadlet would generate from
# home/config/containers/systemd/, writing them to .generated/ for
# inspection (e.g. to eyeball the resulting ExecStart before installing).
# Does not touch any real systemd search path.
#
# Usage: hack/generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# git_commit_state
#
# Prints the current commit's short SHA, with a "-dirty" suffix appended
# if the working tree isn't porcelain-clean (staged, unstaged, or
# untracked changes) -- so a dump can't be mistaken for one generated
# from a different tree state.
git_commit_state() {
    local sha
    sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"

    if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
        sha+="-dirty"
    fi

    printf '%s\n' "${sha}"
}

# dryrun_generate quadlet_bin out_dir dump_file
#
# Dry-runs QUADLET_SRC_DIR through quadlet_bin, writing the generated
# unit dump to dump_file (inside out_dir).
dryrun_generate() {
    local quadlet_bin="$1" out_dir="$2" dump_file="$3"

    rm -rf "${out_dir}"
    mkdir -p "${out_dir}"
    QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" \
        "${quadlet_bin}" -dryrun -user "${out_dir}" \
        >"${dump_file}"
}

# report_generated dump_file
#
# Logs the dump location and every generated *.service unit found in it.
report_generated() {
    local dump_file="$1"

    log_info "Generated unit dump: ${dump_file}"
    local line
    while IFS= read -r line; do
        log_info "found: ${line}"
    done < <(grep -- '---.*\.service---' "${dump_file}")
}

main() {
    init_logging

    local quadlet_bin
    quadlet_bin="$(resolve_quadlet_bin)"
    local out_dir="${REPO_ROOT}/.generated"
    local commit_state
    commit_state="$(git_commit_state)"
    local dump_file="${out_dir}/dryrun-output-${commit_state}.txt"

    dryrun_generate "${quadlet_bin}" "${out_dir}" "${dump_file}"
    report_generated "${dump_file}"
}

main "$@"
