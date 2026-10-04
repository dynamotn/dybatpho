# Feature Specification: Scheduling and Trigger Control

**Feature Branch**: `[spec-schedule]`
**Status**: Implemented
**Input**: Existing source analysis: `src/schedule.sh`, `docs/schedule.md`, `test/schedule.bats`, and `example/schedule_ops.sh`

## Problem Statement *(mandatory)*

`helpers.sh` retries a call that failed, which answers "try again". Nothing answered "should this run at all, and when next". Three shapes keep being rewritten as a hand-rolled `sleep` loop: run every N seconds, collapse a burst of triggers into one run, and run at most once a day. The third is the one a loop cannot do at all, because it has to hold across separate invocations of the script, and a variable resets with the process. Scripts run from an existing scheduler have a fourth problem: deciding whether they are due, which means either installing a crontab entry or writing a cron parser inline.

## Business Value *(mandatory)*

- A cadence that does not drift, and does not pile up catch-up runs after a slow one.
- A burst of filesystem events produces one run, after the burst settles rather than at its start.
- "At most once a day" that survives the process, so a script invoked repeatedly still warns once.
- A cron expression read the way cron reads it, including the day-field rule a hand-written check gets wrong.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run something on a cadence (Priority: P1)

As a script author, I want a command run every N seconds until I stop it, so that a supervised loop needs no `sleep` loop of my own.

**Independent Test**: Run a bounded number of ticks and verify the count, then verify the signal handlers are as they were.

**Acceptance Scenarios**:

1. **Given** an interval, **When** the loop runs, **Then** the first run is immediate and the rest follow on the interval
2. **Given** a run that fails, **When** the loop continues, **Then** the next tick still happens
3. **Given** a run that overruns its slot, **When** the next tick is due, **Then** the missed ticks are dropped rather than queued
4. **Given** handlers already installed for `INT`, **When** the loop finishes, **Then** those handlers are back in place

---

### User Story 2 - Act once a burst has settled (Priority: P1)

As a script author watching for changes, I want rapid triggers collapsed into one run after the quiet window, so that an editor's write-then-rename does not start a build against a half-written file.

**Independent Test**: Fire three triggers within the window and verify exactly one run, by the last trigger.

**Acceptance Scenarios**:

1. **Given** several triggers within the window, **When** they settle, **Then** the command runs once
2. **Given** a trigger that a later one replaced, **When** it finishes waiting, **Then** it does nothing and says so through its exit code
3. **Given** a single trigger, **When** the window passes, **Then** the command runs

---

### User Story 3 - Limit something to once a period (Priority: P1)

As a script author, I want a command run at most once per hour, day, or month, across separate invocations, so that a repeated run does not repeat a warning.

**Independent Test**: Run the same command twice from two separate shells and verify it acted once.

**Acceptance Scenarios**:

1. **Given** a command already run this period, **When** it is asked for again, **Then** nothing happens and the call says so
2. **Given** two separate invocations of a script, **When** both ask, **Then** only the first acts
3. **Given** a number of seconds rather than a named period, **When** that many seconds have passed, **Then** the command runs again
4. **Given** a reset, **When** the command is asked for again, **Then** it runs

---

### User Story 4 - Decide whether a cron expression is due (Priority: P2)

As a script author run by an external scheduler, I want to test a cron expression against a time, so that one entry can drive several jobs with different cadences.

**Independent Test**: Test a set of expressions against a known timestamp and verify each verdict.

**Acceptance Scenarios**:

1. **Given** an expression with steps, ranges, or lists, **When** it is tested, **Then** the verdict follows cron's reading of it
2. **Given** both a day of month and a day of week restricted, **When** either matches, **Then** the expression matches
3. **Given** only one day field restricted, **When** it does not match, **Then** the expression does not match
4. **Given** a malformed expression, **When** it is tested, **Then** the call reports the problem rather than guessing

### Example Workflow

```bash
. dybatpho/init.sh --modules schedule

# Warn once a day however often the script runs.
dybatpho::schedule_once_per day token-expiry -- dybatpho::warn "The token expires soon"

# One rebuild per burst of events, after the burst settles.
dybatpho::schedule_debounce 2 rebuild -- make

# One crontab entry, several cadences.
dybatpho::schedule_cron_due "*/15 * * * *" && collect_metrics
dybatpho::schedule_cron_due "0 3 * * 0" && rotate_logs

# A supervised loop.
dybatpho::schedule_every 60 -- check_health
```

## Edge Cases

