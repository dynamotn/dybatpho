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

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CORE_MODULES`** | string | Modules that call each other and are always loaded |
| **`DYBATPHO_OPTIONAL_MODULES`** | string | Modules that are only loaded when requested |
| **`DYBATPHO_LOADED_MODULES`** | string | Modules loaded so far, in load order |
| **`DYBATPHO_VERSION`** | string | Cached library version, see `dybatpho::version` |

### 🚀 Highlights

- [`dybatpho::version`](#dybatphoversion) — Print the version of the library this shell loaded, including the commit it is at. The release version is read from the `VERSION` file next to `init.sh`, which is what a release stamps and what a vendored or bundled copy carries. When the copy is a Git working tree, the short commit is appended as SemVer build metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the tree has uncommitted changes — so a bug report names the exact code that ran rather than the last tag before it. A checkout without a `VERSION` file falls back to `git describe`, which carries the commit of its own. Only the library's own repository is consulted: a copy vendored inside another project reports its stamped version alone, because that project's commits say nothing about which dybatpho is installed.
- [`dybatpho::load`](#dybatphoload) — Load one or more modules after `init.sh` has already been sourced.
- [`dybatpho::module_loaded`](#dybatphomodule_loaded) — Return success when a module is already loaded.
- [`dybatpho::module_list`](#dybatphomodule_list) — Print module names, one per line.

<a id="see-also"></a>
## 🔗 See also

- [example/init_modules.sh](../example/init_modules.sh)

<a id="reference"></a>
## 📚 Reference

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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Selection, one of `loaded` (default), `all`, `core`, or `optional` |

**📤 Output on stdout**

- Module names in registry order, or in load order for `loaded`

**🚦 Exit codes**

- `0`: Print the requested list
- `1`: Stop the script when the selection is unknown
