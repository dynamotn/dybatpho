#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
#
# **DYBATPHO_USED_ERR_HANDLER** (bool): Flag that script used dybatpho::register_err_handler
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

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
  dybatpho::fatal "${message}" "${BASH_SOURCE[-1]}:${BASH_LINENO[0]}"
  exit "${exit_code}"
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
  dybatpho::trap 'dybatpho::run_err_handler $?' ERR
}

#######################################
# @description Run error handling. If you activate by `dybatpho::register_err_handler`, you don't need to invoke this function.
# @arg $1 number Exit code of last command
#######################################
function dybatpho::run_err_handler {
  local exit_code
  dybatpho::expect_args exit_code -- "$@"
  local i=0
  printf -- '%s\n' "Aborting on error ${exit_code}:" \
    "--------------------" >&2
  while caller "${i}" >&2; do
    ((i++))
  done
  exit "${exit_code}"
}

#######################################
# @description Trap multiple signals
# @arg $1 string Command run when trapped
# @arg $@ string Signals to trap
#######################################
function dybatpho::trap {
  local command
  dybatpho::expect_args command -- "$@"
  shift
  # shellcheck disable=SC2317
  _gen_finalize_command() {
    # shellcheck disable=SC2086
    local cmds=$(trap -p "$1")
    cmds="${cmds#*\'}"
    cmds="${cmds%\'*}"
    echo "${cmds}"
  }

  local finalize_command
  for signal in "$@"; do
    finalize_command=$(_gen_finalize_command "${signal}")
    finalize_command="${finalize_command}${finalize_command:+; }${command}"
    # shellcheck disable=SC2064,SC2086
    trap "${finalize_command}" "${signal}"
  done
}

#######################################
# @description Clean up file on exit
# @arg $1 string File path
#######################################
function dybatpho::cleanup_file_on_exit {
  local filepath
  dybatpho::expect_args filepath -- "$@"

  local pid="$$"
  local cleanup_file
  if hash "mktemp" > /dev/null 2>&1; then
    cleanup_file=$(mktemp --tmpdir="${TMPDIR:-/tmp}" "dybatpho_cleanup-${pid}-XXXXXXXX.sh")
  else
    cleanup_file="/tmp/dybatpho_cleanup-${pid}.sh"
  fi
  touch "${cleanup_file}" "${cleanup_file}.new"
  ( # kcov(skip)
    grep -vF "${cleanup_file}" "${cleanup_file}" \
      || (
        echo "rm -r '${filepath}'"
        echo "rm -r '${cleanup_file}'"
      )                     # kcov(skip)
  ) > "${cleanup_file}.new" # kcov(skip)
  mv -f "${cleanup_file}.new" "${cleanup_file}"

  # kcov(disabled)
  local trap_command="dybatpho::trap"
  if [[ "${BATS_ROOT:-}" != "" ]]; then
    trap_command="trap"
  fi
  "${trap_command}" ". ${cleanup_file}" EXIT HUP INT TERM
  # kcov(enabled)
}
