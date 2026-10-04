# safety.sh

Guards for destructive operations

> 🧭 Source: [src/safety.sh](../src/safety.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Wrappers that make irreversible operations explicit before they run:

- removing files and directories (`dybatpho::safe_rm`)
- overwriting existing files, including copy and move
  (`dybatpho::safe_overwrite`, `dybatpho::safe_copy`, `dybatpho::safe_move`)
- extracting archives, with path-traversal validation
  (`dybatpho::safe_extract`)
- changing system state through an external command
  (`dybatpho::safe_system`)

Every wrapper applies the same three rules:

1. the target path is validated against protected paths and, when
   `DYBATPHO_SAFE_ROOTS` is set, confined inside those roots;
2. the operation runs unattended only with `--force` (or `DYBATPHO_FORCE`),
   otherwise it asks for confirmation on an interactive terminal;
3. a non-interactive run without `--force` refuses instead of guessing, and
   `DRY_RUN` prints the command instead of executing it.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORCE`** | bool | Set to `true` to approve every guarded operation without prompting |
| **`DYBATPHO_INTERACTIVE`** | string | `auto` detects a terminal on stdin, `true`/`false` override the detection |
| **`DYBATPHO_SAFE_ROOTS`** | string | Colon-separated roots; when set, guarded paths must stay inside one of them |
| **`DYBATPHO_PROTECTED_PATHS`** | string | Extra colon-separated paths that guarded operations must never touch |

### 🚀 Highlights

- [`dybatpho::is_interactive`](#dybatphois_interactive) — Return success when the script can ask the user a question.
- [`dybatpho::confirm`](#dybatphoconfirm) — Ask a yes/no question and return the answer as an exit code.
- [`dybatpho::assert_safe_path`](#dybatphoassert_safe_path) — Validate a path before a destructive operation and print it as an absolute path. The checks are made on the path as written and on the path its directories resolve to through symbolic links, so a link inside a safe root that points elsewhere cannot carry the operation out of it. The last component is not followed, as `rm` and `mv` act on a link itself.
- [`dybatpho::safe_rm`](#dybatphosafe_rm) — Remove files and directories after validating them and confirming the removal.
- [`dybatpho::safe_overwrite`](#dybatphosafe_overwrite) — Confirm that an existing file may be replaced, optionally keeping a backup.
- [`dybatpho::safe_copy`](#dybatphosafe_copy) — Copy a file or directory, guarding the destination against an accidental overwrite.
- [`dybatpho::safe_move`](#dybatphosafe_move) — Move a file or directory, guarding the destination against an accidental overwrite.
- [`dybatpho::safe_extract`](#dybatphosafe_extract) — Extract an archive after rejecting entries that escape the destination.
- [`dybatpho::safe_system`](#dybatphosafe_system) — Run a command that changes system state, after confirming it.

<a id="usage"></a>
## 🚀 Usage

### Remove a build directory, asking first

```bash
dybatpho::safe_rm --recursive "${build_dir}"
```

### Overwrite a config file unattended, keeping a backup

```bash
dybatpho::safe_overwrite --force --backup "${config}" \
  && printf '%s\n' "${rendered}" > "${config}"
```

### Extract an untrusted archive

```bash
dybatpho::safe_extract --force "${tarball}" "${workdir}" 1
```

### Guard a system change

```bash
dybatpho::safe_system "Restart nginx" -- systemctl restart nginx
```

<a id="see-also"></a>
## 🔗 See also

- [example/safety_ops.sh](../example/safety_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Confine a whole script with `DYBATPHO_SAFE_ROOTS="${workdir}"` so a bad path can never reach the rest of the filesystem.

### `dybatpho::safe_rm`

- Missing paths are skipped instead of failing, like `rm -f`

### `dybatpho::safe_overwrite`

- Call it as a guard: `dybatpho::safe_overwrite "${file}" && printf '%s' "${data}" > "${file}"`

### `dybatpho::safe_extract`

- Symlink targets stored inside an archive aren't inspected; extract untrusted archives into a scratch directory
- The entries are listed and extracted by the `archive` module, which `safety` does not load; load it alongside: `--modules safety archive`

<a id="reference"></a>
## 📚 Reference

### `dybatpho::is_interactive`

Return success when the script can ask the user a question.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_INTERACTIVE`** | string | `auto` detects a terminal on stdin, `true`/`false` override the detection |

**🚦 Exit codes**

- `0`: Input is attached to a terminal, or `DYBATPHO_INTERACTIVE` forces interactive mode
- `1`: The script runs unattended


---

### `dybatpho::confirm`

Ask a yes/no question and return the answer as an exit code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Question to ask |
| `$2` | string | Optional default answer used on an empty reply, default is `no` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORCE`** | bool | Answer yes without prompting |

**📤 Output on stdout**

- None; the question is written to stderr

**🚦 Exit codes**

- `0`: The answer is yes, or `DYBATPHO_FORCE` is enabled
- `1`: The answer is no, or the script isn't interactive


---

### `dybatpho::assert_safe_path`

Validate a path before a destructive operation and print it as an absolute path.
The checks are made on the path as written and on the path its
directories resolve to through symbolic links, so a link inside a safe
root that points elsewhere cannot carry the operation out of it. The last
component is not followed, as `rm` and `mv` act on a link itself.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to validate |
| `$2` | string | Optional wording used in error messages, default is `path` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SAFE_ROOTS`** | string | Colon-separated roots the path must stay inside when set |
| **`DYBATPHO_PROTECTED_PATHS`** | string | Extra colon-separated paths that are always rejected |

**📤 Output on stdout**

- Normalized absolute path, as written

**🚦 Exit codes**

- `1`: Stop the script when the path is empty, protected, or outside `DYBATPHO_SAFE_ROOTS`


---

### `dybatpho::safe_rm`

Remove files and directories after validating them and confirming the removal.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, or `--recursive`/`-r` to allow directories |
| `$@` | string | Paths to remove, optionally after a `--` separator |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the `rm` commands instead of running them |

**🚦 Exit codes**

- `0`: Every requested path is removed or already missing
- `1`: The removal is declined, or the script stops on an invalid path


---

### `dybatpho::safe_overwrite`

Confirm that an existing file may be replaced, optionally keeping a backup.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy |
| `$2` | string | Destination path to overwrite |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the backup command instead of running it |

**🚦 Exit codes**

- `0`: The destination is free, or replacing it is approved
- `1`: Replacing the destination is declined


---

### `dybatpho::safe_copy`

Copy a file or directory, guarding the destination against an accidental overwrite.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy |
| `$2` | string | Source path |
| `$3` | string | Destination path or directory |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the `cp` command instead of running it |

**🚦 Exit codes**

- `0`: The copy is done
- `1`: The overwrite is declined, or the script stops when the source is missing


---

### `dybatpho::safe_move`

Move a file or directory, guarding the destination against an accidental overwrite.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation, or `--backup`/`-b` to keep a `.bak` copy |
| `$2` | string | Source path |
| `$3` | string | Destination path or directory |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the `mv` command instead of running it |

**🚦 Exit codes**

- `0`: The move is done
- `1`: The overwrite is declined, or the script stops when the source is missing


---

### `dybatpho::safe_extract`

Extract an archive after rejecting entries that escape the destination.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation |
| `$2` | string | Archive file path |
| `$3` | string | Optional destination directory, default is `.` |
| `$4` | number | Optional strip-components count, default is `0` |

**📤 Output on stdout**

- Command output from the selected extractor, if any

**🚦 Exit codes**

- `0`: The archive is extracted
- `1`: Overwriting existing files is declined
- `1`: Stop the script when an entry is absolute or traverses outside the destination
- `1`: Stop the script when the `archive` module is not loaded


---

### `dybatpho::safe_system`

Run a command that changes system state, after confirming it.

**🧪 Example**

```bash
dybatpho::safe_system "Restart nginx" -- systemctl restart nginx
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip confirmation |
| `$2` | string | Human-readable description of the change |
| `$@` | string | A `--` separator followed by the command and its arguments |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the command instead of running it |

**🚦 Exit codes**

- `0`: The command ran successfully
- `1`: The change is declined, or the command failed
