#!/usr/bin/env bash
# Install the opt-in environment.d template that sets XDG_CONFIG_HOME
# session-wide (read by systemd --user's environment.d generator, not
# just interactive shells). Never overwrites an existing destination file,
# same as install.sh's env templates. Separate from `make install` since
# nothing else in this repo requires it -- hack/*.sh and the installed
# units already fall back to ~/.config on their own when XDG_CONFIG_HOME
# is unset.
#
# Usage: hack/install-session-env.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

# install_environment_d_templates environment_d_dir
#
# Copies each env/environment.d/*.example template into environment_d_dir,
# stripping the .example suffix, skipping any destination that already
# exists so a reinstall never clobbers a hand-edited value. Mirrors
# install.sh's install_env_templates().
install_environment_d_templates() {
    local environment_d_dir="$1"

    log_info "installing session-env templates to ${environment_d_dir}"
    mkdir -p "${environment_d_dir}"

    local example dest
    for example in "${ENVIRONMENT_D_EXAMPLE_DIR}"/*.example; do
        dest="${environment_d_dir}/$(basename "${example}" .example)"
        if [[ -e "${dest}" ]]; then
            log_info "skip ${dest} (already exists)"
        else
            install -m 0644 "${example}" "${dest}"
            log_info "wrote ${dest} (edit and uncomment before it takes effect)"
        fi
    done
}

# print_next_steps environment_d_dir
#
# Printed directly rather than through the logger, same rationale as
# install.sh's print_next_steps -- meant to be read as-is, not as a
# timestamped log line.
print_next_steps() {
    local environment_d_dir="$1"

    cat <<EOF

Next steps:
  1. Edit ${environment_d_dir}/mcpod.conf and uncomment XDG_CONFIG_HOME if
     you want it somewhere other than the ~/.config default.
  2. Log out and back in (or run 'systemctl --user daemon-reexec') for
     systemd --user's environment.d generator to pick it up.
EOF
}

main() {
    init_logging

    local environment_d_dir
    environment_d_dir="$(install_environment_d_dir)"

    install_environment_d_templates "${environment_d_dir}"
    print_next_steps "${environment_d_dir}"
}

main "$@"
