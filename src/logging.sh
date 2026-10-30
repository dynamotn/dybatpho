# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it keeps its declarations with the functions they
# describe; it uses `eval`, which is how the spec engine builds a parser.
# dyshellint disable=BSG050,BSG011,BSG033,BSG040
# The library returns its values on stdout, so its own functions are called inside `$(...)` by design. Every call
# here that can stop the script was reviewed: it is fixed, or listed with its reason in test/die-in-substitution.allow,
# which test/conventions.bats enforces.
# dyshellint disable=BSG047 # reviewed in test/die-in-substitution.allow
# A `$(...)` inside an argument passes a value on, the way this code calls the library; the inner command prints its
# own diagnostic when it fails, so a separate assignment for each would only add lines.
# shellcheck disable=SC2312 # values are passed on through $(...)
# @file logging.sh
# @brief Utilities for logging to stdout/stderr
# @namespace dybatpho
# @description
#   This module contains functions to log messages to stdout/stderr. Every
#   structured (JSON) log event is enriched with a request ID, hostname, PID,
#   and duration since the process started. Structured events can also be
#   appended to a rotating log file at an independent verbosity level.
# @see
#   - `example/logging_demo.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# Logging is configured through `DYBATPHO_LOG_*` variables. Each one falls back
# to its unprefixed name (`LOG_LEVEL`, `LOG_FORMAT`, ...) when the prefixed one is
# unset or empty, so scripts written for earlier releases keep working, and the
# prefixed name wins when both are set. None of them is assigned or exported
# here: a value is read where it is used, so a variable the script sets after
# sourcing the library still counts, and a child process inherits only what the
# caller chose to export.
# @env DYBATPHO_LOG_LEVEL string [default: info] Runtime log level for all messages
#   (`trace|debug|info|warn|error|fatal`); falls back to `LOG_LEVEL`
# @env DYBATPHO_LOG_FORMAT string [default: text] Log output format (`text|json`); falls back to `LOG_FORMAT`
# @env NO_COLOR string Disable ANSI colors when set to a non-empty value. Read, never written
# @env DYBATPHO_LOG_REQUEST_ID string Correlation ID attached to every structured log event; falls back to
#   `LOG_REQUEST_ID`. Generated automatically, and kept unexported, when both are empty
# @env DYBATPHO_LOG_FILE string? Path to append structured JSON log lines to, independent of the log format; falls
#   back to `LOG_FILE`
# @env DYBATPHO_LOG_FILE_LEVEL string [default: ${DYBATPHO_LOG_LEVEL}] Verbosity threshold applied only to the log
#   file; falls back to `LOG_FILE_LEVEL`
# @env DYBATPHO_LOG_FILE_MAX_BYTES number [default: 10485760] Rotate the log file once it reaches this size in bytes,
#   10 MiB by default. `0` disables rotation; falls back to `LOG_FILE_MAX_BYTES`
# @env DYBATPHO_LOG_FILE_MAX_BACKUPS number [default: 5] Number of rotated log file backups to keep; falls back to
#   `LOG_FILE_MAX_BACKUPS`
# @env DYBATPHO_SPINNER string When `dybatpho::spinner` animates (`auto|always|never`). `auto` animates only on a
#   terminal.
#   Default `auto`
DYBATPHO_SPINNER="${DYBATPHO_SPINNER:-auto}"
# @env DYBATPHO_SPINNER_INTERVAL string [default: 0.1] Seconds between spinner frames
DYBATPHO_SPINNER_INTERVAL="${DYBATPHO_SPINNER_INTERVAL:-0.1}"
# @env DYBATPHO_SPINNER_FRAMES string Space-separated frames the spinner cycles through
DYBATPHO_SPINNER_FRAMES="${DYBATPHO_SPINNER_FRAMES:-⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏}"
# @env DYBATPHO_TIMER_LAST_MS number Elapsed milliseconds reported by the last `dybatpho::timer_end`
DYBATPHO_TIMER_LAST_MS="${DYBATPHO_TIMER_LAST_MS:-0}"

# Fields attached to every structured log event, keyed by field name.
declare -gA __dybatpho_log_context_values=()
# Field names in the order they were first added, so events stay comparable.
declare -ga __dybatpho_log_context_keys=()
# Start time in milliseconds of each running timer, keyed by timer name.
declare -gA __dybatpho_log_timer=()
# Field names a structured event already carries, which a context field may not shadow.
declare -g __dybatpho_log_reserved_fields=" timestamp level source message request_id hostname pid duration_ms "

#######################################
# @description Mask registered secrets in a variable before it is written
#   anywhere. It does nothing until a secret has been registered, so output
#   costs nothing extra in the usual case, and nothing when the masking
#   internals are missing, as in a child shell that inherited only the exported
#   functions. Every writer in the library goes through here, so the hook
#   contract lives in one place.
# @arg $1 string Name of the variable to mask in place
# @set The named variable
# @internal
#######################################
function __dybatpho_log_redact {
  ((${DYBATPHO_SECRET_COUNT:-0} > 0)) || return 0
  declare -F __dybatpho_secret_mask_var > /dev/null || return 0
  __dybatpho_secret_mask_var "$1"
}

#######################################
# @description Log a message to stdout or stderr, optionally with ANSI color.
# @env DYBATPHO_LOG_LEVEL string Runtime log level of the current script, or `LOG_LEVEL`
# @arg $1 string Log level of message
# @arg $2 string Message
# @arg $3 string `stderr` to write to stderr, otherwise stdout
# @arg $4 string ANSI escape color code
# @stdout Show the formatted message when the level passes filtering and $3 is not `stderr`
# @stderr Show the formatted message when the level passes filtering and $3 is `stderr`
# @internal
#######################################
function __dybatpho_log {
  local show_log_level="$1"
  local msg="$2"
  local out="${3:-stdout}"
  local color="${4-}"
  # A `case` rather than a table built on every line, and one that cannot trip
  # `set -u` on a level it does not know: `INFO` used to abort the script here
  # before the validation below could say what was wrong with it.
  if [[ -z "${color}" ]]; then
    case "${show_log_level,,}" in
      trace) color="0;37" ;;
      debug) color="0;36" ;;
      info) color="0;34" ;;
      warn) color="0;33" ;;
      error) color="1;31" ;;
      *) color="0;31" ;;
    esac
  fi

  # Redact registered secrets before anything reaches stdout or stderr.
  __dybatpho_log_redact msg

  # A bad level, the threshold checked first, is reported and fails (1); a
  # level that is merely filtered out returns quietly (0).
  local __dybatpho_log_rank __dybatpho_log_threshold
  local __dybatpho_log_runtime="${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}"
  __dybatpho_log_rank_into __dybatpho_log_threshold "${__dybatpho_log_runtime,,}" \
    || {
      dybatpho::validate_log_level "${__dybatpho_log_runtime}"
      return 1
    }
  __dybatpho_log_rank_into __dybatpho_log_rank "${show_log_level,,}" \
    || {
      dybatpho::validate_log_level "${show_log_level}"
      return 1
    }
  ((__dybatpho_log_rank <= __dybatpho_log_threshold)) || return 0

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
  # The stream decides, not just `NO_COLOR`: a log redirected to a file used to
  # carry escape sequences into it, while a diff written beside it did not.
  local rendered
  if dybatpho::color_supported "${out}"; then
    printf -v rendered '\033[%sm%s\033[0m\n' "${color}" "${msg}"
  else
    printf -v rendered '%s\n' "${msg}"
  fi

  if [[ "${out}" == "stderr" ]]; then
    printf '%s' "${rendered}" >&2
  else
    printf '%s' "${rendered}"
  fi
}

