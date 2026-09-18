#!/usr/bin/env bash
# @file test.sh
# @brief Test all modules of dybatpho
# Get path to root of repository and export to subshell
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh"
# CMD to run bats
BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"
dybatpho::require "kcov"
dybatpho::require "parallel"
dybatpho::require "nproc"

# @env DYBATPHO_TEST_JOBS number Bats workers to run at once, one per core by
#   default. kcov keeps its coverage state per worker, so a machine with less
#   memory than cores needs this turned down; CI sets it explicitly.
JOBS="${DYBATPHO_TEST_JOBS:-$(nproc)}"
[[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] \
  || dybatpho::die "DYBATPHO_TEST_JOBS must be a positive integer, got '${JOBS}'"

kcov \
  --clean \
  --dump-summary \
  --include-path="${DYBATPHO_DIR}/init.sh" \
  --include-path="${DYBATPHO_DIR}/src" \
  --exclude-line="# kcov(skip)" \
  --exclude-region="# kcov(disabled):# kcov(enabled)" \
  "${DYBATPHO_DIR}"/coverage \
  "${BATS_CMD}" \
  --print-output-on-failure \
  --verbose-run \
  -j "${JOBS}" \
  "${DYBATPHO_DIR}/test"
