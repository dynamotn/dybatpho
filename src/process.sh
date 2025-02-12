#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"

#######################################
# @description Stop script/process.
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @exitcode $2 Stop to process anything else
#######################################
function dybatpho::die {
  local exit_code=${2:-1}
  dybatpho::fatal "${1}" "${BASH_SOURCE[-1]}:${BASH_LINENO[0]}"
  exit "$exit_code"
}

#######################################
# @description Register error handling.
# @noargs
#######################################
function dybatpho::register_err_handler {
  set -E
  trap 'dybatpho::run_err_handler ${?}' ERR
}

#######################################
# @description Run error handling. If you activate by `dybatpho::register_err_handler`, you don't need to invoke this function.
# @arg $1 number Exit code
#######################################
function dybatpho::run_err_handler {
  trap - ERR
  i=0
  printf -- '%s\n' "Aborting on error ${1}:" \
    "--------------------" >&2
  while caller "$i"; do
    ((i++))
  done
  exit "${1}"
}