- A scheduled run fails, or takes longer than its interval.
- The caller already has `INT`/`TERM`/`HUP` handlers.
- Two triggers for the same key arrive at the same moment.
- The marker directory does not exist yet.
- A key would name a file outside the marker directory.
- A cron field is zero-padded, has a zero step, or is not a number.
- A cron expression names Sunday as `7` rather than `0`.
- A script debounces without having loaded the `lock` module.
- Several callers start `schedule_once_per` for the same key at the same moment, or one dies while holding the short claim around the marker.
- Several callers find the same stale claim at once.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The interval loop MUST run the command immediately and then on the interval, measuring from when each run was due so the cadence does not drift.
- **FR-002**: A run that overruns its slot MUST cause the missed ticks to be skipped, not queued.
- **FR-003**: A failing run MUST NOT end the loop.
- **FR-004**: `--times` MUST bound the number of runs; without it the loop runs until interrupted.
- **FR-005**: `INT`, `TERM` and `HUP` MUST end the loop after the run in progress, and the handlers in place beforehand MUST be restored.
- **FR-006**: The debounce MUST run the command only when no later trigger for the key arrived during the window, and MUST report a replaced trigger through a distinct exit code.
- **FR-007**: Registering a trigger MUST be atomic between concurrent callers, so two triggers cannot take the same place in the order.
- **FR-008**: The period limit MUST hold across separate invocations, which requires the marker to be on disk.
- **FR-009**: A named period MUST be a calendar bucket; a number MUST be seconds since the last run.
- **FR-010**: The marker MUST be written before the command runs, so a failing command does not run again next invocation.
- **FR-011**: A reset MUST clear a key's markers and MUST succeed when there are none.
- **FR-012**: A key that is not a plain file name MUST be refused, so it cannot name a file outside the marker directory.
- **FR-013**: The cron predicate MUST support `*`, a number, a range, a comma-separated list, and a `/n` step on any of them.
- **FR-014**: Cron field values MUST be read as decimal, so a zero-padded hour is not treated as octal.
- **FR-015**: Sunday MUST match whether the expression writes it as `0` or `7`.
- **FR-016**: When both day fields are restricted, the expression MUST match if either matches; when only one is, it MUST match on its own.
- **FR-017**: A malformed expression MUST be reported with its own exit code, distinct from "not due".
- **FR-018**: An invalid interval, window, period, or run count MUST stop the script.
- **FR-019**: Loading the module MUST NOT load `lock`; the debounce MUST stop the script, naming the `lock` module and how to load it, when that module is not loaded, before it registers a trigger.
- **FR-020**: `schedule_once_per` MUST read and write its marker as one step under a claim, so only one of several simultaneous callers runs the command; MUST write the marker atomically; and MUST clear a claim older than a few seconds as left by a caller that died.
- **FR-021**: The default marker directory MUST be resolved in the caller's shell, so that with neither XDG_STATE_HOME nor HOME set the function that was called stops instead of placing markers under `/`.
- **FR-022**: `schedule_once_per` MUST give up with exit code 1, running nothing and leaving the marker alone, when a fresh claim is held for the whole wait, and MUST report the claim it waited for.
- **FR-023**: `schedule_once_per` MUST give up with exit code 1, running nothing and leaving the marker alone, when a fresh claim is held for the whole wait, and MUST report the claim it waited for.
- **FR-024**: Removing a stale claim MUST be done by one waiter at a time, which MUST check the claim is still stale before removing it, so a fresh claim taken in its place is never removed.

### Key Entities *(include if feature involves data)*

- **Marker**: A file recording when, or in which bucket, a key last ran.
- **Trigger ticket**: A counter per debounce key, deciding which trigger is last.
- **Period**: `hour`, `day`, `month`, or a number of seconds.
- **Cron expression**: Five fields — minute, hour, day of month, month, day of week.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script keeps a cadence without writing a `sleep` loop, and without drifting.
- **SC-002**: A burst of events produces exactly one run.
- **SC-003**: A warning limited to once a day stays once a day however often the script is invoked.
- **SC-004**: A cron expression is read the way cron reads it, day-field rule included.

## Integration Tests *(mandatory)*

- **IT-001**: Run a bounded number of ticks and count them.
- **IT-002**: Reject an invalid interval, run count, or missing command.
- **IT-003**: Keep looping when a run fails.
- **IT-004**: Restore the caller's `INT` handler afterwards.
- **IT-005**: Run once and skip the rest of the period.
- **IT-006**: Hold the period limit across two separate shells.
- **IT-007**: Measure from the last run when the period is a number of seconds.
- **IT-008**: Accept each named calendar period, and reject an unknown one.
- **IT-009**: Reset a key and run again; reset a key that recorded nothing.
- **IT-010**: Refuse a key that would escape the marker directory.
- **IT-011**: Run a lone debounce trigger.
- **IT-012**: Collapse a burst into one run, by the last trigger.
- **IT-013**: Report a replaced trigger through its exit code.
- **IT-014**: Reject a window that is not a positive number.
- **IT-015**: Match plain cron expressions, and reject non-matching ones.
- **IT-016**: Match steps, ranges, lists, and a stepped range.
- **IT-017**: Match a day of week, with `7` and `0` both Sunday.
- **IT-018**: Match either day field when both are restricted, and only the one given when a single field is.
- **IT-019**: Read a zero-padded hour as decimal.
- **IT-020**: Report a malformed expression, and reject an invalid field.
- **IT-021**: Default the cron predicate to the current time.
- **IT-022**: In a script that loaded `schedule` alone, run a once-per-day command, have the debounce stop and name the `lock` module, and debounce once `lock` is loaded.
- **IT-023**: Start a dozen callers at once for each of several keys, with a named period and with seconds, and find exactly one run per key; plant a stale claim and find the next call runs and removes it.
- **IT-024**: Reset a key with neither XDG_STATE_HOME nor HOME set under `if !`, and stop under the name of `schedule_reset` without touching `/schedule`.
- **IT-025**: Hold a claim that stays fresh for the whole wait and find the call returns 1, names the claim, runs nothing, and writes no marker.
- **IT-026**: Hold a claim that stays fresh for the whole wait and find the call returns 1, names the claim, runs nothing, and writes no marker.
- **IT-027**: Plant a stale claim, start a dozen callers at once, and find exactly one run per round over several rounds, with no claim or reclaim left behind.

## Acceptance Criteria *(mandatory)*

1. Intervals are whole seconds, because fractional `sleep` is not portable to every shell the suite runs on.
2. The module decides and runs; it never installs anything into the system's own scheduler.
3. Computing the next fire time for a cron expression is deliberately out of scope: it needs a full calendar walk, and a half-right answer about when something will next run is worse than no answer. The predicate covers the question a script actually asks.
