#!/usr/bin/env bash
# @file logging.sh
# @brief Utilities for logging to stdout/stderr
# @description
#   This module contains functions to log messages to stdout/stderr. Every
#   structured (JSON) log event is enriched with a request ID, hostname, PID,
#   and duration since the process started. Structured events can also be
#   appended to a rotating log file at an independent verbosity level.
# @see
#   - `example/logging_demo.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env LOG_LEVEL string Runtime log level for all messages (`trace|debug|info|warn|error|fatal`). Default is `info`
LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_LEVEL
# @env LOG_FORMAT string Log output format (`text|json`). Default is `text`
LOG_FORMAT="${LOG_FORMAT:-text}"
export LOG_FORMAT
# @env NO_COLOR string Disable ANSI colors when set to a non-empty value
NO_COLOR="${NO_COLOR:-}"
export NO_COLOR
# @env LOG_REQUEST_ID string Correlation ID attached to every structured log event. Generated automatically when empty
LOG_REQUEST_ID="${LOG_REQUEST_ID:-}"
export LOG_REQUEST_ID
# @env LOG_FILE string Optional path to append structured JSON log lines to, independent of `LOG_FORMAT`
LOG_FILE="${LOG_FILE:-}"
export LOG_FILE
# @env LOG_FILE_LEVEL string Verbosity threshold applied only to `LOG_FILE` output. Default is `LOG_LEVEL`
LOG_FILE_LEVEL="${LOG_FILE_LEVEL:-${LOG_LEVEL}}"
export LOG_FILE_LEVEL
# @env LOG_FILE_MAX_BYTES number Rotate `LOG_FILE` once it reaches this size in bytes. `0` disables rotation. Default `10485760` (10 MiB)
LOG_FILE_MAX_BYTES="${LOG_FILE_MAX_BYTES:-10485760}"
export LOG_FILE_MAX_BYTES
# @env LOG_FILE_MAX_BACKUPS number Number of rotated `LOG_FILE` backups to keep. Default `5`
LOG_FILE_MAX_BACKUPS="${LOG_FILE_MAX_BACKUPS:-5}"
export LOG_FILE_MAX_BACKUPS

