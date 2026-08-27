#!/usr/bin/env bats

setup() {
	load 'test_helper'
}

teardown() {
	rm -rf "${REPO_ROOT}/.generated"
}

@test "generate: names the dump after the current commit (plus -dirty if the tree isn't clean)" {
	run "${REPO_ROOT}/scripts/generate.sh"
	assert_success

	sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
	if [ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]; then
		sha="${sha}-dirty"
	fi
	[ -f "${REPO_ROOT}/.generated/dryrun-output-${sha}.txt" ]
}

@test "generate: produces a systemd unit dump for every quadlet source file" {
	run "${REPO_ROOT}/scripts/generate.sh"
	assert_success

	dump="$(ls "${REPO_ROOT}"/.generated/dryrun-output-*.txt)"
	[ -f "${dump}" ]
	run grep -c -- '---.*\.service---' "${dump}"
	assert_output "5"
}

@test "generate: includes ExecStart for the github and kubernetes containers" {
	"${REPO_ROOT}/scripts/generate.sh"
	dump="$(ls "${REPO_ROOT}"/.generated/dryrun-output-*.txt)"
	run grep -c 'ExecStart=/usr/bin/podman run' "${dump}"
	assert_output "2"
}

@test "make generate: works via the Makefile target" {
	run make -C "${REPO_ROOT}" generate
	assert_success
}
