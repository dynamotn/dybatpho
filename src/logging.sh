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
  declare -A log_colors=([trace]="0;37" [debug]="0;36" [info]="0;34" [warn]="0;33" [error]="1;31" [fatal]="0;31")
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
# @arg $4 number Number of call stack to get source file and line number when logging
# @arg $5 string ANSI escape color code
#######################################
function __log_inspect {
  local log_level=$1
  local log_level_text=$2
  local message="${3:-}"
  local indicator="${4:-0}"
  # 2 is total stacks from dybatpho::(info|fatal|...) to this function
  local magic_number=2
  local stack_total=$((indicator + magic_number))

  if [ "${BASH_SOURCE:-}" = "" ]; then
    indicator="bash:0" # kcov(skip)
  elif [ "${#BASH_SOURCE[@]}" -gt "${stack_total}" ]; then
    indicator="${BASH_SOURCE[${stack_total}]}:${BASH_LINENO[$((stack_total - 1))]}"
  else
    # This case for calling inline from `bash -c`
    indicator="bash:${BASH_LINENO[1]}" # kcov(skip)
  fi
  local color="${5:-}"
  __log "${log_level}" "$(date --rfc-3339="seconds") ‖ ${log_level_text} ‖ ${indicator}: ${message}" stderr "${color}"
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
  __log_inspect debug "DEBUG 🐞      " "$1"
}

#######################################
# @description Show debug result of a command.
# @arg $1 string Message
# @arg $2 string Command
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug_command {
  __log_inspect debug "COMMAND 💻    " "$1\n$(eval "$2")"
}

#######################################
# @description Show info message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than info level
#######################################
function dybatpho::info {
  __log_inspect info "INFO 💡       " "$1"
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
  local color="0;3;34"
  __log info "╭──────────────────────────────────────────────────────────────────────────────╮" stdout "${color}"
  __log info "│  🚀 $*..." stdout "${color}"
  __log info "╰──────────────────────────────────────────────────────────────────────────────╯" stdout "${color}"
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
# @description Show header message with banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::header {
  local color="1;5;30;47"
  __log info "╔══════════════════════════════════════════════════════════════════════════════╗" stdout "${color}"
  __log info "║ $*" stdout "${color}"
  __log info "╚══════════════════════════════════════════════════════════════════════════════╝" stdout "${color}"
}

#######################################
# @description Show success message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::success {
  local color="1;3;32"
  __log info "╭──────────────────────────────────────────────────────────────────────────────╮" stdout "${color}"
  __log info "│  ✅ DONE: $1" stdout "${color}"
  __log info "╰──────────────────────────────────────────────────────────────────────────────╯" stdout "${color}"
}

#######################################
# @description Show warning message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than warn level
#######################################
function dybatpho::warn {
  __log_inspect warn "WARN 🚧       " "$1"
}

#######################################
# @description Show error message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than error level
#######################################
function dybatpho::error {
  __log_inspect error "ERROR ❌      " "$1"
}

#######################################
# @description Show fatal message.
# @arg $1 string Message
# @arg $2 number Number of call stack to get source file and line number when logging
# @stderr Show message if log level of message is less than fatal level
#######################################
function dybatpho::fatal {
  __log_inspect fatal "FATAL 🛑      " "$1" "${2:-0}"
}

#######################################
# @description Start tracing script.
# @noargs
#######################################
function dybatpho::start_trace {
  __log_inspect trace "TRACE ⚡       " "Start tracing"
  if [ "${BASH_SOURCE:-}" = "" ]; then
    PS4='+(bash:0)'
  else
    PS4='+(${BASH_SOURCE}:${LINENO})'
  fi
  export PS4="${PS4}"': ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

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
  __log_inspect trace "TRACE ⚡      " "End tracing"
  # kcov(enabled)
}
