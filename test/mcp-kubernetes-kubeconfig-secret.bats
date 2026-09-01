#!/usr/bin/env bats
# Exercises home/bin/mcp-kubernetes-kubeconfig-secret directly, not via
# install-local.sh (that just copies the file -- see install-local.bats).
# Uses its own sandbox rather than test_helper's setup_sandbox/teardown_sandbox:
# this script never touches XDG_CONFIG_HOME or systemctl, only $HOME/.kube/config
# and podman, so it stubs only podman (test/fixtures/podman-bin/) on top of a
# sandboxed HOME.

setup() {
	load 'test_helper'

	SCRIPT="${REPO_ROOT}/home/bin/mcp-kubernetes-kubeconfig-secret"

	SANDBOX_DIR="$(mktemp -d)"
	export SANDBOX_DIR
	export HOME="${SANDBOX_DIR}/home"
	mkdir -p "${HOME}"

	PODMAN_STUB_LOG="${SANDBOX_DIR}/podman.log"
	export PODMAN_STUB_LOG
	: >"${PODMAN_STUB_LOG}"

	export PATH="${FIXTURES_DIR}/podman-bin:${PATH}"

	unset KUBECONFIG_PODMAN_SECRET_NAME PODMAN_STUB_EXIT
}

teardown() {
	rm -rf "${SANDBOX_DIR}"
}

write_fixture_kubeconfig() {
	mkdir -p "${HOME}/.kube"
	cp "${FIXTURES_DIR}/kubeconfig/config" "${HOME}/.kube/config"
}

@test "mcp-kubernetes-kubeconfig-secret: dies when ~/.kube/config does not exist" {
	run "${SCRIPT}"
	assert_failure
	[ "${status}" -eq 1 ]
	assert_output --partial "${HOME}/.kube/config"
	assert_output --partial "not found"
}

@test "mcp-kubernetes-kubeconfig-secret: never invokes podman when the kubeconfig is missing" {
	run "${SCRIPT}"
	assert_failure

	[ ! -s "${PODMAN_STUB_LOG}" ]
}

@test "mcp-kubernetes-kubeconfig-secret: creates the secret from ~/.kube/config with the default name" {
	write_fixture_kubeconfig

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output "secret create --replace --label type=kubeconfig --label app=mcp-kubernetes-server --label managed-by=mcpod mcp-kubernetes-kubeconfig ${HOME}/.kube/config"
}

@test "mcp-kubernetes-kubeconfig-secret: honors a KUBECONFIG_PODMAN_SECRET_NAME override" {
	write_fixture_kubeconfig

	KUBECONFIG_PODMAN_SECRET_NAME="custom-kubeconfig-secret" run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial "custom-kubeconfig-secret ${HOME}/.kube/config"
	refute_output --partial "mcp-kubernetes-kubeconfig "
}

@test "mcp-kubernetes-kubeconfig-secret: always passes --replace so re-runs overwrite the secret" {
	write_fixture_kubeconfig

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial -- "--replace"
}

@test "mcp-kubernetes-kubeconfig-secret: labels the secret type=kubeconfig, app=mcp-kubernetes-server, managed-by=mcpod" {
	write_fixture_kubeconfig

	run "${SCRIPT}"
	assert_success

	run cat "${PODMAN_STUB_LOG}"
	assert_output --partial -- "--label type=kubeconfig --label app=mcp-kubernetes-server --label managed-by=mcpod"
}

@test "mcp-kubernetes-kubeconfig-secret: prints a confirmation naming the secret and source path" {
	write_fixture_kubeconfig

	run "${SCRIPT}"
	assert_success
	assert_output --partial "mcp-kubernetes-kubeconfig"
	assert_output --partial "${HOME}/.kube/config"
}

@test "mcp-kubernetes-kubeconfig-secret: propagates a podman failure instead of swallowing it" {
	write_fixture_kubeconfig

	export PODMAN_STUB_EXIT=3
	run "${SCRIPT}"
	assert_failure
	[ "${status}" -eq 3 ]
}
