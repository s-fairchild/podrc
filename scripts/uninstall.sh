#!/usr/bin/env bash
# Stop and remove the installed quadlet units. Leaves env files (secrets)
# in place unless --purge is given.
#
# Usage: scripts/uninstall.sh [--purge]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

purge=0
if [[ "${1:-}" == "--purge" ]]; then
	purge=1
fi

config_dir="$(install_config_dir)"
env_dir="$(install_env_dir)"

echo "==> stopping and disabling units (ignoring errors if not installed)"
systemctl --user disable --now mcp-github.service mcp-kubernetes.service 2>/dev/null || true

echo "==> removing quadlet units from ${config_dir}"
rm -f "${config_dir}/mcp-github.container" "${config_dir}/mcp-kubernetes.container" "${config_dir}/mcp.network"

if [[ "${purge}" -eq 1 ]]; then
	echo "==> --purge: removing env files (secrets) from ${env_dir}"
	rm -rf "${env_dir}"
fi

echo "==> systemctl --user daemon-reload"
systemctl --user daemon-reload
