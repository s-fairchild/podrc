#!/usr/bin/env bash
# Shared paths/helpers sourced by the other hack/*.sh entry points.
# Not meant to be run directly.

set -euo pipefail

# Globals (readonly, set once at source time):
#   SCRIPT_DIR      - absolute path to hack/, used to locate sibling files
#   REPO_ROOT       - absolute path to the repo root
#   QUADLET_SRC_DIR - quadlet units to lint/generate/install; overridable via
#                     env var so tests can point it at a fixture directory
#                     instead of home/config/containers/systemd
#   QUADLET_UNIT_SUFFIXES - quadlet unit file extensions this repo installs/
#                     removes/inspects, e.g. mcp-kubernetes.container or
#                     mcp.network
#   ENV_EXAMPLE_DIR - env/config-file templates (*.example) copied by
#                     install.sh, e.g. mcp-kubernetes.env.example or
#                     mcp-kubernetes.toml.example
#   MCP_QUADLETS_CONFIG_DIR - home/config/mcp-quadlets/, a literal mirror of
#                     $XDG_CONFIG_HOME/mcp-quadlets/ (like QUADLET_SRC_DIR
#                     is for containers/systemd/) holding real,
#                     git-ignored files the user edits directly in their
#                     checkout -- e.g. etc/mcp-kubernetes-server/conf.d/
#                     drop-in *.toml files. install.sh mirrors it in
#                     whole on every install; see its
#                     install_local_config(). Overridable via env var so
#                     tests can point it at a fixture directory.
#   HOME_BIN_SRC_DIR - home/bin/, installable scripts install-local.sh
#                     copies into ~/.local/bin (mode 0744). Overridable via
#                     env var so tests can point it at a fixture directory.
#   HOME_LIB_SRC_DIR - home/lib/, library files (sourced by home/bin/
#                     scripts, never executed directly) install-local.sh
#                     copies into ~/.local/lib/mcp-quadlets (mode 0644).
#                     Overridable via env var so tests can point it at a
#                     fixture directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly REPO_ROOT
QUADLET_SRC_DIR="${QUADLET_SRC_DIR:-${REPO_ROOT}/home/config/containers/systemd}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly QUADLET_SRC_DIR
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly QUADLET_UNIT_SUFFIXES=(
  container
  volume
  network
  kube
  image
  build
  pod
  artifact
)
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly ENV_EXAMPLE_DIR="${REPO_ROOT}/env"
MCP_QUADLETS_CONFIG_DIR="${MCP_QUADLETS_CONFIG_DIR:-${REPO_ROOT}/home/config/mcp-quadlets}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly MCP_QUADLETS_CONFIG_DIR
HOME_BIN_SRC_DIR="${HOME_BIN_SRC_DIR:-${REPO_ROOT}/home/bin}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly HOME_BIN_SRC_DIR
HOME_LIB_SRC_DIR="${HOME_LIB_SRC_DIR:-${REPO_ROOT}/home/lib}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly HOME_LIB_SRC_DIR

# init_logging
#
# Sources the vendored bash-logger module (if not already loaded) and
# initializes it under this process's script name, exposing log_debug/
# log_info/log_warn/log_error/... to the caller. Call as the first step
# of every entry point's main().
#
# init_logger's own option-parsing loop uses a bare `((i++))`, which is
# falsy (and so fatal under `set -e`) on its first iteration even though
# init_logger itself returns 0 -- shield the call and restore the
# caller's errexit state afterwards.
init_logging() {
  if ! declare -f init_logger >/dev/null 2>&1; then
    local logger_entry="${REPO_ROOT}/vendor/bash-logger/logging.sh"
    if [[ ! -f "${logger_entry}" ]]; then
      local msg="error: ${logger_entry} not found. "
      msg+="Run: git submodule update --init --recursive"
      echo "${msg}" >&2
      return 1
    fi
    # shellcheck source=../vendor/bash-logger/logging.sh
    source "${logger_entry}"
  fi

  local errexit_was_set=0
  [[ $- == *e* ]] && errexit_was_set=1

  set +e

  init_logger --name "$(basename "$0")"

  (( errexit_was_set )) && set -e

  return 0
}

