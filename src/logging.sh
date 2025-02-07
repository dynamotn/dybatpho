#!/usr/bin/env bash
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

LOG_LEVEL=$(_lower "${LOG_LEVEL:-info}")
export LOG_LEVEL

#######################################
# Verify log level from input.
# Arguments:
#   1: string of log level
# Returns:
#   0 if is valid log level, 1 if invalid
#######################################
_verify_log_level() {
  local level="${1}"
  level=$(_lower "$level")
  if [[ ${level} =~ trace|debug|info|warn|error|fatal ]]; then
    return 0
  else
    echo "${level} is not a valid LOG_LEVEL, it should be trace|debug|info|warn|error|fatal"
    return 1
  fi
}

#######################################
# Log a message to stdout/stderr with color and caution.
# Globals:
#   LOG_LEVEL
# Arguments:
#   1: Log level of message
#   2: Message
#   3: `stdout`/`stderr`
#   4: ANSI escape color code
#   5: Command to run after log
# Outputs:
#   Write to stdout/stderr message if log level of message is less than runtime log level
#######################################
_log() {
  declare -A log_levels=([trace]=5 [debug]=4 [info]=3 [warn]=2 [error]=1 [fatal]=0)
  declare -A log_colors=([trace]="1;30;47" [debug]="0;37;40" [info]="0;40" [warn]="0;33;40" [error]="1;31;40" [fatal]="1;37;41")
  local show_log_level="${1}"
  local msg="${2}"
  local out="${3:-stdout}"
  local color=${4:-${log_colors[${show_log_level}]}}

  _verify_log_level "$LOG_LEVEL"
  _verify_log_level "$show_log_level"

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
# Show debug message.
# Arguments:
#   Message
#######################################
_debug() {
  _log debug "DEBUG: ${*}" stderr
}

#######################################
# Show info message.
# Arguments:
#   Message
#######################################
_info() {
  _log info "INFO: ${*}" stderr
}

#######################################
# Show in progress message.
# Arguments:
#   Message
#######################################
_progress() {
  _log info "${*}..." stdout "0;36"
}

#######################################
# Show notice message with banner.
# Arguments:
#   Message
#######################################
_notice() {
  local color="1;30;44"
  _log info \
    "================================================================================" \
    stdout "$color"
  _log info "${*}" stdout "$color"
  _log info \
    "================================================================================" \
    stdout "$color"
}

#######################################
# Show success message.
# Arguments:
#   Message
#######################################
_success() {
  _log info "DONE: ${*}" stdout "1;32;40"
}

#######################################
# Show warning message.
# Arguments:
#   Message
#######################################
_warning() {
  _log warning "WARNING: ${*}" stderr
}

#######################################
# Show error message.
# Arguments:
#   Message
#######################################
_error() {
  _log error "ERROR: ${*}" stderr
}

#######################################
# Show fatal message and exit process.
# Arguments:
#   Message
#######################################
_fatal() {
  _log fatal "FATAL: ${*}" stderr
  exit 1
}

#######################################
# Start tracing script.
#######################################
_start_trace() {
  _log trace "START TRACE" stderr
  [ "$LOG_LEVEL" = "trace" ] && set -x
}

#######################################
# End tracing script.
#######################################
_end_trace() {
  set +x
  _log trace "END TRACE" stderr
}
