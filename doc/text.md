# text.sh

Utilities for working with multi-line text blocks

> 🧭 Source: [src/text.sh](../src/text.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for formatting larger text blocks: indenting
each line, removing shared indentation, stripping ANSI escape sequences,
turning lines into bullet lists, and aligning simple delimited columns. It
is useful when shell scripts need to prepare readable console output, embed
heredocs, or normalize text before writing files.

### 🚀 Highlights

- [`__text_read_lines`](#__text_read_lines) — Read a text argument or stdin into a target array of lines.
- [`dybatpho::text_indent`](#dybatphotext_indent) — Prefix every line in a text block with the given indent string.
- [`dybatpho::text_dedent`](#dybatphotext_dedent) — Remove the shared leading indentation from a text block.
- [`dybatpho::text_strip_ansi`](#dybatphotext_strip_ansi) — Strip ANSI escape sequences from a text block.
- [`dybatpho::text_bullet_list`](#dybatphotext_bullet_list) — Prefix each non-empty line in a text block as a bullet item.
- [`dybatpho::text_columns`](#dybatphotext_columns) — Align a delimited text block into plain columns.

<a id="see-also"></a>
## 🔗 See also

- [example/text_ops.sh](../example/text_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `__text_read_lines`

Read a text argument or stdin into a target array of lines.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text or `-` for stdin |
| `$2` | string | Name of the array variable to fill |


---

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

