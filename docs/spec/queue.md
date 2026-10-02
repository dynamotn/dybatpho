# Feature Specification: Durable Job Queue

**Feature Branch**: `[spec-queue]`
**Status**: Implemented
**Input**: Existing source analysis: `src/queue.sh`, `docs/queue.md`, `test/queue.bats`, and `example/queue_ops.sh`

## Problem Statement *(mandatory)*

`parallel.sh` runs a bounded worker pool, but the jobs have to be known before the pool starts and none of the run survives the script dying: whatever was still waiting goes with it. Scripts that need work to arrive while workers are already running, or to resume after a crash, build a directory-of-files queue of their own. Those hand-rolled queues share two defects. They have no lock, so two workers read the same oldest file and both run it. And they delete a job as they read it, so a worker that dies between the read and the work takes the job with it.

## Business Value *(mandatory)*

- Work can be produced and consumed at the same time, rather than planned up front.
- A crashed run resumes: nothing waiting is lost and nothing in flight disappears.
- Two workers never do the same job, which no unlocked directory queue can promise.
- A job that cannot be handled is kept for an operator instead of dropped.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Produce and consume at the same time (Priority: P1)

As a script author, I want to add jobs to a queue that workers are already draining, so that a watch loop or a long batch does not have to know its work up front.

**Independent Test**: Push jobs, drain them, and verify each was handled exactly once.

**Acceptance Scenarios**:

1. **Given** a payload, **When** it is pushed, **Then** a job file is written and its id is returned
2. **Given** several pushes, **When** their ids are compared, **Then** they are ordered by arrival
3. **Given** a payload containing line breaks, **When** the job is read back, **Then** the payload is unchanged
4. **Given** an empty queue, **When** a claim is attempted, **Then** it reports that there is nothing to do

---

### User Story 2 - Never run the same job twice (Priority: P1)

As an operator, I want concurrent workers to claim distinct jobs, so that running more workers does not mean running the same work more than once.

**Independent Test**: Drain one queue with several workers at once and verify the count handled equals the count pushed, with no repeats.

**Acceptance Scenarios**:

1. **Given** several workers draining one queue, **When** they finish, **Then** every job was handled exactly once
2. **Given** a claim, **When** it happens, **Then** choosing the job and moving it out of `pending` happen under one lock

---

### User Story 3 - Survive a worker that dies (Priority: P1)

As an operator, I want a claimed job to remain visible until the worker says what happened to it, so that a crash leaves the work recoverable rather than lost.

**Independent Test**: Claim a job, abandon it, and verify it is still in `claimed` and can be requeued.

**Acceptance Scenarios**:

1. **Given** a claimed job, **When** the worker has not finished, **Then** the job is in `claimed` rather than deleted
2. **Given** a claimed job, **When** the work succeeds, **Then** completing it removes the job
3. **Given** a claimed job, **When** it is requeued, **Then** it waits again under a new id, behind the jobs pushed since

---

### User Story 4 - Stop a job that always fails (Priority: P2)

As an operator, I want a job that keeps failing to leave the queue without being thrown away, so that it neither circulates forever nor disappears.

**Independent Test**: Fail one job past its budget and verify it lands in dead letters with its payload intact.

**Acceptance Scenarios**:

1. **Given** a retry budget, **When** a job is requeued more times than it allows, **Then** the job is dead-lettered instead
2. **Given** a requeued job, **When** it is claimed again, **Then** its retry count comes with it
3. **Given** a dead-lettered job, **When** it is read, **Then** its payload is unchanged

---

### User Story 5 - Put urgent work first and hold other work back (Priority: P2)

As a script author, I want to push a job ahead of routine work, or schedule one for later, so that a rollback does not wait behind a backlog and a follow-up runs when it is due rather than when a worker happens to be free.

**Independent Test**: Push jobs of mixed priorities and delays under a frozen clock, drain the queue, and verify the order and that nothing is claimed early.

**Acceptance Scenarios**:

