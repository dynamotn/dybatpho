#!/usr/bin/env bash
# @file test.sh
# @brief Test all modules of dybatpho
# Get path to root of repository and export to subshell
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
. "$DYBATPHO_DIR/init"
# CMD to run bats
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"
dybatpho::require "kcov"
dybatpho::require "parallel"
dybatpho::require "nproc"

kcov \
  --clean \
  --dump-summary \
  --include-path="$DYBATPHO_DIR" \
  --exclude-path="$DYBATPHO_DIR"/test \
  --exclude-line="# kcov(skip)" \
  --exclude-region="# kcov(disabled):# kcov(enabled)" \
  "$DYBATPHO_DIR"/coverage \
  "$BATS_CMD" \
  -j "$(nproc)" \
  "${DYBATPHO_DIR}/test"
