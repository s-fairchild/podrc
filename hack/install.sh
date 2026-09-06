#!/bin/bash
# Install the quadlet units and env-file templates for the current user
# and register them with systemd --user. Never overwrites an existing
# env file, since those hold secrets once filled in.
#
# Usage: hack/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
. "${SCRIPT_DIR}/common.sh"

#######################################
# Copies every quadlet unit file (*.container, *.volume, *.network, *.kube,
# *.image, *.build, *.pod, *.artifact) from QUADLET_SRC_DIR into config_dir.
# Arguments:
#   config_dir: destination directory
# Globals:
#   QUADLET_SRC_DIR
# Outputs:
#   Writes status to the log.
#######################################
install_units() {
  local config_dir="$1"

  log_info "installing quadlet units to ${config_dir}"
  mkdir -p "${config_dir}"

  local -a units=()
  mapfile -t units < <(list_quadlet_units)

  if (( ${#units[@]} == 0 )); then
    log_warn "no quadlet unit files found in ${QUADLET_SRC_DIR}"
    return 0
  fi

  install -m 0644 "${units[@]}" "${config_dir}/"
}

#######################################
# Copies every env/*.example template (env-file or config-file, e.g.
# kubernetes-mcp.env.example or etc/kubernetes-mcp-server/config.toml.example)
# into env_dir, recursively and preserving the path relative to
# ENV_EXAMPLE_DIR, stripping the .example suffix. ENVIRONMENT_D_EXAMPLE_DIR
# is skipped -- install-session-env.sh installs that subtree separately, to
# a different destination. Skips any destination that already exists so a
# reinstall never clobbers a filled-in secret or hand-edited config.
# Arguments:
#   env_dir: destination directory
# Globals:
#   ENV_EXAMPLE_DIR
#   ENVIRONMENT_D_EXAMPLE_DIR
# Outputs:
#   Writes status to the log.
#######################################
install_env_templates() {
  local env_dir="$1"

  log_info "installing config templates to ${env_dir}"
  mkdir -p "${env_dir}"

  local example rel dest
  while IFS= read -r -d '' example; do
    rel="${example#"${ENV_EXAMPLE_DIR}"/}"
    rel="${rel%.example}"
    dest="${env_dir}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    if [[ -e "${dest}" ]]; then
      log_info "skip ${dest} (already exists)"
    else
      install -m 0600 "${example}" "${dest}"
      log_info "wrote ${dest} (fill in real values before starting the service)"
    fi
  done < <(find "${ENV_EXAMPLE_DIR}" -path "${ENVIRONMENT_D_EXAMPLE_DIR}" -prune \
    -o -type f -name '*.example' -print0)
}

#######################################
# Reloads the user systemd manager so it picks up the installed quadlet
# units. Quadlet's systemd generator honors each unit's own [Install]
# WantedBy= at generation time (visible under
# $XDG_RUNTIME_DIR/systemd/generator/default.target.wants/ after this
# runs), so the services are already enabled once daemon-reload
# completes -- do not `systemctl --user enable` them: enable requires a
# persistent unit file to symlink to, but these are generator-owned, so
# it fails with "Unit ... is transient or generated".
# Outputs:
#   Writes status to the log.
#######################################
register_units() {
  local -r systemctl_reload_cmd="systemctl --user daemon-reload"

  log_info "${systemctl_reload_cmd}"
  ${systemctl_reload_cmd}
}

#######################################
# Human-readable follow-up instructions, printed directly rather than
# through the logger since they're meant to be read as-is, not as a
# timestamped log line.
# Arguments:
#   env_dir: installed env dir, for the printed instructions
#   config_dir: installed config dir, for the printed instructions
# Outputs:
#   Writes the "Next steps" block to stdout.
#######################################
print_next_steps() {
  local env_dir="$1" config_dir="$2"

  local -a services=()
  mapfile -t services < <(container_service_names)

  cat <<EOF

Next steps:
  1. Edit ${env_dir}/*.env with real credentials, and
     ${env_dir}/etc/kubernetes-mcp-server/{config.toml,conf.d/*.toml} if
     you need --config-driven settings.
  2. Resolve the TODO(verify) notes in ${config_dir}/kubernetes-mcp.container
     (transport flags, kubernetes image).
  3. systemctl --user start ${services[*]}
  4. So these keep running after you log out, and start again on boot:
     loginctl enable-linger "\$USER"
  5. Run 'make install-local' to install home/bin/*, home/lib/* to
     ~/.local/bin, ~/.local/lib/podrc -- separate from this target
     since those aren't systemd-managed.
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

main "$@"
