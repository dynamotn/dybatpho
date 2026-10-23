# init.sh

Initial script

> 🧭 Source: [init.sh](../init.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This script should be sourced before any of
the other scripts in this repo. Other scripts
make use of ${DYBATPHO_DIR} to find each other.

  Sourcing `init.sh` with no arguments loads the core modules only. A script
  names the modules it needs, and dybatpho resolves the dependencies for it:

  ```sh
  . dybatpho/init.sh --modules logging git semver   # positional form
  DYBATPHO_MODULES="logging git semver" . dybatpho/init.sh # environment form
  . dybatpho/init.sh --modules all                  # the whole library
  ```

  Every module set includes the core modules, and can be widened later with
  `dybatpho::load`.

  By default the bootstrap turns on strict mode in the sourcing shell —
  `set -euo pipefail`, `extglob`, and `inherit_errexit` on Bash 4.4+ — and
  leaves globbing alone: an unmatched pattern stays literal, as Bash does by
  default. `--no-strict` leaves every `set` and `shopt` option of the caller
  as it was:

  ```sh
  . dybatpho/init.sh --no-strict --modules logging
  ```

  Nothing is exported to child processes unless the script asks for it, with
  `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing or a call to
  `dybatpho::export_functions`. Sourcing never ends the calling shell: a
  failed bootstrap returns 1, and the caller decides what to do.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CORE_MODULES`** | string | Modules that call each other and are always loaded |
| **`DYBATPHO_OPTIONAL_MODULES`** | string | Modules that are only loaded when requested |
| **`DYBATPHO_LOADED_MODULES`** | string | Modules loaded so far, in load order |
| **`DYBATPHO_VERSION`** | string | Cached library version, see `dybatpho::version` |
| **`DYBATPHO_EXPORT_FUNCTIONS`** | bool | When true-like before sourcing, call `dybatpho::export_functions` once the modules are loaded, default is `false` |
| **`DYBATPHO_EXPORT_MODULES`** | string | Module set a child process loads through `BASH_ENV`, set by `dybatpho::export_functions` and kept current by `dybatpho::load` |
| **`DYBATPHO_EXPORT_BASH_ENV`** | string | The `BASH_ENV` in place before `dybatpho::export_functions`, sourced first by every child |

### 🚀 Highlights

- [`dybatpho::export_functions`](#dybatphoexport_functions) — Make the loaded library available to child Bash processes. Nothing crosses the process boundary by default: exporting every function made each child start several times slower, could push the environment past what `execve` accepts (`find -exec ... +` then fails with "environment too large"), and still left a child with public functions whose internal helpers and module state were missing. This call instead points `BASH_ENV` at the library, so every non-interactive Bash child -- `bash -c`, `bash script.sh`, `xargs bash -c`, `find -exec bash` -- sources it before running its own commands, with the same module set as this shell and without changing the child's `set` or `shopt` options. A child therefore has the complete library: public functions, internal helpers and module state, freshly initialized. A value `BASH_ENV` already held is kept and still sourced first, so coverage tools and the caller's own hook keep working. `dybatpho::load` keeps the exported module set current. Setting `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing `init.sh` does the same as calling this right after it. What does not cross: state the parent changed at run time through function calls, such as registered secrets or cleanup paths; only exported variables reach the child. Interactive shells and Bash started as `sh` do not read `BASH_ENV`, and each child pays for sourcing the library (a few tens of milliseconds for the core modules).
- [`dybatpho::version`](#dybatphoversion) — Print the version of the library this shell loaded, including the commit it is at. The release version is read from the `VERSION` file next to `init.sh`, which is what a release stamps and what a vendored or bundled copy carries. When the copy is a Git working tree, the short commit is appended as SemVer build metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the tree has uncommitted changes — so a bug report names the exact code that ran rather than the last tag before it. A checkout without a `VERSION` file falls back to `git describe`, which carries the commit of its own. Only the library's own repository is consulted: a copy vendored inside another project reports its stamped version alone, because that project's commits say nothing about which dybatpho is installed.
- [`dybatpho::load`](#dybatphoload) — Load one or more modules after `init.sh` has already been sourced.
- [`dybatpho::module_loaded`](#dybatphomodule_loaded) — Return success when a module is already loaded.
- [`dybatpho::module_list`](#dybatphomodule_list) — Print module names, one per line.

<a id="see-also"></a>

## 🔗 See also

- [example/init_modules.sh](../example/init_modules.sh)

<a id="reference"></a>

## 📚 Reference

### `dybatpho::export_functions`

Make the loaded library available to child Bash processes.
Nothing crosses the process boundary by default: exporting every function
made each child start several times slower, could push the environment past
what `execve` accepts (`find -exec ... +` then fails with "environment too
large"), and still left a child with public functions whose internal helpers
and module state were missing.

This call instead points `BASH_ENV` at the library, so every non-interactive
Bash child -- `bash -c`, `bash script.sh`, `xargs bash -c`, `find -exec bash`
-- sources it before running its own commands, with the same module set as
this shell and without changing the child's `set` or `shopt` options. A child
therefore has the complete library: public functions, internal helpers and
module state, freshly initialized. A value `BASH_ENV` already held is kept
and still sourced first, so coverage tools and the caller's own hook keep
working. `dybatpho::load` keeps the exported module set current.

Setting `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing `init.sh` does the
same as calling this right after it.

What does not cross: state the parent changed at run time through function
calls, such as registered secrets or cleanup paths; only exported variables
reach the child. Interactive shells and Bash started as `sh` do not read
`BASH_ENV`, and each child pays for sourcing the library (a few tens of
milliseconds for the core modules).

**🧪 Example**

```bash
. dybatpho/init.sh --modules semver
dybatpho::export_functions
bash -c 'dybatpho::semver_compare 1.2.0 1.10.0' # -1

```

_Function has no arguments._

**🧩 Variable sets**

- BASH_ENV
- DYBATPHO_EXPORT_MODULES
- DYBATPHO_EXPORT_BASH_ENV

**🚦 Exit codes**

- `0`: The library is exported
- `1`: Stop the script when the library path holds `$`, a backquote or a backslash, which `BASH_ENV` would expand

---

### `dybatpho::version`

Print the version of the library this shell loaded, including the
commit it is at.
The release version is read from the `VERSION` file next to `init.sh`, which
is what a release stamps and what a vendored or bundled copy carries. When
the copy is a Git working tree, the short commit is appended as SemVer build
metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the tree has
uncommitted changes — so a bug report names the exact code that ran rather
than the last tag before it. A checkout without a `VERSION` file falls back
to `git describe`, which carries the commit of its own. Only the library's
own repository is consulted: a copy vendored inside another project reports
its stamped version alone, because that project's commits say nothing about
which dybatpho is installed.

**🧪 Example**

```bash
. dybatpho/init.sh
dybatpho::version   # 2.0.0+af745ff

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_VERSION`** | string | Version to report, resolved on first call and cached; set it to override the resolution |

**🧩 Variable sets**

- DYBATPHO_VERSION

**📤 Output on stdout**

- The version, without a leading `v`, or `unknown` when it cannot be resolved

**🚦 Exit codes**

- `0`: Always

---

### `dybatpho::load`

Load one or more modules after `init.sh` has already been sourced.

**🧪 Example**

```bash
. dybatpho/init.sh --modules logging
dybatpho::load json config

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Module names; dependencies are resolved automatically |

**🧩 Variable sets**

- DYBATPHO_LOADED_MODULES

**🚦 Exit codes**

- `0`: Every requested module is loaded
- `1`: Stop the script when no module is given or a module is unknown

---

### `dybatpho::module_loaded`

Return success when a module is already loaded.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Module name |

**🚦 Exit codes**

- `0`: The module is loaded
- `1`: The module is not loaded

---

### `dybatpho::module_list`

Print module names, one per line.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | no | `loaded` | Selection, one of `loaded`, `all`, `core`, or `optional` |

**📤 Output on stdout**

- Module names in registry order, or in load order for `loaded`

**🚦 Exit codes**

- `0`: Print the requested list
- `1`: Stop the script when the selection is unknown
