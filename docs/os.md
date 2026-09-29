# os.sh

Utilities for getting information of OS/distro

> 🧭 Source: [src/os.sh](../src/os.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to get information of OS/distro, such as platform, distribution and architecture,
plus the host facts other modules would otherwise each detect for themselves: host and user names, processor count,
terminal size, and whether the script runs as root, in a container, under WSL, or on CI. Package manager detection
and dependency installation live in `pkg.sh`.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_VERSION_SCAN_REGEX`** | string | Pattern matching a version inside arbitrary text |

### 🚀 Highlights

- [`dybatpho::goos`](#dybatphogoos) — Get $GOOS compilation environment
- [`dybatpho::platform`](#dybatphoplatform) — Return the normalized host operating system name.
- [`dybatpho::is_macos`](#dybatphois_macos) — Return success when running on macOS.
- [`dybatpho::is_linux`](#dybatphois_linux) — Return success when running on Linux.
- [`dybatpho::is_windows`](#dybatphois_windows) — Return success when running on a Windows-compatible environment such as Cygwin, MSYS, or MinGW.
- [`dybatpho::command_path`](#dybatphocommand_path) — Return the path of the first installed command.
- [`dybatpho::command_version`](#dybatphocommand_version) — Print the version a command reports. The command is asked with `--version`, `-version`, `version`, and `-V`, in that order, until one of them prints something a version can be read out of. Both output streams are read, because a good number of tools answer on standard error, and standard input is closed so that a command that would otherwise wait for input cannot hang the script. Detection is best effort: it reports what the command says about itself, which is not always what a package manager calls the same build.
- [`dybatpho::goarch`](#dybatphogoarch) — Get $GOARCH compilation environment
- [`dybatpho::hostname`](#dybatphohostname) — Print the host name of the machine. The answer is resolved once and cached for the lifetime of the shell, because it cannot change under a running script and every structured log event asks for it.
- [`dybatpho::user`](#dybatphouser) — Print the name of the user the script runs as. This is the effective user, so a script under `sudo` reports `root` rather than the account that called it.
- [`dybatpho::is_root`](#dybatphois_root) — Return success when the script runs as the superuser.
- [`dybatpho::kernel_version`](#dybatphokernel_version) — Print the kernel release of the host.
- [`dybatpho::cpu_count`](#dybatphocpu_count) — Print how many processors the host can run work on. The count is reported rather than defaulted, so that a caller decides for itself what to do on a host that cannot answer.
- [`dybatpho::is_tty`](#dybatphois_tty) — Return success when a standard stream is attached to a terminal.
- [`dybatpho::terminal_width`](#dybatphoterminal_width) — Print the width of the terminal in columns. `COLUMNS` is trusted first, because a caller that sets it is deliberately asking for a width, and `tput` is only asked when a terminal is actually attached.
- [`dybatpho::terminal_height`](#dybatphoterminal_height) — Print the height of the terminal in lines.
- [`__dybatpho_os_terminal_size`](#__dybatpho_os_terminal_size) — Resolve one terminal dimension from the environment, `tput`, or a fallback, in that order.
- [`dybatpho::os_release`](#dybatphoos_release) — Print one field of the host's `os-release` file.
- [`dybatpho::distro`](#dybatphodistro) — Print the distribution the host runs. macOS has no `os-release`, so it answers `macos`; a Linux host answers with the `ID` field, such as `ubuntu`, `debian`, `arch`, or `alpine`.
- [`dybatpho::distro_version`](#dybatphodistro_version) — Print the version of the distribution the host runs.
- [`dybatpho::is_container`](#dybatphois_container) — Return success when the script runs inside a container.
- [`dybatpho::is_wsl`](#dybatphois_wsl) — Return success when the script runs under the Windows Subsystem for Linux.
- [`dybatpho::is_ci`](#dybatphois_ci) — Return success when the script runs on a continuous integration service. `CI` decides whenever it is set, in either direction. Every service sets it, and it is also the one variable a caller can set themselves, so `CI=false` turns the detection off even on a runner that advertises itself by name. The service-specific variables are consulted only when `CI` is unset or empty, which is the case they are there for.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::distro`

- Match on `ID_LIKE` through `dybatpho::os_release` when a whole family should be treated alike, because a derivative such as Linux Mint reports its own `ID`

<a id="reference"></a>
## 📚 Reference

### `dybatpho::goos`

Get $GOOS compilation environment

_Function has no arguments._

**📤 Output on stdout**

- Return $GOOS value https://go.dev/doc/install/source#environment


---

### `dybatpho::platform`

Return the normalized host operating system name.

_Function has no arguments._

**📤 Output on stdout**

- `linux`, `darwin`, `windows`, `android`, or the normalized uname name


---

### `dybatpho::is_macos`

Return success when running on macOS.

_Function has no arguments._


---

### `dybatpho::is_linux`

Return success when running on Linux.

_Function has no arguments._


---

### `dybatpho::is_windows`

Return success when running on a Windows-compatible environment
such as Cygwin, MSYS, or MinGW.

_Function has no arguments._


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

### `dybatpho::command_version`

Print the version a command reports.
The command is asked with `--version`, `-version`, `version`, and `-V`, in
that order, until one of them prints something a version can be read out of.
Both output streams are read, because a good number of tools answer on
standard error, and standard input is closed so that a command that would
otherwise wait for input cannot hang the script.

Detection is best effort: it reports what the command says about itself,
which is not always what a package manager calls the same build.

**🧪 Example**

```bash
dybatpho::command_version git   # 2.43.0
dybatpho::command_version tar   # 1.35

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command to ask |

**📤 Output on stdout**

- The version as the command writes it, without a leading `v`

**🚦 Exit codes**

- `0`: A version was found
- `1`: The command is not installed, or none of the probes revealed a version

**🔗 See also**

- [- `dybatpho::semver_satisfies` - `dybatpho::require](#dybatphosemver_satisfies-dybatphorequire)


---

### `dybatpho::goarch`

Get $GOARCH compilation environment

_Function has no arguments._

**📤 Output on stdout**

- Return $GOOS value https://go.dev/docs/install/source#environment


---

### `dybatpho::hostname`

Print the host name of the machine.
The answer is resolved once and cached for the lifetime of the shell,
because it cannot change under a running script and every structured log
event asks for it.

**🧪 Example**

```bash
dybatpho::info "Deploying from $(dybatpho::hostname)"

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_HOSTNAME`** | string | Host name to use instead of detecting one |

**📤 Output on stdout**

- Host name, or `unknown` when nothing can answer


---

### `dybatpho::user`

Print the name of the user the script runs as.
This is the effective user, so a script under `sudo` reports `root` rather
than the account that called it.

_Function has no arguments._

**📤 Output on stdout**

- User name, or `unknown` when nothing can answer


---

### `dybatpho::is_root`

Return success when the script runs as the superuser.

**🧪 Example**

```bash
dybatpho::is_root || dybatpho::die "Run this with sudo"

```

_Function has no arguments._

**🚦 Exit codes**

- `0`: The effective user is root
- `1`: The effective user is anybody else


---

### `dybatpho::kernel_version`

Print the kernel release of the host.

_Function has no arguments._

**📤 Output on stdout**

- Kernel release, such as `6.12.4-arch1-1`

**🚦 Exit codes**

- `1`: The kernel release cannot be determined


---

### `dybatpho::cpu_count`

Print how many processors the host can run work on.
The count is reported rather than defaulted, so that a caller decides for
itself what to do on a host that cannot answer.

**🧪 Example**

```bash
jobs="$(dybatpho::cpu_count || printf '4')"

```

_Function has no arguments._

**📤 Output on stdout**

- Number of online processors

**🚦 Exit codes**

- `1`: No available command reports a usable count


---

### `dybatpho::is_tty`

Return success when a standard stream is attached to a terminal.

**🧪 Example**

```bash
dybatpho::is_tty stdout && printf 'Colors are worth rendering\n'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Stream to test, `stdin`, `stdout`, `stderr`, or `0`/`1`/`2`, default is `stdout` |

**🚦 Exit codes**

- `0`: The stream is a terminal
- `1`: The stream is a file, a pipe, or anything else


---

### `dybatpho::terminal_width`

Print the width of the terminal in columns.
`COLUMNS` is trusted first, because a caller that sets it is deliberately
asking for a width, and `tput` is only asked when a terminal is actually
attached.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Optional width to use when there is no terminal, default is `80` |

**📤 Output on stdout**

- Terminal width in columns

**🚦 Exit codes**

- `1`: The fallback is not a positive integer


---

### `dybatpho::terminal_height`

Print the height of the terminal in lines.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Optional height to use when there is no terminal, default is `24` |

**📤 Output on stdout**

- Terminal height in lines

**🚦 Exit codes**

- `1`: The fallback is not a positive integer


---

### `__dybatpho_os_terminal_size`

Resolve one terminal dimension from the environment, `tput`, or a
fallback, in that order.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | `tput` capability, `cols` or `lines` |
| `$2` | string | Value of the environment variable that describes the dimension |
| `$3` | number | Fallback used when neither answers |

**📤 Output on stdout**

- The dimension

**🚦 Exit codes**

- `1`: The fallback is not a positive integer


---

### `dybatpho::os_release`

Print one field of the host's `os-release` file.

**🧪 Example**

```bash
dybatpho::os_release PRETTY_NAME

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field name, such as `ID`, `ID_LIKE`, or `VERSION_ID` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_OS_RELEASE`** | string | Path of the `os-release` file to read instead of the standard locations |

**📤 Output on stdout**

- Field value, with the quoting of the file removed

**🚦 Exit codes**

- `1`: There is no `os-release` file, or it has no such field


---

### `dybatpho::distro`

Print the distribution the host runs.
macOS has no `os-release`, so it answers `macos`; a Linux host answers with
the `ID` field, such as `ubuntu`, `debian`, `arch`, or `alpine`.

**🧪 Example**

```bash
case "$(dybatpho::distro)" in
  ubuntu | debian) dybatpho::info "Using apt" ;;
