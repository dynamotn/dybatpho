#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
#
# DYBATPHO_USED_ERR_HANDLER bool Flag that script used dybatpho::register_err_handler
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
  # shellcheck disable=SC2034
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

#######################################
# @description Trap multiple signals
# @arg $1 string Command run when trapped
# @arg $2 string_list Signals to trap
#######################################
function dybatpho::trap {
  local command signal
  dybatpho::expect_args command signal -- "$@"
  shift
  for signal in "$@"; do
    # shellcheck disable=SC2064
    trap "$command" "$signal"
  done
}

#######################################
# @description Generate temporary file
# @arg $1 string Name of file in /tmp/dybatpho
# @arg $2 bool Flag to delete temporary file when exit. Default is true
#######################################
function dybatpho::gen_temp_file {
  dybatpho::require 'mktemp'
  local filename
  dybatpho::expect_args filename -- "$@"
  local filepath=$(mktemp -t "${filename}-XXXXXX")

  if dybatpho::is true "${2:-true}"; then
    dybatpho::trap "rm -f $filepath" EXIT HUP INT TERM
  fi
  echo "$filepath"
}
