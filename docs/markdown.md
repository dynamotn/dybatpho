# markdown.sh

Utilities for building structured Markdown content

> 🧭 Source: [src/markdown.sh](../src/markdown.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains builders for the pieces a generated document is made
of: headings, lists, task lists, links, badges, fenced code blocks, tables,
and collapsible sections. It exists because a script that assembles a
report, a pull request description, or a release note otherwise
concatenates Markdown by hand, and an interpolated value containing `*`,
`_`, `[` or `|` then renders as formatting rather than as the text it was.

**Every builder escapes the text it is given.** A value read from a commit
message, a filename, or a command's output is therefore safe to pass
straight in. To embed Markdown that is already formatted -- a link built by
another call, a bold run of your own -- wrap it in `dybatpho::md_raw`,
which marks the fragment so the surrounding escape leaves it alone. The
exceptions are documented per function: a fenced code block's body is
literal by definition, and a collapsible section's body is the Markdown the
caller already built.

Output goes to stdout one block at a time, so blocks compose through
command substitution and ordinary concatenation rather than through a
document object.

### 🚀 Highlights

- [`dybatpho::md_raw`](#dybatphomd_raw) — Mark text as Markdown that is already formatted, so a builder embeds it instead of escaping it. The marked text carries two control characters that every builder removes as it renders. Print it only through a builder: on its own it still holds them.
- [`dybatpho::md_escape`](#dybatphomd_escape) — Escape the Markdown-significant characters in a text block. The builders in this module already escape what they are given, so this is for Markdown a caller assembles itself. Passing its output to a builder escapes the text twice.
- [`dybatpho::md_heading`](#dybatphomd_heading) — Render an ATX heading.
- [`dybatpho::md_list`](#dybatphomd_list) — Render a bullet or ordered list, one item per input line. A marker of `1.` or `1)` numbers the items from that value; any other marker is used literally on every item. Blank input lines stay blank, so a list can be split into visual groups.
- [`dybatpho::md_task_list`](#dybatphomd_task_list) — Render a GitHub-flavored task list, one item per input line. Each line is `<state><delimiter><text>`; a line with no delimiter is an unchecked item whose text is the whole line. The state is checked for `x`, `X`, and anything `dybatpho::is true` accepts.
- [`dybatpho::md_link`](#dybatphomd_link) — Render an inline link.
- [`dybatpho::md_badge`](#dybatphomd_badge) — Render a shields.io badge as an image, optionally wrapped in a link. The label and value are encoded the way shields.io requires: `-` doubles, `_` doubles, and a space becomes `_`.
- [`dybatpho::md_code_block`](#dybatphomd_code_block) — Render a fenced code block. The body is literal by definition, so it is not escaped. The fence grows past the longest run of backticks the body contains, which is what keeps a block that itself shows fenced Markdown from ending early.
- [`dybatpho::md_table`](#dybatphomd_table) — Render a Markdown table through `table.sh`. Cells are passed through unescaped, because escaping them here would also escape the delimiter that separates them. Escape the values first with `dybatpho::md_escape` and assemble the rows with a delimiter of your own, such as `::`, which the escape leaves alone.
- [`dybatpho::md_collapsible`](#dybatphomd_collapsible) — Render a collapsible `<details>` section. The summary is escaped; the body is the Markdown the caller already built, so it is emitted as given. The blank lines around the body are what let a renderer treat it as Markdown rather than as raw HTML.
- [`dybatpho::md_mention`](#dybatphomd_mention) — Render a mention of a user or group. A leading `@` in the name is accepted and not doubled.
- [`dybatpho::md_emoji`](#dybatphomd_emoji) — Render an emoji shortcode. Surrounding colons are accepted and not doubled.

<a id="see-also"></a>
## 🔗 See also

- [example/markdown_ops.sh](../example/markdown_ops.sh)

<a id="tips"></a>
## 💡 Tips

- `dybatpho::md_table` renders through `table.sh`, so that module must be loaded for it; `markdown` does not load it, and every other builder needs only the core modules

<a id="reference"></a>
## 📚 Reference

### `dybatpho::md_raw`

Mark text as Markdown that is already formatted, so a builder
embeds it instead of escaping it.
The marked text carries two control characters that every builder removes
as it renders. Print it only through a builder: on its own it still holds
them.

**🧪 Example**

```bash
dybatpho::md_list "$(dybatpho::md_raw "$(dybatpho::md_link 'docs' 'https://example.com')")"
# - [docs](https://example.com)
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Markdown fragment, or `-` for stdin |

**📤 Output on stdout**

- The fragment, marked as raw


---

### `dybatpho::md_escape`

Escape the Markdown-significant characters in a text block.
The builders in this module already escape what they are given, so this is
for Markdown a caller assembles itself. Passing its output to a builder
escapes the text twice.

**🧪 Example**

```bash
dybatpho::md_escape 'release v2 [beta]'
# release v2 \[beta\]
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to escape, or `-` for stdin |

**📤 Output on stdout**

- Escaped text


---

### `dybatpho::md_heading`

Render an ATX heading.

**🧪 Example**

```bash
dybatpho::md_heading 2 "Release notes"
# ## Release notes
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Heading level, 1 to 6 |
| `$2` | string | Heading text |

**📤 Output on stdout**

- The heading line

**🚦 Exit codes**

- `0`: The heading is rendered


---

### `dybatpho::md_list`

Render a bullet or ordered list, one item per input line.
A marker of `1.` or `1)` numbers the items from that value; any other
marker is used literally on every item. Blank input lines stay blank, so a
list can be split into visual groups.

**🧪 Example**

```bash
dybatpho::md_list $'first\nsecond' "1."
# 1. first
# 2. second
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | List items, one per line, or `-` for stdin |
| `$2` | string | Optional marker, default is `-` |

**📤 Output on stdout**

- The rendered list


---

### `dybatpho::md_task_list`

Render a GitHub-flavored task list, one item per input line.
Each line is `<state><delimiter><text>`; a line with no delimiter is an
unchecked item whose text is the whole line. The state is checked for
`x`, `X`, and anything `dybatpho::is true` accepts.

**🧪 Example**

```bash
dybatpho::md_task_list $'x|Write the spec\n|Ship it'
# - [x] Write the spec
# - [ ] Ship it
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Task lines, or `-` for stdin |
| `$2` | string | Optional delimiter between state and text, default is `\|` |

**📤 Output on stdout**

- The rendered task list


---

### `dybatpho::md_link`

Render an inline link.

**🧪 Example**

```bash
dybatpho::md_link "the docs" "https://example.com/a b"
# [the docs](https://example.com/a%20b)
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Link text |
| `$2` | string | URL |
| `$3` | string | Optional title shown on hover |

**📤 Output on stdout**

- The rendered link


---

### `dybatpho::md_badge`

Render a shields.io badge as an image, optionally wrapped in a
link. The label and value are encoded the way shields.io requires: `-`
doubles, `_` doubles, and a space becomes `_`.

**🧪 Example**

```bash
dybatpho::md_badge "build" "passing" "green"
# ![build: passing](https://img.shields.io/badge/build-passing-green)
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Badge label, the left half |
| `$2` | string | Badge value, the right half |
| `$3` | string | Optional color, default is `blue` |
| `$4` | string | Optional URL the badge links to |

**📤 Output on stdout**

- The rendered badge


---

### `dybatpho::md_code_block`

Render a fenced code block.
The body is literal by definition, so it is not escaped. The fence grows
past the longest run of backticks the body contains, which is what keeps a
block that itself shows fenced Markdown from ending early.

**🧪 Example**

```bash
dybatpho::md_code_block bash 'ls -la'
# ```bash
# ls -la
# ```
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Language for the info string, empty for none |
| `$2` | string | Code, or `-` for stdin |

**📤 Output on stdout**

- The rendered code block


---

### `dybatpho::md_table`

Render a Markdown table through `table.sh`.
Cells are passed through unescaped, because escaping them here would also
escape the delimiter that separates them. Escape the values first with
`dybatpho::md_escape` and assemble the rows with a delimiter of your own,
such as `::`, which the escape leaves alone.

**🧪 Example**

```bash
. dybatpho/init.sh --modules markdown table
dybatpho::md_table $'Name::Role\nAlice::Dev' "::"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Rows, one per line, cells split on the delimiter, or `-` for stdin |
| `$2` | string | Optional delimiter, default is `\|` |

**📤 Output on stdout**

- The rendered table

**🚦 Exit codes**

- `0`: The table is rendered
- `1`: Stop the script when the `table` module is not loaded


---

### `dybatpho::md_collapsible`

Render a collapsible `<details>` section.
The summary is escaped; the body is the Markdown the caller already built,
so it is emitted as given. The blank lines around the body are what let a
renderer treat it as Markdown rather than as raw HTML.

**🧪 Example**

```bash
dybatpho::md_collapsible "Full log" "$(dybatpho::md_code_block '' "${log}")"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Summary line shown when collapsed |
| `$2` | string | Body, or `-` for stdin |

**📤 Output on stdout**

- The rendered section


---

### `dybatpho::md_mention`

Render a mention of a user or group.
A leading `@` in the name is accepted and not doubled.

**🧪 Example**

```bash
dybatpho::md_mention dynamotn
# @dynamotn
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Account name, with or without a leading `@` |

**📤 Output on stdout**

- The rendered mention


---

### `dybatpho::md_emoji`

Render an emoji shortcode.
Surrounding colons are accepted and not doubled.

**🧪 Example**

```bash
dybatpho::md_emoji rocket
# :rocket:
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Shortcode name, with or without surrounding colons |

**📤 Output on stdout**

- The rendered shortcode
