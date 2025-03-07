#!/usr/bin/env bash
# @file opts.sh
# @brief Utilities for getting options when calling command in script or from CLI
# @description
#   This module contains functions to define, get options (flags, parameters...) for command or subcommand
#   when calling it from CLI or in shell script.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Define spec of parent function or script
# @arg $1 function_name Name of function that has spec of parent function or script
# @arg $2 function_name Name of function
# @stdout Required commands to run
# @exitcode 0 exit code
#######################################
function dybatpho::generate_from_spec {
  local spec parse
  dybatpho::expect_args spec parse -- "$@"
}
