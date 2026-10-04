# Feature Specification: Bounded Concurrent Execution

**Feature Branch**: `[feature-parallel]`
**Status**: Implemented
**Input**: `src/parallel.sh`, `test/parallel.bats`, `docs/parallel.md`, and `example/parallel_ops.sh`

## Problem Statement *(mandatory)*

A script that has a hundred hosts to check or a hundred files to convert runs them one after another and takes a hundred times as long as it needs to. The hand-written fix — backgrounding every job and calling `wait` — gets three things wrong. It launches all hundred at once and overwhelms the machine. It lets the jobs write over one another, producing output whose lines belong to no particular job. And it keeps only one exit code, so a failure in the middle of the run disappears.

## Business Value *(mandatory)*

- Cut the wall-clock time of work that is already independent.
- Keep the machine within a bound the caller chooses rather than the size of the work list.
- Produce output a person can still read after the run.
- Report what each job did, so a failure is attributable rather than merely present.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a list of work a few at a time (Priority: P1)

As a script author, I want to run one command over a list with a bound on how many run at once so that the work finishes sooner without exhausting the machine.

**Why this priority**: This is the whole point of the module; everything else supports it.

**Independent Test**: Run jobs that record when they start and end, and verify that the number running at once never exceeds the requested bound.

**Acceptance Scenarios**:

1. **Given** a list of items and a bound of one, **When** the pool runs, **Then** the jobs do not overlap
2. **Given** a bound smaller than the list, **When** the pool runs, **Then** a job ends before the job beyond the bound begins
3. **Given** a bound of zero, **When** the pool runs, **Then** the count comes from configuration, and from the machine's processor count when nothing is configured
4. **Given** an item containing spaces or shell syntax, **When** it is passed to its job, **Then** it arrives as one value rather than being parsed as shell

---

### User Story 2 - Read the output afterwards (Priority: P1)

As an operator, I want each job's output kept together so that the result of a concurrent run reads like the result of a serial one.

**Why this priority**: Interleaved output is worse than no output: it looks like a report but cannot be trusted line by line.

**Independent Test**: Run overlapping jobs that each print more than one line, and verify that the lines of each job are contiguous and in submission order.

**Acceptance Scenarios**:

1. **Given** jobs that overlap in time, **When** the run finishes, **Then** each job's lines appear together, in the order the jobs were submitted
2. **Given** a job writing to both streams, **When** the run finishes, **Then** its standard error is replayed on standard error, not folded into standard output

---

### User Story 3 - Find out what each job did (Priority: P1)

As a script author, I want the exit code of every job so that I can report which items failed rather than only that something did.

**Why this priority**: A run over a list is usually followed by a decision about the items that failed, which needs per-item results.

**Independent Test**: Run a mix of succeeding and failing jobs, and verify the recorded code of each and the count of failures.

**Acceptance Scenarios**:

1. **Given** a run with some failures, **When** it finishes, **Then** the run reports failure and each job's own exit code is available
2. **Given** a run where everything succeeded, **When** it finishes, **Then** the run reports success and no failures
3. **Given** a caller that captured the run in a command substitution, **When** they read the statuses, **Then** the previous bookkeeping is unchanged, because the capture ran in a subshell

---

### User Story 4 - Stop early when something fails (Priority: P2)

As a script author, I want the option to stop at the first failure so that a broken build does not keep the remaining jobs running for nothing.

**Why this priority**: Useful, but the default of running everything is what most callers want, since it reports on the whole list.

**Independent Test**: Run a failing job in the middle of a list with fail-fast on, and verify that the jobs after it never ran and the jobs beside it were ended.

**Acceptance Scenarios**:

1. **Given** fail-fast is on and a job fails, **When** the run continues, **Then** the remaining jobs are never started
2. **Given** a job that never started, **When** its status is read, **Then** it is reported as skipped rather than as a failure
3. **Given** fail-fast is off, **When** a job fails, **Then** every other job still runs
4. **Given** fail-fast is on and a job fails while another is still running, **When** the failure is seen, **Then** the running job is ended together with its children, reported as terminated, and not counted as a failure
5. **Given** fail-fast stops a run, **When** the run ends, **Then** standard error names the job that failed, its label, and its exit code
6. **Given** `--fail-fast` before the job count, **When** the run starts, **Then** it behaves as `DYBATPHO_PARALLEL_FAILFAST=true` does, for that call only