1. **Given** jobs of several priorities, **When** they are claimed, **Then** a higher priority comes first and one priority keeps arrival order
2. **Given** a job pushed with a delay or a timestamp, **When** it is not yet due, **Then** it is counted and listed but neither claimed nor peeked
3. **Given** that job, **When** the clock reaches its due time, **Then** it is claimed like any other
4. **Given** a claimed job with a priority, **When** it is requeued, **Then** it keeps its priority, and a requeue delay holds it back before it can be claimed again
5. **Given** an invalid priority, duration, timestamp, both a delay and a timestamp, or an unknown option, **When** a push is attempted, **Then** the script is stopped with the reason

---

### User Story 6 - Run a worker without writing the loop (Priority: P2)

As a script author, I want to hand a queue and a handler to one call, so that claiming, completing, retrying with backoff, dead-lettering and waiting for new work are not rewritten in every worker.

**Independent Test**: Push jobs, run the worker with a handler that succeeds, fails or exits, and verify every job ends completed, requeued with the expected due time, or dead-lettered.

**Acceptance Scenarios**:

1. **Given** jobs and a handler that succeeds, **When** the worker runs, **Then** each job is handled in claim order with its payload as the last argument and its id in `DYBATPHO_QUEUE_JOB_ID`, and completed
2. **Given** a handler that fails, **When** the worker runs, **Then** the job is requeued until the retry budget is spent and then dead-lettered with a warning
3. **Given** a base backoff, **When** a job keeps failing, **Then** each retry is held back twice as long as the one before, never longer than the cap
4. **Given** a handler that calls `exit`, **When** the worker runs, **Then** only that job fails and the worker carries on
5. **Given** no `--poll`, **When** nothing is due, **Then** the worker returns; **Given** `--poll`, **Then** it waits and looks again until `--idle` runs out
6. **Given** `--max-jobs`, **When** that many jobs have been handled, **Then** the worker returns
7. **Given** an invalid option or a handler that does not exist, **When** the worker starts, **Then** the script is stopped with the reason

### Example Workflow

```bash
. dybatpho/init.sh --modules queue

# A producer, anywhere.
dybatpho::queue_push deploys "restart api"

# A worker, in another process, for as long as there is work.
while dybatpho::queue_pop deploys id payload; do
  if handle "${payload}"; then
    dybatpho::queue_complete deploys "${id}"
  else
    dybatpho::queue_requeue deploys "${id}" 3
  fi
done

# What could not be handled is still there to look at.
dybatpho::queue_list deploys dead

# Urgent work jumps the backlog; follow-ups wait until they are due.
dybatpho::queue_push --priority 10 deploys "rollback api"
dybatpho::queue_push --delay 15m deploys "warm caches"
dybatpho::queue_requeue --delay 30s deploys "${id}" 3

# Or let the module run the loop, retries and backoff included.
dybatpho::queue_work --retries 5 --backoff 10s --poll 5s --idle 10m deploys handle
```

## Edge Cases

