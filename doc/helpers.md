# helpers.sh

Utilities for common shell-script helper patterns.

> 🧭 Source: [src/helpers.sh](../src/helpers.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`src/helpers.sh` groups together the small building blocks that many other
modules rely on:


- validating function arguments
- checking environment and tool dependencies
- testing common conditions
- checking several commands or env vars at once
- choosing the first usable value from fallbacks
- assigning default env values
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
- [`dybatpho::command_exists_all`](#dybatphocommand_exists_all) — Return success when all listed commands are available.
- [`dybatpho::is`](#dybatphois) — Check whether a value matches a supported shell-oriented condition.
- [`dybatpho::coalesce`](#dybatphocoalesce) — Print the first non-empty value from a list of fallbacks.
- [`dybatpho::coalesce_cmd`](#dybatphocoalesce_cmd) — Print the first available command from a list of candidates.
- [`dybatpho::default_env`](#dybatphodefault_env) — Assign and export a default value for an environment variable when it is empty.
- [`dybatpho::require_envs_any`](#dybatphorequire_envs_any) — Ensure that at least one of the listed environment variables is set.
- [`dybatpho::assert`](#dybatphoassert) — Evaluate a shell condition string and stop with a message when it fails.
- [`dybatpho::retry`](#dybatphoretry) — Retry a shell command with escalating delays until it succeeds or retries are exhausted.
- [`dybatpho::retry_until`](#dybatphoretry_until) — Retry a shell command until it succeeds or the retry budget is exhausted, using a fixed delay.
- [`dybatpho::breakpoint`](#dybatphobreakpoint) — Open an interactive breakpoint for debugging a running script.

<a id="usage"></a>
## 🚀 Usage

### When to use this module


Use `helpers.sh` when you want to:


- make shell functions fail fast on bad input
- avoid repeating `command -v`, `[[ -f ... ]]`, `[[ -d ... ]]`, and similar checks
- validate that any or all required commands and env vars are present
- choose the first non-empty value from environment, defaults, or arguments
- assign fallback defaults into environment variables
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


#### Pick the first configured value


```bash
api_host="$(dybatpho::coalesce "${API_HOST:-}" "${FALLBACK_HOST:-}" "http://localhost:8080")"
```


#### Pick the first available command


```bash
json_tool="$(dybatpho::coalesce_cmd jq yq python3)"
```


#### Add an optional breakpoint


```bash
dybatpho::is true "${DEBUG_BREAK:-false}" && dybatpho::breakpoint
```

<a id="see-also"></a>
## 🔗 See also

- [example/process_ops.sh](../example/process_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Combine `dybatpho::expect_envs` and `dybatpho::require` near the top of entrypoint scripts to fail fast on missing configuration or dependencies.

### `dybatpho::expect_args`

- Prefer calling this at the top of reusable functions instead of manually unpacking `$@`

### `dybatpho::require`

- Prefer this over repeating inline `command -v ... || exit` checks throughout a script

### `dybatpho::is`

- Use this helper to keep calling code readable instead of scattering shell test syntax across the script

### `dybatpho::assert`

- The assertion command is executed with `eval`

### `dybatpho::retry`

- The command is executed with `eval`, so pass it as one shell command string
- Pass a short description when the raw command is noisy so retry logs stay readable

### `dybatpho::retry_until`

- The command is executed with `eval`, so pass it as one shell command string

### `dybatpho::breakpoint`

- This helper is intended for interactive local debugging, not unattended CI or production runs

<a id="reference"></a>
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

### `dybatpho::command_exists_all`

Return success when all listed commands are available.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Commands to check |

**🚦 Exit codes**

- `0`: Every command exists
- `1`: At least one command is missing


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

### `dybatpho::coalesce`

Print the first non-empty value from a list of fallbacks.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Candidate values in priority order |

**📤 Output on stdout**

- First non-empty value

**🚦 Exit codes**

- `0`: A non-empty value is found
- `1`: No values are provided or all values are empty


---

### `dybatpho::coalesce_cmd`

Print the first available command from a list of candidates.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Candidate command names in priority order |

**📤 Output on stdout**

- First available command name

**🚦 Exit codes**

- `0`: An available command is found
- `1`: No commands are available


---

### `dybatpho::default_env`

Assign and export a default value for an environment variable when it is empty.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Environment variable name |
| `$2` | string | Default value |

**📤 Output on stdout**

- Effective value after applying the default


---

### `dybatpho::require_envs_any`

Ensure that at least one of the listed environment variables is set.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Environment variables to check |

**🚦 Exit codes**

- `0`: At least one environment variable is set
- `1`: None of the environment variables are set


---

### `dybatpho::assert`

Evaluate a shell condition string and stop with a message when it fails.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Shell condition or command string to evaluate |
| `$2` | string | Optional failure message |

**🚦 Exit codes**

- `0`: The assertion condition succeeds
- `1`: The assertion condition fails


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

### `dybatpho::retry_until`

Retry a shell command until it succeeds or the retry budget is exhausted, using a fixed delay.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Number of retries |
| `$2` | number | Delay in seconds between attempts |
| `$3` | string | Shell command string to run |
| `$4` | string | Optional short description for retry logs |

**🚦 Exit codes**

- `0`: The command eventually succeeds
- `1`: The command never succeeds and returns its final exit code


---

### `dybatpho::breakpoint`

Open an interactive breakpoint for debugging a running script.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_REPL_HISTORY_FILE`** | string | Override where REPL history is persisted between breakpoint sessions |

