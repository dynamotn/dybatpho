# service.sh

Utilities for enabling, controlling and installing services

> 🧭 Source: [src/service.sh](../src/service.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module drives the machine's service manager -- systemd, OpenRC,
runit on Termux, or launchd -- through one set of calls: enable, disable,
start, stop, restart, ask whether a service is active or enabled, and
install a unit file or plist so the manager picks it up.

An action takes the service name and an optional `--user`. Without it the
action is on the system scope and goes through `dybatpho::privilege_run`;
with it, on the user's own manager, never elevated. Every command can be
printed first with `dybatpho::service_command`, and `DYBATPHO_DRY_RUN`
prints instead of running.

A machine whose manager cannot act -- a container, a CI runner, SSH into a
Mac with no GUI session -- is skipped with a warning, so a bootstrap does
not fail on it; `DYBATPHO_SERVICE_STRICT` makes that a failure.

### 🌍 Environment

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_SERVICE_MANAGER`** | string | yes |  | Force a service manager: `systemd`, `openrc`, `runit` or `launchd` |
| **`DYBATPHO_SERVICE_STRICT`** | bool | no | `false` | Fail, rather than warn and skip, when no manager can act |

### 🚀 Highlights

- [`dybatpho::service_manager`](#dybatphoservice_manager) — Print the service manager this machine runs.
- [`dybatpho::service_manager_available`](#dybatphoservice_manager_available) — Tell whether the service manager can act in a scope here: it is installed, and running for that scope. systemd's user scope needs a user manager answering `show-environment`; its system scope a system that is not `offline` (a chroot) and not a container. OpenRC's user scope needs a user instance, OpenRC 0.60 and later; launchd's, a GUI session.
- [`dybatpho::service_command`](#dybatphoservice_command) — Print the commands an action would run, one shell-quoted command per line, with the elevation prefix where the action is elevated. Nothing is run.
- [`dybatpho::service_enable`](#dybatphoservice_enable) — Enable a service so it starts at boot or login, and start it now.
- [`dybatpho::service_disable`](#dybatphoservice_disable) — Disable a service so it no longer starts, and stop it now. On launchd the job is also unloaded.
- [`dybatpho::service_start`](#dybatphoservice_start) — Start a service now, without enabling it.
- [`dybatpho::service_stop`](#dybatphoservice_stop) — Stop a service now, without disabling it. On launchd the job is unloaded, since a stopped job with `KeepAlive` would be started again.
- [`dybatpho::service_restart`](#dybatphoservice_restart) — Restart a service.
- [`dybatpho::service_is_active`](#dybatphoservice_is_active) — Tell whether a service is running now. On launchd a loaded job that is not running counts as not active.
- [`dybatpho::service_is_enabled`](#dybatphoservice_is_enabled) — Tell whether a service is enabled, so it starts at boot or login.
- [`dybatpho::service_reload_manager`](#dybatphoservice_reload_manager) — Reload the manager's view of its unit files: `daemon-reload` on systemd, nothing elsewhere.
- [`dybatpho::service_install`](#dybatphoservice_install) — Put a unit file or launchd plist where the manager reads it, have the manager pick it up, and enable the service. The file is compared with what is there first: an identical one is not written and causes no reload. A changed one is replaced, the manager reloads, and a running service restarts. On launchd the label is enabled before `bootstrap`, which refuses a label left disabled.
- [`dybatpho::service_uninstall`](#dybatphoservice_uninstall) — Disable a service, remove the unit file `dybatpho::service_install` put in place, and reload the manager.

<a id="usage"></a>

## 🚀 Usage

### Install a user unit and have it running, on systemd or launchd alike

```bash
dybatpho::service_install "${HOME}/.config/app/app.service" --user
```

### Enable a system service, elevated as needed

```bash
dybatpho::service_enable sshd
```

<a id="see-also"></a>

## 🔗 See also

- [example/service_ops.sh](../example/service_ops.sh)

<a id="tips"></a>

## 💡 Tips

**[`dybatpho::service_enable`](#dybatphoservice_enable)**

- On launchd the job must already be loaded; `dybatpho::service_install` loads it

**[`dybatpho::service_install`](#dybatphoservice_install)**

- A system file is written mode 644, and root:wheel on launchd, as `bootstrap` requires

<a id="reference"></a>

## 📚 Reference

### `dybatpho::service_manager`

Print the service manager this machine runs.

**🧪 Example**

```bash
case "$(dybatpho::service_manager)" in
  systemd) ... ;;
