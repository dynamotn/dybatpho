# archive.sh

Utilities for creating, extracting, and listing archives

> 🧭 Source: [src/archive.sh](../src/archive.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for common archive workflows in shell scripts:
creating archives from files or directories, extracting them into a target
directory, and listing their contents. Supported formats include `.tar`,
`.tar.gz` / `.tgz`, `.tar.xz`, `.tar.bz2` / `.tbz2` / `.tbz`, `.tar.zst`,
`.zip`, and single-file compressed outputs such as `.gz`, `.xz`, `.bz2`,
and `.zst`. Extraction also supports optional strip-components behavior.

### 🚀 Highlights

- [`__dybatpho_archive_format`](#__dybatpho_archive_format) — Detect the supported archive format from a file name.
- [`__dybatpho_archive_output_name`](#__dybatpho_archive_output_name) — Return the output name produced when a single-file compressed archive is extracted.
- [`__dybatpho_archive_move_stripped`](#__dybatpho_archive_move_stripped) — Move extracted zip contents while stripping leading path components.
- [`dybatpho::archive_create`](#dybatphoarchive_create) — Create an archive from a file or directory.
- [`dybatpho::archive_extract`](#dybatphoarchive_extract) — Extract an archive into a target directory.
- [`dybatpho::archive_list`](#dybatphoarchive_list) — List the contents of an archive without extracting it.

<a id="see-also"></a>
## 🔗 See also

- [example/archive_ops.sh](../example/archive_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_archive_format`

Detect the supported archive format from a file name.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Archive file path |

**📤 Output on stdout**

- Archive format identifier


---

### `__dybatpho_archive_output_name`

Return the output name produced when a single-file compressed archive is extracted.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Archive file path |

**📤 Output on stdout**

- Default extracted file name


---

### `__dybatpho_archive_move_stripped`

Move extracted zip contents while stripping leading path components.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Temporary extraction directory |
| `$2` | string | Final destination directory |
| `$3` | number | Number of leading path components to remove |


---

### `dybatpho::archive_create`

Create an archive from a file or directory.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Source file or directory |
| `$2` | string | Output archive path |

**📤 Output on stdout**

- Command output from the selected archiver, if any


---

### `dybatpho::archive_extract`

Extract an archive into a target directory.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Archive file path |
| `$2` | string | Optional extraction directory, default is `.` |
| `$3` | number | Optional strip-components count, default is `0` |

**📤 Output on stdout**

- Command output from the selected extractor, if any


---

### `dybatpho::archive_list`

List the contents of an archive without extracting it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Archive file path |

**📤 Output on stdout**

- One listed entry per line

