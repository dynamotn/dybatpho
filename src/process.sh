#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Stop script/process.
# @set SELF_PID number Top level PID
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @exitcode $2 Stop to process anything else
#######################################
function dybatpho::die {
  local exit_code=${2:-1}
  dybatpho::fatal "${1}" "${BASH_SOURCE[-1]}:${BASH_LINENO[0]}"
  exit "$exit_code"
}