- The queue is empty, or its directory does not exist yet.
- A payload is multi-line, or arrives on stdin.
- A worker dies with a job claimed.
- A job is requeued repeatedly, with and without a budget.
- A job id names a path outside the queue.
- A state other than `pending`, `claimed` or `dead` is asked for.
- Two producers push within the same second.
- The queue name is bare, is a path, or is empty.
- Every waiting job has a lower priority than one pushed later, or every waiting job is not yet due.
- A priority is negative, has a leading zero, or is not a whole number; a delay is negative or not a duration; `--delay` and `--at` are both given.
- A priority or due sidecar is missing, as on a job written by an older copy of the module, or damaged.
- A queue name begins with `-`, and is separated from the options by `--`.
- A worker's handler is a function, a program, or missing; it succeeds, fails, or calls `exit`.
- A backoff that doubles past the cap, or a base backoff larger than the cap.
- A worker polls a queue that stays empty, or that a producer fills after the worker started.
- The clock is frozen or jumps while a worker waits.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A bare queue name MUST resolve under `DYBATPHO_QUEUE_DIR`, or the XDG state directory when that is unset; a name containing a slash MUST be used as the directory itself.
- **FR-002**: An empty queue name MUST stop the script.
- **FR-003**: A push MUST write the payload to the `pending` directory and MUST return the new job's id.
- **FR-004**: A payload MUST be accepted as an argument or read from stdin, and MUST survive unchanged, line breaks included.
- **FR-005**: Job ids MUST order jobs by arrival, with the sequence taken under the queue's lock rather than from the clock.
- **FR-006**: A claim MUST take the oldest job of the highest priority among the jobs that are due, and choosing it and moving it MUST happen under one lock.
- **FR-007**: A claim MUST move the job to `claimed` rather than deleting it, so an unfinished job stays visible.
- **FR-008**: A claim on an empty queue MUST report that, without failing the script.
- **FR-009**: Completing a job MUST remove it and its retry count.
- **FR-010**: Requeuing MUST return the job to `pending` under a new id, so a failing job does not jump ahead of jobs pushed since.
- **FR-011**: A job's retry count MUST travel with it between `pending` and `claimed`.
- **FR-012**: Requeuing past a given budget MUST dead-letter the job instead.
- **FR-013**: A dead-lettered job MUST be kept with its payload, not deleted.
- **FR-014**: Completing, requeuing or dead-lettering a job that is not claimed MUST stop the script.
- **FR-015**: A job id that is not of the module's own form MUST be refused, so an id cannot name a file outside the queue.
- **FR-016**: Reading, counting and listing MUST accept `pending`, `claimed` and `dead`, and MUST reject any other state.
- **FR-017**: Counting and listing an absent queue MUST report nothing rather than failing.
- **FR-018**: A peek MUST read the job a claim would take next, without claiming it.
- **FR-019**: A caller-supplied variable name that is not bindable MUST be refused.
- **FR-020**: A push MUST accept `--priority <n>`, a whole number defaulting to `0`, and a higher priority MUST be claimed before a lower one.
- **FR-021**: A push MUST accept `--delay <duration>` or `--at <epoch>`, and a job MUST NOT be claimed or peeked before that moment while still being counted and listed as pending.
- **FR-022**: An invalid priority, duration or timestamp, a negative delay, both `--delay` and `--at`, a missing option value, or an unknown option MUST stop the script.
- **FR-023**: A job's priority MUST travel with it through a claim, a requeue and a dead letter, and completing the job MUST remove it.
- **FR-024**: A requeue MUST accept `--delay` and `--at` to hold the job back before it can be claimed again, and MUST refuse `--priority`.
- **FR-025**: A missing or damaged priority or due sidecar MUST read as priority `0` and due now.
- **FR-026**: A worker MUST claim each due job in claim order and call the handler with the given arguments followed by the payload, with the job id in `DYBATPHO_QUEUE_JOB_ID`.
- **FR-027**: A handler that succeeds MUST have its job completed; one that fails MUST have its job requeued with the retry budget given by `--retries` (default `3`), and a job past the budget MUST be dead-lettered with a warning.
- **FR-028**: With `--backoff`, a retry MUST be held back by the base delay doubled for each earlier attempt, capped at `--max-backoff` (default one hour).
- **FR-029**: The handler MUST run in a subshell, so one that exits fails only its own job.
- **FR-030**: Without `--poll` a worker MUST return once no job is due; with it, the worker MUST wait that long and look again, and with `--idle` MUST return after that long without a job, counted in polls rather than read from the clock.
- **FR-031**: A worker MUST return after `--max-jobs` jobs when that is not `0`.
- **FR-032**: An invalid or unknown worker option, a zero poll interval, or a handler that is not a command MUST stop the script.

### Key Entities *(include if feature involves data)*

