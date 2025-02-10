#!/usr/bin/env bash
# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
export DYBATPHO_DIR
# CMD to run bats
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"

for module in string logging helpers; do
  "$BATS_CMD" "test/${module}.bats"
done
