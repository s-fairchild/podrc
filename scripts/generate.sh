#!/usr/bin/env bash
# Materialize the systemd unit files quadlet would generate from
# config/containers/systemd/, writing them to .generated/ for inspection
# (e.g. to eyeball the resulting ExecStart before installing). Does not
# touch any real systemd search path.
#
# Usage: scripts/generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

quadlet_bin="$(resolve_quadlet_bin)"
out_dir="${REPO_ROOT}/.generated"

rm -rf "${out_dir}"
mkdir -p "${out_dir}"

QUADLET_UNIT_DIRS="${QUADLET_SRC_DIR}" "${quadlet_bin}" -dryrun -user "${out_dir}" >"${out_dir}/dryrun-output.txt"

echo "Generated unit dump: ${out_dir}/dryrun-output.txt"
grep -- '---.*\.service---' "${out_dir}/dryrun-output.txt" | sed 's/^/  found: /'
