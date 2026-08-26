#!/usr/bin/env bash
# Shared paths/helpers sourced by the other scripts/*.sh entry points.
# Not meant to be run directly.

set -euo pipefail

# Globals (readonly, set once at source time):
#   SCRIPT_DIR      - absolute path to scripts/, used to locate sibling files
#   REPO_ROOT       - absolute path to the repo root
#   QUADLET_SRC_DIR - quadlet units to lint/generate/install; overridable via
#                     env var so tests can point it at a fixture directory
#                     instead of config/containers/systemd
#   ENV_EXAMPLE_DIR - env-file templates copied by install.sh
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly REPO_ROOT
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly QUADLET_SRC_DIR="${QUADLET_SRC_DIR:-${REPO_ROOT}/config/containers/systemd}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
readonly ENV_EXAMPLE_DIR="${REPO_ROOT}/env"

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
			echo "error: ${logger_entry} not found. Run: git submodule update --init --recursive" >&2
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

	log_error "quadlet binary not found (looked in /usr/libexec/podman, /usr/lib/podman)."
	log_error "set QUADLET_BIN=/path/to/quadlet to override."

	return 1
}

install_config_dir() {
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/containers/systemd"
}

install_env_dir() {
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/mcp-quadlets"
}