esac

```

_Function has no arguments._

**📤 Output on stdout**

- Distribution identifier, falling back to the normalized platform name


---

### `dybatpho::distro_version`

Print the version of the distribution the host runs.

_Function has no arguments._

**📤 Output on stdout**

- Distribution version, such as `24.04` or `15.1`

**🚦 Exit codes**

- `1`: The version cannot be determined, as on a rolling release that publishes none


---

### `dybatpho::is_container`

Return success when the script runs inside a container.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Docker, Podman, Kubernetes, or LXC owns this process
- `1`: The script runs on the host


---

### `dybatpho::is_wsl`

Return success when the script runs under the Windows Subsystem
for Linux.

_Function has no arguments._

**🚦 Exit codes**

- `0`: The host is WSL
- `1`: The host is anything else


---

### `dybatpho::is_ci`

Return success when the script runs on a continuous integration
service.
`CI` decides whenever it is set, in either direction. Every service sets it,
and it is also the one variable a caller can set themselves, so `CI=false`
turns the detection off even on a runner that advertises itself by name.
The service-specific variables are consulted only when `CI` is unset or
empty, which is the case they are there for.

**🧪 Examples**

```bash
dybatpho::is_ci && export DYBATPHO_FORCE=true

```

```bash
# Run a CI-aware script as if it were a workstation.
CI=false ./deploy.sh

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`CI`** | string | Set to a false value to say the script is not on CI, whatever else the environment advertises |

**🚦 Exit codes**

- `0`: `CI` holds a value other than `false`, `0`, or `no`; or `CI` is unset and a service names itself
- `1`: `CI` holds a false value, or nothing in the environment names a CI service