# resolve_quadlet_bin
#
# Prints the path to the local quadlet binary. Overridable via QUADLET_BIN
# for non-standard installs.
resolve_quadlet_bin() {
  if [[ -n "${QUADLET_BIN:-}" ]]; then
    echo "${QUADLET_BIN}"
    return 0
  fi

  local candidate

  for candidate in /usr/libexec/podman/quadlet /usr/lib/podman/quadlet; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  log_error "quadlet binary not found" \
    "(looked in /usr/libexec/podman, /usr/lib/podman)."
  log_error "set QUADLET_BIN=/path/to/quadlet to override."

  return 1
}

install_config_dir() {
  echo "${XDG_CONFIG_HOME:-${HOME}/.config}/containers/systemd"
}

install_env_dir() {
  echo "${XDG_CONFIG_HOME:-${HOME}/.config}/mcp-quadlets"
}

install_bin_dir() {
  echo "${HOME}/.local/bin"
}

install_lib_dir() {
  echo "${HOME}/.local/lib/mcp-quadlets"
}

# list_quadlet_units
#
# Prints the path to every quadlet unit file (one per QUADLET_UNIT_SUFFIXES
# entry, e.g. *.container, *.network, *.image) present in QUADLET_SRC_DIR,
# one per line. install.sh/uninstall.sh derive what to install/remove from
# this instead of a hardcoded file list.
list_quadlet_units() {
  local suffix
  local -a matches
  shopt -s nullglob
  for suffix in "${QUADLET_UNIT_SUFFIXES[@]}"; do
    matches=("${QUADLET_SRC_DIR}"/*."${suffix}")
    (( ${#matches[@]} > 0 )) && printf '%s\n' "${matches[@]}"
  done
  shopt -u nullglob
}

# container_service_names
#
# Prints the systemd service name Quadlet generates for each *.container
# unit in QUADLET_SRC_DIR (mcp-github.container -> mcp-github.service),
# one per line. install.sh/uninstall.sh derive which services to
# start/stop from this instead of a hardcoded mcp-*.service list.
container_service_names() {
  local unit
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.container; do
    printf '%s.service\n' "$(basename "${unit}" .container)"
  done
  shopt -u nullglob
}

# network_service_names
#
# Prints the systemd service name Quadlet generates for each *.network
# unit in QUADLET_SRC_DIR (mcp.network -> mcp-network.service), one per
# line. uninstall.sh stops these directly (rather than calling `podman
# network rm`) so that NetworkDeleteOnStop=true on the unit handles
# actually removing the podman network.
network_service_names() {
  local unit
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.network; do
    printf '%s-network.service\n' "$(basename "${unit}" .network)"
  done
  shopt -u nullglob
}

# quadlet_unit_value unit_file key
#
# Prints the value of the first "key=value" line found in unit_file
# (e.g. key=ContainerName), or nothing if key isn't set.
quadlet_unit_value() {
  local unit_file="$1" key="$2"

  awk -F= -v k="${key}" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' \
    "${unit_file}"
}

# resolve_unit_specifiers value unit_file
#
# Expands the %N systemd specifier (the unit's own name, sans type
# suffix) in value. The units in this repo only rely on %N; extend this
# if a future unit needs another specifier (%h, %n, ...).
resolve_unit_specifiers() {
  local value="$1" unit_file="$2"
  local base
  base="$(basename "${unit_file}")"
  base="${base%.*}"

  printf '%s\n' "${value//%N/${base}}"
}

# quadlet_container_names
#
# Prints the podman container name Quadlet creates for each *.container
# unit in QUADLET_SRC_DIR, one per line: ContainerName= (with %N
# resolved) when set, otherwise the unit's own basename -- Quadlet's
# default when ContainerName= is absent.
quadlet_container_names() {
  local unit name
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.container; do
    name="$(quadlet_unit_value "${unit}" ContainerName)"
    if [[ -n "${name}" ]]; then
      name="$(resolve_unit_specifiers "${name}" "${unit}")"
    else
      name="$(basename "${unit}" .container)"
    fi
    printf '%s\n' "${name}"
  done
  shopt -u nullglob
}

# quadlet_network_names
#
# Prints the podman network name Quadlet creates for each *.network unit
# in QUADLET_SRC_DIR, one per line: NetworkName= (with %N resolved) when
# set, otherwise the unit's own basename.
quadlet_network_names() {
  local unit name
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.network; do
    name="$(quadlet_unit_value "${unit}" NetworkName)"
    if [[ -n "${name}" ]]; then
      name="$(resolve_unit_specifiers "${name}" "${unit}")"
    else
      name="$(basename "${unit}" .network)"
    fi
    printf '%s\n' "${name}"
  done
  shopt -u nullglob
}
