# Feature Specification: Script Measurement and Prometheus Export

**Feature Branch**: `[feature-metrics]`
**Status**: Implemented
**Input**: `src/metrics.sh`, `test/metrics.bats`, `docs/metrics.md`, `example/metrics_ops.sh`, and the instrumentation hooks in `src/helpers.sh`, `src/logging.sh`, and `src/network.sh`

## Problem Statement *(mandatory)*

A script that runs unattended, in CI or from cron, leaves nothing behind that answers how long it took, how often it had to retry, or how many errors it hit. Operators learn about a backup that grew from two minutes to forty only when it starts overlapping the next run. Adding measurement by hand means capturing timestamps, subtracting them in a shell that has no floating point arithmetic, and hand-assembling an exposition format whose escaping and bucket rules are easy to get wrong.

## Business Value *(mandatory)*

- Turn a script's behavior into data an existing monitoring stack can alert on.
- Make a slow step visible as a trend rather than as an incident.
- Record retries and errors that a script currently logs and forgets.
- Keep the measurement inside the library, so a script does not hand-assemble an exposition format.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Measure how long a step takes (Priority: P1)

As a script author, I want to time a command so that I can see when a step starts getting slower.

**Why this priority**: Duration is the measurement most often missing, and the one that turns an incident into a trend.

**Independent Test**: Time a command that sleeps, then verify a duration was recorded and the command's exit code was passed through unchanged.

**Acceptance Scenarios**:

1. **Given** a command to run, **When** it is wrapped by the timing helper, **Then** its duration is recorded and its exit code is returned to the caller
2. **Given** a command that fails, **When** it is wrapped, **Then** the duration is still recorded and a failure counter is incremented
3. **Given** a region of a script rather than one command, **When** a timer is started and stopped around it, **Then** the elapsed time is recorded and published in a variable
4. **Given** a caller that captures the timing helper's output with a command substitution, **When** the call runs in that subshell, **Then** no measurement is silently lost, because the elapsed time is published in a variable rather than printed

---

### User Story 2 - Count what the script did and what went wrong (Priority: P1)

As an operator, I want counters for work done and errors hit so that a dashboard can show a success rate.

**Why this priority**: A duration without an error rate hides the runs that failed fast.

**Independent Test**: Increment counters with and without labels, set a gauge, and read each back.

**Acceptance Scenarios**:

1. **Given** a counter, **When** it is incremented repeatedly, **Then** the recorded value is the sum of the increments
2. **Given** two label sets for the same metric, **When** each is incremented, **Then** they are kept as separate series
3. **Given** the same labels passed in a different order, **When** each call records, **Then** both land in one series
4. **Given** a gauge, **When** it is set twice, **Then** the second value replaces the first

---

### User Story 3 - Get retries, HTTP latency and errors without asking (Priority: P1)

As a script author, I want the library to record what it already knows so that I do not have to instrument every retry and request myself.

**Why this priority**: The library is the only place that can see a retry loop or an HTTP status; a caller would have to reimplement the loop to measure it.

**Independent Test**: With the module loaded, exhaust a retry, log an error, and issue a mocked HTTP request, then verify each was counted without any explicit metric call.

**Acceptance Scenarios**:

1. **Given** the metrics module is loaded, **When** a retried command runs out of attempts, **Then** both the attempts and the exhaustion are counted
2. **Given** an HTTP request, **When** it completes, **Then** its total duration including retries and its final status are recorded
3. **Given** a logged message, **When** it passes the level filter, **Then** it is counted under its level
4. **Given** the metrics module is not loaded, **When** the same code paths run, **Then** they behave exactly as before and raise no error

---

### User Story 4 - Export to Prometheus (Priority: P1)

As an operator, I want the recorded metrics in a file my collector already reads so that no new transport is needed.

**Why this priority**: Measurement that cannot be scraped changes nothing operationally.

**Independent Test**: Record metrics of each kind, render them, and verify the output is the Prometheus text exposition format with correct types, escaping, and cumulative buckets.

**Acceptance Scenarios**:

1. **Given** recorded metrics, **When** they are rendered, **Then** each carries a `# HELP` and `# TYPE` line and its series, in a stable order
2. **Given** a histogram, **When** it is rendered, **Then** buckets are cumulative, durations appear in seconds, and `_sum`, `_count`, and a `+Inf` bucket are present
3. **Given** a label value containing a quote or a backslash, **When** it is rendered, **Then** it is escaped as the format requires
4. **Given** a destination file, **When** the metrics are written, **Then** the file appears complete or not at all, because a collector may scrape it at any moment

---

