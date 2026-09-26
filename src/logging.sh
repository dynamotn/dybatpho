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
# @env DYBATPHO_SPINNER string When `dybatpho::spinner` animates (`auto|always|never`). `auto` animates only on a terminal. Default `auto`
DYBATPHO_SPINNER="${DYBATPHO_SPINNER:-auto}"
export DYBATPHO_SPINNER
# @env DYBATPHO_SPINNER_INTERVAL string Seconds between spinner frames. Default `0.1`
DYBATPHO_SPINNER_INTERVAL="${DYBATPHO_SPINNER_INTERVAL:-0.1}"
export DYBATPHO_SPINNER_INTERVAL
# @env DYBATPHO_SPINNER_FRAMES string Space-separated frames the spinner cycles through
DYBATPHO_SPINNER_FRAMES="${DYBATPHO_SPINNER_FRAMES:-⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏}"
export DYBATPHO_SPINNER_FRAMES
# @env DYBATPHO_TIMER_LAST_MS number Elapsed milliseconds reported by the last `dybatpho::timer_end`
DYBATPHO_TIMER_LAST_MS="${DYBATPHO_TIMER_LAST_MS:-0}"
export DYBATPHO_TIMER_LAST_MS

# Fields attached to every structured log event, keyed by field name.
# @env __dybatpho_log_context_values
declare -gA __dybatpho_log_context_values=()
# Field names in the order they were first added, so events stay comparable.
# @env __dybatpho_log_context_keys
declare -ga __dybatpho_log_context_keys=()
# Start time in milliseconds of each running timer, keyed by timer name.
# @env __dybatpho_log_timer
declare -gA __dybatpho_log_timer=()
# Field names a structured event already carries, which a context field may not shadow.
# @env __dybatpho_log_reserved_fields
declare -g __dybatpho_log_reserved_fields=" timestamp level source message request_id hostname pid duration_ms "

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
function __dybatpho_log {
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

  # Counting logged messages is how the metrics module reports the error rate of
  # a run. The hook stays silent unless that optional module is loaded here.
  # The test names an internal helper on purpose: `dybatpho::metrics_counter_inc`
  # is exported and a child shell inherits it without the helpers it calls, so
  # testing the public name would take this branch in a child that never loaded
  # `metrics` and then fail on the first internal call.
  if declare -F __dybatpho_metrics_key > /dev/null; then
    dybatpho::metrics_counter_inc dybatpho_log_messages_total 1 "level=${show_log_level}"
  fi

  # `printf '%s'` rather than `echo -e`: a log message is data, and a Windows
  # path, a regular expression or a `sed` script carries backslashes that
  # `echo -e` would silently eat -- `C:\new\table` came out as a newline and a
  # tab. Callers that want a line break put a real one in the message.
  local rendered
  if [[ -n "${NO_COLOR}" ]]; then
    printf -v rendered '%s\n' "${msg}"
  else
    printf -v rendered '\033[%sm%s\033[0m\n' "${color}" "${msg}"
  fi

  if [[ "${out}" == "stderr" ]]; then
    printf '%s' "${rendered}" >&2
  else
    printf '%s' "${rendered}"
  fi
}

