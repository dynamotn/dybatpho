# Feature Specification: Portable Process Locking and Coordination

**Feature Branch**: `[reverse-spec-lock]`
**Status**: Implemented
**Input**: Existing source analysis: `src/lock.sh`, `docs/lock.md`, `test/lock.bats`, and `example/lock_ops.sh`

## Problem Statement *(mandatory)*

Cron jobs, deployment scripts, and maintenance tasks must not run twice at the
same time, but the usual Bash answer is `flock`, which is not shipped by
default on macOS. Hand-rolled alternatives based on a PID file race between the
"does it exist" check and the write, leak the lock when a process dies, and
give the operator no way to see who is holding it.

## Business Value *(mandatory)*

- Prevent concurrent runs of the same script on Linux and macOS with one call.
- Remove the dependency on `flock` and other non-portable tooling.
- Make a blocked run diagnosable: report the pid, host, command, and time of
  the holder instead of failing silently.
- Recover automatically from locks abandoned by a crashed process.
- Guarantee the lock is released when the guarded command fails.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prevent concurrent runs (Priority: P1)

As a script author, I want the second copy of my script to refuse to start
while the first copy is still running.

**Independent Test**: Acquire a lock, attempt to acquire the same lock again,
and verify the second attempt fails immediately.

**Acceptance Scenarios**:

1. **Given** no lock exists, **When** `lock_acquire NAME` runs, **Then** the
   lock is created atomically and the call succeeds
2. **Given** a lock is held by a live process, **When** `lock_acquire NAME`
   runs without a timeout, **Then** it fails immediately without waiting
3. **Given** a lock was acquired, **When** `lock_is_held NAME` runs, **Then**
   it succeeds while the lock is held and fails after it is released

### User Story 2 - Wait for a lock with a timeout (Priority: P1)

As an operator, I want a queued run to wait a bounded amount of time for the
lock instead of failing on the first attempt.

**Independent Test**: Hold a lock, release it from a background process, and
verify a waiting acquire succeeds within its timeout while a still-blocked
acquire fails once the timeout elapses.

**Acceptance Scenarios**:

1. **Given** a lock is held and released before the timeout elapses, **When**
   `lock_acquire NAME TIMEOUT` runs, **Then** it acquires the lock and succeeds
2. **Given** a lock is still held when the timeout elapses, **When**
   `lock_acquire NAME TIMEOUT` runs, **Then** it fails and reports the holder
3. **Given** a wait is in progress, **When** the poll interval elapses, **Then**
   the next attempt is made after `DYBATPHO_LOCK_POLL_INTERVAL` seconds

### User Story 3 - Inspect the current holder (Priority: P2)

As an operator debugging a blocked job, I want to see which process holds the
lock so that I can decide whether to wait or intervene.

**Independent Test**: Acquire a lock and verify the reported metadata matches
the current process, then verify an unheld lock reports nothing.

**Acceptance Scenarios**:

1. **Given** a held lock, **When** `lock_info NAME` runs, **Then** it prints
   `pid=`, `host=`, `acquired_at=`, and `command=` for the holder
2. **Given** the lock is not held, **When** `lock_info NAME` runs, **Then** it
   fails and prints nothing
3. **Given** a blocked acquire, **When** it gives up, **Then** its diagnostic
   includes the same holder information

### User Story 4 - Reclaim stale locks (Priority: P1)

As a script author, I want a lock left behind by a crashed process to be
reclaimed automatically instead of blocking every future run.

**Independent Test**: Create a lock directory recording a pid that is not
running, then verify the next acquire reclaims it and succeeds.

**Acceptance Scenarios**:

1. **Given** a lock records a pid that is no longer running on this host,
   **When** `lock_acquire` runs, **Then** the stale lock is removed, a notice is
   written to stderr, and the lock is acquired
2. **Given** a lock records a different host, **When** liveness is checked,
   **Then** it is conservatively treated as still held rather than reclaimed
