# file.sh

Utilities for file handling

> 🧭 Source: [src/file.sh](../src/file.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for previewing files, splitting, joining,
normalizing, comparing, and rewriting paths, and creating temporary files
or directories that are cleaned up automatically on shell exit.

### 🚀 Highlights

- [`dybatpho::show_file`](#dybatphoshow_file) — Show the contents of a file with line numbers.
- [`dybatpho::path_dirname`](#dybatphopath_dirname) — Return the directory component of a path.
- [`dybatpho::path_basename`](#dybatphopath_basename) — Return the basename component of a path.
- [`dybatpho::path_extname`](#dybatphopath_extname) — Return the final extension of a path, including the leading dot.
- [`dybatpho::path_stem`](#dybatphopath_stem) — Return the basename of a path without its final extension.
- [`dybatpho::path_join`](#dybatphopath_join) — Join path segments with single `/` separators.
- [`dybatpho::path_normalize`](#dybatphopath_normalize) — Normalize a path by collapsing repeated separators and resolving `.` and `..` textually.
- [`dybatpho::path_is_abs`](#dybatphopath_is_abs) — Return success when a path is absolute.
- [`dybatpho::path_has_ext`](#dybatphopath_has_ext) — Return success when a path has any extension or a matching exact extension.
- [`dybatpho::path_change_ext`](#dybatphopath_change_ext) — Return a path with its final extension replaced.
- [`dybatpho::path_relative`](#dybatphopath_relative) — Return the relative path from a base path to a target path.
- [`dybatpho::create_temp`](#dybatphocreate_temp) — Create a temporary file or directory and register it for cleanup on shell exit.

<a id="see-also"></a>
## 🔗 See also

- [example/file_ops.sh](../example/file_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::show_file`

- Uses `bat` when available for richer output, otherwise falls back to `cat -n`

### `dybatpho::create_temp`

- Pass `/` or an empty extension to create a directory instead of a file
- The created path is automatically registered for cleanup on script exit

<a id="reference"></a>
## 📚 Reference

### `dybatpho::show_file`

Show the contents of a file with line numbers.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |

**📤 Output on stderr**

- File contents


---

### `dybatpho::path_dirname`

Return the directory component of a path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |

**📤 Output on stdout**

- Directory component of the path


---

### `dybatpho::path_basename`

Return the basename component of a path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |
| `$2` | string | Optional suffix to strip from the basename |

**📤 Output on stdout**

- Basename component of the path


---

### `dybatpho::path_extname`

Return the final extension of a path, including the leading dot.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |

**📤 Output on stdout**

- Final extension of the basename, or empty when none exists


---

### `dybatpho::path_stem`

Return the basename of a path without its final extension.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |

**📤 Output on stdout**

- Basename without the final extension


---

### `dybatpho::path_join`

Join path segments with single `/` separators.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Path segments to join |

**📤 Output on stdout**

- Joined path


---

### `dybatpho::path_normalize`

Normalize a path by collapsing repeated separators and resolving `.` and `..` textually.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to normalize |

**📤 Output on stdout**

- Normalized path


---

### `dybatpho::path_is_abs`

Return success when a path is absolute.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |

**🚦 Exit codes**

- `0`: The path is absolute
- `1`: The path is relative


---

### `dybatpho::path_has_ext`

Return success when a path has any extension or a matching exact extension.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to inspect |
| `$2` | string | Optional extension to compare against |

**🚦 Exit codes**

- `0`: The path has an extension or matches the requested one
- `1`: The path does not have an extension or does not match the requested one


---

### `dybatpho::path_change_ext`

Return a path with its final extension replaced.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to rewrite |
| `$2` | string | New extension, with or without leading dot, or empty to remove the extension |

**📤 Output on stdout**

- Path with updated extension


---

### `dybatpho::path_relative`

Return the relative path from a base path to a target path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Target path |
| `$2` | string | Base path |

**📤 Output on stdout**

- Relative path from base to target


---

### `dybatpho::create_temp`

Create a temporary file or directory and register it for cleanup on shell exit.

**🧪 Examples**

```bash
local TMPFILE
dybatpho::create_temp TMPFILE ".txt"
echo "hello" > "${TMPFILE}"

```

```bash
local TMPDIR_VAR
dybatpho::create_temp TMPDIR_VAR "/"
mkdir -p "${TMPDIR_VAR}/subdir"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the created path |
| `$2` | string | File extension to append, or `/`/empty to create a directory |
| `$3` | string | Name prefix, default is `temp` |
| `$4` | string | Parent directory, default is `${TMPDIR:-/tmp}` |

