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

**Independent Test**: Run a failing job in the middle of a list with fail-fast on, and verify that the jobs after it never ran.

**Acceptance Scenarios**:

1. **Given** fail-fast is on and a job fails, **When** the run continues, **Then** the remaining jobs are never started
2. **Given** a job that never started, **When** its status is read, **Then** it is reported as skipped rather than as a failure
3. **Given** fail-fast is off, **When** a job fails, **Then** every other job still runs

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

- An empty work list.
- A job count that is not a positive integer.
- A status read for an index that has no job.
- A job that starts a child of its own, which must not outlive an interrupted run.
- A caller whose shell already had job control enabled.
- A run captured in a command substitution, which happens in a subshell.

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

### Key Entities *(include if feature involves data)*

- **Job**: One unit of work, with its own captured output and exit code.
- **Pool**: The bound on how many jobs run at once.
- **Status**: The exit code of one job, or the fact that it never ran.

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

## Acceptance Criteria *(mandatory)*

1. Concurrency is bounded by the caller, never by the size of the work list.
2. The output and the exit codes of a concurrent run are as usable as a serial run's.
3. An interrupted run leaves nothing behind still working.
