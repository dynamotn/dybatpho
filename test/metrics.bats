setup() {
  load test_helper
  dybatpho::metrics_reset
}

@test "dybatpho::metrics_counter_inc accumulates and defaults to one" {
  dybatpho::metrics_counter_inc jobs_total
  dybatpho::metrics_counter_inc jobs_total
  dybatpho::metrics_counter_inc jobs_total 5
  assert_equal "$(dybatpho::metrics_get counter jobs_total)" "7"
}

@test "dybatpho::metrics_counter_inc keeps label sets apart" {
  dybatpho::metrics_counter_inc requests_total 1 status=200
  dybatpho::metrics_counter_inc requests_total 1 status=200
  dybatpho::metrics_counter_inc requests_total 1 status=500
  assert_equal "$(dybatpho::metrics_get counter requests_total status=200)" "2"
  assert_equal "$(dybatpho::metrics_get counter requests_total status=500)" "1"
}

@test "label order does not create a second series" {
  dybatpho::metrics_counter_inc requests_total 1 method=GET status=200
  dybatpho::metrics_counter_inc requests_total 1 status=200 method=GET
  assert_equal "$(dybatpho::metrics_get counter requests_total method=GET status=200)" "2"
  run dybatpho::metrics_render
  assert_line --partial 'requests_total{method="GET",status="200"} 2'
}

@test "dybatpho::metrics_counter_inc rejects a bad name, label or amount" {
  run ! dybatpho::metrics_counter_inc '9invalid'
  run ! dybatpho::metrics_counter_inc valid_total 1 'not-a-pair'
  run ! dybatpho::metrics_counter_inc valid_total 1 '9bad=x'
  run ! dybatpho::metrics_counter_inc valid_total -3
  run ! dybatpho::metrics_counter_inc valid_total abc
}

@test "dybatpho::metrics_gauge_set replaces the value and accepts negatives" {
  dybatpho::metrics_gauge_set queue_depth 5
  dybatpho::metrics_gauge_set queue_depth 12
  assert_equal "$(dybatpho::metrics_get gauge queue_depth)" "12"
  dybatpho::metrics_gauge_set drift_seconds -1.5
  assert_equal "$(dybatpho::metrics_get gauge drift_seconds)" "-1.5"
  run ! dybatpho::metrics_gauge_set queue_depth "not a number"
}

@test "label values are escaped the way Prometheus requires" {
  dybatpho::metrics_counter_inc events_total 1 'path=a"b\c'
  run dybatpho::metrics_render
  assert_line --partial 'events_total{path="a\"b\\c"} 1'
}

@test "dybatpho::metrics_observe_ms fills cumulative buckets, sum and count" {
  DYBATPHO_METRICS_BUCKETS_MS="10,100,1000"
  dybatpho::metrics_observe_ms request_duration_seconds 5
  dybatpho::metrics_observe_ms request_duration_seconds 50
  dybatpho::metrics_observe_ms request_duration_seconds 5000
  run dybatpho::metrics_render
  # 5ms lands in every bucket, 50ms in the last two, 5000ms only in +Inf.
  assert_line --partial 'request_duration_seconds_bucket{le="0.010"} 1'
  assert_line --partial 'request_duration_seconds_bucket{le="0.100"} 2'
  assert_line --partial 'request_duration_seconds_bucket{le="1.000"} 2'
  assert_line --partial 'request_duration_seconds_bucket{le="+Inf"} 3'
  assert_line --partial 'request_duration_seconds_sum 5.055'
  assert_line --partial 'request_duration_seconds_count 3'
}

@test "dybatpho::metrics_observe_ms renders milliseconds as seconds" {
  dybatpho::metrics_observe_ms d_seconds 1
  dybatpho::metrics_observe_ms d_seconds 1500
  run dybatpho::metrics_render
  assert_line --partial 'd_seconds_sum 1.501'
}

@test "dybatpho::metrics_observe_ms rejects a non-integer duration" {
  run ! dybatpho::metrics_observe_ms d_seconds 1.5
  run ! dybatpho::metrics_observe_ms d_seconds -1
}

@test "a histogram keeps its label sets apart" {
  dybatpho::metrics_observe_ms d_seconds 10 host=a
  dybatpho::metrics_observe_ms d_seconds 20 host=b
  assert_equal "$(dybatpho::metrics_get count d_seconds host=a)" "1"
  assert_equal "$(dybatpho::metrics_get sum d_seconds host=b)" "20"
  run dybatpho::metrics_render
  assert_line --partial 'd_seconds_bucket{host="a",le="+Inf"} 1'
  assert_line --partial 'd_seconds_sum{host="b"} 0.020'
}

