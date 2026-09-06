#!/bin/bash
# Runs the bats suite under kcov to measure line coverage of hack/*.sh and
# home/bin/* (the shell code the suite actually exercises), writing an
# HTML report to .coverage/ (deliberately not .generated/ -- see
# hack/generate.sh; test/generate.bats rm -rf's .generated/ as part of
# testing it, which would delete kcov's output out from under it
# mid-run). Never touches any real systemd path -- kcov only instruments
# the bash processes bats forks while running test/*.bats, which already
# point at fixtures/dry-run paths the same way `make test` does.
#
# Usage: hack/coverage.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

#######################################
# Prints the path to kcov, or fails with install guidance. Overridable via
# KCOV_BIN for non-standard installs, same pattern as resolve_quadlet_bin.
# Globals:
#   KCOV_BIN
# Outputs:
#   Writes the resolved kcov binary path to stdout, or an error to the
#   log if none is found.
# Returns:
#   1 if kcov isn't found.
#######################################
resolve_kcov_bin() {
  if [[ -n "${KCOV_BIN:-}" ]]; then
    echo "${KCOV_BIN}"
    return 0
  fi

  if command -v kcov >/dev/null 2>&1; then
    command -v kcov
    return 0
  fi

  log_error "kcov not found."
  log_error "install it (e.g. 'dnf install kcov' on Fedora) or set" \
    "KCOV_BIN=/path/to/kcov to override."

  return 1
}

#######################################
# Runs the whole bats suite under kcov_bin, scoping the report to the
# shell code under test (hack/, home/bin/, home/lib/) rather than
# test/vendor/, vendor/bash-logger, or the test files themselves. Prints
# kcov's own exit status via a global (COVERAGE_STATUS) instead of
# letting it propagate under `set -e`: kcov exits with the wrapped bats
# run's status, and a coverage report is still useful even when a test
# failed, so main() reports it before exiting with that status itself.
#
# kcov's bash line-tracer is unreliable across forked/exec'd child
# processes: hack/*.sh (invoked the same way, via `run "$SCRIPT"` in a
# bats test) is consistently covered, but home/bin/* scripts -- run as
# subprocesses by e.g. kubernetes-mcp-kubeconfig-secret.bats -- are
# consistently missing from the report even though the tests exercise
# and pass them, across every script shape/location/env tried. This is a
# kcov limitation (bisected extensively; not about home/bin/ vs hack/ as
# a path, env vars, exit status, or sourcing), not a gap in the test
# suite -- don't read a 0%/absent home/bin/* line in the report as
# uncovered code.
# Arguments:
#   kcov_bin: path to the kcov binary
#   bats_bin: path to the bats binary to run under kcov
#   out_dir: directory to write the coverage report into
# Globals:
#   SCRIPT_DIR
#   HOME_BIN_SRC_DIR
#   HOME_LIB_SRC_DIR
#   REPO_ROOT
#   COVERAGE_STATUS (set by this function)
# Outputs:
#   Writes status to the log; sets COVERAGE_STATUS to kcov's exit status.
#######################################
run_coverage() {
  local kcov_bin="$1" bats_bin="$2" out_dir="$3"

  # kcov creates out_dir itself but doesn't mkdir -p it -- fails outright
  # if its parent doesn't exist yet.
  rm -rf "${out_dir}"
  mkdir -p "${out_dir}"

  local include_path="${SCRIPT_DIR},${HOME_BIN_SRC_DIR},${HOME_LIB_SRC_DIR}"

  log_info "kcov --include-path=${include_path} ${out_dir} ${bats_bin} test/*.bats"
  set +e
  "${kcov_bin}" --include-path="${include_path}" "${out_dir}" \
    "${bats_bin}" "${REPO_ROOT}"/test/*.bats
  COVERAGE_STATUS=$?
  set -e
}

#######################################
# Logs the path to the per-run HTML report kcov produced under out_dir
# (one subdirectory per traced process tree, named after bats_bin plus a
# hash) -- there's exactly one for a single kcov invocation like this.
# Arguments:
#   out_dir: directory kcov wrote its report into
# Outputs:
#   Writes status to the log.
#######################################
report_summary() {
  local out_dir="$1"

  local run_dir
  run_dir="$(find "${out_dir}" -maxdepth 1 -type d -name 'bats.*' | head -n1)"

  if [[ -z "${run_dir}" ]]; then
    log_warn "no per-run coverage directory found under ${out_dir}"
    return 0
  fi

  log_info "coverage report: ${run_dir}/index.html"
}

main() {
  init_logging

  local kcov_bin
  kcov_bin="$(resolve_kcov_bin)"
  local bats_bin="${REPO_ROOT}/test/vendor/bats-core/bin/bats"
  local out_dir="${REPO_ROOT}/.coverage"

  local COVERAGE_STATUS
  run_coverage "${kcov_bin}" "${bats_bin}" "${out_dir}"
  report_summary "${out_dir}"

  if (( COVERAGE_STATUS != 0 )); then
    log_warn "bats suite exited ${COVERAGE_STATUS}; coverage report above is still valid"
  fi
  exit "${COVERAGE_STATUS}"
}

main "$@"
