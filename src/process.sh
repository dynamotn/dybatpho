#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains functions to error handling, fork process...
#
# **DYBATPHO_USED_ERR_HANDLER** (bool): Flag that script used dybatpho::register_err_handler
# **DYBATPHO_USED_KILLED_HANDLER** (bool): Flag that script used dybatpho::register_killed_handler
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

DYBATPHO_USED_ERR_HANDLER=false
DYBATPHO_USED_KILLED_HANDLER=false
DRY_RUN="${DRY_RUN:-}"
export DRY_RUN

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
  dybatpho::fatal "${message}" 1
  exit "${exit_code}"
}

#######################################
# @description Register error handler.
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
# @description Register killed process handler.
# @set DYBATPHO_USED_ERR_HANDLING
# @noargs
#######################################
function dybatpho::register_killed_handler {
  # shellcheck disable=SC2034
  DYBATPHO_USED_KILLED_HANDLER=true
  dybatpho::trap 'dybatpho::killed_process_handler SIGINT' SIGINT
  dybatpho::trap 'dybatpho::killed_process_handler SIGTERM' SIGTERM
}

#######################################
# @description Register all handlers
# @noargs
#######################################
function dybatpho::register_common_handlers {
  dybatpho::register_err_handler
  dybatpho::register_killed_handler
}

#######################################
# @description Handle error when running process. If you activate by `dybatpho::register_err_handler`, you don't need to invoke this function.
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
# @description Handle killed process. If you activate by `dybatpho::register_killed_handler`, you don't need to invoke this function.
# @arg $1 string Signal
#######################################
function dybatpho::killed_process_handler {
  local signal
  dybatpho::expect_args signal -- "$@"

  case ${signal} in
    SIGINT)
      dybatpho::error 'Interrupt by CTRL+C'
      ;;
    SIGTERM)
      dybatpho::error 'Terminated'
      ;;
  esac
  trap - SIGTERM && kill -- -$$
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
  _gen_finalize_command() {
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

  local pid="${BASHPID}"
  local cleanup_file
  if hash "mktemp" > /dev/null 2>&1; then
    cleanup_file=$(mktemp --tmpdir="${TMPDIR:-/tmp}" "dybatpho_cleanup-${pid}-XXXXXXXX.sh")
  else
    cleanup_file="/tmp/dybatpho_cleanup-${pid}.sh" # kcov(skip)
  fi
  touch "${cleanup_file}" "${cleanup_file}.new"
  ( # kcov(skip)
    grep -vF "${cleanup_file}" "${cleanup_file}" \
      || (
        echo ". ${DYBATPHO_DIR}/init.sh"
        echo "if [[ \"\$BASHPID\" == ${pid} ]]; then"
        echo "  dybatpho::debug 'Delete ${cleanup_file} and ${filepath} of PID ${pid}'"
        echo "  rm -rf '${filepath}' 2>&1 > /dev/null"
        echo "  rm -rf '${cleanup_file}' 2>&1 > /dev/null"
        echo "fi"
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

#######################################
# @description Show dry run message or run command.
# @arg $@ string Command to run
# @stdout Show details of command if DRY_RUN is set to true
#######################################
function dybatpho::dry_run {
  if dybatpho::is true "${DRY_RUN}"; then
    echo "🧪 DRY RUN: $*"
  else
    "$@"
  fi
}
