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

# install_units config_dir
#
# Copies quadlet *.container/*.network units from QUADLET_SRC_DIR into
# config_dir.
install_units() {
	local config_dir="$1"

	log_info "installing quadlet units to ${config_dir}"
	mkdir -p "${config_dir}"
	install -m 0644 "${QUADLET_SRC_DIR}"/*.container "${QUADLET_SRC_DIR}"/*.network "${config_dir}/"
}

# install_env_templates env_dir
#
# Copies each env/*.env.example template into env_dir as <name>.env,
# skipping any destination that already exists so a reinstall never
# clobbers a filled-in secret.
install_env_templates() {
	local env_dir="$1"

	log_info "installing env-file templates to ${env_dir}"
	mkdir -p "${env_dir}"
	local example name dest
	for example in "${ENV_EXAMPLE_DIR}"/*.env.example; do
		name="$(basename "${example}" .env.example)"
		dest="${env_dir}/${name}.env"
		if [[ -e "${dest}" ]]; then
			log_info "skip ${dest} (already exists)"
		else
			install -m 0600 "${example}" "${dest}"
			log_info "wrote ${dest} (fill in real values before starting the service)"
		fi
	done
}

# register_units
#
# Reloads the user systemd manager and enables (but does not start) both
# MCP services.
register_units() {
	log_info "systemctl --user daemon-reload"
	systemctl --user daemon-reload

	log_info "enabling units (not starting -- fill in env files and TODOs first)"
	systemctl --user enable mcp-github.service mcp-kubernetes.service
}

# print_next_steps env_dir config_dir
#
# Human-readable follow-up instructions, printed directly rather than
# through the logger since they're meant to be read as-is, not as a
# timestamped log line.
print_next_steps() {
	local env_dir="$1" config_dir="$2"

	cat <<EOF

Next steps:
  1. Edit ${env_dir}/*.env with real credentials.
  2. Resolve the TODO(verify) notes in ${config_dir}/mcp-github.container
     and mcp-kubernetes.container (transport flags, kubernetes image).
  3. systemctl --user start mcp-github.service mcp-kubernetes.service
  4. So these keep running after you log out, and start again on boot:
     loginctl enable-linger "\$USER"
EOF
}

main() {
	init_logging

	"${SCRIPT_DIR}/lint.sh"

	local config_dir
	config_dir="$(install_config_dir)"
	local env_dir
	env_dir="$(install_env_dir)"

	install_units "${config_dir}"
	install_env_templates "${env_dir}"
	register_units
	print_next_steps "${env_dir}" "${config_dir}"
}

# shellcheck disable=SC2068
main $@
