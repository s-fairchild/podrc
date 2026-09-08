#!/usr/bin/env bats

setup() {
  load 'test_helper'
}

@test "lint: passes on the repo's real quadlet units" {
  run "${REPO_ROOT}/hack/lint.sh"
  assert_success
  assert_output --partial "OK: all quadlet units parsed cleanly"
  assert_output --partial "OK: systemd accepts all generated units"
}

@test "lint: fails on a quadlet unit with an unsupported key" {
  QUADLET_SRC_DIR="${FIXTURES_DIR}/bad-quadlets" run "${REPO_ROOT}/hack/lint.sh"
  assert_failure
}

@test "lint: fails when systemd-analyze rejects a unit quadlet itself accepted" {
  # broken.container's [Service] passes ExecStartPre= straight through --
  # quadlet doesn't validate raw passthrough sections, so its own dry-run
  # accepts this unit; only systemd-analyze verify catches the nonexistent
  # binary.
  QUADLET_SRC_DIR="${FIXTURES_DIR}/quadlets-bad-systemd-unit" \
    run "${REPO_ROOT}/hack/lint.sh"
  assert_failure
  assert_output --partial "OK: all quadlet units parsed cleanly"
  assert_output --partial "is not executable"
  assert_output --partial "systemd-analyze reported errors verifying generated units"
}

@test "lint: warns and skips systemd-analyze verification when it isn't installed" {
  # Same rationale/technique as the shellcheck-skip test below: mirror
  # /usr/bin into a sandbox dir, symlinking everything except
  # systemd-analyze, since a real one is normally present system-wide.
  sandbox_dir="$(mktemp -d)"
  no_systemd_analyze_bin="${sandbox_dir}/no-systemd-analyze-bin"
  mkdir -p "${no_systemd_analyze_bin}"
  for f in /usr/bin/*; do
    [[ -x "${f}" ]] || continue
    name="$(basename "${f}")"
    [[ "${name}" == "systemd-analyze" ]] && continue
    ln -sf "${f}" "${no_systemd_analyze_bin}/${name}"
  done

  PATH="${no_systemd_analyze_bin}" run "${REPO_ROOT}/hack/lint.sh"
  assert_success
  assert_output --partial "systemd-analyze not installed; skipping unit verification."

  rm -rf "${sandbox_dir}"
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
