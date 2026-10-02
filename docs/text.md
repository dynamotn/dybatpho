# text.sh

Utilities for working with multi-line text blocks

> 🧭 Source: [src/text.sh](../src/text.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for formatting larger text blocks: indenting
each line, removing shared indentation, stripping ANSI escape sequences,
turning lines into bullet lists, aligning simple delimited columns,
drawing a border around a block, centering lines, numbering them, and
cutting a long block short. It is useful when shell scripts need to prepare
readable console output, embed heredocs, or normalize text before writing
files.

The helpers that pad or center measure each line by what a terminal shows:
ANSI escape sequences count for nothing, and when the `screen` module is
loaded its Unicode-aware measurement is used, so a CJK character or an emoji
counts for the two columns it occupies. Without `screen`, a line is measured
by its character count, which is exact for every character one column wide.

### 🚀 Highlights

- [`dybatpho::text_indent`](#dybatphotext_indent) — Prefix every line in a text block with the given indent string.
- [`dybatpho::text_dedent`](#dybatphotext_dedent) — Remove the shared leading indentation from a text block.
- [`dybatpho::text_strip_ansi`](#dybatphotext_strip_ansi) — Strip ANSI escape sequences from a text block.
- [`dybatpho::text_bullet_list`](#dybatphotext_bullet_list) — Prefix each non-empty line in a text block as a bullet item.
- [`dybatpho::text_columns`](#dybatphotext_columns) — Align a delimited text block into plain columns.
- [`dybatpho::text_box`](#dybatphotext_box) — Draw a border around a text block, with an optional title set into the top edge. The box is as wide as the widest line or the title, whichever is wider, with one space of padding on each side. Lines are padded by their visible width, so colored text and, with the `screen` module loaded, wide characters keep the right edge straight.
- [`dybatpho::text_center`](#dybatphotext_center) — Center each line of a text block within a width. Lines are padded on the left only, so no trailing whitespace is added. When the padding cannot be split evenly, the extra column goes to the right. A line at least as wide as the width is printed unchanged, and a blank line stays blank. Widths are measured as `dybatpho::text_box` measures them.
- [`dybatpho::text_number_lines`](#dybatphotext_number_lines) — Prefix each line of a text block with its line number. Numbers are right-aligned to the width of the last one, so a block of ten or more lines keeps its text in one column. Blank lines are numbered too.
- [`dybatpho::text_truncate_lines`](#dybatphotext_truncate_lines) — Keep the first lines of a text block and say how many were left out. A block that already fits is printed unchanged, with no marker. Otherwise the first `count` lines are printed, followed by a marker line. The default marker reads `… 1 more line` or `… N more lines`; a custom marker has every `{count}` replaced by the number of lines left out.

<a id="see-also"></a>
## 🔗 See also

- [example/text_ops.sh](../example/text_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::text_indent`

Prefix every line in a text block with the given indent string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | string | Optional indent prefix, default is two spaces |

**📤 Output on stdout**

- Indented text block


---

### `dybatpho::text_dedent`

Remove the shared leading indentation from a text block.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |

**📤 Output on stdout**

- Dedented text block


---

### `dybatpho::text_strip_ansi`

Strip ANSI escape sequences from a text block.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |

**📤 Output on stdout**

- Text without ANSI color/control sequences


---

### `dybatpho::text_bullet_list`

Prefix each non-empty line in a text block as a bullet item.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | string | Optional bullet marker, default is `-` |

**📤 Output on stdout**

- Bullet-formatted text block


---

### `dybatpho::text_columns`

Align a delimited text block into plain columns.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | string | Optional exact delimiter, default is `\|` |
| `$3` | number | Optional gap width between columns, default is 2 |

**📤 Output on stdout**

- Plain aligned columns


---

### `dybatpho::text_box`

Draw a border around a text block, with an optional title set
into the top edge.
The box is as wide as the widest line or the title, whichever is wider,
with one space of padding on each side. Lines are padded by their visible
width, so colored text and, with the `screen` module loaded, wide
characters keep the right edge straight.

**🧪 Example**

```bash
dybatpho::text_box $'alpha\nbeta' "Notes"
# ┌─ Notes ─┐
# │ alpha   │
# │ beta    │
# └─────────┘

dybatpho::text_box "plain" "" ascii
# +-------+
# | plain |
# +-------+
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | string | Optional title shown in the top border, default is none |
| `$3` | string | Optional border style: `single` (default), `double`, `rounded`, `heavy`, or `ascii` |

**📤 Output on stdout**

- The boxed text block

**🚦 Exit codes**

- `1`: The border style is unknown


---

### `dybatpho::text_center`

Center each line of a text block within a width.
Lines are padded on the left only, so no trailing whitespace is added. When
the padding cannot be split evenly, the extra column goes to the right. A
line at least as wide as the width is printed unchanged, and a blank line
stays blank. Widths are measured as `dybatpho::text_box` measures them.

**🧪 Example**

```bash
dybatpho::text_center $'title\nsubtitle here' 20
#        title
#    subtitle here
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | number | Optional width to center within, default is the terminal width |

**📤 Output on stdout**

- The centered text block

**🚦 Exit codes**

- `1`: The width is not a positive integer


---

### `dybatpho::text_number_lines`

Prefix each line of a text block with its line number.
Numbers are right-aligned to the width of the last one, so a block of ten
or more lines keeps its text in one column. Blank lines are numbered too.

**🧪 Example**

```bash
dybatpho::text_number_lines $'alpha\nbeta'
# 1  alpha
# 2  beta

dybatpho::text_number_lines $'alpha\nbeta' 9 ": "
#  9: alpha
# 10: beta
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | number | Optional number of the first line, default is `1` |
| `$3` | string | Optional separator between number and text, default is two spaces |

**📤 Output on stdout**

- The numbered text block

**🚦 Exit codes**

- `1`: The first line number is not a non-negative integer


---

### `dybatpho::text_truncate_lines`

Keep the first lines of a text block and say how many were left
out.
A block that already fits is printed unchanged, with no marker. Otherwise
the first `count` lines are printed, followed by a marker line. The default
marker reads `… 1 more line` or `… N more lines`; a custom marker has every
`{count}` replaced by the number of lines left out.

**🧪 Example**

```bash
dybatpho::text_truncate_lines $'one\ntwo\nthree\nfour' 2
# one
# two
# … 2 more lines

git log --oneline | dybatpho::text_truncate_lines - 5 "(+{count} commits)"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | number | Number of lines to keep |
| `$3` | string | Optional marker template, `{count}` is replaced by the number of lines left out |

**📤 Output on stdout**

- The kept lines and, when lines were left out, the marker

**🚦 Exit codes**

- `1`: The count is not a non-negative integer
