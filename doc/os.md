# os.sh

Utilities for working with OS/distro package manager or getting information of OS/distro

> 🧭 Source: [src/os.sh](../src/os.sh)
>
> Jump to: [Overview](#overview) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to get information of OS/distro or work with package manager

### 🚀 Highlights

- [`dybatpho::goos`](#dybatphogoos) — Get $GOOS compilation environment
- [`dybatpho::platform`](#dybatphoplatform) — Return the normalized host operating system name.
- [`dybatpho::is_macos`](#dybatphois_macos) — Return success when running on macOS.
- [`dybatpho::is_linux`](#dybatphois_linux) — Return success when running on Linux.
- [`dybatpho::command_path`](#dybatphocommand_path) — Return the path of the first installed command.
- [`dybatpho::goarch`](#dybatphogoarch) — Get $GOARCH compilation environment

<a id="reference"></a>
## 📚 Reference

### `dybatpho::goos`

Get $GOOS compilation environment

**📤 Output on stdout**

- Return $GOOS value https://go.dev/doc/install/source#environment


---

### `dybatpho::platform`

Return the normalized host operating system name.

**📤 Output on stdout**

- `linux`, `darwin`, `windows`, `android`, or the normalized uname name


---

### `dybatpho::is_macos`

Return success when running on macOS.


---

### `dybatpho::is_linux`

Return success when running on Linux.


---

### `dybatpho::command_path`

Return the path of the first installed command.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Commands to check |

**📤 Output on stdout**

- Path of the first available command

**🚦 Exit codes**

- `1`: None of the commands is installed


---

### `dybatpho::goarch`

Get $GOARCH compilation environment

**📤 Output on stdout**

- Return $GOOS value https://go.dev/doc/install/source#environment

