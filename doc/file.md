# file.sh

Utilities for file handling

> 🧭 Source: [src/file.sh](../src/file.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for previewing files, splitting, joining,
normalizing, comparing, and rewriting paths, creating temporary files
or directories that are cleaned up automatically on shell exit, and
reading or rewriting the contents of a file.


Every helper that changes a file writes through a staging file in the
destination directory and renames it into place, so a reader never observes
a half-written file and an interrupted run leaves the original intact. The
destination's mode is carried over, and its owner too when the process has
the privilege to set it. These helpers honor `DRY_RUN`.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When true-like, the default, helpers that rewrite a file write through a symlink instead of replacing it |

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
- [`__dybatpho_file_stat`](#__dybatpho_file_stat) — Read one metadata field of a path across `stat` implementations. GNU and BusyBox `stat` take `-c`, BSD and macOS take `-f` with different format letters, so the GNU form is tried first and the BSD form second.
- [`__dybatpho_file_resolve`](#__dybatpho_file_resolve) — Follow a symlink chain to the file it ends at. Committing a rewrite means renaming a staging file onto the destination, which would replace a symlink with a regular file and quietly detach it from whatever it pointed at. Resolving first writes through the link instead, so a dotfile symlinked into a repository keeps pointing there and the file in the repository is the one that changes.
- [`__dybatpho_file_staging`](#__dybatpho_file_staging) — Print the path of a staging file next to a destination. The staging file has to share a directory with the destination, because `mv` is only atomic within one filesystem.
- [`__dybatpho_file_discard`](#__dybatpho_file_discard) — Remove a staging file that will not be committed.
- [`__dybatpho_file_operand`](#__dybatpho_file_operand) — Render a path that is safe to pass to a command that does not understand `--`. The BSD versions of `chmod`, `chown`, and `sed` on macOS treat `--` as a file name rather than as the end of the options, so a path that could be read as an option is prefixed with `./` instead.
- [`__dybatpho_file_commit`](#__dybatpho_file_commit) — Move a staging file onto its destination, carrying the destination's mode and owner over first so that the rename does not change how the file is accessed.
- [`dybatpho::file_write_atomic`](#dybatphofile_write_atomic) — Write standard input to a file through a staging file, so that readers see either the previous contents or the complete new contents.
- [`__dybatpho_file_sed_delimiter`](#__dybatpho_file_sed_delimiter) — Pick a `sed` substitution delimiter that appears in neither the pattern nor the replacement, so that neither has to be escaped.
- [`dybatpho::file_replace`](#dybatphofile_replace) — Substitute every match of a pattern in a file, in place.
- [`dybatpho::file_ensure_line`](#dybatphofile_ensure_line) — Append a line to a file unless the exact line is already there. Running it again changes nothing, which makes it safe for scripts that maintain a dotfile across repeated runs.
- [`dybatpho::file_remove_line`](#dybatphofile_remove_line) — Remove every occurrence of an exact line from a file. A file that never contained the line, or that does not exist, is left as is and reported as success: the line is absent either way.
- [`dybatpho::file_hash`](#dybatphofile_hash) — Print the checksum of a file.
- [`dybatpho::file_size`](#dybatphofile_size) — Print the size of a file in bytes.
- [`dybatpho::file_age_seconds`](#dybatphofile_age_seconds) — Print how many seconds have passed since a file was last modified.
- [`dybatpho::file_backup`](#dybatphofile_backup) — Copy a file next to itself under a timestamped name and print the copy's path, so that a caller can undo a change it is about to make.
- [`dybatpho::find_up`](#dybatphofind_up) — Search a directory and each of its parents for an entry, and print the first one found. This is how a tool locates the root of the project it was invoked inside, from wherever the caller happened to be.
- [`dybatpho::ensure_dir`](#dybatphoensure_dir) — Create a directory and every missing parent, then print its path. Running it again on an existing directory changes nothing, which lets a script call it before every write instead of guarding each one.

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

### `dybatpho::file_write_atomic`

- The destination keeps its mode, and its owner when the process may set it

### `dybatpho::file_replace`

- This avoids `sed -i`, whose argument differs between GNU and BSD, by rewriting through a staging file instead

### `dybatpho::file_ensure_line`

- The comparison is an exact whole-line match, not a substring or pattern

### `dybatpho::file_remove_line`

- The comparison is an exact whole-line match, not a substring or pattern

### `dybatpho::file_hash`

- Falls back from the GNU `*sum` tools to `shasum`/`md5` and then `openssl`

### `dybatpho::file_backup`

- A second backup in the same second gets a numeric suffix, so an existing backup is never overwritten

### `dybatpho::find_up`

- Matches files and directories alike, so `.git` is found in a worktree, where it is a file, as well as in a normal clone

### `dybatpho::ensure_dir`

- A mode is applied whether the directory was just created or already existed, so the result does not depend on whether the script ran before

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


---

### `__dybatpho_file_stat`

Read one metadata field of a path across `stat` implementations.
  GNU and BusyBox `stat` take `-c`, BSD and macOS take `-f` with different
  format letters, so the GNU form is tried first and the BSD form second.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field to read, one of `mode`, `size`, `mtime`, or `owner` |
| `$2` | string | Path to inspect |

**📤 Output on stdout**

- Requested field

**🚦 Exit codes**

- `1`: No `stat` implementation understood the request


---

### `__dybatpho_file_resolve`

Follow a symlink chain to the file it ends at.
  Committing a rewrite means renaming a staging file onto the destination,
  which would replace a symlink with a regular file and quietly detach it from
  whatever it pointed at. Resolving first writes through the link instead, so
  a dotfile symlinked into a repository keeps pointing there and the file in
  the repository is the one that changes.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to resolve |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When false-like, return the path unchanged so the symlink itself is replaced |

**📤 Output on stdout**

- Resolved path, or the original path when it is not a symlink

**🚦 Exit codes**

- `1`: The symlink chain is too deep to be a valid one


---

### `__dybatpho_file_staging`

Print the path of a staging file next to a destination.
  The staging file has to share a directory with the destination, because
  `mv` is only atomic within one filesystem.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination path |

**📤 Output on stdout**

- Staging file path


---

### `__dybatpho_file_discard`

Remove a staging file that will not be committed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Staging file path |


---

### `__dybatpho_file_operand`

Render a path that is safe to pass to a command that does not
  understand `--`. The BSD versions of `chmod`, `chown`, and `sed` on macOS
  treat `--` as a file name rather than as the end of the options, so a path
  that could be read as an option is prefixed with `./` instead.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path |

**📤 Output on stdout**

- The path, prefixed with `./` when it starts with a dash


---

### `__dybatpho_file_commit`

Move a staging file onto its destination, carrying the
  destination's mode and owner over first so that the rename does not change
  how the file is accessed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Staging file path |
| `$2` | string | Destination path |

**🚦 Exit codes**

- `1`: The staging file cannot be moved into place


---

### `dybatpho::file_write_atomic`

Write standard input to a file through a staging file, so that
  readers see either the previous contents or the complete new contents.

**🧪 Examples**

```bash
printf 'port = 8080\n' | dybatpho::file_write_atomic "${HOME}/.config/app.ini"

```

```bash
dybatpho::file_write_atomic "./config.json" << 'EOF'
{ "debug": false }
EOF

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination file path |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the write instead of performing it |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When true-like, the default, write through a symlink rather than replacing it |

**🚦 Exit codes**

- `1`: The destination directory is missing or the write fails


---

### `__dybatpho_file_sed_delimiter`

Pick a `sed` substitution delimiter that appears in neither the
  pattern nor the replacement, so that neither has to be escaped.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Substitution pattern |
| `$2` | string | Replacement text |

**📤 Output on stdout**

- Delimiter character

**🚦 Exit codes**

- `1`: Every candidate delimiter occurs in the pattern or replacement


---

### `dybatpho::file_replace`

Substitute every match of a pattern in a file, in place.

**🧪 Examples**

```bash
dybatpho::file_replace "./app.conf" "^debug = true$" "debug = false"

```

```bash
dybatpho::file_replace "./Makefile" "v[0-9]\+\.[0-9]\+" "v2.0"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path to rewrite |
| `$2` | string | POSIX basic regular expression to match |
| `$3` | string | Replacement text, where `&` and `\1` refer to the match |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the rewrite instead of performing it |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When true-like, the default, write through a symlink rather than replacing it |

**🚦 Exit codes**

- `1`: The file is missing, `sed` fails, or no delimiter can be chosen


---

### `dybatpho::file_ensure_line`

Append a line to a file unless the exact line is already there.
  Running it again changes nothing, which makes it safe for scripts that
  maintain a dotfile across repeated runs.

**🧪 Example**

```bash
dybatpho::file_ensure_line "${HOME}/.bashrc" 'export EDITOR=nvim'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path, created when it does not exist |
| `$2` | string | Exact line to guarantee |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the change instead of performing it |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When true-like, the default, write through a symlink rather than replacing it |

**🚦 Exit codes**

- `1`: The parent directory is missing or the write fails


---

### `dybatpho::file_remove_line`

Remove every occurrence of an exact line from a file.
  A file that never contained the line, or that does not exist, is left as is
  and reported as success: the line is absent either way.

**🧪 Example**

```bash
dybatpho::file_remove_line "${HOME}/.bashrc" 'export EDITOR=nvim'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |
| `$2` | string | Exact line to remove |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the change instead of performing it |
| **`DYBATPHO_FILE_FOLLOW_SYMLINKS`** | string | When true-like, the default, write through a symlink rather than replacing it |

**🚦 Exit codes**

- `1`: The write fails


---

### `dybatpho::file_hash`

Print the checksum of a file.

**🧪 Example**

```bash
checksum="$(dybatpho::file_hash "./release.tar.gz")"
dybatpho::file_hash "./release.tar.gz" sha512

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |
| `$2` | string | Algorithm, one of `md5`, `sha1`, `sha256` (default), or `sha512` |

**📤 Output on stdout**

- Checksum in lowercase hexadecimal, without the file name

**🚦 Exit codes**

- `1`: The file is missing, the algorithm is unknown, or no checksum tool is installed


---

### `dybatpho::file_size`

Print the size of a file in bytes.

**🧪 Example**

```bash
bytes="$(dybatpho::file_size "./release.tar.gz")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |

**📤 Output on stdout**

- Size in bytes

**🚦 Exit codes**

- `1`: The file is missing


---

### `dybatpho::file_age_seconds`

Print how many seconds have passed since a file was last modified.

**🧪 Example**

```bash
if (($(dybatpho::file_age_seconds "${cache}") > 3600)); then
  dybatpho::info "Cache is stale"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |

**📤 Output on stdout**

- Age in seconds, or `0` when the modification time is in the future

**🚦 Exit codes**

- `1`: The file is missing or its modification time cannot be read


---

### `dybatpho::file_backup`

Copy a file next to itself under a timestamped name and print
  the copy's path, so that a caller can undo a change it is about to make.

**🧪 Example**

```bash
backup="$(dybatpho::file_backup "${HOME}/.bashrc")"
dybatpho::info "Previous version kept at ${backup}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path to back up |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the path without copying anything |

**📤 Output on stdout**

- Path of the backup copy

**🚦 Exit codes**

- `1`: The file is missing or the copy fails


---

### `dybatpho::find_up`

Search a directory and each of its parents for an entry, and
  print the first one found. This is how a tool locates the root of the
  project it was invoked inside, from wherever the caller happened to be.

**🧪 Examples**

```bash
if git_dir="$(dybatpho::find_up ".git")"; then
  root="$(dybatpho::path_dirname "${git_dir}")"
fi

```

```bash
manifest="$(dybatpho::find_up "package.json" "${source_dir}")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Entry name to look for in each directory |
| `$2` | string | Directory to start from, default is the current directory |

**📤 Output on stdout**

- Absolute path of the first matching entry

**🚦 Exit codes**

- `0`: A matching entry was found
- `1`: The filesystem root was reached without a match


---

### `dybatpho::ensure_dir`

Create a directory and every missing parent, then print its
  path. Running it again on an existing directory changes nothing, which lets
  a script call it before every write instead of guarding each one.

**🧪 Examples**

```bash
cache="$(dybatpho::ensure_dir "${HOME}/.cache/myapp")"
printf 'cached\n' | dybatpho::file_write_atomic "${cache}/last-run"

```

```bash
dybatpho::ensure_dir "${HOME}/.config/myapp" 700 > /dev/null

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Directory path |
| `$2` | string | Optional mode applied to the directory, such as `755` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the path without creating anything |

**📤 Output on stdout**

- The directory path

**🚦 Exit codes**

- `1`: The path exists as something other than a directory, or cannot be created

