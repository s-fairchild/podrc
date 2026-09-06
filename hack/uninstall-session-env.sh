#!/usr/bin/env bash
# Remove the environment.d template(s) install-session-env.sh writes.
# Counterpart to install-session-env.sh; not part of `make uninstall`
# since install-session-env.sh isn't part of `make install` either.
#
# Usage: hack/uninstall-session-env.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

#######################################
# Removes every file this repo's env/environment.d/*.example templates
# install into environment_d_dir (mirrors install_environment_d_templates
# in install-session-env.sh), ignoring ones already absent.
# Arguments:
#   environment_d_dir: directory to remove installed templates from
# Globals:
#   ENVIRONMENT_D_EXAMPLE_DIR
# Outputs:
#   Writes status to the log.
#######################################
remove_environment_d_templates() {
  local environment_d_dir="$1"

  log_info "removing session-env templates from ${environment_d_dir}"

  local example
  for example in "${ENVIRONMENT_D_EXAMPLE_DIR}"/*.example; do
    rm -f "${environment_d_dir}/$(basename "${example}" .example)"
  done
}

main() {
  init_logging

  local environment_d_dir
  environment_d_dir="$(install_environment_d_dir)"

  remove_environment_d_templates "${environment_d_dir}"
}

main "$@"
