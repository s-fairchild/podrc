#!/usr/bin/env bash
# Register this repo's MCP servers with Claude Code's own `claude mcp`
# config. Opt-in and separate from `make install`: it touches Claude
# Code's user config, outside ~/.config/mcpod (this repo's usual install
# scope), and requires the `claude` CLI, neither of which every user of
# this repo has.
#
# kubernetes-mcp is registered as a Streamable-HTTP server pointed at
# 127.0.0.1:8081/mcp -- see kubernetes-mcp-server.container's PublishPort= and
# README.md "Configuring each server" for the /mcp path. mcp-github is
# registered as a stdio server pointed at the installed
# home/bin/github-mcp-server-stdio (run `make install-local` first).
#
# Never overwrites an existing registration -- same skip-if-exists
# convention as install.sh's env templates. Run
# `claude mcp remove <name> -s user` first to reconfigure one.
#
# Usage: hack/install-claude-mcp.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

readonly KUBERNETES_MCP_URL="http://127.0.0.1:8081/mcp"

# require_claude_cli
#
# Fails with guidance if the `claude` CLI isn't on PATH -- same pattern
# as resolve_quadlet_bin's check for the quadlet binary.
require_claude_cli() {
    if ! command -v claude >/dev/null 2>&1; then
        log_error "claude CLI not found on PATH."
        log_error "Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
        return 1
    fi
}

# mcp_server_registered name
#
# True if Claude Code already has an MCP server config under name.
mcp_server_registered() {
    claude mcp get "$1" >/dev/null 2>&1
}

# register_kubernetes_mcp
#
# Registers kubernetes-mcp as a user-scope HTTP server, skipping if
# already registered.
register_kubernetes_mcp() {
    if mcp_server_registered kubernetes-mcp; then
        log_info "kubernetes-mcp already registered with claude; skipping" \
            "(run 'claude mcp remove kubernetes-mcp -s user' first to reconfigure)"
        return 0
    fi

    log_info "registering kubernetes-mcp with claude (${KUBERNETES_MCP_URL})"
    claude mcp add --transport http kubernetes-mcp "${KUBERNETES_MCP_URL}" \
        --scope user
}

# register_mcp_github
#
# Registers mcp-github as a user-scope stdio server pointed at the
# installed home/bin/github-mcp-server-stdio, skipping if already registered or
# if that script hasn't been installed yet.
register_mcp_github() {
    local bin_path
    bin_path="$(install_bin_dir)/github-mcp-server-stdio"

    if [[ ! -x "${bin_path}" ]]; then
        log_warn "skipping mcp-github: ${bin_path} not found or not executable" \
            "(run 'make install-local' first)"
        return 0
    fi

    if mcp_server_registered mcp-github; then
        log_info "mcp-github already registered with claude; skipping" \
            "(run 'claude mcp remove mcp-github -s user' first to reconfigure)"
        return 0
    fi

    log_info "registering mcp-github with claude (${bin_path})"
    claude mcp add mcp-github --scope user -- "${bin_path}"
}

main() {
    init_logging
    require_claude_cli

    register_kubernetes_mcp
    register_mcp_github
}

main "$@"
