# Feature Specification: Process Lifecycle, Traps, Cleanup, Dry Run, Timeouts, Background Jobs, and PID Files

**Feature Branch**: `[reverse-spec-process]`
**Status**: Implemented
**Input**: Existing source analysis: `src/process.sh`, `docs/process.md`, `test/process.bats`, and `example/process_ops.sh`

## Problem Statement *(mandatory)*

Operational shell scripts need predictable exit behavior, signal handling, composable traps, deferred cleanup, and safe dry-run execution. Without a shared module, these concerns are typically reimplemented poorly and inconsistently.

They also need to bound how long a command may run, to start and supervise several long-running commands at once, and to record which process is serving so a second copy is not started. Until now the library only bounded a curl request, so every script that needed a general time limit reached for the `timeout` binary — which is absent on a stock macOS and cannot run a shell function — and hand-rolled its own process bookkeeping.

## Business Value *(mandatory)*

- Make destructive or long-running scripts safer to run.
- Standardize error and signal handling across dybatpho-based scripts.
- Allow scripts to preview side effects before execution.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Handle errors and signals consistently (Priority: P1)

As a script author, I want one-line registration of common handlers so that errors and interrupts are surfaced consistently without custom trap code.

**Why this priority**: Signal and error handling affect script safety and user trust.

**Independent Test**: Register common handlers, trigger a command failure or signal, and verify structured termination behavior.

**Acceptance Scenarios**:

1. **Given** a script opts into the common handlers, **When** a command fails under the ERR trap, **Then** the error handler reports the failure and exits non-zero
2. **Given** a script receives SIGINT or SIGTERM, **When** the signal handler
   runs, **Then** the script reports the interruption and exits with the
   signal-specific status

---

### User Story 2 - Clean up temporary resources automatically (Priority: P1)

As an operator, I want files and directories removed on shell exit so that temporary workspaces do not leak after the script finishes or aborts.

**Why this priority**: Deferred cleanup is a core safety feature used by the file module and many automation flows.

**Independent Test**: Register temporary paths for cleanup, exit the shell, and verify the paths are removed.

**Acceptance Scenarios**:

1. **Given** a script registers a temporary file for cleanup, **When** the shell exits normally, **Then** the temporary path is removed automatically
2. **Given** multiple cleanup actions already exist on a signal or exit trap, **When** a new cleanup action is added, **Then** existing trap behavior is preserved instead of overwritten

---

### User Story 3 - Bound how long a command may run (Priority: P1)

As a script author, I want any command to be ended once it overruns a time
limit so that an automation run cannot hang forever on a wedged network call,
build, or deploy.

**Why this priority**: An unbounded command is the usual cause of a CI job that
has to be cancelled by hand, and of a cron run that overlaps the next one.

**Independent Test**: Run a command that sleeps past its limit and verify it is
ended and reported as a timeout, while a command that finishes in time keeps
its own exit code.

**Acceptance Scenarios**:

1. **Given** a command that outlives its limit, **When** it is run under the
   time limit, **Then** it is ended and the caller sees exit code 124
2. **Given** a command that finishes in time, **When** it is run under the time
   limit, **Then** the caller sees the command's own exit code and output
3. **Given** the `timeout` binary is missing or unusable, **When** a command is
   run under a time limit, **Then** the behaviour is unchanged
4. **Given** a shell function rather than a program, **When** it is run under a
   time limit, **Then** it runs and is bounded like any other command

---

### User Story 4 - Run and supervise several background jobs (Priority: P2)

As a script author, I want to start long-running commands under a name, wait
for all of them, and learn which one failed, so that a script can run a server
and a worker side by side without losing either job's exit code.

**Why this priority**: `wait` on its own reports only one status, so a script
that starts several jobs cannot say which of them failed.

**Independent Test**: Start one succeeding and one failing job, wait for both,
and verify each job's exit code is reported under its own name.

**Acceptance Scenarios**:

1. **Given** several named background jobs, **When** they are all waited for,
   **Then** each job's exit code is available under its name and the wait fails
   when any job failed
2. **Given** a background job that started processes of its own, **When** the
   jobs are ended, **Then** those processes are ended with it rather than
   orphaned
3. **Given** a name whose job is still running, **When** the same name is
   started again, **Then** the request is refused instead of losing the first
   job

---

### User Story 5 - Record and check a PID file (Priority: P2)

As an operator, I want a script to record its process ID and to check whether a
recorded process is still alive, so that a service is not started twice and a
PID file left behind by a crash does not block a restart.

**Why this priority**: A half-written or stale PID file is what makes a
supervisor either start a second copy or refuse to start at all.

**Independent Test**: Write a PID file, verify it reads as running, replace it
with a process ID that has exited, and verify it reads as not running.

**Acceptance Scenarios**:

1. **Given** a PID file recording a live process, **When** it is checked,
   **Then** it reads as running
2. **Given** a PID file that is missing, empty, malformed, or records a process
   that has exited, **When** it is checked, **Then** it reads as not running
3. **Given** a PID file that records another process, **When** removal is
   requested for this process, **Then** the file is left alone

---

### Example Workflow

