#!/usr/bin/env bash
# @file metrics.sh
# @brief Utilities for measuring a script and exporting the result to Prometheus
# @description
#   This module records how long a script spends in a command, how often it
#   retried, and how many errors it hit, then renders the result in the
#   Prometheus text exposition format.
#
#   Metrics live in the current shell only. Nothing is sent anywhere: a script
#   writes the rendered text to a file, and a collector such as the node
#   exporter's textfile collector picks it up. `dybatpho::metrics_write` writes
#   that file atomically, which is what the textfile collector requires in order
#   never to read a half-written file.
#
#   Durations are handled in whole milliseconds, because Bash has no floating
#   point arithmetic, and rendered in seconds, because that is the unit
#   Prometheus expects.
#
#   Loading this module also turns on the instrumentation that `helpers`,
#   `network`, and `logging` offer: retries, HTTP requests, and logged errors
#   are counted without the script asking for it.
# @see
#   - `example/metrics_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_METRICS_BUCKETS_MS string Comma-separated histogram bucket bounds in milliseconds
DYBATPHO_METRICS_BUCKETS_MS="${DYBATPHO_METRICS_BUCKETS_MS:-5,10,25,50,100,250,500,1000,2500,5000,10000}"
# @env DYBATPHO_METRICS_LAST_MS number Elapsed milliseconds published by the timing helpers
DYBATPHO_METRICS_LAST_MS="${DYBATPHO_METRICS_LAST_MS:-0}"

# Series storage. Keys are `<name>` for an unlabelled series and
# `<name>{<labels>}` otherwise, which is also how the series is rendered.
declare -gA __dybatpho_metrics_counter=()
declare -gA __dybatpho_metrics_gauge=()
declare -gA __dybatpho_metrics_sum=()
declare -gA __dybatpho_metrics_count=()
declare -gA __dybatpho_metrics_bucket=()
declare -gA __dybatpho_metrics_help=()
declare -gA __dybatpho_metrics_type=()
declare -gA __dybatpho_metrics_timer=()

#######################################
# @description Fail unless a string is a valid Prometheus metric or label name.
# @arg $1 string Name to validate
# @arg $2 string What the name is, used in the failure message
# @exitcode 1 The name is not valid
#######################################
function __dybatpho_metrics_validate_name {
  local name kind
  dybatpho::expect_args name kind -- "$@"
  [[ "${name}" =~ ^[a-zA-Z_:][a-zA-Z0-9_:]*$ ]] \
    || dybatpho::die "${FUNCNAME[2]}: Invalid ${kind} name '${name}'"
}

