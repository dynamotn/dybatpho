# pkg.sh

Package manager detection and guarded dependency installation

> 🧭 Source: [src/pkg.sh](../src/pkg.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module answers three questions a portable installer script keeps
asking:

- which package manager does this machine use (`dybatpho::pkg_manager`);
- is a dependency already there (`dybatpho::pkg_installed`,
  `dybatpho::pkg_missing`);
- how do I install it here without surprising the user
  (`dybatpho::pkg_install`, `dybatpho::pkg_ensure`,
  `dybatpho::pkg_require`).

Six managers are supported: `apt`, `brew`, `apk`, `dnf`, `pacman`, and
`emerge`. Detection prefers the platform's native manager, so a Linux box
with Homebrew installed still reports its distribution manager, and
`DYBATPHO_PKG_MANAGER` overrides the detection outright.

Because the same dependency is named differently on every distribution, the
install helpers accept `<manager>:<package>` overrides: `fd` is `fd-find` on
Debian, `fd` everywhere else, and `dybatpho::pkg_require fd apt:fd-find`
says exactly that.

A manager flag that this module does not model - `--cask` for Homebrew,
`--no-cache` for `apk`, `--no-install-recommends` for `apt-get` - is passed
through with `--arg`, once per flag, and lands right before the package
names.

Nothing here changes the system without saying so first. Every mutating
function asks for confirmation unless `--force`/`DYBATPHO_FORCE` is set,
refuses rather than guessing in a non-interactive shell, and prints the
command instead of running it under `--dry-run` or `DRY_RUN`.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PKG_MANAGER`** | string | Force a package manager instead of detecting one |
| **`DYBATPHO_PKG_SUDO`** | string | `auto` elevates with sudo when not root, `true`/`false` override the detection |
| **`DYBATPHO_PKG_ASSUME_YES`** | bool | Set to `false` to drop the manager's non-interactive flags |

### 🚀 Highlights

- [`dybatpho::pkg_supported`](#dybatphopkg_supported) — Print every package manager this module supports.
- [`dybatpho::pkg_manager`](#dybatphopkg_manager) — Report the package manager of the current machine.
- [`dybatpho::pkg_manager_available`](#dybatphopkg_manager_available) — Return success when a package manager is usable on this machine.
- [`dybatpho::pkg_name`](#dybatphopkg_name) — Resolve a package name for the current manager from `<manager>:<package>` overrides.
- [`dybatpho::pkg_installed`](#dybatphopkg_installed) — Return success when a package is installed, according to the detected manager.
- [`dybatpho::pkg_missing`](#dybatphopkg_missing) — Print the packages that are not installed yet.
- [`dybatpho::pkg_install_command`](#dybatphopkg_install_command) — Print the command that would install the given packages, without running it.
- [`dybatpho::pkg_update`](#dybatphopkg_update) — Refresh the package index, after confirming the change.
- [`dybatpho::pkg_install`](#dybatphopkg_install) — Install packages with the detected manager, after confirming the change.
- [`dybatpho::pkg_ensure`](#dybatphopkg_ensure) — Install only the packages that are missing, and do nothing when they are all there.
- [`dybatpho::pkg_require`](#dybatphopkg_require) — Make sure a command is available, installing the package that provides it on this machine.

<a id="usage"></a>
## 🚀 Usage

### Report the machine's package manager

```bash
dybatpho::pkg_manager   # apt, brew, apk, dnf, pacman or emerge
```

### Install only what is missing, unattended

```bash
dybatpho::pkg_ensure --force curl jq
```

### Make sure a command exists, whatever the distribution calls it

```bash
dybatpho::pkg_require fd apt:fd-find emerge:sys-apps/fd
```

### Show what would happen without touching the system

```bash
dybatpho::pkg_install --dry-run ripgrep
```

### Pass a flag the manager understands but this module does not

```bash
dybatpho::pkg_install --force --arg --cask -- firefox
dybatpho::pkg_install --force --arg --no-cache --arg --no-interactive -- curl
```

<a id="see-also"></a>
## 🔗 See also

- [example/pkg_ops.sh](../example/pkg_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Run an installer with `--dry-run` first, then with `--force` from CI, and the same script covers both the review and the unattended run.

### `dybatpho::pkg_install`

- An `--arg` belongs to the install command alone: the `--update` refresh that may run before it is never given the extra arguments.

<a id="reference"></a>
## 📚 Reference

### `dybatpho::pkg_supported`

Print every package manager this module supports.

_Function has no arguments._

**📤 Output on stdout**

- One manager name per line, alphabetically


---

### `dybatpho::pkg_manager`

Report the package manager of the current machine.

**🧪 Example**

```bash
manager="$(dybatpho::pkg_manager)" || dybatpho::die "No supported package manager"

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_PKG_MANAGER`** | string | When set, this manager is reported without probing |

**📤 Output on stdout**

- `apt`, `brew`, `apk`, `dnf`, `pacman`, or `emerge`

**🚦 Exit codes**

- `0`: A supported manager is installed
- `1`: None of the supported managers is installed


---

### `dybatpho::pkg_manager_available`

Return success when a package manager is usable on this machine.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional manager name, default is the detected one |

**🚦 Exit codes**

- `0`: The manager is installed
- `1`: The manager is not installed, or nothing was detected


---

### `dybatpho::pkg_name`

Resolve a package name for the current manager from `<manager>:<package>` overrides.

**🧪 Example**

```bash
dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd   # fd-find on Debian

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Default package name, used when no override matches |
| `$@` | string | Optional `<manager>:<package>` overrides |

**📤 Output on stdout**

- The package name to install on this machine

**🚦 Exit codes**

- `0`: A name is printed
- `1`: No package manager was detected


---

### `dybatpho::pkg_installed`

Return success when a package is installed, according to the detected manager.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Package name |

**🚦 Exit codes**

- `0`: The package is installed
- `1`: The package is missing, or no package manager was detected


---

### `dybatpho::pkg_missing`

Print the packages that are not installed yet.

**🧪 Example**

```bash
mapfile -t missing < <(dybatpho::pkg_missing curl jq)

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Package names |

**📤 Output on stdout**

- One missing package per line, in the order they were given

**🚦 Exit codes**

- `0`: The check ran; empty output means nothing is missing
- `1`: No package manager was detected


---

### `dybatpho::pkg_install_command`

Print the command that would install the given packages, without running it.

**🧪 Examples**

```bash
dybatpho::pkg_install_command ripgrep   # sudo apt-get install -y ripgrep

```

```bash
dybatpho::pkg_install_command --arg --cask -- firefox   # brew install --cask firefox

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--arg`/`-a` to pass one extra argument to the manager, repeatable |
| `$@` | string | Package names, optionally after a `--` separator |

**📤 Output on stdout**

- The install command as a single quoted line

**🚦 Exit codes**

- `1`: No package manager was detected


---

### `dybatpho::pkg_update`

Refresh the package index, after confirming the change.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, `--dry-run`/`-n` to print the command instead, `--arg`/`-a` to pass one extra argument to the manager, repeatable |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the command instead of running it |

**🚦 Exit codes**

- `0`: The index was refreshed, or the command was printed
- `1`: The refresh is declined, the command failed, or no manager was detected


---

### `dybatpho::pkg_install`

Install packages with the detected manager, after confirming the change.

**🧪 Examples**

```bash
dybatpho::pkg_install --force curl jq

```

```bash
dybatpho::pkg_install --dry-run -- ripgrep

```

```bash
dybatpho::pkg_install --force --arg --cask -- firefox

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, `--dry-run`/`-n` to print the command instead, `--update`/`-u` to refresh the index first, `--arg`/`-a` to pass one extra argument to the manager, repeatable |
| `$@` | string | Packages, optionally after a `--` separator |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the command instead of running it |
| **`DYBATPHO_FORCE`** | bool | Approve the change without prompting |

**🚦 Exit codes**

- `0`: The packages were installed, or the command was printed
- `1`: The install is declined, the command failed, or no manager was detected


---

### `dybatpho::pkg_ensure`

Install only the packages that are missing, and do nothing when they are all there.

**🧪 Example**

```bash
dybatpho::pkg_ensure --force curl jq

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | The options of `dybatpho::pkg_install`, including `--arg`/`-a` |
| `$@` | string | Packages, optionally after a `--` separator |

**🚦 Exit codes**

- `0`: Every package is installed, was already installed, or the command was printed
- `1`: The install is declined, the command failed, or no manager was detected


---

### `dybatpho::pkg_require`

Make sure a command is available, installing the package that provides it on this machine.

**🧪 Example**

```bash
dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | The options of `dybatpho::pkg_install`, including `--arg`/`-a` |
| `$2` | string | Command that must be available, also the default package name |
| `$@` | string | Optional `<manager>:<package>` overrides |

**🚦 Exit codes**

- `0`: The command is available, or its package was installed
- `1`: The install is declined, the command failed, or the command is still missing afterwards
