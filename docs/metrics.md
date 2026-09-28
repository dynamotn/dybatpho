# metrics.sh

Utilities for measuring a script and exporting the result to Prometheus

> 🧭 Source: [src/metrics.sh](../src/metrics.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module records how long a script spends in a command, how often it
retried, and how many errors it hit, then renders the result in the
Prometheus text exposition format.

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
| **`DYBATPHO_METRICS_LAST_MS`** | number | Elapsed milliseconds published by the timing helpers |

### 🚀 Highlights

- [`__dybatpho_metrics_validate_name`](#__dybatpho_metrics_validate_name) — Fail unless a string is a valid Prometheus metric or label name.
- [`__dybatpho_metrics_sort`](#__dybatpho_metrics_sort) — Sort an array in place, in Bash. `__log` calls into this module, and `__log` has to keep working where `PATH` is restricted, so nothing here may depend on an external command.
- [`__dybatpho_metrics_labels`](#__dybatpho_metrics_labels) — Turn `key=value` arguments into a rendered Prometheus label set. Labels are sorted so that the same set always produces the same series key, whatever order the caller passed them in.
- [`__dybatpho_metrics_key`](#__dybatpho_metrics_key) — Build the storage key for one series. The key is returned through a variable rather than standard output, because a command substitution would validate inside a subshell, where a rejected name or label could not stop the caller from recording the series anyway.
- [`__dybatpho_metrics_declare`](#__dybatpho_metrics_declare) — Record the type and help text of a metric, the first time it is seen.
- [`dybatpho::metrics_help`](#dybatphometrics_help) — Describe a metric, so that the exported text explains it.
- [`dybatpho::metrics_counter_inc`](#dybatphometrics_counter_inc) — Add to a counter, a value that only ever grows.
- [`dybatpho::metrics_gauge_set`](#dybatphometrics_gauge_set) — Set a gauge, a value that can go up and down.
- [`dybatpho::metrics_observe_ms`](#dybatphometrics_observe_ms) — Record one duration in a histogram. The value is taken in milliseconds because that is what Bash can measure with integer arithmetic, and exported in seconds because that is what Prometheus expects.
- [`dybatpho::metrics_timer_start`](#dybatphometrics_timer_start) — Start a named timer.
- [`dybatpho::metrics_timer_stop`](#dybatphometrics_timer_stop) — Stop a timer, record its duration, and print the elapsed milliseconds.
- [`dybatpho::metrics_time`](#dybatphometrics_time) — Run a command, record how long it took, and pass its exit code on. The duration is recorded whether the command succeeded or not, and a failure also increments a failure counter named after the metric, so that a dashboard can show latency and error rate from the same run: `deploy_duration_seconds` pairs with `deploy_failures_total`.
- [`dybatpho::metrics_get`](#dybatphometrics_get) — Read one series back, for a script that branches on its own measurements and for tests.
- [`dybatpho::metrics_reset`](#dybatphometrics_reset) — Forget every recorded metric.
- [`__dybatpho_metrics_seconds`](#__dybatpho_metrics_seconds) — Render whole milliseconds as the seconds value Prometheus expects.
- [`__dybatpho_metrics_series`](#__dybatpho_metrics_series) — Rewrite a series key with a name suffix and an optional extra label. `http_duration{host="a"}` becomes `http_duration_bucket{host="a",le="0.5"}`.
- [`dybatpho::metrics_render`](#dybatphometrics_render) — Render every recorded metric in the Prometheus text exposition format.
- [`__dybatpho_metrics_keys_of`](#__dybatpho_metrics_keys_of) — Print the series keys of one metric, in a stable order.
- [`dybatpho::metrics_write`](#dybatphometrics_write) — Write the rendered metrics to a file, atomically. The node exporter's textfile collector reads whatever it finds whenever it scrapes, so the file has to appear complete or not at all.

<a id="see-also"></a>
## 🔗 See also

- [example/metrics_ops.sh](../example/metrics_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `__dybatpho_metrics_key`

- The hooks in `helpers`, `logging`, and `network` test for this function to decide whether metrics are recordable. It is internal, so it never crosses a process boundary, which is exactly what makes it the right marker: a child shell inherits the exported `dybatpho::metrics_*` functions but not the helpers they call, and a guard on a public name would take the recording branch there and fail. Renaming this function means updating those guards.

### `dybatpho::metrics_timer_stop`

- The elapsed time is published in `DYBATPHO_METRICS_LAST_MS` rather than printed, because capturing output with `$(...)` would run the call in a subshell and throw away the measurement it just recorded

### `dybatpho::metrics_render`

- Durations are exported in seconds, so a metric name ending in `_seconds` reads correctly on a dashboard

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_metrics_validate_name`

Fail unless a string is a valid Prometheus metric or label name.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name to validate |
| `$2` | string | What the name is, used in the failure message |

**🚦 Exit codes**

- `1`: The name is not valid


---

### `__dybatpho_metrics_sort`

Sort an array in place, in Bash.
`__log` calls into this module, and `__log` has to keep working where `PATH`
is restricted, so nothing here may depend on an external command.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable to sort |


---

### `__dybatpho_metrics_labels`

Turn `key=value` arguments into a rendered Prometheus label set.
Labels are sorted so that the same set always produces the same series key,
whatever order the caller passed them in.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable that receives the rendered label set |
| `$@` | string | Label assignments such as `status=200` |

**🧩 Variable sets**

- **`The`** (named): variable, to the label set including braces, or empty when no labels were given

**🚦 Exit codes**

- `1`: An argument is not a `key=value` pair, or a key is not a valid name


---

### `__dybatpho_metrics_key`

Build the storage key for one series.
The key is returned through a variable rather than standard output, because
a command substitution would validate inside a subshell, where a rejected
name or label could not stop the caller from recording the series anyway.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable that receives the key |
| `$2` | string | Metric name |
| `$@` | string | Label assignments |

**🧩 Variable sets**

- **`The`** (named): variable, to the series key


---

### `__dybatpho_metrics_declare`

Record the type and help text of a metric, the first time it is seen.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name |
| `$2` | string | Metric type |


---

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

### `__dybatpho_metrics_seconds`

Render whole milliseconds as the seconds value Prometheus expects.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Milliseconds |

**📤 Output on stdout**

- Seconds with three decimal places


---

### `__dybatpho_metrics_series`

Rewrite a series key with a name suffix and an optional extra label.
`http_duration{host="a"}` becomes `http_duration_bucket{host="a",le="0.5"}`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Series key |
| `$2` | string | Suffix appended to the metric name |
| `$3` | string | Optional extra label, already rendered as `key="value"` |

**📤 Output on stdout**

- Rewritten series key


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

### `__dybatpho_metrics_keys_of`

Print the series keys of one metric, in a stable order.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Metric name |
| `$2` | string | Name of the associative array to read |

**📤 Output on stdout**

- Matching series keys, sorted


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
