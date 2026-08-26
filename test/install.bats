#!/usr/bin/env bats

setup() {
	load 'test_helper'
	setup_sandbox
}

teardown() {
	teardown_sandbox
}

@test "install: copies quadlet units into XDG_CONFIG_HOME/containers/systemd" {
	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	[ -f "${XDG_CONFIG_HOME}/containers/systemd/mcp-github.container" ]
	[ -f "${XDG_CONFIG_HOME}/containers/systemd/mcp-kubernetes.container" ]
	[ -f "${XDG_CONFIG_HOME}/containers/systemd/mcp.network" ]
}

@test "install: writes env templates without pre-existing secrets" {
	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	[ -f "${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github.env" ]
	run grep -q "GITHUB_PERSONAL_ACCESS_TOKEN=changeme" "${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github.env"
	assert_success
}

@test "install: never overwrites an existing env file" {
	"${REPO_ROOT}/scripts/install.sh"
	env_file="${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github.env"
	echo "GITHUB_PERSONAL_ACCESS_TOKEN=real-secret-value" >"${env_file}"

	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	run grep -q "real-secret-value" "${env_file}"
	assert_success
}

@test "install: reloads and enables units through systemctl --user" {
	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	run grep -qx -- "--user daemon-reload" "${SYSTEMCTL_STUB_LOG}"
	assert_success
	run grep -q -- "--user enable mcp-github.service mcp-kubernetes.service" "${SYSTEMCTL_STUB_LOG}"
	assert_success
}

@test "make install: works via the Makefile target" {
	run make -C "${REPO_ROOT}" install
	assert_success
}
