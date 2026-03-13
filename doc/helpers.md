# helpers.sh

Utilities for common shell-script helper patterns.

> 🧭 Source: [src/helpers.sh](../src/helpers.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

## ✨ Overview

`src/helpers.sh` groups together the small building blocks that many other
modules rely on:


- validating function arguments
- checking environment and tool dependencies
- testing common conditions
- retrying flaky commands
- opening an interactive breakpoint

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_REPL_HISTORY_FILE`** | string | History file used by `dybatpho::breakpoint` |

### 🚀 Highlights

- [`dybatpho::expect_args`](#dybatphoexpect_args) — Validate function arguments and assign them into named local variables.
- [`dybatpho::still_has_args`](#dybatphostill_has_args) — Check whether at least one more positional argument remains after the current one. This helper is useful while manually parsing a shifting argument list.
- [`dybatpho::expect_envs`](#dybatphoexpect_envs) — Ensure that required environment variables are set.
- [`dybatpho::require`](#dybatphorequire) — Ensure that a required command is installed.
- [`dybatpho::is`](#dybatphois) — Check whether a value matches a supported shell-oriented condition.
- [`dybatpho::retry`](#dybatphoretry) — Retry a shell command with escalating delays until it succeeds or retries are exhausted.
- [`dybatpho::breakpoint`](#dybatphobreakpoint) — Open an interactive breakpoint for debugging a running script.

## 🚀 Usage

### When to use this module


Use `helpers.sh` when you want to:


- make shell functions fail fast on bad input
- avoid repeating `command -v`, `[[ -f ... ]]`, `[[ -d ... ]]`, and similar checks
- retry transient commands without rewriting loop logic
- inspect runtime state interactively while debugging a script


### Common patterns


#### Validate function input


```bash
function copy_file() {
  local src dst
  dybatpho::expect_args src dst -- "$@"
  cp "${src}" "${dst}"
}
```


#### Require environment + binary before running


```bash
dybatpho::expect_envs API_TOKEN
dybatpho::require curl
```


#### Guard conditions


```bash
if ! dybatpho::is file "${config_path}"; then
  dybatpho::die "Config file not found: ${config_path}"
fi
```


#### Retry transient network operations


```bash
dybatpho::retry 4 "curl -fsSL '${health_url}'" "service health check"
```


#### Add an optional breakpoint


```bash
dybatpho::is true "${DEBUG_BREAK:-false}" && dybatpho::breakpoint
```

## 🔗 See also

- [example/process_ops.sh](../example/process_ops.sh)

## 💡 Tips

- Combine `dybatpho::expect_envs` and `dybatpho::require` near the top of entrypoint scripts to fail fast on missing configuration or dependencies.

### `dybatpho::expect_args`

- Prefer calling this at the top of reusable functions instead of manually unpacking `$@`

### `dybatpho::require`

- Prefer this over repeating inline `command -v ... || exit` checks throughout a script

### `dybatpho::is`

- Use this helper to keep calling code readable instead of scattering shell test syntax across the script

### `dybatpho::retry`

- The command is executed with `eval`, so pass it as one shell command string
- Pass a short description when the raw command is noisy so retry logs stay readable

### `dybatpho::breakpoint`

- This helper is intended for interactive local debugging, not unattended CI or production runs

## 📚 Reference

### `dybatpho::expect_args`

Validate function arguments and assign them into named local variables.

**🧪 Example**

```bash
local arg1 arg2 .. argN
dybatpho::expect_args arg1 arg2 .. argN -- "$@"

```

**🚦 Exit codes**

- `1`: Stop the script if the specification is invalid or required arguments are missing
- `0`: Assign arguments to the requested variable names and return successfully


---

### `dybatpho::still_has_args`

Check whether at least one more positional argument remains after the current one.
This helper is useful while manually parsing a shifting argument list.

**🧪 Example**

```bash
while dybatpho::still_has_args "$@" && shift; do
  echo "Function has next argument is $1"
done
```

**🚦 Exit codes**

- `0`: Still has an argument
- `1`: No additional arguments remain


---

### `dybatpho::expect_envs`

Ensure that required environment variables are set.

**🧪 Example**

```bash
dybatpho::expect_envs ENV_VAR1 ENV_VAR2
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Environment variables to check |

**🚦 Exit codes**

- `1`: Stop the script if any variable is unset or empty


---

### `dybatpho::require`

Ensure that a required command is installed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command that must be available |
| `$2` | number | Exit code if not installed (default 127) |

**🚦 Exit codes**

- `127`: Stop script if command isn't installed
- `0`: The command is available
- `other`: Exit code if command isn't installed and second argument is set


---

### `dybatpho::is`

Check whether a value matches a supported shell-oriented condition.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Condition (command\|function\|file\|dir\|link\|exist\|readable\|writeable\|executable\|set\|empty\|number\|int\|true\|false) |
| `$2` | string | Value to test |

**🚦 Exit codes**

- `0`: If matched
- `1`: If not matched


---

### `dybatpho::retry`

Retry a shell command with escalating delays until it succeeds or retries are exhausted.

**🧪 Example**

```bash
dybatpho::retry 3 "curl -fsSL '${url}'" "health check"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Number of retries |
| `$2` | string | Shell command string to run |
| `$3` | string | Optional short description for retry logs |

**🚦 Exit codes**

- `0`: The command eventually succeeds
- `1`: The command never succeeds and returns 1 on the final attempt


---

### `dybatpho::breakpoint`

Open an interactive breakpoint for debugging a running script.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_REPL_HISTORY_FILE`** | string | Override where REPL history is persisted between breakpoint sessions |