```bash
# Install the ERR/INT/TERM handlers once, at the top of the script.
dybatpho::register_common_handlers

dybatpho::create_temp workdir "/" "build"
dybatpho::cleanup_file_on_exit "${workdir}"
dybatpho::trap 'dybatpho::warn "Interrupted, rolling back"; ./rollback.sh' INT TERM

# DRY_RUN=true prints the command instead of running it.
dybatpho::dry_run "rsync -a ${workdir}/ /srv/app/"

[[ -f "${workdir}/manifest" ]] || dybatpho::die "Build produced no manifest" 2

# Nothing may hang the run: 120 seconds, then SIGTERM and SIGKILL.
dybatpho::run_with_timeout 120 ./integration-tests.sh \
  || (($? == 124)) && dybatpho::die "Integration tests did not finish in 120s"

# Two long-running jobs, each reported under its own name.
dybatpho::trap dybatpho::kill_children EXIT INT TERM
dybatpho::background_run api ./serve.sh --port 8080
dybatpho::background_run worker ./worker.sh
dybatpho::wait_all \
  || dybatpho::die "worker exited $(dybatpho::background_status worker)"

# One copy at a time.
dybatpho::pid_file_is_running /var/run/app.pid && dybatpho::die "Already running"
dybatpho::pid_file_write /var/run/app.pid
dybatpho::trap 'dybatpho::pid_file_remove /var/run/app.pid' EXIT
```

## Edge Cases

- A script already has an EXIT or signal trap when dybatpho trap composition is requested.
- `DRY_RUN` is unset, true-like, or false-like.
- A dry-run command is supplied as one shell string (evaluated) or multiple
  arguments (executed directly).
- Cleanup registration runs under normal scripts and Bats test environments.
- An existing trap must be preserved when cleanup or another handler is added.
- The `timeout` binary is absent, or present but rejects `-k`.
- A timed command is a shell function, which no external program can execute.
- A timed command exits with 143 of its own accord, which is indistinguishable
  from being killed by SIGTERM unless the timeout is recorded separately.
- A timed or background command started processes of its own, which must not be
  orphaned when it is ended.
- A timed or background command ignores SIGTERM and has to be sent SIGKILL.
- A background job exits while a process it started, which ignores SIGTERM,
  is still running in its group.
- A time limit of `0` means no limit.
- A background job name is started again after its previous job was reaped, or
  while that job is still running.
- `dybatpho::wait_all` and `dybatpho::kill_children` are called when no job was
  ever started.
- A PID file is missing, unreadable, empty, malformed, padded with whitespace by
  another tool, or records a process that has exited.
- A PID file is removed by a process other than the one it records.
- An existing trap handler contains a quote, which `trap -p` prints escaped.
- A script with EXIT handlers composed through `dybatpho::trap` (temporary-file
  cleanup, terminal restore, privilege release) is ended by SIGINT or SIGTERM.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a fatal exit helper with configurable exit code.
- **FR-002**: The module MUST provide helpers to register ERR and signal handlers, individually and together.
- **FR-003**: The module MUST provide a trap-composition helper that preserves existing trap commands.
- **FR-004**: The module MUST provide deferred cleanup registration for files and directories on shell exit.
- **FR-005**: The module MUST provide a dry-run helper that prints commands instead of executing them when dry-run mode is enabled.
- **FR-006**: Cleanup registration MUST be suitable for temporary resources created during script execution.
- **FR-007**: `DRY_RUN` MUST treat `0`, `true`, `yes`, and `on` as enabled
  values and execute commands otherwise.
- **FR-008**: `dry_run` MUST evaluate a single command string and execute
  multiple arguments directly when dry-run mode is disabled.
- **FR-009**: Signal handlers MUST return 130 for SIGINT and 143 for SIGTERM.
- **FR-010**: Cleanup registration MUST append to existing traps and remove
  registered files or directories on EXIT, HUP, INT, or TERM.
- **FR-011**: The module MUST provide a general time limit for any command,
  reporting exit code 124 when the limit elapses and the command's own exit
  code otherwise.
- **FR-012**: The time limit MUST work without the `timeout` binary, and MUST
  accept a shell function as the command.
- **FR-013**: A timed command MUST be sent SIGTERM first and SIGKILL after
  `DYBATPHO_TIMEOUT_KILL_AFTER` seconds, and the processes it started MUST be
  ended with it.
- **FR-014**: A time limit of `0` MUST run the command without a limit, and a
  limit that is not a non-negative integer MUST stop the script.
- **FR-015**: The module MUST provide named background jobs, recording each
  job's process ID and refusing to start a name whose job is still running.
- **FR-016**: Waiting for the background jobs MUST record each job's exit code
  under its name and MUST fail when any job failed.
- **FR-017**: Ending the background jobs MUST also end the processes those jobs
  started, MUST reap them, and MUST empty the registry so the names can be
  reused. It MUST wait on the job's whole process group, not on the job alone,
  so a process that outlives the job and ignores SIGTERM is still sent SIGKILL.
- **FR-018**: PID file writes MUST be atomic, MUST default to the current
  script's `$$`, and MUST create the directory the file lives in.
