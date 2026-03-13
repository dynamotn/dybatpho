# process.sh

Utilities for process handling

> 🧭 Source: [src/process.sh](../src/process.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for script termination, signal handling, trap
composition, deferred cleanup, and dry-run execution.



### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_USED_ERR_HANDLER`** | bool | Internal flag set after `dybatpho::register_err_handler` |
| **`DYBATPHO_USED_KILLED_HANDLER`** | bool | Internal flag set after `dybatpho::register_killed_handler` |
| **`DRY_RUN`** | string | When true-like, `dybatpho::dry_run` prints commands instead of executing them |

### 🚀 Highlights

- [`dybatpho::die`](#dybatphodie) — Log a fatal message and stop the current script or process.
- [`dybatpho::register_err_handler`](#dybatphoregister_err_handler) — Register the ERR trap handler used by dybatpho scripts.
- [`dybatpho::register_killed_handler`](#dybatphoregister_killed_handler) — Register handlers for SIGINT and SIGTERM.
- [`dybatpho::register_common_handlers`](#dybatphoregister_common_handlers) — Register both error and signal handlers.
- [`dybatpho::run_err_handler`](#dybatphorun_err_handler) — Handle a command failure captured by `dybatpho::register_err_handler`.
- [`dybatpho::killed_process_handler`](#dybatphokilled_process_handler) — Handle SIGINT or SIGTERM received by the current process.
- [`dybatpho::trap`](#dybatphotrap) — Append a command to one or more trap handlers without discarding existing traps.
- [`_gen_finalize_command`](#_gen_finalize_command) — Read the current trap command registered for a signal.
- [`dybatpho::cleanup_file_on_exit`](#dybatphocleanup_file_on_exit) — Register a file or directory to be removed when the current shell exits.
- [`dybatpho::dry_run`](#dybatphodry_run) — Print a shell command instead of executing it when `DRY_RUN` is enabled.

<a id="see-also"></a>
## 🔗 See also

- [example/process_ops.sh](../example/process_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::register_common_handlers`

- This is the usual one-line setup at the top of scripts that want both error and signal handling

### `dybatpho::cleanup_file_on_exit`

- `dybatpho::create_temp` already uses this internally, so call it directly only for custom temporary paths

### `dybatpho::dry_run`

- Pass a single shell command string because this helper executes the command with `eval`

<a id="reference"></a>
## 📚 Reference

### `dybatpho::die`

Log a fatal message and stop the current script or process.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |
| `$2` | number | Exit code, default is 1 |

**🚦 Exit codes**

- `$2`: Exit the current shell with the requested code


---

### `dybatpho::register_err_handler`

Register the ERR trap handler used by dybatpho scripts.

_Function has no arguments._

**🧩 Variable sets**

- DYBATPHO_USED_ERR_HANDLER


---

### `dybatpho::register_killed_handler`

Register handlers for SIGINT and SIGTERM.

_Function has no arguments._

**🧩 Variable sets**

- DYBATPHO_USED_KILLED_HANDLER


---

### `dybatpho::register_common_handlers`

Register both error and signal handlers.

_Function has no arguments._


---

### `dybatpho::run_err_handler`

Handle a command failure captured by `dybatpho::register_err_handler`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Exit code of last command |


---

### `dybatpho::killed_process_handler`

Handle SIGINT or SIGTERM received by the current process.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Signal |


---

### `dybatpho::trap`

Append a command to one or more trap handlers without discarding existing traps.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command to run when the signal is trapped |
| `$@` | string | Signals to trap |


---

### `_gen_finalize_command`

Read the current trap command registered for a signal.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Signal name |

**📤 Output on stdout**

- Existing trap command, or an empty string when none is registered


---

### `dybatpho::cleanup_file_on_exit`

Register a file or directory to be removed when the current shell exits.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File or directory path |


---

### `dybatpho::dry_run`

Print a shell command instead of executing it when `DRY_RUN` is enabled.

**🧪 Examples**

```bash
DRY_RUN=true
dybatpho::dry_run "rm -rf ./build"

```

```bash
dybatpho::dry_run "ssh ${host} 'systemctl restart app'"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Shell command string to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | Set to `true`, `yes`, `on`, or `0` to print commands instead of executing them |

**📤 Output on stdout**

- Show the command instead of executing it when `DRY_RUN` is true

