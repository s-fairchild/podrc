#!/usr/bin/env bats

setup() {
	load 'test_helper'
	setup_sandbox
	"${REPO_ROOT}/hack/install.sh" >/dev/null
}

teardown() {
	teardown_sandbox
}

@test "uninstall: removes quadlet units but keeps env files" {
	run "${REPO_ROOT}/hack/uninstall.sh"
	assert_success

	[ ! -e "${XDG_CONFIG_HOME}/containers/systemd/kubernetes-mcp-server.container" ]
	[ -f "${XDG_CONFIG_HOME}/mcpod/github-mcp-server.env" ]
}

@test "uninstall: disables units through systemctl --user" {
	run "${REPO_ROOT}/hack/uninstall.sh"
	assert_success

	run grep -q -- "--user disable --now kubernetes-mcp-server.service" "${SYSTEMCTL_STUB_LOG}"
	assert_success
}

@test "uninstall --purge: also removes env files" {
	run "${REPO_ROOT}/hack/uninstall.sh" --purge
	assert_success

	[ ! -e "${XDG_CONFIG_HOME}/mcpod" ]
}

@test "make uninstall: works via the Makefile target" {
	run make -C "${REPO_ROOT}" uninstall
	assert_success
}
