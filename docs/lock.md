# lock.sh

Utilities for process locking and coordination

> 🧭 Source: [src/lock.sh](../src/lock.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module provides a portable file lock (Linux/macOS) built on the
atomicity of `ln -s`: creating a symbolic link fails when the name already
exists, so one call both claims the lock and records who holds it. It works
the same way without depending on `flock`, which isn't shipped by default
on macOS.

A lock is a symbolic link whose target records the process holding it
(pid, hostname, and acquisition time), with the command kept in a
`.command` file beside it, which lets callers:

- prevent two runs of the same script from executing concurrently
- wait for a lock with a timeout instead of failing immediately
- inspect which process currently holds a lock
- detect and reclaim stale locks left behind by a dead process

When a lock has to be shared with other programs that `flock` the same
file, `dybatpho::flock_acquire`, `dybatpho::flock_release` and
`dybatpho::with_flock` take a `flock` instead. They need `flock` installed
and stop the script with an install hint when it isn't.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOCK_DIR`** | string | Base directory used to resolve lock names into lock paths |
| **`DYBATPHO_LOCK_POLL_INTERVAL`** | number | Seconds to sleep between acquire attempts while waiting |

### 🚀 Highlights

- [`dybatpho::lock_hostname`](#dybatpholock_hostname) — Print the host name a lock records as its owner. It is its own function so a test can replace it, which is how the stale-lock paths are exercised without a second machine.
- [`dybatpho::lock_path`](#dybatpholock_path) — Resolve a lock name or path into an absolute lock directory path.
- [`dybatpho::lock_field`](#dybatpholock_field) — Read a single metadata field recorded for a lock.
- [`dybatpho::lock_is_alive`](#dybatpholock_is_alive) — Return success when the process that owns a lock is still alive on this host.
- [`dybatpho::lock_is_held`](#dybatpholock_is_held) — Return success when a lock is currently held by a live process.
- [`dybatpho::lock_info`](#dybatpholock_info) — Print information about the process currently holding a lock.
- [`dybatpho::lock_reclaim_stale`](#dybatpholock_reclaim_stale) — Remove a lock left behind by a process that is no longer running. Deleting it in place was a way for two processes to end up holding the same lock. Both read the dead holder, both decided to reclaim, the first one removed it and took the lock, and the second one then removed *that* — a live lock — and took it as well. Reclaiming is therefore a rename rather than a delete. `rename()` fails when the source is gone, so of two processes racing to reclaim the same lock exactly one moves it aside and the loser touches nothing. The identity recorded in the lock is re-read from the moved-aside copy and compared with the one that was judged stale: they differ only when the lock was replaced between the judgement and the move, and the fresh lock is put back rather than deleted. Putting it back still lost to a third process: A judged the lock stale, B reclaimed and claimed it before A's move, A moved B's lock aside, and C claimed the emptied name before A could put it back, so B and C both held it. Reclaimers therefore take a guard, `<lock>.reclaim`, and look at the holder again once they hold it; with one reclaimer at a time the name only changes by a holder letting go, and a dead holder never does.
- [`dybatpho::lock_acquire`](#dybatpholock_acquire) — Acquire a portable, cross-platform (Linux/macOS) file lock, waiting up to a timeout.
- [`dybatpho::lock_release`](#dybatpholock_release) — Release a lock previously acquired by the current process.
- [`dybatpho::with_lock`](#dybatphowith_lock) — Acquire a lock, run a command while holding it, then release it, even if the command fails.
- [`dybatpho::flock_acquire`](#dybatphoflock_acquire) — Take a `flock` on a file through a descriptor of its own, for sharing a lock with other programs that `flock` the same file. Unlike `dybatpho::lock_acquire`, it needs `flock`, and records no holder: the kernel drops the lock when the holder dies, so there is nothing stale to reclaim.
- [`dybatpho::flock_release`](#dybatphoflock_release) — Let go of a lock taken by `dybatpho::flock_acquire` and close its descriptor. The lock is dropped before the descriptor is closed: a background job started while it was held has its own copy of the descriptor, and closing ours alone would leave the lock held for as long as that job runs.
- [`dybatpho::with_flock`](#dybatphowith_flock) — Take a `flock` on a file, run a command while holding it, then let go, even if the command fails. The command runs in the current shell, so a function it calls can set the caller's variables.
- [`dybatpho::lock_semaphore_acquire`](#dybatpholock_semaphore_acquire) — Take one of a fixed number of slots, so that at most that many processes run a section at once, waiting up to a timeout for one to free up. A semaphore is a row of ordinary locks, one per slot, tried in order. Each slot is claimed atomically and records its holder, so a slot left by a dead process is reclaimed exactly as a stale lock is, and a refusal names every process holding a slot. Every caller must give the same slot count.
- [`dybatpho::lock_semaphore_release`](#dybatpholock_semaphore_release) — Give back a semaphore slot taken by the current process. Naming the slot releases that one; without it, every slot the current process (`BASHPID`) holds is released, which is what an exit handler wants. A subshell releasing all its slots leaves the script's alone.
- [`dybatpho::lock_semaphore_holders`](#dybatpholock_semaphore_holders) — Print who holds each taken slot of a semaphore.
- [`dybatpho::with_semaphore`](#dybatphowith_semaphore) — Take a semaphore slot, run a command while holding it, then give the slot back, even if the command fails or the shell is interrupted.

<a id="usage"></a>

## 🚀 Usage

### Prevent concurrent runs of the same script

```bash
dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"
trap 'dybatpho::lock_release "$(basename "$0")"' EXIT
```

### Wait up to 30s for a lock, then run a command while holding it

```bash
dybatpho::with_lock "deploy" 30 -- ./deploy.sh
```

### Inspect who is holding a lock

```bash
dybatpho::lock_info "deploy"
```

### Share a lock with programs that `flock` the same file

```bash
dybatpho::with_flock "${state_dir}/state.lock" 5 -- _update_state
```

<a id="see-also"></a>

## 🔗 See also

- [example/lock_ops.sh](../example/lock_ops.sh)

<a id="tips"></a>

## 💡 Tips

**[`dybatpho::lock_acquire`](#dybatpholock_acquire)**

- Claims the lock with one `ln -s`, which fails when the lock exists, so no dependency on `flock` is required
- Pair with `dybatpho::lock_release` in a trap so the lock is always freed on exit

**[`dybatpho::lock_release`](#dybatpholock_release)**

- Safe to call even when the lock was never acquired by this process

**[`dybatpho::flock_acquire`](#dybatphoflock_acquire)**

- Each call opens a new descriptor, so several locks can be held at once
- A background job started while the lock is held inherits the descriptor; `dybatpho::flock_release` lets go even so

<a id="reference"></a>

## 📚 Reference

### `dybatpho::lock_hostname`

Print the host name a lock records as its owner. It is its own
function so a test can replace it, which is how the stale-lock paths are
exercised without a second machine.

_Function has no arguments._

**📤 Output on stdout**

- The host name

---

### `dybatpho::lock_path`

Resolve a lock name or path into an absolute lock directory path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name (bare word) or an explicit absolute/relative path |

**📤 Output on stdout**

- Absolute lock directory path, always suffixed with `.lock`

---

### `dybatpho::lock_field`

Read a single metadata field recorded for a lock.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock directory path |
| `$2` | string | Field name (pid\|host\|command\|acquired_at) |

**📤 Output on stdout**

- Recorded value, or empty when the lock or field doesn't exist

---

### `dybatpho::lock_is_alive`

Return success when the process that owns a lock is still alive on this host.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock directory path |

**🚦 Exit codes**

- `0`: The recorded pid belongs to a live process on the current host
- `1`: The lock is missing, foreign to this host, or its process is gone (stale)

---

### `dybatpho::lock_is_held`

Return success when a lock is currently held by a live process.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name or path |

**🚦 Exit codes**

- `0`: The lock exists and is held by a live process
- `1`: The lock doesn't exist or is stale

---

### `dybatpho::lock_info`

Print information about the process currently holding a lock.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name or path |

**📤 Output on stdout**

- `pid=<pid> host=<host> acquired_at=<timestamp> command=<command>` when held

**🚦 Exit codes**

- `0`: The lock is currently held and its info was printed
- `1`: The lock isn't held by anyone

---

### `dybatpho::lock_reclaim_stale`

Remove a lock left behind by a process that is no longer running.
Deleting it in place was a way for two processes to end up holding the same
lock. Both read the dead holder, both decided to reclaim, the first one
removed it and took the lock, and the second one then removed *that* — a
live lock — and took it as well.

Reclaiming is therefore a rename rather than a delete. `rename()` fails when
the source is gone, so of two processes racing to reclaim the same lock
exactly one moves it aside and the loser touches nothing. The identity
recorded in the lock is re-read from the moved-aside copy and compared with
the one that was judged stale: they differ only when the lock was replaced
between the judgement and the move, and the fresh lock is put back rather
than deleted.

Putting it back still lost to a third process: A judged the lock stale, B
reclaimed and claimed it before A's move, A moved B's lock aside, and C
claimed the emptied name before A could put it back, so B and C both held
it. Reclaimers therefore take a guard, `<lock>.reclaim`, and look at the
holder again once they hold it; with one reclaimer at a time the name only
changes by a holder letting go, and a dead holder never does.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock directory path |

**📤 Output on stderr**

- Notice when a stale lock is reclaimed

---

### `dybatpho::lock_acquire`

Acquire a portable, cross-platform (Linux/macOS) file lock, waiting up to a timeout.

**🧪 Examples**

```bash
dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"

```

```bash
dybatpho::lock_acquire "deploy" 30

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Lock name (bare word resolved under `DYBATPHO_LOCK_DIR`) or an explicit path |
| `$2` | number | no | `0` | Seconds to wait for the lock before giving up; `0` tries once without waiting |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOCK_DIR`** | string | Base directory used to resolve bare lock names |
| **`DYBATPHO_LOCK_POLL_INTERVAL`** | number | Seconds to sleep between acquire attempts while waiting |

**📤 Output on stderr**

- Info about the current holder when the lock can't be acquired

**🚦 Exit codes**

- `0`: The lock was acquired by the current process
- `1`: The lock is still held by another live process after the timeout elapses

---

### `dybatpho::lock_release`

Release a lock previously acquired by the current process.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name or path |

**🚦 Exit codes**

- `0`: The lock was released, or wasn't held by the current process to begin with
- `1`: The lock is held by a different, still-live process and was left untouched

---

### `dybatpho::with_lock`

Acquire a lock, run a command while holding it, then release it, even if the command fails.

**🧪 Example**

```bash
dybatpho::with_lock "deploy" 30 -- ./deploy.sh --env prod

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name or path |
| `$2` | number | Seconds to wait for the lock before giving up |
| `$3` | string | Literal `--` separating lock options from the command |
| `$@` | string | Command and arguments to run while holding the lock |

**🚦 Exit codes**

- `1`: The lock couldn't be acquired within the timeout
- `other`: Exit code of the wrapped command

---

### `dybatpho::flock_acquire`

Take a `flock` on a file through a descriptor of its own, for
sharing a lock with other programs that `flock` the same file. Unlike
`dybatpho::lock_acquire`, it needs `flock`, and records no holder: the
kernel drops the lock when the holder dies, so there is nothing stale to
reclaim.

**🧪 Example**

```bash
local fd
dybatpho::flock_acquire fd "${state_dir}/state.lock" 5 || dybatpho::die "State is busy"
# ... read, change and write the state ...
dybatpho::flock_release "${fd}"

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Name of the variable receiving the descriptor |
| `$2` | path | yes |  | File to lock, used as given and created when missing |
| `$3` | number | no | `wait until free` | Seconds to wait; `0` tries once without waiting |

**🧩 Variable sets**

- **`The`** (named): variable, to the descriptor holding the lock

**🚦 Exit codes**

- `0`: The lock was taken
- `1`: Another process held the lock for the whole wait
- `127`: Stop script when `flock` isn't installed

---

### `dybatpho::flock_release`

Let go of a lock taken by `dybatpho::flock_acquire` and close its
descriptor.
The lock is dropped before the descriptor is closed: a background job
started while it was held has its own copy of the descriptor, and closing
ours alone would leave the lock held for as long as that job runs.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Descriptor set by `dybatpho::flock_acquire` |

---

### `dybatpho::with_flock`

Take a `flock` on a file, run a command while holding it, then
let go, even if the command fails. The command runs in the current shell,
so a function it calls can set the caller's variables.

**🧪 Examples**

```bash
dybatpho::with_flock "${state_dir}/state.lock" 5 -- _update_state "${id}"

```

```bash
# Wait for whoever holds the lock to finish
dybatpho::with_flock "${state_dir}/state.lock" "" -- true

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | File to lock |
| `$2` | number | Seconds to wait; `0` tries once, empty waits until free |
| `$3` | string | Literal `--` separating lock options from the command |
| `$@` | string | Command and arguments to run while holding the lock |

**🚦 Exit codes**

- `1`: The lock couldn't be taken within the wait
- `127`: Stop script when `flock` isn't installed
- `other`: Exit code of the wrapped command

---

### `dybatpho::lock_semaphore_acquire`

Take one of a fixed number of slots, so that at most that many
processes run a section at once, waiting up to a timeout for one to free up.

A semaphore is a row of ordinary locks, one per slot, tried in order. Each
slot is claimed atomically and records its holder, so a slot left by a dead
process is reclaimed exactly as a stale lock is, and a refusal names every
process holding a slot. Every caller must give the same slot count.

**🧪 Example**

```bash
local slot
dybatpho::lock_semaphore_acquire downloads 4 60 slot || exit 1
curl -fsSLO "${url}"
dybatpho::lock_semaphore_release downloads 4 "${slot}"

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Semaphore name (bare word resolved under `DYBATPHO_LOCK_DIR`) or an explicit path |
| `$2` | number | yes |  | Number of slots, from 1 to 9999 |
| `$3` | number | no | `0` | Seconds to wait for a free slot before giving up; `0` tries once without waiting |
| `$4` | string | no |  | Name of a variable receiving the slot number taken |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOCK_POLL_INTERVAL`** | number | Seconds to sleep between attempts while waiting |

**🧩 Variable sets**

- **`The`** (named): variable, when one is given

**📤 Output on stderr**

- Every holder when no slot could be taken

**🚦 Exit codes**

- `0`: A slot was taken by the current process
- `1`: Every slot is still held by a live process after the timeout

---

### `dybatpho::lock_semaphore_release`

Give back a semaphore slot taken by the current process.
Naming the slot releases that one; without it, every slot the current
process (`BASHPID`) holds is released, which is what an exit handler
wants. A subshell releasing all its slots leaves the script's alone.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Semaphore name or path |
| `$2` | number | yes |  | Number of slots, as given when acquiring |
| `$3` | number | no |  | Slot number to release |

**🚦 Exit codes**

- `0`: The slot was released, or was not held by the current process
- `1`: The named slot is held by another live process and was left untouched

---

### `dybatpho::lock_semaphore_holders`

Print who holds each taken slot of a semaphore.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Semaphore name or path |
| `$2` | number | Number of slots |

**📤 Output on stdout**

- `slot=<n> pid=<pid> host=<host> acquired_at=<timestamp> command=<command>`, one line per held slot

**🚦 Exit codes**

- `0`: At least one slot is held
- `1`: No slot is held

---

### `dybatpho::with_semaphore`

Take a semaphore slot, run a command while holding it, then give
the slot back, even if the command fails or the shell is interrupted.

**🧪 Example**

```bash
dybatpho::with_semaphore builds 2 300 -- make -C "${project}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Semaphore name or path |
| `$2` | number | Number of slots |
| `$3` | number | Seconds to wait for a free slot before giving up |
| `$4` | string | Literal `--` separating semaphore options from the command |
| `$@` | string | Command and arguments to run while holding the slot |

**🚦 Exit codes**

- `1`: No slot could be taken within the timeout
- `other`: Exit code of the wrapped command
