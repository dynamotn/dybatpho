# service.sh

Utilities for enabling, controlling and installing services

> 🧭 Source: [src/service.sh](../src/service.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Reference](#reference)

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
