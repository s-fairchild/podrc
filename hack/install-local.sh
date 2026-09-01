#!/usr/bin/env bash
# Install home/bin/* into ~/.local/bin (mode 0744, executable) and
# home/lib/* into ~/.local/lib/mcpod (mode 0644, not executable --
# these are library files meant to be sourced by home/bin/ scripts, never
# run directly). Separate from install.sh/`make install` since neither
# destination is systemd-managed. Always overwrites: these are the repo's
# own deliverable scripts, not user-editable data, so a reinstall should
# always pick up the checked-in version.
#
# Usage: hack/install-local.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# install_tree src_dir dest_dir mode label
#
# Installs every non-hidden file directly under src_dir (no recursion) into
# dest_dir at the given mode, creating dest_dir if needed. Hidden files
# (e.g. .gitkeep) are repo bookkeeping only and are skipped. Logs a warning
# instead of failing if src_dir has nothing to install yet.
install_tree() {
    local src_dir="$1" dest_dir="$2" mode="$3" label="$4"

    local -a files=()
    shopt -s nullglob
    files=("${src_dir}"/*)
    shopt -u nullglob

    local -a to_install=()
    local f
    for f in "${files[@]}"; do
        [[ -f "${f}" && "$(basename "${f}")" != .* ]] && to_install+=("${f}")
    done

    if (( ${#to_install[@]} == 0 )); then
        log_warn "no ${label} files found in ${src_dir}; nothing to install"
        return 0
    fi

    log_info "installing ${label} files to ${dest_dir} (mode ${mode})"
    mkdir -p "${dest_dir}"
    install -m "${mode}" "${to_install[@]}" "${dest_dir}/"
}

main() {
    init_logging

    local bin_dir
    bin_dir="$(install_bin_dir)"
    local lib_dir
    lib_dir="$(install_lib_dir)"

    install_tree "${HOME_BIN_SRC_DIR}" "${bin_dir}" 0744 bin
    install_tree "${HOME_LIB_SRC_DIR}" "${lib_dir}" 0644 lib

    log_info "done. Make sure ${bin_dir} is on your PATH."
}

main "$@"