### User Story 5 - Report percentiles of a step's duration (Priority: P2)

As an operator, I want a script to export the median and the tail latency of a step it repeats, so that a dashboard shows exact quantiles without estimating them from buckets.

**Why this priority**: A histogram answers "how many were under 100ms"; the question a run report is read for is usually "what was the 99th percentile", and a script records few enough durations to keep them all.

**Independent Test**: Record several durations in a summary, render, and verify the quantile series, `_sum`, `_count`, the configured quantile list, and the refusals.

**Acceptance Scenarios**:

1. **Given** durations recorded in a summary, **When** the metrics are rendered, **Then** a `summary` type line is followed by one series per quantile in `DYBATPHO_METRICS_QUANTILES`, carrying a `quantile` label and the exact value in seconds, then `_sum` and `_count`
2. **Given** a custom `DYBATPHO_METRICS_QUANTILES`, **When** a duration is recorded, **Then** the listed quantiles are validated as numbers from `0` to `1` and exported instead of the default `0.5,0.9,0.99`
3. **Given** a metric already recorded as a histogram, **When** a summary observation uses the same name, **Then** it is refused, and the reverse is refused too

---

### User Story 6 - Push a short-lived job's metrics (Priority: P2)

As an operator, I want a cron job or CI step to push its metrics to a Prometheus Pushgateway before it exits, so that a run too short to be scraped still reaches the dashboard.

**Why this priority**: The textfile collector needs a node exporter on the same host; a job in a container or on a CI runner has neither, and the Pushgateway is the standard answer.

**Independent Test**: Record metrics, push them to a mocked Pushgateway, and verify the URL, method, content type, body, encoded grouping labels, and the handling of a refusal, of nothing recorded, and of `DRY_RUN`.

**Acceptance Scenarios**:

1. **Given** recorded metrics, **When** they are pushed with a job name and grouping labels, **Then** the rendered exposition is sent with `PUT` to `<gateway>/metrics/job/<job>/<label>/<value>…` as `text/plain; version=0.0.4`
2. **Given** `--add`, **When** the metrics are pushed, **Then** `POST` is used so that metrics of the group not pushed again are kept
3. **Given** a job name or grouping value that is empty or contains a `/`, **When** the URL is built, **Then** that pair is sent as `<label>@base64/<base64url value>`, and every other value is percent-encoded
4. **Given** the Pushgateway answers with an error status, **When** the push completes, **Then** the status class is returned as the exit code and the gateway's own error text is logged
5. **Given** nothing has been recorded, **When** a push is asked for, **Then** no request is sent, a warning says so, and the call succeeds

---

### Example Workflow

```bash
. dybatpho/init.sh --modules metrics

dybatpho::metrics_time backup_duration_seconds target=db -- pg_dump -Fc mydb -f /backup/db.dump
dybatpho::metrics_gauge_set backup_size_bytes "$(dybatpho::file_size /backup/db.dump)"
dybatpho::metrics_write /var/lib/node_exporter/textfile_collector/backup.prom
```

## Edge Cases

