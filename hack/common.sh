#!/bin/bash
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
#                     removes/inspects, e.g. kubernetes-mcp.container or
#                     k3d.network
#   ENV_EXAMPLE_DIR - env/config-file templates (*.example) copied by
#                     install.sh, recursively and preserving relative
#                     directory structure, e.g. kubernetes-mcp.env.example
#                     or etc/kubernetes-mcp-server/conf.d/00-base.toml.example
#                     -- excluding ENVIRONMENT_D_EXAMPLE_DIR, which is
#                     installed separately (see below)
#   ENVIRONMENT_D_EXAMPLE_DIR - env/environment.d/*.example templates
#                     copied by install-session-env.sh into
#                     $XDG_CONFIG_HOME/environment.d/, e.g. podrc.conf.example
#                     -- separate from ENV_EXAMPLE_DIR because these land in
#                     environment.d/, not podrc/, and are read by
#                     systemd --user's environment.d generator, not
#                     EnvironmentFile=
#   HOME_BIN_SRC_DIR - home/bin/, installable scripts install-local.sh
#                     copies into ~/.local/bin (mode 0744). Overridable via
#                     env var so tests can point it at a fixture directory.
#   HOME_LIB_SRC_DIR - home/lib/podrc/, library files (sourced by home/bin/
#                     scripts, never executed directly) install-local.sh
#                     copies into ~/.local/lib/podrc (mode 0644). The
#                     podrc/ subdirectory under home/lib/ mirrors the
#                     ~/.local/lib/podrc destination 1:1, same as
#                     home/config/ and home/bin/ mirror theirs.
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
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly ENVIRONMENT_D_EXAMPLE_DIR="${REPO_ROOT}/env/environment.d"
HOME_BIN_SRC_DIR="${HOME_BIN_SRC_DIR:-${REPO_ROOT}/home/bin}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly HOME_BIN_SRC_DIR
HOME_LIB_SRC_DIR="${HOME_LIB_SRC_DIR:-${REPO_ROOT}/home/lib/podrc}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly HOME_LIB_SRC_DIR

#######################################
# Sources the vendored bash-logger module (if not already loaded) and
# initializes it under this process's script name, exposing log_debug/
# log_info/log_warn/log_error/... to the caller. Call as the first step
# of every entry point's main().
#
# init_logger's own option-parsing loop uses a bare `((i++))`, which is
# falsy (and so fatal under `set -e`) on its first iteration even though
# init_logger itself returns 0 -- shield the call and restore the
# caller's errexit state afterwards.
# Globals:
#   REPO_ROOT
# Outputs:
#   Writes an error to stderr if the vendored bash-logger submodule is
#   missing.
# Returns:
#   1 if the vendored bash-logger submodule isn't present, 0 otherwise.
#######################################
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
    . "${logger_entry}"
  fi

  local -a init_logger_options=("--name" "$(basename "$0")")
  local logger_dev_config="${REPO_ROOT}/hack/etc/bash-logger/logging-dev.conf"
  [[ -f "${logger_dev_config}" ]] && init_logger_options+=("--config" "${logger_dev_config}")
  readonly init_logger_options

  local errexit_was_set=0
  [[ $- == *e* ]] && errexit_was_set=1

  set +e

  # shellcheck disable=SC2068
  init_logger ${init_logger_options[@]}

  (( errexit_was_set )) && set -e

  return 0
}

#######################################
# Prints the path to the local quadlet binary. Overridable via QUADLET_BIN
# for non-standard installs.
# Globals:
#   QUADLET_BIN
# Outputs:
#   Writes the resolved quadlet binary path to stdout, or an error to the
#   log if none is found.
# Returns:
#   1 if no quadlet binary is found.
#######################################
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

#######################################
# Prints the systemd --user config dir quadlet units install to.
# Outputs:
#   Writes the resolved path to stdout.
#######################################
install_config_dir() {
  echo "${XDG_CONFIG_HOME:-${HOME}/.config}/containers/systemd"
}

#######################################
# Prints the dir env/*.example templates install to.
# Outputs:
#   Writes the resolved path to stdout.
#######################################
install_env_dir() {
  echo "${XDG_CONFIG_HOME:-${HOME}/.config}/podrc"
}

#######################################
# Prints the dir env/environment.d/*.example templates install to.
# Outputs:
#   Writes the resolved path to stdout.
#######################################
install_environment_d_dir() {
  echo "${XDG_CONFIG_HOME:-${HOME}/.config}/environment.d"
}

