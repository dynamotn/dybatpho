# queue.sh

A durable job queue backed by the filesystem

> 🧭 Source: [src/queue.sh](../src/queue.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`parallel.sh` runs a bounded worker pool over a job list that has to be
known up front, and nothing of it survives the script dying: the jobs still
waiting are gone with it. This module is the other half — a queue that
lives on disk, that a producer can add to while workers are already
running, and that a crashed run can be resumed from.

A job is claimed rather than consumed. `dybatpho::queue_pop` moves it out
of `pending` and into `claimed`, and it stays there until the worker says
what happened: `dybatpho::queue_complete` removes it,
`dybatpho::queue_requeue` puts it back, and
`dybatpho::queue_dead_letter` files it under `dead` rather than dropping
it. A worker that dies leaves its job in `claimed`, where it can be seen
and requeued, instead of vanishing between the read and the work.

Ordering is strict FIFO. The sequence number in a job's id is handed out
under the queue's lock rather than taken from the clock, so two producers
in the same second still come out in the order they arrived — a
second-resolution timestamp could not tell them apart, and `date` has no
portable sub-second field.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_QUEUE_DIR`** | string | Base directory for bare queue names, default is the XDG state directory |
| **`DYBATPHO_QUEUE_TIMEOUT`** | number | Seconds to wait for the queue lock, default is `10` |
| **`DYBATPHO_QUEUE_DIR`** | string | Where a bare queue name resolves to |
| **`DYBATPHO_QUEUE_TIMEOUT`** | number | Seconds a queue operation waits for the lock, default is `10` |

### 🚀 Highlights

- [`dybatpho::queue_push`](#dybatphoqueue_push) — Add a job to a queue. The payload is written to a temporary file and renamed into `pending`, so a worker never sees a job whose payload is still being written.
- [`dybatpho::queue_pop`](#dybatphoqueue_pop) — Claim the oldest job in a queue. The job moves from `pending` to `claimed` and stays there until the caller completes, requeues, or dead-letters it, so a worker that dies leaves its job where it can be found rather than losing it.
- [`dybatpho::queue_peek`](#dybatphoqueue_peek) — Read the oldest waiting job without claiming it.
- [`dybatpho::queue_len`](#dybatphoqueue_len) — Count the jobs in one of a queue's states.
- [`dybatpho::queue_list`](#dybatphoqueue_list) — List a queue's job ids for one state, oldest first.
- [`dybatpho::queue_complete`](#dybatphoqueue_complete) — Remove a claimed job, marking the work as done.
- [`dybatpho::queue_requeue`](#dybatphoqueue_requeue) — Put a claimed job back at the end of the queue. Each requeue counts, and when a job has been requeued as many times as the budget allows it is dead-lettered instead, so a job that always fails stops circulating without being thrown away.
- [`dybatpho::queue_dead_letter`](#dybatphoqueue_dead_letter) — Move a claimed job to the queue's dead letters. A job that cannot be handled is kept rather than deleted, so an operator can read it, fix the cause, and push it again.
- [`dybatpho::queue_read`](#dybatphoqueue_read) — Read a job's payload from any state, into a named variable.

<a id="see-also"></a>
## 🔗 See also

- [example/queue_ops.sh](../example/queue_ops.sh)

<a id="tips"></a>
## 💡 Tips

- A payload is text, and may be anything including newlines; encode a structured payload with `json.sh` before pushing it and decode it after
- A bare queue name lives under `DYBATPHO_QUEUE_DIR`; a name containing a slash is used as the directory itself

<a id="reference"></a>
## 📚 Reference

### `dybatpho::queue_push`

Add a job to a queue.
The payload is written to a temporary file and renamed into `pending`, so
a worker never sees a job whose payload is still being written.

**🧪 Example**

```bash
id="$(dybatpho::queue_push deploys "restart api")"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Payload text, or `-` to read it from stdin |

**📤 Output on stdout**

- The new job's id

**🚦 Exit codes**

- `0`: The job was added
- `1`: The queue lock could not be taken


---

### `dybatpho::queue_pop`

Claim the oldest job in a queue.
The job moves from `pending` to `claimed` and stays there until the caller
completes, requeues, or dead-letters it, so a worker that dies leaves its
job where it can be found rather than losing it.

**🧪 Example**

```bash
while dybatpho::queue_pop deploys id payload; do
  if handle "${payload}"; then
    dybatpho::queue_complete deploys "${id}"
  else
    dybatpho::queue_requeue deploys "${id}" 3
  fi
done
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Name of the variable receiving the job id |
| `$3` | string | Name of the variable receiving the payload |

**🧩 Variable sets**

- **`Both`** (named): variables

**🚦 Exit codes**

- `0`: A job was claimed
- `1`: The queue is empty, or its lock could not be taken


---

### `dybatpho::queue_peek`

Read the oldest waiting job without claiming it.

**🧪 Example**

```bash
dybatpho::queue_peek deploys
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Optional name of a variable receiving the job id |

**🧩 Variable sets**

- **`The`** (named): variable, when one is given

**📤 Output on stdout**

- The payload of the oldest waiting job

**🚦 Exit codes**

- `0`: A job was read
- `1`: The queue is empty


---

### `dybatpho::queue_len`

Count the jobs in one of a queue's states.

**🧪 Example**

```bash
(($(dybatpho::queue_len deploys) > 0)) && dybatpho::info "Work is waiting"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Optional state: `pending` (default), `claimed`, or `dead` |

**📤 Output on stdout**

- The number of jobs

**🚦 Exit codes**

- `0`: The count was printed
- `1`: The state is not one this module keeps


---

### `dybatpho::queue_list`

List a queue's job ids for one state, oldest first.

**🧪 Example**

```bash
dybatpho::queue_list deploys dead
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Optional state: `pending` (default), `claimed`, or `dead` |

**📤 Output on stdout**

- One job id per line

**🚦 Exit codes**

- `0`: The listing was printed, empty when there is nothing to list
- `1`: The state is not one this module keeps


---

### `dybatpho::queue_complete`

Remove a claimed job, marking the work as done.

**🧪 Example**

```bash
dybatpho::queue_complete deploys "${id}"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Job id |

**🚦 Exit codes**

- `0`: The job was removed
- `1`: No such job is claimed


---

### `dybatpho::queue_requeue`

Put a claimed job back at the end of the queue.
Each requeue counts, and when a job has been requeued as many times as the
budget allows it is dead-lettered instead, so a job that always fails stops
circulating without being thrown away.

**🧪 Example**

```bash
dybatpho::queue_requeue deploys "${id}" 3
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Job id |
| `$3` | number | Optional retry budget; past it the job is dead-lettered instead |

**📤 Output on stdout**

- The job's new id when it is requeued

**🚦 Exit codes**

- `0`: The job was requeued, or dead-lettered because its budget ran out
- `1`: No such job is claimed, or the queue lock could not be taken


---

### `dybatpho::queue_dead_letter`

Move a claimed job to the queue's dead letters.
A job that cannot be handled is kept rather than deleted, so an operator
can read it, fix the cause, and push it again.

**🧪 Example**

```bash
dybatpho::queue_dead_letter deploys "${id}"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Job id |

**🚦 Exit codes**

- `0`: The job was filed under dead letters
- `1`: No such job is claimed


---

### `dybatpho::queue_read`

Read a job's payload from any state, into a named variable.

**🧪 Example**

```bash
dybatpho::queue_read deploys "${id}" payload dead
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Queue name or path |
| `$2` | string | Job id |
| `$3` | string | Name of the variable receiving the payload |
| `$4` | string | Optional state: `pending`, `claimed`, or `dead`, default is to search all three |

**🧩 Variable sets**

- **`The`** (named): variable

**🚦 Exit codes**

- `0`: The job was read
- `1`: No job with that id is in the queue
