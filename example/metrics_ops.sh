#!/usr/bin/env bash
# @file metrics_ops.sh
# @brief Example showing timing, counters and Prometheus export
# @description Demonstrates dybatpho::metrics_time, metrics_timer_start/stop,
#   metrics_counter_inc, metrics_gauge_set, metrics_observe_ms,
#   metrics_summary_ms, metrics_get, metrics_render, metrics_write,
#   metrics_push, and the retry/HTTP/error instrumentation that loading this
#   module turns on
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules metrics math network

dybatpho::register_common_handlers

# @description Run the `TIMING A COMMAND` section of this example.
# @noargs
function _demo_timing {
  dybatpho::header "TIMING A COMMAND"

  # `metrics_time` runs the command, records how long it took, and passes the
  # exit code on, so it can wrap a step without changing what the script does.
  dybatpho::metrics_time build_duration_seconds stage=compile -- sleep 0.05
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "Compile stage took ${DYBATPHO_METRICS_LAST_MS}ms"

  # A failing step is still timed, and also counted as a failure.
  dybatpho::metrics_time build_duration_seconds stage=link -- false || true
  dybatpho::info "Link stage failed after ${DYBATPHO_METRICS_LAST_MS}ms"
  local metrics_get
  metrics_get=$(dybatpho::metrics_get counter build_failures_total stage=link)
  dybatpho::info "Failures so far: ${metrics_get}"

  # A timer suits a region that is not a single command.
  dybatpho::metrics_timer_start deploy_duration_seconds
  sleep 0.02
  dybatpho::metrics_timer_stop deploy_duration_seconds target=staging
  dybatpho::info "Deploy took ${DYBATPHO_METRICS_LAST_MS}ms"
}

# @description Run the `COUNTERS AND GAUGES` section of this example.
# @noargs
function _demo_counters {
  dybatpho::header "COUNTERS AND GAUGES"

  dybatpho::metrics_help artifacts_total "Artifacts published by this run"
  dybatpho::metrics_counter_inc artifacts_total 1 kind=tarball
  dybatpho::metrics_counter_inc artifacts_total 2 kind=checksum
  dybatpho::metrics_gauge_set queue_depth 7

  local metrics_get_2
  metrics_get_2=$(dybatpho::metrics_get counter artifacts_total kind=tarball)
  dybatpho::info "Tarballs  : ${metrics_get_2}"
  local metrics_get
  metrics_get=$(dybatpho::metrics_get counter artifacts_total kind=checksum)
  dybatpho::info "Checksums : ${metrics_get}"
}

# @description Run the `PERCENTILES OF A STEP` section of this example.
# @noargs
function _demo_summary {
  dybatpho::header "PERCENTILES OF A STEP"

  # A summary keeps every observation and exports exact quantiles, which suits
  # a script that repeats a step a few dozen times and then exits.
  dybatpho::metrics_help fetch_duration_seconds "Time to fetch one page"
  local milliseconds
  for milliseconds in 120 95 310 101 88 97 1250 104; do
    dybatpho::metrics_summary_ms fetch_duration_seconds "${milliseconds}" site=docs
  done
  # shellcheck disable=SC2154 # declared by `src/metrics.sh`
  dybatpho::info "Quantiles exported: ${DYBATPHO_METRICS_QUANTILES}"
  local fetches
  fetches="$(dybatpho::metrics_get count fetch_duration_seconds site=docs)"
  dybatpho::info "Fetches recorded  : ${fetches}"
}

# @description Run the `AUTOMATIC INSTRUMENTATION` section of this example.
# @noargs
function _demo_automatic {
  dybatpho::header "AUTOMATIC INSTRUMENTATION"
  dybatpho::info "Loading the metrics module is enough; these need no extra calls"

  # Retries and logged errors are counted by the library itself.
  dybatpho::retry 2 "false" > /dev/null 2>&1 || true
  dybatpho::error "a failure worth counting" 2> /dev/null

  local metrics_get_3
  metrics_get_3=$(dybatpho::metrics_get counter dybatpho_retry_attempts_total)
  dybatpho::info "Retries      : ${metrics_get_3}"
  local metrics_get_2
  metrics_get_2=$(dybatpho::metrics_get counter dybatpho_retry_exhausted_total)
  dybatpho::info "Gave up      : ${metrics_get_2}"
  local metrics_get
  metrics_get=$(dybatpho::metrics_get counter dybatpho_log_messages_total level=error)
  dybatpho::info "Errors logged: ${metrics_get}"
}

# @description Run the `PROMETHEUS EXPORT` section of this example.
# @noargs
function _demo_export {
  dybatpho::header "PROMETHEUS EXPORT"

  # The node exporter's textfile collector reads whatever it finds whenever it
  # scrapes, so the file is written atomically.
  local WORKDIR
  dybatpho::create_temp WORKDIR "/"
  local prom="${WORKDIR}/dybatpho.prom"
  dybatpho::metrics_write "${prom}"
  dybatpho::info "Wrote ${prom}"
  dybatpho::show_file "${prom}"
  dybatpho::info "In production this would live in the textfile collector directory"

  # A job that exits before anything scrapes it pushes to a Pushgateway instead.
  # `DRY_RUN` prints the request rather than sending it, which keeps this
  # example offline; a grouping value with a `/` goes base64url-encoded.
  DRY_RUN=true dybatpho::metrics_push http://pushgateway.example.test:9091 nightly-backup \
    target=db path=/var/backups
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_timing
  _demo_counters
  _demo_summary
  _demo_automatic
  _demo_export
  dybatpho::success "Metrics demo complete"
}

_main "$@"
