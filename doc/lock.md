# lock.sh

Utilities for process locking and coordination

> 🧭 Source: [src/lock.sh](../src/lock.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module provides a portable file lock (Linux/macOS) built on the
atomicity of `mkdir`, so it works the same way without depending on
`flock`, which isn't shipped by default on macOS.


A lock is a directory containing metadata about the process holding it
(pid, hostname, command, and acquisition time), which lets callers:


- prevent two runs of the same script from executing concurrently
- wait for a lock with a timeout instead of failing immediately
- inspect which process currently holds a lock
- detect and reclaim stale locks left behind by a dead process

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOCK_DIR`** | string | Base directory used to resolve lock names into lock paths |
| **`DYBATPHO_LOCK_POLL_INTERVAL`** | number | Seconds to sleep between acquire attempts while waiting |

### 🚀 Highlights

- [`__dybatpho_lock_exists`](#__dybatpho_lock_exists) — Return success when something holds this lock path, whichever form it is in: a symbolic link, which is what the atomic claim writes, or a directory, which is what versions before it wrote. `[[ -L ]]` is deliberately first and deliberately not `[[ -e ]]`: the link target is data rather than a path, so it never resolves, and `-e` reports a dangling link as absent.
- [`__dybatpho_lock_target`](#__dybatpho_lock_target) — Print the link target that identifies the holder of a lock, as `pid:host:acquired_at`.
- [`dybatpho::lock_hostname`](#dybatpholock_hostname) — 
- [`dybatpho::lock_path`](#dybatpholock_path) — Resolve a lock name or path into an absolute lock directory path.
- [`dybatpho::lock_field`](#dybatpholock_field) — Read a single metadata field recorded for a lock.
- [`dybatpho::lock_is_alive`](#dybatpholock_is_alive) — Return success when the process that owns a lock is still alive on this host.
- [`dybatpho::lock_is_held`](#dybatpholock_is_held) — Return success when a lock is currently held by a live process.
- [`dybatpho::lock_info`](#dybatpholock_info) — Print information about the process currently holding a lock.
- [`dybatpho::lock_reclaim_stale`](#dybatpholock_reclaim_stale) — Remove a lock left behind by a process that is no longer running. Deleting it in place was a way for two processes to end up holding the same lock. Both read the dead holder, both decided to reclaim, the first one removed it and took the lock, and the second one then removed *that* — a live lock — and took it as well. Reclaiming is therefore a rename rather than a delete. `rename()` fails when the source is gone, so of two processes racing to reclaim the same lock exactly one moves it aside and the loser touches nothing. The identity recorded in the lock is re-read from the moved-aside copy and compared with the one that was judged stale: they differ only when the lock was replaced between the judgement and the move, and the fresh lock is put back rather than deleted.
- [`__dybatpho_lock_identity`](#__dybatpho_lock_identity) — Print what identifies the holder of a lock, for comparing one observation of a lock with a later one. It is the link target for the atomic form, and the recorded pid for the directory form older copies of the library wrote.
- [`dybatpho::lock_acquire`](#dybatpholock_acquire) — Acquire a portable, cross-platform (Linux/macOS) file lock, waiting up to a timeout.
- [`dybatpho::lock_release`](#dybatpholock_release) — Release a lock previously acquired by the current process.
- [`dybatpho::with_lock`](#dybatphowith_lock) — Acquire a lock, run a command while holding it, then release it, even if the command fails.

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

<a id="see-also"></a>
## 🔗 See also

- [example/lock_ops.sh](../example/lock_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::lock_acquire`

- Uses `mkdir` for atomic lock creation, so no dependency on `flock` is required
- Pair with `dybatpho::lock_release` in a trap so the lock is always freed on exit

### `dybatpho::lock_release`

- Safe to call even when the lock was never acquired by this process

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_lock_exists`

Return success when something holds this lock path, whichever
  form it is in: a symbolic link, which is what the atomic claim writes, or a
  directory, which is what versions before it wrote.


  `[[ -L ]]` is deliberately first and deliberately not `[[ -e ]]`: the link
  target is data rather than a path, so it never resolves, and `-e` reports a
  dangling link as absent.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock path |

**🚦 Exit codes**

- `0`: A lock is present
- `1`: Nothing is there


---

### `__dybatpho_lock_target`

Print the link target that identifies the holder of a lock,
  as `pid:host:acquired_at`.

**📤 Output on stdout**

- The target


---

### `dybatpho::lock_hostname`



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

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock directory path |

**📤 Output on stderr**

- Notice when a stale lock is reclaimed


---

### `__dybatpho_lock_identity`

Print what identifies the holder of a lock, for comparing one
  observation of a lock with a later one. It is the link target for the
  atomic form, and the recorded pid for the directory form older copies of
  the library wrote.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock path |

**📤 Output on stdout**

- The identity, or nothing when the lock is gone


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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Lock name (bare word resolved under `DYBATPHO_LOCK_DIR`) or an explicit path |
| `$2` | number | Seconds to wait for the lock before giving up, default 0 (try once, don't wait) |

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

