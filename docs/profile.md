# profile.sh

Utilities for finding where a Bash script spends its time

> 🧭 Source: [src/profile.sh](../src/profile.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module times named blocks of a script and reports, per name, how many
times it ran, its total time, and its self time -- the total less the time
of the blocks that ran inside it, so a nested block is never counted twice.

Blocks are marked by hand with `dybatpho::profile_begin` and
`dybatpho::profile_end`, or `dybatpho::profile_run` around one command. For
one run, `dybatpho::profile_start` times every function instead, through a
`DEBUG` trap; that costs time on every command, so it does nothing unless
`DYBATPHO_PROFILE` is set, and it needs Bash 5's `EPOCHREALTIME`.

### 🌍 Environment

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_PROFILE`** | bool | no | `false` | Let `dybatpho::profile_start` time every function |

### 🚀 Highlights

- [`dybatpho::profile_begin`](#dybatphoprofile_begin) — Start timing a block. Blocks nest: one begun inside another is counted in the outer block's total and not in its self time.
- [`dybatpho::profile_end`](#dybatphoprofile_end) — Stop timing the innermost open block, which must be the one named.
- [`dybatpho::profile_run`](#dybatphoprofile_run) — Run a command inside a block, ending the block whatever the command returns.
- [`dybatpho::profile_start`](#dybatphoprofile_start) — Time every function from now on, each as a block of its name, until `dybatpho::profile_stop`. A `DEBUG` trap does the timing, so every command costs more while it runs; it does nothing unless `DYBATPHO_PROFILE` is true-like, and it needs Bash 5's `EPOCHREALTIME`.
- [`dybatpho::profile_stop`](#dybatphoprofile_stop) — Stop timing every function, end the blocks it opened, and put back the `functrace` setting the caller had and its `DEBUG` trap. Bash shows a function the caller's `DEBUG` trap only when `functrace` is on, as under Bats: a trap set without it cannot be saved, and is cleared.
- [`dybatpho::profile_report`](#dybatphoprofile_report) — Print the recorded blocks: name, calls, total and self time in milliseconds, the most self time first, then by name. Blocks still open are not counted.
- [`dybatpho::profile_reset`](#dybatphoprofile_reset) — Forget every recorded block and every open one.

<a id="usage"></a>

## 🚀 Usage

### Time the blocks you suspect

```bash
dybatpho::profile_begin "load config"
load_config
dybatpho::profile_end "load config"
dybatpho::profile_run sync -- sync_all
dybatpho::profile_report
```

### Time every function, for one run

```bash
dybatpho::profile_start   # only with DYBATPHO_PROFILE=true
main "$@"
dybatpho::profile_stop
dybatpho::profile_report
```

<a id="see-also"></a>

## 🔗 See also

- [example/profile_ops.sh](../example/profile_ops.sh)

<a id="reference"></a>

## 📚 Reference

### `dybatpho::profile_begin`

Start timing a block. Blocks nest: one begun inside another is
counted in the outer block's total and not in its self time.

**🧪 Example**

```bash
dybatpho::profile_begin "load config"
load_config
dybatpho::profile_end "load config"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Block name |

---

### `dybatpho::profile_end`

Stop timing the innermost open block, which must be the one named.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Block name |

**🚦 Exit codes**

- `1`: Stop script when no block is open, or the innermost is another one

---

### `dybatpho::profile_run`

Run a command inside a block, ending the block whatever the
command returns.

**🧪 Example**

```bash
dybatpho::profile_run sync -- rsync -a src/ dest/

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Block name |
| `$2` | string | Literal `--` |
| `$@` | string | Command and its arguments |

**🚦 Exit codes**

- `other`: Exit code of the command

---

### `dybatpho::profile_start`

Time every function from now on, each as a block of its name,
until `dybatpho::profile_stop`. A `DEBUG` trap does the timing, so every
command costs more while it runs; it does nothing unless
`DYBATPHO_PROFILE` is true-like, and it needs Bash 5's `EPOCHREALTIME`.

**🧪 Example**

```bash
DYBATPHO_PROFILE=true ./deploy.sh   # deploy.sh calls profile_start ... profile_stop

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_PROFILE`** | bool | no | `false` | Turn per-function timing on |

**📤 Output on stderr**

- A warning when it was asked for on a Bash without `EPOCHREALTIME`

---

### `dybatpho::profile_stop`

Stop timing every function, end the blocks it opened, and put
back the `functrace` setting the caller had and its `DEBUG` trap.
Bash shows a function the caller's `DEBUG` trap only when `functrace` is
on, as under Bats: a trap set without it cannot be saved, and is cleared.

_Function has no arguments._

---

### `dybatpho::profile_report`

Print the recorded blocks: name, calls, total and self time in
milliseconds, the most self time first, then by name. Blocks still open are
not counted.

**🧪 Example**

```bash
dybatpho::profile_report
dybatpho::profile_report --tsv > profile.tsv

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | [optional] `--tsv` for tab-separated rows with a header, instead of an aligned table |

**📤 Output on stdout**

- The report

---

### `dybatpho::profile_reset`

Forget every recorded block and every open one.

_Function has no arguments._