- A metric or label name that Prometheus would reject.
- A label value containing a quote, a backslash, or a newline.
- The same labels supplied in a different order on two calls.
- A timer stopped without being started.
- A duration longer than every bucket bound, which belongs only in `+Inf`.
- A metric described but never given a sample.
- Nothing recorded at all, so there is nothing to export.
- An ERR trap installed by `dybatpho::register_common_handlers` while rendering.
- A summary with a single observation, where every quantile is that value.
- A quantile list that is empty, not numeric, or outside `0`–`1`.
- One metric name used for both a histogram and a summary.
- A script loads `metrics` alone and then records a summary or pushes.
- A push with nothing recorded, or under `DRY_RUN`.
- A grouping value that is empty, contains a `/`, a space, or non-ASCII text.
- A Pushgateway that refuses the push with a 4xx or 5xx status and an explanation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST record counters, gauges, and duration histograms and summaries in the current shell, and MUST NOT send anything anywhere unless the script calls the push helper.
- **FR-002**: The module MUST reject a metric or label name that is not a valid Prometheus name, and a counter amount or histogram observation that is not a non-negative integer.
- **FR-003**: Validation MUST stop the caller from recording the series, and therefore MUST NOT be performed inside a command substitution, where a rejection could not reach the caller.
- **FR-004**: Series MUST be identified by their metric name and label set, with labels ordered so that the same set recorded in a different order is one series.
- **FR-005**: Label values MUST be escaped for backslash, double quote, and newline.
- **FR-006**: Durations MUST be taken in whole milliseconds and exported in seconds, because Bash has no floating point arithmetic and Prometheus expects seconds.
- **FR-007**: Histogram buckets MUST be cumulative, MUST be configurable, and MUST include a `+Inf` bucket, a `_sum`, and a `_count`.
- **FR-008**: The timing helpers MUST publish the elapsed time in a variable rather than on standard output, so that capturing the result cannot discard the recording through a subshell.
- **FR-009**: The command timing helper MUST return the command's exit code unchanged, MUST record the duration whether it succeeded or failed, and MUST count a failure separately.
- **FR-010**: Rendering MUST produce the Prometheus text exposition format with `# HELP` and `# TYPE` lines, in an order that does not change between runs with the same data.
- **FR-011**: A metric that has been described but never sampled MUST NOT appear in the output.
- **FR-012**: Writing the metrics to a file MUST be atomic, because a collector may read the file at any moment.
- **FR-013**: Loading the module MUST activate the retry, HTTP, and logging instrumentation without any further call.
- **FR-014**: The instrumented modules MUST behave exactly as before when the module is not loaded, and MUST NOT depend on it.
- **FR-014a**: The instrumentation hooks MUST decide whether to record by testing for an internal helper of this module, never for one of its exported public functions. A child shell inherits the public functions without the internal helpers they call, so a hook guarded on a public name would try to record where recording is impossible and abort the script.
- **FR-015**: Rendering MUST succeed under `set -e` and an ERR trap.
- **FR-016**: The module MUST record durations in a summary that keeps every observation and renders, per series, one `quantile`-labelled sample for each quantile in `DYBATPHO_METRICS_QUANTILES` (default `0.5,0.9,0.99`), followed by `_sum` and `_count`, under a `summary` type line.
- **FR-017**: Summary quantiles MUST be interpolated linearly between the nearest ranks, as `dybatpho::math_percentile` does, and exported in seconds without rounding.
- **FR-018**: The module MUST refuse a quantile list that is empty or holds a value that is not a number from `0` to `1`, and MUST refuse to record one metric name as both a histogram and a summary.
- **FR-019**: Summary totals MUST be readable through the same `sum` and `count` kinds of `dybatpho::metrics_get` as a histogram's, in milliseconds.
- **FR-020**: The module MUST push the rendered exposition to a Pushgateway URL given by the script, under `/metrics/job/<job>` followed by one `/<label>/<value>` pair per grouping label, with content type `text/plain; version=0.0.4`, using `PUT` by default and `POST` with `--add`.
- **FR-021**: A job name or grouping value that is empty or contains `/` MUST be sent as `<label>@base64/<value>` in the URL-safe base64 alphabet, an empty value as `=`, and every other value MUST be percent-encoded.
- **FR-022**: The push helper MUST refuse a URL without an `http://` or `https://` scheme, an empty job name, a grouping label that is not a `key=value` pair with a valid label name, and a grouping label named `job`.
- **FR-023**: The push helper MUST return the network module's exit code for the request and MUST log the gateway's error text when it refuses the push, rather than hiding the failure.
- **FR-024**: The push helper MUST send no request and succeed with a warning when nothing has been recorded, and MUST honor `DRY_RUN` by printing the request instead of sending it, with the gateway URL shown as its scheme and host only, like every URL the network module logs.
- **FR-025**: Loading `metrics` MUST NOT load `math` or `network`. Recording a summary MUST stop the script, naming the `math` module and how to load it, when `math` is not loaded, and a push MUST do the same for `network`, each before recording or sending anything; counters, gauges, histograms and timers MUST work without either.
- **FR-026**: `metrics_time`, `metrics_timer_start` and `metrics_timer_stop` MUST refuse an invalid metric name or label under their own name, and `metrics_time` MUST do so before running the command.
- **FR-027**: `metrics_push` MUST check the quantile list in the caller's shell before rendering, so that a list made invalid after a summary was recorded stops the push instead of reporting success.
- **FR-028**: A command timed by `metrics_time` MUST see the caller's variables and MUST NOT change what is recorded by assigning to one: the timer MUST keep its state in prefixed locals.

### Key Entities *(include if feature involves data)*

- **Series**: One metric name with one label set, the unit that carries a value.
- **Counter**: A value that only grows, such as a request or error count.
- **Gauge**: A value that can move in either direction, such as a queue depth.
- **Histogram**: A set of cumulative duration buckets with a sum and a count.
- **Summary**: Every observed duration of a series, exported as exact quantiles with a sum and a count.
- **Exposition**: The rendered text a Prometheus collector reads.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script records a step's duration with one call that does not change what the script does.
- **SC-002**: Retries, HTTP latency, and logged errors are recorded without the script instrumenting them.
- **SC-003**: The exported file is accepted by a Prometheus collector as valid exposition text.
- **SC-004**: A collector never reads a partially written metrics file.
- **SC-005**: A script that does not load the module is unaffected in behavior.
- **SC-006**: A run report shows the exact median and tail latency of a repeated step from a single recording call per step.
- **SC-007**: A job that exits before any scrape still delivers its metrics through a Pushgateway with one call.

