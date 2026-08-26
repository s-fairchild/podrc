#!/usr/bin/env bash
# Install the quadlet units and env-file templates for the current user
# and register them with systemd --user. Never overwrites an existing
# env file, since those hold secrets once filled in.
#
# Usage: scripts/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

"${SCRIPT_DIR}/lint.sh"

config_dir="$(install_config_dir)"
env_dir="$(install_env_dir)"

echo "==> installing quadlet units to ${config_dir}"
mkdir -p "${config_dir}"
install -m 0644 "${QUADLET_SRC_DIR}"/*.container "${QUADLET_SRC_DIR}"/*.network "${config_dir}/"

echo "==> installing env-file templates to ${env_dir}"
mkdir -p "${env_dir}"
for example in "${ENV_EXAMPLE_DIR}"/*.env.example; do
	name="$(basename "${example}" .env.example)"
	dest="${env_dir}/${name}.env"
	if [[ -e "${dest}" ]]; then
		echo "  skip ${dest} (already exists)"
	else
		install -m 0600 "${example}" "${dest}"
		echo "  wrote ${dest} (fill in real values before starting the service)"
	fi
done

echo "==> systemctl --user daemon-reload"
systemctl --user daemon-reload

echo "==> enabling units (not starting -- fill in env files and TODOs first)"
systemctl --user enable mcp-github.service mcp-kubernetes.service

cat <<EOF

Next steps:
  1. Edit ${env_dir}/*.env with real credentials.
  2. Resolve the TODO(verify) notes in ${config_dir}/mcp-github.container
     and mcp-kubernetes.container (transport flags, kubernetes image).
  3. systemctl --user start mcp-github.service mcp-kubernetes.service
  4. So these keep running after you log out, and start again on boot:
     loginctl enable-linger "\$USER"
EOF
