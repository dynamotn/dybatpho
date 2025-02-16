#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
#
# DYBATPHO_USED_ERR_HANDLING bool Flag that script used dybatpho::register_err_handler
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"

DYBATPHO_USED_ERR_HANDLER=false

#######################################
# @description Stop script/process.
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @exitcode $2 Stop to process anything else
#######################################
function dybatpho::die {
  local message exit_code
  dybatpho::expect_args message -- "$@"
  exit_code=${2:-1}
  dybatpho::fatal "$message" "${BASH_SOURCE[-1]}:${BASH_LINENO[0]}"
  exit "$exit_code"
}

#######################################
# @description Register error handling.
# @set DYBATPHO_USED_ERR_HANDLING
# @noargs
#######################################
function dybatpho::register_err_handler {
  set -E
  DYBATPHO_USED_ERR_HANDLER=true
  trap 'dybatpho::run_err_handler ${?}' ERR
}

#######################################
# @description Run error handling. If you activate by `dybatpho::register_err_handler`, you don't need to invoke this function.
# @arg $1 number Exit code
#######################################
function dybatpho::run_err_handler {
  trap - ERR
  local exit_code
  dybatpho::expect_args exit_code -- "$@"
  local i=0
  printf -- '%s\n' "Aborting on error ${exit_code}:" \
    "--------------------" >&2
  while caller "$i"; do
    ((i++))
  done
  exit "$exit_code"
}
