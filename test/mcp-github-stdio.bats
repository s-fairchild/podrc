#!/usr/bin/env bats
# Exercises home/bin/mcp-github-stdio directly, not via install-local.sh
# (that just copies the file -- see install-local.bats). Uses its own
# sandbox rather than test_helper's setup_sandbox/teardown_sandbox: this
# script never touches systemctl, only $XDG_CONFIG_HOME/mcpod (or its
# $HOME/.config fallback) and podman, so it stubs only podman
# (test/fixtures/podman-bin/) on top of a sandboxed HOME/XDG_CONFIG_HOME.
#
# The script `exec`s into podman as its very last step, so a successful
# run's exit status and stdout/stderr are the stub's, not the script's --
# assertions below check the stub's argv log instead of relying on
# anything the script itself would have printed after that point.

setup() {
	load 'test_helper'

	SCRIPT="${REPO_ROOT}/home/bin/mcp-github-stdio"
	ENV_FIXTURES_DIR="${FIXTURES_DIR}/mcp-github-env"

	SANDBOX_DIR="$(mktemp -d)"
	export SANDBOX_DIR
	export HOME="${SANDBOX_DIR}/home"
	export XDG_CONFIG_HOME="${HOME}/.config"
	mkdir -p "${HOME}"

	PODMAN_STUB_LOG="${SANDBOX_DIR}/podman.log"
	export PODMAN_STUB_LOG
	: >"${PODMAN_STUB_LOG}"

	export PATH="${FIXTURES_DIR}/podman-bin:${PATH}"

	unset MCP_GITHUB_STDIO_CONTAINER_IMAGE_TAG PODMAN_STUB_EXIT
}

teardown() {
	rm -rf "${SANDBOX_DIR}"
}

mcpod_config_dir() {
	echo "${XDG_CONFIG_HOME}/mcpod"
}

write_container_env() {
	mkdir -p "$(mcpod_config_dir)"
	cp "${ENV_FIXTURES_DIR}/mcp-github.env" "$(mcpod_config_dir)/mcp-github.env"
}

write_systemd_env() {
	mkdir -p "$(mcpod_config_dir)"
	cp "${ENV_FIXTURES_DIR}/mcp-github-systemd.env" "$(mcpod_config_dir)/mcp-github-systemd.env"
}

write_both_env_files() {
	write_container_env
	write_systemd_env
}

@test "mcp-github-stdio: dies when the container env file is missing" {
	write_systemd_env

	run "${SCRIPT}"
	assert_failure
	[ "${status}" -eq 1 ]
	assert_output --partial "$(mcpod_config_dir)/mcp-github.env"
	assert_output --partial "make install"
}

@test "mcp-github-stdio: dies when the systemd env file is missing" {
	write_container_env

	run "${SCRIPT}"
	assert_failure
	[ "${status}" -eq 1 ]
	assert_output --partial "$(mcpod_config_dir)/mcp-github-systemd.env"
	assert_output --partial "make install"
}

@test "mcp-github-stdio: never invokes podman when an env file is missing" {
	write_container_env

	run "${SCRIPT}"
	assert_failure

	[ ! -s "${PODMAN_STUB_LOG}" ]
}

@test "mcp-github-stdio: dies when GITHUB_APP_PRIVATE_KEY_PODMAN_SECRET is unset in the systemd env file" {
	write_container_env
	mkdir -p "$(mcpod_config_dir)"
	: >"$(mcpod_config_dir)/mcp-github-systemd.env"

	run "${SCRIPT}"
	assert_failure
	assert_output --partial "GITHUB_APP_PRIVATE_KEY_PODMAN_SECRET"

	[ ! -s "${PODMAN_STUB_LOG}" ]
}

@test "mcp-github-stdio: runs podman with -i --rm against the github-mcp-server image" {
	write_both_env_files

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "run -i --rm"
	assert_output --partial "ghcr.io/github/github-mcp-server:latest"
}

@test "mcp-github-stdio: mounts the podman secret named in the systemd env file" {
	write_both_env_files

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "--secret=test-github-app-private-key,type=mount,target=/run/secrets/github-app-key.pem"
}

@test "mcp-github-stdio: passes the container env file via --env-file" {
	write_both_env_files

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "--env-file=$(mcpod_config_dir)/mcp-github.env"
}

@test "mcp-github-stdio: runs the image in stdio mode with command logging enabled" {
	write_both_env_files

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "stdio --enable-command-logging"
}

@test "mcp-github-stdio: defaults the image tag to latest" {
	write_both_env_files

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "ghcr.io/github/github-mcp-server:latest"
}

@test "mcp-github-stdio: honors a MCP_GITHUB_STDIO_CONTAINER_IMAGE_TAG override" {
	write_both_env_files

	MCP_GITHUB_STDIO_CONTAINER_IMAGE_TAG="v1.2.3" run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "ghcr.io/github/github-mcp-server:v1.2.3"
	refute_output --partial "github-mcp-server:latest"
}

@test "mcp-github-stdio: falls back to \$HOME/.config when XDG_CONFIG_HOME is unset" {
	unset XDG_CONFIG_HOME
	mkdir -p "${HOME}/.config/mcpod"
	cp "${ENV_FIXTURES_DIR}/mcp-github.env" "${HOME}/.config/mcpod/mcp-github.env"
	cp "${ENV_FIXTURES_DIR}/mcp-github-systemd.env" "${HOME}/.config/mcpod/mcp-github-systemd.env"

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "--env-file=${HOME}/.config/mcpod/mcp-github.env"
}

@test "mcp-github-stdio: propagates a podman failure instead of swallowing it" {
	write_both_env_files

	export PODMAN_STUB_EXIT=3
	run "${SCRIPT}"
	assert_failure
	[ "${status}" -eq 3 ]
}
