# file.sh

Utilities for file handling

> 🧭 Source: [src/file.sh](../src/file.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for previewing files and creating temporary
files or directories that are cleaned up automatically on shell exit.

### 🚀 Highlights

- [`dybatpho::show_file`](#dybatphoshow_file) — Show the contents of a file with line numbers.
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

