# table.sh

Utilities for rendering aligned plain-text tables

> 🧭 Source: [src/table.sh](../src/table.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for rendering delimited row data as aligned
plain text, Unicode boxed tables, or Markdown tables. It also supports
explicit plain-table alignment rules and lightweight CSV rendering. It
targets small script-generated tables where readability matters more than
strict CSV parsing.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TABLE_CSV_STRICT`** | bool | Refuse input whose fields are quoted, rather than splitting through the quotes. Default `true` |

### 🚀 Highlights

- [`dybatpho::table_print`](#dybatphotable_print) — Render aligned columns without borders from delimited rows.
- [`dybatpho::table_align`](#dybatphotable_align) — Render aligned columns with optional per-column alignment rules.
- [`dybatpho::table_box`](#dybatphotable_box) — Render a Unicode boxed table from delimited rows.
- [`dybatpho::table_markdown`](#dybatphotable_markdown) — Render a Markdown table from delimited rows.
- [`dybatpho::table_csv`](#dybatphotable_csv) — Render lightweight comma-delimited table data using one of the supported styles.

<a id="see-also"></a>
## 🔗 See also

- [example/table_ops.sh](../example/table_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Rows are provided as a single multi-line string (or stdin with `-`), and cells are split on an exact delimiter such as `|`, `,`, or `::`

<a id="reference"></a>
## 📚 Reference

### `dybatpho::table_print`

Render aligned columns without borders from delimited rows.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text block or `-` for stdin |
| `$2` | string | Optional exact delimiter, default is `\|` |

**📤 Output on stdout**

- Aligned plain-text table


---

### `dybatpho::table_align`

Render aligned columns with optional per-column alignment rules.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text block or `-` for stdin |
| `$2` | string | Optional exact delimiter, default is `\|` |
| `$3` | string | Optional comma-separated alignments (`left,right,center`) |
| `$4` | number | Optional gap width between columns, default is 2 |

**📤 Output on stdout**

- Aligned plain-text table


---

### `dybatpho::table_box`

Render a Unicode boxed table from delimited rows.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text block or `-` for stdin |
| `$2` | string | Optional exact delimiter, default is `\|` |

**📤 Output on stdout**

- Boxed Unicode table


---

### `dybatpho::table_markdown`

Render a Markdown table from delimited rows.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input text block or `-` for stdin |
| `$2` | string | Optional exact delimiter, default is `\|` |

**📤 Output on stdout**

- Markdown table using the first row as the header


---

### `dybatpho::table_csv`

Render lightweight comma-delimited table data using one of the supported styles.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Input CSV-like text block or `-` for stdin |
| `$2` | string | Optional style: `plain`, `box`, or `markdown`, default is `plain` |
| `$3` | string | Optional comma-separated alignments for `plain` style |

**📤 Output on stdout**

- Rendered table
