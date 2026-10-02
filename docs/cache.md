# cache.sh

Utilities for remembering an answer on disk until it goes stale

> 🧭 Source: [src/cache.sh](../src/cache.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

A script that asks a slow question more than once -- an API listing, a
dependency resolution, a `--version` probe across a fleet -- ends up writing
the same four lines: work out a file name, check how old the file is,
compare that against a number of seconds, and remember to create the
directory. `dybatpho::file_age_seconds` even documents that shape as its own
example. This module is that shape, written once.

The centre of it is `dybatpho::cache_run`, which memoizes what a command
prints:

```sh
releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"
```

A failing command is never stored. Caching a failure turns one bad minute
into an hour of them, and the caller cannot tell the difference between a
remembered error and a fresh one.

Entries are written through `dybatpho::file_write_atomic`, so a reader sees
either the previous entry or the complete new one, never half of a write in
progress.

The `lock` module guards the background refresh `dybatpho::cache_run
--stale` starts, so that a burst of callers finding the same stale entry
runs the command once.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries, default is the XDG cache directory for `dybatpho` |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Subdirectory grouping related entries, default is `default`; empty puts entries directly in the cache directory |
| **`DYBATPHO_CACHE_TTL`** | number | Seconds an entry stays fresh when a call does not say, default is `3600` |
| **`DYBATPHO_CACHE_STALE`** | number | Seconds `dybatpho::cache_run` may serve an expired entry while it refreshes in the background, default is `0` (never) |

### 🚀 Highlights

- [`dybatpho::cache_dir`](#dybatphocache_dir) — Print the directory entries are written to. This is `DYBATPHO_CACHE_DIR` with the namespace below it, or the cache directory itself when the namespace is empty.
- [`dybatpho::cache_key`](#dybatphocache_key) — Turn any values into a key that is safe as a file name. Call this when the thing that identifies an entry is a URL, a request body, or anything else that is not already a short name.
- [`dybatpho::cache_path`](#dybatphocache_path) — Print the path an entry is stored at.
- [`dybatpho::cache_has`](#dybatphocache_has) — Return success when an entry exists and is still fresh. An entry is fresh while `age < ttl`, so a time to live of one hour means an entry lives one hour. `0` therefore makes nothing fresh, which is the way to force a refresh without deleting anything. There is no value meaning "never expires": an entry that never goes stale is a file, and `dybatpho::file_write_atomic` writes those.
- [`dybatpho::cache_get`](#dybatphocache_get) — Print an entry when it is still fresh.
- [`dybatpho::cache_set`](#dybatphocache_set) — Store standard input as an entry. The write goes through `dybatpho::file_write_atomic`, so a reader sees the previous entry or the whole new one, and two writers cannot interleave.
- [`dybatpho::cache_forget`](#dybatphocache_forget) — Remove one entry.
- [`dybatpho::cache_clear`](#dybatphocache_clear) — Remove every entry in the current namespace. Only files this module wrote are removed, recognised by their suffix. The cache directory is named by an environment variable, and emptying whatever a path happens to contain is not a thing a helper should offer to do.
- [`dybatpho::cache_wait`](#dybatphocache_wait) — Wait until no background refresh of an entry is running. `dybatpho::cache_run --stale` answers from an expired entry and refreshes it behind the caller's back. Usually that is the point, but a script that is about to exit, or that wants the refreshed answer for a later step, calls this first. The refresh usually runs in a command substitution's subshell, which a bare `wait` in the calling shell knows nothing about.
- [`dybatpho::cache_run`](#dybatphocache_run) — Print what a command prints, running it only when the remembered answer has gone stale. This is the whole module in one call: ask once, reuse the answer until it expires, and put the command's own output through unchanged either way. A command that fails is not stored, and its exit status is returned as it is. Remembering a failure would turn one bad minute into a whole time to live of them, and the caller could not tell a remembered error from a fresh one. Standard error is not captured either way, so a warning the command prints is seen every time rather than once. `--stale <seconds>` adds a grace window after the time to live: an entry older than the time to live but younger than the two together is printed at once, as it is, while the command runs again in the background to replace it. The caller never waits for a slow source that answered recently, and the answer is at most one refresh behind. Only one refresh of an entry runs at a time, guarded by a lock beside the entry, and a refresh that fails keeps the entry it was meant to replace. An entry older than the window is a miss, and the command runs in the foreground as usual. `dybatpho::cache_wait` waits for a refresh to finish.
- [`dybatpho::cache_prune`](#dybatphocache_prune) — Remove old entries until the namespace fits the limits given. Entries older than `--older-than` go first. Then, while the namespace holds more than `--max-entries` entries or more than `--max-size` bytes, the oldest remaining entry is removed. Oldest means least recently written: an entry's modification time is also its age, so reading an entry cannot mark it as used without making it look fresh, and the entry the cache refreshed longest ago is the one it would refetch first anyway. Like `dybatpho::cache_clear`, only files this module wrote are considered, and only in the current namespace.
- [`dybatpho::cache_stats`](#dybatphocache_stats) — Describe the current namespace: how many entries it holds, how many bytes they take, how many are still fresh, and how old the oldest and newest are. Freshness is judged against the time to live given, or `DYBATPHO_CACHE_TTL`, the same way `dybatpho::cache_has` judges one entry. Ages are in seconds. A namespace that was never written reports zero everywhere rather than failing, so a report or a metric can always be made. Hits and misses are not counted. `dybatpho::cache_run` is usually called in a command substitution, whose subshell would take any count with it, and a count kept on disk would turn every read into a write.

<a id="see-also"></a>
## 🔗 See also

- [example/cache_ops.sh](../example/cache_ops.sh)
- [dybatpho::file_age_seconds](#dybatphofile_age_seconds)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::cache_dir`

Print the directory entries are written to.
This is `DYBATPHO_CACHE_DIR` with the namespace below it, or the cache
directory itself when the namespace is empty.

**🧪 Example**

```bash
dybatpho::cache_dir                                   # ~/.cache/dybatpho/default
DYBATPHO_CACHE_NAMESPACE=gh dybatpho::cache_dir        # ~/.cache/dybatpho/gh

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Subdirectory grouping related entries |

**📤 Output on stdout**

- The directory entries live in


---

### `dybatpho::cache_key`

Turn any values into a key that is safe as a file name.
Call this when the thing that identifies an entry is a URL, a request body,
or anything else that is not already a short name.

**🧪 Example**

```bash
key="$(dybatpho::cache_key "${url}" "${token_owner}")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Values identifying the entry; each is hashed in order |

**📤 Output on stdout**

- A hexadecimal key

**🚦 Exit codes**

- `1`: Stop the script when no value is given or no hashing command exists


---

### `dybatpho::cache_path`

Print the path an entry is stored at.

**🧪 Example**

```bash
dybatpho::cache_path releases

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Subdirectory grouping related entries |

**📤 Output on stdout**

- The path of the entry, whether or not it exists

**🚦 Exit codes**

- `1`: Stop the script when the key cannot be a file name


---

### `dybatpho::cache_has`

Return success when an entry exists and is still fresh.
An entry is fresh while `age < ttl`, so a time to live of one hour means an
entry lives one hour. `0` therefore makes nothing fresh, which is the way to
force a refresh without deleting anything. There is no value meaning "never
expires": an entry that never goes stale is a file, and
`dybatpho::file_write_atomic` writes those.

**🧪 Example**

```bash
if dybatpho::cache_has releases 3600; then ... ; fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |
| `$2` | number | Seconds the entry stays fresh, default is `DYBATPHO_CACHE_TTL` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_TTL`** | number | Default time to live |

**🚦 Exit codes**

- `0`: The entry exists and is fresh
- `1`: There is no entry, or it is older than the time to live


---

### `dybatpho::cache_get`

Print an entry when it is still fresh.

**🧪 Example**

```bash
if body="$(dybatpho::cache_get releases 3600)"; then
  dybatpho::debug "Using the remembered listing"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |
| `$2` | number | Seconds the entry stays fresh, default is `DYBATPHO_CACHE_TTL` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_TTL`** | number | Default time to live |

**📤 Output on stdout**

- The stored entry

**🚦 Exit codes**

- `0`: A fresh entry was printed
- `1`: There is no entry, or it is older than the time to live

**🔗 See also**

- [- `dybatpho::cache_run](#dybatphocache_run)


---

### `dybatpho::cache_set`

Store standard input as an entry.
The write goes through `dybatpho::file_write_atomic`, so a reader sees the
previous entry or the whole new one, and two writers cannot interleave.

**🧪 Example**

```bash
printf '%s\n' "${body}" | dybatpho::cache_set releases

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DRY_RUN`** | string | When true-like, report the write instead of performing it |

**📥 Input on stdin**

- The content to store

**🚦 Exit codes**

- `0`: The entry was written
- `1`: Stop the script when the key cannot be a file name or the write fails


---

### `dybatpho::cache_forget`

Remove one entry.

**🧪 Example**

```bash
dybatpho::cache_forget releases

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |

**🚦 Exit codes**

- `0`: The entry is gone, whether or not it was there
- `1`: Stop the script when the key cannot be a file name


---

### `dybatpho::cache_clear`

Remove every entry in the current namespace.
Only files this module wrote are removed, recognised by their suffix. The
cache directory is named by an environment variable, and emptying whatever
a path happens to contain is not a thing a helper should offer to do.

**🧪 Example**

```bash
dybatpho::cache_clear
DYBATPHO_CACHE_NAMESPACE=gh dybatpho::cache_clear

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Namespace to empty |
| **`DRY_RUN`** | string | When true-like, report the removal instead of performing it |

**🚦 Exit codes**

- `0`: The namespace holds no entries, whether or not it did before


---

### `dybatpho::cache_wait`

Wait until no background refresh of an entry is running.
`dybatpho::cache_run --stale` answers from an expired entry and refreshes it
behind the caller's back. Usually that is the point, but a script that is
about to exit, or that wants the refreshed answer for a later step, calls
this first. The refresh usually runs in a command substitution's subshell,
which a bare `wait` in the calling shell knows nothing about.

**🧪 Example**

```bash
status="$(dybatpho::cache_run status 300 --stale 86400 -- fetch_status)"
dybatpho::cache_wait status 30 || dybatpho::warn "status refresh still running"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |
| `$2` | number | Seconds to wait at most, default is `60` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_LOCK_POLL_INTERVAL`** | number | Seconds to sleep between checks |

**🚦 Exit codes**

- `0`: No refresh of the entry is running
- `1`: A refresh was still running when the time ran out


---

### `dybatpho::cache_run`

Print what a command prints, running it only when the remembered
answer has gone stale.
This is the whole module in one call: ask once, reuse the answer until it
expires, and put the command's own output through unchanged either way.

A command that fails is not stored, and its exit status is returned as it
is. Remembering a failure would turn one bad minute into a whole time to
live of them, and the caller could not tell a remembered error from a fresh
one. Standard error is not captured either way, so a warning the command
prints is seen every time rather than once.

`--stale <seconds>` adds a grace window after the time to live: an entry
older than the time to live but younger than the two together is printed
at once, as it is, while the command runs again in the background to
replace it. The caller never waits for a slow source that answered recently,
and the answer is at most one refresh behind. Only one refresh of an entry
runs at a time, guarded by a lock beside the entry, and a refresh that fails
keeps the entry it was meant to replace. An entry older than the window is
a miss, and the command runs in the foreground as usual.
`dybatpho::cache_wait` waits for a refresh to finish.

**🧪 Examples**

```bash
releases="$(dybatpho::cache_run gh-releases 3600 -- gh api /repos/o/r/releases)"

```

```bash
# Without a time to live, DYBATPHO_CACHE_TTL decides.
dybatpho::cache_run tags -- git ls-remote --tags origin

```

```bash
# Fresh for five minutes, then served stale for up to a day while it refreshes.
dybatpho::cache_run status 300 --stale 86400 -- curl -fsS "${status_url}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry key |
| `$2` | number | Optional seconds the entry stays fresh, before `--` |
| `$@` | string | Optional `--stale <seconds>`, then `--` followed by the command and its arguments |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_TTL`** | number | Default time to live |
| **`DYBATPHO_CACHE_STALE`** | number | Default grace window in seconds, `0` (none) unless set |

**📤 Output on stdout**

- The command's output, from the entry or from running it

**🚦 Exit codes**

- `0`: The output came from a fresh or stale entry, or the command succeeded
- `other`: The command failed, with its own exit status, and nothing was stored
- `1`: Stop the script when no command is given after `--`, or a time is not a number of seconds

**🔗 See also**

- [- `dybatpho::cache_get` - `dybatpho::cache_wait](#dybatphocache_get-dybatphocache_wait)


---

### `dybatpho::cache_prune`

Remove old entries until the namespace fits the limits given.
Entries older than `--older-than` go first. Then, while the namespace holds
more than `--max-entries` entries or more than `--max-size` bytes, the
oldest remaining entry is removed. Oldest means least recently written: an
entry's modification time is also its age, so reading an entry cannot mark
it as used without making it look fresh, and the entry the cache refreshed
longest ago is the one it would refetch first anyway.

Like `dybatpho::cache_clear`, only files this module wrote are considered,
and only in the current namespace.

**🧪 Example**

```bash
dybatpho::cache_prune --older-than 604800
dybatpho::cache_prune --max-entries 500 --max-size 50M

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | At least one of `--older-than <seconds>`, `--max-entries <count>`, `--max-size <size>`; a size takes an optional binary `K`, `M` or `G` suffix |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Namespace to prune |
| **`DRY_RUN`** | string | When true-like, report each removal instead of performing it |

**🚦 Exit codes**

- `0`: The namespace fits the limits, whether or not anything was removed
- `1`: Stop the script when no limit is given, an option is unknown, or a limit is malformed

**🔗 See also**

- [- `dybatpho::cache_stats](#dybatphocache_stats)


---

### `dybatpho::cache_stats`

Describe the current namespace: how many entries it holds, how
many bytes they take, how many are still fresh, and how old the oldest and
newest are.
Freshness is judged against the time to live given, or
`DYBATPHO_CACHE_TTL`, the same way `dybatpho::cache_has` judges one entry.
Ages are in seconds. A namespace that was never written reports zero
everywhere rather than failing, so a report or a metric can always be made.

Hits and misses are not counted. `dybatpho::cache_run` is usually called in
a command substitution, whose subshell would take any count with it, and a
count kept on disk would turn every read into a write.

**🧪 Examples**

```bash
dybatpho::cache_stats
# namespace  default
# directory  /home/me/.cache/dybatpho/default
# entries    3
# bytes      1800
# fresh      1
# stale      2
# oldest     7200
# newest     5

```

```bash
dybatpho::cache_stats 600 --json | jq .stale

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Optional seconds an entry stays fresh, default is `DYBATPHO_CACHE_TTL` |
| `$@` | string | Optional `--json`, for one JSON object of the counts instead of aligned lines |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CACHE_DIR`** | string | Directory holding cache entries |
| **`DYBATPHO_CACHE_NAMESPACE`** | string | Namespace to describe |
| **`DYBATPHO_CACHE_TTL`** | number | Default time to live |

**📤 Output on stdout**

- The report; the JSON form holds `entries`, `bytes`, `fresh`, `stale`, `oldest_age` and `newest_age`

**🚦 Exit codes**

- `0`: The report was printed
- `1`: Stop the script when the time to live is not a number of seconds or an option is unknown

**🔗 See also**

- [- `dybatpho::cache_prune](#dybatphocache_prune)
