#!/usr/bin/env bash
# @file test.sh
# @brief Test all modules of dybatpho
# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
export DYBATPHO_DIR
# CMD to run bats
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"

for module in string logging helpers; do
  "$BATS_CMD" "${DYBATPHO_DIR}/test/${module}.bats"
done
