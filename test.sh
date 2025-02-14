#!/usr/bin/env bash
# @file test.sh
# @brief Test all modules of dybatpho
# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$DYBATPHO_DIR/init"
# CMD to run bats
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"
dybatpho::require "kcov"

kcov \
  --clean \
  --dump-summary \
  --include-pattern=.sh \
  --exclude-path="$DYBATPHO_DIR"/test \
  --exclude-line="# kcov(skip)" \
  --exclude-region="# kcov(disabled):# kcov(enabled)" \
  --configure=coveralls-service-name=github-actions \
  "$DYBATPHO_DIR"/coverage \
  "$BATS_CMD" \
  "${DYBATPHO_DIR}/test"