3. **Given** a lock records no pid, **When** liveness is checked, **Then** it is
   treated as stale

### User Story 5 - Run a command under a lock (Priority: P1)

As a script author, I want to run one command while holding a lock and have the
lock released afterwards regardless of the command's outcome.

**Independent Test**: Run a succeeding and a failing command through
`with_lock` and verify the exit code is propagated and the lock is released in
both cases.

**Acceptance Scenarios**:

1. **Given** the lock can be acquired, **When** `with_lock NAME TIMEOUT --
   COMMAND` runs, **Then** the command runs while the lock is held and the lock
   is released afterwards
2. **Given** the wrapped command fails, **When** it returns, **Then** the lock
   is still released and the command's exit code is propagated
3. **Given** the lock cannot be acquired within the timeout, **When**
   `with_lock` runs, **Then** it fails without running the command

### Example Workflow

```bash
# Refuse to start a second copy of this script.
dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"
trap 'dybatpho::lock_release "$(basename "$0")"' EXIT

# Queue behind a deploy for up to 30 seconds, then run under the lock.
dybatpho::with_lock "deploy" 30 -- ./deploy.sh --env prod

# Report who is blocking us.
dybatpho::lock_info "deploy"
```

## Edge Cases

- A bare lock name, an explicit relative path, and an explicit absolute path
  must all resolve to a lock directory.
- A name that already ends in `.lock` must not gain a second `.lock` suffix.
- Two processes call `lock_acquire` at the same instant, so creation must be
  atomic rather than check-then-create.
- The lock is held by a live process on the current host.
- The lock is held by a process on a different host, whose liveness cannot be
  checked locally.
- The lock records a pid that no longer exists, or records no pid at all.
- `lock_release` is called for a lock that was never acquired.
- `lock_release` is called for a lock owned by a different, still-live process.
- `lock_info` is called for a lock that is not held.
- `with_lock` is called without the `--` separator or without a command.
- `hostname` is unavailable, so the host name must come from a fallback.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST implement locking without depending on `flock`,
  and MUST work the same way on Linux and macOS.
- **FR-002**: Lock creation MUST be atomic, using `mkdir` on the lock directory
  rather than a check-then-create sequence.
- **FR-003**: `lock_path` MUST resolve a bare name under `DYBATPHO_LOCK_DIR` as
  `dybatpho-<name>`, MUST keep an explicit path containing `/` unchanged, and
  MUST ensure exactly one `.lock` suffix.
- **FR-004**: An acquired lock MUST record the holder's `pid`, `host`,
  `acquired_at` timestamp, and `command` as fields inside the lock directory.
- **FR-005**: `lock_acquire` MUST default to a `0` second timeout, failing on
  the first attempt instead of waiting.
- **FR-006**: With a positive timeout, `lock_acquire` MUST retry until the
  timeout elapses, sleeping `DYBATPHO_LOCK_POLL_INTERVAL` seconds between
  attempts.
- **FR-007**: A failed acquire MUST report the current holder on stderr.
- **FR-008**: `lock_is_alive` MUST treat a lock as held when its recorded pid is
  running on the current host, MUST conservatively treat a lock recorded on a
  different host as held, and MUST treat a missing lock, a missing pid, or a
  dead pid as stale.
- **FR-009**: `lock_acquire` MUST reclaim a stale lock before each attempt and
  MUST report the reclamation on stderr.
- **FR-010**: `lock_is_held` MUST return success only when the named lock exists
  and is held by a live process.
- **FR-011**: `lock_info` MUST print `pid`, `host`, `acquired_at`, and `command`
  for a held lock, and MUST fail without output otherwise.
- **FR-012**: `lock_release` MUST remove a lock owned by the current process,
  MUST succeed when the lock does not exist, and MUST refuse to remove a lock
  owned by a different live process.
- **FR-013**: `with_lock` MUST require a literal `--` separator and at least one
  command argument, and MUST fail through the library's diagnostic path
  otherwise.