---

### User Story 5 - Give up on a job that hangs (Priority: P2)

As a script author, I want a time limit per job so that one host that never answers does not hold the whole run open.

**Why this priority**: A hung job is the most common way a concurrent run fails to finish, and wrapping every job in a timeout by hand loses the job's process group.

**Independent Test**: Run a job that sleeps past a short limit beside a quick one, and verify the slow one is ended with exit `124` while the quick one is unaffected.

**Acceptance Scenarios**:

1. **Given** `--timeout <duration>`, **When** a job runs longer than the limit, **Then** its process group is asked to stop, it is recorded as exit `124`, and standard error names it
2. **Given** a job that ignores the request to stop, **When** `DYBATPHO_TIMEOUT_KILL_AFTER` seconds pass, **Then** it is killed
3. **Given** a limit far longer than the jobs take, **When** they finish, **Then** the run ends as soon as they do
4. **Given** fail-fast and a limit, **When** a job times out, **Then** the timeout is the failure fail-fast stops on

---

### User Story 6 - See how far a long run has got (Priority: P3)

As a script author, I want to see how many jobs have finished while a long run is working so that a quiet terminal does not look like a hang.

**Why this priority**: A convenience: the run's results are the same with or without it.

**Independent Test**: Run a list with `--progress` and verify standard error reports the jobs finishing while standard output carries only the jobs' own output.

**Acceptance Scenarios**:

1. **Given** `--progress` and the `tui` module loaded, **When** jobs finish, **Then** the `tui` progress bar advances, or logs on a percentage grid when standard error is not a terminal
2. **Given** `--progress` without the `tui` module, **When** each job finishes, **Then** one `Jobs: <done>/<total> finished` line is written to standard error
3. **Given** progress in any form, **When** the run ends, **Then** standard output holds exactly what the jobs wrote

---

### Example Workflow

```bash
. dybatpho/init.sh --modules parallel

function check_host {
  ssh "$1" 'systemctl is-active myapp' || return 1
}

dybatpho::parallel_map 8 check_host "${hosts[@]}" || true

for ((i = 0; i < $(dybatpho::parallel_count); i++)); do
  [[ "$(dybatpho::parallel_status "${i}")" == "0" ]] || dybatpho::warn "${hosts[i]} is down"
done
```

## Edge Cases