@test "dybatpho::metrics_summary_ms exports exact quantiles, sum and count" {
  local ms
  for ms in 300 100 1000 200 400; do
    dybatpho::metrics_summary_ms step_duration_seconds "${ms}" step=fetch
  done
  run_traced dybatpho::metrics_render
  assert_line --index 0 "# HELP step_duration_seconds step_duration_seconds"
  assert_line --index 1 "# TYPE step_duration_seconds summary"
  assert_line --index 2 'step_duration_seconds{step="fetch",quantile="0.5"} 0.3'
  assert_line --index 3 'step_duration_seconds{step="fetch",quantile="0.9"} 0.76'
  assert_line --index 4 'step_duration_seconds{step="fetch",quantile="0.99"} 0.976'
  assert_line --index 5 'step_duration_seconds_sum{step="fetch"} 2.000'
  assert_line --index 6 'step_duration_seconds_count{step="fetch"} 5'
  assert_equal "$(dybatpho::metrics_get count step_duration_seconds step=fetch)" "5"
  assert_equal "$(dybatpho::metrics_get sum step_duration_seconds step=fetch)" "2000"
}

@test "dybatpho::metrics_summary_ms keeps label sets apart and handles one sample" {
  dybatpho::metrics_summary_ms d_seconds 10 host=a
  dybatpho::metrics_summary_ms d_seconds 30 host=a
  dybatpho::metrics_summary_ms d_seconds 7 host=b
  run_traced dybatpho::metrics_render
  assert_line 'd_seconds{host="a",quantile="0.5"} 0.02'
  assert_line 'd_seconds{host="b",quantile="0.99"} 0.007'
  assert_line 'd_seconds_count{host="b"} 1'
}

@test "dybatpho::metrics_summary_ms exports an unlabelled series and custom quantiles" {
  DYBATPHO_METRICS_QUANTILES="0,1"
  dybatpho::metrics_summary_ms d_seconds 0
  dybatpho::metrics_summary_ms d_seconds 1500
  run_traced dybatpho::metrics_render
  assert_line 'd_seconds{quantile="0"} 0'
  assert_line 'd_seconds{quantile="1"} 1.5'
  assert_line 'd_seconds_sum 1.500'
  refute_line --partial 'quantile="0.5"'
}

@test "dybatpho::metrics_summary_ms rejects a bad duration, quantile or label" {
  run ! dybatpho::metrics_summary_ms d_seconds 1.5
  run ! dybatpho::metrics_summary_ms d_seconds -1
  run ! dybatpho::metrics_summary_ms d_seconds 5 'not-a-pair'
  DYBATPHO_METRICS_QUANTILES="0.5,1.5" run dybatpho::metrics_summary_ms d_seconds 5
  assert_failure
  assert_output --partial "Quantile must be a number from 0 to 1, got '1.5'"
  DYBATPHO_METRICS_QUANTILES="median" run dybatpho::metrics_summary_ms d_seconds 5
  assert_failure
  assert_output --partial "got 'median'"
  DYBATPHO_METRICS_QUANTILES="" run dybatpho::metrics_summary_ms d_seconds 5
  assert_failure
  assert_output --partial "must list at least one quantile"
  assert_equal "$(dybatpho::metrics_get count d_seconds)" "0"
}

@test "a metric cannot be both a histogram and a summary" {
  dybatpho::metrics_observe_ms h_seconds 5
  run dybatpho::metrics_summary_ms h_seconds 5
  assert_failure
  assert_output --partial "Metric 'h_seconds' is already recorded as a histogram"
  dybatpho::metrics_summary_ms s_seconds 5
  run dybatpho::metrics_observe_ms s_seconds 5
  assert_failure
  assert_output --partial "Metric 's_seconds' is already recorded as a summary"
}

@test "dybatpho::metrics_reset forgets the samples of a summary" {
  dybatpho::metrics_summary_ms d_seconds 900
  dybatpho::metrics_reset
  dybatpho::metrics_summary_ms d_seconds 100
  run_traced dybatpho::metrics_render
  assert_line 'd_seconds{quantile="0.99"} 0.1'
}

@test "dybatpho::metrics_timer_stop records the duration and publishes it" {
  dybatpho::metrics_timer_start work_duration_seconds
  sleep 0.05
  dybatpho::metrics_timer_stop work_duration_seconds stage=build
  # The measurement survives because the call was not made in a subshell.
  assert_equal "$(dybatpho::metrics_get count work_duration_seconds stage=build)" "1"
  assert [ "${DYBATPHO_METRICS_LAST_MS}" -ge 40 ]
  assert [ "${DYBATPHO_METRICS_LAST_MS}" -lt 5000 ]
}

