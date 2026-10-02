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

The tree diff walks two directories and reports each entry that was added,
removed, rewritten, or changed kind, comparing files by content and links
by target, so a copy with fresh timestamps is no change and a link is never
followed into whatever it points at.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DIFF_COLOR`** | string | Force color on or off; the default follows `NO_COLOR` and whether stdout is a terminal |
| **`DYBATPHO_DIFF_CONTEXT`** | number | Lines of context in a text diff, default is `3` |
| **`DYBATPHO_DIFF_CONTEXT`** | number | Lines of context around each change, default is `3` |
| **`DYBATPHO_DIFF_COLOR`** | string | `true` or `false` to decide coloring, empty to detect it |

### 🚀 Highlights

- [`dybatpho::diff_text`](#dybatphodiff_text) — Compare two texts and print a colored unified diff. The exit code is `diff`'s own, so the call reads as a question in a conditional: zero when the two are identical, one when they are not.
- [`dybatpho::diff_summary`](#dybatphodiff_summary) — Summarize a text comparison as one line. `~K` counts hunks, not changed lines: a unified diff records a rewritten line as one removal and one addition, so calling that a change as well would count it twice.
- [`dybatpho::diff_json`](#dybatphodiff_json) — Compare two JSON documents by key rather than by line. A reordered or reformatted document reports no change, because the comparison is between the values at each path.
- [`dybatpho::diff_yaml`](#dybatphodiff_yaml) — Compare two YAML documents by key rather than by line. Both are converted to JSON first, so anchors, quoting style and key order are not reported as changes.
- [`dybatpho::diff_dir`](#dybatphodiff_dir) — Compare two directory trees entry by entry. Every path under either root is reported once, sorted bytewise so the output is the same on every machine: - `+ path` exists only in the second tree; - `- path` exists only in the first; - `~ path` is a file whose content differs, or a symbolic link whose target differs; - `! path: file -> directory` changed kind between the two trees. A directory's path carries a trailing `/` when it is added or removed, and the entries inside it are reported too, so a removed directory reads as the whole of what went with it. Files are compared by content with `cmp`, so a copy with a new modification time is no change; permissions and ownership are not compared. Symbolic links are compared by target and never followed, so a link into a large tree does not drag that tree in. A path holding a backslash, newline, tab, or carriage return is written with C escapes so each record stays on one line; `--null` prints each record raw and NUL-terminated instead, for a reader that needs the exact name.

<a id="see-also"></a>
## 🔗 See also

- [example/diff_ops.sh](../example/diff_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Every text and document comparison takes a file path, `-` for stdin, or the text itself, and only one side can be stdin
- A side that names an existing file is read as that file. Text that could itself be a path -- a command's output, say -- belongs in a file first, or the wrong thing gets compared
- `dybatpho::diff_dir` takes two directories and needs only `find`, `cmp` and `sort`
- `dybatpho::diff_text` needs no external command; the structured diffs need `jq`, and `dybatpho::diff_yaml` needs `yq` to reach JSON first

<a id="reference"></a>
## 📚 Reference

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


---

### `dybatpho::diff_dir`

Compare two directory trees entry by entry.
Every path under either root is reported once, sorted bytewise so the
output is the same on every machine:

- `+ path` exists only in the second tree;
- `- path` exists only in the first;
- `~ path` is a file whose content differs, or a symbolic link whose target
  differs;
- `! path: file -> directory` changed kind between the two trees.

A directory's path carries a trailing `/` when it is added or removed, and
the entries inside it are reported too, so a removed directory reads as
the whole of what went with it. Files are compared by content with `cmp`,
so a copy with a new modification time is no change; permissions and
ownership are not compared. Symbolic links are compared by target and never
followed, so a link into a large tree does not drag that tree in.

A path holding a backslash, newline, tab, or carriage return is written
with C escapes so each record stays on one line; `--null` prints each
record raw and NUL-terminated instead, for a reader that needs the exact
name.

**🧪 Example**

```bash
dybatpho::diff_dir ./release-1.2 ./release-1.3
# + bin/new-tool
# - share/old.conf
# ~ etc/app.conf
# ! lib/plugins: file -> directory
dybatpho::diff_dir --summary ./release-1.2 ./release-1.3   # +1 -1 ~2
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Options, then the first directory |
| `$2` | string | Second directory |

**📤 Output on stdout**

- One record per difference, or the summary line

**🚦 Exit codes**

- `0`: The two trees hold the same entries with the same content
- `1`: They differ
- `2`: Either side is not a directory
