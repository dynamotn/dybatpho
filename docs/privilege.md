# privilege.sh

Acquiring and holding a privilege escalation for a run

> 🧭 Source: [src/privilege.sh](../src/privilege.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`pkg.sh` can put `sudo` in front of one command. A script that runs twenty
of them over several minutes needs something else: the password asked for
once at the start, the ticket kept alive while the work runs, and no child
process able to stop and ask for it again halfway through.

That is what this module holds. `dybatpho::privilege_acquire` authenticates
once, refreshes the ticket in the background for as long as the script
lives, and -- when asked to -- puts a non-interactive `sudo` first on
`PATH` so nothing underneath can prompt. The refresher is tied to this
process and torn down through `process.sh`'s trap handling, so it cannot
outlive the script that started it.

Only the escalation itself lives here. Whether an action should happen at
all is `safety.sh`'s question, and the two are independent: reading a
protected file needs privilege and destroys nothing, while deleting your
own work needs no privilege at all.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PRIVILEGE_COMMAND`** | string | Escalation command, `auto` to detect `sudo` then `doas` |
| **`DYBATPHO_PRIVILEGE`** | string | `auto` elevates when not root, `true`/`false` override the detection |
| **`DYBATPHO_PRIVILEGE_SUSPEND_HOOK`** | string | Function called with `suspend` before prompting and `resume` after |
| **`DYBATPHO_PRIVILEGE_REFRESH`** | number | Seconds between ticket refreshes, default is `60` |
| **`DYBATPHO_PRIVILEGE`** | string | Whether to elevate at all: `auto`, `true`, or `false` |
| **`DYBATPHO_PRIVILEGE_COMMAND`** | string | Escalation command to use, or `auto` to detect one |
| **`DYBATPHO_PRIVILEGE_SUSPEND_HOOK`** | string | Function handing the terminal over around a prompt |
| **`DYBATPHO_PRIVILEGE_REFRESH`** | number | Seconds between ticket refreshes |

### 🚀 Highlights

- [`dybatpho::privilege_command`](#dybatphoprivilege_command) — Print the escalation command this host should use. `sudo` first, then `doas`. `run0` is deliberately not detected: it is new enough that a script finding it would more often be finding a system where `sudo` was the intended path.
- [`dybatpho::privilege_needed`](#dybatphoprivilege_needed) — Return success when a command has to be elevated to run. Already root, no escalation command installed, or the caller turning it off all mean no.
- [`__dybatpho_privilege_hand_over`](#__dybatpho_privilege_hand_over) — Hand the terminal over, or take it back, around a prompt. A full-screen application draws over the alternate screen, where a password prompt is invisible; the hook is how such a caller steps aside without this module knowing anything about `screen` or `tui`.
- [`__dybatpho_privilege_cached`](#__dybatpho_privilege_cached) — Return success when the escalation command already holds a valid ticket, so no prompt would appear.
- [`__dybatpho_privilege_keepalive`](#__dybatpho_privilege_keepalive) — Keep the escalation ticket alive until this process ends. The refresher watches the parent rather than being signalled by it: a script killed outright never gets to signal anything, and a refresher left behind would hold a ticket for a process that no longer exists.
- [`__dybatpho_privilege_shield`](#__dybatpho_privilege_shield) — Put a non-interactive escalation command first on `PATH`. Without this, a child process deep inside a package manager can stop and ask for a password that nothing is in a position to display. The wrapper makes that failure loud and immediate instead of a run that hangs.
- [`dybatpho::privilege_acquire`](#dybatphoprivilege_acquire) — Authenticate once and hold the escalation for this run. Nothing happens when elevation is not needed, so a caller can ask unconditionally. Asking again while the escalation is held adds only what was not there yet, such as the wrapper a first call without `--shield` left out; it never starts a second refresher or wrapper. When a prompt is required and the session cannot answer one, this fails rather than blocking on a password nothing will type -- which is what a script run from cron needs.
- [`dybatpho::privilege_release`](#dybatphoprivilege_release) — Let the escalation go: stop the refresher and take the wrapper off `PATH`. Calling it when nothing was acquired does nothing.
- [`dybatpho::privilege_run`](#dybatphoprivilege_run) — Run one command elevated, for a caller that needs that and no session. When elevation is not needed the command runs as it is, so the call reads the same either way.

<a id="see-also"></a>
## 🔗 See also

- [example/privilege_ops.sh](../example/privilege_ops.sh)

<a id="tips"></a>
## 💡 Tips

- A full-screen application has to give the terminal back before the password prompt is drawn, which is what `DYBATPHO_PRIVILEGE_SUSPEND_HOOK` is for

<a id="reference"></a>
## 📚 Reference

### `dybatpho::privilege_command`

Print the escalation command this host should use.
`sudo` first, then `doas`. `run0` is deliberately not detected: it is new
enough that a script finding it would more often be finding a system where
`sudo` was the intended path.

_Function has no arguments._

**📤 Output on stdout**

- `sudo`, `doas`, or nothing when neither is installed

**🚦 Exit codes**

- `0`: A command was printed
- `1`: Neither is installed


---

### `dybatpho::privilege_needed`

Return success when a command has to be elevated to run.
Already root, no escalation command installed, or the caller turning it
off all mean no.

**🧪 Example**

```bash
dybatpho::privilege_needed && dybatpho::privilege_acquire
```

_Function has no arguments._

**🚦 Exit codes**

- `0`: Elevation is needed
- `1`: It is not


---

### `__dybatpho_privilege_hand_over`

Hand the terminal over, or take it back, around a prompt.
A full-screen application draws over the alternate screen, where a
password prompt is invisible; the hook is how such a caller steps aside
without this module knowing anything about `screen` or `tui`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | `suspend` or `resume` |


---

### `__dybatpho_privilege_cached`

Return success when the escalation command already holds a
valid ticket, so no prompt would appear.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Escalation command |

**🚦 Exit codes**

- `0`: A ticket is cached
- `1`: There is none, or this command has no cache to ask about


---

### `__dybatpho_privilege_keepalive`

Keep the escalation ticket alive until this process ends.
The refresher watches the parent rather than being signalled by it: a
script killed outright never gets to signal anything, and a refresher
left behind would hold a ticket for a process that no longer exists.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Escalation command |
| `$2` | number | Seconds between refreshes |


---

### `__dybatpho_privilege_shield`

Put a non-interactive escalation command first on `PATH`.
Without this, a child process deep inside a package manager can stop and
ask for a password that nothing is in a position to display. The wrapper
makes that failure loud and immediate instead of a run that hangs.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Escalation command |

**🚦 Exit codes**

- `0`: The wrapper is in place and `PATH` points at it


---

### `dybatpho::privilege_acquire`

Authenticate once and hold the escalation for this run.
Nothing happens when elevation is not needed, so a caller can ask
unconditionally. Asking again while the escalation is held adds only what
was not there yet, such as the wrapper a first call without `--shield`
left out; it never starts a second refresher or wrapper. When a prompt is required and the session cannot answer
one, this fails rather than blocking on a password nothing will type --
which is what a script run from cron needs.

**🧪 Example**

```bash
dybatpho::privilege_acquire --shield || dybatpho::die "Cannot elevate"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Options, in any order |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report what would be acquired and change nothing |

**🚦 Exit codes**

- `0`: The escalation is held, or was not needed
- `1`: Authentication failed, or a prompt was needed and could not be answered


---

### `dybatpho::privilege_release`

Let the escalation go: stop the refresher and take the wrapper
off `PATH`. Calling it when nothing was acquired does nothing.

**🧪 Example**

```bash
dybatpho::privilege_release
```

_Function has no arguments._

**🚦 Exit codes**

- `0`: Anything that was held is released


---

### `dybatpho::privilege_run`

Run one command elevated, for a caller that needs that and no
session. When elevation is not needed the command runs as it is, so the
call reads the same either way.

**🧪 Example**

```bash
dybatpho::privilege_run -- systemctl restart nginx
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Literal `--` separating the options from the command |
| `$@` | string | Command and arguments to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the command instead of running it |

**🚦 Exit codes**

- `0`: The command ran
- `other`: The command's own exit code
