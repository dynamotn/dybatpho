# metrics.sh

Utilities for measuring a script and exporting the result to Prometheus

> 🧭 Source: [src/metrics.sh](../src/metrics.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module records how long a script spends in a command, how often it
retried, and how many errors it hit, then renders the result in the
Prometheus text exposition format. Durations go into a histogram, with
cumulative buckets, or into a summary, which exports exact quantiles such
as the median and the 99th percentile.

Metrics live in the current shell only. Nothing is sent anywhere: a script
writes the rendered text to a file, and a collector such as the node
exporter's textfile collector picks it up. `dybatpho::metrics_write` writes
that file atomically, which is what the textfile collector requires in order
never to read a half-written file.

Durations are handled in whole milliseconds, because Bash has no floating
point arithmetic, and rendered in seconds, because that is the unit
Prometheus expects.

Loading this module also turns on the instrumentation that `helpers`,
`network`, and `logging` offer: retries, HTTP requests, and logged errors
are counted without the script asking for it.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_METRICS_BUCKETS_MS`** | string | Comma-separated histogram bucket bounds in milliseconds |
| **`DYBATPHO_METRICS_QUANTILES`** | string | Comma-separated quantiles a summary exports, each from `0` to `1` |
| **`DYBATPHO_METRICS_LAST_MS`** | number | Elapsed milliseconds published by the timing helpers |

### 🚀 Highlights

- [`dybatpho::metrics_help`](#dybatphometrics_help) — Describe a metric, so that the exported text explains it.
- [`dybatpho::metrics_counter_inc`](#dybatphometrics_counter_inc) — Add to a counter, a value that only ever grows.
- [`dybatpho::metrics_gauge_set`](#dybatphometrics_gauge_set) — Set a gauge, a value that can go up and down.
- [`dybatpho::metrics_observe_ms`](#dybatphometrics_observe_ms) — Record one duration in a histogram. The value is taken in milliseconds because that is what Bash can measure with integer arithmetic, and exported in seconds because that is what Prometheus expects.
- [`dybatpho::metrics_summary_ms`](#dybatphometrics_summary_ms) — Record one duration in a summary, which exports quantiles. A histogram only says how many observations fell under each bucket bound, and a dashboard estimates percentiles from that. A summary keeps every observation for the life of the shell and exports the exact quantiles listed in `DYBATPHO_METRICS_QUANTILES`, interpolated the way `dybatpho::math_percentile` does, together with `_sum` and `_count`. That suits a script, which records tens or hundreds of durations and exits; a long-running loop that records without end should use a histogram.
- [`dybatpho::metrics_timer_start`](#dybatphometrics_timer_start) — Start a named timer.
- [`dybatpho::metrics_timer_stop`](#dybatphometrics_timer_stop) — Stop a timer, record its duration, and print the elapsed milliseconds.
- [`dybatpho::metrics_time`](#dybatphometrics_time) — Run a command, record how long it took, and pass its exit code on. The duration is recorded whether the command succeeded or not, and a failure also increments a failure counter named after the metric, so that a dashboard can show latency and error rate from the same run: `deploy_duration_seconds` pairs with `deploy_failures_total`.
- [`dybatpho::metrics_get`](#dybatphometrics_get) — Read one series back, for a script that branches on its own measurements and for tests.
- [`dybatpho::metrics_reset`](#dybatphometrics_reset) — Forget every recorded metric.
- [`dybatpho::metrics_render`](#dybatphometrics_render) — Render every recorded metric in the Prometheus text exposition format.
- [`dybatpho::metrics_write`](#dybatphometrics_write) — Write the rendered metrics to a file, atomically. The node exporter's textfile collector reads whatever it finds whenever it scrapes, so the file has to appear complete or not at all.

<a id="see-also"></a>
## 🔗 See also

- [example/metrics_ops.sh](../example/metrics_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::metrics_summary_ms`

- `dybatpho::metrics_get sum` and `dybatpho::metrics_get count` read a summary's totals back in milliseconds, as they do for a histogram

### `dybatpho::metrics_timer_stop`

- The elapsed time is published in `DYBATPHO_METRICS_LAST_MS` rather than printed, because capturing output with `$(...)` would run the call in a subshell and throw away the measurement it just recorded

### `dybatpho::metrics_render`

- Durations are exported in seconds, so a metric name ending in `_seconds` reads correctly on a dashboard

<a id="reference"></a>
## 📚 Reference

### `dybatpho::metrics_help`

Describe a metric, so that the exported text explains it.

**🧪 Example**

```bash
dybatpho::metrics_help deploy_duration_seconds "How long a deployment took"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name |
| `$2` | string | Help text |


---

### `dybatpho::metrics_counter_inc`

Add to a counter, a value that only ever grows.

**🧪 Example**

```bash
dybatpho::metrics_counter_inc deploy_total
dybatpho::metrics_counter_inc http_requests_total 1 method=GET status=200

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name, conventionally ending in `_total` |
| `$2` | number | Amount to add, default `1` |
| `$@` | string | Label assignments such as `status=200` |

**🚦 Exit codes**

- `1`: The name, a label, or the amount is not valid


---

### `dybatpho::metrics_gauge_set`

Set a gauge, a value that can go up and down.

**🧪 Example**

```bash
dybatpho::metrics_gauge_set queue_depth 12
dybatpho::metrics_gauge_set build_info 1 version=2.0.0

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name |
| `$2` | number | Value, which may be negative or fractional |
| `$@` | string | Label assignments |

**🚦 Exit codes**

- `1`: The name, a label, or the value is not valid


---

### `dybatpho::metrics_observe_ms`

Record one duration in a histogram.
The value is taken in milliseconds because that is what Bash can measure
with integer arithmetic, and exported in seconds because that is what
Prometheus expects.

**🧪 Example**

```bash
dybatpho::metrics_observe_ms http_request_duration_seconds 143 host=example.com

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name, conventionally ending in `_seconds` |
| `$2` | number | Observed duration in whole milliseconds |
| `$@` | string | Label assignments |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_METRICS_BUCKETS_MS`** | string | Bucket bounds, in milliseconds |

**🚦 Exit codes**

- `1`: The name, a label, or the duration is not valid


---

### `dybatpho::metrics_summary_ms`

Record one duration in a summary, which exports quantiles.
A histogram only says how many observations fell under each bucket bound,
and a dashboard estimates percentiles from that. A summary keeps every
observation for the life of the shell and exports the exact quantiles listed
in `DYBATPHO_METRICS_QUANTILES`, interpolated the way
`dybatpho::math_percentile` does, together with `_sum` and `_count`. That
suits a script, which records tens or hundreds of durations and exits; a
long-running loop that records without end should use a histogram.

**🧪 Example**

```bash
dybatpho::metrics_summary_ms step_duration_seconds 143 step=fetch
dybatpho::metrics_render
# step_duration_seconds{step="fetch",quantile="0.5"} 0.143

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name, conventionally ending in `_seconds` |
| `$2` | number | Observed duration in whole milliseconds |
| `$@` | string | Label assignments |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_METRICS_QUANTILES`** | string | Quantiles to export, each from `0` to `1` |

**🚦 Exit codes**

- `1`: The name, a label, the duration or a quantile is not valid, or the metric is already a histogram


---

### `dybatpho::metrics_timer_start`

Start a named timer.

**🧪 Example**

```bash
dybatpho::metrics_timer_start build_duration_seconds
make
dybatpho::metrics_timer_stop build_duration_seconds stage=compile
dybatpho::info "Build took ${DYBATPHO_METRICS_LAST_MS}ms"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Timer name |


---

### `dybatpho::metrics_timer_stop`

Stop a timer, record its duration, and print the elapsed milliseconds.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Timer name, also used as the metric name |
| `$@` | string | Label assignments |

**🧩 Variable sets**

- **`DYBATPHO_METRICS_LAST_MS`** (number): Elapsed milliseconds of this timer

**🚦 Exit codes**

- `1`: The timer was never started


---

### `dybatpho::metrics_time`

Run a command, record how long it took, and pass its exit code on.
The duration is recorded whether the command succeeded or not, and a failure
also increments a failure counter named after the metric, so that a dashboard
can show latency and error rate from the same run:
`deploy_duration_seconds` pairs with `deploy_failures_total`.

**🧪 Example**

```bash
dybatpho::metrics_time deploy_duration_seconds stage=upload -- rsync -a ./dist/ host:/srv/

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name |
| `$@` | string | Label assignments, then `--`, then the command and its arguments |

**🧩 Variable sets**

- **`DYBATPHO_METRICS_LAST_MS`** (number): Elapsed milliseconds of the command

**🚦 Exit codes**

- `*`: The exit code of the command


---

### `dybatpho::metrics_get`

Read one series back, for a script that branches on its own
measurements and for tests.

**🧪 Example**

```bash
if (($(dybatpho::metrics_get counter http_requests_total status=500) > 0)); then
  dybatpho::warn "The run saw server errors"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Series kind, one of `counter`, `gauge`, `sum`, or `count` |
| `$2` | string | Metric name |
| `$@` | string | Label assignments |

**📤 Output on stdout**

- The recorded value, or `0` when the series has not been recorded

**🚦 Exit codes**

- `1`: The kind is unknown


---

### `dybatpho::metrics_reset`

Forget every recorded metric.

_Function has no arguments._


---

### `dybatpho::metrics_render`

Render every recorded metric in the Prometheus text exposition format.

**🧪 Example**

```bash
dybatpho::metrics_render
# HELP http_requests_total http_requests_total
# TYPE http_requests_total counter
http_requests_total{status="200"} 3

```

_Function has no arguments._

**📤 Output on stdout**

- Prometheus text exposition format, with metrics and series in a stable order


---

### `dybatpho::metrics_write`

Write the rendered metrics to a file, atomically.
The node exporter's textfile collector reads whatever it finds whenever it
scrapes, so the file has to appear complete or not at all.

**🧪 Example**

```bash
dybatpho::metrics_write /var/lib/node_exporter/textfile_collector/backup.prom

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination file path, conventionally ending in `.prom` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the write instead of performing it |

**🚦 Exit codes**

- `1`: The destination directory is missing or the write fails
