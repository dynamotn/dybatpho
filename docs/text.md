# text.sh

Utilities for working with multi-line text blocks

> 🧭 Source: [src/text.sh](../src/text.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

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
ANSI escape sequences count for nothing, and the library's built-in Unicode
tables give a CJK character or an emoji the two columns it occupies and a
combining mark none -- the same measure `table`, `screen` and the boxed log
helpers use.

### 🚀 Highlights

- [`dybatpho::text_indent`](#dybatphotext_indent) — Prefix every line in a text block with the given indent string.
- [`dybatpho::text_dedent`](#dybatphotext_dedent) — Remove the shared leading indentation from a text block.
- [`dybatpho::text_strip_ansi`](#dybatphotext_strip_ansi) — Strip ANSI escape sequences from a text block.
- [`dybatpho::text_sanitize`](#dybatphotext_sanitize) — Make text that is not trusted -- from another process, a file, the network -- safe to print to a terminal. Escape sequences are removed whole, then every character that can move the cursor, rewrite a line, or change what the reader sees without being seen: C0 controls other than tab (carriage return included), DEL, C1 controls, bidirectional controls, zero-width characters, the byte-order mark and Unicode tag characters, over and over until none is left, since removing one can join its neighbours into another -- at most four rounds, after which input nested that deep loses every byte from 0x80 up. Lines stay lines; printable text, tabs and other Unicode are kept. A caller's `nocasematch` does not change it. The caller's locale says what the terminal reads. Under UTF-8, bytes that cannot be part of a character which is a control (a C1 byte at the start or after ASCII, an overlong form) are removed too, and an 8-bit introducer such as U+009B is read as the sequence it opens; a C1 byte after another non-ASCII byte is left, which a UTF-8 terminal shows as U+FFFD. Under any other locale, every byte 0x80-0x9F is removed, since an 8-bit terminal obeys it as a C1 control -- UTF-8 text then loses those bytes, so run under a UTF-8 locale to keep it.
- [`dybatpho::text_bullet_list`](#dybatphotext_bullet_list) — Prefix each non-empty line in a text block as a bullet item.
- [`dybatpho::text_columns`](#dybatphotext_columns) — Align a delimited text block into plain columns. The columns are laid out by `dybatpho::table_align`, so the `table` module is loaded on demand the first time this runs; name it up front to load it once.
- [`dybatpho::text_box`](#dybatphotext_box) — Draw a border around a text block, with an optional title set into the top edge. The box is as wide as the widest line or the title, whichever is wider, with one space of padding on each side. Lines are padded by their visible width, so colored text and wide characters keep the right edge straight.
- [`dybatpho::text_center`](#dybatphotext_center) — Center each line of a text block within a width. Lines are padded on the left only, so no trailing whitespace is added. When the padding cannot be split evenly, the extra column goes to the right. A line at least as wide as the width is printed unchanged, and a blank line stays blank. Widths are measured as `dybatpho::text_box` measures them.
- [`dybatpho::text_number_lines`](#dybatphotext_number_lines) — Prefix each line of a text block with its line number. Numbers are right-aligned to the width of the last one, so a block of ten or more lines keeps its text in one column. Blank lines are numbered too.
- [`dybatpho::text_truncate_lines`](#dybatphotext_truncate_lines) — Keep the first lines of a text block and say how many were left out. A block that already fits is printed unchanged, with no marker. Otherwise the first `count` lines are printed, followed by a marker line. The default marker reads `… 1 more line` or `… N more lines`; a custom marker has every `{count}` replaced by the number of lines left out.

<a id="see-also"></a>

## 🔗 See also

- [example/text_ops.sh](../example/text_ops.sh)

<a id="tips"></a>

## 💡 Tips

**[`dybatpho::text_sanitize`](#dybatphotext_sanitize)**

- Use it on anything a peer, a file or a remote wrote before showing it; `text_strip_ansi` alone keeps a bare carriage return or a right-to-left override that can disguise a line

<a id="reference"></a>

## 📚 Reference

### `dybatpho::text_indent`

Prefix every line in a text block with the given indent string.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | string | no |  | Indent prefix, default is two spaces |

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

### `dybatpho::text_sanitize`

Make text that is not trusted -- from another process, a file,
the network -- safe to print to a terminal. Escape sequences are removed
whole, then every character that can move the cursor, rewrite a line, or
change what the reader sees without being seen: C0 controls other than tab
(carriage return included), DEL, C1 controls, bidirectional controls,
zero-width characters, the byte-order mark and Unicode tag characters,
over and over until none is left, since removing one can join its
neighbours into another -- at most four rounds, after which input nested
that deep loses every byte from 0x80 up. Lines stay lines; printable text,
tabs and other Unicode are kept. A caller's `nocasematch` does not change it.

The caller's locale says what the terminal reads. Under UTF-8, bytes that
cannot be part of a character which is a control (a C1 byte at the start or
after ASCII, an overlong form) are removed too, and an 8-bit introducer such
as U+009B is read as the sequence it opens; a C1 byte after another
non-ASCII byte is left, which a UTF-8 terminal shows as U+FFFD. Under any other locale,
every byte 0x80-0x9F is removed, since an 8-bit terminal obeys it as a C1
control -- UTF-8 text then loses those bytes, so run under a UTF-8 locale to
keep it.

**🧪 Example**

```bash
dybatpho::text_sanitize "$(< "${peer_log}")" 2000

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | number | no |  | Largest number of characters to print, line breaks between lines included; characters as the caller's locale counts them, so bytes under `C` |

**📝 Notes**

- Bash's pattern substitution makes the time grow faster than a line's length: a line of 12000 escape sequences takes about a second; split or bound very long input before sanitizing it

**📤 Output on stdout**

- The text without those characters

---

### `dybatpho::text_bullet_list`

Prefix each non-empty line in a text block as a bullet item.

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | string | no | `-` | Bullet marker |

**📤 Output on stdout**

- Bullet-formatted text block

---

### `dybatpho::text_columns`

Align a delimited text block into plain columns.
The columns are laid out by `dybatpho::table_align`, so the `table` module
is loaded on demand the first time this runs; name it up front to load it
once.

**🧪 Example**

```bash
. dybatpho/init.sh --modules text table
dybatpho::text_columns $'name|version\ndybatpho|6.0.0'

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | string | no | `\|` | Exact delimiter |
| `$3` | number | no | `2` | Gap width between columns |

**📤 Output on stdout**

- Plain aligned columns

**🚦 Exit codes**

- `1`: Stop the script when the `table` module cannot be loaded on demand

---

### `dybatpho::text_box`

Draw a border around a text block, with an optional title set
into the top edge.
The box is as wide as the widest line or the title, whichever is wider,
with one space of padding on each side. Lines are padded by their visible
width, so colored text and wide characters keep the right edge straight.

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

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | string | no |  | Title shown in the top border, default is none |
| `$3` | string | no |  | Border style: `single` (default), `double`, `rounded`, `heavy`, or `ascii` |

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

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | number | no |  | Width to center within, default is the terminal width |

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

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | number | no | `1` | Number of the first line |
| `$3` | string | no |  | Separator between number and text, default is two spaces |

**📤 Output on stdout**

- The numbered text block

**🚦 Exit codes**

- `1`: The first line number is not an integer from 0 to 9223372036854775807

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

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Input text or `-` for stdin |
| `$2` | number | yes |  | Number of lines to keep |
| `$3` | string | no |  | Marker template, `{count}` is replaced by the number of lines left out |

**📤 Output on stdout**

- The kept lines and, when lines were left out, the marker

**🚦 Exit codes**

- `1`: The count is not an integer from 0 to 9223372036854775807
