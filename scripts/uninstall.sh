#!/usr/bin/env bash
# Stop and remove the installed quadlet units. Leaves env files (secrets)
# and podman volumes/secrets in place unless --purge is given, which also
# removes podman containers and networks created from this repo's units.
#
# Usage: scripts/uninstall.sh [--purge]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# stop_units
#
# Disables and stops every mcp-*.service Quadlet generates from this
# repo's *.container units, ignoring errors if not installed.
stop_units() {
  local -a services=()
  mapfile -t services < <(container_service_names)

  if (( ${#services[@]} == 0 )); then
    log_warn "no *.container units found in ${QUADLET_SRC_DIR}; nothing to stop"
    return 0
  fi

  log_info "stopping and disabling units (ignoring errors if not installed)"
  systemctl --user \
    disable \
    --now \
    "${services[@]}" \
    2>/dev/null || true
}

# remove_units config_dir
#
# Removes every installed quadlet unit file (mirrors install.sh's
# install_units) from config_dir.
remove_units() {
  local config_dir="$1"

  log_info "removing quadlet units from ${config_dir}"

  local -a units=()
  mapfile -t units < <(list_quadlet_units)

  local unit
  for unit in "${units[@]}"; do
    rm -f "${config_dir}/$(basename "${unit}")"
  done
}

# purge_podman_resources
#
# Removes podman containers (running or stopped) and networks created
# from this repo's quadlet units. Leaves volumes and secrets untouched --
# those can hold data/credentials the user wants to keep across a purge.
purge_podman_resources() {
  local -a containers=()
  mapfile -t containers < <(quadlet_container_names)
  if (( ${#containers[@]} > 0 )); then
    log_info "--purge: removing podman containers: ${containers[*]}"
    podman rm --force "${containers[@]}" >/dev/null 2>&1 || true
  fi

  local -a networks=()
  mapfile -t networks < <(quadlet_network_names)
  if (( ${#networks[@]} > 0 )); then
    log_info "--purge: removing podman networks: ${networks[*]}"
    podman network rm "${networks[@]}" >/dev/null 2>&1 || true
  fi
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

  if (( purge )); then
    purge_podman_resources
    purge_env "${env_dir}"
  fi

  log_info "systemctl --user daemon-reload"
  systemctl --user daemon-reload
}

main "$@"
