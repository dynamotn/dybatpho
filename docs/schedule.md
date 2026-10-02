# schedule.sh

Deciding when a command should run, and running it on a cadence

> 🧭 Source: [src/schedule.sh](../src/schedule.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`helpers.sh` retries a call that failed. This module answers a different
question: should this run at all, and when next. It covers the three
shapes a script keeps reimplementing as a `sleep` loop — run every N
seconds, collapse a burst of triggers into one run, and run at most once
per day — plus a predicate for a cron expression, so a script can tell
whether it is due without a crontab entry.

The state that has to outlive the process lives on disk, under
`DYBATPHO_SCHEDULE_DIR`. That is what makes "at most once a day" hold
across separate invocations rather than only within one run, which is the
case a variable cannot cover.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SCHEDULE_DIR`** | string | Where markers live, default is `schedule` under the XDG state directory |
| **`DYBATPHO_SCHEDULE_DIR`** | string | Directory holding the markers that outlive a run |

### 🚀 Highlights

- [`__dybatpho_schedule_dir_into`](#__dybatpho_schedule_dir_into) — Resolve the directory markers are kept in, into a named variable, creating it if needed.
- [`__dybatpho_schedule_expect_key`](#__dybatpho_schedule_expect_key) — Stop when a key could name a file outside the marker directory.
- [`__dybatpho_schedule_command_into`](#__dybatpho_schedule_command_into) — Split `<args> -- <command...>`, leaving the command in a named array and checking there is one.
- [`dybatpho::schedule_every`](#dybatphoschedule_every) — Run a command on a fixed cadence until it is interrupted. The first run is immediate. The cadence is measured from when each run was due rather than from when the last one ended, so the schedule does not drift; a run that overruns its slot makes the missed ticks be skipped rather than queued, because catching up by running the same command four times in a row is never what the caller meant. `SIGINT`, `SIGTERM` and `SIGHUP` end the loop after the run in progress, and the handlers in place before the call are put back afterwards.
- [`dybatpho::schedule_debounce`](#dybatphoschedule_debounce) — Run a command once a burst of triggers has settled. Every trigger calls this. Each call registers itself, waits out the window, and then runs the command only if nothing else registered while it waited — so a burst of events produces exactly one run, after the burst ends rather than at its start. That is what an editor's write-then-rename needs: running on the first event would read a file that is still half written. The call blocks for the length of the window, so a trigger loop should call it in the background when it must keep reading events.
- [`dybatpho::schedule_once_per`](#dybatphoschedule_once_per) — Run a command at most once in each period. The marker is a file, so the limit holds across separate invocations of the script rather than only within one run. A named period is a calendar bucket -- `hour` means "once in this clock hour", not "once in any sixty minutes" -- while a number of seconds measures from the last run.
- [`__dybatpho_schedule_bucket_into`](#__dybatpho_schedule_bucket_into) — Work out the bucket a period puts the current time in.
- [`dybatpho::schedule_reset`](#dybatphoschedule_reset) — Forget what a key has recorded, so the next call runs.
- [`dybatpho::schedule_cron_due`](#dybatphoschedule_cron_due) — Return success when a time matches a cron expression. This answers "am I due", which is what a script run from an existing scheduler needs. It deliberately does not compute the next fire time: that needs a full calendar walk, and a half-right answer about when something will next run is worse than no answer. Fields are the usual five -- minute, hour, day of month, month, day of week -- each one `*`, a number, `a-b`, a comma-separated list, or any of those with a `/n` step. Sunday is `0` or `7`. When both day of month and day of week are restricted, the expression matches if **either** does, which is what cron itself does and what a hand-written check almost always gets wrong.
- [`__dybatpho_schedule_weekday_matches`](#__dybatpho_schedule_weekday_matches) — Match a day-of-week field, accepting `7` for Sunday.
- [`__dybatpho_schedule_field_matches`](#__dybatpho_schedule_field_matches) — Match one cron field against one value.

<a id="see-also"></a>
## 🔗 See also

- [example/schedule_ops.sh](../example/schedule_ops.sh)

<a id="tips"></a>
## 💡 Tips

- An interval is in whole seconds: `sleep` takes fractions on GNU but not everywhere, and this module keeps to what BusyBox also accepts

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_schedule_dir_into`

Resolve the directory markers are kept in, into a named
variable, creating it if needed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the directory |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_schedule_expect_key`

Stop when a key could name a file outside the marker directory.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Key |

**🚦 Exit codes**

- `0`: The key is safe to use as a file name
- `1`: Stop the script when it is not


---

### `__dybatpho_schedule_command_into`

Split `<args> -- <command...>`, leaving the command in a named
array and checking there is one.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the command |
| `$@` | string | The arguments following the separator |

**🧩 Variable sets**

- **`The`** (named): array


---

### `dybatpho::schedule_every`

Run a command on a fixed cadence until it is interrupted.
The first run is immediate. The cadence is measured from when each run was
due rather than from when the last one ended, so the schedule does not
drift; a run that overruns its slot makes the missed ticks be skipped
rather than queued, because catching up by running the same command four
times in a row is never what the caller meant.

`SIGINT`, `SIGTERM` and `SIGHUP` end the loop after the run in progress,
and the handlers in place before the call are put back afterwards.

**🧪 Example**

```bash
dybatpho::schedule_every 60 --times 5 -- dybatpho::info "tick"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Seconds between runs |
| `$2` | string | Options, then `--`, then the command |
| `$@` | string | Command and arguments, after `--` |

**🚦 Exit codes**

- `0`: The loop finished its runs, or was interrupted
- `1`: The interval or the run count is not a positive number


---

### `dybatpho::schedule_debounce`

Run a command once a burst of triggers has settled.
Every trigger calls this. Each call registers itself, waits out the
window, and then runs the command only if nothing else registered while it
waited — so a burst of events produces exactly one run, after the burst
ends rather than at its start. That is what an editor's
write-then-rename needs: running on the first event would read a file that
is still half written.

The call blocks for the length of the window, so a trigger loop should
call it in the background when it must keep reading events.

**🧪 Example**

```bash
dybatpho::schedule_debounce 2 rebuild -- make
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Seconds of quiet required before the command runs |
| `$2` | string | Key identifying the burst, shared by the triggers that belong together |
| `$3` | string | Literal `--` separating the key from the command |
| `$@` | string | Command and arguments to run |

**🚦 Exit codes**

- `0`: The command ran, and its own exit code is returned
- `1`: The window or the key is invalid
- `9`: A later trigger arrived, so this call did nothing


---

### `dybatpho::schedule_once_per`

Run a command at most once in each period.
The marker is a file, so the limit holds across separate invocations of
the script rather than only within one run. A named period is a calendar
bucket -- `hour` means "once in this clock hour", not "once in any sixty
minutes" -- while a number of seconds measures from the last run.

**🧪 Example**

```bash
dybatpho::schedule_once_per day warn-expiry -- dybatpho::warn "The token expires soon"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Period: `hour`, `day`, `month`, or a number of seconds |
| `$2` | string | Key identifying what is being limited |
| `$3` | string | Literal `--` separating the key from the command |
| `$@` | string | Command and arguments to run |

**🚦 Exit codes**

- `0`: The command ran, and its own exit code is returned
- `1`: The period or the key is invalid
- `9`: The command already ran in this period, so nothing was done


---

### `__dybatpho_schedule_bucket_into`

Work out the bucket a period puts the current time in.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the bucket |
| `$2` | string | Period name or a number of seconds |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `dybatpho::schedule_reset`

Forget what a key has recorded, so the next call runs.

**🧪 Example**

```bash
dybatpho::schedule_reset warn-expiry
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Key |

**🚦 Exit codes**

- `0`: The key's markers are gone, whether or not there were any
- `1`: The key is invalid


---

### `dybatpho::schedule_cron_due`

Return success when a time matches a cron expression.
This answers "am I due", which is what a script run from an existing
scheduler needs. It deliberately does not compute the next fire time: that
needs a full calendar walk, and a half-right answer about when something
will next run is worse than no answer.

Fields are the usual five -- minute, hour, day of month, month, day of
week -- each one `*`, a number, `a-b`, a comma-separated list, or any of
those with a `/n` step. Sunday is `0` or `7`.

When both day of month and day of week are restricted, the expression
matches if **either** does, which is what cron itself does and what a
hand-written check almost always gets wrong.

**🧪 Example**

```bash
dybatpho::schedule_cron_due "*/15 * * * *" && run_the_job
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cron expression, five fields |
| `$2` | number | Optional Unix timestamp to test, default is now |

**🚦 Exit codes**

- `0`: The time matches
- `1`: It does not
- `2`: The expression is malformed


---

### `__dybatpho_schedule_weekday_matches`

Match a day-of-week field, accepting `7` for Sunday.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field specification |
| `$2` | number | Day of week, `0` for Sunday |

**🚦 Exit codes**

- `0`: The field matches
- `1`: It does not


---

### `__dybatpho_schedule_field_matches`

Match one cron field against one value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field specification |
| `$2` | number | Value to test |
| `$3` | number | Lowest value the field allows, used when a step has no range |
| `$4` | number | Highest value the field allows |

**🚦 Exit codes**

- `0`: The field matches
- `1`: It does not
