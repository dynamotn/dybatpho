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

- [`__dybatpho_log`](#__dybatpho_log) — Log a message to stdout or stderr, optionally with ANSI color.
- [`__dybatpho_log_json_escape`](#__dybatpho_log_json_escape) — Escape a string for use as a JSON string value.
- [`__dybatpho_log_timestamp`](#__dybatpho_log_timestamp) — Return an RFC 3339 timestamp for a log event.
- [`__dybatpho_log_now_ms`](#__dybatpho_log_now_ms) — Return the current time in milliseconds since the epoch, using the most precise portable source available.
- [`__dybatpho_log_duration_ms`](#__dybatpho_log_duration_ms) — Return the elapsed time since the process started, for structured log events.
- [`__dybatpho_log_request_id`](#__dybatpho_log_request_id) — Return the correlation ID attached to every structured log event, generating and caching one when `LOG_REQUEST_ID` is empty.
- [`__dybatpho_log_hostname`](#__dybatpho_log_hostname) — Return the current hostname attached to every structured log event, caching the result for the process lifetime.
- [`__dybatpho_log_json_event`](#__dybatpho_log_json_event) — Build one structured JSON log event enriched with request ID, hostname, PID, duration, and the fields registered with `dybatpho::log_context`.
- [`__dybatpho_log_rotate_file`](#__dybatpho_log_rotate_file) — Rotate a log file in place once it reaches a size threshold, keeping a bounded number of numbered backups.
- [`__dybatpho_log_write_file`](#__dybatpho_log_write_file) — Append a structured JSON log event to `LOG_FILE` when it passes `LOG_FILE_LEVEL` filtering, rotating the file first when needed.
- [`__dybatpho_log_structured`](#__dybatpho_log_structured) — Log a diagnostic event as JSON when `LOG_FORMAT=json`.
- [`dybatpho::compare_log_level`](#dybatphocompare_log_level) — Return success when a message level should be shown against a threshold.
- [`__dybatpho_log_translate`](#__dybatpho_log_translate) — Translate a diagnostic dybatpho itself emitted, using the English text as its own message id the way gettext does, so that none of the several hundred `die`, `warn` and `error` call sites in the library has to be rewritten to use a key. The hook is inert unless the optional `i18n` module is loaded and translation of library messages was explicitly turned on, which keeps the default output byte for byte the same. The guard names an internal helper of that module on purpose: `dybatpho::` functions are exported and a child shell inherits them without the internals they call, so guarding on the public name would take the active branch in a child that never loaded `i18n`.
- [`__dybatpho_log_text`](#__dybatpho_log_text) — Translate a piece of dybatpho's own user interface that carries a value, such as a help heading or a parser error naming the switch it rejected. Unlike a diagnostic, that text cannot be its own message id once a value is baked into it, so the caller names a stable key and passes the English it would otherwise have printed. `cli` renders its help and parser errors through this helper as well. `logging` is a core module and owns the hook, so routing the call through here keeps the optional `i18n` module out of the dependency graph of both.
- [`__dybatpho_log_text_n`](#__dybatpho_log_text_n) — Translate a piece of dybatpho's own user interface that counts something, letting the target language pick the plural form rather than the English call site.
- [`__dybatpho_log_inspect`](#__dybatpho_log_inspect) — Log a structured diagnostic message with timestamp and call-site information. Also appends a JSON event to `LOG_FILE` when configured, independently of `LOG_FORMAT`.
- [`__dybatpho_log_get_terminal_width`](#__dybatpho_log_get_terminal_width) — Return the effective terminal width used by boxed logging helpers.
- [`__dybatpho_log_is_plain_ascii`](#__dybatpho_log_is_plain_ascii) — Return success when a string holds nothing but printable ASCII, which is the case where one character is exactly one terminal column and Bash can measure it on its own. `LC_ALL=C` is local to this function so the bracket range means bytes 0x20..0x7E rather than whatever the caller's collation makes of it.
- [`__dybatpho_log_char_at_into`](#__dybatpho_log_char_at_into) — Read the character that starts at an index, as UTF-8. Outside a UTF-8 locale Bash indexes a string by byte, so a glyph such as `✅` would be measured as three one-column characters and the box drawn around it would come out too wide. The lead byte gives the length of the sequence, which keeps the measure the same under the C locale.
- [`__dybatpho_log_indexes_bytes`](#__dybatpho_log_indexes_bytes) — Report whether Bash indexes strings by byte in this locale.
- [`__dybatpho_log_learn_widths`](#__dybatpho_log_learn_widths) — Fill the character-width cache for every non-ASCII character in a string that is not in it yet, in a single `python3` call. Width used to cost one process per measured string, so a twenty-row table paid eighty of them and a boxed `dybatpho::success` paid one per line. Caching per character rather than per string is what makes that cost amortize away: the library's own labels hold about ten distinct glyphs, and CJK text reuses its characters heavily, so a long run settles into no processes at all while still answering exactly what `python3` answers. Without `python3` every unknown character is recorded as one column, which is the answer the previous fallback gave.
- [`__dybatpho_log_width_into`](#__dybatpho_log_width_into) — Return the display width of a string, accounting for wide Unicode glyphs when possible.
- [`__dybatpho_log_repeat_into`](#__dybatpho_log_repeat_into) — Repeat a string, writing the result into a named variable. The renderers build padding one cell at a time, and reaching `dybatpho::string_repeat` through `$( )` forked once per cell.
- [`__dybatpho_log_string_display_width`](#__dybatpho_log_string_display_width) — Return the display width of a string, accounting for wide Unicode glyphs when possible.
- [`__dybatpho_log_wrap_line`](#__dybatpho_log_wrap_line) — Wrap one text line to the requested width using word boundaries when possible.
- [`__dybatpho_log_box`](#__dybatpho_log_box) — Render a boxed message sized to its content while respecting terminal width.
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
- [`__dybatpho_log_context_json`](#__dybatpho_log_context_json) — Render the fields registered with `dybatpho::log_context` as a JSON fragment ready to be spliced into a structured event. Values are redacted here rather than when the field is registered, so a secret registered after the fact is still masked on the next event.
- [`__dybatpho_log_context_text`](#__dybatpho_log_context_text) — Render the registered context fields for a human-readable line.
- [`__dybatpho_log_context_add`](#__dybatpho_log_context_add) — Register or update context fields from `name=value` pairs.
- [`__dybatpho_log_context_remove`](#__dybatpho_log_context_remove) — Drop context fields by name, ignoring names that are not set.
- [`__dybatpho_log_parse_size`](#__dybatpho_log_parse_size) — Convert a human-readable byte size into a plain byte count.
- [`__dybatpho_log_sleep`](#__dybatpho_log_sleep) — Pause for a fractional number of seconds, falling back to one whole second where `sleep` only understands integers.
- [`__dybatpho_log_spin`](#__dybatpho_log_spin) — Animate the spinner on stderr until the shell that started it kills it. Runs as a background job, so it never returns on its own.
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

### `__dybatpho_log`

Log a message to stdout or stderr, optionally with ANSI color.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level of message |
| `$2` | string | Message |
| `$3` | string | `stderr` to write to stderr, otherwise stdout |
| `$4` | string | ANSI escape color code |

**🧩 Variable sets**

- **`LOG_LEVEL`**: string Runtime log level of the current script

**📤 Output on stdout**

- Show the formatted message when the level passes filtering and $3 is not `stderr`

**📤 Output on stderr**

- Show the formatted message when the level passes filtering and $3 is `stderr`


---

### `__dybatpho_log_json_escape`

Escape a string for use as a JSON string value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text |

**📤 Output on stdout**

- JSON-escaped text without surrounding quotes


---

### `__dybatpho_log_timestamp`

Return an RFC 3339 timestamp for a log event.

**📤 Output on stdout**

- Current timestamp


---

### `__dybatpho_log_now_ms`

Return the current time in milliseconds since the epoch, using the most precise portable source available.

**📤 Output on stdout**

- Current time in milliseconds


---

### `__dybatpho_log_duration_ms`

Return the elapsed time since the process started, for structured log events.

**📤 Output on stdout**

- Elapsed time in milliseconds


---

### `__dybatpho_log_request_id`

Return the correlation ID attached to every structured log event, generating and caching one when `LOG_REQUEST_ID` is empty.

**🧩 Variable sets**

- **`LOG_REQUEST_ID`**: string Generated correlation ID, when it was previously empty

**📤 Output on stdout**

- Correlation ID


---

### `__dybatpho_log_hostname`

Return the current hostname attached to every structured log event, caching the result for the process lifetime.

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOG_HOSTNAME`** | string | Hostname to log instead of the one `dybatpho::hostname` detects |

**📤 Output on stdout**

- Hostname


---

### `__dybatpho_log_json_event`

Build one structured JSON log event enriched with request ID, hostname, PID, duration, and the fields registered with `dybatpho::log_context`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | RFC 3339 timestamp |
| `$2` | string | Log level |
| `$3` | string | Source location |
| `$4` | string | Message |
| `$5` | number | Duration in milliseconds since the process started |
| `$6` | string | Ready-made JSON fragment of extra fields, each one leading with its own comma |

**📤 Output on stdout**

- One JSON object followed by a newline


---

### `__dybatpho_log_rotate_file`

Rotate a log file in place once it reaches a size threshold, keeping a bounded number of numbered backups.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log file path |
| `$2` | number | Maximum size in bytes before rotating, `0` disables rotation |
| `$3` | number | Number of rotated backups to keep |


---

### `__dybatpho_log_write_file`

Append a structured JSON log event to `LOG_FILE` when it passes `LOG_FILE_LEVEL` filtering, rotating the file first when needed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level |
| `$2` | string | Source location |
| `$3` | string | Message |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_FILE`** | string | Destination file; no-op when empty |
| **`LOG_FILE_LEVEL`** | string | Verbosity threshold applied independently of `LOG_LEVEL` |
| **`LOG_FILE_MAX_BYTES`** | number | Rotation size threshold |
| **`LOG_FILE_MAX_BACKUPS`** | number | Number of rotated backups to keep |


---

### `__dybatpho_log_structured`

Log a diagnostic event as JSON when `LOG_FORMAT=json`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level |
| `$2` | string | Source location |
| `$3` | string | Message |
| `$4` | string | ANSI escape color code |
| `$5` | string | Ready-made JSON fragment of extra fields, each one leading with its own comma |


---

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

### `__dybatpho_log_translate`

Translate a diagnostic dybatpho itself emitted, using the English
  text as its own message id the way gettext does, so that none of the several
  hundred `die`, `warn` and `error` call sites in the library has to be
  rewritten to use a key.


  The hook is inert unless the optional `i18n` module is loaded and
  translation of library messages was explicitly turned on, which keeps the
  default output byte for byte the same. The guard names an internal helper of
  that module on purpose: `dybatpho::` functions are exported and a child
  shell inherits them without the internals they call, so guarding on the
  public name would take the active branch in a child that never loaded
  `i18n`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | The English message |

**📤 Output on stdout**

- The translation when one exists, otherwise the message unchanged


---

### `__dybatpho_log_text`

Translate a piece of dybatpho's own user interface that carries a
  value, such as a help heading or a parser error naming the switch it
  rejected. Unlike a diagnostic, that text cannot be its own message id once a
  value is baked into it, so the caller names a stable key and passes the
  English it would otherwise have printed.


  `cli` renders its help and parser errors through this helper as well.
  `logging` is a core module and owns the hook, so routing the call through
  here keeps the optional `i18n` module out of the dependency graph of both.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message key |
| `$2` | string | The English rendering, already complete |
| `$@` | string | `name=value` bindings for the translated template |

**📤 Output on stdout**

- The translation when one exists, otherwise $2 unchanged


---

### `__dybatpho_log_text_n`

Translate a piece of dybatpho's own user interface that counts
  something, letting the target language pick the plural form rather than the
  English call site.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message key |
| `$2` | number | Count |
| `$3` | string | The English rendering, already complete |
| `$@` | string | Further `name=value` bindings for the translated template |

**📤 Output on stdout**

- The translation when one exists, otherwise $3 unchanged


---

### `__dybatpho_log_inspect`

Log a structured diagnostic message with timestamp and call-site information. Also appends a JSON event to `LOG_FILE` when configured, independently of `LOG_FORMAT`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level |
| `$2` | string | Rendered label for the log level |
| `$3` | string | Message |
| `$4` | number | Additional stack frames to skip when resolving the source location |
| `$5` | string | ANSI escape color code |
| `$6` | string | Ready-made JSON fragment of extra fields, each one leading with its own comma |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_FILE`** | string | Optional file that receives a structured JSON event regardless of `LOG_FORMAT` |


---

### `__dybatpho_log_get_terminal_width`

Return the effective terminal width used by boxed logging helpers.

**📤 Output on stdout**

- Terminal width, falling back to 80 columns


---

### `__dybatpho_log_is_plain_ascii`

Return success when a string holds nothing but printable ASCII,
  which is the case where one character is exactly one terminal column and
  Bash can measure it on its own.


  `LC_ALL=C` is local to this function so the bracket range means bytes
  0x20..0x7E rather than whatever the caller's collation makes of it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to classify |

**🚦 Exit codes**

- `0`: The text is printable ASCII, optionally with tabs
- `1`: The text holds a character that may not be one column wide


---

### `__dybatpho_log_char_at_into`

Read the character that starts at an index, as UTF-8.
  Outside a UTF-8 locale Bash indexes a string by byte, so a glyph such as
  `✅` would be measured as three one-column characters and the box drawn
  around it would come out too wide. The lead byte gives the length of the
  sequence, which keeps the measure the same under the C locale.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the character |
| `$2` | string | Text to read from |
| `$3` | number | Index of the character's first byte or character |
| `$4` | bool | `1` when Bash is indexing by byte |

**🧩 Variable sets**

- **`The`**: named variable


---

### `__dybatpho_log_indexes_bytes`

Report whether Bash indexes strings by byte in this locale.

**🚦 Exit codes**

- `0`: Bash counts bytes, so multi-byte characters must be assembled
- `1`: Bash counts characters


---

### `__dybatpho_log_learn_widths`

Fill the character-width cache for every non-ASCII character in
  a string that is not in it yet, in a single `python3` call.


  Width used to cost one process per measured string, so a twenty-row table
  paid eighty of them and a boxed `dybatpho::success` paid one per line.
  Caching per character rather than per string is what makes that cost
  amortize away: the library's own labels hold about ten distinct glyphs, and
  CJK text reuses its characters heavily, so a long run settles into no
  processes at all while still answering exactly what `python3` answers.


  Without `python3` every unknown character is recorded as one column, which
  is the answer the previous fallback gave.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text whose characters to learn |

**🧩 Variable sets**

- __dybatpho_log_char_width_cache


---

### `__dybatpho_log_width_into`

Return the display width of a string, accounting for wide Unicode glyphs when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text |

**📤 Output on stdout**

- Display width of the input


---

### `__dybatpho_log_repeat_into`

Repeat a string, writing the result into a named variable.
  The renderers build padding one cell at a time, and reaching
  `dybatpho::string_repeat` through `$( )` forked once per cell.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the result |
| `$2` | string | Text to repeat |
| `$3` | number | Number of repetitions |

**🧩 Variable sets**

- **`The`**: named variable


---

### `__dybatpho_log_string_display_width`

Return the display width of a string, accounting for wide Unicode glyphs when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text |

**📤 Output on stdout**

- Display width of the input


---

### `__dybatpho_log_wrap_line`

Wrap one text line to the requested width using word boundaries when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input line |
| `$2` | number | Maximum width |

**📤 Output on stdout**

- Wrapped lines


---

### `__dybatpho_log_box`

Render a boxed message sized to its content while respecting terminal width.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Top-left border character |
| `$2` | string | Horizontal border character |
| `$3` | string | Top-right border character |
| `$4` | string | Left border character |
| `$5` | string | Right border character |
| `$6` | string | Bottom-left border character |
| `$7` | string | Bottom-right border character |
| `$8` | string | Message body |
| `$9` | string | Output stream (`stdout` or `stderr`) |
| `$10` | string | ANSI color code |


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

### `__dybatpho_log_context_json`

Render the fields registered with `dybatpho::log_context` as a
  JSON fragment ready to be spliced into a structured event.


  Values are redacted here rather than when the field is registered, so a
  secret registered after the fact is still masked on the next event.

**📤 Output on stdout**

- `,"name":"value"` for every registered field, in registration order


---

### `__dybatpho_log_context_text`

Render the registered context fields for a human-readable line.

**📤 Output on stdout**

- ` name=value` for every registered field, in registration order


---

### `__dybatpho_log_context_add`

Register or update context fields from `name=value` pairs.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | `name=value` pairs |

**🧩 Variable sets**

- __dybatpho_log_context_values
- __dybatpho_log_context_keys


---

### `__dybatpho_log_context_remove`

Drop context fields by name, ignoring names that are not set.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Field names |

**🧩 Variable sets**

- __dybatpho_log_context_values
- __dybatpho_log_context_keys


---

### `__dybatpho_log_parse_size`

Convert a human-readable byte size into a plain byte count.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Size such as `1048576`, `512K`, `10M` or `2GiB` |

**📤 Output on stdout**

- The size in bytes

**🚦 Exit codes**

- `1`: The input is not a size this function understands


---

### `__dybatpho_log_sleep`

Pause for a fractional number of seconds, falling back to one
  whole second where `sleep` only understands integers.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Seconds to wait |


---

### `__dybatpho_log_spin`

Animate the spinner on stderr until the shell that started it
  kills it. Runs as a background job, so it never returns on its own.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message shown beside the frame, already redacted |

**📤 Output on stderr**

- One frame per interval, redrawn over the same line


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

- **`LOG_FILE`**: string Path that receives the structured events
- **`LOG_FILE_MAX_BYTES`**: number Size threshold the file is rotated at
- **`LOG_FILE_MAX_BACKUPS`**: number Number of rotated backups kept
- **`LOG_FILE_LEVEL`**: string Verbosity threshold applied to the file alone

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

- **`DYBATPHO_TIMER_LAST_MS`**: number Elapsed milliseconds of this timer
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