- **FR-019**: A PID file check MUST report "not running" for a missing,
  unreadable, empty, or malformed file and for a process that has exited.
- **FR-020**: PID file removal MUST leave a file that records a different
  process alone, and MUST succeed when the file is already gone.
- **FR-021**: The SIGINT and SIGTERM handlers MUST leave the EXIT trap armed,
  so the EXIT handlers composed through `dybatpho::trap` still run when the
  script is interrupted.
- **FR-022**: Trap composition MUST put back an existing handler exactly as it
  was registered, quotes included, and MUST NOT change any variable of the
  caller.
- **FR-023**: `pid_file_write` MUST refuse an empty path or one naming a directory before staging anything, MUST create its staging file without following a file or link already at that name, and MUST remove the staging file when the move fails.
- **FR-024**: A handler installed for the length of a call MUST run alone while the call holds what it cleans up, and the caller's handlers MUST be restored and the signal raised again afterwards, so they run once and after the cleanup.
- **FR-025**: A function run by `run_with_timeout` MUST see the caller's variables: the timeout and its fallback MUST keep their state in prefixed locals.
- **FR-026**: A function run by `run_with_timeout` MUST see the caller's variables: the timeout and its fallback MUST keep their state in prefixed locals.
- **FR-027**: A command started by `background_run` MUST see the caller's variables: the starter MUST keep its state in prefixed locals.
- **FR-028**: The error handler MUST print every frame of the stack and exit with the status of the command that failed.

### Key Entities *(include if feature involves data)*

- **Registered Trap Action**: A command appended to one or more shell trap handlers.
- **Deferred Cleanup Target**: A file or directory scheduled for removal when the owning shell exits.
- **Dry-Run Command**: A command represented as a shell string or argument
  vector and optionally printed instead of run.
- **Timed Command**: A command with a limit in seconds, ended with SIGTERM and
  then SIGKILL once the limit elapses.
- **Background Job**: A named command running in a subshell of the caller, with
  a process ID while it runs and an exit code once it has been reaped.
- **PID File**: A file holding the process ID of the script that owns a
  resource, used to answer whether that process is still running.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can opt into consistent lifecycle handling with one or two helper calls.
- **SC-002**: Temporary resources do not leak after scripts exit under normal conditions.
- **SC-003**: Operators can preview command execution safely when dry-run mode is enabled.
- **SC-004**: Existing trap behavior is retained when dybatpho handlers and
  cleanup actions are registered.
- **SC-005**: No command run through the module can hang a script for longer
  than its stated limit, on any platform, with or without coreutils.
- **SC-006**: A script that starts several background jobs can name which one
  failed and with what code.
- **SC-007**: An interrupted script leaves behind neither running children nor
  a PID file that belongs to another process.

## Integration Tests *(mandatory)*

- **IT-001**: Register common handlers and verify command failures trigger the shared error path.
- **IT-002**: Register cleanup for a file and directory, exit the shell, and verify both are removed.
- **IT-003**: Set `DRY_RUN=true` and verify the dry-run helper prints the command without executing it.
- **IT-004**: Verify false-like dry-run execution, signal-specific statuses,
  and trap composition with pre-existing handlers.
- **IT-005**: Run a command past its limit and verify exit code 124, both with
  the `timeout` binary and with the probe forced off.
- **IT-006**: Run a shell function under a time limit and verify it is bounded,
  and that a command exiting 143 of its own accord is not reported as a
  timeout.
- **IT-007**: Time out a command that started a grandchild and verify the
  grandchild is gone.
- **IT-008**: Start a succeeding and a failing background job, wait for both,
  and verify each exit code and the aggregate failure.
- **IT-009**: End the background jobs and verify the jobs, their children, and
  the registry are all gone.
- **IT-010**: Write, check, and remove a PID file across the live, stale,
  malformed, missing, padded, and foreign-owner cases.
- **IT-011**: End a script that registered the signal handlers and a cleanup
  path with SIGTERM and SIGINT, and verify the exit codes and that the path
  was removed.
- **IT-012**: Compose onto an EXIT handler that contains a quote and verify
  both handlers run as written, and that a caller's `signal` variable is left
  alone.
- **IT-013**: Write a pid file to an empty path, a path ending in `/` and an existing directory from a script in its own directory, refuse all three, and leave that directory as it was.
- **IT-014**: Hold a lock and run a pool under `dybatpho::register_killed_handler`, send TERM, and see each cleanup happen before the shell exits with 143.
- **IT-015**: Run a function under a time limit that reads variables named like the runner's locals, and see the caller's values.
- **IT-016**: Run a function under a time limit that reads variables named like the runner's locals, and see the caller's values.
- **IT-017**: Start a background job that reads variables named like the starter's locals, and see the caller's values.
- **IT-018**: Fail with status 7 three functions deep after `register_err_handler`, and exit 7 with all three frames printed.
- **IT-019**: Start a background job that leaves behind a child ignoring SIGTERM and exits, end the jobs, and see that child killed.

## Acceptance Criteria *(mandatory)*

1. The module provides the lifecycle guardrails required by file, network, and example scripts.
2. Trap composition and cleanup remain safe to reuse across multiple script layers.
