#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains helpers for script termination, signal handling, trap
#   composition, deferred cleanup, and dry-run execution.
#
# @see
#   - `example/process_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_USED_ERR_HANDLER bool Internal flag set after `dybatpho::register_err_handler`
DYBATPHO_USED_ERR_HANDLER=false
# @env DYBATPHO_USED_KILLED_HANDLER bool Internal flag set after `dybatpho::register_killed_handler`
DYBATPHO_USED_KILLED_HANDLER=false
# @env DRY_RUN string When true-like, `dybatpho::dry_run` prints commands instead of executing them
DRY_RUN="${DRY_RUN:-}"
export DRY_RUN

#######################################
# @description Log a fatal message and stop the current script or process.
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @exitcode $2 Exit the current shell with the requested code
#######################################
function dybatpho::die {
  local message exit_code
  dybatpho::expect_args message -- "$@"
  exit_code=${2:-1}
  dybatpho::fatal "${message}" 1
  exit "${exit_code}"
}

#######################################
# @description Register the ERR trap handler used by dybatpho scripts.
# @set DYBATPHO_USED_ERR_HANDLER
# @noargs
#######################################
function dybatpho::register_err_handler {
  set -E
  # shellcheck disable=SC2034
  DYBATPHO_USED_ERR_HANDLER=true
  dybatpho::trap 'dybatpho::run_err_handler $?' ERR
}

#######################################
# @description Register handlers for SIGINT and SIGTERM.
# @set DYBATPHO_USED_KILLED_HANDLER
# @noargs
#######################################
function dybatpho::register_killed_handler {
  # shellcheck disable=SC2034
  DYBATPHO_USED_KILLED_HANDLER=true
  dybatpho::trap 'dybatpho::killed_process_handler SIGINT' SIGINT
  dybatpho::trap 'dybatpho::killed_process_handler SIGTERM' SIGTERM
}

#######################################
# @description Register both error and signal handlers.
# @noargs
# @tip This is the usual one-line setup at the top of scripts that want both error and signal handling
#######################################
function dybatpho::register_common_handlers {
  dybatpho::register_err_handler
  dybatpho::register_killed_handler
}

#######################################
# @description Handle a command failure captured by `dybatpho::register_err_handler`.
# @arg $1 number Exit code of last command
#######################################
function dybatpho::run_err_handler {
  local exit_code
  dybatpho::expect_args exit_code -- "$@"
  local i=0
  printf -- '%s\n' "Aborting on error ${exit_code}:" "--------------------" >&2
  while caller "${i}" >&2; do
    ((i++))
  done
  exit "${exit_code}"
}

#######################################
# @description Handle SIGINT or SIGTERM received by the current process.
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
# @description Append a command to one or more trap handlers without discarding existing traps.
# @arg $1 string Command to run when the signal is trapped
# @arg $@ string Signals to trap
#######################################
function dybatpho::trap {
  local command
  dybatpho::expect_args command -- "$@"
  shift
  #######################################
  # @description Read the current trap command registered for a signal.
  # @arg $1 string Signal name
  # @stdout Existing trap command, or an empty string when none is registered
  #######################################
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
# @description Register a file or directory to be removed when the current shell exits.
# @arg $1 string File or directory path
# @tip `dybatpho::create_temp` already uses this internally, so call it directly only for custom temporary paths
#######################################
function dybatpho::cleanup_file_on_exit {
  local filepath
  dybatpho::expect_args filepath -- "$@"

  local pid="${BASHPID}"
  local cleanup_file quoted_filepath quoted_cleanup_file quoted_init
  if hash "mktemp" > /dev/null 2>&1; then
    cleanup_file=$(mktemp --tmpdir="${TMPDIR:-/tmp}" "dybatpho_cleanup-${pid}-XXXXXXXX.sh")
  else
    cleanup_file="/tmp/dybatpho_cleanup-${pid}.sh" # kcov(skip)
  fi
  touch "${cleanup_file}" "${cleanup_file}.new" || return 1
  printf -v quoted_filepath '%q' "${filepath}"
  printf -v quoted_cleanup_file '%q' "${cleanup_file}"
  printf -v quoted_init '%q' "${DYBATPHO_DIR}/init.sh"
  ( # kcov(skip)
    grep -vF "${cleanup_file}" "${cleanup_file}" \
      || (
        echo ". ${quoted_init}"
        echo "dybatpho::debug 'Delete ${cleanup_file} and ${filepath} of PID ${pid}'"
        echo "[ -e ${quoted_filepath} ] && rm -rf ${quoted_filepath} > /dev/null 2>&1"
        echo "[ -e ${quoted_cleanup_file} ] && rm -rf ${quoted_cleanup_file} > /dev/null 2>&1"
      )                     # kcov(skip)
  ) > "${cleanup_file}.new" # kcov(skip)
  mv -f "${cleanup_file}.new" "${cleanup_file}"

  # kcov(disabled)
  local trap_command="dybatpho::trap"
  if [[ "${BATS_ROOT:-}" != "" ]]; then
    trap_command="trap"
  fi
  "${trap_command}" "[[ \"\${BASHPID}\" == ${pid} ]] && bash ${cleanup_file}" EXIT HUP INT TERM
  # kcov(enabled)
}

#######################################
# @description Print a shell command instead of executing it when `DRY_RUN` is enabled.
# @example
#   DRY_RUN=true
#   dybatpho::dry_run "rm -rf ./build"
#
# @example
#   dybatpho::dry_run "ssh ${host} 'systemctl restart app'"
#
# @arg $@ string Shell command string to run
# @env DRY_RUN string Set to `true`, `yes`, `on`, or `0` to print commands instead of executing them
# @stdout Show the command instead of executing it when `DRY_RUN` is true
# @tip Pass a single shell command string because this helper executes the command with `eval`
#######################################
function dybatpho::dry_run {
  if dybatpho::is true "${DRY_RUN}"; then
    echo "🧪 DRY RUN: $*"
  else
    # shellcheck disable=2294
    eval "$@"
  fi
}