@test "dybatpho::metrics_timer_stop rejects a timer that was never started" {
  run ! dybatpho::metrics_timer_stop never_started
}

@test "dybatpho::metrics_time records a successful command and passes its status on" {
  dybatpho::metrics_time task_duration_seconds stage=unit -- true
  assert_equal "$(dybatpho::metrics_get count task_duration_seconds stage=unit)" "1"
  # A `_duration_seconds` metric pairs with a `_failures_total` counter.
  assert_equal "$(dybatpho::metrics_get counter task_failures_total stage=unit)" "0"
}

@test "dybatpho::metrics_time records a failure and preserves the exit code" {
  run -3 dybatpho::metrics_time task_duration_seconds -- bash -c 'exit 3'
  # `run` used a subshell, so record it again in this shell to inspect the state.
  dybatpho::metrics_time task_duration_seconds -- bash -c 'exit 3' || true
  assert_equal "$(dybatpho::metrics_get count task_duration_seconds)" "1"
  assert_equal "$(dybatpho::metrics_get counter task_failures_total)" "1"
}

@test "dybatpho::metrics_time requires a command after the separator" {
  run ! dybatpho::metrics_time d_seconds -- 
  run ! dybatpho::metrics_time d_seconds stage=x true
}

@test "dybatpho::metrics_render emits valid HELP and TYPE lines in a stable order" {
  dybatpho::metrics_help jobs_total "Jobs processed"
  dybatpho::metrics_counter_inc jobs_total
  dybatpho::metrics_gauge_set alpha_gauge 1
  run dybatpho::metrics_render
  assert_line --index 0 "# HELP alpha_gauge alpha_gauge"
  assert_line --index 1 "# TYPE alpha_gauge gauge"
  assert_line --index 2 "alpha_gauge 1"
  assert_line --index 3 "# HELP jobs_total Jobs processed"
  assert_line --index 4 "# TYPE jobs_total counter"
  assert_line --index 5 "jobs_total 1"
}

@test "dybatpho::metrics_render prints nothing when nothing was recorded" {
  run dybatpho::metrics_render
  assert_output ""
}

@test "a described metric stays out of the output until it has a sample" {
  dybatpho::metrics_help unused_total "Never incremented"
  run dybatpho::metrics_render
  assert_output ""
}

@test "dybatpho::metrics_reset forgets every series" {
  dybatpho::metrics_counter_inc jobs_total
  dybatpho::metrics_observe_ms d_seconds 10
  dybatpho::metrics_reset
  run dybatpho::metrics_render
  assert_output ""
  assert_equal "$(dybatpho::metrics_get counter jobs_total)" "0"
}

@test "dybatpho::metrics_get reports zero for an unrecorded series and rejects a bad kind" {
  assert_equal "$(dybatpho::metrics_get counter never_seen_total)" "0"
  assert_equal "$(dybatpho::metrics_get sum never_seen_seconds)" "0"
  run ! dybatpho::metrics_get bogus jobs_total
}

@test "dybatpho::metrics_write writes the rendered text atomically" {
  dybatpho::metrics_counter_inc jobs_total 3
  local target="${BATS_TEST_TMPDIR}/metrics.prom"
  dybatpho::metrics_write "${target}"
  assert_equal "$(grep -c '^jobs_total 3$' "${target}")" "1"
  run find "${BATS_TEST_TMPDIR}" -name '.dybatpho_staging_*'
  assert_output ""
  run ! dybatpho::metrics_write "${BATS_TEST_TMPDIR}/missing/dir/metrics.prom"
}

@test "logged messages are counted by level" {
  dybatpho::error "failed" 2> /dev/null
  dybatpho::error "failed again" 2> /dev/null
  dybatpho::warn "careful" 2> /dev/null
  assert_equal "$(dybatpho::metrics_get counter dybatpho_log_messages_total level=error)" "2"
  assert_equal "$(dybatpho::metrics_get counter dybatpho_log_messages_total level=warn)" "1"
}

@test "retries are counted, including running out of them" {
  dybatpho::retry 2 "false" > /dev/null 2>&1 || true
  assert_equal "$(dybatpho::metrics_get counter dybatpho_retry_attempts_total)" "2"
  assert_equal "$(dybatpho::metrics_get counter dybatpho_retry_exhausted_total)" "1"
}

