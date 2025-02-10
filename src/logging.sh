#!/usr/bin/env bash
# @file logging.sh
# @brief Utilities for logging to stdout/stderr
# @description
#   This module contains functions to log messages to stdout/stderr.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

LOG_LEVEL=$(dybatpho::lower "${LOG_LEVEL:-info}")
export LOG_LEVEL

#######################################
# @description Verify log level from input.
# @arg $1 string String of log level
# @exitcode 0 If is valid log level
# @exitcode 1 If invalid
#######################################
function __verify_log_level {
  local level="${1}"
  level=$(dybatpho::lower "$level")
  if [[ ${level} =~ trace|debug|info|warn|error|fatal ]]; then
    return 0
  else
    echo "${level} is not a valid LOG_LEVEL, it should be trace|debug|info|warn|error|fatal"
    return 1
  fi
}

#######################################
# @description Log a message to stdout/stderr with color and caution.
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
  declare -A log_levels=([trace]=5 [debug]=4 [info]=3 [warn]=2 [error]=1 [fatal]=0)
  declare -A log_colors=([trace]="1;30;47" [debug]="0;37;40" [info]="0;40" [warn]="0;33;40" [error]="1;31;40" [fatal]="1;37;41")
  local show_log_level="${1}"
  local msg="${2}"
  local out="${3:-stdout}"
  local color=${4:-${log_colors[${show_log_level}]}}

  __verify_log_level "$LOG_LEVEL"
  __verify_log_level "$show_log_level"

  local runtime_level_num="${log_levels[${LOG_LEVEL}]}"
  local write_level_num="${log_levels[${show_log_level}]}"

  [ "$write_level_num" -le "$runtime_level_num" ] || return 0

  if [[ "$out" == "stderr" ]]; then
    echo -e "\e[${color}m${msg}\e[0m" 1>&2
  else
    echo -e "\e[${color}m${msg}\e[0m"
  fi
}

#######################################
# @description Show debug message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug {
  __log debug "DEBUG: ${*}" stderr
}

#######################################
# @description Show info message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than info level
#######################################
function dybatpho::info {
  __log info "INFO: ${*}" stderr
}

#######################################
# @description Show in progress message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::progress {
  __log info "${*}..." stdout "0;36"
}

#######################################
# @description Show notice message with banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::notice {
  local color="1;30;44"
  __log info \
    "================================================================================" \
    stdout "$color"
  __log info "${*}" stdout "$color"
  __log info \
    "================================================================================" \
    stdout "$color"
}

#######################################
# @description Show success message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::success {
  __log info "DONE: ${1}" stdout "1;32;40"
}

#######################################
# @description Show warning message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than warning level
#######################################
function dybatpho::warning {
  __log warning "WARNING: ${1}" stderr
}

#######################################
# @description Show error message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than error level
#######################################
function dybatpho::error {
  __log error "ERROR: ${1}" stderr
}

#######################################
# @description Show fatal message and exit process.
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @stderr Show message if log level of message is less than fatal level
# @exitcode $2 Stop to process anything else
#######################################
function dybatpho::fatal {
  local exit_code=${2:-1}
  __log fatal "FATAL: ${1}" stderr
  exit "$exit_code"
}

#######################################
# @description Start tracing script.
# @noargs
#######################################
function dybatpho::start_trace {
  __log trace "START TRACE" stderr
  [ "$LOG_LEVEL" = "trace" ] && set -x
}

#######################################
# @description End tracing script.
# @noargs
#######################################
function dybatpho::end_trace {
  set +x
  __log trace "END TRACE" stderr
}
