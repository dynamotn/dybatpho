# diff.sh

Utilities for comparing text and structured documents

> 🧭 Source: [src/diff.sh](../src/diff.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Showing a user what changed is something scripts keep doing and keep doing
differently: one shells out to `diff` with its own flags, another to `jq`,
and a snapshot assertion dumps whatever `diff -u` printed. This module is
the one place that answers it.

The text diff is a unified diff colored by this module rather than by
`diff --color`, which only GNU has. The comparison itself uses `diff -u`,
which GNU, BSD and BusyBox all understand, so the output is the same
wherever the script runs.

The structured diffs answer a different question. A line diff of
reformatted JSON is noise; what a reader wants is which keys were added,
removed, or given a new value. Both documents are flattened to
`path<TAB>value` pairs and compared by path, so reordering a document
changes nothing and a moved key is not reported as a rewrite.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DIFF_COLOR`** | string | Force color on or off; the default follows `NO_COLOR` and whether stdout is a terminal |
| **`DYBATPHO_DIFF_CONTEXT`** | number | Lines of context in a text diff, default is `3` |
| **`DYBATPHO_DIFF_CONTEXT`** | number | Lines of context around each change, default is `3` |
| **`DYBATPHO_DIFF_COLOR`** | string | `true` or `false` to decide coloring, empty to detect it |

### 🚀 Highlights

- [`__dybatpho_diff_wants_color`](#__dybatpho_diff_wants_color) — Return success when the output should carry ANSI color. `DYBATPHO_DIFF_COLOR` decides when it is set, which is what lets a test assert on colored output without a terminal; otherwise `NO_COLOR` and whether stdout is a terminal do.
- [`__dybatpho_diff_side_into`](#__dybatpho_diff_side_into) — Resolve one side of a comparison to a file, into a named variable. `-` is stdin, an existing file is itself, and anything else is text, which is written to a temporary file so `diff` has two paths to compare either way.
- [`__dybatpho_diff_paint`](#__dybatpho_diff_paint) — Print a unified diff line with the color its prefix calls for.
- [`dybatpho::diff_text`](#dybatphodiff_text) — Compare two texts and print a colored unified diff. The exit code is `diff`'s own, so the call reads as a question in a conditional: zero when the two are identical, one when they are not.
- [`dybatpho::diff_summary`](#dybatphodiff_summary) — Summarize a text comparison as one line. `~K` counts hunks, not changed lines: a unified diff records a rewritten line as one removal and one addition, so calling that a change as well would count it twice.
- [`__dybatpho_diff_flatten`](#__dybatpho_diff_flatten) — Flatten a JSON document to sorted `path<TAB>value` lines.
- [`dybatpho::diff_json`](#dybatphodiff_json) — Compare two JSON documents by key rather than by line. A reordered or reformatted document reports no change, because the comparison is between the values at each path.
- [`__dybatpho_diff_report`](#__dybatpho_diff_report) — Print one structural difference.
- [`dybatpho::diff_yaml`](#dybatphodiff_yaml) — Compare two YAML documents by key rather than by line. Both are converted to JSON first, so anchors, quoting style and key order are not reported as changes.

<a id="see-also"></a>
## 🔗 See also

- [example/diff_ops.sh](../example/diff_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Every comparison takes a file path, `-` for stdin, or the text itself, and only one side can be stdin
- A side that names an existing file is read as that file. Text that could itself be a path -- a command's output, say -- belongs in a file first, or the wrong thing gets compared
- `dybatpho::diff_text` needs no external command; the structured diffs need `jq`, and `dybatpho::diff_yaml` needs `yq` to reach JSON first

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_diff_wants_color`

Return success when the output should carry ANSI color.
`DYBATPHO_DIFF_COLOR` decides when it is set, which is what lets a test
assert on colored output without a terminal; otherwise `NO_COLOR` and
whether stdout is a terminal do.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Color should be emitted
- `1`: It should not


---

### `__dybatpho_diff_side_into`

Resolve one side of a comparison to a file, into a named
variable. `-` is stdin, an existing file is itself, and anything else is
text, which is written to a temporary file so `diff` has two paths to
compare either way.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the path |
| `$2` | string | File path, `-`, or text |
| `$3` | string | Label used in the diff header |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_diff_paint`

Print a unified diff line with the color its prefix calls for.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | One line of unified diff output |
| `$2` | string | `1` to color, `0` to print plain |

**📤 Output on stdout**

- The line


---

### `dybatpho::diff_text`

Compare two texts and print a colored unified diff.
The exit code is `diff`'s own, so the call reads as a question in a
conditional: zero when the two are identical, one when they are not.

**🧪 Example**

```bash
dybatpho::diff_text /etc/nginx/nginx.conf "${rendered}" current proposed
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path, `-` for stdin, or text |
| `$2` | string | File path, `-` for stdin, or text |
| `$3` | string | Optional label for the first side, default is its path |
| `$4` | string | Optional label for the second side, default is its path |

**📤 Output on stdout**

- A unified diff, empty when the two are identical

**🚦 Exit codes**

- `0`: The two are identical
- `1`: They differ


---

### `dybatpho::diff_summary`

Summarize a text comparison as one line.
`~K` counts hunks, not changed lines: a unified diff records a rewritten
line as one removal and one addition, so calling that a change as well
would count it twice.

**🧪 Example**

```bash
dybatpho::diff_summary "${before}" "${after}" || true
# +12 -3 ~4
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path, `-` for stdin, or text |
| `$2` | string | File path, `-` for stdin, or text |

**📤 Output on stdout**

- `+N -M ~K`: lines added, lines removed, and hunks touched

**🚦 Exit codes**

- `0`: The two are identical
- `1`: They differ


---

### `__dybatpho_diff_flatten`

Flatten a JSON document to sorted `path<TAB>value` lines.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path |

**📤 Output on stdout**

- One line per scalar, sorted by path

**🚦 Exit codes**

- `0`: The document was flattened
- `1`: The document is not valid JSON


---

### `dybatpho::diff_json`

Compare two JSON documents by key rather than by line.
A reordered or reformatted document reports no change, because the
comparison is between the values at each path.

**🧪 Example**

```bash
dybatpho::diff_json old-state.json new-state.json
# ~ replicas: 2 -> 3
# + labels.tier = "web"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path, `-` for stdin, or JSON text |
| `$2` | string | JSON file path, `-` for stdin, or JSON text |

**📤 Output on stdout**

- One line per difference: `+ path = value`, `- path = value`, or `~ path: old -> new`

**🚦 Exit codes**

- `0`: The two documents hold the same values
- `1`: They differ
- `127`: `jq` is not installed


---

### `__dybatpho_diff_report`

Print one structural difference.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | `1` to color, `0` to print plain |
| `$2` | string | Kind: `added`, `removed`, or `changed` |
| `$3` | string | Path |
| `$4` | string | Value, or the old value for a change |
| `$5` | string | New value, for a change |

**📤 Output on stdout**

- The formatted line


---

### `dybatpho::diff_yaml`

Compare two YAML documents by key rather than by line.
Both are converted to JSON first, so anchors, quoting style and key order
are not reported as changes.

**🧪 Example**

```bash
dybatpho::diff_yaml deploy-old.yaml deploy-new.yaml
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path, `-` for stdin, or YAML text |
| `$2` | string | YAML file path, `-` for stdin, or YAML text |

**📤 Output on stdout**

- One line per difference, in the form `dybatpho::diff_json` prints

**🚦 Exit codes**

- `0`: The two documents hold the same values
- `1`: They differ
- `127`: `jq` or `yq` is not installed
