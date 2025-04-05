#!/usr/bin/env bash
# @file doc.sh
# @brief Generate documentation of dybatpho
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh"
dybatpho::require "shdoc"
dybatpho::require "gawk"

for module in string array opts logging helpers process network; do
  shdoc < "${DYBATPHO_DIR}/src/${module}.sh" > doc/"${module}".md || true
done