- **Job**: One unit of work: a payload file named by its id.
- **Job id**: A zero-padded sequence number and the push time, ordering jobs by arrival.
- **State**: `pending` (waiting), `claimed` (in flight), or `dead` (given up on).
- **Retry count**: A sidecar beside a job, counting how often it has been requeued.
- **Priority**: A sidecar beside a job holding its priority, written only when it is not `0`.
- **Due time**: A sidecar beside a job holding the Unix time before which it cannot be claimed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Several workers draining one queue handle every job exactly once.
- **SC-002**: A killed run loses no waiting work, and leaves in-flight work recoverable.
- **SC-003**: A job that always fails leaves the queue after a bounded number of attempts, and is still readable afterwards.
- **SC-004**: A producer can add work while workers are running.
- **SC-005**: An urgent job is claimed before every routine job already waiting, and a scheduled job is never claimed early.
- **SC-006**: A complete worker, retries and backoff included, is one call.

## Integration Tests *(mandatory)*

- **IT-001**: Push a job and verify the file and the returned id.
- **IT-002**: Verify ids are handed out in arrival order.
- **IT-003**: Push a multi-line payload from stdin and read it back unchanged.
- **IT-004**: Claim the oldest job, then the next.
- **IT-005**: Verify a claim moves the job to `claimed` rather than deleting it.
- **IT-006**: Report an empty queue on a claim.
- **IT-007**: Refuse a variable name that belongs to the library.
- **IT-008**: Drain one queue with four concurrent workers and verify no job was handled twice or lost.
- **IT-009**: Peek without claiming, report the id read, and report an empty queue.
- **IT-010**: Count each state, and an absent queue.
- **IT-011**: Reject an unknown state for counting and listing.
- **IT-012**: List ids oldest first, and nothing for an absent queue.
- **IT-013**: Complete a claimed job, and report one that is not claimed.
- **IT-014**: Requeue a job behind the jobs pushed since.
- **IT-015**: Dead-letter a job once its retry budget runs out.
- **IT-016**: Carry a retry count through a claim.
- **IT-017**: Reject a retry budget that is not a number.
- **IT-018**: Dead-letter a job and read its payload back.
- **IT-019**: Refuse a job id that would escape the queue directory.
- **IT-020**: Resolve a bare queue name under `DYBATPHO_QUEUE_DIR`, and refuse an empty name.
- **IT-021**: Drain mixed priorities and verify higher first, arrival order within one priority.
- **IT-022**: Peek the job a claim would take next.
- **IT-023**: Hold a `--delay` job back under a frozen clock, then claim it once the clock advances.
- **IT-024**: Hold an `--at` job back until its timestamp.
- **IT-025**: Refuse each invalid scheduling option.
- **IT-026**: Accept `--` before the queue name.
- **IT-027**: Requeue with `--delay`, keeping the priority, and refuse `--priority` on a requeue.
- **IT-028**: Remove sidecars on completion and keep them on a dead letter.
- **IT-029**: Read damaged sidecars as the defaults.
- **IT-030**: Drain a queue with a function handler, in claim order, with arguments, payload and job id.
- **IT-031**: Return at once from an empty queue.
- **IT-032**: Retry a failing job and dead-letter it past the budget with a warning.
- **IT-033**: Fail only the job whose handler exits.
- **IT-034**: Back off exponentially under a frozen clock, up to the cap, and leave a job that is not due.
- **IT-035**: Stop after `--max-jobs`.
- **IT-036**: Wait with `--poll` for a job pushed later, and return once `--idle` runs out.
- **IT-037**: Run a program handler with arguments.
- **IT-038**: Refuse each invalid worker option and a missing handler.
- **IT-039**: Accept `--` before the queue name.

## Acceptance Criteria *(mandatory)*

1. The queue needs no daemon and no external command: it is directories, files, and the library's own lock.
2. A job is claimed, not consumed, so every job's fate is stated by the worker rather than assumed.
3. Nothing is deleted silently: a job that cannot be handled is filed under dead letters with its payload.
4. Priority and delay change only which due job is claimed next; a queue that never uses them behaves exactly as strict FIFO.