- **FR-014**: `with_lock` MUST release the lock after the wrapped command
  returns, whether it succeeded or failed, and MUST propagate the command's
  exit code.
- **FR-015**: `with_lock` MUST fail without running the command when the lock
  cannot be acquired within the timeout.
- **FR-016**: `DYBATPHO_LOCK_DIR` MUST default to `TMPDIR` or `/tmp`, and
  `DYBATPHO_LOCK_POLL_INTERVAL` MUST default to `1` second.
- **FR-017**: `lock_hostname` MUST stamp the lock with the host name the `os`
  module resolves, which uses `hostname`, `uname -n`, the kernel, or
  `HOSTNAME`, in that order.
- **FR-018**: Acquiring a lock MUST be a single atomic operation that
  records the holder at the same moment it takes the lock, so the lock is never
  observable in a state where it exists without an owner. Claiming it and
  recording the owner as two steps let a second process read the gap as "nobody
  holds this", remove the lock and take it.
- **FR-019**: The module MUST still read a lock written in the directory
  form used before the atomic claim, so a lock taken by an older copy of the
  library is not mistaken for a free one.
- **FR-020**: `with_lock` MUST release the lock when the command it is
  running is interrupted, and MUST restore the signal handlers it installed, so
  repeated calls do not accumulate handlers.

### Key Entities *(include if feature involves data)*

- **Lock Directory**: A directory ending in `.lock` whose existence represents
  ownership of the lock.
- **Lock Metadata**: The `pid`, `host`, `acquired_at`, and `command` files
  written inside the lock directory when it is acquired.
- **Lock Name**: A bare word resolved under `DYBATPHO_LOCK_DIR`, or an explicit
  path used as-is.
- **Stale Lock**: A lock directory whose recorded pid is not running on the
  current host.
- **Lock Base Directory**: `DYBATPHO_LOCK_DIR`, the root used to resolve bare
  lock names.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script guarantees single-instance execution with one
  `lock_acquire` call and one trap, on both Linux and macOS.
- **SC-002**: A blocked run always names the process holding the lock.
- **SC-003**: A lock abandoned by a crashed process never blocks later runs.
- **SC-004**: A command run through `with_lock` never leaves the lock behind,
  including when it fails.
- **SC-005**: No lock operation depends on `flock` or any other tool absent
  from a default macOS install.

## Integration Tests *(mandatory)*

- **IT-001**: Resolve bare names, explicit paths, and names already ending in
  `.lock`.
- **IT-002**: Acquire a lock, verify it is held, release it, and verify it is
  no longer held.
- **IT-003**: Verify a second acquire fails immediately and reports the holder.
- **IT-004**: Verify a waiting acquire succeeds after a background release, and
  fails once the timeout elapses while the lock is still held.
- **IT-005**: Verify `lock_info` prints the holder metadata when held and fails
  without output when not held.
- **IT-006**: Verify `lock_release` is a no-op for an unheld lock and refuses to
  remove a lock owned by another live process.
- **IT-007**: Verify a lock recording a dead pid is reclaimed on the next
  acquire, with a notice on stderr.
- **IT-008**: Verify `with_lock` runs the command, releases the lock, and
  propagates both success and failure exit codes.
- **IT-009**: Verify `with_lock` rejects a missing `--` separator.
- **IT-010**: Verify a freshly acquired lock already names its holder,
  and that a second process is refused while it is held.
- **IT-011**: Verify a lock in the older directory form is still read
  and still reported as held.
- **IT-012**: Verify `with_lock` has a release handler installed while
  its command runs and none afterwards.

## Acceptance Criteria *(mandatory)*

1. Lock acquisition is atomic, so two simultaneous callers cannot both win.
2. Every lock is either released by its owner, reclaimed as stale, or reported
   with the identity of the process still holding it.
3. Failures identify the lock path and the blocking process rather than failing
   silently.
