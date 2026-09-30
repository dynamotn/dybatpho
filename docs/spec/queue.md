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

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A bare queue name MUST resolve under `DYBATPHO_QUEUE_DIR`, or the XDG state directory when that is unset; a name containing a slash MUST be used as the directory itself.
- **FR-002**: An empty queue name MUST stop the script.
- **FR-003**: A push MUST write the payload to the `pending` directory and MUST return the new job's id.
- **FR-004**: A payload MUST be accepted as an argument or read from stdin, and MUST survive unchanged, line breaks included.
- **FR-005**: Job ids MUST order jobs by arrival, with the sequence taken under the queue's lock rather than from the clock.
- **FR-006**: A claim MUST take the oldest waiting job, and choosing it and moving it MUST happen under one lock.
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
- **FR-018**: A peek MUST read the oldest waiting job without claiming it.
- **FR-019**: A caller-supplied variable name that is not bindable MUST be refused.

### Key Entities *(include if feature involves data)*

- **Job**: One unit of work: a payload file named by its id.
- **Job id**: A zero-padded sequence number and the push time, ordering jobs by arrival.
- **State**: `pending` (waiting), `claimed` (in flight), or `dead` (given up on).
- **Retry count**: A sidecar beside a job, counting how often it has been requeued.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Several workers draining one queue handle every job exactly once.
- **SC-002**: A killed run loses no waiting work, and leaves in-flight work recoverable.
- **SC-003**: A job that always fails leaves the queue after a bounded number of attempts, and is still readable afterwards.
- **SC-004**: A producer can add work while workers are running.

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

## Acceptance Criteria *(mandatory)*

1. The queue needs no daemon and no external command: it is directories, files, and the library's own lock.
2. A job is claimed, not consumed, so every job's fate is stated by the worker rather than assumed.
3. Nothing is deleted silently: a job that cannot be handled is filed under dead letters with its payload.
