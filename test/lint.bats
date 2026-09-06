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

@test "lint: warns and skips shellcheck when it isn't installed" {
  # A real shellcheck may be installed system-wide (e.g. /usr/bin/shellcheck),
  # so a plain PATH restriction isn't enough to hide it -- mirror /usr/bin
  # into a sandbox dir instead, symlinking everything except any file
  # literally named shellcheck.
  sandbox_dir="$(mktemp -d)"
  no_shellcheck_bin="${sandbox_dir}/no-shellcheck-bin"
  mkdir -p "${no_shellcheck_bin}"
  for f in /usr/bin/*; do
    [[ -x "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "shellcheck" ]] && continue
    ln -sf "${f}" "${no_shellcheck_bin}/${name}"
  done

  PATH="${no_shellcheck_bin}" run "${REPO_ROOT}/hack/lint.sh"
  assert_success
  assert_output --partial "failed to lint shell scripts: shellcheck not installed."

  rm -rf "${sandbox_dir}"
}
