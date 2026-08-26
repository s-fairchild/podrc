#!/usr/bin/env bash
# Shared paths/helpers sourced by the other scripts/*.sh entry points.
# Not meant to be run directly.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck disable=SC2034 # consumed by scripts that source this file
# Overridable so tests can point lint/generate at a fixture directory
# instead of this repo's real quadlet units.
QUADLET_SRC_DIR="${QUADLET_SRC_DIR:-${REPO_ROOT}/config/containers/systemd}"
# shellcheck disable=SC2034 # consumed by scripts that source this file
ENV_EXAMPLE_DIR="${REPO_ROOT}/env"

# Resolve the local quadlet binary. Overridable via QUADLET_BIN for
# non-standard installs.
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
	echo "error: quadlet binary not found (looked in /usr/libexec/podman, /usr/lib/podman)." >&2
	echo "       set QUADLET_BIN=/path/to/quadlet to override." >&2
	return 1
}

install_config_dir() {
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/containers/systemd"
}

install_env_dir() {
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/mcp-quadlets"
}