- A child forked just as the pool is interrupted misses the signal, because until it execs it runs with the handlers of a shell that has an `EXIT` trap.
- A script limits jobs with a duration such as `5m` without having loaded the `date` module.
- An empty work list.
- A job count that is not a positive integer.
- A status read for an index that has no job.
- A job that starts a child of its own, which must not outlive an interrupted run.
- A caller whose shell already had job control enabled.
- A failure that arrives after the last job has started, while the pool is draining.
- An item that starts with `--`, which is an item rather than an option because options end at the job count.
- An unknown option, or `--` used to end the options.
- A job that traps or ignores `SIGTERM` when its time limit is reached.
- A duration that cannot be read, is negative, or is missing after `--timeout`.
- A job that exits with `124` of its own accord, which reads the same as a timeout, as it does with `timeout`.
- A child shell that inherited the exported `dybatpho::tui_progress_*` functions without loading `tui`, which must take the plain report.
- A run captured in a command substitution, which happens in a subshell.
- A script that runs pools in a loop, and has SIGINT or SIGTERM handlers of its own.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST run at most the requested number of jobs at once, and MUST accept zero as a request to take the count from configuration, and then from the processor count.
- **FR-002**: A job count that is not a positive integer MUST stop the caller, and MUST NOT be validated inside a command substitution, where a rejection could not prevent the jobs from running.
- **FR-003**: Items MUST be passed to their job as single values, so that an item containing spaces or shell syntax is not re-parsed.
- **FR-004**: Each job's standard output and standard error MUST be captured while it runs and replayed afterwards, in submission order, each on its own stream.
- **FR-005**: Each job's exit code MUST be recorded separately and be readable afterwards by job index.
- **FR-006**: Exit codes MUST travel through files rather than through `wait`, which reports a status without saying which job it belongs to.
- **FR-007**: A run MUST report failure when any job failed, and success otherwise.
- **FR-008**: With fail-fast enabled, a failure MUST stop further jobs from starting, and an unstarted job MUST be reported as skipped rather than as failed.
- **FR-009**: A job MUST run in a subshell of the caller, so that a function the caller defined can be used as the command without being exported.
- **FR-010**: The pool MUST end its jobs, together with any children they started, when the shell is interrupted or terminated.
- **FR-011**: The pool MUST restore the caller's job-control setting, which it changes in order to give each job its own process group.
- **FR-012**: The module MUST honor `DRY_RUN` by reporting the jobs and running none of them.
- **FR-013**: The pool MUST keep itself full by waiting for the next job to finish, rather than draining and refilling in batches.
- **FR-014**: `dybatpho::parallel_map` and `dybatpho::parallel_run` MUST accept leading options before the job count, MUST treat everything from the job count on as positional, MUST accept `--` to end the options, and MUST stop the caller on an unknown option.
- **FR-015**: `--fail-fast` MUST enable fail-fast for that call regardless of `DYBATPHO_PARALLEL_FAILFAST`.
- **FR-016**: With fail-fast enabled, the first failure MUST end every job still running, together with its process group, including while the pool drains after the last job started; such a job MUST be reported as `terminated` and MUST NOT be counted by `dybatpho::parallel_failed`.
- **FR-017**: When fail-fast stops a run, the module MUST report on standard error the index, label (item or command string), and exit code of the job that failed.
- **FR-018**: `--timeout <duration>` and `--timeout=<duration>` MUST limit how long each job runs, reading the duration as `dybatpho::date_parse_duration` does, with `DYBATPHO_PARALLEL_TIMEOUT` as the default and an empty value or `0` meaning no limit; an unreadable, negative, or missing duration MUST stop the caller.
- **FR-019**: A job over its limit MUST have its process group sent `SIGTERM`, then `SIGKILL` after `DYBATPHO_TIMEOUT_KILL_AFTER` seconds (default `5`) if anything in it is still running, MUST be recorded as exit `124`, and MUST be named on standard error.
- **FR-020**: The watchdog enforcing a limit MUST NOT keep the run open once its job has finished or the run is interrupted, and MUST NOT hold the caller's output streams.
- **FR-021**: `--progress`, or a true-like `DYBATPHO_PARALLEL_PROGRESS`, MUST report finished jobs on standard error only: through the `tui` progress bar when that module is loaded, detected by an internal `tui` helper rather than a public name, and otherwise as one `Jobs: <done>/<total> finished` line per reap; `tui` MUST NOT become a dependency of `parallel`.
- **FR-022**: Loading the module MUST NOT load `date`. A time limit in plain seconds MUST work without it; any other duration MUST stop the caller, naming the `date` module and how to load it, when that module is not loaded, before any job starts or anything is created.
- **FR-023**: A run MUST put back the SIGINT and SIGTERM handlers it found once it ends, so its terminate handler does not outlive it and repeated runs do not accumulate handlers.
- **FR-024**: A refused `--timeout` MUST be reported under the public function that was called, not under the pool that reads it.
- **FR-025**: An interrupt (SIGINT or SIGTERM) MUST stop the pool from starting further jobs, end every job and watchdog it started -- including any started around the signal -- restore the caller's handlers, and then raise the same signal again, so the shell ends or the caller's handler runs as without a pool.
- **FR-026**: An interrupted pool MUST end its jobs before any handler of the caller runs, including one that exits.
- **FR-027**: A job run by `parallel_map` or `parallel_run` MUST see the caller's variables: the pool and its launchers MUST keep their state in prefixed locals.
- **FR-028**: Ending jobs MUST signal each job's process group again until it is empty, and MUST end what remains with `KILL` once `DYBATPHO_TIMEOUT_KILL_AFTER` seconds have passed, so that no process a job started outlives the pool.

### Key Entities *(include if feature involves data)*

