#!/usr/bin/env bash
# Install the quadlet units and env-file templates for the current user
# and register them with systemd --user. Never overwrites an existing
# env file, since those hold secrets once filled in.
#
# Usage: hack/install.sh

set -o errexit \
    -o nounset \
    -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# install_units config_dir
#
# Copies every quadlet unit file (*.container, *.volume, *.network, *.kube,
# *.image, *.build, *.pod, *.artifact) from QUADLET_SRC_DIR into config_dir.
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

# install_env_templates env_dir
#
# Copies each env/*.example template (env-file or config-file, e.g.
# mcp-kubernetes.env.example or mcp-kubernetes.toml.example) into env_dir,
# stripping the .example suffix, skipping any destination that already
# exists so a reinstall never clobbers a filled-in secret or edited config.
install_env_templates() {
    local env_dir="$1"

    log_info "installing config templates to ${env_dir}"
    mkdir -p "${env_dir}"

    local example dest
    for example in "${ENV_EXAMPLE_DIR}"/*.example; do
        dest="${env_dir}/$(basename "${example}" .example)"
        if [[ -e "${dest}" ]]; then
            log_info "skip ${dest} (already exists)"
        else
            install -m 0600 "${example}" "${dest}"
            log_info "wrote ${dest} (fill in real values before starting the service)"
        fi
    done
}

# install_local_config env_dir
#
# Mirrors MCPOD_CONFIG_DIR (home/config/mcpod/) into env_dir,
# preserving its directory layout -- e.g.
# home/config/mcpod/etc/mcp-kubernetes-server/{config.toml,conf.d/*.toml}
# lands at env_dir/etc/mcp-kubernetes-server/. Unlike
# install_env_templates, this always overwrites: these aren't one-shot
# templates, they're the user's real, git-ignored files, edited directly
# in their checkout, and a reinstall should pick up edits made since the
# last one. .gitignore files are repo bookkeeping only and are skipped.
install_local_config() {
    local env_dir="$1"

    [[ -d "${MCPOD_CONFIG_DIR}" ]] || return 0

    local msg="installing local config overlay from home/config/mcpod "
    msg+="to ${env_dir}"
    log_info "${msg}"

    local path rel dest
    while IFS= read -r -d '' path; do
        rel="${path#"${MCPOD_CONFIG_DIR}"}"
        mkdir -p "${env_dir}${rel}"
    done < <(find "${MCPOD_CONFIG_DIR}" -type d -print0)

    while IFS= read -r -d '' path; do
        [[ "$(basename "${path}")" == .gitignore ]] && continue
        rel="${path#"${MCPOD_CONFIG_DIR}"}"
        dest="${env_dir}${rel}"
        install -m 0600 "${path}" "${dest}"
        log_info "wrote ${dest}"
    done < <(find "${MCPOD_CONFIG_DIR}" -type f -print0)
}

# register_units
#
# Reloads the user systemd manager so it picks up the installed quadlet
# units. Quadlet's systemd generator honors each unit's own [Install]
# WantedBy= at generation time (visible under
# $XDG_RUNTIME_DIR/systemd/generator/default.target.wants/ after this
# runs), so the services are already enabled once daemon-reload
# completes -- do not `systemctl --user enable` them: enable requires a
# persistent unit file to symlink to, but these are generator-owned, so
# it fails with "Unit ... is transient or generated".
register_units() {
    local -r systemctl_reload_cmd="systemctl --user daemon-reload"

    log_info "${systemctl_reload_cmd}"
    ${systemctl_reload_cmd}
}

# print_next_steps env_dir config_dir
#
# Human-readable follow-up instructions, printed directly rather than
# through the logger since they're meant to be read as-is, not as a
# timestamped log line.
print_next_steps() {
    local env_dir="$1" config_dir="$2"

    local -a services=()
    mapfile -t services < <(container_service_names)

    cat <<EOF

Next steps:
  1. Edit ${env_dir}/*.env with real credentials.
  2. Drop your kubernetes-mcp-server config.toml and conf.d/*.toml files
     into home/config/mcpod/etc/mcp-kubernetes-server/ (git-ignored)
     and re-run this install to sync them to
     ${env_dir}/etc/mcp-kubernetes-server/.
  3. Resolve the TODO(verify) notes in ${config_dir}/mcp-kubernetes.container
     (transport flags, kubernetes image).
  4. systemctl --user start ${services[*]}
  5. So these keep running after you log out, and start again on boot:
     loginctl enable-linger "\$USER"
  6. Run 'make install-local' to install home/bin/*, home/lib/* to
     ~/.local/bin, ~/.local/lib/mcpod -- separate from this target
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
    install_local_config "${env_dir}"
    register_units
    print_next_steps "${env_dir}" "${config_dir}"
}

main "$@"
