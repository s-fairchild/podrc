#!/usr/bin/env bats

# Every test here runs hack/generate.sh (directly or via `make generate`)
# against the one real, shared "${REPO_ROOT}/.generated/" output
# directory -- there's no per-test sandbox for it like setup_sandbox()
# gives install.bats. `make test`'s `--jobs` enables bats-core's *within*
# -file parallelism too, not just across files, so without this these
# tests' bodies/teardowns (each rm -rf's and repopulates the same
# .generated/) interleave across threads and race on that shared path --
# this is what actually caused the flakiness, not the per-test git-state
# checks. BATS_NO_PARALLELIZE_WITHIN_FILE is bats-core's documented
# opt-out for exactly this: forces this file's tests to run serially even
# when the suite as a whole runs with --jobs > 1.
export BATS_NO_PARALLELIZE_WITHIN_FILE=true

setup() {
  load 'test_helper'
}

teardown() {
  rm -rf "${REPO_ROOT}/.generated"
}

@test "generate: names the dump after the current commit (plus -dirty if the tree isn't clean)" {
  # Capture the expected sha/dirty state *before* running generate.sh, not
  # after: generate.sh derives this same state internally right as it
  # starts (hack/generate.sh's git_commit_state()), and the dry-run itself
  # takes real wall-clock time. Recomputing it here afterward would race
  # against any change to the tree in between, intermittently naming a
  # different file than the one generate.sh actually wrote.
  sha="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    sha="${sha}-dirty"
  fi

  run "${REPO_ROOT}/hack/generate.sh"
  assert_success

  [[ -f "${REPO_ROOT}/.generated/dryrun-output-${sha}.txt" ]]
}

@test "generate: produces a systemd unit dump for every quadlet source file" {
  run "${REPO_ROOT}/hack/generate.sh"
  assert_success

  dump="$(ls "${REPO_ROOT}"/.generated/dryrun-output-*.txt)"
  [[ -f "${dump}" ]]
  run grep -c -- '---.*\.service---' "${dump}"
  assert_output "7"
}

@test "generate: includes ExecStart for the kubernetes container" {
  "${REPO_ROOT}/hack/generate.sh"
  dump="$(ls "${REPO_ROOT}"/.generated/dryrun-output-*.txt)"
  run grep -c 'ExecStart=/usr/bin/podman run' "${dump}"
  assert_output "1"
}

@test "make generate: works via the Makefile target" {
  run make -C "${REPO_ROOT}" generate
  assert_success
}
