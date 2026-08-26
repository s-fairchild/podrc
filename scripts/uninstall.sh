#!/usr/bin/env bash
# Stop and remove the installed quadlet units. Leaves env files (secrets)
# in place unless --purge is given.
#
# Usage: scripts/uninstall.sh [--purge]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# stop_units
#
# Disables and stops both MCP services, ignoring errors if not installed.
stop_units() {
    log_info "stopping and disabling units (ignoring errors if not installed)"
    systemctl --user disable --now mcp-github.service mcp-kubernetes.service 2>/dev/null || true
}

# remove_units config_dir
#
# Removes the installed quadlet unit files from config_dir.
remove_units() {
    local config_dir="$1"

    log_info "removing quadlet units from ${config_dir}"
    rm -f "${config_dir}/mcp-github.container" "${config_dir}/mcp-kubernetes.container" "${config_dir}/mcp.network"
}

# purge_env env_dir
#
# Deletes env_dir entirely (secrets included).
purge_env() {
    local env_dir="$1"

    log_info "--purge: removing env files (secrets) from ${env_dir}"
    rm -rf "${env_dir}"
}

main() {
    init_logging

    local purge=0
    if [[ "${1:-}" == "--purge" ]]; then
        purge=1
    fi

    local config_dir
    config_dir="$(install_config_dir)"
    local env_dir
    env_dir="$(install_env_dir)"

    stop_units
    remove_units "${config_dir}"

    if [[ "${purge}" -eq 1 ]]; then
        purge_env "${env_dir}"
    fi

    log_info "systemctl --user daemon-reload"
    systemctl --user daemon-reload
}

main "$@"
