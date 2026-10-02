# parallel.sh

Utilities for running work concurrently with a bounded worker pool

> 🧭 Source: [src/parallel.sh](../src/parallel.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module runs a list of jobs several at a time and reports what each one
did. It exists because the hand-written version of this loop gets three
things wrong: it launches every job at once and overwhelms the machine, it
lets concurrent jobs interleave their output into an unreadable mess, and it
loses the exit code of everything except the last job.

Each job's output is captured while it runs and replayed afterwards in the
order the jobs were submitted, so the result reads as though the jobs had
run one after another. Each job's exit code is recorded separately, and the
run as a whole fails when any job failed.

A job runs in a subshell of the calling shell, so it can call any function
the caller has defined without exporting anything.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PARALLEL_JOBS`** | number | Default number of jobs to run at once, default is the CPU count |
| **`DYBATPHO_PARALLEL_FAILFAST`** | string | When true-like, stop launching and end running jobs once one fails |
| **`DYBATPHO_PARALLEL_TIMEOUT`** | string | Longest a job may run, such as `90`, `5m` or `1h30m`; empty or `0` is no limit |
| **`DYBATPHO_PARALLEL_PROGRESS`** | string | When true-like, report on standard error how many jobs have finished |
| **`DYBATPHO_PARALLEL_STATUS`** | array | Exit code of each job of the last run, in submission order |

### 🚀 Highlights

- [`dybatpho::parallel_map`](#dybatphoparallel_map) — Run one command once per item, several items at a time. The command and each item are passed as separate arguments, so an item containing a space or a quote is handled as one value rather than re-parsed as shell syntax.
- [`dybatpho::parallel_run`](#dybatphoparallel_run) — Run several shell commands at once, each given as one string. Use this when the jobs differ from one another; use `dybatpho::parallel_map` when the same command runs over a list, because that form needs no quoting.
- [`dybatpho::parallel_status`](#dybatphoparallel_status) — Print the exit code of one job of the last run.
- [`dybatpho::parallel_count`](#dybatphoparallel_count) — Print how many jobs the last run had.
- [`dybatpho::parallel_failed`](#dybatphoparallel_failed) — Print how many jobs of the last run failed. A job that fail-fast prevented from starting, or ended while it ran, is not counted: it was stopped because another job failed, not because it did.

<a id="see-also"></a>
## 🔗 See also

- [example/parallel_ops.sh](../example/parallel_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::parallel_map`

- A function defined by the caller works as the command, because each job runs in a subshell of the calling shell
- The per-job exit codes are kept in the calling shell, so a call made inside `$(...)` or a pipeline reports its own output but leaves `dybatpho::parallel_status` unchanged

### `dybatpho::parallel_run`

- Each string is evaluated as a shell command, so quote anything inside it that must survive that second round of parsing
- The per-job exit codes are kept in the calling shell, so a call made inside `$(...)` or a pipeline reports its own output but leaves `dybatpho::parallel_status` unchanged

<a id="reference"></a>
## 📚 Reference

### `dybatpho::parallel_map`

Run one command once per item, several items at a time.
The command and each item are passed as separate arguments, so an item
containing a space or a quote is handled as one value rather than re-parsed
as shell syntax.

**🧪 Examples**

```bash
function _convert { dybatpho::info "converting $1"; convert "$1" "${1%.png}.webp"; }
dybatpho::parallel_map 4 _convert ./images/*.png

```

```bash
# Let the job count follow the machine.
dybatpho::parallel_map 0 _check "${hosts[@]}"

```

```bash
# Stop everything as soon as one host fails.
dybatpho::parallel_map --fail-fast 4 _deploy "${hosts[@]}"

```

```bash
# Give up on a host that takes more than half a minute.
dybatpho::parallel_map --timeout 30s 8 _check "${hosts[@]}"

```

```bash
# Show a bar while a long list converts; the output stays clean.
dybatpho::parallel_map --progress 4 _convert ./images/*.png > converted.log

```

**🎛️ Options**

| Option | Description |
| --- | --- |
| **--fail-fast** | Stop starting jobs and end the running ones once a job fails |
| **--timeout \<duration\>** | End a job that runs longer than this, recording exit `124` |
| **--progress** | Report on standard error how many jobs have finished |
| -- End of options, for a job count that is not one |  |

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Jobs to run at once, or `0` to use the CPU count |
| `$2` | string | Command or function to run for each item |
| `$@` | string | Items, one job each |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PARALLEL_JOBS`** | number | Job count used when `0` is requested |
| **`DYBATPHO_PARALLEL_FAILFAST`** | string | When true-like, stop at the first failure |
| **`DYBATPHO_PARALLEL_TIMEOUT`** | string | Per-job limit used when `--timeout` is not given |
| **`DYBATPHO_PARALLEL_PROGRESS`** | string | When true-like, report progress as `--progress` does |
| **`DYBATPHO_TIMEOUT_KILL_AFTER`** | number | Seconds a timed-out job has to stop before it is killed, default is `5` |
| **`DRY_RUN`** | string | When true-like, report the jobs instead of running them |

**🧩 Variable sets**

- DYBATPHO_PARALLEL_STATUS

**📤 Output on stdout**

- Standard output of every job, replayed in submission order

**📤 Output on stderr**

- Standard error of every job, replayed in submission order

**🚦 Exit codes**

- `0`: Every job succeeded
- `1`: At least one job failed


---

### `dybatpho::parallel_run`

Run several shell commands at once, each given as one string.
Use this when the jobs differ from one another; use `dybatpho::parallel_map`
when the same command runs over a list, because that form needs no quoting.

**🧪 Example**

```bash
dybatpho::parallel_run 3 \
  "npm run build" \
  "cargo build --release" \
  "go build ./..."

```

**🎛️ Options**

| Option | Description |
| --- | --- |
| **--fail-fast** | Stop starting jobs and end the running ones once a job fails |
| **--timeout \<duration\>** | End a job that runs longer than this, recording exit `124` |
| **--progress** | Report on standard error how many jobs have finished |
| -- End of options |  |

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Jobs to run at once, or `0` to use the CPU count |
| `$@` | string | Shell command strings, one job each |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PARALLEL_FAILFAST`** | string | When true-like, stop at the first failure |
| **`DYBATPHO_PARALLEL_TIMEOUT`** | string | Per-job limit used when `--timeout` is not given |
| **`DYBATPHO_PARALLEL_PROGRESS`** | string | When true-like, report progress as `--progress` does |
| **`DYBATPHO_TIMEOUT_KILL_AFTER`** | number | Seconds a timed-out job has to stop before it is killed, default is `5` |
| **`DRY_RUN`** | string | When true-like, report the commands instead of running them |

**🧩 Variable sets**

- DYBATPHO_PARALLEL_STATUS

**📤 Output on stdout**

- Standard output of every job, replayed in submission order

**📤 Output on stderr**

- Standard error of every job, replayed in submission order

**🚦 Exit codes**

- `0`: Every job succeeded
- `1`: At least one job failed


---

### `dybatpho::parallel_status`

Print the exit code of one job of the last run.

**🧪 Example**

```bash
dybatpho::parallel_map 4 _check "${hosts[@]}" || true
for index in $(seq 0 $(($(dybatpho::parallel_count) - 1))); do
  dybatpho::print "${hosts[index]} -> $(dybatpho::parallel_status "${index}")"
done

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Job index, counting from zero in submission order |

**📤 Output on stdout**

- The job's exit code (`124` when `--timeout` ended it), `skipped` when fail-fast stopped it from
  starting, or `terminated` when fail-fast ended it while it was running

**🚦 Exit codes**

- `1`: There is no job with that index


---

### `dybatpho::parallel_count`

Print how many jobs the last run had.

_Function has no arguments._

**📤 Output on stdout**

- Job count


---

### `dybatpho::parallel_failed`

Print how many jobs of the last run failed.
A job that fail-fast prevented from starting, or ended while it ran, is not
counted: it was stopped because another job failed, not because it did.

_Function has no arguments._

**📤 Output on stdout**

- Number of failed jobs
