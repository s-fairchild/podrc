#!/usr/bin/env bats

setup() {
  load 'test_helper'
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "install-claude-mcp: registers kubernetes-mcp as an http server" {
  run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_success

  [[ -f "${CLAUDE_STUB_STATE_DIR}/kubernetes-mcp" ]]
  run grep -q 'mcp add --transport http kubernetes-mcp http://127.0.0.1:8081/mcp --scope user' "${CLAUDE_STUB_LOG}"
  assert_success
}

@test "install-claude-mcp: skips mcp-github when github-mcp-server-stdio isn't installed" {
  run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_success

  [[ ! -e "${CLAUDE_STUB_STATE_DIR}/mcp-github" ]]
}

@test "install-claude-mcp: registers mcp-github once github-mcp-server-stdio is installed" {
  "${REPO_ROOT}/hack/install-local.sh"

  run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_success

  [[ -f "${CLAUDE_STUB_STATE_DIR}/mcp-github" ]]
  run grep -q "mcp add mcp-github --scope user -- ${HOME}/.local/bin/github-mcp-server-stdio" "${CLAUDE_STUB_LOG}"
  assert_success
}

@test "install-claude-mcp: never overwrites an existing registration" {
  run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_success
  : >"${CLAUDE_STUB_LOG}"

  run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_success

  run grep -q 'mcp add' "${CLAUDE_STUB_LOG}"
  assert_failure
}

@test "install-claude-mcp: fails with guidance when the claude CLI is missing" {
  # A real `claude` may be installed system-wide (e.g. /usr/bin/claude),
  # so a plain PATH restriction isn't enough to hide it -- mirror
  # /usr/bin into a sandbox dir instead, symlinking everything except
  # any file literally named `claude`.
  no_claude_bin="${SANDBOX_DIR}/no-claude-bin"
  mkdir -p "${no_claude_bin}"
  for f in /usr/bin/*; do
    [[ -x "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "claude" ]] && continue
    ln -sf "${f}" "${no_claude_bin}/${name}"
  done

  PATH="${no_claude_bin}" run "${REPO_ROOT}/hack/install-claude-mcp.sh"
  assert_failure
  assert_output --partial "claude CLI not found on PATH"
}

@test "make install-claude-mcp: works via the Makefile target" {
  run make -C "${REPO_ROOT}" install-claude-mcp
  assert_success

  [[ -f "${CLAUDE_STUB_STATE_DIR}/kubernetes-mcp" ]]
}

@test "uninstall-claude-mcp: removes both registrations" {
  "${REPO_ROOT}/hack/install-local.sh"
  "${REPO_ROOT}/hack/install-claude-mcp.sh"

  run "${REPO_ROOT}/hack/uninstall-claude-mcp.sh"
  assert_success

  [[ ! -e "${CLAUDE_STUB_STATE_DIR}/kubernetes-mcp" ]]
  [[ ! -e "${CLAUDE_STUB_STATE_DIR}/mcp-github" ]]
}

@test "uninstall-claude-mcp: succeeds even if nothing was registered" {
  run "${REPO_ROOT}/hack/uninstall-claude-mcp.sh"
  assert_success
}

@test "make uninstall-claude-mcp: works via the Makefile target" {
  "${REPO_ROOT}/hack/install-claude-mcp.sh"

  run make -C "${REPO_ROOT}" uninstall-claude-mcp
  assert_success

  [[ ! -e "${CLAUDE_STUB_STATE_DIR}/kubernetes-mcp" ]]
}
