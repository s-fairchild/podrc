#!/bin/bash
# Remove the MCP server registrations install-claude-mcp.sh writes from
# Claude Code's own `claude mcp` config. Counterpart to
# install-claude-mcp.sh; not part of `make uninstall` since
# install-claude-mcp.sh isn't part of `make install` either.
#
# Usage: hack/uninstall-claude-mcp.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

#######################################
# Fails with guidance if the `claude` CLI isn't on PATH.
# Outputs:
#   Writes an error to the log if the CLI isn't found.
# Returns:
#   1 if the claude CLI isn't on PATH.
#######################################
require_claude_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    log_error "claude CLI not found on PATH."
    log_error "Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
    return 1
  fi
}

#######################################
# Removes name from Claude Code's user-scope MCP config, ignoring it if
# already absent -- mirrors uninstall-session-env.sh's rm -f semantics.
# Arguments:
#   name: MCP server name to remove
# Outputs:
#   Writes status to the log.
#######################################
unregister_mcp_server() {
  local name="$1"

  if ! claude mcp get "${name}" >/dev/null 2>&1; then
    log_info "${name} not registered with claude; nothing to remove"
    return 0
  fi

  log_info "removing ${name} from claude"
  claude mcp remove "${name}" --scope user
}

main() {
  init_logging
  require_claude_cli

  unregister_mcp_server kubernetes-mcp
  unregister_mcp_server mcp-github
}

main "$@"
