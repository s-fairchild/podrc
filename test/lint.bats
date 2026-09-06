#!/usr/bin/env bats

setup() {
  load 'test_helper'
}

@test "lint: passes on the repo's real quadlet units" {
  run "${REPO_ROOT}/hack/lint.sh"
  assert_success
  assert_output --partial "OK: all quadlet units parsed cleanly"
}

@test "lint: fails on a quadlet unit with an unsupported key" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/bad-quadlets" run "${REPO_ROOT}/hack/lint.sh"
  assert_failure
}

@test "make lint: passes via the Makefile target" {
  run make -C "${REPO_ROOT}" lint
  assert_success
}
