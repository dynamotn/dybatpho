# logging.sh

Utilities for logging to stdout/stderr

> 🧭 Source: [src/logging.sh](../src/logging.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to log messages to stdout/stderr.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Runtime log level for all messages (`trace\|debug\|info\|warn\|error\|fatal`). Default is `info` |
| **`NO_COLOR`** | string | Disable ANSI colors when set to a non-empty value |

### 🚀 Highlights

- [`__log`](#__log) — Log a message to stdout or stderr, optionally with ANSI color.
- [`__check_color`](#__check_color) — Render the current log message with ANSI color unless `NO_COLOR` is set.
- [`dybatpho::compare_log_level`](#dybatphocompare_log_level) — Return success when a message level should be shown for the current `LOG_LEVEL`.
- [`__log_inspect`](#__log_inspect) — Log a structured diagnostic message with timestamp and call-site information.
- [`__get_terminal_width`](#__get_terminal_width) — Return the effective terminal width used by boxed logging helpers.
- [`__string_display_width`](#__string_display_width) — Return the display width of a string, accounting for wide Unicode glyphs when possible.
- [`__wrap_line`](#__wrap_line) — Wrap one text line to the requested width using word boundaries when possible.
- [`__log_box`](#__log_box) — Render a boxed message sized to its content while respecting terminal width.
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
- [`dybatpho::start_trace`](#dybatphostart_trace) — Enable Bash tracing with dybatpho formatting.
- [`dybatpho::end_trace`](#dybatphoend_trace) — Disable Bash tracing started by `dybatpho::start_trace`.

<a id="see-also"></a>
## 🔗 See also

- [example/logging_demo.sh](../example/logging_demo.sh)

<a id="reference"></a>
## 📚 Reference

### `__log`

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

### `__check_color`

Render the current log message with ANSI color unless `NO_COLOR` is set.

_Function has no arguments._

**📤 Output on stdout**

- Message text for the active log call


---

### `dybatpho::compare_log_level`

Return success when a message level should be shown for the current `LOG_LEVEL`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input log level |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`LOG_LEVEL`** | string | Runtime threshold used to decide whether the message is emitted |

**🚦 Exit codes**

- `0`: The message level should be emitted
- `1`: The message level is filtered out


---

### `__log_inspect`

Log a structured diagnostic message with timestamp and call-site information.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Log level |
| `$2` | string | Rendered label for the log level |
| `$3` | string | Message |
| `$4` | number | Additional stack frames to skip when resolving the source location |
| `$5` | string | ANSI escape color code |


---

### `__get_terminal_width`

Return the effective terminal width used by boxed logging helpers.

**📤 Output on stdout**

- Terminal width, falling back to 80 columns


---

### `__string_display_width`

Return the display width of a string, accounting for wide Unicode glyphs when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text |

**📤 Output on stdout**

- Display width of the input


---

### `__wrap_line`

Wrap one text line to the requested width using word boundaries when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input line |
| `$2` | number | Maximum width |

**📤 Output on stdout**

- Wrapped lines


---

### `__log_box`

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

