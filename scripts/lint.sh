#!/usr/bin/env bash
# Validate every quadlet file under config/containers/systemd/ without
# touching any real systemd search path, by pointing the local quadlet
# binary's dry-run mode at this repo via QUADLET_UNIT_DIRS.
#
# Usage: scripts/lint.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

quadlet_bin="$(resolve_quadlet_bin)"
out_dir="$(mktemp -d)"
trap 'rm -rf "${out_dir}"' EXIT

echo "==> shellcheck scripts/*.sh"
if command -v shellcheck >/dev/null 2>&1; then
	shellcheck -x "${SCRIPT_DIR}"/*.sh
else
	echo "warning: shellcheck not installed, skipping" >&2
fi

echo "==> ${quadlet_bin} -dryrun -user (source: ${QUADLET_SRC_DIR})"
if QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" "${quadlet_bin}" -dryrun -user "${out_dir}"; then
	echo "OK: all quadlet units parsed cleanly"
else
	status=$?
	echo "FAIL: quadlet reported errors parsing units under ${QUADLET_SRC_DIR}" >&2
	exit "${status}"
fi