esac

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SERVICE_MANAGER`** | string | Force a manager instead of detecting one |

**📤 Output on stdout**

- `systemd`, `openrc`, `runit` or `launchd`

**🚦 Exit codes**

- `0`: A manager was found
- `1`: None was found

---

### `dybatpho::service_manager_available`

Tell whether the service manager can act in a scope here: it is
installed, and running for that scope. systemd's user scope needs a user
manager answering `show-environment`; its system scope a system that is
not `offline` (a chroot) and not a container. OpenRC's user scope needs a
user instance, OpenRC 0.60 and later; launchd's, a GUI session.

**🧪 Example**

```bash
dybatpho::service_manager_available --user || dybatpho::warn "No user services here"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: The manager can act in that scope
- `1`: It cannot, or there is none

---

### `dybatpho::service_command`

Print the commands an action would run, one shell-quoted
command per line, with the elevation prefix where the action is elevated.
Nothing is run.

**🧪 Example**

```bash
dybatpho::service_command enable sshd
# sudo -- systemctl enable --now sshd

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Action: `enable`, `disable`, `start`, `stop`, `restart`, `is-active` or `is-enabled` |
| `$2` | string | Service name |
| `$3` | string | [optional] `--user` for the user's own manager |

**📤 Output on stdout**

- The commands, one per line

**🚦 Exit codes**

- `0`: The commands were printed
- `1`: No service manager was found

---

### `dybatpho::service_enable`

Enable a service so it starts at boot or login, and start it now.

**🧪 Example**

```bash
dybatpho::service_enable sshd
dybatpho::service_enable syncthing --user

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DRY_RUN`** | string | When true-like, print the commands instead of running them |

**🚦 Exit codes**

- `0`: Enabled, or skipped with a warning where no manager can act
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed

---

### `dybatpho::service_disable`

Disable a service so it no longer starts, and stop it now. On
launchd the job is also unloaded.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Disabled, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed

---

### `dybatpho::service_start`

Start a service now, without enabling it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Started, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed

---

### `dybatpho::service_stop`

Stop a service now, without disabling it. On launchd the job is
unloaded, since a stopped job with `KeepAlive` would be started again.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Stopped, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed

---

### `dybatpho::service_restart`

Restart a service.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Restarted, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed

---

### `dybatpho::service_is_active`

Tell whether a service is running now. On launchd a loaded job
that is not running counts as not active.

**🧪 Example**

```bash
dybatpho::service_is_active rclone --user && dybatpho::info "rclone is running"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: It is running
- `1`: It is not, or no manager can answer

---

### `dybatpho::service_is_enabled`

Tell whether a service is enabled, so it starts at boot or login.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: It is enabled
- `1`: It is not, or no manager can answer

---

### `dybatpho::service_reload_manager`

Reload the manager's view of its unit files: `daemon-reload`
on systemd, nothing elsewhere.

**🧪 Example**

```bash
dybatpho::service_reload_manager --user

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Reloaded, nothing to do, or skipped with a warning
- `other`: Exit code of `systemctl daemon-reload`

---

### `dybatpho::service_install`

Put a unit file or launchd plist where the manager reads it,
have the manager pick it up, and enable the service.
The file is compared with what is there first: an identical one is not
written and causes no reload. A changed one is replaced, the manager
reloads, and a running service restarts. On launchd the label is enabled
before `bootstrap`, which refuses a label left disabled.

**🧪 Example**

```bash
dybatpho::service_install ./sync.service --user
dybatpho::service_install ./dev.example.sync.plist --user

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | Unit file or plist |
| `$@` | string | [optional] `--user` for the user's own manager, and `--name NAME` to install under another name |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DRY_RUN`** | string | When true-like, print the commands instead of running them |

**🚦 Exit codes**

- `0`: Installed and enabled, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set, or the file is missing
- `other`: Exit code of the command that failed

---

### `dybatpho::service_uninstall`

Disable a service, remove the unit file `dybatpho::service_install`
put in place, and reload the manager.

**🧪 Example**

```bash
dybatpho::service_uninstall sync.service --user

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Service name, as installed |
| `$2` | string | [optional] `--user` for the user's own manager |

**🚦 Exit codes**

- `0`: Removed, or skipped with a warning
- `1`: No manager can act and `DYBATPHO_SERVICE_STRICT` is set
- `other`: Exit code of the command that failed
