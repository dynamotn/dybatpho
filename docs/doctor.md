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

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_BASH_MINIMUM`** | string | Lowest Bash version the library supports |
| **`DYBATPHO_DOCTOR_REQUIRED`** | array | Required external commands per module |
| **`DYBATPHO_DOCTOR_OPTIONAL`** | array | Optional external commands per module |

### 🚀 Highlights

- [`__dybatpho_doctor_rank`](#__dybatpho_doctor_rank) — Rank a status, so that the least satisfying alternative of a spec is not the one that gets reported. When no alternative satisfies the spec, the most specific complaint is the useful one: `outdated` names a version to upgrade, `unknown` names a command that is at least installed, and `missing` says the least.
- [`__dybatpho_doctor_split`](#__dybatpho_doctor_split) — Split a dependency alternative into its command and version range. A range here cannot contain a space, because the maps separate one spec from the next with one. `^4` says what `>=4 <5` would have said.
- [`__dybatpho_doctor_resolve`](#__dybatpho_doctor_resolve) — Decide whether a dependency spec is satisfied, and how. A spec is one alternative, or several separated by `|` when any one of them will do. An alternative may carry a version constraint, as in `yq>=4`, in which case being installed is not enough on its own. Only an alternative that carries a constraint is asked for its version. A report has no business running every tool on the host to print a table, and the version of a dependency nothing has an opinion about is not news.
- [`dybatpho::doctor_requirements`](#dybatphodoctor_requirements) — Print the external commands a module can call.
- [`dybatpho::doctor_bash_supported`](#dybatphodoctor_bash_supported) — Return success when the running Bash is new enough for the library.
- [`__dybatpho_doctor_scope`](#__dybatpho_doctor_scope) — Resolve the module list a report covers.
- [`__dybatpho_doctor_json_escape`](#__dybatpho_doctor_json_escape) — Escape a value for use inside a JSON string. The report is written without `jq`, because a diagnostic that needs a tool the user may be missing is of no use.
- [`__dybatpho_doctor_rows`](#__dybatpho_doctor_rows) — Collect every dependency row a scope produces. A row is `module<TAB>spec<TAB>kind<TAB>status<TAB>path<TAB>version`, which keeps the text and JSON renderers reading the same data.
- [`__dybatpho_doctor_report_text`](#__dybatpho_doctor_report_text) — Print the report as aligned text.
- [`__dybatpho_doctor_report_json`](#__dybatpho_doctor_report_json) — Print the report as a single JSON object.
- [`dybatpho::doctor`](#dybatphodoctor) — Report the environment the loaded modules need, and what is missing.

<a id="see-also"></a>
## 🔗 See also

- [example/doctor_ops.sh](../example/doctor_ops.sh)
- [scripts/bundle.sh](../scripts/bundle.sh)

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_doctor_rank`

Rank a status, so that the least satisfying alternative of a spec
is not the one that gets reported.
When no alternative satisfies the spec, the most specific complaint is the
useful one: `outdated` names a version to upgrade, `unknown` names a command
that is at least installed, and `missing` says the least.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Status |

**📤 Output on stdout**

- The rank, higher being more worth reporting


---

### `__dybatpho_doctor_split`

Split a dependency alternative into its command and version range.
A range here cannot contain a space, because the maps separate one spec from
the next with one. `^4` says what `>=4 <5` would have said.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | One alternative, such as `yq` or `yq>=4` |

**📤 Output on stdout**

- Two lines: the command name, and the range or an empty line


---

### `__dybatpho_doctor_resolve`

Decide whether a dependency spec is satisfied, and how.
A spec is one alternative, or several separated by `|` when any one of them
will do. An alternative may carry a version constraint, as in `yq>=4`, in
which case being installed is not enough on its own.

Only an alternative that carries a constraint is asked for its version. A
report has no business running every tool on the host to print a table, and
the version of a dependency nothing has an opinion about is not news.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Dependency spec, such as `curl`, `sha256sum\|shasum`, or `yq>=4` |

**📤 Output on stdout**

- One line of `status<TAB>path<TAB>version`, where status is `ok`,
  `outdated`, `unknown`, or `missing`

**🚦 Exit codes**

- `0`: An alternative is installed and satisfies its constraint
- `1`: No alternative does


---

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

**🚦 Exit codes**

- `0`: Bash is at least `DYBATPHO_BASH_MINIMUM`
- `1`: Bash is older than the supported minimum


---

### `__dybatpho_doctor_scope`

Resolve the module list a report covers.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable that receives the module names |
| `$2` | string | Scope, either `loaded`, `all`, or an explicit module list |

**🧩 Variable sets**

- **`The`** (named): array, to module names in registry or load order

**🚦 Exit codes**

- `1`: Stop the script when an explicitly named module is unknown


---

### `__dybatpho_doctor_json_escape`

Escape a value for use inside a JSON string.
The report is written without `jq`, because a diagnostic that needs a tool
the user may be missing is of no use.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Raw value |

**📤 Output on stdout**

- The value with the characters JSON reserves escaped


---

### `__dybatpho_doctor_rows`

Collect every dependency row a scope produces.
A row is `module<TAB>spec<TAB>kind<TAB>status<TAB>path<TAB>version`, which
keeps the text and JSON renderers reading the same data.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable that receives the rows |
| `$@` | string | Module names to inspect |

**🧩 Variable sets**

- **`The`** (named): array, to one row per dependency


---

### `__dybatpho_doctor_report_text`

Print the report as aligned text.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable holding the rows |
| `$@` | string | Module names covered by the report |

**📤 Output on stdout**

- The environment summary, the dependency table, and a closing summary


---

### `__dybatpho_doctor_report_json`

Print the report as a single JSON object.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable holding the rows |
| `$@` | string | Module names covered by the report |

**📤 Output on stdout**

- One JSON object describing the environment and every dependency


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