#######################################
# @description Escape a string for use as a JSON string value, into a variable.
#   This is the library's one JSON string escaper: `json`, `notification`,
#   `doctor`, `config` and the generated CLI schema all go through it.
#   JSON forbids a raw control character inside a string, and only five of them
#   have a short escape. Leaving the rest alone produced a line no parser would
#   read: a message carrying an ANSI colour sequence -- which is what logging
#   the output of any coloured command gives you -- made the whole event
#   invalid, and a log shipper drops an invalid line without saying so.
#   Anything with no short escape goes out as `\u00XX`, and so does DEL.
# @arg $1 string Name of the variable receiving the escaped text
# @arg $2 string Input text
# @set The named variable, without surrounding quotes
# @internal
#######################################
function __dybatpho_log_json_escape_into {
  local -n __dybatpho_log_json_escape_out="$1"
  local __dybatpho_log_json_value="${2-}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//\\/\\\\}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//\"/\\\"}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//$'\n'/\\n}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//$'\r'/\\r}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//$'\t'/\\t}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//$'\b'/\\b}"
  __dybatpho_log_json_value="${__dybatpho_log_json_value//$'\f'/\\f}"
  # The walk below costs a pass per character, so it runs only when something
  # is left that the substitutions above could not spell.
  if [[ "${__dybatpho_log_json_value}" == *[[:cntrl:]]* ]]; then
    local __dybatpho_log_json_walked="" __dybatpho_log_json_index
    local __dybatpho_log_json_char __dybatpho_log_json_code
    for ((__dybatpho_log_json_index = 0;  \
    __dybatpho_log_json_index < ${#__dybatpho_log_json_value};  \
    __dybatpho_log_json_index++)); do
      __dybatpho_log_json_char="${__dybatpho_log_json_value:__dybatpho_log_json_index:1}"
      # The code point decides, not a bracket range: a range is resolved by the
      # locale's collation and a multi-byte character can fall inside one.
      printf -v __dybatpho_log_json_code '%d' "'${__dybatpho_log_json_char}"
      if ((__dybatpho_log_json_code < 32 || __dybatpho_log_json_code == 127)); then
        printf -v __dybatpho_log_json_walked '%s\\u%04x' \
          "${__dybatpho_log_json_walked}" "${__dybatpho_log_json_code}"
      else
        __dybatpho_log_json_walked+="${__dybatpho_log_json_char}"
      fi
    done
    __dybatpho_log_json_value="${__dybatpho_log_json_walked}"
  fi
  __dybatpho_log_json_escape_out="${__dybatpho_log_json_value}"
}

#######################################
# @description Escape a string for use as a JSON string value.
#   The printing form of `__dybatpho_log_json_escape_into`, for a caller that
#   writes the result straight out.
# @arg $1 string Input text
# @stdout JSON-escaped text without surrounding quotes
# @internal
#######################################
function __dybatpho_log_json_escape {
  local escaped
  __dybatpho_log_json_escape_into escaped "${1-}"
  printf '%s' "${escaped}"
}

#######################################
# @description Return an RFC 3339 timestamp for a log event.
# @noargs
# @stdout Current timestamp
# @internal
#######################################
function __dybatpho_log_timestamp {
  local timestamp
  __dybatpho_log_timestamp_into timestamp
  printf '%s\n' "${timestamp}"
}

#######################################
# @description Tell whether the `date` or `busybox` first on `PATH` is a
#   stand-in rather than the system's: a shell function of that name, or a
#   command under the mock directory of `dybatpho::mock_time`, under a Bats
#   test directory, or under the temporary directory, which is where every
#   mock this library knows of is written.
# @arg $1 string Optional: `date` or `busybox` to ask about that command alone
# @exitcode 0 A stand-in is on `PATH`
# @exitcode 1 Both commands are the system's, or missing
# @internal
#######################################
function __dybatpho_log_date_is_stand_in {
  local -a __dybatpho_log_ts_names=(date busybox)
  [[ -z "${1-}" ]] || __dybatpho_log_ts_names=("$1")
  local __dybatpho_log_ts_cmd __dybatpho_log_ts_dir
  # A shell function named like the command is the oldest way to stand in.
  for __dybatpho_log_ts_cmd in "${__dybatpho_log_ts_names[@]}"; do
    declare -F "${__dybatpho_log_ts_cmd}" > /dev/null && return 0
  done
  for __dybatpho_log_ts_cmd in "${__dybatpho_log_ts_names[@]}"; do
    __dybatpho_log_ts_cmd="${BASH_CMDS[${__dybatpho_log_ts_cmd}]-}"
    [[ -n "${__dybatpho_log_ts_cmd}" ]] || continue
    for __dybatpho_log_ts_dir in "${DYBATPHO_TEST_MOCK_DIR-}" "${BATS_MOCK_BINDIR-}" \
      "${BATS_TEST_TMPDIR-}" "${TMPDIR:-/tmp}"; do
      [[ -n "${__dybatpho_log_ts_dir}" ]] || continue
      [[ "${__dybatpho_log_ts_cmd}" == "${__dybatpho_log_ts_dir%/}/"* ]] && return 0
    done
  done
  return 1
}

#######################################
# @description Store the builtin clock's RFC 3339 stamp in a variable.
#   `printf '%(...)T'` costs more the more the shell exports: every exported
#   function and variable is walked on each call, so with the whole library
#   loaded one stamp took about a millisecond. A stamp only changes once a
#   second, so where Bash has `EPOCHSECONDS` (5.0 and later) the rendered one
#   is kept, keyed by that second and by `TZ`, and reused until either moves.
# @arg $1 string Name of the variable receiving the timestamp
# @set The named variable
# @internal
#######################################
function __dybatpho_log_builtin_stamp_into {
  local -n __dybatpho_log_bs_out="$1"
  local __dybatpho_log_bs_now="${EPOCHSECONDS-}"
  if [[ -n "${__dybatpho_log_bs_now}" ]]; then
    local __dybatpho_log_bs_key="${__dybatpho_log_bs_now}|${TZ+set}|${TZ-}"
    if [[ "${__dybatpho_log_bs_key}" == "${__DYBATPHO_LOG_STAMP_KEY-}" ]]; then
      __dybatpho_log_bs_out="${__DYBATPHO_LOG_STAMP}"
      return 0
    fi
  else
    __dybatpho_log_bs_now=-1
  fi
  # `%z` has no colon form in strftime; the offset is the last five
  # characters and the colon goes in front of its minutes.
  printf -v __dybatpho_log_bs_out '%(%Y-%m-%dT%H:%M:%S%z)T' "${__dybatpho_log_bs_now}"
  __dybatpho_log_bs_out="${__dybatpho_log_bs_out:0:22}:${__dybatpho_log_bs_out:22}"
  if [[ "${__dybatpho_log_bs_now}" != "-1" ]]; then
    __DYBATPHO_LOG_STAMP_KEY="${__dybatpho_log_bs_key}"
    __DYBATPHO_LOG_STAMP="${__dybatpho_log_bs_out}"
  fi
}

#######################################
# @description Store an RFC 3339 timestamp for a log event in a variable.
#   The stamp comes from `printf '%(...)T'`, which reads the clock without
#   starting a process; that is the difference between a log line costing
#   microseconds and one costing several milliseconds, which on a chatty
#   script is most of its run time. A `date` that lives under a temporary
#   directory is a stand-in a caller put first on `PATH` on purpose --
#   `dybatpho::mock_time` freezes the clock that way, and a test may stub
#   `date` or `busybox` -- so that one keeps being asked, through the flags
#   its flavour accepts. What is remembered is which `date` this is, keyed by
#   where `busybox` and `date` resolve, so the `date --version` probe runs once
#   rather than on every line.
# @arg $1 string Name of the variable receiving the timestamp
# @set The named variable
# @internal
#######################################
function __dybatpho_log_timestamp_into {
  local -n __dybatpho_log_ts_out="$1"
  # A stand-in resolves to a file under one of the directories
  # `__dybatpho_log_date_is_stand_in` knows, so one can only be found when a
  # `PATH` entry lies under one of them. That is worked out once per `PATH`;
  # without such an entry, and without a function of either name, the clock is
  # the builtin's and no `PATH` search runs at all -- `hash busybox` searches
  # every entry on each call where busybox is missing, which cost more than the
  # stamp itself. Comparing the whole `PATH` on every line costs tens of
  # microseconds of its own, so a change is noticed the way Bash notices it:
  # assigning `PATH` empties the command hash table, and with it the marker
  # entry left there after the last look.
  local __dybatpho_log_ts_dirs="${DYBATPHO_TEST_MOCK_DIR-}|${BATS_MOCK_BINDIR-}|${BATS_TEST_TMPDIR-}|${TMPDIR:-/tmp}"
  if [[ -z "${BASH_CMDS[__dybatpho_log_ts_path]-}" ]] \
    || [[ "${__dybatpho_log_ts_dirs}" != "${__DYBATPHO_LOG_TS_DIRS-}" ]]; then
    __DYBATPHO_LOG_TS_WATCH=0
    local __dybatpho_log_ts_entry __dybatpho_log_ts_dir
    local -a __dybatpho_log_ts_entries=()
    IFS=':' read -r -a __dybatpho_log_ts_entries <<< "${PATH}"
    for __dybatpho_log_ts_entry in ${__dybatpho_log_ts_entries[@]+"${__dybatpho_log_ts_entries[@]}"}; do
      for __dybatpho_log_ts_dir in "${DYBATPHO_TEST_MOCK_DIR-}" "${BATS_MOCK_BINDIR-}" \
        "${BATS_TEST_TMPDIR-}" "${TMPDIR:-/tmp}"; do
        [[ -n "${__dybatpho_log_ts_dir}" ]] || continue
        [[ "${__dybatpho_log_ts_entry%/}/" == "${__dybatpho_log_ts_dir%/}/"* ]] && __DYBATPHO_LOG_TS_WATCH=1
      done
    done
    __DYBATPHO_LOG_TS_DIRS="${__dybatpho_log_ts_dirs}"
    # Without `hashall` the entry does not stick, and every line looks again.
    BASH_CMDS[__dybatpho_log_ts_path]=/dev/null
  fi
  if ((__DYBATPHO_LOG_TS_WATCH == 0)) \
    && ! { declare -F date || declare -F busybox; } > /dev/null; then
    __dybatpho_log_builtin_stamp_into __dybatpho_log_ts_out
    return 0
  fi
  # `hash` fills BASH_CMDS without starting a process, and an empty entry is
  # what a command missing from PATH leaves.
  hash busybox 2> /dev/null || true
  hash date 2> /dev/null || true
  local __dybatpho_log_ts_key="${PATH}|${BASH_CMDS[busybox]-}|${BASH_CMDS[date]-}"
  if [[ "${__dybatpho_log_ts_key}" != "${__DYBATPHO_LOG_TS_KEY-}" ]]; then
    if __dybatpho_log_date_is_stand_in; then
      # A `date` stand-in is asked itself even where busybox is installed:
      # it is what `dybatpho::mock_time` and the test mocks put on `PATH`.
      if [[ -n "${BASH_CMDS[busybox]-}" ]] && ! __dybatpho_log_date_is_stand_in date; then
        __DYBATPHO_LOG_TS_FLAVOR=busybox
      elif date --version &> /dev/null; then
        __DYBATPHO_LOG_TS_FLAVOR=gnu
      else
        __DYBATPHO_LOG_TS_FLAVOR=portable
      fi
    else
      __DYBATPHO_LOG_TS_FLAVOR=builtin
    fi
    __DYBATPHO_LOG_TS_KEY="${__dybatpho_log_ts_key}"
  fi
  case "${__DYBATPHO_LOG_TS_FLAVOR}" in
    builtin) __dybatpho_log_builtin_stamp_into __dybatpho_log_ts_out ;;
    busybox) __dybatpho_log_ts_out="$(busybox date +%Y-%m-%dT%H:%M:%S%:z)" ;;
    gnu) __dybatpho_log_ts_out="$(date --rfc-3339="seconds")" ;;
    *) __dybatpho_log_ts_out="$(date +%Y-%m-%dT%H:%M:%S%z)" ;;
  esac
}

#######################################
# @description
#   Return the current time in milliseconds since the epoch, using the most precise portable source available.
# @noargs
# @stdout Current time in milliseconds
# @internal
#######################################
function __dybatpho_log_now_ms {
  local now_ms
  __dybatpho_log_now_ms_into now_ms
  printf '%s' "${now_ms}"
}

