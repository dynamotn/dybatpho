#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh"
dybatpho::require "shdoc"
dybatpho::require "gawk"

for module in string array logging helpers process network file cli os; do
  shdoc < "${DYBATPHO_DIR}/src/${module}.sh" > "${DYBATPHO_DIR}/doc/${module}.md" || true
done
