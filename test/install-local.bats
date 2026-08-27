#!/usr/bin/env bats

setup() {
	load 'test_helper'
	setup_sandbox
}

teardown() {
	teardown_sandbox
}

@test "install-local: installs home/bin/* to ~/.local/bin with mode 0744" {
	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-bin" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		run "${REPO_ROOT}/hack/install-local.sh"
	assert_success

	dest="${HOME}/.local/bin/hello.sh"
	[ -f "${dest}" ]
	run grep -q "hello from fixture bin script" "${dest}"
	assert_success

	run stat -c '%a' "${dest}"
	assert_output "744"
}

@test "install-local: installs home/lib/* to ~/.local/lib/mcp-quadlets with mode 0644" {
	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-bin" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib" \
		run "${REPO_ROOT}/hack/install-local.sh"
	assert_success

	dest="${HOME}/.local/lib/mcp-quadlets/helper.sh"
	[ -f "${dest}" ]

	run stat -c '%a' "${dest}"
	assert_output "644"
	[ ! -x "${dest}" ]
}

@test "install-local: skips hidden files (e.g. .gitkeep)" {
	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-bin" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		run "${REPO_ROOT}/hack/install-local.sh"
	assert_success

	[ ! -e "${HOME}/.local/bin/.gitkeep-test-hidden" ]
}

@test "install-local: warns but succeeds when a source dir has nothing to install" {
	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		run "${REPO_ROOT}/hack/install-local.sh"
	assert_success
	assert_output --partial "nothing to install"

	[ ! -e "${HOME}/.local/bin/hello.sh" ]
}

@test "install-local: always overwrites (not a one-shot template)" {
	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-bin" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		"${REPO_ROOT}/hack/install-local.sh"
	dest="${HOME}/.local/bin/hello.sh"
	echo "hand-edited, should be clobbered" >"${dest}"

	HOME_BIN_SRC_DIR="${FIXTURES_DIR}/home-bin" \
		HOME_LIB_SRC_DIR="${FIXTURES_DIR}/home-lib-empty" \
		run "${REPO_ROOT}/hack/install-local.sh"
	assert_success

	run grep -q "hello from fixture bin script" "${dest}"
	assert_success
}

@test "install-local: real home/bin/ and home/lib/ install cleanly" {
	run "${REPO_ROOT}/hack/install-local.sh"
	assert_success

	dest="${HOME}/.local/bin/mcp-github-stdio.sh"
	[ -f "${dest}" ]
	run stat -c '%a' "${dest}"
	assert_output "744"
}

@test "make install-local: works via the Makefile target" {
	run make -C "${REPO_ROOT}" install-local
	assert_success
}