@test "HTTP requests record their status and how long they took" {
  dybatpho::mock_http "https://example.com/api" 200 "ok"
  dybatpho::curl_do "https://example.com/api" /dev/null > /dev/null 2>&1 || true
  assert_equal "$(dybatpho::metrics_get counter dybatpho_http_requests_total status=200)" "1"
  assert_equal "$(dybatpho::metrics_get count dybatpho_http_request_duration_seconds status=200)" "1"
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push PUTs the exposition to the job's group" {
  dybatpho::mock_http "pushgateway.test" 200 ""
  dybatpho::metrics_counter_inc jobs_total 3
  run_traced -0 dybatpho::metrics_push http://pushgateway.test:9091/ backup host=web-1
  assert_equal "$(dybatpho::mock_http_calls)" "http://pushgateway.test:9091/metrics/job/backup/host/web-1"
  run_traced dybatpho::mock_calls curl
  assert_output --partial "--request PUT"
  assert_output --partial "--header Content-Type: text/plain; version=0.0.4"
  run_traced dybatpho::mock_http_payloads
  assert_output --partial "# TYPE jobs_total counter jobs_total 3"
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push --add POSTs so the rest of the group survives" {
  dybatpho::mock_http "pushgateway.test" 202 ""
  dybatpho::metrics_gauge_set queue_depth 4
  run_traced -0 dybatpho::metrics_push --add https://pushgateway.test nightly
  run_traced dybatpho::mock_calls curl
  assert_output --partial "--request POST"
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push encodes grouping values the way the Pushgateway reads them" {
  dybatpho::mock_http "pushgateway.test" 200 ""
  dybatpho::metrics_counter_inc jobs_total
  # A `/` or an empty value goes base64url-encoded; anything else is
  # percent-encoded.
  run_traced -0 dybatpho::metrics_push http://pushgateway.test "backup/db" env= "path=a b" "name=é/ü" "dir=a/b/c/d"
  assert_equal "$(dybatpho::mock_http_calls)" \
    "http://pushgateway.test/metrics/job@base64/YmFja3VwL2Ri/env@base64/=/path/a%20b/name@base64/w6kvw7w=/dir@base64/YS9iL2MvZA=="
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push reports the Pushgateway's refusal and its status" {
  dybatpho::mock_http "pushgateway.test" 400 "text format parsing error in line 1"
  dybatpho::metrics_counter_inc jobs_total
  DYBATPHO_CURL_MAX_RETRIES=0 run_traced -4 dybatpho::metrics_push http://pushgateway.test nightly
  # `run_traced` leaves standard error alone, so `run` reads the message.
  DYBATPHO_CURL_MAX_RETRIES=0 run -4 dybatpho::metrics_push http://pushgateway.test nightly
  assert_output --partial "Pushgateway refused the push to http://pushgateway.test/metrics/job/nightly (exit 4)"
  assert_output --partial "text format parsing error in line 1"
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push sends nothing when nothing was recorded" {
  dybatpho::mock_http "pushgateway.test" 200 ""
  # `run` goes first: its subshell keeps the warning from being counted by the
  # logging instrumentation, which would give the second call something to push.
  run -0 dybatpho::metrics_push http://pushgateway.test nightly
  assert_output --partial "Nothing recorded, so nothing was pushed"
  run_traced -0 dybatpho::metrics_push http://pushgateway.test nightly
  run_traced -1 dybatpho::mock_http_calls
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push prints the request under DRY_RUN" {
  dybatpho::mock_http "pushgateway.test" 200 ""
  dybatpho::metrics_counter_inc jobs_total
  DRY_RUN=true run_traced -0 dybatpho::metrics_push http://pushgateway.test nightly
  assert_output --partial "http://pushgateway.test/metrics/job/nightly"
  run_traced -1 dybatpho::mock_http_calls
  dybatpho::unmock_all
}

@test "dybatpho::metrics_push rejects a bad gateway, job or grouping label" {
  dybatpho::metrics_counter_inc jobs_total
  run dybatpho::metrics_push pushgateway.test nightly
  assert_failure
  assert_output --partial "Pushgateway URL must start with http:// or https://"
  run dybatpho::metrics_push http://pushgateway.test ""
  assert_failure
  assert_output --partial "Job name must not be empty"
  run dybatpho::metrics_push http://pushgateway.test nightly not-a-pair
  assert_failure
  assert_output --partial "Grouping label must be given as key=value, got 'not-a-pair'"
  run dybatpho::metrics_push http://pushgateway.test nightly 9bad=x
  assert_failure
  assert_output --partial "dybatpho::metrics_push: Invalid label name '9bad'"
  run dybatpho::metrics_push http://pushgateway.test nightly a:b=x
  assert_failure
  assert_output --partial "Invalid label name 'a:b'"
  run dybatpho::metrics_push http://pushgateway.test nightly job=other
  assert_failure
  assert_output --partial "The job is already the first grouping label"
}