#######################################
# @description Sort an array in place, in Bash.
#   `__log` calls into this module, and `__log` has to keep working where `PATH`
#   is restricted, so nothing here may depend on an external command.
# @arg $1 string Name of the array variable to sort
#######################################
function __dybatpho_metrics_sort {
  local -n __sort_target="$1"
  local i j item
  for ((i = 1; i < ${#__sort_target[@]}; i++)); do
    item="${__sort_target[i]}"
    j=$((i - 1))
    while ((j >= 0)) && [[ "${__sort_target[j]}" > "${item}" ]]; do
      __sort_target[j + 1]="${__sort_target[j]}"
      j=$((j - 1))
    done
    __sort_target[j + 1]="${item}"
  done
}

#######################################
# @description Turn `key=value` arguments into a rendered Prometheus label set.
#   Labels are sorted so that the same set always produces the same series key,
#   whatever order the caller passed them in.
# @arg $1 string Name of the variable that receives the rendered label set
# @arg $@ string Label assignments such as `status=200`
# @set The named variable, to the label set including braces, or empty when no labels were given
# @exitcode 1 An argument is not a `key=value` pair, or a key is not a valid name
#######################################
function __dybatpho_metrics_labels {
  local -n __labels_out="$1"
  shift
  __labels_out=""
  (($#)) || return 0
  local pair key value rendered=()
  for pair in "$@"; do
    [[ "${pair}" == *=* ]] \
      || dybatpho::die "${FUNCNAME[2]}: Label must be given as key=value, got '${pair}'"
    key="${pair%%=*}"
    value="${pair#*=}"
    __dybatpho_metrics_validate_name "${key}" "label"
    # Prometheus requires these three characters to be escaped in a label value.
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    rendered+=("${key}=\"${value}\"")
  done
  __dybatpho_metrics_sort rendered
  local joined="" item
  for item in "${rendered[@]}"; do
    joined="${joined:+${joined},}${item}"
  done
  __labels_out="{${joined}}"
}

#######################################
# @description Build the storage key for one series.
#   The key is returned through a variable rather than standard output, because
#   a command substitution would validate inside a subshell, where a rejected
#   name or label could not stop the caller from recording the series anyway.
# @arg $1 string Name of the variable that receives the key
# @arg $2 string Metric name
# @arg $@ string Label assignments
# @set The named variable, to the series key
#######################################
function __dybatpho_metrics_key {
  local -n __key_out="$1"
  shift
  local name
  dybatpho::expect_args name -- "$@"
  shift
  __dybatpho_metrics_validate_name "${name}" "metric"
  local __dybatpho_key_labels
  __dybatpho_metrics_labels __dybatpho_key_labels "$@"
  __key_out="${name}${__dybatpho_key_labels}"
}

#######################################
# @description Record the type and help text of a metric, the first time it is seen.
# @arg $1 string Metric name
# @arg $2 string Metric type
#######################################
function __dybatpho_metrics_declare {
  local name type
  dybatpho::expect_args name type -- "$@"
  [[ -n "${__dybatpho_metrics_type[${name}]-}" ]] && return 0
  __dybatpho_metrics_type["${name}"]="${type}"
  __dybatpho_metrics_help["${name}"]="${__dybatpho_metrics_help[${name}]-${name}}"
  return 0
}

#######################################
# @description Describe a metric, so that the exported text explains it.
# @example
#   dybatpho::metrics_help deploy_duration_seconds "How long a deployment took"
#
# @arg $1 string Metric name
# @arg $2 string Help text
#######################################
function dybatpho::metrics_help {
  local name help
  dybatpho::expect_args name help -- "$@"
  __dybatpho_metrics_validate_name "${name}" "metric"
  __dybatpho_metrics_help["${name}"]="${help}"
}

#######################################
# @description Add to a counter, a value that only ever grows.
# @example
#   dybatpho::metrics_counter_inc deploy_total
#   dybatpho::metrics_counter_inc http_requests_total 1 method=GET status=200
#
# @arg $1 string Metric name, conventionally ending in `_total`
# @arg $2 number Amount to add, default `1`
# @arg $@ string Label assignments such as `status=200`
# @exitcode 1 The name, a label, or the amount is not valid
#######################################
function dybatpho::metrics_counter_inc {
  local name amount key
  dybatpho::expect_args name -- "$@"
  shift
  amount="${1:-1}"
  (($#)) && shift
  [[ "${amount}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Amount must be a non-negative integer, got '${amount}'"
  __dybatpho_metrics_key key "${name}" "$@"
  __dybatpho_metrics_declare "${name}" counter
  __dybatpho_metrics_counter["${key}"]=$((${__dybatpho_metrics_counter[${key}]-0} + amount))
}

#######################################
# @description Set a gauge, a value that can go up and down.
# @example
#   dybatpho::metrics_gauge_set queue_depth 12
#   dybatpho::metrics_gauge_set build_info 1 version=2.0.0
#
# @arg $1 string Metric name
# @arg $2 number Value, which may be negative or fractional
# @arg $@ string Label assignments
# @exitcode 1 The name, a label, or the value is not valid
#######################################
function dybatpho::metrics_gauge_set {
  local name value key
  dybatpho::expect_args name value -- "$@"
  shift 2
  [[ "${value}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Value must be a number, got '${value}'"
  __dybatpho_metrics_key key "${name}" "$@"
  __dybatpho_metrics_declare "${name}" gauge
  __dybatpho_metrics_gauge["${key}"]="${value}"
}

#######################################
# @description Record one duration in a histogram.
#   The value is taken in milliseconds because that is what Bash can measure
#   with integer arithmetic, and exported in seconds because that is what
#   Prometheus expects.
# @example
#   dybatpho::metrics_observe_ms http_request_duration_seconds 143 host=example.com
#
# @arg $1 string Metric name, conventionally ending in `_seconds`
# @arg $2 number Observed duration in whole milliseconds
# @arg $@ string Label assignments
# @env DYBATPHO_METRICS_BUCKETS_MS string Bucket bounds, in milliseconds
# @exitcode 1 The name, a label, or the duration is not valid
#######################################
function dybatpho::metrics_observe_ms {
  local name milliseconds key bound
  dybatpho::expect_args name milliseconds -- "$@"
  shift 2
  [[ "${milliseconds}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Duration must be a non-negative integer of milliseconds, got '${milliseconds}'"
  __dybatpho_metrics_key key "${name}" "$@"
  __dybatpho_metrics_declare "${name}" histogram

  __dybatpho_metrics_sum["${key}"]=$((${__dybatpho_metrics_sum[${key}]-0} + milliseconds))
  __dybatpho_metrics_count["${key}"]=$((${__dybatpho_metrics_count[${key}]-0} + 1))
  # A Prometheus bucket is cumulative: an observation counts in every bucket
  # whose bound it does not exceed.
  local IFS=,
  for bound in ${DYBATPHO_METRICS_BUCKETS_MS}; do
    [[ "${bound}" =~ ^[0-9]+$ ]] \
      || dybatpho::die "${FUNCNAME[0]}: Bucket bound must be a whole number of milliseconds, got '${bound}'"
    if ((milliseconds <= bound)); then
      __dybatpho_metrics_bucket["${key}|${bound}"]=$((${__dybatpho_metrics_bucket[${key}|${bound}]-0} + 1))
    else
      __dybatpho_metrics_bucket["${key}|${bound}"]=$((${__dybatpho_metrics_bucket[${key}|${bound}]-0}))
    fi
  done
}

#######################################
# @description Start a named timer.
# @example
#   dybatpho::metrics_timer_start build_duration_seconds
#   make
#   dybatpho::metrics_timer_stop build_duration_seconds stage=compile
#   dybatpho::info "Build took ${DYBATPHO_METRICS_LAST_MS}ms"
#
# @arg $1 string Timer name
#######################################
function dybatpho::metrics_timer_start {
  local name
  dybatpho::expect_args name -- "$@"
  __dybatpho_metrics_timer["${name}"]="$(__dybatpho_log_now_ms)"
}

#######################################
# @description Stop a timer, record its duration, and print the elapsed milliseconds.
# @arg $1 string Timer name, also used as the metric name
# @arg $@ string Label assignments
# @set DYBATPHO_METRICS_LAST_MS number Elapsed milliseconds of this timer
# @exitcode 1 The timer was never started
# @tip The elapsed time is published in `DYBATPHO_METRICS_LAST_MS` rather than
#   printed, because capturing output with `$(...)` would run the call in a
#   subshell and throw away the measurement it just recorded
#######################################
function dybatpho::metrics_timer_stop {
  local name started elapsed
  dybatpho::expect_args name -- "$@"
  shift
  started="${__dybatpho_metrics_timer[${name}]-}"
  [[ -n "${started}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Timer '${name}' was never started"
  elapsed=$(($(__dybatpho_log_now_ms) - started))
  ((elapsed < 0)) && elapsed=0
  unset "__dybatpho_metrics_timer[${name}]"
  dybatpho::metrics_observe_ms "${name}" "${elapsed}" "$@"
  DYBATPHO_METRICS_LAST_MS="${elapsed}"
}

#######################################
# @description Run a command, record how long it took, and pass its exit code on.
#   The duration is recorded whether the command succeeded or not, and a failure
#   also increments a failure counter named after the metric, so that a dashboard
#   can show latency and error rate from the same run:
#   `deploy_duration_seconds` pairs with `deploy_failures_total`.
# @example
#   dybatpho::metrics_time deploy_duration_seconds stage=upload -- rsync -a ./dist/ host:/srv/
#
# @arg $1 string Metric name
# @arg $@ string Label assignments, then `--`, then the command and its arguments
# @set DYBATPHO_METRICS_LAST_MS number Elapsed milliseconds of the command
# @exitcode * The exit code of the command
#######################################
function dybatpho::metrics_time {
  local name
  dybatpho::expect_args name -- "$@"
  shift
  local -a labels=()
  while (($#)) && [[ "$1" != "--" ]]; do
    labels+=("$1")
    shift
  done
  [[ "${1-}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected '--' between the labels and the command"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Expected a command after '--'"

  local started elapsed status=0
  started="$(__dybatpho_log_now_ms)"
  "$@" || status=$?
  elapsed=$(($(__dybatpho_log_now_ms) - started))
  ((elapsed < 0)) && elapsed=0
  dybatpho::metrics_observe_ms "${name}" "${elapsed}" ${labels[@]+"${labels[@]}"}
  DYBATPHO_METRICS_LAST_MS="${elapsed}"
  if ((status != 0)); then
    local base="${name%_seconds}"
    base="${base%_duration}"
    dybatpho::metrics_counter_inc "${base}_failures_total" 1 ${labels[@]+"${labels[@]}"}
  fi
  return "${status}"
}

#######################################
# @description Read one series back, for a script that branches on its own
#   measurements and for tests.
# @example
#   if (($(dybatpho::metrics_get counter http_requests_total status=500) > 0)); then
#     dybatpho::warn "The run saw server errors"
#   fi
#
# @arg $1 string Series kind, one of `counter`, `gauge`, `sum`, or `count`
# @arg $2 string Metric name
# @arg $@ string Label assignments
# @stdout The recorded value, or `0` when the series has not been recorded
# @exitcode 1 The kind is unknown
#######################################
function dybatpho::metrics_get {
  local kind name key
  dybatpho::expect_args kind name -- "$@"
  shift 2
  __dybatpho_metrics_key key "${name}" "$@"
  case "${kind}" in
    counter) printf '%s\n' "${__dybatpho_metrics_counter[${key}]-0}" ;;
    gauge) printf '%s\n' "${__dybatpho_metrics_gauge[${key}]-0}" ;;
    sum) printf '%s\n' "${__dybatpho_metrics_sum[${key}]-0}" ;;
    count) printf '%s\n' "${__dybatpho_metrics_count[${key}]-0}" ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown kind '${kind}', expected counter, gauge, sum or count" ;;
  esac
}

#######################################
# @description Forget every recorded metric.
# @noargs
#######################################
function dybatpho::metrics_reset {
  __dybatpho_metrics_counter=()
  __dybatpho_metrics_gauge=()
  __dybatpho_metrics_sum=()
  __dybatpho_metrics_count=()
  __dybatpho_metrics_bucket=()
  __dybatpho_metrics_help=()
  __dybatpho_metrics_type=()
  __dybatpho_metrics_timer=()
}

#######################################
# @description Render whole milliseconds as the seconds value Prometheus expects.
# @arg $1 number Milliseconds
# @stdout Seconds with three decimal places
#######################################
function __dybatpho_metrics_seconds {
  local milliseconds
  dybatpho::expect_args milliseconds -- "$@"
  printf '%d.%03d\n' $((milliseconds / 1000)) $((milliseconds % 1000))
}

#######################################
# @description Rewrite a series key with a name suffix and an optional extra label.
#   `http_duration{host="a"}` becomes `http_duration_bucket{host="a",le="0.5"}`.
# @arg $1 string Series key
# @arg $2 string Suffix appended to the metric name
# @arg $3 string Optional extra label, already rendered as `key="value"`
# @stdout Rewritten series key
#######################################
function __dybatpho_metrics_series {
  local key suffix extra name labels
  dybatpho::expect_args key suffix -- "$@"
  extra="${3-}"
  name="${key%%\{*}"
  labels=""
  if [[ "${key}" == *"{"* ]]; then
    labels="${key#*\{}"
    labels="${labels%\}}"
  fi
  if [[ -n "${extra}" ]]; then
    labels="${labels:+${labels},}${extra}"
  fi
  if [[ -n "${labels}" ]]; then
    printf '%s%s{%s}\n' "${name}" "${suffix}" "${labels}"
  else
    printf '%s%s\n' "${name}" "${suffix}"
  fi
}

#######################################
# @description Render every recorded metric in the Prometheus text exposition format.
# @example
#   dybatpho::metrics_render
#   # HELP http_requests_total http_requests_total
#   # TYPE http_requests_total counter
#   http_requests_total{status="200"} 3
#
# @noargs
# @stdout Prometheus text exposition format, with metrics and series in a stable order
# @tip Durations are exported in seconds, so a metric name ending in `_seconds`
#   reads correctly on a dashboard
#######################################
function dybatpho::metrics_render {
  local name key bound total
  local -a names=("${!__dybatpho_metrics_type[@]}")
  __dybatpho_metrics_sort names
  for name in ${names[@]+"${names[@]}"}; do
    printf '# HELP %s %s\n' "${name}" "${__dybatpho_metrics_help[${name}]}"
    printf '# TYPE %s %s\n' "${name}" "${__dybatpho_metrics_type[${name}]}"
    case "${__dybatpho_metrics_type[${name}]}" in
      counter)
        for key in $(__dybatpho_metrics_keys_of "${name}" __dybatpho_metrics_counter); do
          printf '%s %s\n' "${key}" "${__dybatpho_metrics_counter[${key}]}"
        done
        ;;
      gauge)
        for key in $(__dybatpho_metrics_keys_of "${name}" __dybatpho_metrics_gauge); do
          printf '%s %s\n' "${key}" "${__dybatpho_metrics_gauge[${key}]}"
        done
        ;;
      histogram)
        for key in $(__dybatpho_metrics_keys_of "${name}" __dybatpho_metrics_count); do
          local IFS=,
          for bound in ${DYBATPHO_METRICS_BUCKETS_MS}; do
            printf '%s %s\n' \
              "$(__dybatpho_metrics_series "${key}" "_bucket" "le=\"$(__dybatpho_metrics_seconds "${bound}")\"")" \
              "${__dybatpho_metrics_bucket[${key}|${bound}]-0}"
          done
          unset IFS
          total="${__dybatpho_metrics_count[${key}]}"
          printf '%s %s\n' \
            "$(__dybatpho_metrics_series "${key}" "_bucket" 'le="+Inf"')" "${total}"
          printf '%s %s\n' \
            "$(__dybatpho_metrics_series "${key}" "_sum")" \
            "$(__dybatpho_metrics_seconds "${__dybatpho_metrics_sum[${key}]}")"
          printf '%s %s\n' "$(__dybatpho_metrics_series "${key}" "_count")" "${total}"
        done
        ;;
    esac
  done
}

#######################################
# @description Print the series keys of one metric, in a stable order.
# @arg $1 string Metric name
# @arg $2 string Name of the associative array to read
# @stdout Matching series keys, sorted
#######################################
function __dybatpho_metrics_keys_of {
  local name array_name key
  dybatpho::expect_args name array_name -- "$@"
  local -n array="${array_name}"
  # An `&&` here would leave the loop's status at 1 whenever the last key does
  # not match, which an ERR trap reports as a failure.
  local -a matched=()
  for key in "${!array[@]}"; do
    if [[ "${key}" == "${name}" || "${key}" == "${name}{"* ]]; then
      matched+=("${key}")
    fi
  done
  __dybatpho_metrics_sort matched
  ((${#matched[@]})) && printf '%s\n' "${matched[@]}"
  return 0
}

#######################################
# @description Write the rendered metrics to a file, atomically.
#   The node exporter's textfile collector reads whatever it finds whenever it
#   scrapes, so the file has to appear complete or not at all.
# @example
#   dybatpho::metrics_write /var/lib/node_exporter/textfile_collector/backup.prom
#
# @arg $1 string Destination file path, conventionally ending in `.prom`
# @env DRY_RUN string When true-like, report the write instead of performing it
# @exitcode 1 The destination directory is missing or the write fails
#######################################
function dybatpho::metrics_write {
  local path
  dybatpho::expect_args path -- "$@"
  dybatpho::metrics_render | dybatpho::file_write_atomic "${path}"
}

# Describe the metrics the library records on its own. Only the help text is
# registered here: a metric appears in the exported text once it has a sample,
# so a run that never retried does not export an empty retry series.
dybatpho::metrics_help dybatpho_log_messages_total "Log messages emitted, by level"
dybatpho::metrics_help dybatpho_retry_attempts_total "Retries performed by dybatpho::retry"
dybatpho::metrics_help dybatpho_retry_exhausted_total "Commands that ran out of retries"
dybatpho::metrics_help dybatpho_http_requests_total "HTTP requests issued, by final status"
dybatpho::metrics_help dybatpho_http_retries_total "HTTP requests retried"
dybatpho::metrics_help dybatpho_http_request_duration_seconds "HTTP request duration including retries"
