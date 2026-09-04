# secret.sh

Utilities for handling secrets safely

> 🧭 Source: [src/secret.sh](../src/secret.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module reads secrets from files, environment variables, or stdin,
masks registered secrets in logs and error messages, and enforces safe
file permissions. Secrets are kept in shell variables only; they are never
exported, never written to shell history, and never placed in a shared
temporary file unless explicitly requested.



### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SECRET_PLACEHOLDER`** | string | Text substituted for registered secrets. Default is `***` |
| **`DYBATPHO_SECRET_MIN_LENGTH`** | number | Shortest value that may be registered for masking. Default is `4` |
| **`DYBATPHO_SECRET_MAX_MODE`** | string | Most permissive octal mode allowed for a secret file. Default is `600` |
| **`DYBATPHO_SECRET_STRICT_PERMS`** | string | When true-like, permission problems fail instead of warning. Default is `true` |
| **`DYBATPHO_SECRET_COUNT`** | number | Number of registered secrets; logging masks output only when above zero |

### 🚀 Highlights

- [`__dybatpho_secret_permission_error`](#__dybatpho_secret_permission_error) — Report a permission problem as a fatal error or a warning.
- [`__dybatpho_secret_register_one`](#__dybatpho_secret_register_one) — Register one value for masking, keeping the registry sorted by length.
- [`__dybatpho_secret_mask_var`](#__dybatpho_secret_mask_var) — Replace every registered secret inside a variable, in place.
- [`__dybatpho_secret_file_mode`](#__dybatpho_secret_file_mode) — Print the octal permission mode of a path, following symbolic links.
- [`__dybatpho_secret_file_owner`](#__dybatpho_secret_file_owner) — Print the owner user id of a path.
- [`dybatpho::secret_register`](#dybatphosecret_register) — Register secret values so they are masked in logs, errors, and masked output.
- [`dybatpho::secret_forget`](#dybatphosecret_forget) — Forget every registered secret so masking stops.
- [`dybatpho::secret_mask`](#dybatphosecret_mask) — Mask registered secrets in arguments or in stdin.
- [`dybatpho::secret_mask_run`](#dybatphosecret_mask_run) — Run a command and mask registered secrets in its output.
- [`dybatpho::secret_hint`](#dybatphosecret_hint) — Print a non-reversible hint for a secret, revealing only its last characters.
- [`dybatpho::secret_check_permission`](#dybatphosecret_check_permission) — Verify that a secret file is owned by the current user and isn't readable by others.
- [`dybatpho::secret_from_file`](#dybatphosecret_from_file) — Read a secret from a file into a variable and register it for masking.
- [`dybatpho::secret_from_env`](#dybatphosecret_from_env) — Read a secret from an environment variable and unset the source variable.
- [`dybatpho::secret_from_stdin`](#dybatphosecret_from_stdin) — Read a secret from stdin, without echoing it when the input is a terminal.
- [`dybatpho::secret_read`](#dybatphosecret_read) — Read a secret from a source specification.
- [`dybatpho::secret_write_file`](#dybatphosecret_write_file) — Write a secret to a file that only its owner can read.
- [`dybatpho::secret_with_file`](#dybatphosecret_with_file) — Run a command that needs the secret as a file, without writing it to disk.
- [`exec`](#exec) — 
- [`exec`](#exec) — 
- [`exec`](#exec) — 
- [`dybatpho::secret_no_history`](#dybatphosecret_no_history) — Stop the current shell from recording commands into a history file.
- [`dybatpho::secret_wipe`](#dybatphosecret_wipe) — Overwrite and unset variables that hold secrets.
- [`dybatpho::secret_shred`](#dybatphosecret_shred) — Remove files containing secrets, overwriting their content when possible.
- [`__dybatpho_secret_file_size`](#__dybatpho_secret_file_size) — Print the size of a file in bytes.

<a id="see-also"></a>
## 🔗 See also

- [example/secret_ops.sh](../example/secret_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::secret_register`

- Multiline secrets also register each of their lines so line-based streams stay masked

### `dybatpho::secret_forget`

- Registered values are process-local; this only clears the current shell

### `dybatpho::secret_mask`

- Stdin is processed line by line, so register multiline secrets before streaming
- Registered secrets stay in the current process, so run this in the shell that registered them

### `dybatpho::secret_mask_run`

- Output streams are merged so a secret split across both streams can't leak unmasked

### `dybatpho::secret_from_file`

- Permissions are validated with `dybatpho::secret_check_permission` before the file is read

### `dybatpho::secret_from_env`

- The source variable is unset by default so the secret isn't inherited by child processes

### `dybatpho::secret_from_stdin`

- Reads a single line; use `dybatpho::secret_from_file` for multiline material such as private keys

### `dybatpho::secret_write_file`

- The file is created with mode 600 through a private temporary file and moved into place atomically

### `dybatpho::secret_with_file`

- The secret is exposed through `/dev/fd`, so it never reaches the filesystem on supported systems

### `dybatpho::secret_no_history`

- Call this before any command that receives a secret on its command line

### `dybatpho::secret_wipe`

- Overwriting is best effort because Bash may keep copies of a string; masking stays active after a wipe

### `dybatpho::secret_shred`

- Overwriting is skipped on copy-on-write or journaling filesystems that keep old blocks

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_secret_permission_error`

Report a permission problem as a fatal error or a warning.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message |

**🚦 Exit codes**

- `1`: Stop the script when `DYBATPHO_SECRET_STRICT_PERMS` is true-like


---

### `__dybatpho_secret_register_one`

Register one value for masking, keeping the registry sorted by length.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Secret value |
| `$2` | string | Pass `true` to report skipped short values at debug level |


---

### `__dybatpho_secret_mask_var`

Replace every registered secret inside a variable, in place.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable to redact |


---

### `__dybatpho_secret_file_mode`

Print the octal permission mode of a path, following symbolic links.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path |

**📤 Output on stdout**

- Three or four digit octal mode

**🚦 Exit codes**

- `1`: The mode cannot be read


---

### `__dybatpho_secret_file_owner`

Print the owner user id of a path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path |

**📤 Output on stdout**

- Numeric user id

**🚦 Exit codes**

- `1`: The owner cannot be read


---

### `dybatpho::secret_register`

Register secret values so they are masked in logs, errors, and masked output.

**🧪 Example**

```bash
dybatpho::secret_register "${TOKEN}"
dybatpho::error "request failed with ${TOKEN}" # logs `request failed with ***`

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Secret values |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SECRET_MIN_LENGTH`** | number | Values shorter than this are skipped to avoid redacting unrelated text |


---

### `dybatpho::secret_forget`

Forget every registered secret so masking stops.

_Function has no arguments._


---

### `dybatpho::secret_mask`

Mask registered secrets in arguments or in stdin.

**🧪 Example**

```bash
printf 'token=%s\n' "${TOKEN}" | dybatpho::secret_mask
dybatpho::secret_mask "authorization: ${TOKEN}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Optional text to mask; stdin is read when no argument is given |

**📤 Output on stdout**

- Input text with every registered secret replaced by the placeholder


---

### `dybatpho::secret_mask_run`

Run a command and mask registered secrets in its output.

**🧪 Example**

```bash
dybatpho::secret_mask_run curl -H "Authorization: Bearer ${TOKEN}" "${url}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Command and arguments |

**📤 Output on stdout**

- Masked stdout and stderr of the command

**🚦 Exit codes**

- `*`: Exit code of the command


---

### `dybatpho::secret_hint`

Print a non-reversible hint for a secret, revealing only its last characters.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Secret value |
| `$2` | number | Characters to reveal, default is 4 |

**📤 Output on stdout**

- Placeholder followed by the revealed suffix


---

### `dybatpho::secret_check_permission`

Verify that a secret file is owned by the current user and isn't readable by others.

**🧪 Example**

```bash
dybatpho::secret_check_permission ~/.config/app/token 600

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |
| `$2` | string | Most permissive octal mode allowed, default is `DYBATPHO_SECRET_MAX_MODE` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SECRET_STRICT_PERMS`** | string | Set to a false-like value to warn instead of failing |

**🚦 Exit codes**

- `0`: The file exists and its permissions are acceptable
- `1`: The file is missing, unreadable, or too permissive under strict mode


---

### `dybatpho::secret_from_file`

Read a secret from a file into a variable and register it for masking.

**🧪 Example**

```bash
local TOKEN
dybatpho::secret_from_file TOKEN ~/.config/app/token

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the secret |
| `$2` | string | File path |

**🧩 Variable sets**

- **`$1`**: string Secret content without trailing newlines

**🚦 Exit codes**

- `1`: The file is missing, empty, or has unsafe permissions


---

### `dybatpho::secret_from_env`

Read a secret from an environment variable and unset the source variable.

**🧪 Example**

```bash
local TOKEN
dybatpho::secret_from_env TOKEN APP_TOKEN

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the secret |
| `$2` | string | Environment variable holding the secret |
| `$3` | string | Pass `keep` to leave the environment variable in place |

**🧩 Variable sets**

- **`$1`**: string Secret value

**🚦 Exit codes**

- `1`: The environment variable is unset or empty


---

### `dybatpho::secret_from_stdin`

Read a secret from stdin, without echoing it when the input is a terminal.

**🧪 Example**

```bash
local TOKEN
dybatpho::secret_from_stdin TOKEN "API token: "

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the secret |
| `$2` | string | Optional prompt written to stderr when stdin is a terminal |

**🧩 Variable sets**

- **`$1`**: string Secret value without its trailing newline

**📤 Output on stderr**

- Prompt text when stdin is a terminal

**🚦 Exit codes**

- `1`: No secret is provided


---

### `dybatpho::secret_read`

Read a secret from a source specification.

**🧪 Example**

```bash
local TOKEN
dybatpho::secret_read TOKEN "file:${HOME}/.token"
dybatpho::secret_read TOKEN env:APP_TOKEN
dybatpho::secret_read TOKEN - "API token: "

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the secret |
| `$2` | string | Source: `file:PATH`, `env:NAME`, `stdin`, or `-` |
| `$3` | string | Optional prompt used by the stdin source |

**🧩 Variable sets**

- **`$1`**: string Secret value

**🚦 Exit codes**

- `1`: The source is unsupported or the secret can't be read


---

### `dybatpho::secret_write_file`

Write a secret to a file that only its owner can read.

**🧪 Example**

```bash
dybatpho::secret_write_file "${HOME}/.config/app/token" TOKEN

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination file path |
| `$2` | string | Variable name holding the secret |

**🚦 Exit codes**

- `1`: The destination directory is missing or the write fails


---

### `dybatpho::secret_with_file`

Run a command that needs the secret as a file, without writing it to disk.

**🧪 Example**

```bash
dybatpho::secret_with_file TOKEN gpg --passphrase-file '{}' --decrypt archive.gpg

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name holding the secret |
| `$@` | string | Command and arguments; every `{}` is replaced by the secret file path |

**🚦 Exit codes**

- `*`: Exit code of the command


---

### `exec`



---

### `exec`



---

### `exec`



---

### `dybatpho::secret_no_history`

Stop the current shell from recording commands into a history file.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_REPL_HISTORY_FILE`** | string | Redirected to `/dev/null` so breakpoints don't persist secrets |


---

### `dybatpho::secret_wipe`

Overwrite and unset variables that hold secrets.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Variable names |


---

### `dybatpho::secret_shred`

Remove files containing secrets, overwriting their content when possible.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | File paths |


---

### `__dybatpho_secret_file_size`

Print the size of a file in bytes.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path |

**📤 Output on stdout**

- Size in bytes, or `0` when it can't be determined

