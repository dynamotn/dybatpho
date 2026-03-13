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

### 🚀 Highlights

- [`__table_cell_width`](#__table_cell_width) — Return the display width of a table cell.
- [`__table_pad`](#__table_pad) — Pad a cell to the requested display width.
- [`__table_split_row`](#__table_split_row) — Split one delimited row into trimmed cells.
- [`__table_measure_widths`](#__table_measure_widths) — Measure the widest cell in each column across all rows.
- [`__table_parse_alignments`](#__table_parse_alignments) — Normalize a per-column alignment specification.
- [`__table_format_cell`](#__table_format_cell) — Format a cell according to width and alignment.
- [`_table_rule`](#_table_rule) — Print a Unicode rule line for a boxed table.
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

### `__table_cell_width`

Return the display width of a table cell.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cell text |

**📤 Output on stdout**

- Cell width


---

### `__table_pad`

Pad a cell to the requested display width.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cell text |
| `$2` | number | Target width |

**📤 Output on stdout**

- Right-padded cell text


---

### `__table_split_row`

Split one delimited row into trimmed cells.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Row text |
| `$2` | string | Exact delimiter |
| `$3` | string | Name of the array variable to fill |


---

### `__table_measure_widths`

Measure the widest cell in each column across all rows.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the row array variable |
| `$2` | string | Exact delimiter |
| `$3` | string | Name of the width array variable to fill |


---

### `__table_parse_alignments`

Normalize a per-column alignment specification.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Comma-separated alignments (`left,right,center`) |
| `$2` | string | Name of the widths array variable |
| `$3` | string | Name of the alignments array variable to fill |


---

### `__table_format_cell`

Format a cell according to width and alignment.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cell text |
| `$2` | number | Target width |
| `$3` | string | Alignment (`left`, `right`, `center`) |

**📤 Output on stdout**

- Formatted cell text


---

### `_table_rule`

Print a Unicode rule line for a boxed table.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Left corner character |
| `$2` | string | Join character |
| `$3` | string | Right corner character |
| `$4` | string | Name of the widths array variable |

**📤 Output on stdout**

- Rendered rule line


---

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

