#!/usr/bin/env bats
# Exercises hack/common.sh's own helper functions directly rather than
# only incidentally through the entry-point scripts that source it --
# some of their branches (a missing vendor/bash-logger submodule, a
# *.container/*.network unit with no ContainerName=/NetworkName= set)
# never come up when running install.sh/uninstall.sh/lint.sh/generate.sh
# against this repo's own real quadlet units.

setup() {
  load 'test_helper'
}

#######################################
# Sources hack/common.sh into a disposable bash subprocess and evaluates
# expr there, so common.sh's own `set -euo pipefail` and readonly globals
# never leak into bats' own test shell.
# Arguments:
#   expr: shell code to evaluate after sourcing common.sh
# Globals:
#   REPO_ROOT
#######################################
run_common() {
  bash -c "source '${REPO_ROOT}/hack/common.sh' && $1"
}

@test "resolve_quadlet_bin: honors QUADLET_BIN override" {
  QUADLET_BIN="/custom/path/to/quadlet" run run_common 'resolve_quadlet_bin'
  assert_success
  assert_output "/custom/path/to/quadlet"
}

@test "init_logging: fails with guidance when vendor/bash-logger is missing" {
  # A fake repo root with hack/common.sh but no vendor/bash-logger --
  # common.sh derives REPO_ROOT from its own BASH_SOURCE, so sourcing a
  # copy from here makes it look for (and not find) vendor/bash-logger
  # under fake_repo, regardless of whether the real checkout has it.
  fake_repo="$(mktemp -d)"
  mkdir -p "${fake_repo}/hack"
  cp "${REPO_ROOT}/hack/common.sh" "${fake_repo}/hack/common.sh"

  run bash -c "source '${fake_repo}/hack/common.sh' && init_logging"
  assert_failure
  assert_output --partial "vendor/bash-logger/logging.sh not found"
  assert_output --partial "Run: git submodule update --init --recursive"

  rm -rf "${fake_repo}"
}

@test "quadlet_container_names: falls back to the unit's own basename when ContainerName= is unset" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/unnamed-quadlets" run run_common 'quadlet_container_names'
  assert_success
  assert_output "unnamed"
}

@test "quadlet_network_names: resolves %N in NetworkName= when set" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/unnamed-quadlets" \
    run run_common 'quadlet_network_names | grep -x net-named'
  assert_success
}

@test "quadlet_network_names: falls back to the unit's own basename when NetworkName= is unset" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/unnamed-quadlets" \
    run run_common 'quadlet_network_names | grep -x unnamed'
  assert_success
}