#######################################
# @description Log a message to stdout or stderr, optionally with ANSI color.
# @set LOG_LEVEL string Runtime log level of the current script
# @arg $1 string Log level of message
# @arg $2 string Message
# @arg $3 string `stderr` to write to stderr, otherwise stdout
# @arg $4 string ANSI escape color code
# @stdout Show the formatted message when the level passes filtering and $3 is not `stderr`
# @stderr Show the formatted message when the level passes filtering and $3 is `stderr`
#######################################
function __log {
  declare -A log_colors=([trace]="0;37" [debug]="0;36" [info]="0;34" [warn]="0;33" [error]="1;31" [fatal]="0;31")
  local show_log_level="$1"
  local msg="$2"
  local out="${3:-stdout}"
  local color="${4:-${log_colors[${show_log_level}]}}"

  # Redact registered secrets before anything reaches stdout or stderr.
  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var msg
  fi

  dybatpho::validate_log_level "${LOG_LEVEL}" || return 1
  dybatpho::validate_log_level "${show_log_level}" || return 1

  dybatpho::compare_log_level "${show_log_level}" || return 0

  #######################################
  # @description Render the current log message with ANSI color unless `NO_COLOR` is set.
  # @noargs
  # @stdout Message text for the active log call
  #######################################
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
# @description Escape a string for use as a JSON string value.
# @arg $1 string Input text
# @stdout JSON-escaped text without surrounding quotes
#######################################
function __log_json_escape {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

#######################################
# @description Return an RFC 3339 timestamp for a log event.
# @stdout Current timestamp
#######################################
function __log_timestamp {
  if hash "busybox" 2> /dev/null; then
    busybox date +%Y-%m-%dT%H:%M:%S%:z
  elif date --version > /dev/null 2>&1; then
    date --rfc-3339="seconds"
  else
    date +%Y-%m-%dT%H:%M:%S%z
  fi
}

#######################################
# @description Return the current time in milliseconds since the epoch, using the most precise portable source available.
# @stdout Current time in milliseconds
#######################################
function __log_now_ms {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local whole="${EPOCHREALTIME%%.*}" frac="${EPOCHREALTIME#*.}"
    printf '%s' $((whole * 1000 + 10#${frac:0:3}))
    return 0
  fi
  local nanoseconds
  if nanoseconds=$(date +%s%N 2> /dev/null) && [[ "${nanoseconds}" =~ ^[0-9]+$ ]]; then
    printf '%s' $((nanoseconds / 1000000))
    return 0
  fi
  # kcov(disabled) - only reachable without EPOCHREALTIME or GNU/busybox date
  printf '%s' $((SECONDS * 1000))
  # kcov(enabled)
}

# Captured once per process so structured log events can report elapsed duration.
DYBATPHO_LOG_START_MS="$(__log_now_ms)"

#######################################
# @description Return the elapsed time since the process started, for structured log events.
# @stdout Elapsed time in milliseconds
#######################################
function __log_duration_ms {
  printf '%s' "$(($(__log_now_ms) - DYBATPHO_LOG_START_MS))"
}

#######################################
# @description Return the correlation ID attached to every structured log event, generating and caching one when `LOG_REQUEST_ID` is empty.
# @set LOG_REQUEST_ID string Generated correlation ID, when it was previously empty
# @stdout Correlation ID
#######################################
function __log_request_id {
  if [[ -z "${LOG_REQUEST_ID:-}" ]]; then
    if dybatpho::is command uuidgen; then
      LOG_REQUEST_ID="$(uuidgen)" # kcov(skip)
    else
      LOG_REQUEST_ID="$(printf '%s-%s-%s' "$$" "$(__log_now_ms)" "${RANDOM}${RANDOM}")"
    fi
    export LOG_REQUEST_ID
  fi
  printf '%s' "${LOG_REQUEST_ID}"
}

#######################################
# @description Return the current hostname attached to every structured log event, caching the result for the process lifetime.
# @stdout Hostname
#######################################
function __log_hostname {
  if [[ -z "${DYBATPHO_LOG_HOSTNAME:-}" ]]; then
    if dybatpho::is command hostname; then
      DYBATPHO_LOG_HOSTNAME=$(hostname 2> /dev/null) || true
    fi
    if [[ -z "${DYBATPHO_LOG_HOSTNAME:-}" && -r /proc/sys/kernel/hostname ]]; then
      DYBATPHO_LOG_HOSTNAME=$(cat /proc/sys/kernel/hostname 2> /dev/null) || true # kcov(skip)
    fi
    [[ -z "${DYBATPHO_LOG_HOSTNAME:-}" ]] && DYBATPHO_LOG_HOSTNAME="${HOSTNAME:-unknown}" # kcov(skip)
  fi
  printf '%s' "${DYBATPHO_LOG_HOSTNAME}"
}

#######################################
# @description Build one structured JSON log event enriched with request ID, hostname, PID, and duration.
# @arg $1 string RFC 3339 timestamp
# @arg $2 string Log level
# @arg $3 string Source location
# @arg $4 string Message
# @arg $5 number Duration in milliseconds since the process started
# @stdout One JSON object followed by a newline
#######################################
function __log_json_event {
  local timestamp="$1" level="$2" source="$3" message="$4" duration_ms="$5"
  # Call these directly (not inside `$(...)`) so the caches they populate
  # persist in the current shell instead of being lost with a subshell.
  __log_request_id > /dev/null
  __log_hostname > /dev/null
  printf '{"timestamp":"%s","level":"%s","source":"%s","message":"%s","request_id":"%s","hostname":"%s","pid":%s,"duration_ms":%s}\n' \
    "$(__log_json_escape "${timestamp}")" \
    "$(__log_json_escape "${level}")" \
    "$(__log_json_escape "${source}")" \
    "$(__log_json_escape "${message}")" \
    "$(__log_json_escape "${LOG_REQUEST_ID}")" \
    "$(__log_json_escape "${DYBATPHO_LOG_HOSTNAME}")" \
    "$$" \
    "${duration_ms}"
}

#######################################
# @description Rotate a log file in place once it reaches a size threshold, keeping a bounded number of numbered backups.
# @arg $1 string Log file path
# @arg $2 number Maximum size in bytes before rotating, `0` disables rotation
# @arg $3 number Number of rotated backups to keep
#######################################
function __log_rotate_file {
  local file="$1" max_bytes="$2" max_backups="$3"
  [[ -f "${file}" ]] || return 0
  ((max_bytes > 0)) || return 0

  local size
  size=$(wc -c < "${file}" 2> /dev/null || echo 0)
  ((size >= max_bytes)) || return 0

  if ((max_backups <= 0)); then
    : > "${file}"
    return 0
  fi

  local i
  for ((i = max_backups - 1; i >= 1; i--)); do
    [[ -f "${file}.${i}" ]] && mv -f "${file}.${i}" "${file}.$((i + 1))"
  done
  mv -f "${file}" "${file}.1"
}

#######################################
# @description Append a structured JSON log event to `LOG_FILE` when it passes `LOG_FILE_LEVEL` filtering, rotating the file first when needed.
# @arg $1 string Log level
# @arg $2 string Source location
# @arg $3 string Message
# @env LOG_FILE string Destination file; no-op when empty
# @env LOG_FILE_LEVEL string Verbosity threshold applied independently of `LOG_LEVEL`
# @env LOG_FILE_MAX_BYTES number Rotation size threshold
# @env LOG_FILE_MAX_BACKUPS number Number of rotated backups to keep
#######################################
function __log_write_file {
  local log_level="$1"
  local source="$2"
  local message="$3"
  [[ -n "${LOG_FILE:-}" ]] || return 0
  dybatpho::compare_log_level "${log_level}" "${LOG_FILE_LEVEL:-${LOG_LEVEL}}" || return 0

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  local log_dir
  log_dir=$(dirname "${LOG_FILE}")
  [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}" 2> /dev/null || return 0

  __log_rotate_file "${LOG_FILE}" "${LOG_FILE_MAX_BYTES}" "${LOG_FILE_MAX_BACKUPS}"
  __log_json_event "$(__log_timestamp)" "${log_level}" "${source}" "${message}" "$(__log_duration_ms)" >> "${LOG_FILE}"
}

#######################################
# @description Log a diagnostic event as JSON when `LOG_FORMAT=json`.
# @arg $1 string Log level
# @arg $2 string Source location
# @arg $3 string Message
# @arg $4 string ANSI escape color code
#######################################
function __log_structured {
  local log_level="$1"
  local source="$2"
  local message="$3"
  local color="${4:-}"
  local timestamp
  dybatpho::compare_log_level "${log_level}" || return 0
  timestamp=$(__log_timestamp)

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    __log_json_event "${timestamp}" "${log_level}" "${source}" "${message}" "$(__log_duration_ms)" >&2
  else
    __log "${log_level}" "${timestamp} ‖ ${source}: ${message}" stderr "${color}"
  fi
}

#######################################
# @description Return success when a message level should be shown against a threshold.
# @arg $1 string Input log level
# @arg $2 string Threshold level to compare against, default is `LOG_LEVEL`
# @env LOG_LEVEL string Runtime threshold used to decide whether the message is emitted, when no explicit threshold is given
# @exitcode 0 The message level should be emitted
# @exitcode 1 The message level is filtered out
#######################################
function dybatpho::compare_log_level {
  declare -A log_levels=([trace]=5 [debug]=4 [info]=3 [warn]=2 [error]=1 [fatal]=0)
  local level="$1"
  local runtime_level="${2:-${LOG_LEVEL}}"
  level=$(dybatpho::lower "${level}")
  runtime_level=$(dybatpho::lower "${runtime_level}")

  dybatpho::validate_log_level "${runtime_level}" || return 1
  dybatpho::validate_log_level "${level}" || return 1
  local runtime_level_num="${log_levels[${runtime_level}]}"
  local write_level_num="${log_levels[${level}]}"

  [ "${write_level_num}" -le "${runtime_level_num}" ]
}

#######################################
# @description Log a structured diagnostic message with timestamp and call-site information. Also appends a JSON event to `LOG_FILE` when configured, independently of `LOG_FORMAT`.
# @arg $1 string Log level
# @arg $2 string Rendered label for the log level
# @arg $3 string Message
# @arg $4 number Additional stack frames to skip when resolving the source location
# @arg $5 string ANSI escape color code
# @env LOG_FILE string Optional file that receives a structured JSON event regardless of `LOG_FORMAT`
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
  __log_write_file "${log_level}" "${indicator}" "${message}"
  if [[ "${LOG_FORMAT}" == "json" ]]; then
    __log_structured "${log_level}" "${indicator}" "${message}" "${color}"
  else
    __log "${log_level}" "$(__log_timestamp) ‖ ${log_level_text} ‖ ${indicator}: ${message}" stderr "${color}"
  fi
}

#######################################
# @description Return the effective terminal width used by boxed logging helpers.
# @stdout Terminal width, falling back to 80 columns
#######################################
function __get_terminal_width {
  local width="${COLUMNS:-}"
  if ! [[ "${width}" =~ ^[0-9]+$ ]] || ((width <= 0)); then
    if dybatpho::is command tput && [[ -t 1 || -t 2 ]]; then
      width="$(tput cols 2> /dev/null || true)" # kcov(skip) - needs a terminal
    fi
  fi
  if ! [[ "${width}" =~ ^[0-9]+$ ]] || ((width <= 0)); then
    width=80
  fi
  printf '%s\n' "${width}"
}

#######################################
# @description Return the display width of a string, accounting for wide Unicode glyphs when possible.
# @arg $1 string Input text
# @stdout Display width of the input
#######################################
function __string_display_width {
  local text="${1:-}"

  if dybatpho::is command python3; then
    TEXT="${text}" python3 - << 'PY'
import os
import unicodedata

text = os.environ.get("TEXT", "")
width = 0
for char in text:
    if unicodedata.combining(char):
        continue
    width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
print(width)
PY
    return 0
  fi

  printf '%s\n' "${#text}"
}

#######################################
# @description Wrap one text line to the requested width using word boundaries when possible.
# @arg $1 string Input line
# @arg $2 number Maximum width
# @stdout Wrapped lines
#######################################
function __wrap_line {
  local line max_width
  dybatpho::expect_args line max_width -- "$@"
  if ((max_width <= 0)); then
    printf '%s\n' "${line}"
    return 0
  fi
  if [[ -z "${line}" ]]; then
    printf '\n'
    return 0
  fi

  if dybatpho::is command python3; then
    LINE="${line}" MAX_WIDTH="${max_width}" python3 - << 'PY'
import os
import unicodedata

line = os.environ.get("LINE", "")
max_width = int(os.environ["MAX_WIDTH"])

def char_width(char):
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1

def text_width(text):
    return sum(char_width(char) for char in text)

def wrap_text(text, limit):
    if text == "":
        return [""]

    result = []
    remaining = text
    while text_width(remaining) > limit:
        width = 0
        break_at = None
        last_space = None
        for index, char in enumerate(remaining):
            width += char_width(char)
            if char == " ":
                last_space = index
            if width > limit:
                break_at = last_space if last_space is not None else index
                break

        if break_at is None:
            break

        if last_space is not None:
            result.append(remaining[:break_at])
            remaining = remaining[break_at + 1 :].lstrip(" ")
        else:
            # No space before limit; scan forward to keep the word/link whole
            next_space = remaining.find(" ", index)
            if next_space != -1:
                result.append(remaining[:next_space])
                remaining = remaining[next_space + 1 :].lstrip(" ")
            else:
                result.append(remaining[:break_at])
                remaining = remaining[break_at:]

    result.append(remaining)
    return result

for part in wrap_text(line, max_width):
    print(part)
PY
    return 0
  fi

  while ((${#line} > max_width)); do
    local break_at=-1 i
    for ((i = max_width; i >= 1; i--)); do
      if [[ "${line:i-1:1}" == " " ]]; then
        break_at=${i}
        break
      fi
    done
    if ((break_at == -1)); then
      # No space before limit; scan forward to keep the word/link whole
      for ((i = max_width + 1; i <= ${#line}; i++)); do
        if [[ "${line:i-1:1}" == " " ]]; then
          break_at=${i}
          break
        fi
      done
    fi
    if ((break_at == -1)); then
      printf '%s\n' "${line:0:max_width}"
      line="${line:max_width}"
    else
      printf '%s\n' "${line:0:break_at-1}"
      line="${line:break_at}"
      while [[ "${line}" == " "* ]]; do
        line="${line# }"
      done
    fi
  done
  printf '%s\n' "${line}"
}

#######################################
# @description Render a boxed message sized to its content while respecting terminal width.
# @arg $1 string Top-left border character
# @arg $2 string Horizontal border character
# @arg $3 string Top-right border character
# @arg $4 string Left border character
# @arg $5 string Right border character
# @arg $6 string Bottom-left border character
# @arg $7 string Bottom-right border character
# @arg $8 string Message body
# @arg $9 string Output stream (`stdout` or `stderr`)
# @arg $10 string ANSI color code
#######################################
function __log_box {
  local top_left="$1"
  local horizontal="$2"
  local top_right="$3"
  local left_border="$4"
  local right_border="$5"
  local bottom_left="$6"
  local bottom_right="$7"
  local message="$8"
  local out="${9:-stdout}"
  local color="${10:-0}"
  local terminal_width inner_limit line content_width=0
  local -a input_lines=() wrapped_lines=()

  terminal_width=$(__get_terminal_width)
  inner_limit=$((terminal_width - 4))
  if ((inner_limit < 1)); then
    inner_limit=1
  fi

  mapfile -t input_lines <<< "${message}"
  if ((${#input_lines[@]} == 0)); then
    input_lines=("") # kcov(skip) - defensive; a here-string always yields one line
  fi

  local input_line wrapped_line
  for input_line in "${input_lines[@]}"; do
    while IFS= read -r wrapped_line; do
      wrapped_lines+=("${wrapped_line}")
      local wrapped_width
      wrapped_width=$(__string_display_width "${wrapped_line}")
      if ((wrapped_width > content_width)); then
        content_width=${wrapped_width}
      fi
    done < <(__wrap_line "${input_line}" "${inner_limit}") # kcov(skip)
  done

  if ((${#wrapped_lines[@]} == 0)); then
    wrapped_lines=("") # kcov(skip) - defensive; wrapping always yields one line
  fi

  local border_count=$((content_width + 2))
  local horizontal_line
  horizontal_line="$(dybatpho::string_repeat "${horizontal}" "${border_count}")"

  __log info "${top_left}${horizontal_line}${top_right}" "${out}" "${color}"
  for line in "${wrapped_lines[@]}"; do
    local line_width padding_size
    line_width=$(__string_display_width "${line}")
    padding_size=$((content_width - line_width))
    local padding=""
    if ((padding_size > 0)); then
      padding="$(dybatpho::string_repeat " " "${padding_size}")"
    fi
    __log info "${left_border} ${line}${padding} ${right_border}" "${out}" "${color}"
  done
  __log info "${bottom_left}${horizontal_line}${bottom_right}" "${out}" "${color}"
}

#######################################
# @description Validate a candidate log level value.
# @arg $1 string Log level to validate
# @exitcode 0 The input is a supported log level
# @exitcode 1 The input is invalid
#######################################
function dybatpho::validate_log_level {
  local level="$1"
  level=$(dybatpho::lower "${level}")
  if [[ "${level}" =~ ^(trace|debug|info|warn|error|fatal)$ ]]; then
    return 0
  else
    printf '%s is not a valid LOG_LEVEL, it should be trace|debug|info|warn|error|fatal\n' "${level}" >&2
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
# @description Log a debug message together with the output of a shell command.
# @arg $1 string Introductory message
# @arg $2 string Shell command string to evaluate
# @env LOG_LEVEL string Set to `debug` or `trace` to see this output
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug_command {
  dybatpho::compare_log_level debug || return 0
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
# @description Show a highlighted in-progress banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::progress {
  local color="0;3;34"
  __log_box "╭" "─" "╮" "│" "│" "╰" "╯" "🚀 $*..." stdout "${color}"
}

#######################################
# @description Render a percentage-based progress bar on the current output line.
# @arg $1 number Progress percentage from 0 to 100
# @arg $2 number Width of the progress bar in characters. Default is 50
# @stdout Show the progress bar; print a newline in the caller when the task is done
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
# @description Show a section header banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::header {
  local color="1;5;30;47"
  __log_box "╔" "═" "╗" "║" "║" "╚" "╝" "$*" stdout "${color}"
}

#######################################
# @description Show success message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::success {
  local color="1;3;32"
  __log_box "╭" "─" "╮" "│" "│" "╰" "╯" "✅ DONE: $1" stdout "${color}"
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
# @description Enable Bash tracing with dybatpho formatting.
# @noargs
# @env LOG_LEVEL string Set to `trace` to emit the trace start/end messages
#######################################
function dybatpho::start_trace {
  # kcov(disabled) - replacing PS4 stops the coverage tracer
  __log_inspect trace "TRACE ⚡       " "Start tracing"
  PS4='+(${BASH_SOURCE:-no_source}:${LINENO:-no_line})'
  export PS4="${PS4}"': ${FUNCNAME[0]-no_func:+${FUNCNAME[0]-no_func}(): }'

  local trap_command="dybatpho::trap"
  if [[ "${BATS_ROOT:-}" != "" ]]; then
    trap_command="trap"
  fi
  "${trap_command}" 'set +xv' EXIT && set -xv
  # kcov(enabled)
}

#######################################
# @description Disable Bash tracing started by `dybatpho::start_trace`.
# @noargs
#######################################
function dybatpho::end_trace {
  # kcov(disabled) - disabling xtrace stops the coverage tracer
  set +xv
  __log_inspect trace "TRACE ⚡      " "End tracing"
  # kcov(enabled)
}
