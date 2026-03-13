#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh"
dybatpho::require "gawk"

if (($#)); then
  sources=("$@")
else
  sources=("${DYBATPHO_DIR}/src/"*.sh)
fi

for src in "${sources[@]}"; do
  module="$(basename "${src}" .sh)"
  gawk \
    -f "${SCRIPT_DIR}/genshdoc.awk" \
    "${src}" > "${DYBATPHO_DIR}/doc/${module}.md"
done
