#!/usr/bin/env bash
# @file logging.sh
# @brief Utilities for logging to stdout/stderr
# @description
#   This module contains functions to log messages to stdout/stderr.
#
# **LOG_LEVEL** (string): Run time log level of all messages (trace|debug|info|warn|error|fatal). Default is `info`
# **NO_COLOR** (string): Prevents the addition of ANSI color to the output when present and not an empty string. Default is ``
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_LEVEL
NO_COLOR="${NO_COLOR:-}"
export NO_COLOR

#######################################
# @description Log a message to stdout/stderr with color and caution
# @set LOG_LEVEL string Log level of script
# @arg $1 string Log level of message
# @arg $2 string Message
# @arg $3 string `stderr` to output to stderr, otherwise then to stdout
# @arg $4 string ANSI escape color code
# @arg $5 string Command to run after log
# @stdout Show message if log level of message is less than runtime log level and $3 is not `stderr`
# @stderr Show message if log level of message is less than runtime log level and $3 is `stderr`
#######################################
function __log {
  declare -A log_colors=([trace]="0;36" [debug]="0;35" [info]="0;32" [warn]="0;33" [error]="1;31" [fatal]="0;31")
  local show_log_level="$1"
  local msg="$2"
  local out="${3:-stdout}"
  local color="${4:-${log_colors[${show_log_level}]}}"

  dybatpho::validate_log_level "${LOG_LEVEL}"
  dybatpho::validate_log_level "${show_log_level}"

  dybatpho::compare_log_level "${show_log_level}" || return 0

  __check_color() {
    if [[ "${NO_COLOR}" != "" ]]; then
      echo -e "${msg}"
    else
      echo -e "\e[${color}m${msg}\e[0m"
    fi
  }
  if [[ "${out}" == "stderr" ]]; then
    __check_color >&2
  else
    __check_color
  fi
}

#######################################
# @description Verify input log level is less than runtime log level
# @arg $1 string Input log level
# @exitcode 0 If less than
# @exitcode 1 Otherwise
#######################################
function dybatpho::compare_log_level {
  declare -A log_levels=([trace]=5 [debug]=4 [info]=3 [warn]=2 [error]=1 [fatal]=0)
  local level="$1"
  level=$(dybatpho::lower "${level}")
  LOG_LEVEL=$(dybatpho::lower "${LOG_LEVEL}")

  local runtime_level_num="${log_levels[${LOG_LEVEL}]}"
  local write_level_num="${log_levels[${level}]}"

  [ "${write_level_num}" -le "${runtime_level_num}" ]
}

#######################################
# @description Log a message with date time and invoke file indicator for easier
#              to recognize on tty
# @arg $1 string String of log level
# @arg $2 string Text of log level
# @arg $3 string Message
# @arg $4 string Indicator of message, default is `<invoke file>:<line number of invoke file>`
# @arg $5 string ANSI escape color code
#######################################
function __log_inspect {
  local log_level=$1
  local log_level_text=$2
  local message="${3:-}"
  local indicator="${4:-${BASH_SOURCE[-1]}:${BASH_LINENO[1]}}"
  local color="${5:-}"
  __log "${log_level}" "$(date --rfc-3339="seconds") ‖ ${log_level_text} ‖ ${indicator}:${message}" stderr "${color}"
}

#######################################
# @description Validate log level from input.
# @arg $1 string String of log level
# @exitcode 0 If is valid log level
# @exitcode 1 If invalid
#######################################
function dybatpho::validate_log_level {
  local level="$1"
  level=$(dybatpho::lower "${level}")
  if [[ "${level}" =~ trace|debug|info|warn|error|fatal ]]; then
    return 0
  else
    echo "${level} is not a valid LOG_LEVEL, it should be trace|debug|info|warn|error|fatal"
    return 1
  fi
}

#######################################
# @description Show debug message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug {
  __log_inspect debug "DEBUG        " "$1"
}

#######################################
# @description Show debug result of a command.
# @arg $1 string Message
# @arg $2 string Command
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug_command {
  if dybatpho::compare_log_level debug; then
    __log_inspect debug "DEBUG COMMAND" "$1\n$(eval "$2")"
  fi
}

#######################################
# @description Show info message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than info level
#######################################
function dybatpho::info {
  __log_inspect info "INFO         " "$1"
}

#######################################
# @description Show normal message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::print {
  __log info "$*" stdout "0"
}

#######################################
# @description Show in progress message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::progress {
  __log info "$*..." stdout "0;3;34"
}

#######################################
# @description Show progress bar.
# @arg $1 number Elapsed percentage
# @arg $2 number Total length of progress bar in chars. Default is 50
# @stdout Show progress bar and it's disappeared after done
#######################################
function dybatpho::progress_bar {
  local percentage="$1"
  local length="${2:-50}"
  local elapsed=$((percentage * length / 100))

  printf -v prog "%${elapsed}s"
  printf -v total "%$((length - elapsed))s"
  printf '%s\r' "[${prog// /#}${total}]"
}

#######################################
# @description Show notice message with banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::notice {
  local color="1;5;44"
  __log info \
    "================================================================================" \
    stdout "${color}"
  __log info "$*" stdout "${color}"
  __log info \
    "================================================================================" \
    stdout "${color}"
}

#######################################
# @description Show success message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::success {
  __log info "DONE: $1" stdout "1;4;32;40"
}

#######################################
# @description Show warning message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than warn level
#######################################
function dybatpho::warn {
  __log_inspect warn "WARN         " "$1"
}

#######################################
# @description Show error message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than error level
#######################################
function dybatpho::error {
  __log_inspect error "ERROR        " "$1"
}

#######################################
# @description Show fatal message and exit process.
# @arg $1 string Message
# @arg $2 string Indicator of message, default is `<invoke file>:<line number of invoke file>`
# @stderr Show message if log level of message is less than fatal level
#######################################
function dybatpho::fatal {
  __log_inspect fatal "FATAL        " "$1" "${2:-}"
}

#######################################
# @description Start tracing script.
# @noargs
#######################################
function dybatpho::start_trace {
  dybatpho::compare_log_level trace || return 0
  __log_inspect trace "TRACE        " "Start tracing"
  export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

  # kcov(disabled)
  local trap_command="dybatpho::trap"
  if [[ "${BATS_ROOT:-}" != "" ]]; then
    trap_command="trap"
  fi
  "${trap_command}" 'set +xv' EXIT && set -xv
  # kcov(enabled)
}

#######################################
# @description End tracing script.
# @noargs
#######################################
function dybatpho::end_trace {
  set +xv
  # kcov(disabled)
  dybatpho::compare_log_level trace || return 0
  __log_inspect trace "TRACE        " "End tracing"
  # kcov(enabled)
}
