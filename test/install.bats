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
	[ -f "${XDG_CONFIG_HOME}/containers/systemd/github-mcp-server.image" ]
	[ -f "${XDG_CONFIG_HOME}/containers/systemd/kubernetes-mcp-server.image" ]
}

@test "install: writes env templates without pre-existing secrets" {
	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	[ -f "${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github-systemd.env" ]
	run grep -q 'GITHUB_PERSONAL_ACCESS_TOKEN_PODMAN_SECRET="github-personal-access-token"' "${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github-systemd.env"
	assert_success
}

@test "install: mirrors config/mcp-quadlets local config overlay into XDG_CONFIG_HOME/mcp-quadlets" {
	MCP_QUADLETS_CONFIG_DIR="${FIXTURES_DIR}/mcp-quadlets-config" run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	[ -f "${XDG_CONFIG_HOME}/mcp-quadlets/etc/mcp-kubernetes-server/config.toml" ]
	[ -f "${XDG_CONFIG_HOME}/mcp-quadlets/etc/mcp-kubernetes-server/conf.d/00-test.toml" ]
}

@test "install: local config overlay always overwrites (not a one-shot template)" {
	MCP_QUADLETS_CONFIG_DIR="${FIXTURES_DIR}/mcp-quadlets-config" "${REPO_ROOT}/scripts/install.sh"
	dest="${XDG_CONFIG_HOME}/mcp-quadlets/etc/mcp-kubernetes-server/config.toml"
	echo "log_level = 1" >"${dest}"

	MCP_QUADLETS_CONFIG_DIR="${FIXTURES_DIR}/mcp-quadlets-config" run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	run grep -q "log_level = 6" "${dest}"
	assert_success
}

@test "install: never overwrites an existing env file" {
	"${REPO_ROOT}/scripts/install.sh"
	env_file="${XDG_CONFIG_HOME}/mcp-quadlets/mcp-github-systemd.env"
	echo 'GITHUB_PERSONAL_ACCESS_TOKEN_PODMAN_SECRET="real-secret-name"' >"${env_file}"

	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	run grep -q "real-secret-name" "${env_file}"
	assert_success
}

@test "install: reloads the user systemd manager (quadlet auto-enables via its own [Install])" {
	run "${REPO_ROOT}/scripts/install.sh"
	assert_success

	run grep -qx -- "--user daemon-reload" "${SYSTEMCTL_STUB_LOG}"
	assert_success
	# Quadlet-generated units are enabled by the systemd generator itself
	# (from each unit's own [Install] WantedBy=) at daemon-reload time, not
	# via `systemctl enable` -- that call fails against real quadlet units
	# ("is transient or generated"), so install.sh must not run it.
	run grep -q -- "--user enable" "${SYSTEMCTL_STUB_LOG}"
	assert_failure
}

@test "make install: works via the Makefile target" {
	run make -C "${REPO_ROOT}" install
	assert_success
}
