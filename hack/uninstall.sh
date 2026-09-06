#!/usr/bin/env bash
# Stop and remove the installed quadlet units. Leaves env files (secrets)
# and podman volumes/secrets in place unless --purge is given, which also
# removes podman containers and networks created from this repo's units.
#
# Usage: hack/uninstall.sh [--purge]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

#######################################
# Disables and stops every mcp-*.service Quadlet generates from this
# repo's *.container units, ignoring errors if not installed.
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes status to the log.
#######################################
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

#######################################
# Removes every installed quadlet unit file (mirrors install.sh's
# install_units) from config_dir.
# Arguments:
#   config_dir: directory to remove installed unit files from
# Outputs:
#   Writes status to the log.
#######################################
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

#######################################
# Removes podman containers (running or stopped) created from this
# repo's quadlet units. Leaves volumes and secrets untouched -- those can
# hold data/credentials the user wants to keep across a purge. Networks
# are handled separately by stop_network_units, since Quadlet deletes
# them itself on stop rather than needing a manual `podman network rm`.
# Outputs:
#   Writes status to the log.
#######################################
purge_podman_resources() {
  local -a containers=()
  mapfile -t containers < <(quadlet_container_names)
  if (( ${#containers[@]} > 0 )); then
    log_info "--purge: removing podman containers: ${containers[*]}"
    podman rm --force "${containers[@]}" >/dev/null 2>&1 || true
  fi
}

#######################################
# Stops the systemd service(s) Quadlet generates from this repo's
# *.network units, once every container service depending on them is
# already stopped (see stop_units). Each unit sets
# NetworkDeleteOnStop=true, so stopping it also deletes the underlying
# podman network -- no manual `podman network rm` needed, and no stale
# "active" service left behind that would otherwise need a restart after
# the next `make install` recreates the network.
# Outputs:
#   Writes status to the log.
#######################################
stop_network_units() {
  local -a services=()
  mapfile -t services < <(network_service_names)

  if (( ${#services[@]} == 0 )); then
    return 0
  fi

  log_info "--purge: stopping network units (deletes the podman network): ${services[*]}"
  systemctl --user stop "${services[@]}" 2>/dev/null || true
}

#######################################
# Deletes env_dir entirely (secrets included).
# Arguments:
#   env_dir: directory to remove
# Outputs:
#   Writes status to the log.
#######################################
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
    stop_network_units
    purge_env "${env_dir}"
  fi

  log_info "systemctl --user daemon-reload"
  systemctl --user daemon-reload
}

main "$@"
