#!/bin/bash
# Validate every quadlet file under home/config/containers/systemd/
# without touching any real systemd search path, by pointing the local
# quadlet binary's dry-run mode at this repo via QUADLET_UNIT_DIRS, then
# feeding the units quadlet would generate to `systemd-analyze verify` --
# a second, independent check that catches things quadlet's own dry-run
# doesn't (e.g. a nonexistent ExecStart binary, or a Requires=/After=
# target that doesn't resolve to any real or sibling-generated unit).
#
# Usage: hack/lint.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

#######################################
# Runs shellcheck over hack/*.sh, home/bin/*, and home/lib/* (the latter
# two if any exist yet) if available; warns and skips otherwise. home/bin/
# entry points deliberately carry no file extension, so their files are
# discovered the same way install-local.sh discovers what to install
# (list_dir_files), not by a *.sh glob.
# Globals:
#   SCRIPT_DIR
#   HOME_BIN_SRC_DIR
#   HOME_LIB_SRC_DIR
# Outputs:
#   Writes shellcheck's report to stdout/stderr, or a log message if it
#   isn't installed.
#######################################
run_shellcheck() {
  log_info "shellcheck hack/*.sh home/bin/* home/lib/*"

  if ! command -v shellcheck >/dev/null 2>&1; then
    log_fatal "failed to lint shell scripts: shellcheck not installed."
    return
  fi

  local -a targets=("${SCRIPT_DIR}"/*.sh)
  local -a home_targets=()
  mapfile -t home_targets < <(
    list_dir_files "${HOME_BIN_SRC_DIR}"
    list_dir_files "${HOME_LIB_SRC_DIR}"
  )
  targets+=("${home_targets[@]}")

  shellcheck -x "${targets[@]}"
}

#######################################
# Dry-runs every unit under QUADLET_SRC_DIR through quadlet_bin, writing
# the generated-unit dump quadlet prints to stdout into dump_file (quadlet
# itself never writes into out_dir in -dryrun mode -- out_dir is a
# required positional argument it otherwise ignores). Still streams to the
# terminal via tee, so this doesn't change what running the script looks
# like. Exits with quadlet's status on failure.
# Arguments:
#   quadlet_bin: path to the quadlet binary
#   out_dir: throwaway directory to dry-run into
#   dump_file: path to save quadlet's generated-unit dump to
# Globals:
#   QUADLET_SRC_DIR
#######################################
dryrun_quadlets() {
  local quadlet_bin="$1" out_dir="$2" dump_file="$3"

  log_info "${quadlet_bin} -dryrun -user (source: ${QUADLET_SRC_DIR})"
  if QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" \
    "${quadlet_bin}" -dryrun -user "${out_dir}" | tee "${dump_file}"; then
    log_info "OK: all quadlet units parsed cleanly"
  else
    local status=$?
    log_error "quadlet reported errors parsing units under ${QUADLET_SRC_DIR}"
    exit "${status}"
  fi
}

#######################################
# Splits quadlet's "---name.service---"-delimited dump_file (see
# dryrun_quadlets) back into individual *.service files under out_dir, so
# they can be handed to systemd-analyze verify as a set -- verify needs
# sibling units on disk together to resolve this repo's own
# Requires=/After= references between them (e.g.
# kubernetes-mcp-server.service -> kubernetes-mcp-server-image.service);
# passed one at a time, each of those would fail as "unit not found".
# Arguments:
#   dump_file: path to quadlet's generated-unit dump
#   out_dir: directory to write the split-out *.service files into
#######################################
split_generated_units() {
  local dump_file="$1" out_dir="$2"
  local line current_file=""

  while IFS= read -r line; do
    if [[ "${line}" =~ ^---(.+\.service)---$ ]]; then
      current_file="${out_dir}/${BASH_REMATCH[1]}"
      : >"${current_file}"
      continue
    fi
    [[ -n "${current_file}" ]] && printf '%s\n' "${line}" >>"${current_file}"
  done <"${dump_file}"
}

#######################################
# Verifies every generated *.service unit under out_dir with
# `systemd-analyze verify`, a second, independent check beyond quadlet's
# own dry-run: it catches things like a nonexistent ExecStart binary or a
# Requires=/After= target that doesn't resolve, which quadlet's own
# dry-run (only a parse of its Quadlet -> systemd conversion) doesn't
# check. All generated units are passed to a single verify invocation
# (not one per file) so cross-unit references between them resolve
# locally -- see split_generated_units. Warns and skips if
# systemd-analyze isn't installed, rather than failing lint outright.
# Arguments:
#   out_dir: directory holding the split-out *.service files
#######################################
verify_generated_units() {
  local out_dir="$1"

  if ! command -v systemd-analyze >/dev/null 2>&1; then
    log_warn "systemd-analyze not installed; skipping unit verification."
    return
  fi

  local -a services
  shopt -s nullglob
  services=("${out_dir}"/*.service)
  shopt -u nullglob

  if (( ${#services[@]} == 0 )); then
    log_warn "no generated *.service units found; skipping unit verification."
    return
  fi

  log_info "systemd-analyze --user verify (generated units: ${#services[@]})"
  if systemd-analyze --user verify "${services[@]}"; then
    log_info "OK: systemd accepts all generated units"
  else
    local status=$?
    log_error "systemd-analyze reported errors verifying generated units"
    exit "${status}"
  fi
}

main() {
  init_logging

  local quadlet_bin
  quadlet_bin="$(resolve_quadlet_bin)"
  local out_dir
  out_dir="$(mktemp -d)"
  # out_dir is local to main(), but the EXIT trap fires after main()
  # returns (once the whole script exits), so the path is embedded into
  # the trap command directly (intentionally expanded now) rather than
  # referenced as a variable that would already be out of scope.
  # shellcheck disable=SC2064
  trap "rm -rf -- '${out_dir}'" EXIT
  local dump_file="${out_dir}/dryrun-output.txt"

  run_shellcheck
  dryrun_quadlets "${quadlet_bin}" "${out_dir}" "${dump_file}"
  split_generated_units "${dump_file}" "${out_dir}"
  verify_generated_units "${out_dir}"
}

main "$@"