#######################################
# @description Store the current time in milliseconds since the epoch in a
#   variable, without starting a process when `EPOCHREALTIME` is available.
# @arg $1 string Name of the variable receiving the time
# @set The named variable
# @internal
#######################################
function __dybatpho_log_now_ms_into {
  local -n __dybatpho_log_now_out="$1"
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    # Bash writes the fraction with the locale's decimal separator, so under
    # `de_DE` the value reads `1792325856,140977`; either separator splits it.
    local __dybatpho_log_now_whole="${EPOCHREALTIME%%[.,]*}" __dybatpho_log_now_frac="${EPOCHREALTIME#*[.,]}"
    __dybatpho_log_now_out=$((__dybatpho_log_now_whole * 1000 + 10#${__dybatpho_log_now_frac:0:3}))
    return 0
  fi
  local __dybatpho_log_now_ns
  if __dybatpho_log_now_ns=$(date +%s%N 2> /dev/null) && [[ "${__dybatpho_log_now_ns}" =~ ^[0-9]+$ ]]; then
    __dybatpho_log_now_out=$((__dybatpho_log_now_ns / 1000000))
    return 0
  fi
  # kcov(disabled) - only reachable without EPOCHREALTIME or GNU/busybox date
  __dybatpho_log_now_out=$((SECONDS * 1000))
  # kcov(enabled)
}

# Captured once per process so structured log events can report elapsed duration.
DYBATPHO_LOG_START_MS="$(__dybatpho_log_now_ms)"

#######################################
# @description Return the elapsed time since the process started, for structured log events.
# @noargs
# @stdout Elapsed time in milliseconds
# @internal
#######################################
function __dybatpho_log_duration_ms {
  local log_now_ms
  __dybatpho_log_now_ms_into log_now_ms
  printf '%s' "$((log_now_ms - DYBATPHO_LOG_START_MS))"
}

#######################################
# @description
#   Return the correlation ID attached to every structured log event, generating and caching one when both
#   `DYBATPHO_LOG_REQUEST_ID` and `LOG_REQUEST_ID` are empty.
#   The generated ID is kept in the current shell and not exported: a child
#   process shares it only when the caller exports `DYBATPHO_LOG_REQUEST_ID`.
# @noargs
# @set DYBATPHO_LOG_REQUEST_ID string Generated correlation ID, when none was set
# @stdout Correlation ID
# @internal
#######################################
function __dybatpho_log_request_id {
  if [[ -z "${DYBATPHO_LOG_REQUEST_ID:-${LOG_REQUEST_ID:-}}" ]]; then
    if dybatpho::is command uuidgen; then
      DYBATPHO_LOG_REQUEST_ID="$(uuidgen)" # kcov(skip)
    else
      local log_now_ms
      log_now_ms=$(__dybatpho_log_now_ms)
      DYBATPHO_LOG_REQUEST_ID="$(printf '%s-%s-%s' "$$" "${log_now_ms}" "${RANDOM}${RANDOM}")"
    fi
  fi
  printf '%s' "${DYBATPHO_LOG_REQUEST_ID:-${LOG_REQUEST_ID:-}}"
}

#######################################
# @description
#   Return the current hostname attached to every structured log event, caching the result for the process lifetime.
# @noargs
# @stdout Hostname
# @env DYBATPHO_LOG_HOSTNAME string Hostname to log instead of the one `dybatpho::hostname` detects
# @internal
#######################################
function __dybatpho_log_hostname {
  if [[ -z "${DYBATPHO_LOG_HOSTNAME:-}" ]]; then
    # dyshellint disable=BSG084 # the hostname is only memoized; losing it with the subshell costs a second lookup
    DYBATPHO_LOG_HOSTNAME="$(dybatpho::hostname)"
  fi
  printf '%s' "${DYBATPHO_LOG_HOSTNAME}"
}

#######################################
# @description
#   Build one structured JSON log event enriched with request ID, hostname, PID, duration, and the fields registered
#   with `dybatpho::log_context`.
# @arg $1 string RFC 3339 timestamp
# @arg $2 string Log level
# @arg $3 string Source location
# @arg $4 string Message
# @arg $5 number Duration in milliseconds since the process started
# @arg $6 string Ready-made JSON fragment of extra fields, each one leading with its own comma
# @stdout One JSON object followed by a newline
# @internal
#######################################
function __dybatpho_log_json_event {
  local __dybatpho_log_event_line
  __dybatpho_log_json_event_into __dybatpho_log_event_line "$@"
  printf '%s' "${__dybatpho_log_event_line}"
}

#######################################
# @description Build one structured JSON log event, as `__dybatpho_log_json_event`
#   does, into a variable, so the file sink can count the bytes it appends.
# @arg $1 string Name of the variable receiving the event and its newline
# @arg $@ string The arguments of `__dybatpho_log_json_event`
# @set The named variable
# @internal
#######################################
function __dybatpho_log_json_event_into {
  local -n __dybatpho_log_event_out="$1"
  shift
  local timestamp="$1" level="$2" source="$3" message="$4" duration_ms="$5"
  local extra_fields="${6:-}"
  # Call these directly (not inside `$(...)`) so the caches they populate
  # persist in the current shell instead of being lost with a subshell.
  __dybatpho_log_request_id > /dev/null
  __dybatpho_log_hostname > /dev/null
  local event_format='{"timestamp":"%s","level":"%s","source":"%s","message":"%s","request_id":"%s",'
  event_format+='"hostname":"%s","pid":%s,"duration_ms":%s%s%s}\n'
  # shellcheck disable=SC2059 # the format is built above, not taken from input
  local log_context_json=""
  if ((${#__dybatpho_log_context_keys[@]} > 0)); then
    log_context_json=$(__dybatpho_log_context_json)
  fi
  local log_json_escape
  __dybatpho_log_json_escape_into log_json_escape "${message}"
  local log_json_escape_2
  __dybatpho_log_json_escape_into log_json_escape_2 "${timestamp}"
  local log_json_escape_3
  __dybatpho_log_json_escape_into log_json_escape_3 "${DYBATPHO_LOG_HOSTNAME}"
  local log_json_escape_4
  __dybatpho_log_json_escape_into log_json_escape_4 "${source}"
  local log_json_escape_5
  __dybatpho_log_json_escape_into log_json_escape_5 "${DYBATPHO_LOG_REQUEST_ID:-${LOG_REQUEST_ID:-}}"
  local log_json_escape_6
  __dybatpho_log_json_escape_into log_json_escape_6 "${level}"
  # shellcheck disable=SC2059 # the format is built above, not taken from input
  printf -v __dybatpho_log_event_out "${event_format}" \
    "${log_json_escape_2}" \
    "${log_json_escape_6}" \
    "${log_json_escape_4}" \
    "${log_json_escape}" \
    "${log_json_escape_5}" \
    "${log_json_escape_3}" \
    "$$" \
    "${duration_ms}" \
    "${log_context_json}" \
    "${extra_fields}"
}

#######################################
# @description
#   Rotate a log file in place once it reaches a size threshold, keeping a bounded number of numbered backups.
# @arg $1 string Log file path
# @arg $2 number Maximum size in bytes before rotating, `0` disables rotation
# @arg $3 number Number of rotated backups to keep
# @internal
#######################################
function __dybatpho_log_rotate_file {
  local file="$1" max_bytes="$2" max_backups="$3"
  [[ -f "${file}" ]] || return 0
  ((max_bytes > 0)) || return 0

  # The size is counted as the file sink appends, rather than asked of `wc` on
  # every line, which started a process per log line. It is measured for real
  # when the file changes and before rotating, so a stale count never rotates.
  if [[ "${__DYBATPHO_LOG_FILE_SIZE_OF-}" != "${file}" ]] || ((__DYBATPHO_LOG_FILE_SIZE >= max_bytes)); then
    __DYBATPHO_LOG_FILE_SIZE=$(wc -c < "${file}" 2> /dev/null || echo 0)
    __DYBATPHO_LOG_FILE_SIZE_OF="${file}"
  fi
  ((__DYBATPHO_LOG_FILE_SIZE >= max_bytes)) || return 0
  __DYBATPHO_LOG_FILE_SIZE=0

  if ((max_backups <= 0)); then
    : > "${file}"
    return 0
  fi

  local i
  for ((i = max_backups - 1; i >= 1; i--)); do
    [[ -f "${file}.${i}" ]] && mv -f -- "${file}.${i}" "${file}.$((i + 1))"
  done
  mv -f -- "${file}" "${file}.1"
}

#######################################
# @description
#   Append a structured JSON log event to `DYBATPHO_LOG_FILE` when it passes `DYBATPHO_LOG_FILE_LEVEL` filtering,
#   rotating the file first when needed. Each setting falls back to its unprefixed name.
# @arg $1 string Log level
# @arg $2 string Source location
# @arg $3 string Message
# @env DYBATPHO_LOG_FILE string Destination file; no-op when empty
# @env DYBATPHO_LOG_FILE_LEVEL string Verbosity threshold applied independently of the log level
# @env DYBATPHO_LOG_FILE_MAX_BYTES number Rotation size threshold
# @env DYBATPHO_LOG_FILE_MAX_BACKUPS number Number of rotated backups to keep
# @internal
#######################################
function __dybatpho_log_write_file {
  local log_level="$1"
  local source="$2"
  local message="$3"
  local extra_fields="${4:-}"
  local log_file="${DYBATPHO_LOG_FILE:-${LOG_FILE:-}}"
  [[ -n "${log_file}" ]] || return 0
  local file_level="${DYBATPHO_LOG_FILE_LEVEL:-${LOG_FILE_LEVEL:-${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}}}"
  dybatpho::compare_log_level "${log_level}" "${file_level}" || return 0

  __dybatpho_log_redact message

  # What `dirname` answers, without starting it: a name with no slash lives in
  # the current directory, and one directly under `/` in the root.
  local log_dir="."
  if [[ "${log_file}" == */* ]]; then
    log_dir="${log_file%/*}"
    log_dir="${log_dir:-/}"
  fi
  [[ -d "${log_dir}" ]] || mkdir -p -- "${log_dir}" 2> /dev/null || return 0

  __dybatpho_log_rotate_file "${log_file}" "${DYBATPHO_LOG_FILE_MAX_BYTES:-${LOG_FILE_MAX_BYTES:-10485760}}" \
    "${DYBATPHO_LOG_FILE_MAX_BACKUPS:-${LOG_FILE_MAX_BACKUPS:-5}}"
  local log_now_ms log_timestamp
  __dybatpho_log_now_ms_into log_now_ms
  __dybatpho_log_timestamp_into log_timestamp
  local log_event
  __dybatpho_log_json_event_into log_event "${log_timestamp}" "${log_level}" "${source}" \
    "${message}" "$((log_now_ms - DYBATPHO_LOG_START_MS))" "${extra_fields}"
  printf '%s' "${log_event}" >> "${log_file}"
  __dybatpho_log_count_bytes "${log_file}" "${log_event}"
}

#######################################
# @description Add the bytes just appended to a log file to the size the
#   rotation check keeps for it. The count is in bytes whatever the locale, as
#   the threshold is.
# @arg $1 string Log file path
# @arg $2 string Text appended to it
# @set __DYBATPHO_LOG_FILE_SIZE
# @internal
#######################################
function __dybatpho_log_count_bytes {
  [[ "${__DYBATPHO_LOG_FILE_SIZE_OF-}" == "$1" ]] || return 0
  local LC_ALL=C
  __DYBATPHO_LOG_FILE_SIZE=$((__DYBATPHO_LOG_FILE_SIZE + ${#2}))
}

#######################################
# @description Log a diagnostic event as JSON when the log format is `json`.
# @arg $1 string Log level
# @arg $2 string Source location
# @arg $3 string Message
# @arg $4 string Ready-made JSON fragment of extra fields, each one leading with its own comma
# @internal
#######################################
function __dybatpho_log_structured {
  local log_level="$1"
  local source="$2"
  local message="$3"
  local extra_fields="${4:-}"
  local timestamp
  dybatpho::compare_log_level "${log_level}" || return 0
  __dybatpho_log_timestamp_into timestamp

  __dybatpho_log_redact message

  local log_now_ms
  __dybatpho_log_now_ms_into log_now_ms
  __dybatpho_log_json_event "${timestamp}" "${log_level}" "${source}" "${message}" \
    "$((log_now_ms - DYBATPHO_LOG_START_MS))" "${extra_fields}" >&2
}

#######################################
# @description Return success unless a line at this level is certain to be
#   dropped by both the terminal threshold and the log file. It prints nothing and
#   answers "wanted" whenever a level it reads is not valid, so the full path
#   still reports the bad value exactly as before.
# @arg $1 string Level of the line
# @exitcode 0 Some destination may take the line, or a level is not valid
# @exitcode 1 No destination takes the line
# @internal
#######################################
function __dybatpho_log_wanted {
  local level threshold runtime_level="${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}"
  __dybatpho_log_rank_into level "${1,,}" || return 0
  __dybatpho_log_rank_into threshold "${runtime_level,,}" || return 0
  ((level <= threshold)) && return 0
  [[ -n "${DYBATPHO_LOG_FILE:-${LOG_FILE:-}}" ]] || return 1
  local file_threshold="${DYBATPHO_LOG_FILE_LEVEL:-${LOG_FILE_LEVEL:-${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}}}"
  __dybatpho_log_rank_into threshold "${file_threshold,,}" || return 0
  ((level <= threshold))
}

#######################################
# @description Store the rank of a lowercase log level, `fatal` 0 up to
#   `trace` 5, so that a level is shown when its rank is at most the
#   threshold's. A `case` costs a fraction of the table it replaces, which was
#   built afresh on every log line.
# @arg $1 string Name of the variable receiving the rank
# @arg $2 string Lowercase log level
# @set The named variable
# @exitcode 0 The level is known
# @exitcode 1 It is not; the variable is left alone
# @internal
#######################################
function __dybatpho_log_rank_into {
  local -n __dybatpho_log_rank_out="$1"
  case "${2-}" in
    trace) __dybatpho_log_rank_out=5 ;;
    debug) __dybatpho_log_rank_out=4 ;;
    info) __dybatpho_log_rank_out=3 ;;
    warn) __dybatpho_log_rank_out=2 ;;
    error) __dybatpho_log_rank_out=1 ;;
    fatal) __dybatpho_log_rank_out=0 ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Return success when a message level should be shown against a threshold.
# @arg $1 string Input log level
# @arg $2 string [default: ${DYBATPHO_LOG_LEVEL}] Threshold level to compare against
# @env DYBATPHO_LOG_LEVEL string Runtime threshold used to decide whether the message is emitted, when no explicit
#   threshold is given; falls back to `LOG_LEVEL`, then `info`
# @exitcode 0 The message level should be emitted
# @exitcode 1 The message level is filtered out
#######################################
function dybatpho::compare_log_level {
  local level="$1"
  local runtime_level="${2:-${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}}"
  level="${level,,}"
  runtime_level="${runtime_level,,}"

  # Spelled out rather than through `__dybatpho_log_rank_into`: this function is
  # exported, and a child shell inherits it without the module's internals.
  local runtime_level_num write_level_num
  case "${runtime_level}" in
    trace) runtime_level_num=5 ;;
    debug) runtime_level_num=4 ;;
    info) runtime_level_num=3 ;;
    warn) runtime_level_num=2 ;;
    error) runtime_level_num=1 ;;
    fatal) runtime_level_num=0 ;;
    *)
      dybatpho::validate_log_level "${runtime_level}"
      return 1
      ;;
  esac
  case "${level}" in
    trace) write_level_num=5 ;;
    debug) write_level_num=4 ;;
    info) write_level_num=3 ;;
    warn) write_level_num=2 ;;
    error) write_level_num=1 ;;
    fatal) write_level_num=0 ;;
    *)
      dybatpho::validate_log_level "${level}"
      return 1
      ;;
  esac

  ((write_level_num <= runtime_level_num))
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
# @internal
#######################################
function __dybatpho_log_translate {
  local translated
  __dybatpho_log_translate_into translated "${1-}"
  printf '%s' "${translated}"
}

#######################################
# @description Translate a diagnostic into a variable: what
#   `__dybatpho_log_translate` does, without the subshell a `$(...)` costs on
#   every log line. Trailing newlines go, as the substitution dropped them.
# @arg $1 string Name of the variable receiving the text
# @arg $2 string English text of the diagnostic
# @set The named variable
# @internal
#######################################
function __dybatpho_log_translate_into {
  local -n __dybatpho_log_translate_out="$1"
  local __dybatpho_log_translate_text="${2-}"
  while [[ "${__dybatpho_log_translate_text}" == *$'\n' ]]; do
    __dybatpho_log_translate_text="${__dybatpho_log_translate_text%$'\n'}"
  done
  __dybatpho_log_translate_out="${__dybatpho_log_translate_text}"
  if declare -F __dybatpho_i18n_lookup > /dev/null \
    && dybatpho::is true "${DYBATPHO_I18N_TRANSLATE_LIBRARY:-false}"; then
    local __dybatpho_log_translate_found
    if __dybatpho_i18n_lookup __dybatpho_log_translate_found "${__dybatpho_log_translate_text}"; then
      __dybatpho_log_translate_out="${__dybatpho_log_translate_found}"
    fi
  fi
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
# @internal
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
# @internal
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
# @description
#   Log a structured diagnostic message with timestamp and call-site information. Also appends a JSON event to
#   `DYBATPHO_LOG_FILE` when configured, independently of `DYBATPHO_LOG_FORMAT`.
# @arg $1 string Log level
# @arg $2 string Rendered label for the log level
# @arg $3 string Message
# @arg $4 number Additional stack frames to skip when resolving the source location
# @arg $5 string ANSI escape color code
# @arg $6 string Ready-made JSON fragment of extra fields, each one leading with its own comma
# @env DYBATPHO_LOG_FILE string? File that receives a structured JSON event regardless of `DYBATPHO_LOG_FORMAT`
# @internal
#######################################
function __dybatpho_log_inspect {
  local log_level=$1
  # A line neither the terminal nor the log file will take stops here, before the
  # source lookup, the translation, the context and the timestamp, each of
  # which used to start a process for a line that was then thrown away.
  __dybatpho_log_wanted "${log_level}" || return 0
  local log_level_text=$2
  local message="${3:-}"
  local indicator="${4:-0}"
  local extra_fields="${6:-}"
  # 2 is total stacks from dybatpho::(info|fatal|...) to this function
  local magic_number=2
  local stack_total=$((indicator + magic_number))

  if [[ "${BASH_SOURCE:-}" = "" ]]; then
    indicator="bash:0" # kcov(skip)
  elif [[ "${#BASH_SOURCE[@]}" -gt "${stack_total}" ]]; then
    indicator="${BASH_SOURCE[${stack_total}]}:${BASH_LINENO[$((stack_total - 1))]}"
  else
    # This case for calling inline from `bash -c`
    indicator="bash:${BASH_LINENO[1]}" # kcov(skip)
  fi
  local color="${5:-}"
  # Only the message is translated here: the level label beside it is padded to
  # a fixed width for the column separators and must not change.
  __dybatpho_log_translate_into message "${message}"
  __dybatpho_log_write_file "${log_level}" "${indicator}" "${message}" "${extra_fields}"
  if [[ "${DYBATPHO_LOG_FORMAT:-${LOG_FORMAT:-text}}" == "json" ]]; then
    __dybatpho_log_structured "${log_level}" "${indicator}" "${message}" "${extra_fields}"
  else
    local log_context_text="" log_timestamp
    if ((${#__dybatpho_log_context_keys[@]} > 0)); then
      log_context_text=$(__dybatpho_log_context_text)
    fi
    __dybatpho_log_timestamp_into log_timestamp
    __dybatpho_log "${log_level}" \
      "${log_timestamp} ‖ ${log_level_text} ‖ ${indicator}: ${message}${log_context_text}" \
      stderr "${color}"
  fi
}

#######################################
# @description Return the effective terminal width used by boxed logging helpers.
# @noargs
# @stdout Terminal width, falling back to 80 columns
# @internal
#######################################
function __dybatpho_log_get_terminal_width {
  dybatpho::terminal_width 80
}

# Codepoint ranges that occupy no terminal column, as `start end` pairs in
# ascending order: nonspacing and enclosing marks, format characters such as the
# zero-width space, joiner and variation selectors (the soft hyphen excepted,
# which terminals draw), and the Hangul medial and final jamo. Generated from
# Unicode 16.0 general categories; this is the `wcwidth` convention terminals
# follow.
# kcov(disabled) - a range table: its lines are data, not commands
declare -ga __DYBATPHO_LOG_WIDTH_ZERO=(
  0x300 0x36F 0x483 0x489 0x591 0x5BD 0x5BF 0x5BF 0x5C1 0x5C2 0x5C4 0x5C5
  0x5C7 0x5C7 0x600 0x605 0x610 0x61A 0x61C 0x61C 0x64B 0x65F 0x670 0x670
  0x6D6 0x6DD 0x6DF 0x6E4 0x6E7 0x6E8 0x6EA 0x6ED 0x70F 0x70F 0x711 0x711
  0x730 0x74A 0x7A6 0x7B0 0x7EB 0x7F3 0x7FD 0x7FD 0x816 0x819 0x81B 0x823
  0x825 0x827 0x829 0x82D 0x859 0x85B 0x890 0x891 0x897 0x89F 0x8CA 0x902
  0x93A 0x93A 0x93C 0x93C 0x941 0x948 0x94D 0x94D 0x951 0x957 0x962 0x963
  0x981 0x981 0x9BC 0x9BC 0x9C1 0x9C4 0x9CD 0x9CD 0x9E2 0x9E3 0x9FE 0x9FE
  0xA01 0xA02 0xA3C 0xA3C 0xA41 0xA42 0xA47 0xA48 0xA4B 0xA4D 0xA51 0xA51
  0xA70 0xA71 0xA75 0xA75 0xA81 0xA82 0xABC 0xABC 0xAC1 0xAC5 0xAC7 0xAC8
  0xACD 0xACD 0xAE2 0xAE3 0xAFA 0xAFF 0xB01 0xB01 0xB3C 0xB3C 0xB3F 0xB3F
  0xB41 0xB44 0xB4D 0xB4D 0xB55 0xB56 0xB62 0xB63 0xB82 0xB82 0xBC0 0xBC0
  0xBCD 0xBCD 0xC00 0xC00 0xC04 0xC04 0xC3C 0xC3C 0xC3E 0xC40 0xC46 0xC48
  0xC4A 0xC4D 0xC55 0xC56 0xC62 0xC63 0xC81 0xC81 0xCBC 0xCBC 0xCBF 0xCBF
  0xCC6 0xCC6 0xCCC 0xCCD 0xCE2 0xCE3 0xD00 0xD01 0xD3B 0xD3C 0xD41 0xD44
  0xD4D 0xD4D 0xD62 0xD63 0xD81 0xD81 0xDCA 0xDCA 0xDD2 0xDD4 0xDD6 0xDD6
  0xE31 0xE31 0xE34 0xE3A 0xE47 0xE4E 0xEB1 0xEB1 0xEB4 0xEBC 0xEC8 0xECE
  0xF18 0xF19 0xF35 0xF35 0xF37 0xF37 0xF39 0xF39 0xF71 0xF7E 0xF80 0xF84
  0xF86 0xF87 0xF8D 0xF97 0xF99 0xFBC 0xFC6 0xFC6 0x102D 0x1030 0x1032 0x1037
  0x1039 0x103A 0x103D 0x103E 0x1058 0x1059 0x105E 0x1060 0x1071 0x1074
  0x1082 0x1082 0x1085 0x1086 0x108D 0x108D 0x109D 0x109D 0x1160 0x11FF
  0x135D 0x135F 0x1712 0x1714 0x1732 0x1733 0x1752 0x1753 0x1772 0x1773
  0x17B4 0x17B5 0x17B7 0x17BD 0x17C6 0x17C6 0x17C9 0x17D3 0x17DD 0x17DD
  0x180B 0x180F 0x1885 0x1886 0x18A9 0x18A9 0x1920 0x1922 0x1927 0x1928
  0x1932 0x1932 0x1939 0x193B 0x1A17 0x1A18 0x1A1B 0x1A1B 0x1A56 0x1A56
  0x1A58 0x1A5E 0x1A60 0x1A60 0x1A62 0x1A62 0x1A65 0x1A6C 0x1A73 0x1A7C
  0x1A7F 0x1A7F 0x1AB0 0x1ACE 0x1B00 0x1B03 0x1B34 0x1B34 0x1B36 0x1B3A
  0x1B3C 0x1B3C 0x1B42 0x1B42 0x1B6B 0x1B73 0x1B80 0x1B81 0x1BA2 0x1BA5
  0x1BA8 0x1BA9 0x1BAB 0x1BAD 0x1BE6 0x1BE6 0x1BE8 0x1BE9 0x1BED 0x1BED
  0x1BEF 0x1BF1 0x1C2C 0x1C33 0x1C36 0x1C37 0x1CD0 0x1CD2 0x1CD4 0x1CE0
  0x1CE2 0x1CE8 0x1CED 0x1CED 0x1CF4 0x1CF4 0x1CF8 0x1CF9 0x1DC0 0x1DFF
  0x200B 0x200F 0x202A 0x202E 0x2060 0x2064 0x2066 0x206F 0x20D0 0x20F0
  0x2CEF 0x2CF1 0x2D7F 0x2D7F 0x2DE0 0x2DFF 0x302A 0x302D 0x3099 0x309A
  0xA66F 0xA672 0xA674 0xA67D 0xA69E 0xA69F 0xA6F0 0xA6F1 0xA802 0xA802
  0xA806 0xA806 0xA80B 0xA80B 0xA825 0xA826 0xA82C 0xA82C 0xA8C4 0xA8C5
  0xA8E0 0xA8F1 0xA8FF 0xA8FF 0xA926 0xA92D 0xA947 0xA951 0xA980 0xA982
  0xA9B3 0xA9B3 0xA9B6 0xA9B9 0xA9BC 0xA9BD 0xA9E5 0xA9E5 0xAA29 0xAA2E
  0xAA31 0xAA32 0xAA35 0xAA36 0xAA43 0xAA43 0xAA4C 0xAA4C 0xAA7C 0xAA7C
  0xAAB0 0xAAB0 0xAAB2 0xAAB4 0xAAB7 0xAAB8 0xAABE 0xAABF 0xAAC1 0xAAC1
  0xAAEC 0xAAED 0xAAF6 0xAAF6 0xABE5 0xABE5 0xABE8 0xABE8 0xABED 0xABED
  0xFB1E 0xFB1E 0xFE00 0xFE0F 0xFE20 0xFE2F 0xFEFF 0xFEFF 0xFFF9 0xFFFB
  0x101FD 0x101FD 0x102E0 0x102E0 0x10376 0x1037A 0x10A01 0x10A03
  0x10A05 0x10A06 0x10A0C 0x10A0F 0x10A38 0x10A3A 0x10A3F 0x10A3F
  0x10AE5 0x10AE6 0x10D24 0x10D27 0x10D69 0x10D6D 0x10EAB 0x10EAC
  0x10EFC 0x10EFF 0x10F46 0x10F50 0x10F82 0x10F85 0x11001 0x11001
  0x11038 0x11046 0x11070 0x11070 0x11073 0x11074 0x1107F 0x11081
  0x110B3 0x110B6 0x110B9 0x110BA 0x110BD 0x110BD 0x110C2 0x110C2
  0x110CD 0x110CD 0x11100 0x11102 0x11127 0x1112B 0x1112D 0x11134
  0x11173 0x11173 0x11180 0x11181 0x111B6 0x111BE 0x111C9 0x111CC
  0x111CF 0x111CF 0x1122F 0x11231 0x11234 0x11234 0x11236 0x11237
  0x1123E 0x1123E 0x11241 0x11241 0x112DF 0x112DF 0x112E3 0x112EA
  0x11300 0x11301 0x1133B 0x1133C 0x11340 0x11340 0x11366 0x1136C
  0x11370 0x11374 0x113BB 0x113C0 0x113CE 0x113CE 0x113D0 0x113D0
  0x113D2 0x113D2 0x113E1 0x113E2 0x11438 0x1143F 0x11442 0x11444
  0x11446 0x11446 0x1145E 0x1145E 0x114B3 0x114B8 0x114BA 0x114BA
  0x114BF 0x114C0 0x114C2 0x114C3 0x115B2 0x115B5 0x115BC 0x115BD
  0x115BF 0x115C0 0x115DC 0x115DD 0x11633 0x1163A 0x1163D 0x1163D
  0x1163F 0x11640 0x116AB 0x116AB 0x116AD 0x116AD 0x116B0 0x116B5
  0x116B7 0x116B7 0x1171D 0x1171D 0x1171F 0x1171F 0x11722 0x11725
  0x11727 0x1172B 0x1182F 0x11837 0x11839 0x1183A 0x1193B 0x1193C
  0x1193E 0x1193E 0x11943 0x11943 0x119D4 0x119D7 0x119DA 0x119DB
  0x119E0 0x119E0 0x11A01 0x11A0A 0x11A33 0x11A38 0x11A3B 0x11A3E
  0x11A47 0x11A47 0x11A51 0x11A56 0x11A59 0x11A5B 0x11A8A 0x11A96
  0x11A98 0x11A99 0x11C30 0x11C36 0x11C38 0x11C3D 0x11C3F 0x11C3F
  0x11C92 0x11CA7 0x11CAA 0x11CB0 0x11CB2 0x11CB3 0x11CB5 0x11CB6
  0x11D31 0x11D36 0x11D3A 0x11D3A 0x11D3C 0x11D3D 0x11D3F 0x11D45
  0x11D47 0x11D47 0x11D90 0x11D91 0x11D95 0x11D95 0x11D97 0x11D97
  0x11EF3 0x11EF4 0x11F00 0x11F01 0x11F36 0x11F3A 0x11F40 0x11F40
  0x11F42 0x11F42 0x11F5A 0x11F5A 0x13430 0x13440 0x13447 0x13455
  0x1611E 0x16129 0x1612D 0x1612F 0x16AF0 0x16AF4 0x16B30 0x16B36
  0x16F4F 0x16F4F 0x16F8F 0x16F92 0x16FE4 0x16FE4 0x1BC9D 0x1BC9E
  0x1BCA0 0x1BCA3 0x1CF00 0x1CF2D 0x1CF30 0x1CF46 0x1D167 0x1D169
  0x1D173 0x1D182 0x1D185 0x1D18B 0x1D1AA 0x1D1AD 0x1D242 0x1D244
  0x1DA00 0x1DA36 0x1DA3B 0x1DA6C 0x1DA75 0x1DA75 0x1DA84 0x1DA84
  0x1DA9B 0x1DA9F 0x1DAA1 0x1DAAF 0x1E000 0x1E006 0x1E008 0x1E018
  0x1E01B 0x1E021 0x1E023 0x1E024 0x1E026 0x1E02A 0x1E08F 0x1E08F
  0x1E130 0x1E136 0x1E2AE 0x1E2AE 0x1E2EC 0x1E2EF 0x1E4EC 0x1E4EF
  0x1E5EE 0x1E5EF 0x1E8D0 0x1E8D6 0x1E944 0x1E94A 0xE0001 0xE0001
  0xE0020 0xE007F 0xE0100 0xE01EF
)
# kcov(enabled)

# Codepoint ranges that occupy two terminal columns, as `start end` pairs in
# ascending order: every character Unicode 16.0 gives an East Asian Width of
# Wide or Fullwidth -- the CJK blocks, Hangul syllables, fullwidth forms and the
# emoji terminals draw double width.
# kcov(disabled) - a range table: its lines are data, not commands
declare -ga __DYBATPHO_LOG_WIDTH_WIDE=(
  0x1100 0x115F 0x231A 0x231B 0x2329 0x232A 0x23E9 0x23EC 0x23F0 0x23F0
  0x23F3 0x23F3 0x25FD 0x25FE 0x2614 0x2615 0x2630 0x2637 0x2648 0x2653
  0x267F 0x267F 0x268A 0x268F 0x2693 0x2693 0x26A1 0x26A1 0x26AA 0x26AB
  0x26BD 0x26BE 0x26C4 0x26C5 0x26CE 0x26CE 0x26D4 0x26D4 0x26EA 0x26EA
  0x26F2 0x26F3 0x26F5 0x26F5 0x26FA 0x26FA 0x26FD 0x26FD 0x2705 0x2705
  0x270A 0x270B 0x2728 0x2728 0x274C 0x274C 0x274E 0x274E 0x2753 0x2755
  0x2757 0x2757 0x2795 0x2797 0x27B0 0x27B0 0x27BF 0x27BF 0x2B1B 0x2B1C
  0x2B50 0x2B50 0x2B55 0x2B55 0x2E80 0x2E99 0x2E9B 0x2EF3 0x2F00 0x2FD5
  0x2FF0 0x3029 0x302E 0x303E 0x3041 0x3096 0x309B 0x30FF 0x3105 0x312F
  0x3131 0x318E 0x3190 0x31E5 0x31EF 0x321E 0x3220 0x3247 0x3250 0xA48C
  0xA490 0xA4C6 0xA960 0xA97C 0xAC00 0xD7A3 0xF900 0xFAFF 0xFE10 0xFE19
  0xFE30 0xFE52 0xFE54 0xFE66 0xFE68 0xFE6B 0xFF01 0xFF60 0xFFE0 0xFFE6
  0x16FE0 0x16FE3 0x16FF0 0x16FF1 0x17000 0x187F7 0x18800 0x18CD5
  0x18CFF 0x18D08 0x1AFF0 0x1AFF3 0x1AFF5 0x1AFFB 0x1AFFD 0x1AFFE
  0x1B000 0x1B122 0x1B132 0x1B132 0x1B150 0x1B152 0x1B155 0x1B155
  0x1B164 0x1B167 0x1B170 0x1B2FB 0x1D300 0x1D356 0x1D360 0x1D376
  0x1F004 0x1F004 0x1F0CF 0x1F0CF 0x1F18E 0x1F18E 0x1F191 0x1F19A
  0x1F200 0x1F202 0x1F210 0x1F23B 0x1F240 0x1F248 0x1F250 0x1F251
  0x1F260 0x1F265 0x1F300 0x1F320 0x1F32D 0x1F335 0x1F337 0x1F37C
  0x1F37E 0x1F393 0x1F3A0 0x1F3CA 0x1F3CF 0x1F3D3 0x1F3E0 0x1F3F0
  0x1F3F4 0x1F3F4 0x1F3F8 0x1F43E 0x1F440 0x1F440 0x1F442 0x1F4FC
  0x1F4FF 0x1F53D 0x1F54B 0x1F54E 0x1F550 0x1F567 0x1F57A 0x1F57A
  0x1F595 0x1F596 0x1F5A4 0x1F5A4 0x1F5FB 0x1F64F 0x1F680 0x1F6C5
  0x1F6CC 0x1F6CC 0x1F6D0 0x1F6D2 0x1F6D5 0x1F6D7 0x1F6DC 0x1F6DF
  0x1F6EB 0x1F6EC 0x1F6F4 0x1F6FC 0x1F7E0 0x1F7EB 0x1F7F0 0x1F7F0
  0x1F90C 0x1F93A 0x1F93C 0x1F945 0x1F947 0x1F9FF 0x1FA70 0x1FA7C
  0x1FA80 0x1FA89 0x1FA8F 0x1FAC6 0x1FACE 0x1FADC 0x1FADF 0x1FAE9
  0x1FAF0 0x1FAF8 0x20000 0x2FFFD 0x30000 0x3FFFD
)
# kcov(enabled)

# Width of every non-ASCII character measured so far, keyed by the character.
declare -gA __dybatpho_log_char_width=()
# Width of every non-ASCII string measured so far, keyed by the string. A screen
# redraws the same borders and titles every frame and a boxed log reuses its
# labels, so the second measurement is a lookup. The cache is dropped when it
# grows past `__DYBATPHO_LOG_WIDTH_CACHE_MAX` entries, so a long run that logs
# endless distinct messages does not grow without bound.
declare -gA __dybatpho_log_string_width=()
declare -gi __DYBATPHO_LOG_WIDTH_CACHE_MAX=4096

#######################################
# @description Return success when a string is nothing but ASCII, which is the
#   case where one character is one index and one column, so no measuring is
#   needed at all.
#
#   The test is `[:ascii:]` rather than a byte range under a local `LC_ALL=C`.
#   Assigning `LC_ALL` makes Bash reload its locale data on the way in and again
#   on the way out, which measured at 47 microseconds a call against 14 for this
#   form -- and a screen calls it under every segment of every frame.
# @arg $1 string Text to classify
# @exitcode 0 The text is ASCII
# @exitcode 1 The text holds a character that may not be one column wide
# @internal
#######################################
function __dybatpho_log_is_ascii {
  [[ "${1-}" == *[![:ascii:]]* ]] && return 1
  return 0
}

# The locale the byte-indexing answer below was worked out for, and the answer.
__dybatpho_log_byte_locale=$'\x1f'
__dybatpho_log_byte_indexed=0

#######################################
# @description Report whether Bash indexes strings by byte in this locale.
#   Under a UTF-8 locale a multi-byte character is one index and `printf '%d'`
#   reports its codepoint; under `C` both count bytes, and a character has to be
#   reassembled before it can be measured. The answer is remembered per locale,
#   so a script that switches `LC_ALL` for one call still gets the right one.
# @noargs
# @exitcode 0 Bash counts bytes
# @exitcode 1 Bash counts characters
# @internal
#######################################
function __dybatpho_log_indexes_bytes {
  local __dybatpho_log_locale="${LC_ALL-}|${LC_CTYPE-}|${LANG-}"
  if [[ "${__dybatpho_log_locale}" != "${__dybatpho_log_byte_locale}" ]]; then
    local __dybatpho_log_probe=$'\303\251'
    __dybatpho_log_byte_indexed=0
    ((${#__dybatpho_log_probe} != 1)) && __dybatpho_log_byte_indexed=1
    __dybatpho_log_byte_locale="${__dybatpho_log_locale}"
  fi
  ((__dybatpho_log_byte_indexed == 1))
}

#######################################
# @description Split text into characters, whatever the locale indexes by.
#   Outside a UTF-8 locale Bash indexes a string by byte, so a glyph such as
#   `✅` would come apart into three pieces; the lead byte gives the length of
#   the sequence, which keeps each character whole under the C locale.
# @arg $1 string Name of the array variable receiving the characters
# @arg $2 string Text to split
# @set The named array
# @internal
#######################################
function __dybatpho_log_chars_into {
  local -n __dybatpho_log_chars_out="$1"
  local __dybatpho_log_chars_text="${2-}"
  local __dybatpho_log_chars_index=0 __dybatpho_log_chars_lead
  local __dybatpho_log_chars_length __dybatpho_log_chars_bytes=0

  __dybatpho_log_chars_out=()
  __dybatpho_log_indexes_bytes && __dybatpho_log_chars_bytes=1

  while ((__dybatpho_log_chars_index < ${#__dybatpho_log_chars_text})); do
    __dybatpho_log_chars_length=1
    if ((__dybatpho_log_chars_bytes)); then
      printf -v __dybatpho_log_chars_lead '%d' \
        "'${__dybatpho_log_chars_text:__dybatpho_log_chars_index:1}"
      # Only the byte itself: glibc can report a high byte as negative, and
      # musl's C locale maps it to the codepoint `0xDF00` plus the byte.
      __dybatpho_log_chars_lead=$((__dybatpho_log_chars_lead & 0xFF))
      if ((__dybatpho_log_chars_lead >= 240)); then
        __dybatpho_log_chars_length=4
      elif ((__dybatpho_log_chars_lead >= 224)); then
        __dybatpho_log_chars_length=3
      elif ((__dybatpho_log_chars_lead >= 192)); then
        __dybatpho_log_chars_length=2
      fi
    fi
    __dybatpho_log_chars_out+=("${__dybatpho_log_chars_text:__dybatpho_log_chars_index:__dybatpho_log_chars_length}")
    __dybatpho_log_chars_index=$((__dybatpho_log_chars_index + __dybatpho_log_chars_length))
  done
}

#######################################
# @description Decode one character to its Unicode codepoint, including when
#   the locale makes Bash index by byte and the character arrives as its UTF-8
#   bytes.
# @arg $1 string Name of the variable receiving the codepoint
# @arg $2 string One character
# @set The named variable
# @internal
#######################################
function __dybatpho_log_codepoint_into {
  local -n __dybatpho_log_cp_out="$1"
  local __dybatpho_log_cp_char="$2"
  local __dybatpho_log_cp_byte __dybatpho_log_cp_index

  if ((${#__dybatpho_log_cp_char} == 1)); then
    printf -v __dybatpho_log_cp_out '%d' "'${__dybatpho_log_cp_char}"
    return 0
  fi

  # Several indexes for one character means Bash is counting bytes, so the
  # codepoint is rebuilt from the UTF-8 sequence: the lead byte carries the high
  # bits and every continuation byte adds six more.
  printf -v __dybatpho_log_cp_byte '%d' "'${__dybatpho_log_cp_char:0:1}"
  case "${#__dybatpho_log_cp_char}" in
    2) __dybatpho_log_cp_out=$((__dybatpho_log_cp_byte & 0x1F)) ;;
    3) __dybatpho_log_cp_out=$((__dybatpho_log_cp_byte & 0x0F)) ;;
    *) __dybatpho_log_cp_out=$((__dybatpho_log_cp_byte & 0x07)) ;;
  esac
  for ((__dybatpho_log_cp_index = 1;  \
  __dybatpho_log_cp_index < ${#__dybatpho_log_cp_char};  \
  __dybatpho_log_cp_index++)); do
    printf -v __dybatpho_log_cp_byte '%d' \
      "'${__dybatpho_log_cp_char:__dybatpho_log_cp_index:1}"
    __dybatpho_log_cp_out=$(((__dybatpho_log_cp_out << 6) | (__dybatpho_log_cp_byte & 0x3F)))
  done
}

#######################################
# @description Return success when a codepoint falls in one of a table's
#   ranges. The tables are sorted and do not overlap, so a binary search finds
#   the answer in a handful of comparisons however long the table is.
# @arg $1 string Name of the flat `start end ...` range array
# @arg $2 number Codepoint
# @exitcode 0 The codepoint is in a range
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_log_in_ranges {
  local -n __dybatpho_log_ranges_ref="$1"
  local __dybatpho_log_ranges_cp="$2" __dybatpho_log_ranges_mid
  local __dybatpho_log_ranges_low=0
  local __dybatpho_log_ranges_high=$((${#__dybatpho_log_ranges_ref[@]} / 2 - 1))
  while ((__dybatpho_log_ranges_low <= __dybatpho_log_ranges_high)); do
    __dybatpho_log_ranges_mid=$(((__dybatpho_log_ranges_low + __dybatpho_log_ranges_high) / 2))
    if ((__dybatpho_log_ranges_cp < __dybatpho_log_ranges_ref[__dybatpho_log_ranges_mid * 2])); then
      __dybatpho_log_ranges_high=$((__dybatpho_log_ranges_mid - 1))
    elif ((__dybatpho_log_ranges_cp > __dybatpho_log_ranges_ref[__dybatpho_log_ranges_mid * 2 + 1])); then
      __dybatpho_log_ranges_low=$((__dybatpho_log_ranges_mid + 1))
    else
      return 0
    fi
  done
  return 1
}

#######################################
# @description Return the number of columns one character occupies, against the
#   embedded Unicode tables. Every character measured is remembered, so a screen
#   redrawn sixty times a second measures each distinct glyph once.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string One character
# @set The named variable
# @internal
#######################################
function __dybatpho_log_char_width_into {
  local -n __dybatpho_log_cw_out="$1"
  local __dybatpho_log_cw_char="$2"

  if [[ -n "${__dybatpho_log_char_width[${__dybatpho_log_cw_char}]-}" ]]; then
    __dybatpho_log_cw_out="${__dybatpho_log_char_width[${__dybatpho_log_cw_char}]}"
    return 0
  fi

  local __dybatpho_log_cw_cp
  __dybatpho_log_codepoint_into __dybatpho_log_cw_cp "${__dybatpho_log_cw_char}"
  if ((__dybatpho_log_cw_cp < 0x300)); then
    __dybatpho_log_cw_out=1
  elif __dybatpho_log_in_ranges __DYBATPHO_LOG_WIDTH_ZERO "${__dybatpho_log_cw_cp}"; then
    __dybatpho_log_cw_out=0
  elif __dybatpho_log_in_ranges __DYBATPHO_LOG_WIDTH_WIDE "${__dybatpho_log_cw_cp}"; then
    __dybatpho_log_cw_out=2
  else
    __dybatpho_log_cw_out=1
  fi
  __dybatpho_log_char_width["${__dybatpho_log_cw_char}"]="${__dybatpho_log_cw_out}"
}

#######################################
# @description Return the number of terminal columns a string occupies.
#   This is the library's one display-width measure: logging's boxes, `text`,
#   `table`, `markdown`, `screen` and `tui` all go through it. Text that is
#   nothing but ASCII is its own length, which is the overwhelmingly common case
#   and is answered without looking at a single character; anything else is
#   measured character by character against the embedded Unicode tables, with
#   no external process. ANSI escape sequences are not stripped here: a caller
#   measuring styled text strips them first.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Text to measure
# @set The named variable
# @internal
#######################################
function __dybatpho_log_width_into {
  local -n __dybatpho_log_w_out="$1"
  local __dybatpho_log_w_text="${2-}"

  if __dybatpho_log_is_ascii "${__dybatpho_log_w_text}"; then
    __dybatpho_log_w_out="${#__dybatpho_log_w_text}"
    return 0
  fi

  if [[ -n "${__dybatpho_log_string_width[${__dybatpho_log_w_text}]-}" ]]; then
    __dybatpho_log_w_out="${__dybatpho_log_string_width[${__dybatpho_log_w_text}]}"
    return 0
  fi

  local -a __dybatpho_log_w_chars=()
  local __dybatpho_log_w_char __dybatpho_log_w_each __dybatpho_log_w_total=0
  __dybatpho_log_chars_into __dybatpho_log_w_chars "${__dybatpho_log_w_text}"
  for __dybatpho_log_w_char in ${__dybatpho_log_w_chars[@]+"${__dybatpho_log_w_chars[@]}"}; do
    __dybatpho_log_char_width_into __dybatpho_log_w_each "${__dybatpho_log_w_char}"
    __dybatpho_log_w_total=$((__dybatpho_log_w_total + __dybatpho_log_w_each))
  done
  if ((${#__dybatpho_log_string_width[@]} >= __DYBATPHO_LOG_WIDTH_CACHE_MAX)); then
    __dybatpho_log_string_width=()
  fi
  __dybatpho_log_string_width["${__dybatpho_log_w_text}"]="${__dybatpho_log_w_total}"
  __dybatpho_log_w_out="${__dybatpho_log_w_total}"
}

#######################################
# @description Repeat a string, writing the result into a named variable.
#   The renderers build padding one cell at a time, and reaching
#   `dybatpho::string_repeat` through `$( )` forked once per cell.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to repeat
# @arg $3 number Number of repetitions
# @set The named variable
# @internal
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
# @description Wrap one text line to the requested width using word boundaries when possible.
# @arg $1 string Input line
# @arg $2 number Maximum width
# @stdout Wrapped lines
# @internal
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
  # line breaks where it actually reaches the edge of the terminal. The line is
  # split into whole characters first: under the C locale Bash indexes by byte,
  # and walking bytes measured each piece of a multi-byte glyph on its own.
  local -a chars=() widths=()
  __dybatpho_log_chars_into chars "${line}"
  local total="${#chars[@]}" index char_width
  for ((index = 0; index < total; index++)); do
    if __dybatpho_log_is_ascii "${chars[index]}"; then
      widths[index]=1
    else
      __dybatpho_log_char_width_into char_width "${chars[index]}"
      widths[index]="${char_width}"
    fi
  done

  local IFS=
  local start=0 used cut last_space break_at next_space
  while ((start < total)); do
    used=0
    cut=-1
    last_space=-1
    for ((index = start; index < total; index++)); do
      used=$((used + widths[index]))
      [[ "${chars[index]}" == " " ]] && last_space=${index}
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
        if [[ "${chars[index]}" == " " ]]; then
          next_space=${index}
          break
        fi
      done
      ((next_space >= 0)) || break
      break_at=${next_space}
    fi

    printf '%s\n' "${chars[*]:start:break_at-start}"
    start=$((break_at + 1))
    while ((start < total)) && [[ "${chars[start]}" == " " ]]; do
      start=$((start + 1))
    done
  done

  printf '%s\n' "${chars[*]:start}"
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
# @internal
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

  # Measure the whole message once here, in this shell. The wrapping below runs
  # inside `$(...)`, and a subshell's additions to the width cache die with it,
  # so warming the cache in the parent saves every line looking its characters
  # up again.
  # shellcheck disable=SC2034 # measured only to fill the cache; the value is not needed
  local warmed_width
  __dybatpho_log_width_into warmed_width "${message}"

  mapfile -t input_lines <<< "${message}"
  if ((${#input_lines[@]} == 0)); then
    input_lines=("") # kcov(skip) - defensive; a here-string always yields one line
  fi

  local input_line wrapped_line
  for input_line in "${input_lines[@]}"; do
    local log_wrap_line_output
    log_wrap_line_output=$(__dybatpho_log_wrap_line "${input_line}" "${inner_limit}") # kcov(skip)
    while IFS= read -r wrapped_line || [[ -n "${wrapped_line}" ]]; do
      wrapped_lines+=("${wrapped_line}")
      local wrapped_width
      __dybatpho_log_width_into wrapped_width "${wrapped_line}"
      if ((wrapped_width > content_width)); then
        content_width=${wrapped_width}
      fi
    done < <(printf '%s' "${log_wrap_line_output}") # kcov(skip) - the boxed logging tests run it; kcov records no hit
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
  local level="${1,,}"
  case "${level}" in
    trace | debug | info | warn | error | fatal) return 0 ;;
    *)
      printf '%s is not a valid log level, it should be trace|debug|info|warn|error|fatal\n' "${level}" >&2
      return 1
      ;;
  esac
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
# @description Log a debug message together with the output of a command.
#   The command is given after `--` as a command and its arguments, which run
#   as they are, never parsed as shell. The older form, a single shell command
#   string in place of `--`, still works but is deprecated: it runs through
#   `eval`, so a value interpolated into it is parsed as code.
# @example
#   dybatpho::debug_command "Generated file" -- cat -- "${path}"
#
# @example
#   dybatpho::debug_command "Generated file" "cat ./generated.sh"   # deprecated string form
#
# @arg $1 string Introductory message
# @arg $2 string `--`, or (deprecated) a shell command string to evaluate
# @arg $@ string Command and its arguments, after `--`
# @env DYBATPHO_LOG_LEVEL string Set to `debug` or `trace` to see this output; falls back to `LOG_LEVEL`
# @stderr Show message if log level of message is less than debug level
#######################################
function dybatpho::debug_command {
  (($# >= 2)) || dybatpho::die "${FUNCNAME[0]}: Expected: message -- command [args...]"
  if [[ "$2" == "--" ]]; then
    (($# >= 3)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"
    dybatpho::compare_log_level debug || return 0
    # kcov records no hit for the continuation line of the message, which
    # "dybatpho::debug_command -- runs a command and its arguments as words,
    # never as shell" runs.
    __dybatpho_log_inspect debug "COMMAND 💻    " "$1
$("${@:3}")" # kcov(skip)
    return 0
  fi
  dybatpho::compare_log_level debug || return 0
  # dyshellint disable=BSG080 # deprecated string form, kept for compatibility; the `--` form above runs no `eval`
  # Likewise run by "dybatpho::debug_command output".
  __dybatpho_log_inspect debug "COMMAND 💻    " "$1
$(eval "$2")" # kcov(skip)
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
  __dybatpho_log_progress_to stdout "$@"
}

#######################################
# @description Show the in-progress banner of `dybatpho::progress` on a chosen
#   stream. The retry helpers report on stderr, where their caller's `$(...)`
#   does not capture the banner along with the command's own output.
# @arg $1 string `stdout` or `stderr`
# @arg $@ string Message, its words joined by spaces as `dybatpho::progress` joins them
# @internal
#######################################
function __dybatpho_log_progress_to {
  local color="0;3;34"
  # The banner helpers compose their text before boxing it, so they never reach
  # the hook in `__dybatpho_log_inspect` and have to translate their own message.
  local message
  __dybatpho_log_translate_into message "${*:2}"
  __dybatpho_log_box "╭" "─" "╮" "│" "│" "╰" "╯" "🚀 ${message}..." "$1" "${color}"
}

#######################################
# @description Render a percentage-based progress bar on the current output line.
# @arg $1 number Progress percentage from 0 to 100
# @arg $2 number [default: 50] Width of the progress bar in characters
# @stdout Show the progress bar; print a newline in the caller when the task is done
#######################################
function dybatpho::progress_bar {
  local percentage="$1"
  local length="${2:-50}"
  # Both reach arithmetic, which reads `08` as a bad octal number and runs a
  # command written as an array subscript.
  [[ "${percentage}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Percentage must be a whole number, got '${percentage}'"
  [[ "${length}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Width must be a whole number, got '${length}'"
  percentage=$((10#${percentage}))
  length=$((10#${length}))
  local elapsed=$((percentage * length / 100))
  local prog total

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
  __dybatpho_log_translate_into message "$*"
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
  __dybatpho_log_translate_into message "$1"
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
# @noargs
# @stdout `,"name":"value"` for every registered field, in registration order
# @internal
#######################################
function __dybatpho_log_context_json {
  ((${#__dybatpho_log_context_keys[@]} > 0)) || return 0
  local key value
  for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
    value="${__dybatpho_log_context_values[${key}]-}"
    __dybatpho_log_redact value
    local log_json_escape
    __dybatpho_log_json_escape_into log_json_escape "${value}"
    local log_json_escape_2
    __dybatpho_log_json_escape_into log_json_escape_2 "${key}"
    printf ',"%s":"%s"' \
      "${log_json_escape_2}" \
      "${log_json_escape}"
  done
}

#######################################
# @description Render the registered context fields for a human-readable line.
# @noargs
# @stdout ` name=value` for every registered field, in registration order
# @internal
#######################################
function __dybatpho_log_context_text {
  ((${#__dybatpho_log_context_keys[@]} > 0)) || return 0
  local key value
  for key in ${__dybatpho_log_context_keys[@]+"${__dybatpho_log_context_keys[@]}"}; do
    value="${__dybatpho_log_context_values[${key}]-}"
    __dybatpho_log_redact value
    printf ' %s=%s' "${key}" "${value}"
  done
}

#######################################
# @description Register or update context fields from `name=value` pairs.
# @arg $@ string `name=value` pairs
# @set __dybatpho_log_context_values
# @set __dybatpho_log_context_keys
# @internal
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
    # shellcheck disable=SC2154 # declared by `src/helpers.sh`, a core module
    if [[ ! "${name}" =~ ${__DYBATPHO_HELPERS_RE_IDENTIFIER} ]]; then
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
# @internal
#######################################
function __dybatpho_log_context_remove {
  (($# > 0)) \
    || dybatpho::die "dybatpho::log_context: 'remove' expects at least one field name"
  local name key
  local -a kept=()
  for name in "$@"; do
    # Single quotes: `unset` expands the subscript itself, and a key it saw already
    # expanded was expanded twice, running a `$(...)` in a field name.
    unset -v '__dybatpho_log_context_values[$name]'
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
# @internal
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
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac
  printf '%s' "${number}"
}

#######################################
# @description Pause for a fractional number of seconds, falling back to one
#   whole second where `sleep` only understands integers.
# @arg $1 string Seconds to wait
# @internal
#######################################
function __dybatpho_log_sleep {
  sleep "$1" 2> /dev/null || sleep 1
}

#######################################
# @description Animate the spinner on stderr until the shell that started it
#   kills it. Runs as a background job, so it never returns on its own.
# @arg $1 string Message shown beside the frame, already redacted
# @stderr One frame per interval, redrawn over the same line
# @internal
#######################################
function __dybatpho_log_spin {
  __dybatpho_log_spin_loop "${DYBATPHO_SPINNER_FRAMES}" "${DYBATPHO_SPINNER_INTERVAL}" "${1-}"
}

#######################################
# @description The animation both spinners run: `dybatpho::spinner` here and
#   the `tui` one. When a state file is given, the message is read from it on
#   every frame, so the shell that owns the spinner can change it; reading it
#   with `read` rather than `$(< file)` keeps a frame from starting a process.
# @arg $1 string Space-separated frames
# @arg $2 string Seconds between frames
# @arg $3 string Message shown beside the frame, already redacted
# @arg $4 string? File the message is re-read from on every frame
# @stderr One frame per interval, redrawn over the same line
# @internal
#######################################
function __dybatpho_log_spin_loop {
  local interval="$2" message="${3-}" file="${4-}"
  local -a frames=()
  read -r -a frames <<< "$1"
  ((${#frames[@]} > 0)) || frames=('-' "\\" '|' '/')
  local index=0 parent="$$"
  while true; do
    # The animation is a background job of the script; when the script ends
    # without stopping it -- `die`, `set -e`, a plain `exit` -- it would be
    # orphaned to PID 1 and keep drawing over the shell prompt.
    if ! kill -0 "${parent}" 2> /dev/null; then
      printf '\r\033[K\033[?25h' >&2
      # dyshellint disable=BSG090 # this is the background animation job, not the script
      exit 0
    fi
    if [[ -n "${file}" ]]; then
      message=""
      { IFS= read -r -d '' message < "${file}"; } 2> /dev/null || true
      # What `$(< file)` used to leave: trailing newlines go.
      while [[ "${message}" == *$'\n' ]]; do
        message="${message%$'\n'}"
      done
    fi
    printf '\r%s %s\033[K' "${frames[index % ${#frames[@]}]}" "${message}" >&2
    index=$((index + 1))
    __dybatpho_log_sleep "${interval}"
  done
}

#######################################
# @description Send structured JSON events to a file alongside the
#   human-readable output on stderr, and keep that file bounded by rotating it.
#
#   This is the front end to the `DYBATPHO_LOG_FILE*` variables: a script names
#   the path once instead of setting four of them, and gets the argument checking, the
#   parent directory and a private mode along with it. Every registered secret
#   is redacted before a line reaches the file, exactly as it is on stderr, so
#   turning on a durable log never turns it into a place a token leaks to.
# @example
#   dybatpho::log_to_file /var/log/deploy.log rotate:10M keep:3 level:debug
#   dybatpho::info "Deploying"  # text on stderr, JSON in the file
#   dybatpho::log_to_file off   # stop writing to a file
#
# @arg $1 string Path of the log file, or `off` to stop file logging
# @arg $@ string? `rotate:SIZE`, `keep:COUNT` and `level:LEVEL` settings
# @set DYBATPHO_LOG_FILE string Path that receives the structured events
# @set DYBATPHO_LOG_FILE_MAX_BYTES number Size threshold the file is rotated at
# @set DYBATPHO_LOG_FILE_MAX_BACKUPS number Number of rotated backups kept
# @set DYBATPHO_LOG_FILE_LEVEL string Verbosity threshold applied to the file alone
# @exitcode 1 A setting is malformed, or the file cannot be written
# @tip `rotate:0` disables rotation, and a size may be given as bytes or with a `K`, `M`, `G` or `T` suffix
# @tip A log file this function creates gets mode `600`; one that already exists keeps the mode it has
# @tip The settings are not exported; export `DYBATPHO_LOG_FILE` and its siblings yourself when a child process
#   should write to the same file. `off` also clears an unprefixed `LOG_FILE`
#######################################
function dybatpho::log_to_file {
  local path
  dybatpho::expect_args path -- "$@"
  shift

  local rotate="${DYBATPHO_LOG_FILE_MAX_BYTES:-${LOG_FILE_MAX_BYTES:-10485760}}"
  local keep="${DYBATPHO_LOG_FILE_MAX_BACKUPS:-${LOG_FILE_MAX_BACKUPS:-5}}"
  local level="${DYBATPHO_LOG_FILE_LEVEL:-${LOG_FILE_LEVEL:-${DYBATPHO_LOG_LEVEL:-${LOG_LEVEL:-info}}}}"
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
    # The unprefixed name is the fallback for an empty prefixed one, so both
    # are cleared, or an inherited `LOG_FILE` would keep the sink open.
    DYBATPHO_LOG_FILE=""
    LOG_FILE=""
  else
    local directory
    directory="$(dirname -- "${path}")"
    if [[ ! -d "${directory}" ]]; then
      mkdir -p -- "${directory}" \
        || dybatpho::die "${FUNCNAME[0]}: Cannot create log directory '${directory}'"
    fi
    if [[ ! -e "${path}" ]]; then
      # A log file holds whatever the script logged, which is the last place a
      # value should become world-readable. The mode is chosen at creation
      # only, so an operator who widened it deliberately keeps their choice.
      # The closing line dies, so "dybatpho::log_to_file stops when it cannot
      # create the log file" runs it under `run`, where kcov cannot see it.
      (
        umask 077
        : > "${path}"
      ) || dybatpho::die "${FUNCNAME[0]}: Cannot create log file '${path}'" # kcov(skip)
    fi
    [[ -w "${path}" ]] \
      || dybatpho::die "${FUNCNAME[0]}: Log file '${path}' is not writable"
    DYBATPHO_LOG_FILE="${path}"
  fi

  DYBATPHO_LOG_FILE_MAX_BYTES="${rotate}"
  DYBATPHO_LOG_FILE_MAX_BACKUPS="${keep}"
  DYBATPHO_LOG_FILE_LEVEL="${level}"
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
# @tip Fields are held in the current shell, so a child process starts with none of them; export
#   `DYBATPHO_LOG_REQUEST_ID` to correlate across processes
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
      [[ -n "${__dybatpho_log_context_values[${name}]+set}" ]] || return 1
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
# @tip This times a step so the log says how long it took; `dybatpho::metrics_timer_start` records the same measurement
#   as
#   a metric for a dashboard
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
# @arg $2 string [default: info] Level to log the duration at
# @set DYBATPHO_TIMER_LAST_MS number Elapsed milliseconds of this timer
# @set __dybatpho_log_timer
# @stderr The duration message, at the requested level
# @exitcode 1 The requested level is not a valid log level
# @tip The elapsed time is published in `DYBATPHO_TIMER_LAST_MS` rather than printed, because capturing output with
#   `$(...)` would run the call in a subshell and throw the measurement away
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
  local elapsed
  elapsed=$(($(__dybatpho_log_now_ms) - started))
  if ((elapsed < 0)); then
    elapsed=0
  fi
  # Single quotes, so the timer name is expanded once, by `unset` itself.
  unset -v '__dybatpho_log_timer[$name]'
  DYBATPHO_TIMER_LAST_MS="${elapsed}"

  local extra_fields
  local log_json_escape
  __dybatpho_log_json_escape_into log_json_escape "${name}"
  printf -v extra_fields ',"timer":"%s","elapsed_ms":%s' \
    "${log_json_escape}" "${elapsed}"
  local message
  message="$(__dybatpho_log_text logging.timer_end "${name} took ${elapsed}ms" name="${name}" elapsed_ms="${elapsed}")"
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
  local __dybatpho_log_spinner_message
  dybatpho::expect_args __dybatpho_log_spinner_message -- "$@"
  shift
  [[ "${1-}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected -- between the message and the command"
  shift
  (($# > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected a command after --"

  __dybatpho_log_redact __dybatpho_log_spinner_message

  local __dybatpho_log_spinner_animate=false
  case "${DYBATPHO_SPINNER}" in
    never) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    always) __dybatpho_log_spinner_animate=true ;;
    *)
      if [[ -t 2 ]] && dybatpho::compare_log_level info; then
        __dybatpho_log_spinner_animate=true
      fi
      ;;
  esac

  local __dybatpho_log_spinner_spinner_pid=""
  if [[ "${__dybatpho_log_spinner_animate}" == true ]]; then
    __dybatpho_log_spin "${__dybatpho_log_spinner_message}" &
    __dybatpho_log_spinner_spinner_pid=$!
  else
    __dybatpho_log_inspect info "SPIN ⏳       " "${__dybatpho_log_spinner_message}"
  fi

  local __dybatpho_log_spinner_started __dybatpho_log_spinner_status=0
  __dybatpho_log_spinner_started="$(__dybatpho_log_now_ms)"
  "$@" || __dybatpho_log_spinner_status=$?

  if [[ -n "${__dybatpho_log_spinner_spinner_pid}" ]]; then
    kill "${__dybatpho_log_spinner_spinner_pid}" 2> /dev/null || true
    wait "${__dybatpho_log_spinner_spinner_pid}" 2> /dev/null || true
    # Erase the frame so the next line starts on a clean column, whether the
    # command printed anything of its own or not.
    printf '\r\033[K' >&2
  fi

  local __dybatpho_log_spinner_elapsed
  __dybatpho_log_spinner_elapsed=$(($(__dybatpho_log_now_ms) - __dybatpho_log_spinner_started))
  if ((__dybatpho_log_spinner_elapsed < 0)); then
    __dybatpho_log_spinner_elapsed=0
  fi
  local __dybatpho_log_spinner_extra_fields
  printf -v __dybatpho_log_spinner_extra_fields ',"elapsed_ms":%s,"exit_code":%s' "${__dybatpho_log_spinner_elapsed}" \
    "${__dybatpho_log_spinner_status}"
  local __dybatpho_log_spinner_done="${__dybatpho_log_spinner_message} finished in"
  __dybatpho_log_spinner_done+=" ${__dybatpho_log_spinner_elapsed}ms with exit code ${__dybatpho_log_spinner_status}"
  __dybatpho_log_inspect debug "SPIN ⏳       " \
    "${__dybatpho_log_spinner_done}" 0 "" "${__dybatpho_log_spinner_extra_fields}"

  return "${__dybatpho_log_spinner_status}"
}

#######################################
# @description Enable Bash tracing with dybatpho formatting.
# @noargs
# @env DYBATPHO_LOG_LEVEL string Set to `trace` to emit the trace start/end messages; falls back to `LOG_LEVEL`
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
  # dyshellint disable=BSG034 # this is `dybatpho::start_trace`; it has no helper to defer to
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