@test "rendering survives an ERR trap installed by register_common_handlers" {
  # `run` disables errexit, so this has to be a real strict-mode shell: an
  # earlier version returned non-zero from the series lookup whenever the last
  # key did not match, which the ERR trap reported as a failure.
  # A `bash -c` shell has an empty `BASH_SOURCE`, which the kcov hook expands on
  # every command and `set -u` then turns into a failure that shows up only
  # under `scripts/test.sh --coverage`. Spawn from a script file instead.
  local script="${BATS_TEST_TMPDIR}/err_trap.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules metrics
dybatpho::register_common_handlers
dybatpho::metrics_counter_inc a_total
dybatpho::metrics_counter_inc b_total
dybatpho::metrics_observe_ms c_seconds 5
dybatpho::metrics_render > /dev/null
printf "rendered\n"
SCRIPT
  run -0 env -u DYBATPHO_MODULES bash "${script}" "${DYBATPHO_DIR}"
  assert_output "rendered"
  refute_output --partial "Aborting on error"
}

@test "a child shell that never loaded metrics logs without failing" {
  # The parent exports every `dybatpho::` function, so the child inherits
  # `dybatpho::metrics_counter_inc` without the internal helpers it calls. A
  # hook guarded on that public name took the recording branch here and died
  # with `__dybatpho_metrics_key: command not found` on the first log line.
  # Spawn from a script file, not `bash -c`: a `-c` shell has an empty
  # `BASH_SOURCE`, which the kcov hook expands on every command.
  local script="${BATS_TEST_TMPDIR}/child_logging.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules logging
dybatpho::info "hello" 2> /dev/null
printf "logged\n"
SCRIPT
  run -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}"
  assert_output "logged"
  refute_output --partial "command not found"
}

@test "a child shell that never loaded metrics retries without failing" {
  local script="${BATS_TEST_TMPDIR}/child_retry.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::retry 2 "false" > /dev/null 2>&1 || true
printf "retried\n"
SCRIPT
  run -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}"
  assert_output "retried"
  refute_output --partial "command not found"
}

@test "a child shell that loads metrics itself still records" {
  local script="${BATS_TEST_TMPDIR}/child_metrics.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules metrics
dybatpho::error "failed" 2> /dev/null
dybatpho::metrics_get counter dybatpho_log_messages_total level=error
SCRIPT
  run -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}"
  assert_output "1"
}

@test "summaries ask for math and a push asks for network when they are not loaded" {
  # `metrics` loads neither, so counting and timing never pull in `curl`. The
  # child inherits the public `math` and `network` functions this process
  # exports, which is why the guards test internal helpers instead.
  local script="${BATS_TEST_TMPDIR}/child_narrow.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules "${2}"
dybatpho::metrics_counter_inc jobs_total
dybatpho::metrics_render | grep '^jobs_total'
case "${3}" in
  summary) dybatpho::metrics_summary_ms fetch_seconds 10 && dybatpho::metrics_render | grep quantile=\"0.5\" ;;
  push) DRY_RUN=true dybatpho::metrics_push http://gateway.invalid nightly ;;
esac
SCRIPT
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}" metrics summary
  assert_failure
  assert_line --index 0 "jobs_total 1"
  assert_output --partial "dybatpho::metrics_summary_ms needs the math module, load it with: dybatpho::load math"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}" metrics push
  assert_failure
  assert_output --partial "dybatpho::metrics_push needs the network module, load it with: dybatpho::load network"

  run -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}" "metrics math" summary
  assert_output --partial 'fetch_seconds{quantile="0.5"} 0.01'
}

@test "dybatpho::metrics_get rejects a kind it does not know" {
  run ! dybatpho::metrics_get sparkline jobs_total
  assert_output --partial "Unknown kind 'sparkline'"
}

@test "dybatpho::metrics_render prints the header of a type it cannot expand" {
  # A type outside the four the renderer expands still gets its HELP and TYPE
  # lines and no series, so the exposition stays parseable rather than losing
  # the metric. Only the recorder reaches this, so it is declared directly.
  __dybatpho_metrics_declare untyped_metric untyped
  run_traced -0 dybatpho::metrics_render
  assert_output "# HELP untyped_metric untyped_metric
# TYPE untyped_metric untyped"
}

@test "dybatpho::metrics_render prints only the header of a summary with no sample" {
  __dybatpho_metrics_declare summary_metric summary
  run_traced -0 dybatpho::metrics_render
  assert_output "# HELP summary_metric summary_metric
# TYPE summary_metric summary"
}