## Integration Tests *(mandatory)*

- **IT-001**: Increment counters with and without labels, in different label orders, and verify the recorded values and series.
- **IT-002**: Set a gauge twice, including a negative and a fractional value, and verify the last value wins.
- **IT-003**: Reject an invalid metric name, an invalid label name, a malformed label, and a non-integer amount, and verify nothing is recorded.
- **IT-004**: Observe durations that fall in different buckets and verify cumulative counts, `_sum`, `_count`, and `+Inf`.
- **IT-005**: Verify that milliseconds are rendered as seconds with three decimal places.
- **IT-006**: Start and stop a timer and verify the recording survives and the elapsed time is published in a variable.
- **IT-007**: Stop a timer that was never started and verify the failure.
- **IT-008**: Time a succeeding and a failing command and verify the duration, the failure counter, and the propagated exit code.
- **IT-009**: Verify the rendered output's `# HELP` and `# TYPE` lines, ordering, and label escaping.
- **IT-010**: Verify that nothing recorded renders nothing, and that a described but unsampled metric stays out of the output.
- **IT-011**: Write metrics to a file and verify the content and that no staging file is left behind.
- **IT-012**: Exhaust a retry, log errors, and issue a mocked HTTP request, and verify each was counted automatically.
- **IT-013**: Render under `dybatpho::register_common_handlers` and verify no ERR trap fires.
- **IT-014**: From a shell that has loaded the module, run a child script that loads only `logging`, and another that loads the core modules and retries, and verify both complete instead of failing on a missing internal helper; run a third child that loads the module itself and verify it still records.
- **IT-015**: Record durations in a summary and verify the type line, the default quantiles, `_sum`, `_count`, and the totals read back through `dybatpho::metrics_get`.
- **IT-016**: Record summaries under different label sets and with a single observation, and verify each series' quantiles.
- **IT-017**: Configure a custom quantile list, including `0` and `1`, on an unlabelled series, and verify only those quantiles are exported.
- **IT-018**: Reject a non-integer duration, a malformed label, and an empty, non-numeric or out-of-range quantile list, and verify nothing is recorded.
- **IT-019**: Verify a histogram name cannot take a summary observation and a summary name cannot take a histogram observation.
- **IT-020**: Reset the metrics and verify a summary's earlier observations no longer affect its quantiles.
- **IT-021**: Load the module on its own and verify nothing optional is loaded ahead of it; in such a shell count and render, verify a summary stops naming `dybatpho::load math` and a push stops naming `dybatpho::load network`, and verify a summary renders once `math` is loaded.
- **IT-022**: Render a summary that has been declared but has no sample, and a type the renderer does not expand, and verify each prints its `# HELP` and `# TYPE` lines and no series.
- **IT-023**: Push recorded metrics to a mocked Pushgateway and verify the URL with grouping labels, the `PUT` method, the content type, and the exposition body.
- **IT-024**: Push with `--add` and verify `POST` is used.
- **IT-025**: Push with a job and grouping values that are empty, contain a `/`, a space, and non-ASCII text, and verify the base64url and percent encodings in the URL.
- **IT-026**: Push to a mocked Pushgateway that answers 400 with an explanation and verify the exit code `4` and the logged error text.
- **IT-027**: Push with nothing recorded and under `DRY_RUN`, and verify no request reaches the gateway.
- **IT-028**: Reject a URL without a scheme, an empty job, a malformed grouping label, an invalid label name, and a grouping label named `job`.
- **IT-029**: Refuse a bad name and a bad label in `metrics_time` without running the command, a bad name in `metrics_timer_start`, and a bad label in `metrics_timer_stop`, each under its own name.
- **IT-030**: Record a summary, make `DYBATPHO_METRICS_QUANTILES` invalid, push, and fail under the name of `metrics_push` without sending a request.
- **IT-031**: Time a command that reads variables named like the timer's locals and assigns to one, and see the caller's values and the metric recorded under its own name.

## Acceptance Criteria *(mandatory)*

1. Measurement is opt-in by loading the module, and free of effect when it is not loaded.
2. The exported text is valid Prometheus exposition format.
3. A script's behavior and exit codes are unchanged by measuring it.