- **Job**: One unit of work, with its own captured output and exit code.
- **Pool**: The bound on how many jobs run at once.
- **Status**: The exit code of one job, or the fact that it never ran (`skipped`) or was ended by fail-fast (`terminated`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Independent work finishes in roughly the time of the longest job rather than the sum of all of them.
- **SC-002**: The output of a concurrent run is as readable as that of a serial one.
- **SC-003**: A caller can name exactly which items failed.
- **SC-004**: An interrupted run leaves no job still working.

## Integration Tests *(mandatory)*

- **IT-001**: Run a list with a bound of one and verify the jobs did not overlap.
- **IT-002**: Run a list with a bound above one and verify the jobs did overlap, and that the bound was respected.
- **IT-003**: Run overlapping multi-line jobs and verify each job's lines are contiguous and in submission order.
- **IT-004**: Verify standard error is replayed separately from standard output.
- **IT-005**: Run a mix of outcomes and verify each recorded exit code, the failure count, and the run's own status.
- **IT-006**: Pass items containing spaces, quotes, and command substitution syntax, and verify each arrives intact.
- **IT-007**: Verify fail-fast stops later jobs, reports them as skipped, and does not count them as failures.
- **IT-008**: Verify that without fail-fast every job runs despite a failure.
- **IT-009**: Verify command strings are evaluated and their exit codes recorded.
- **IT-010**: Verify an empty work list succeeds and records no jobs.
- **IT-011**: Verify a job count of zero follows configuration and then the machine, and that an invalid count is rejected.
- **IT-012**: Verify a status read for a missing or malformed index is rejected.
- **IT-013**: Verify `DRY_RUN` runs nothing and has no side effect.
- **IT-014**: Verify the caller's job-control setting is the same after a run as before it.
- **IT-015**: Verify a job can call a function defined by the caller.
- **IT-016**: Verify that capturing a run in a command substitution leaves the recorded statuses untouched.
- **IT-017**: Verify `--fail-fast` stops the pool the same way the variable does.
- **IT-018**: Start a slow job beside a failing one with `--fail-fast`, and verify the slow job and its child are ended, it reads as `terminated`, it is not counted as failed, and standard error names the failing job.
- **IT-019**: Verify `dybatpho::parallel_run` accepts `--fail-fast` and names the failing command.
- **IT-020**: Verify `--` ends the options and an unknown option is refused by both entry points.
- **IT-021**: Verify an item that looks like an option is passed to the job unchanged.
- **IT-022**: Run a slow job beside a quick one under `--timeout 1`, and verify `124`, the quick job's output and status, the warning, and that the slow job's child is gone.
- **IT-023**: Run a job that ignores `SIGTERM` with a one-second grace, and verify it is killed and recorded as `124`.
- **IT-024**: Verify a one-minute limit over quick jobs does not delay the run.
- **IT-025**: Verify `DYBATPHO_PARALLEL_TIMEOUT` applies when no option is given.
- **IT-026**: Verify a timeout triggers fail-fast.
- **IT-027**: Verify an unreadable, negative, or missing duration is refused.
- **IT-028**: Send `SIGTERM` to a pool running under a one-minute limit, and verify its job's child is gone and the pool ends at once rather than waiting out the watchdog.
- **IT-029**: Verify `--progress` leaves standard output as the jobs wrote it and reports `3/3` on standard error.
- **IT-030**: Verify `DYBATPHO_PARALLEL_PROGRESS` turns progress on without the option.
- **IT-031**: Verify a run without progress writes nothing of its own to standard error.
- **IT-032**: In a child shell that loads only `parallel`, verify one plain progress line per finished job.
- **IT-033**: In a child shell that loads only `parallel`, run with a limit in seconds, have a `5m` limit stop the call and name the `date` module without running the job, and run with it once `date` is loaded.
- **IT-034**: In a child shell with a SIGTERM handler of its own, run several pools and verify the SIGINT and SIGTERM handlers are the same after each one and never name the pool's terminate handler.
- **IT-035**: Refuse an unreadable and a negative `--timeout`, and report each under `dybatpho::parallel_map` or `dybatpho::parallel_run`.
- **IT-036**: Have the first of two jobs send SIGTERM to the pool under a one-minute timeout; the pool ends within seconds with status 143, the second job never starts, and the first job's child is gone.
- **IT-037**: TERM a pool under `killed_process_handler` and see the job receive the pool's TERM before the shell exits with 143.
- **IT-038**: Run a function as a parallel job through `parallel_map` and `parallel_run` that reads variables named like the pool's locals, and see the caller's values.
- **IT-039**: Interrupt a pool whose job started a child that ignores TERM, and find the child dead within the grace period.

## Acceptance Criteria *(mandatory)*

1. Concurrency is bounded by the caller, never by the size of the work list.
2. The output and the exit codes of a concurrent run are as usable as a serial run's.
3. An interrupted run leaves nothing behind still working.
