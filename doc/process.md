# process.sh

Utilities for process handling

> 🧭 Source: [src/process.sh](../src/process.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for script termination, signal handling, trap
composition, deferred cleanup, and dry-run execution. It also bounds how
long a command may run, supervises named background jobs, and reads and
writes PID files.



### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_USED_ERR_HANDLER`** | bool | Internal flag set after `dybatpho::register_err_handler` |
| **`DYBATPHO_USED_KILLED_HANDLER`** | bool | Internal flag set after `dybatpho::register_killed_handler` |
| **`DRY_RUN`** | string | When true-like, `dybatpho::dry_run` prints commands instead of executing them |
| **`DYBATPHO_CLEANUP_PATHS`** | array | Paths registered by `dybatpho::cleanup_file_on_exit`, each as `<pid>:<path>` |
| **`DYBATPHO_TIMEOUT_KILL_AFTER`** | number | Seconds between SIGTERM and SIGKILL when a timed or background job is ended, default is `5` |
| **`DYBATPHO_BACKGROUND_NAMES`** | array | Names of the background jobs started by `dybatpho::background_run`, in submission order |
| **`DYBATPHO_BACKGROUND_PIDS`** | array | Process ID of each background job, keyed by job name |
| **`DYBATPHO_BACKGROUND_STATUS`** | array | Exit code of each background job that `dybatpho::wait_all` has reaped, keyed by job name |

### 🚀 Highlights

- [`dybatpho::die`](#dybatphodie) — Log a fatal message and stop the current script or process.
- [`dybatpho::register_err_handler`](#dybatphoregister_err_handler) — Register the ERR trap handler used by dybatpho scripts.
- [`dybatpho::register_killed_handler`](#dybatphoregister_killed_handler) — Register handlers for SIGINT and SIGTERM.
- [`dybatpho::register_common_handlers`](#dybatphoregister_common_handlers) — Register both error and signal handlers.
- [`dybatpho::run_err_handler`](#dybatphorun_err_handler) — Handle a command failure captured by `dybatpho::register_err_handler`.
- [`dybatpho::killed_process_handler`](#dybatphokilled_process_handler) — Handle SIGINT or SIGTERM received by the current process.
- [`dybatpho::trap`](#dybatphotrap) — Append a command to one or more trap handlers without discarding existing traps.
- [`__dybatpho_process_gen_finalize_command`](#__dybatpho_process_gen_finalize_command) — Read the current trap command registered for a signal.
- [`__dybatpho_cleanup_run`](#__dybatpho_cleanup_run) — Remove every path registered by `dybatpho::cleanup_file_on_exit` from the current shell. Paths registered by another shell are left alone, so a subshell exiting does not delete the temporary files its parent still needs.
- [`dybatpho::cleanup_file_on_exit`](#dybatphocleanup_file_on_exit) — Register a file or directory to be removed when the current shell exits.
- [`dybatpho::dry_run`](#dybatphodry_run) — Print a shell command instead of executing it when `DRY_RUN` is enabled.
- [`__dybatpho_process_forget_cleanup`](#__dybatpho_process_forget_cleanup) — Drop a path from the deferred-cleanup registry. A temporary file that a function removes itself leaves its registration behind, and a script that times hundreds of commands would carry one dead entry per call to the end of the run.
- [`__dybatpho_process_has_timeout`](#__dybatpho_process_has_timeout) — Report whether the system `timeout` is a coreutils one. Only GNU and uutils coreutils are trusted: BusyBox `timeout` accepts `-k` but reports a timeout as 143 rather than 124, which would break the exit code this helper promises. The probe runs once and its answer is cached, because the alternative is spawning a process on every timed command.
- [`__dybatpho_process_end_job`](#__dybatpho_process_end_job) — End a background job, and whatever it started, with SIGTERM and then SIGKILL. A job launched under job control leads its own process group, so the group is signalled first: ending the job alone would orphan its children, which is the usual way a "killed" build leaves a compiler running. The group kill is only attempted for a job that does lead its own group, never as a blind fallback, because a job that shares the caller's process group would take the calling script down with it.
- [`__dybatpho_process_timeout_fallback`](#__dybatpho_process_timeout_fallback) — Run a command under a time limit without the `timeout` binary. The command runs under job control so it leads its own process group, and a watchdog subshell ends that group once the limit elapses. The watchdog records that it fired by creating a marker file, rather than leaving the answer to the exit status: a command killed by SIGTERM and a command that chose to exit 143 are indistinguishable otherwise, and only the first is a timeout.
- [`dybatpho::run_with_timeout`](#dybatphorun_with_timeout) — Run a command and end it if it takes too long. The system `timeout` is used when it is available and usable, and a pure-Bash watchdog takes over when it is not, which is the common case on macOS, where coreutils is not installed by default. A shell function always takes the Bash path, because `timeout` executes a program and cannot see the caller's functions. The command is ended with SIGTERM first and SIGKILL afterwards, so a job that traps SIGTERM still gets to clean up before it is removed, and one that ignores it is still removed.
- [`dybatpho::background_run`](#dybatphobackground_run) — Start a command in the background under a name. The name is how every other helper in this group refers to the job, because a process ID is both unreadable in a script and unusable once the job has been reaped. Starting a second job under a name whose job is still running is refused rather than silently forgetting the first one. The job runs in a subshell of the calling shell, so it can call any function the caller has defined, and it leads its own process group, so `dybatpho::kill_children` can end its children along with it.
- [`dybatpho::background_pid`](#dybatphobackground_pid) — Print the process ID of a background job.
- [`dybatpho::background_status`](#dybatphobackground_status) — Print the exit code of a background job that has finished. The code is only known once the job has been waited for, which is what `dybatpho::wait_all` does; before that the job has no exit code to report.
- [`dybatpho::wait_all`](#dybatphowait_all) — Wait for every background job started by `dybatpho::background_run`. Each job's exit code is recorded under its name instead of being collapsed into one status, because `wait` on its own reports only the last job and a script that started three of them needs to know which one failed.
- [`dybatpho::kill_children`](#dybatphokill_children) — End every background job started by `dybatpho::background_run`, together with the processes those jobs started. Each job is signalled with SIGTERM and then, if it is still there, SIGKILL, and is waited for afterwards so it does not linger as a zombie. The registry is emptied, so the same names can be started again.
- [`dybatpho::pid_file_write`](#dybatphopid_file_write) — Write a process ID to a PID file. The file is written to a neighbouring temporary file and moved into place, so a reader never sees a half-written or empty PID file, the state that makes a supervisor believe a healthy service is dead.
- [`dybatpho::pid_file_is_running`](#dybatphopid_file_is_running) — Report whether the process recorded in a PID file is still alive. A missing file, an empty one, one holding something other than a number, and one holding a process that has since exited all answer the same way: nothing is running. That is what callers act on, and separating "no PID file" from "stale PID file" only moves the decision up one level.
- [`dybatpho::pid_file_remove`](#dybatphopid_file_remove) — Remove a PID file, but only when it records the given process. The guard is the point: a service that exits after a replacement has already written its own PID file would otherwise delete the live one on its way out, and the supervisor would then start a second copy.

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

### `dybatpho::run_with_timeout`

- Compare the exit code against 124 to tell a timeout apart from a command that failed on its own

### `dybatpho::wait_all`

- Call `dybatpho::background_status <name>` afterwards to see which job failed and how

### `dybatpho::kill_children`

- Register it on a trap (`dybatpho::trap dybatpho::kill_children EXIT INT TERM`) so an interrupted script leaves nothing behind

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

### `__dybatpho_process_gen_finalize_command`

Read the current trap command registered for a signal.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Signal name |

**📤 Output on stdout**

- Existing trap command, or an empty string when none is registered


---

### `__dybatpho_cleanup_run`

Remove every path registered by `dybatpho::cleanup_file_on_exit`
  from the current shell. Paths registered by another shell are left alone, so
  a subshell exiting does not delete the temporary files its parent still
  needs.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Always, so a failed removal cannot change the shell's exit status


---

### `dybatpho::cleanup_file_on_exit`

Register a file or directory to be removed when the current shell exits.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File or directory path |

**📝 Notes**

- Paths are collected in `DYBATPHO_CLEANUP_PATHS` and removed by a single trap installed on first use, rather than one trap command per path: a script that creates many temporary files would otherwise build a trap string that grows with every one of them.


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


---

### `__dybatpho_process_forget_cleanup`

Drop a path from the deferred-cleanup registry.
  A temporary file that a function removes itself leaves its registration
  behind, and a script that times hundreds of commands would carry one dead
  entry per call to the end of the run.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to forget |

**🧩 Variable sets**

- DYBATPHO_CLEANUP_PATHS


---

### `__dybatpho_process_has_timeout`

Report whether the system `timeout` is a coreutils one.
  Only GNU and uutils coreutils are trusted: BusyBox `timeout` accepts `-k`
  but reports a timeout as 143 rather than 124, which would break the exit
  code this helper promises. The probe runs once and its answer is cached,
  because the alternative is spawning a process on every timed command.

_Function has no arguments._

**🚦 Exit codes**

- `0`: A coreutils `timeout -k` is usable
- `1`: There is no `timeout`, or it is not a coreutils one


---

### `__dybatpho_process_end_job`

End a background job, and whatever it started, with SIGTERM and
  then SIGKILL.
  A job launched under job control leads its own process group, so the group
  is signalled first: ending the job alone would orphan its children, which is
  the usual way a "killed" build leaves a compiler running. The group kill is
  only attempted for a job that does lead its own group, never as a blind
  fallback, because a job that shares the caller's process group would take
  the calling script down with it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Process ID of the job, which is also its process group ID |
| `$2` | bool | Whether the job leads its own process group |
| `$3` | number | Seconds to wait after SIGTERM before sending SIGKILL |

**🚦 Exit codes**

- `0`: Always, so a job that already exited cannot fail the caller


---

### `__dybatpho_process_timeout_fallback`

Run a command under a time limit without the `timeout` binary.
  The command runs under job control so it leads its own process group, and a
  watchdog subshell ends that group once the limit elapses. The watchdog
  records that it fired by creating a marker file, rather than leaving the
  answer to the exit status: a command killed by SIGTERM and a command that
  chose to exit 143 are indistinguishable otherwise, and only the first is a
  timeout.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Seconds to allow |
| `$2` | number | Seconds between SIGTERM and SIGKILL |
| `$@` | string | Command and arguments |

**🚦 Exit codes**

- `124`: The command was still running when the limit elapsed
- `*`: Exit code of the command


---

### `dybatpho::run_with_timeout`

Run a command and end it if it takes too long.
  The system `timeout` is used when it is available and usable, and a
  pure-Bash watchdog takes over when it is not, which is the common case on
  macOS, where coreutils is not installed by default. A shell function always
  takes the Bash path, because `timeout` executes a program and cannot see the
  caller's functions.


  The command is ended with SIGTERM first and SIGKILL afterwards, so a job
  that traps SIGTERM still gets to clean up before it is removed, and one that
  ignores it is still removed.

**🧪 Examples**

```bash
dybatpho::run_with_timeout 30 curl -fsSL https://example.com

```

```bash
# A shell function works too, unlike with the `timeout` binary.
dybatpho::run_with_timeout 5 my_slow_function argument

```

```bash
dybatpho::run_with_timeout 30 ./deploy.sh || {
  (($? == 124)) && dybatpho::die "Deploy did not finish in 30s"
}

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Seconds to allow, or `0` to run without a limit |
| `$@` | string | Command and arguments |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TIMEOUT_KILL_AFTER`** | number | Seconds between SIGTERM and SIGKILL, default is `5` |

**🚦 Exit codes**

- `124`: The command was still running when the limit elapsed
- `*`: Exit code of the command


---

### `dybatpho::background_run`

Start a command in the background under a name.
  The name is how every other helper in this group refers to the job, because
  a process ID is both unreadable in a script and unusable once the job has
  been reaped. Starting a second job under a name whose job is still running
  is refused rather than silently forgetting the first one.


  The job runs in a subshell of the calling shell, so it can call any function
  the caller has defined, and it leads its own process group, so
  `dybatpho::kill_children` can end its children along with it.

**🧪 Example**

```bash
dybatpho::background_run api ./serve.sh --port 8080
dybatpho::background_run worker ./worker.sh
dybatpho::wait_all || dybatpho::die "A background job failed"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name for the job |
| `$@` | string | Command and arguments |

**🧩 Variable sets**

- DYBATPHO_BACKGROUND_PIDS
- DYBATPHO_BACKGROUND_NAMES

**🚦 Exit codes**

- `0`: The job was started
- `1`: Stop the script when the name is invalid, already running, or no command was given


---

### `dybatpho::background_pid`

Print the process ID of a background job.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Job name |

**📤 Output on stdout**

- Process ID of the job

**🚦 Exit codes**

- `0`: The job is known
- `1`: No job was started under that name


---

### `dybatpho::background_status`

Print the exit code of a background job that has finished.
  The code is only known once the job has been waited for, which is what
  `dybatpho::wait_all` does; before that the job has no exit code to report.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Job name |

**📤 Output on stdout**

- Exit code of the job

**🚦 Exit codes**

- `0`: The job has finished and its exit code was printed
- `1`: The job is unknown, or has not been waited for yet


---

### `dybatpho::wait_all`

Wait for every background job started by `dybatpho::background_run`.
  Each job's exit code is recorded under its name instead of being collapsed
  into one status, because `wait` on its own reports only the last job and a
  script that started three of them needs to know which one failed.

_Function has no arguments._

**🧩 Variable sets**

- DYBATPHO_BACKGROUND_STATUS

**🚦 Exit codes**

- `0`: Every job succeeded, or there were none
- `1`: At least one job failed


---

### `dybatpho::kill_children`

End every background job started by `dybatpho::background_run`,
  together with the processes those jobs started.
  Each job is signalled with SIGTERM and then, if it is still there, SIGKILL,
  and is waited for afterwards so it does not linger as a zombie. The registry
  is emptied, so the same names can be started again.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TIMEOUT_KILL_AFTER`** | number | Seconds between SIGTERM and SIGKILL, default is `5` |

**🧩 Variable sets**

- DYBATPHO_BACKGROUND_PIDS
- DYBATPHO_BACKGROUND_NAMES

**🚦 Exit codes**

- `0`: Always, so a job that had already exited cannot fail the caller


---

### `dybatpho::pid_file_write`

Write a process ID to a PID file.
  The file is written to a neighbouring temporary file and moved into place,
  so a reader never sees a half-written or empty PID file, the state that
  makes a supervisor believe a healthy service is dead.

**🧪 Example**

```bash
dybatpho::pid_file_write /var/run/app.pid
dybatpho::trap 'dybatpho::pid_file_remove /var/run/app.pid' EXIT

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path of the PID file |
| `$2` | number | Process ID to record, default is the current script's `$$` |

**📝 Notes**

- `$$` is the script's own process ID and stays the same inside a subshell, which is what a PID file is expected to hold. Pass `${BASHPID}` explicitly to record a subshell instead.

**🚦 Exit codes**

- `0`: The PID file was written
- `1`: Stop the script when the process ID is not a number or the file cannot be written


---

### `dybatpho::pid_file_is_running`

Report whether the process recorded in a PID file is still alive.
  A missing file, an empty one, one holding something other than a number, and
  one holding a process that has since exited all answer the same way: nothing
  is running. That is what callers act on, and separating "no PID file" from
  "stale PID file" only moves the decision up one level.

**🧪 Example**

```bash
if dybatpho::pid_file_is_running /var/run/app.pid; then
  dybatpho::die "Already running"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path of the PID file |

**📝 Notes**

- A PID file whose process has exited can be reused by an unrelated process that happens to receive the same ID, which no PID file can detect; use `dybatpho::lock_acquire` when the answer has to be exact.

**🚦 Exit codes**

- `0`: The recorded process is running
- `1`: There is no readable PID file, its contents are not a process ID, or that process has exited


---

### `dybatpho::pid_file_remove`

Remove a PID file, but only when it records the given process.
  The guard is the point: a service that exits after a replacement has already
  written its own PID file would otherwise delete the live one on its way out,
  and the supervisor would then start a second copy.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path of the PID file |
| `$2` | number | Process ID the file must record, default is the current script's `$$` |

**🚦 Exit codes**

- `0`: The file was removed, or was already gone
- `1`: The file records a different process and was left alone

