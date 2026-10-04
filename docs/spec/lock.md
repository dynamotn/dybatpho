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

---

### User Story 6 - Let a few runs in at once (Priority: P2)

As a script author, I want at most N copies of a section to run at the same
time, so that parallel downloads or builds share a machine without overloading
it, and a crashed copy never takes a slot with it.

**Independent Test**: Start more workers than slots through `with_semaphore`
and verify the number inside never exceeds the slot count and every worker
eventually runs.

**Acceptance Scenarios**:

1. **Given** a semaphore with N slots, **When** N callers acquire it, **Then**
   each gets a distinct slot number, and the next caller is refused with every
   holder named
2. **Given** every slot is held, **When** a caller waits with a timeout and a
   slot frees up, **Then** it takes that slot
3. **Given** a slot recorded by a dead process, **When** a caller acquires,
   **Then** the slot is reclaimed with a notice
4. **Given** a slot number, **When** it is released, **Then** that slot frees,
   unless another live process holds it; **Given** no slot number, **Then**
   every slot the current process holds frees and no other
5. **Given** `with_semaphore NAME SLOTS TIMEOUT -- COMMAND`, **When** it runs,
   **Then** the command runs holding a slot, the slot is given back afterwards,
   and the command's exit code is propagated

### Example Workflow

```bash
# Refuse to start a second copy of this script.
dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"
trap 'dybatpho::lock_release "$(basename "$0")"' EXIT

# Queue behind a deploy for up to 30 seconds, then run under the lock.
dybatpho::with_lock "deploy" 30 -- ./deploy.sh --env prod

# Report who is blocking us.
dybatpho::lock_info "deploy"

# At most four downloads at once, across every copy of the script.
dybatpho::with_semaphore downloads 4 60 -- curl -fsSLO "${url}"
dybatpho::lock_semaphore_holders downloads 4
```

## Edge Cases

- A wait runs while `dybatpho::mock_time` has frozen the `date` clock.
- A bare lock name, an explicit relative path, and an explicit absolute path
  must all resolve to a lock directory.
- A name that already ends in `.lock` must not gain a second `.lock` suffix.
- Two processes call `lock_acquire` at the same instant, so creation must be
  atomic rather than check-then-create.
- The lock is held by a live process on the current host.
- The lock is held by a process on a different host, whose liveness cannot be
  checked locally.
- The lock records a pid that no longer exists, or records no pid at all.
- The holder releases the lock while another process is judging it, and a
  third process claims it before the judgement is acted on.
- `lock_release` is called for a lock that was never acquired.
- `lock_release` is called for a lock owned by a different, still-live process.
- `lock_info` is called for a lock that is not held.
- `with_lock` is called without the `--` separator or without a command.
- `hostname` is unavailable, so the host name must come from a fallback.
- More callers than semaphore slots arrive at the same instant.
- A semaphore slot is held by a dead process, or by another live process when
  it is named for release.
- A slot count of `0`, a slot number outside the semaphore, or a timeout that
  is not a number.
- The caller's variable for the slot number is called `slot`.
- The variable a caller names for the slot number matches a name the semaphore uses internally, such as `timeout`.
- `lock_acquire` is given a timeout that is not a number of seconds.

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
- **FR-021**: `lock_semaphore_acquire` MUST let at most the given number of
  slots be held at once, each slot being a lock claimed atomically and
  reclaimed when stale, and MUST report the slot taken through an optional
  variable.
- **FR-022**: `lock_semaphore_acquire` MUST wait up to its timeout for a free
  slot, and on failure MUST report every holder on stderr.
- **FR-023**: `lock_semaphore_release` MUST release the named slot under the
  same ownership rule as `lock_release`, and without a slot MUST release every
  slot held by the current process and no other.
- **FR-024**: `lock_semaphore_holders` MUST print `slot=<n>` followed by the
  holder metadata for each held slot, and MUST fail when no slot is held.
- **FR-025**: `with_semaphore` MUST follow the `with_lock` contract — the `--`
  separator, release after success, failure and interruption, and the
  command's exit code — for one slot of a semaphore.
- **FR-026**: A slot count outside `1`..`9999`, a slot number outside the
  semaphore, or a non-numeric timeout MUST stop the script.
- **FR-027**: Reclaiming MUST judge the holder it read rather than whatever
  holds the name when the check runs, MUST leave the lock alone when it was
  released before its holder could be read, and MUST NOT move aside a lock
  whose holder changed after it was judged stale.
- **FR-028**: `lock_semaphore_acquire` MUST fill the caller's named variable whatever the name is, short of the reserved `__dybatpho` prefix.
- **FR-029**: `lock_acquire` MUST stop with a message naming the value when its timeout is not a whole number of seconds, before it touches the lock.
- **FR-030**: `lock_acquire` and `lock_semaphore_acquire` MUST share one wait loop that times the wait with Bash's own clock, so a poll starts no `date` process and a frozen `date` clock does not hold a wait open, and MUST ask for the host name at most once per call.
- **FR-031**: A bare lock name MUST resolve under the default temporary directory when `DYBATPHO_LOCK_DIR` is empty, never at the root of the filesystem.

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
- **Semaphore Slot**: One of N locks named `<name>.slot<n>.lock` beside the
  semaphore's lock path; holding any one of them is holding the semaphore.

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
- **SC-006**: However many copies start, no more than the slot count are ever
  inside a semaphore at once.

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
- **IT-013**: Hand out each semaphore slot once, then refuse and name every
  holder.
- **IT-014**: Set a caller variable called `slot`.
- **IT-015**: Wait for a slot freed in the background.
- **IT-016**: Reclaim a slot recorded by a dead process.
- **IT-017**: Run six concurrent workers through a two-slot semaphore and
  verify no more than two were ever inside.
- **IT-018**: Release only the caller's own slots without a slot number, and
  refuse a named slot held by another live process.
- **IT-019**: Report nothing for a free semaphore.
- **IT-020**: Refuse a bad slot count, slot number, or timeout.
- **IT-021**: Run a command through `with_semaphore`, propagate its exit code,
  and give the slot back.
- **IT-022**: Fail `with_semaphore` when no slot frees up, and reject a missing
  `--` or command.
- **IT-023**: Leave alone, without a reclaim notice, a lock released during the
  check and claimed by the next process.
- **IT-024**: Acquire slots into variables called `timeout`, `slot_path` and `target`, and find each one filled.
- **IT-025**: Call `lock_acquire` with the timeout `soon` and find a clear refusal and no lock taken.
- **IT-026**: Wait for a held lock while the `date` clock is frozen and find the wait ends on time; wait for a held lock and a full semaphore and find the host name asked for once each.
- **IT-027**: Resolve a bare lock name with `DYBATPHO_LOCK_DIR` emptied and get a path under `TMPDIR`.

## Acceptance Criteria *(mandatory)*

1. Lock acquisition is atomic, so two simultaneous callers cannot both win.
2. Every lock is either released by its owner, reclaimed as stale, or reported
   with the identity of the process still holding it.
3. Failures identify the lock path and the blocking process rather than failing
   silently.
4. A semaphore is built from the same atomic, self-describing locks, so it
   inherits their stale reclaim and holder reporting rather than adding its own.
