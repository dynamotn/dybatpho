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
- asking the library about itself

That last one is `dybatpho::provides`, `dybatpho::describe` and
`dybatpho::function_list`. The library documents itself in `docs/`, which
answers the question while you are reading; these answer it from the
running shell, where the question actually comes up. They ask Bash rather
than the filesystem: `declare -F` under `extdebug` reports the file and line
a function was defined at, and the documentation comment is sitting just
above that line in the source that was loaded. They live here, in a core
module, because a helper you have to remember to load is one you will not
reach for at a prompt.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RETRY_BASE_DELAY`** | number | First retry delay in seconds (default `2`) |
| **`DYBATPHO_RETRY_MAX_DELAY`** | number | Longest a single retry waits (default `30`) |
| **`DYBATPHO_RETRY_JITTER`** | bool | Add up to one base delay of random jitter (default `false`) |
| **`DYBATPHO_REPL_HISTORY_FILE`** | string | History file used by `dybatpho::breakpoint` |

### 🚀 Highlights

- [`dybatpho::expect_args`](#dybatphoexpect_args) — Validate function arguments and assign them into named local variables.
- [`dybatpho::expect_ref`](#dybatphoexpect_ref) — Check that a caller-supplied variable name can safely be bound to a nameref, and stop the script when it cannot. A function that writes its answer into a variable the caller names does it with `local -n`, and that has a failure mode with no error in it. When the name the caller passes is also the name of one of the function's own local variables, the nameref resolves to *that* local instead of to the caller's variable, and every write lands somewhere the caller will never look. Bash warns about the narrow case where the name collides with the nameref itself — `circular name reference`, after which the writes are dropped — and says nothing at all about the wider case where it collides with any other local. That second case was real: `dybatpho::array_sort __sort_values` used to return successfully and sort nothing. The library closes this by reserving a prefix. Every local in a function that takes a variable name is called `__dybatpho_...`, and this check refuses a caller-supplied name in that namespace. A collision is then either impossible or a loud error, never a silent wrong answer.
- [`dybatpho::still_has_args`](#dybatphostill_has_args) — Check whether at least one more positional argument remains after the current one. This helper is useful while manually parsing a shifting argument list.
- [`dybatpho::expect_envs`](#dybatphoexpect_envs) — Ensure that required environment variables are set.
- [`dybatpho::require`](#dybatphorequire) — Ensure that a required command is installed, and new enough. With a version range, the command is asked what version it is through `dybatpho::command_version`, the answer is normalized by `dybatpho::semver_coerce`, and the result is matched with `dybatpho::semver_satisfies`. The range is written the way that function documents it: `>=1.6`, `^4`, `>=1.2 <2`, `1.2.x`, or alternatives with `||`. The range has to open with one of `>`, `<`, `=`, `^`, or `~`. A bare `4` is a valid range on its own elsewhere, but this argument has meant an exit code since before ranges existed here, and no amount of cleverness makes `require jq 3` mean both things at once. Matching a version needs the optional `semver` module. Rather than let a range pass unchecked in a script that did not load it, this stops with a message naming what to load: a requirement that is silently not enforced is worse than one that was never written. A command whose version cannot be read is also a failure, for the same reason. `dybatpho::doctor` treats that case as a report rather than a failure, because a report is allowed to say "I could not tell".
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
- [`dybatpho::provides`](#dybatphoprovides) — Print the module that defines a function. The answer comes from where Bash says the function was defined, so it describes the code that is actually loaded rather than what a directory listing suggests. Functions the bootstrap defines report `init`.
- [`dybatpho::describe`](#dybatphodescribe) — Print the documentation comment of a function. The library documents itself in `docs/`, which answers the question when you are reading it. At a prompt, mid-script, the question is what a function takes and what it returns, and the answer is in a browser tab. This reads it out of the source the shell actually loaded, so it describes the code that will run, and it is there whether or not `docs/` was ever generated. The banner rules and any `shellcheck` directive between the comment and the function are dropped, one `#` and the space after it are taken off each line, and the `@description` marker is removed from the prose it introduces. Everything else, `@arg` and `@exitcode` tags included, is printed as the source wrote it.
- [`dybatpho::function_list`](#dybatphofunction_list) — Print the public functions this shell has loaded. Without an argument this is the whole loaded API; with one it is what a single module exports, which is the list to skim when reaching for a module for the first time. Only `dybatpho::` names are listed. The `__dybatpho_` helpers are internal, and `declare -F` is right there for anyone debugging one.

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

- Combine `dybatpho::expect_envs` and `dybatpho::require` near the top of entrypoint scripts to fail fast on missing configuration or dependencies. The `dybatpho::is` family and the lookups below are questions, not work: a caller tests them, so `set -e` is not meant to reach inside.

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
- Turn on `DYBATPHO_RETRY_JITTER` when several machines retry the same dependency, so they do not all come back at the same instant
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

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Variable names, then `--`, then the arguments to bind |

**🚦 Exit codes**

- `1`: Stop the script if the specification is invalid or required arguments are missing
- `0`: Assign arguments to the requested variable names and return successfully


---

### `dybatpho::expect_ref`

Check that a caller-supplied variable name can safely be bound to
a nameref, and stop the script when it cannot.

A function that writes its answer into a variable the caller names does it
with `local -n`, and that has a failure mode with no error in it. When the
name the caller passes is also the name of one of the function's own local
variables, the nameref resolves to *that* local instead of to the caller's
variable, and every write lands somewhere the caller will never look. Bash
warns about the narrow case where the name collides with the nameref itself
— `circular name reference`, after which the writes are dropped — and says
nothing at all about the wider case where it collides with any other local.
That second case was real: `dybatpho::array_sort __sort_values` used to
return successfully and sort nothing.

The library closes this by reserving a prefix. Every local in a function
that takes a variable name is called `__dybatpho_...`, and this check
refuses a caller-supplied name in that namespace. A collision is then either
impossible or a loud error, never a silent wrong answer.

**🧪 Example**

```bash
function my_helper {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  local -n __dybatpho_out="${target}"
  __dybatpho_out="value"
}

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name supplied by the caller |

**🚦 Exit codes**

- `0`: The name is safe to bind
- `1`: Stop the script when the name is not an identifier, or is reserved


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

_Function has no arguments._

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

Ensure that a required command is installed, and new enough.
With a version range, the command is asked what version it is through
`dybatpho::command_version`, the answer is normalized by
`dybatpho::semver_coerce`, and the result is matched with
`dybatpho::semver_satisfies`. The range is written the way that function
documents it: `>=1.6`, `^4`, `>=1.2 <2`, `1.2.x`, or alternatives with `||`.

The range has to open with one of `>`, `<`, `=`, `^`, or `~`. A bare `4`
is a valid range on its own elsewhere, but this argument has meant an exit
code since before ranges existed here, and no amount of cleverness makes
`require jq 3` mean both things at once.

Matching a version needs the optional `semver` module. Rather than let a
range pass unchecked in a script that did not load it, this stops with a
message naming what to load: a requirement that is silently not enforced is
worse than one that was never written.

A command whose version cannot be read is also a failure, for the same
reason. `dybatpho::doctor` treats that case as a report rather than a
failure, because a report is allowed to say "I could not tell".

**🧪 Example**

```bash
dybatpho::require git
dybatpho::require jq '>=1.6'
dybatpho::require yq '^4' 3

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command that must be available |
| `$2` | string | Version range opening with an operator, or the exit code |
| `$3` | number | Exit code when a range was given (default 127) |

**🚦 Exit codes**

- `127`: Stop script if command isn't installed, or is outside the range
- `0`: The command is available and satisfies the range
- `other`: Exit code given as an argument, instead of 127

**🔗 See also**

- [- `dybatpho::command_version` - `dybatpho::semver_coerce` - `dybatpho::semver_satisfies](#dybatphocommand_version-dybatphosemver_coerce-dybatphosemver_satisfies)


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

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RETRY_BASE_DELAY`** | number | First retry delay in seconds |
| **`DYBATPHO_RETRY_MAX_DELAY`** | number | Longest a single retry waits |
| **`DYBATPHO_RETRY_JITTER`** | bool | Add up to one base delay of random jitter |

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


---

### `dybatpho::provides`

Print the module that defines a function.
The answer comes from where Bash says the function was defined, so it
describes the code that is actually loaded rather than what a directory
listing suggests. Functions the bootstrap defines report `init`.

**🧪 Example**

```bash
dybatpho::provides semver_valid            # semver
dybatpho::provides dybatpho::cache_run     # cache
dybatpho::provides --path cache_run        # /path/to/src/cache.sh:245

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | `--path` to print `file:line` instead of the module name |
| `$@` | string | Function name, with or without the `dybatpho::` prefix |

**📝 Notes**

- A bundle holds every module in one file, so only `--path` can answer there, and it still points at the right line

**📤 Output on stdout**

- The module name, or `file:line` with `--path`

**🚦 Exit codes**

- `1`: The function is not defined in this shell, or it came from a bundle, where there are no module sources to name

**🔗 See also**

- [- `dybatpho::describe` - `dybatpho::function_list](#dybatphodescribe-dybatphofunction_list)


---

### `dybatpho::describe`

Print the documentation comment of a function.
The library documents itself in `docs/`, which answers the question when you
are reading it. At a prompt, mid-script, the question is what a function
takes and what it returns, and the answer is in a browser tab. This reads it
out of the source the shell actually loaded, so it describes the code that
will run, and it is there whether or not `docs/` was ever generated.

The banner rules and any `shellcheck` directive between the comment and the
function are dropped, one `#` and the space after it are taken off each
line, and the `@description` marker is removed from the prose it introduces.
Everything else, `@arg` and `@exitcode` tags included, is printed as the
source wrote it.

**🧪 Example**

```bash
dybatpho::describe cache_run
dybatpho::describe dybatpho::semver_satisfies

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Function name, with or without the `dybatpho::` prefix |

**📤 Output on stdout**

- A heading naming the function and where it came from, then the comment

**🚦 Exit codes**

- `1`: The function is not defined in this shell, or its source is no longer readable

**🔗 See also**

- [- `dybatpho::provides](#dybatphoprovides)


---

### `dybatpho::function_list`

Print the public functions this shell has loaded.
Without an argument this is the whole loaded API; with one it is what a
single module exports, which is the list to skim when reaching for a module
for the first time.

Only `dybatpho::` names are listed. The `__dybatpho_` helpers are internal,
and `declare -F` is right there for anyone debugging one.

**🧪 Example**

```bash
dybatpho::function_list              # everything loaded
dybatpho::function_list cache        # just that module
dybatpho::function_list | wc -l

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional module name to limit the list to |

**📤 Output on stdout**

- One function name per line, in alphabetical order

**🚦 Exit codes**

- `1`: Stop the script when the named module is not loaded, or when the library came from a bundle, where no function can be attributed to a module

**🔗 See also**

- [- `dybatpho::module_list` - `dybatpho::provides](#dybatphomodule_list-dybatphoprovides)