#######################################
# Prints the dir home/bin/* scripts install to.
# Outputs:
#   Writes the resolved path to stdout.
#######################################
install_bin_dir() {
  echo "${HOME}/.local/bin"
}

#######################################
# Prints the dir home/lib/podrc/* files install to.
# Outputs:
#   Writes the resolved path to stdout.
#######################################
install_lib_dir() {
  echo "${HOME}/.local/lib/podrc"
}

#######################################
# Prints the path to every non-hidden regular file directly under dir (no
# recursion), one per line, or nothing if dir doesn't exist or has none.
# Used to discover home/bin/*, home/lib/* installables/lint targets
# without assuming a file extension -- home/bin/* deliberately have none.
# Arguments:
#   dir: directory to list
# Outputs:
#   Writes each matching file's path to stdout, one per line.
#######################################
list_dir_files() {
  local dir="$1"

  local -a entries=()
  shopt -s nullglob
  entries=("${dir}"/*)
  shopt -u nullglob

  local f
  for f in "${entries[@]}"; do
    [[ -f "${f}" && "$(basename "${f}")" != .* ]] && printf '%s\n' "${f}"
  done
}

#######################################
# Prints the path to every quadlet unit file (one per QUADLET_UNIT_SUFFIXES
# entry, e.g. *.container, *.network, *.image) present in QUADLET_SRC_DIR,
# one per line. install.sh/uninstall.sh derive what to install/remove from
# this instead of a hardcoded file list.
# Globals:
#   QUADLET_SRC_DIR
#   QUADLET_UNIT_SUFFIXES
# Outputs:
#   Writes each matching unit file's path to stdout, one per line.
#######################################
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

#######################################
# Prints the systemd service name Quadlet generates for each *.container
# unit in QUADLET_SRC_DIR (kubernetes-mcp.container -> kubernetes-mcp.service),
# one per line. install.sh/uninstall.sh derive which services to
# start/stop from this instead of a hardcoded mcp-*.service list.
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes each service name to stdout, one per line.
#######################################
container_service_names() {
  local unit
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.container; do
    printf '%s.service\n' "$(basename "${unit}" .container)"
  done
  shopt -u nullglob
}

#######################################
# Prints the systemd service name Quadlet generates for each *.network
# unit in QUADLET_SRC_DIR (k3d.network -> k3d-network.service), one per
# line. uninstall.sh stops these directly (rather than calling `podman
# network rm`) so that NetworkDeleteOnStop=true on the unit handles
# actually removing the podman network.
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes each service name to stdout, one per line.
#######################################
network_service_names() {
  local unit
  shopt -s nullglob
  for unit in "${QUADLET_SRC_DIR}"/*.network; do
    printf '%s-network.service\n' "$(basename "${unit}" .network)"
  done
  shopt -u nullglob
}

#######################################
# Prints the value of the first "key=value" line found in unit_file
# (e.g. key=ContainerName), or nothing if key isn't set.
# Arguments:
#   unit_file: quadlet unit file to read
#   key: the key to look up
# Outputs:
#   Writes the value to stdout, or nothing if key isn't set.
#######################################
quadlet_unit_value() {
  local unit_file="$1" key="$2"

  awk -F= -v k="${key}" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' \
    "${unit_file}"
}

#######################################
# Expands the %N systemd specifier (the unit's own name, sans type
# suffix) in value. The units in this repo only rely on %N; extend this
# if a future unit needs another specifier (%h, %n, ...).
# Arguments:
#   value: string to expand %N in
#   unit_file: unit file whose basename (sans suffix) becomes %N
# Outputs:
#   Writes the expanded value to stdout.
#######################################
resolve_unit_specifiers() {
  local value="$1" unit_file="$2"
  local base
  base="$(basename "${unit_file}")"
  base="${base%.*}"

  printf '%s\n' "${value//%N/${base}}"
}

#######################################
# Prints the podman container name Quadlet creates for each *.container
# unit in QUADLET_SRC_DIR, one per line: ContainerName= (with %N
# resolved) when set, otherwise the unit's own basename -- Quadlet's
# default when ContainerName= is absent.
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes each container name to stdout, one per line.
#######################################
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

#######################################
# Prints the podman network name Quadlet creates for each *.network unit
# in QUADLET_SRC_DIR, one per line: NetworkName= (with %N resolved) when
# set, otherwise the unit's own basename.
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes each network name to stdout, one per line.
#######################################
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
