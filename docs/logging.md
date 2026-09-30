# logging.sh

Utilities for logging to stdout/stderr

> 🧭 Source: [src/logging.sh](../src/logging.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to log messages to stdout/stderr. Every
structured (JSON) log event is enriched with a request ID, hostname, PID,
and duration since the process started. Structured events can also be
appended to a rotating log file at an independent verbosity level.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Runtime log level for all messages (`trace\|debug\|info\|warn\|error\|fatal`). Default is `info` |
| **`LOG_FORMAT`** | string | Log output format (`text\|json`). Default is `text` |
| **`NO_COLOR`** | string | Disable ANSI colors when set to a non-empty value |
| **`LOG_REQUEST_ID`** | string | Correlation ID attached to every structured log event. Generated automatically when empty |
| **`LOG_FILE`** | string | Optional path to append structured JSON log lines to, independent of `LOG_FORMAT` |
| **`LOG_FILE_LEVEL`** | string | Verbosity threshold applied only to `LOG_FILE` output. Default is `LOG_LEVEL` |
| **`LOG_FILE_MAX_BYTES`** | number | Rotate `LOG_FILE` once it reaches this size in bytes. `0` disables rotation. Default `10485760` (10 MiB) |
| **`LOG_FILE_MAX_BACKUPS`** | number | Number of rotated `LOG_FILE` backups to keep. Default `5` |
| **`DYBATPHO_SPINNER`** | string | When `dybatpho::spinner` animates (`auto\|always\|never`). `auto` animates only on a terminal. Default `auto` |
| **`DYBATPHO_SPINNER_INTERVAL`** | string | Seconds between spinner frames. Default `0.1` |
| **`DYBATPHO_SPINNER_FRAMES`** | string | Space-separated frames the spinner cycles through |
| **`DYBATPHO_TIMER_LAST_MS`** | number | Elapsed milliseconds reported by the last `dybatpho::timer_end` |
| __dybatpho_log_context_values |  |  |
| __dybatpho_log_context_keys |  |  |
| __dybatpho_log_timer |  |  |
| __dybatpho_log_reserved_fields |  |  |
| __dybatpho_log_char_width_cache |  |  |

### 🚀 Highlights

- [`dybatpho::compare_log_level`](#dybatphocompare_log_level) — Return success when a message level should be shown against a threshold.
- [`dybatpho::validate_log_level`](#dybatphovalidate_log_level) — Validate a candidate log level value.
- [`dybatpho::debug`](#dybatphodebug) — Show debug message.
- [`dybatpho::debug_command`](#dybatphodebug_command) — Log a debug message together with the output of a shell command.
- [`dybatpho::info`](#dybatphoinfo) — Show info message.
- [`dybatpho::print`](#dybatphoprint) — Show normal message.
- [`dybatpho::progress`](#dybatphoprogress) — Show a highlighted in-progress banner.
- [`dybatpho::progress_bar`](#dybatphoprogress_bar) — Render a percentage-based progress bar on the current output line.
- [`dybatpho::header`](#dybatphoheader) — Show a section header banner.
- [`dybatpho::success`](#dybatphosuccess) — Show success message.
- [`dybatpho::warn`](#dybatphowarn) — Show warning message.
- [`dybatpho::error`](#dybatphoerror) — Show error message.
- [`dybatpho::fatal`](#dybatphofatal) — Show fatal message.
- [`dybatpho::log_to_file`](#dybatpholog_to_file) — Send structured JSON events to a file alongside the human-readable output on stderr, and keep that file bounded by rotating it. This is the front end to the `LOG_FILE*` variables: a script names the path once instead of exporting four of them, and gets the argument checking, the parent directory and a private mode along with it. Every registered secret is redacted before a line reaches the file, exactly as it is on stderr, so turning on a durable log never turns it into a place a token leaks to.
- [`dybatpho::log_context`](#dybatpholog_context) — Attach fields to every structured log event that follows, so a run identifier or a stage name rides along with each JSON line instead of being spelled out in every message. Text output carries the same fields after the message.
- [`dybatpho::timer_start`](#dybatphotimer_start) — Start a named timer whose elapsed time `dybatpho::timer_end` logs.
- [`dybatpho::timer_end`](#dybatphotimer_end) — Stop a named timer and log how long it ran. The structured event carries the timer name and its elapsed milliseconds as fields of their own, so a log aggregator can chart a step without parsing the message.
- [`dybatpho::spinner`](#dybatphospinner) — Run a command while a spinner reports that it is still going, then pass its exit code back unchanged. The command runs in the foreground of the calling shell, so it keeps stdin, its output goes where it would anyway, and its exit code is the one this function returns. Only the spinner runs in the background, and it is torn down before this returns whether the command succeeded or failed. Without a terminal on stderr -- in CI, or with output redirected -- there is nothing to animate, so the message is logged once at `info` instead and the command runs as usual.
- [`dybatpho::start_trace`](#dybatphostart_trace) — Enable Bash tracing with dybatpho formatting.
- [`dybatpho::end_trace`](#dybatphoend_trace) — Disable Bash tracing started by `dybatpho::start_trace`.

<a id="see-also"></a>
## 🔗 See also

- [example/logging_demo.sh](../example/logging_demo.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::log_to_file`

- `rotate:0` disables rotation, and a size may be given as bytes or with a `K`, `M`, `G` or `T` suffix
- A log file this function creates gets mode `600`; one that already exists keeps the mode it has

### `dybatpho::log_context`

- Fields are held in the current shell, so a child process starts with none of them; export `LOG_REQUEST_ID` to correlate across processes
- Registered secrets are redacted in field values the same way they are in messages

### `dybatpho::timer_start`

- This times a step so the log says how long it took; `dybatpho::metrics_timer_start` records the same measurement as a metric for a dashboard

### `dybatpho::timer_end`

- The elapsed time is published in `DYBATPHO_TIMER_LAST_MS` rather than printed, because capturing output with `$(...)` would run the call in a subshell and throw the measurement away

### `dybatpho::spinner`

- Registered secrets are redacted in the message before it is drawn

<a id="reference"></a>
## 📚 Reference

### `dybatpho::compare_log_level`

Return success when a message level should be shown against a threshold.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input log level |
| `$2` | string | Threshold level to compare against, default is `LOG_LEVEL` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Runtime threshold used to decide whether the message is emitted, when no explicit threshold is given |

**🚦 Exit codes**

- `0`: The message level should be emitted
- `1`: The message level is filtered out


---

### `dybatpho::validate_log_level`

Validate a candidate log level value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level to validate |

**🚦 Exit codes**

- `0`: The input is a supported log level
- `1`: The input is invalid


---

### `dybatpho::debug`

Show debug message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stderr**

- Show message if log level of message is less than debug level


---

### `dybatpho::debug_command`

Log a debug message together with the output of a shell command.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Introductory message |
| `$2` | string | Shell command string to evaluate |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Set to `debug` or `trace` to see this output |

**📤 Output on stderr**

- Show message if log level of message is less than debug level


---

### `dybatpho::info`

Show info message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stderr**

- Show message if log level of message is less than info level


---

### `dybatpho::print`

Show normal message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stdout**

- Show message if log level of message is less than info level


---

### `dybatpho::progress`

Show a highlighted in-progress banner.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stdout**

- Show message if log level of message is less than info level


---

### `dybatpho::progress_bar`

Render a percentage-based progress bar on the current output line.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Progress percentage from 0 to 100 |
| `$2` | number | Width of the progress bar in characters. Default is 50 |

**📤 Output on stdout**

- Show the progress bar; print a newline in the caller when the task is done


---

### `dybatpho::header`

Show a section header banner.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stdout**

- Show message if log level of message is less than info level


---

### `dybatpho::success`

Show success message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stdout**

- Show message if log level of message is less than info level


---

### `dybatpho::warn`

Show warning message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stderr**

- Show message if log level of message is less than warn level


---

### `dybatpho::error`

Show error message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**📤 Output on stderr**

- Show message if log level of message is less than error level


---

### `dybatpho::fatal`

Show fatal message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |
| `$2` | number | Number of call stack to get source file and line number when logging |

**📤 Output on stderr**

- Show message if log level of message is less than fatal level


---

### `dybatpho::log_to_file`

Send structured JSON events to a file alongside the
human-readable output on stderr, and keep that file bounded by rotating it.

This is the front end to the `LOG_FILE*` variables: a script names the path
once instead of exporting four of them, and gets the argument checking, the
parent directory and a private mode along with it. Every registered secret
is redacted before a line reaches the file, exactly as it is on stderr, so
turning on a durable log never turns it into a place a token leaks to.

**🧪 Example**

```bash
dybatpho::log_to_file /var/log/deploy.log rotate:10M keep:3 level:debug
dybatpho::info "Deploying"  # text on stderr, JSON in the file
dybatpho::log_to_file off   # stop writing to a file

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path of the log file, or `off` to stop file logging |
| `$@` | string | Optional `rotate:SIZE`, `keep:COUNT` and `level:LEVEL` settings |

**🧩 Variable sets**

- **`LOG_FILE`** (string): Path that receives the structured events
- **`LOG_FILE_MAX_BYTES`** (number): Size threshold the file is rotated at
- **`LOG_FILE_MAX_BACKUPS`** (number): Number of rotated backups kept
- **`LOG_FILE_LEVEL`** (string): Verbosity threshold applied to the file alone

**🚦 Exit codes**

- `1`: A setting is malformed, or the file cannot be written


---

### `dybatpho::log_context`

Attach fields to every structured log event that follows, so a
run identifier or a stage name rides along with each JSON line instead of
being spelled out in every message. Text output carries the same fields
after the message.

**🧪 Example**

```bash
dybatpho::log_context add run_id=abc stage=build
dybatpho::error "compilation failed"  # the event carries both fields
dybatpho::log_context remove stage
dybatpho::log_context clear

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | One of `add`, `remove`, `clear`, `list` or `get` |
| `$@` | string | `name=value` pairs for `add`, field names for `remove` and `get` |

**🧩 Variable sets**

- __dybatpho_log_context_values
- __dybatpho_log_context_keys

**📤 Output on stdout**

- One `name=value` per field for `list`, the bare value for `get`

**🚦 Exit codes**

- `1`: `get` was asked for a field that is not set


---

### `dybatpho::timer_start`

Start a named timer whose elapsed time `dybatpho::timer_end` logs.

**🧪 Example**

```bash
dybatpho::timer_start migration
./migrate.sh
dybatpho::timer_end migration

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Timer name |

**🧩 Variable sets**

- __dybatpho_log_timer


---

### `dybatpho::timer_end`

Stop a named timer and log how long it ran. The structured event
carries the timer name and its elapsed milliseconds as fields of their own,
so a log aggregator can chart a step without parsing the message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Timer name |
| `$2` | string | Level to log the duration at, default is `info` |

**🧩 Variable sets**

- **`DYBATPHO_TIMER_LAST_MS`** (number): Elapsed milliseconds of this timer
- __dybatpho_log_timer

**📤 Output on stderr**

- The duration message, at the requested level

**🚦 Exit codes**

- `1`: The requested level is not a valid log level


---

### `dybatpho::spinner`

Run a command while a spinner reports that it is still going,
then pass its exit code back unchanged.

The command runs in the foreground of the calling shell, so it keeps stdin,
its output goes where it would anyway, and its exit code is the one this
function returns. Only the spinner runs in the background, and it is torn
down before this returns whether the command succeeded or failed.

Without a terminal on stderr -- in CI, or with output redirected -- there is
nothing to animate, so the message is logged once at `info` instead and the
command runs as usual.

**🧪 Example**

```bash
dybatpho::spinner "Downloading dependencies" -- npm ci
dybatpho::spinner "Building" -- make -j4 || dybatpho::die "build failed"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message shown beside the spinner |
| `$2` | string | The literal `--` |
| `$@` | string | Command and arguments to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SPINNER`** | string | `never` to always skip the animation, `always` to force it |
| **`DYBATPHO_SPINNER_INTERVAL`** | string | Seconds between frames |
| **`DYBATPHO_SPINNER_FRAMES`** | string | Space-separated frames to cycle through |

**📤 Output on stderr**

- The animation while the command runs, then the line is erased

**🚦 Exit codes**

- `The`: exit code of the command


---

### `dybatpho::start_trace`

Enable Bash tracing with dybatpho formatting.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Set to `trace` to emit the trace start/end messages |


---

### `dybatpho::end_trace`

Disable Bash tracing started by `dybatpho::start_trace`.

_Function has no arguments._