#######################################
# @description Escape a string for use as a JSON string value.
# @arg $1 string Input text
# @stdout JSON-escaped text without surrounding quotes
#######################################
function __dybatpho_log_json_escape {
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
function __dybatpho_log_timestamp {
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
function __dybatpho_log_now_ms {
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
DYBATPHO_LOG_START_MS="$(__dybatpho_log_now_ms)"

#######################################
# @description Return the elapsed time since the process started, for structured log events.
# @stdout Elapsed time in milliseconds
#######################################
function __dybatpho_log_duration_ms {
  printf '%s' "$(($(__dybatpho_log_now_ms) - DYBATPHO_LOG_START_MS))"
}

#######################################
# @description Return the correlation ID attached to every structured log event, generating and caching one when `LOG_REQUEST_ID` is empty.
# @set LOG_REQUEST_ID string Generated correlation ID, when it was previously empty
# @stdout Correlation ID
#######################################
function __dybatpho_log_request_id {
  if [[ -z "${LOG_REQUEST_ID:-}" ]]; then
    if dybatpho::is command uuidgen; then
      LOG_REQUEST_ID="$(uuidgen)" # kcov(skip)
    else
      LOG_REQUEST_ID="$(printf '%s-%s-%s' "$$" "$(__dybatpho_log_now_ms)" "${RANDOM}${RANDOM}")"
    fi
    export LOG_REQUEST_ID
  fi
  printf '%s' "${LOG_REQUEST_ID}"
}

#######################################
# @description Return the current hostname attached to every structured log event, caching the result for the process lifetime.
# @stdout Hostname
# @env DYBATPHO_LOG_HOSTNAME string Hostname to log instead of the one `dybatpho::hostname` detects
#######################################
function __dybatpho_log_hostname {
  if [[ -z "${DYBATPHO_LOG_HOSTNAME:-}" ]]; then
    DYBATPHO_LOG_HOSTNAME="$(dybatpho::hostname)"
  fi
  printf '%s' "${DYBATPHO_LOG_HOSTNAME}"
}

#######################################
# @description Build one structured JSON log event enriched with request ID, hostname, PID, duration, and the fields registered with `dybatpho::log_context`.
# @arg $1 string RFC 3339 timestamp
# @arg $2 string Log level
# @arg $3 string Source location
# @arg $4 string Message
# @arg $5 number Duration in milliseconds since the process started
# @arg $6 string Ready-made JSON fragment of extra fields, each one leading with its own comma
# @stdout One JSON object followed by a newline
#######################################
function __dybatpho_log_json_event {
  local timestamp="$1" level="$2" source="$3" message="$4" duration_ms="$5"
  local extra_fields="${6:-}"
  # Call these directly (not inside `$(...)`) so the caches they populate
  # persist in the current shell instead of being lost with a subshell.
  __dybatpho_log_request_id > /dev/null
  __dybatpho_log_hostname > /dev/null
  printf '{"timestamp":"%s","level":"%s","source":"%s","message":"%s","request_id":"%s","hostname":"%s","pid":%s,"duration_ms":%s%s%s}\n' \
    "$(__dybatpho_log_json_escape "${timestamp}")" \
    "$(__dybatpho_log_json_escape "${level}")" \
    "$(__dybatpho_log_json_escape "${source}")" \
    "$(__dybatpho_log_json_escape "${message}")" \
    "$(__dybatpho_log_json_escape "${LOG_REQUEST_ID}")" \
    "$(__dybatpho_log_json_escape "${DYBATPHO_LOG_HOSTNAME}")" \
    "$$" \
    "${duration_ms}" \
    "$(__dybatpho_log_context_json)" \
    "${extra_fields}"
}

#######################################
# @description Rotate a log file in place once it reaches a size threshold, keeping a bounded number of numbered backups.
# @arg $1 string Log file path
# @arg $2 number Maximum size in bytes before rotating, `0` disables rotation
# @arg $3 number Number of rotated backups to keep
#######################################
function __dybatpho_log_rotate_file {
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
function __dybatpho_log_write_file {
  local log_level="$1"
  local source="$2"
  local message="$3"
  local extra_fields="${4:-}"
  [[ -n "${LOG_FILE:-}" ]] || return 0
  dybatpho::compare_log_level "${log_level}" "${LOG_FILE_LEVEL:-${LOG_LEVEL}}" || return 0

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  local log_dir
  log_dir=$(dirname "${LOG_FILE}")
  [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}" 2> /dev/null || return 0

  __dybatpho_log_rotate_file "${LOG_FILE}" "${LOG_FILE_MAX_BYTES}" "${LOG_FILE_MAX_BACKUPS}"
  __dybatpho_log_json_event "$(__dybatpho_log_timestamp)" "${log_level}" "${source}" "${message}" "$(__dybatpho_log_duration_ms)" "${extra_fields}" >> "${LOG_FILE}"
}

#######################################
# @description Log a diagnostic event as JSON when `LOG_FORMAT=json`.
# @arg $1 string Log level
# @arg $2 string Source location
# @arg $3 string Message
# @arg $4 string ANSI escape color code
# @arg $5 string Ready-made JSON fragment of extra fields, each one leading with its own comma
#######################################
function __dybatpho_log_structured {
  local log_level="$1"
  local source="$2"
  local message="$3"
  local color="${4:-}"
  local extra_fields="${5:-}"
  local timestamp
  dybatpho::compare_log_level "${log_level}" || return 0
  timestamp=$(__dybatpho_log_timestamp)

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    __dybatpho_log_json_event "${timestamp}" "${log_level}" "${source}" "${message}" "$(__dybatpho_log_duration_ms)" "${extra_fields}" >&2
  else
    __dybatpho_log "${log_level}" "${timestamp} ‖ ${source}: ${message}$(__dybatpho_log_context_text)" stderr "${color}"
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
# @description Translate a diagnostic dybatpho itself emitted, using the English
#   text as its own message id the way gettext does, so that none of the several
#   hundred `die`, `warn` and `error` call sites in the library has to be
#   rewritten to use a key.
#
#   The hook is inert unless the optional `i18n` module is loaded and
#   translation of library messages was explicitly turned on, which keeps the
#   default output byte for byte the same. The guard names an internal helper of
#   that module on purpose: `dybatpho::` functions are exported and a child
#   shell inherits them without the internals they call, so guarding on the
#   public name would take the active branch in a child that never loaded
#   `i18n`.
# @arg $1 string The English message
# @stdout The translation when one exists, otherwise the message unchanged
#######################################
function __dybatpho_log_translate {
  if declare -F __dybatpho_i18n_lookup > /dev/null; then
    dybatpho::i18n_library_message "${1-}"
    return 0
  fi
  printf '%s' "${1-}"
}

#######################################
# @description Translate a piece of dybatpho's own user interface that carries a
#   value, such as a help heading or a parser error naming the switch it
#   rejected. Unlike a diagnostic, that text cannot be its own message id once a
#   value is baked into it, so the caller names a stable key and passes the
#   English it would otherwise have printed.
#
#   `cli` renders its help and parser errors through this helper as well.
#   `logging` is a core module and owns the hook, so routing the call through
#   here keeps the optional `i18n` module out of the dependency graph of both.
# @arg $1 string Message key
# @arg $2 string The English rendering, already complete
# @arg $@ string `name=value` bindings for the translated template
# @stdout The translation when one exists, otherwise $2 unchanged
#######################################
function __dybatpho_log_text {
  local key="${1-}" english="${2-}"
  shift 2 2> /dev/null || true
  if declare -F __dybatpho_i18n_lookup > /dev/null; then
    dybatpho::i18n_library_text "${key}" "${english}" "$@"
    return 0
  fi
  printf '%s' "${english}"
}

#######################################
# @description Translate a piece of dybatpho's own user interface that counts
#   something, letting the target language pick the plural form rather than the
#   English call site.
# @arg $1 string Message key
# @arg $2 number Count
# @arg $3 string The English rendering, already complete
# @arg $@ string Further `name=value` bindings for the translated template
# @stdout The translation when one exists, otherwise $3 unchanged
#######################################
function __dybatpho_log_text_n {
  local key="${1-}" count="${2-}" english="${3-}"
  shift 3 2> /dev/null || true
  if declare -F __dybatpho_i18n_lookup > /dev/null; then
    dybatpho::i18n_library_plural "${key}" "${count}" "${english}" "$@"
    return 0
  fi
  printf '%s' "${english}"
}

#######################################
# @description Log a structured diagnostic message with timestamp and call-site information. Also appends a JSON event to `LOG_FILE` when configured, independently of `LOG_FORMAT`.
# @arg $1 string Log level
# @arg $2 string Rendered label for the log level
# @arg $3 string Message
# @arg $4 number Additional stack frames to skip when resolving the source location
# @arg $5 string ANSI escape color code
# @arg $6 string Ready-made JSON fragment of extra fields, each one leading with its own comma
# @env LOG_FILE string Optional file that receives a structured JSON event regardless of `LOG_FORMAT`
#######################################
function __dybatpho_log_inspect {
  local log_level=$1
  local log_level_text=$2
  local message="${3:-}"
  local indicator="${4:-0}"
  local extra_fields="${6:-}"
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
  # Only the message is translated here: the level label beside it is padded to
  # a fixed width for the column separators and must not change.
  message="$(__dybatpho_log_translate "${message}")"
  __dybatpho_log_write_file "${log_level}" "${indicator}" "${message}" "${extra_fields}"
  if [[ "${LOG_FORMAT}" == "json" ]]; then
    __dybatpho_log_structured "${log_level}" "${indicator}" "${message}" "${color}" "${extra_fields}"
  else
    __dybatpho_log "${log_level}" "$(__dybatpho_log_timestamp) ‖ ${log_level_text} ‖ ${indicator}: ${message}$(__dybatpho_log_context_text)" stderr "${color}"
  fi
}

#######################################
# @description Return the effective terminal width used by boxed logging helpers.
# @stdout Terminal width, falling back to 80 columns
#######################################
function __dybatpho_log_get_terminal_width {
  dybatpho::terminal_width 80
}

#######################################
# @description Return success when a string holds nothing but printable ASCII,
#   which is the case where one character is exactly one terminal column and
#   Bash can measure it on its own.
#
#   `LC_ALL=C` is local to this function so the bracket range means bytes
#   0x20..0x7E rather than whatever the caller's collation makes of it.
# @arg $1 string Text to classify
# @exitcode 0 The text is printable ASCII, optionally with tabs
# @exitcode 1 The text holds a character that may not be one column wide
#######################################
function __dybatpho_log_is_plain_ascii {
  local LC_ALL=C
  case "${1-}" in
    *[!$'\t'\ -~]*) return 1 ;;
    *) return 0 ;;
  esac
}

#######################################
# @description Read the character that starts at an index, as UTF-8.
#   Outside a UTF-8 locale Bash indexes a string by byte, so a glyph such as
#   `✅` would be measured as three one-column characters and the box drawn
#   around it would come out too wide. The lead byte gives the length of the
#   sequence, which keeps the measure the same under the C locale.
# @arg $1 string Name of the variable receiving the character
# @arg $2 string Text to read from
# @arg $3 number Index of the character's first byte or character
# @arg $4 bool `1` when Bash is indexing by byte
# @set The named variable
#######################################
function __dybatpho_log_char_at_into {
  local -n __dybatpho_char_out="$1"
  local __dybatpho_char_text="$2" __dybatpho_char_index="$3"
  local __dybatpho_char_lead __dybatpho_char_length=1

  __dybatpho_char_out="${__dybatpho_char_text:__dybatpho_char_index:1}"
  [[ "$4" == 1 ]] || return 0
  printf -v __dybatpho_char_lead '%d' "'${__dybatpho_char_out}"
  if ((__dybatpho_char_lead >= 240)); then
    __dybatpho_char_length=4
  elif ((__dybatpho_char_lead >= 224)); then
    __dybatpho_char_length=3
  elif ((__dybatpho_char_lead >= 192)); then
    __dybatpho_char_length=2
  fi
  __dybatpho_char_out="${__dybatpho_char_text:__dybatpho_char_index:__dybatpho_char_length}"
}

#######################################
# @description Report whether Bash indexes strings by byte in this locale.
# @exitcode 0 Bash counts bytes, so multi-byte characters must be assembled
# @exitcode 1 Bash counts characters
#######################################
function __dybatpho_log_indexes_bytes {
  local probe=$'\303\251'
  ((${#probe} != 1))
}

# Display width of each non-ASCII character seen so far, keyed by the character.
# @env __dybatpho_log_char_width_cache
declare -gA __dybatpho_log_char_width_cache=()

#######################################
# @description Fill the character-width cache for every non-ASCII character in
#   a string that is not in it yet, in a single `python3` call.
#
#   Width used to cost one process per measured string, so a twenty-row table
#   paid eighty of them and a boxed `dybatpho::success` paid one per line.
#   Caching per character rather than per string is what makes that cost
#   amortize away: the library's own labels hold about ten distinct glyphs, and
#   CJK text reuses its characters heavily, so a long run settles into no
#   processes at all while still answering exactly what `python3` answers.
#
#   Without `python3` every unknown character is recorded as one column, which
#   is the answer the previous fallback gave.
# @arg $1 string Text whose characters to learn
# @set __dybatpho_log_char_width_cache
#######################################
function __dybatpho_log_learn_widths {
  local text="${1-}"
  local -a unknown=()
  local index character bytewise=0
  __dybatpho_log_indexes_bytes && bytewise=1

  for ((index = 0; index < ${#text}; index += ${#character})); do
    __dybatpho_log_char_at_into character "${text}" "${index}" "${bytewise}"
    __dybatpho_log_is_plain_ascii "${character}" && continue
    [[ -v "__dybatpho_log_char_width_cache[${character}]" ]] && continue
    __dybatpho_log_char_width_cache["${character}"]=1
    unknown+=("${character}")
  done

  ((${#unknown[@]})) || return 0
  dybatpho::is command python3 || return 0

  local joined
  printf -v joined '%s' "${unknown[@]}"

  local -a widths=()
  mapfile -t widths < <(TEXT="${joined}" python3 - << 'PY'
import os
import unicodedata

text = os.environ.get("TEXT", "")
for char in text:
    if unicodedata.combining(char):
        print(0)
    else:
        print(2 if unicodedata.east_asian_width(char) in ("F", "W") else 1)
PY
  )

  # A short answer means python3 failed part way through; the characters it did
  # not reach keep the one-column default recorded above.
  for ((index = 0; index < ${#unknown[@]} && index < ${#widths[@]}; index++)); do
    [[ "${widths[index]}" =~ ^[0-9]+$ ]] || continue
    __dybatpho_log_char_width_cache["${unknown[index]}"]="${widths[index]}"
  done
}

#######################################
# @description Return the display width of a string, accounting for wide Unicode glyphs when possible.
# @arg $1 string Input text
# @stdout Display width of the input
#######################################
function __dybatpho_log_width_into {
  local __dybatpho_width_name="$1"
  local __dybatpho_width_text="${2:-}"
  local -n __dybatpho_width_out="${__dybatpho_width_name}"

  if __dybatpho_log_is_plain_ascii "${__dybatpho_width_text}"; then
    __dybatpho_width_out="${#__dybatpho_width_text}"
    return 0
  fi

  __dybatpho_log_learn_widths "${__dybatpho_width_text}"

  local __dybatpho_width_index __dybatpho_width_char __dybatpho_width_bytewise=0
  __dybatpho_log_indexes_bytes && __dybatpho_width_bytewise=1
  __dybatpho_width_out=0
  for ((__dybatpho_width_index = 0; __dybatpho_width_index < ${#__dybatpho_width_text}; __dybatpho_width_index += ${#__dybatpho_width_char})); do
    __dybatpho_log_char_at_into __dybatpho_width_char "${__dybatpho_width_text}" \
      "${__dybatpho_width_index}" "${__dybatpho_width_bytewise}"
    if __dybatpho_log_is_plain_ascii "${__dybatpho_width_char}"; then
      __dybatpho_width_out=$((__dybatpho_width_out + 1))
    else
      __dybatpho_width_out=$((__dybatpho_width_out + ${__dybatpho_log_char_width_cache[${__dybatpho_width_char}]:-1}))
    fi
  done
}

#######################################
# @description Repeat a string, writing the result into a named variable.
#   The renderers build padding one cell at a time, and reaching
#   `dybatpho::string_repeat` through `$( )` forked once per cell.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to repeat
# @arg $3 number Number of repetitions
# @set The named variable
#######################################
function __dybatpho_log_repeat_into {
  local __dybatpho_repeat_name="$1"
  local __dybatpho_repeat_token="${2-}"
  local __dybatpho_repeat_count="${3:-0}"
  local -n __dybatpho_repeat_out="${__dybatpho_repeat_name}"
  local __dybatpho_repeat_index

  __dybatpho_repeat_out=""
  ((__dybatpho_repeat_count > 0)) || return 0
  for ((__dybatpho_repeat_index = 0; __dybatpho_repeat_index < __dybatpho_repeat_count; __dybatpho_repeat_index++)); do
    __dybatpho_repeat_out+="${__dybatpho_repeat_token}"
  done
}

#######################################
# @description Return the display width of a string, accounting for wide Unicode glyphs when possible.
# @arg $1 string Input text
# @stdout Display width of the input
#######################################
function __dybatpho_log_string_display_width {
  local __dybatpho_display_width
  __dybatpho_log_width_into __dybatpho_display_width "${1:-}"
  printf '%s\n' "${__dybatpho_display_width}"
}


#######################################
# @description Wrap one text line to the requested width using word boundaries when possible.
# @arg $1 string Input line
# @arg $2 number Maximum width
# @stdout Wrapped lines
#######################################
function __dybatpho_log_wrap_line {
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

  # Wrapping is measured in columns rather than characters, so a CJK or emoji
  # line breaks where it actually reaches the edge of the terminal. The widths
  # come from the character cache, which `__dybatpho_log_learn_widths` fills in
  # one shot here rather than once per line in a `python3` child.
  __dybatpho_log_learn_widths "${line}"

  local total="${#line}"
  local -a widths=()
  local index character
  for ((index = 0; index < total; index++)); do
    character="${line:index:1}"
    if __dybatpho_log_is_plain_ascii "${character}"; then
      widths[index]=1
    else
      widths[index]="${__dybatpho_log_char_width_cache[${character}]:-1}"
    fi
  done

  local start=0 used cut last_space break_at next_space
  while ((start < total)); do
    used=0
    cut=-1
    last_space=-1
    for ((index = start; index < total; index++)); do
      used=$((used + widths[index]))
      [[ "${line:index:1}" == " " ]] && last_space=${index}
      if ((used > max_width)); then
        cut=${index}
        break
      fi
    done

    # Everything left fits on one line.
    ((cut >= 0)) || break

    if ((last_space >= start)); then
      break_at=${last_space}
    else
      # Nothing to break on before the limit. Keep the word -- a URL, a path --
      # whole and run past the edge rather than cutting it in half.
      next_space=-1
      for ((index = cut; index < total; index++)); do
        if [[ "${line:index:1}" == " " ]]; then
          next_space=${index}
          break
        fi
      done
      ((next_space >= 0)) || break
      break_at=${next_space}
    fi

    printf '%s\n' "${line:start:break_at-start}"
    start=$((break_at + 1))
    while ((start < total)) && [[ "${line:start:1}" == " " ]]; do
      start=$((start + 1))
    done
  done

  printf '%s\n' "${line:start}"
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
function __dybatpho_log_box {
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

  terminal_width=$(__dybatpho_log_get_terminal_width)
  inner_limit=$((terminal_width - 4))
  if ((inner_limit < 1)); then
    inner_limit=1
  fi

  # Learn every character's width here, in this shell. The measuring below runs
  # inside `$(...)`, and a subshell's additions to the cache die with it, so
  # warming it once in the parent is what lets a boxed message be drawn without
  # a `python3` child per line.
  __dybatpho_log_learn_widths "${message}"

  mapfile -t input_lines <<< "${message}"
  if ((${#input_lines[@]} == 0)); then
    input_lines=("") # kcov(skip) - defensive; a here-string always yields one line
  fi

  local input_line wrapped_line
  for input_line in "${input_lines[@]}"; do
    while IFS= read -r wrapped_line; do
      wrapped_lines+=("${wrapped_line}")
      local wrapped_width
      __dybatpho_log_width_into wrapped_width "${wrapped_line}"
      if ((wrapped_width > content_width)); then
        content_width=${wrapped_width}
      fi
    done < <(__dybatpho_log_wrap_line "${input_line}" "${inner_limit}") # kcov(skip)
  done

  if ((${#wrapped_lines[@]} == 0)); then
    wrapped_lines=("") # kcov(skip) - defensive; wrapping always yields one line
  fi

  local border_count=$((content_width + 2))
  local horizontal_line
  __dybatpho_log_repeat_into horizontal_line "${horizontal}" "${border_count}"

  __dybatpho_log info "${top_left}${horizontal_line}${top_right}" "${out}" "${color}"
  for line in "${wrapped_lines[@]}"; do
    local line_width padding_size
    __dybatpho_log_width_into line_width "${line}"
    padding_size=$((content_width - line_width))
    local padding=""
    if ((padding_size > 0)); then
      __dybatpho_log_repeat_into padding " " "${padding_size}"
    fi
    __dybatpho_log info "${left_border} ${line}${padding} ${right_border}" "${out}" "${color}"
  done
  __dybatpho_log info "${bottom_left}${horizontal_line}${bottom_right}" "${out}" "${color}"
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
  __dybatpho_log_inspect debug "DEBUG 🐞      " "$1"
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
  __dybatpho_log_inspect debug "COMMAND 💻    " "$1
$(eval "$2")"
}

#######################################
# @description Show info message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than info level
#######################################
function dybatpho::info {
  __dybatpho_log_inspect info "INFO 💡       " "$1"
}

#######################################
# @description Show normal message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::print {
  __dybatpho_log info "$*" stdout "0"
}

#######################################
# @description Show a highlighted in-progress banner.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::progress {
  local color="0;3;34"
  # The banner helpers compose their text before boxing it, so they never reach
  # the hook in `__dybatpho_log_inspect` and have to translate their own message.
  local message
  message="$(__dybatpho_log_translate "$*")"
  __dybatpho_log_box "╭" "─" "╮" "│" "│" "╰" "╯" "🚀 ${message}..." stdout "${color}"
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
  local message
  message="$(__dybatpho_log_translate "$*")"
  __dybatpho_log_box "╔" "═" "╗" "║" "║" "╚" "╝" "${message}" stdout "${color}"
}

#######################################
# @description Show success message.
# @arg $1 string Message
# @stdout Show message if log level of message is less than info level
#######################################
function dybatpho::success {
  local color="1;3;32"
  # The message is the caller's and is keyed by its English text; the `DONE:`
  # beside it is the library's own label and gets a stable key of its own.
  local message label
  message="$(__dybatpho_log_translate "$1")"
  label="$(__dybatpho_log_text logging.done "DONE:")"
  __dybatpho_log_box "╭" "─" "╮" "│" "│" "╰" "╯" "✅ ${label} ${message}" stdout "${color}"
}

#######################################
# @description Show warning message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than warn level
#######################################
function dybatpho::warn {
  __dybatpho_log_inspect warn "WARN 🚧       " "$1"
}

#######################################
# @description Show error message.
# @arg $1 string Message
# @stderr Show message if log level of message is less than error level
#######################################
function dybatpho::error {
  __dybatpho_log_inspect error "ERROR ❌      " "$1"
}

#######################################
# @description Show fatal message.
# @arg $1 string Message
# @arg $2 number Number of call stack to get source file and line number when logging
# @stderr Show message if log level of message is less than fatal level
#######################################
function dybatpho::fatal {
  __dybatpho_log_inspect fatal "FATAL 🛑      " "$1" "${2:-0}"
}

#######################################
# @description Render the fields registered with `dybatpho::log_context` as a
#   JSON fragment ready to be spliced into a structured event.
#
#   Values are redacted here rather than when the field is registered, so a
#   secret registered after the fact is still masked on the next event.
# @stdout `,"name":"value"` for every registered field, in registration order
#######################################
function __dybatpho_log_context_json {
  ((${#__dybatpho_log_context_keys[@]} > 0)) || return 0
  local key value
  for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
    value="${__dybatpho_log_context_values[${key}]-}"
    if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
      __dybatpho_secret_mask_var value
    fi
    printf ',"%s":"%s"' \
      "$(__dybatpho_log_json_escape "${key}")" \
      "$(__dybatpho_log_json_escape "${value}")"
  done
}

#######################################
# @description Render the registered context fields for a human-readable line.
# @stdout ` name=value` for every registered field, in registration order
#######################################
function __dybatpho_log_context_text {
  ((${#__dybatpho_log_context_keys[@]} > 0)) || return 0
  local key value
  for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
    value="${__dybatpho_log_context_values[${key}]-}"
    if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
      __dybatpho_secret_mask_var value
    fi
    printf ' %s=%s' "${key}" "${value}"
  done
}

#######################################
# @description Register or update context fields from `name=value` pairs.
# @arg $@ string `name=value` pairs
# @set __dybatpho_log_context_values
# @set __dybatpho_log_context_keys
#######################################
function __dybatpho_log_context_add {
  (($# > 0)) \
    || dybatpho::die "dybatpho::log_context: 'add' expects at least one name=value pair"
  local pair name value existing found
  for pair in "$@"; do
    [[ "${pair}" == *=* ]] \
      || dybatpho::die "dybatpho::log_context: '${pair}' is not a name=value pair"
    name="${pair%%=*}"
    value="${pair#*=}"
    if [[ ! "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      dybatpho::die "dybatpho::log_context: '${name}' is not a valid field name"
    fi
    if [[ "${__dybatpho_log_reserved_fields}" == *" ${name} "* ]]; then
      dybatpho::die "dybatpho::log_context: '${name}' is already a field of every log event"
    fi
    # An update keeps the field where it was first added, so two events from
    # the same run stay comparable field by field.
    found=false
    for existing in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
      if [[ "${existing}" == "${name}" ]]; then
        found=true
        break
      fi
    done
    if [[ "${found}" == false ]]; then
      __dybatpho_log_context_keys+=("${name}")
    fi
    __dybatpho_log_context_values["${name}"]="${value}"
  done
}

#######################################
# @description Drop context fields by name, ignoring names that are not set.
# @arg $@ string Field names
# @set __dybatpho_log_context_values
# @set __dybatpho_log_context_keys
#######################################
function __dybatpho_log_context_remove {
  (($# > 0)) \
    || dybatpho::die "dybatpho::log_context: 'remove' expects at least one field name"
  local name key
  local -a kept=()
  for name in "$@"; do
    unset "__dybatpho_log_context_values[${name}]"
    kept=()
    for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
      if [[ "${key}" != "${name}" ]]; then
        kept+=("${key}")
      fi
    done
    __dybatpho_log_context_keys=(${kept[@]+"${kept[@]}"})
  done
}

#######################################
# @description Convert a human-readable byte size into a plain byte count.
# @arg $1 string Size such as `1048576`, `512K`, `10M` or `2GiB`
# @stdout The size in bytes
# @exitcode 1 The input is not a size this function understands
#######################################
function __dybatpho_log_parse_size {
  local input="${1-}"
  [[ "${input}" =~ ^([0-9]+)[[:space:]]*([KkMmGgTt]?)([Ii]?[Bb])?$ ]] || return 1
  local number="${BASH_REMATCH[1]}"
  case "${BASH_REMATCH[2]}" in
    [Kk]) number=$((number * 1024)) ;;
    [Mm]) number=$((number * 1024 * 1024)) ;;
    [Gg]) number=$((number * 1024 * 1024 * 1024)) ;;
    [Tt]) number=$((number * 1024 * 1024 * 1024 * 1024)) ;;
  esac
  printf '%s' "${number}"
}

#######################################
# @description Pause for a fractional number of seconds, falling back to one
#   whole second where `sleep` only understands integers.
# @arg $1 string Seconds to wait
#######################################
function __dybatpho_log_sleep {
  sleep "${1}" 2> /dev/null || sleep 1
}

#######################################
# @description Animate the spinner on stderr until the shell that started it
#   kills it. Runs as a background job, so it never returns on its own.
# @arg $1 string Message shown beside the frame, already redacted
# @stderr One frame per interval, redrawn over the same line
#######################################
function __dybatpho_log_spin {
  local message="${1-}"
  local -a frames=()
  read -r -a frames <<< "${DYBATPHO_SPINNER_FRAMES}"
  ((${#frames[@]} > 0)) || frames=('-' "\\" '|' '/')
  local index=0
  while true; do
    printf '\r%s %s\033[K' "${frames[index % ${#frames[@]}]}" "${message}" >&2
    index=$((index + 1))
    __dybatpho_log_sleep "${DYBATPHO_SPINNER_INTERVAL}"
  done
}

#######################################
# @description Send structured JSON events to a file alongside the
#   human-readable output on stderr, and keep that file bounded by rotating it.
#
#   This is the front end to the `LOG_FILE*` variables: a script names the path
#   once instead of exporting four of them, and gets the argument checking, the
#   parent directory and a private mode along with it. Every registered secret
#   is redacted before a line reaches the file, exactly as it is on stderr, so
#   turning on a durable log never turns it into a place a token leaks to.
# @example
#   dybatpho::log_to_file /var/log/deploy.log rotate:10M keep:3 level:debug
#   dybatpho::info "Deploying"  # text on stderr, JSON in the file
#   dybatpho::log_to_file off   # stop writing to a file
#
# @arg $1 string Path of the log file, or `off` to stop file logging
# @arg $@ string Optional `rotate:SIZE`, `keep:COUNT` and `level:LEVEL` settings
# @set LOG_FILE string Path that receives the structured events
# @set LOG_FILE_MAX_BYTES number Size threshold the file is rotated at
# @set LOG_FILE_MAX_BACKUPS number Number of rotated backups kept
# @set LOG_FILE_LEVEL string Verbosity threshold applied to the file alone
# @exitcode 1 A setting is malformed, or the file cannot be written
# @tip `rotate:0` disables rotation, and a size may be given as bytes or with a `K`, `M`, `G` or `T` suffix
# @tip A log file this function creates gets mode `600`; one that already exists keeps the mode it has
#######################################
function dybatpho::log_to_file {
  local path
  dybatpho::expect_args path -- "$@"
  shift

  local rotate="${LOG_FILE_MAX_BYTES}"
  local keep="${LOG_FILE_MAX_BACKUPS}"
  local level="${LOG_FILE_LEVEL:-${LOG_LEVEL}}"
  local setting value parsed
  for setting in "$@"; do
    value="${setting#*:}"
    case "${setting}" in
      rotate:*)
        parsed="$(__dybatpho_log_parse_size "${value}")" \
          || dybatpho::die "${FUNCNAME[0]}: Rotation size must be a byte count such as 10M, got '${value}'"
        rotate="${parsed}"
        ;;
      keep:*)
        if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
          dybatpho::die "${FUNCNAME[0]}: Backup count must be a whole number, got '${value}'"
        fi
        keep="${value}"
        ;;
      level:*)
        dybatpho::validate_log_level "${value}" \
          || dybatpho::die "${FUNCNAME[0]}: Log level of the file sink is invalid"
        level="$(dybatpho::lower "${value}")"
        ;;
      *)
        dybatpho::die "${FUNCNAME[0]}: Unknown setting '${setting}', expected rotate:SIZE, keep:COUNT or level:LEVEL"
        ;;
    esac
  done

  if [[ "${path}" == "off" ]]; then
    LOG_FILE=""
  else
    local directory
    directory="$(dirname "${path}")"
    if [[ ! -d "${directory}" ]]; then
      mkdir -p "${directory}" \
        || dybatpho::die "${FUNCNAME[0]}: Cannot create log directory '${directory}'"
    fi
    if [[ ! -e "${path}" ]]; then
      # A log file holds whatever the script logged, which is the last place a
      # value should become world-readable. The mode is chosen at creation
      # only, so an operator who widened it deliberately keeps their choice.
      (
        umask 077
        : > "${path}"
      ) || dybatpho::die "${FUNCNAME[0]}: Cannot create log file '${path}'"
    fi
    [[ -w "${path}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Log file '${path}' is not writable"
    LOG_FILE="${path}"
  fi

  LOG_FILE_MAX_BYTES="${rotate}"
  LOG_FILE_MAX_BACKUPS="${keep}"
  LOG_FILE_LEVEL="${level}"
  export LOG_FILE LOG_FILE_MAX_BYTES LOG_FILE_MAX_BACKUPS LOG_FILE_LEVEL
}

#######################################
# @description Attach fields to every structured log event that follows, so a
#   run identifier or a stage name rides along with each JSON line instead of
#   being spelled out in every message. Text output carries the same fields
#   after the message.
# @example
#   dybatpho::log_context add run_id=abc stage=build
#   dybatpho::error "compilation failed"  # the event carries both fields
#   dybatpho::log_context remove stage
#   dybatpho::log_context clear
#
# @arg $1 string One of `add`, `remove`, `clear`, `list` or `get`
# @arg $@ string `name=value` pairs for `add`, field names for `remove` and `get`
# @stdout One `name=value` per field for `list`, the bare value for `get`
# @exitcode 1 `get` was asked for a field that is not set
# @set __dybatpho_log_context_values
# @set __dybatpho_log_context_keys
# @tip Fields are held in the current shell, so a child process starts with none of them; export `LOG_REQUEST_ID` to correlate across processes
# @tip Registered secrets are redacted in field values the same way they are in messages
#######################################
function dybatpho::log_context {
  local action
  dybatpho::expect_args action -- "$@"
  shift
  case "${action}" in
    add | set)
      __dybatpho_log_context_add "$@"
      ;;
    remove | unset)
      __dybatpho_log_context_remove "$@"
      ;;
    clear)
      __dybatpho_log_context_values=()
      __dybatpho_log_context_keys=()
      ;;
    list)
      local key
      for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
        printf '%s=%s\n' "${key}" "${__dybatpho_log_context_values[${key}]-}"
      done
      ;;
    get)
      local name
      dybatpho::expect_args name -- "$@"
      [[ -v "__dybatpho_log_context_values[${name}]" ]] || return 1
      printf '%s\n' "${__dybatpho_log_context_values[${name}]}"
      ;;
    *)
      dybatpho::die "${FUNCNAME[0]}: Unknown action '${action}', expected add, remove, clear, list or get"
      ;;
  esac
}

#######################################
# @description Start a named timer whose elapsed time `dybatpho::timer_end` logs.
# @example
#   dybatpho::timer_start migration
#   ./migrate.sh
#   dybatpho::timer_end migration
#
# @arg $1 string Timer name
# @set __dybatpho_log_timer
# @tip This times a step so the log says how long it took; `dybatpho::metrics_timer_start` records the same measurement as a metric for a dashboard
#######################################
function dybatpho::timer_start {
  local name
  dybatpho::expect_args name -- "$@"
  __dybatpho_log_timer["${name}"]="$(__dybatpho_log_now_ms)"
}

#######################################
# @description Stop a named timer and log how long it ran. The structured event
#   carries the timer name and its elapsed milliseconds as fields of their own,
#   so a log aggregator can chart a step without parsing the message.
# @arg $1 string Timer name
# @arg $2 string Level to log the duration at, default is `info`
# @set DYBATPHO_TIMER_LAST_MS number Elapsed milliseconds of this timer
# @set __dybatpho_log_timer
# @stderr The duration message, at the requested level
# @exitcode 1 The requested level is not a valid log level
# @tip The elapsed time is published in `DYBATPHO_TIMER_LAST_MS` rather than printed, because capturing output with `$(...)` would run the call in a subshell and throw the measurement away
#######################################
function dybatpho::timer_end {
  local name
  dybatpho::expect_args name -- "$@"
  local level="${2:-info}"
  dybatpho::validate_log_level "${level}" || return 1
  level="$(dybatpho::lower "${level}")"

  local started="${__dybatpho_log_timer[${name}]-}"
  [[ -n "${started}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Timer '${name}' was never started"
  local elapsed=$(($(__dybatpho_log_now_ms) - started))
  if ((elapsed < 0)); then
    elapsed=0
  fi
  unset "__dybatpho_log_timer[${name}]"
  DYBATPHO_TIMER_LAST_MS="${elapsed}"
  export DYBATPHO_TIMER_LAST_MS

  local extra_fields
  printf -v extra_fields ',"timer":"%s","elapsed_ms":%s' \
    "$(__dybatpho_log_json_escape "${name}")" "${elapsed}"
  local message
  message="$(__dybatpho_log_text logging.timer_end "${name} took ${elapsed}ms" \
    name="${name}" elapsed_ms="${elapsed}")"
  __dybatpho_log_inspect "${level}" "TIMER ⏳      " "${message}" 0 "" "${extra_fields}"
}

#######################################
# @description Run a command while a spinner reports that it is still going,
#   then pass its exit code back unchanged.
#
#   The command runs in the foreground of the calling shell, so it keeps stdin,
#   its output goes where it would anyway, and its exit code is the one this
#   function returns. Only the spinner runs in the background, and it is torn
#   down before this returns whether the command succeeded or failed.
#
#   Without a terminal on stderr -- in CI, or with output redirected -- there is
#   nothing to animate, so the message is logged once at `info` instead and the
#   command runs as usual.
# @example
#   dybatpho::spinner "Downloading dependencies" -- npm ci
#   dybatpho::spinner "Building" -- make -j4 || dybatpho::die "build failed"
#
# @arg $1 string Message shown beside the spinner
# @arg $2 string The literal `--`
# @arg $@ string Command and arguments to run
# @env DYBATPHO_SPINNER string `never` to always skip the animation, `always` to force it
# @env DYBATPHO_SPINNER_INTERVAL string Seconds between frames
# @env DYBATPHO_SPINNER_FRAMES string Space-separated frames to cycle through
# @stderr The animation while the command runs, then the line is erased
# @exitcode The exit code of the command
# @tip Registered secrets are redacted in the message before it is drawn
#######################################
function dybatpho::spinner {
  local message
  dybatpho::expect_args message -- "$@"
  shift
  [[ "${1-}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected -- between the message and the command"
  shift
  (($# > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected a command after --"

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  local animate=false
  case "${DYBATPHO_SPINNER}" in
    never) ;;
    always) animate=true ;;
    *)
      if [[ -t 2 ]] && dybatpho::compare_log_level info; then
        animate=true
      fi
      ;;
  esac

  local spinner_pid=""
  if [[ "${animate}" == true ]]; then
    __dybatpho_log_spin "${message}" &
    spinner_pid=$!
  else
    __dybatpho_log_inspect info "SPIN ⏳       " "${message}"
  fi

  local started status=0
  started="$(__dybatpho_log_now_ms)"
  "$@" || status=$?

  if [[ -n "${spinner_pid}" ]]; then
    kill "${spinner_pid}" 2> /dev/null || true
    wait "${spinner_pid}" 2> /dev/null || true
    # Erase the frame so the next line starts on a clean column, whether the
    # command printed anything of its own or not.
    printf '\r\033[K' >&2
  fi

  local elapsed=$(($(__dybatpho_log_now_ms) - started))
  if ((elapsed < 0)); then
    elapsed=0
  fi
  local extra_fields
  printf -v extra_fields ',"elapsed_ms":%s,"exit_code":%s' "${elapsed}" "${status}"
  __dybatpho_log_inspect debug "SPIN ⏳       " \
    "${message} finished in ${elapsed}ms with exit code ${status}" 0 "" "${extra_fields}"

  return "${status}"
}

#######################################
# @description Enable Bash tracing with dybatpho formatting.
# @noargs
# @env LOG_LEVEL string Set to `trace` to emit the trace start/end messages
#######################################
function dybatpho::start_trace {
  # kcov(disabled) - replacing PS4 stops the coverage tracer
  __dybatpho_log_inspect trace "TRACE ⚡       " "Start tracing"
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
  __dybatpho_log_inspect trace "TRACE ⚡      " "End tracing"
  # kcov(enabled)
}
