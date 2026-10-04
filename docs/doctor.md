# doctor.sh

Utilities for checking that the environment can run what a script loaded

> 🧭 Source: [src/doctor.sh](../src/doctor.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module answers the question a user asks after a script fails with
`yq isn't installed` on line 400: what else is missing? A dybatpho module
only calls an external tool when the caller reaches the function that needs
it, so a missing dependency surfaces halfway through the work instead of at
the start.

`dybatpho::doctor` reports the Bash version, the library version, and every
external command the loaded modules can call, marking each one found or
missing. It reads as a report rather than a failure, so a user can run it
before the real script and fix everything at once.

Dependencies are declared per module, split in two:

- **required** — the module's main functions cannot work without it, such as
  `curl` for `network`;
- **optional** — only part of the module needs it, such as `zstd` for
  `archive` or `gpg` for signing a release.

A dependency written as `a|b` is satisfied by any one of the alternatives:
`file` hashes with whichever of `sha256sum`, `shasum`, or `openssl` exists.

A dependency may also name a version, as in `yq>=4`, using the range syntax
of `dybatpho::semver_satisfies` minus the spaces, which separate one spec
from the next here. Being installed is then not enough: the wrong major
release of a tool is its own kind of missing, and `yq` is the example that
prompted this, since the Go `yq` this library calls and the Python program
of the same name share nothing but a name.

A dependency is reported as one of four statuses:

- **ok** — installed, and new enough when a version was asked for;
- **missing** — no alternative is installed;
- **outdated** — installed, but the version does not satisfy the constraint;
- **unknown** — installed, but the version could not be read.

Only **required** dependencies that are missing or outdated make
`dybatpho::doctor` fail. An optional entry is information rather than a
problem, and so is `unknown`: a probe that could not read a version has not
shown that anything is wrong.

The report also walks the module dependency graph with
`dybatpho::array_toposort`, the same edges the loader follows. An explicit
`--modules` list is widened to every module it pulls in, in load order, so
the tools a dependency needs are reported too. An edge naming a module the
registry does not know fails the report, because the loader would stop on
it; a cycle is only noted, because the loader allows one.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_BASH_MINIMUM`** | string | Lowest Bash version the library supports |
| **`DYBATPHO_DOCTOR_REQUIRED`** | array | Required external commands per module |
| **`DYBATPHO_DOCTOR_OPTIONAL`** | array | Optional external commands per module |

### 🚀 Highlights

- [`dybatpho::doctor_requirements`](#dybatphodoctor_requirements) — Print the external commands a module can call.
- [`dybatpho::doctor_bash_supported`](#dybatphodoctor_bash_supported) — Return success when the running Bash is new enough for the library.
- [`dybatpho::doctor`](#dybatphodoctor) — Report the environment the loaded modules need, and what is missing.

<a id="see-also"></a>
## 🔗 See also

- [example/doctor_ops.sh](../example/doctor_ops.sh)
- [scripts/bundle.sh](../scripts/bundle.sh)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::doctor_requirements`

Print the external commands a module can call.

**🧪 Example**

```bash
dybatpho::doctor_requirements archive required

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Module name |
| `$2` | string | Kind, one of `all` (default), `required`, or `optional` |

**📤 Output on stdout**

- One dependency spec per line, required specs first

**🚦 Exit codes**

- `0`: Print the dependencies, including nothing for a module that has none
- `1`: Stop the script when the module is unknown or the kind is invalid


---

### `dybatpho::doctor_bash_supported`

Return success when the running Bash is new enough for the library.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Bash is at least `DYBATPHO_BASH_MINIMUM`
- `1`: Bash is older than the supported minimum


---

### `dybatpho::doctor`

Report the environment the loaded modules need, and what is missing.

**🧪 Example**

```bash
dybatpho::doctor              # the modules this shell loaded
dybatpho::doctor --all        # every module in the registry
dybatpho::doctor --modules "json git" --json

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Options: `--all`, `--modules <list>`, `--json`, `--quiet` |

**📤 Output on stdout**

- The report, as aligned text or as one JSON object with `--json`

**🚦 Exit codes**

- `0`: Every required dependency is installed and Bash is supported
- `1`: A required dependency is missing, Bash is too old, or an option is invalid
