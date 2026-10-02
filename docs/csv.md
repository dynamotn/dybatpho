# csv.sh

Utilities for reading, filtering and writing CSV data

> 🧭 Source: [src/csv.sh](../src/csv.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module reads the tabular format ops scripts keep receiving --
spreadsheet exports, cloud billing reports, CI artifacts -- and it parses
the quoting that `awk -F,` and `cut -d,` get wrong. A field may contain the
delimiter, a doubled quote, or a line break, and none of them end the field.

`table.sh` renders comma-delimited text and says so: it splits on every
comma and refuses a quoted field rather than turning one into two columns.
This module is the parser that refusal points at. Render through
`table.sh` afterwards by writing the parsed rows back out with
`dybatpho::csv_write`.

Rows are exchanged as an array whose every element is one record, its
fields joined by the ASCII unit separator. Splitting a record is then a
single unambiguous operation, which is what `dybatpho::csv_fields` does.
Data containing that byte is rejected rather than silently re-split.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CSV_DELIMITER`** | string | Field delimiter, default is `,`; set it to `;`, or to `tab` for TSV |
| **`DYBATPHO_CSV_DELIMITER`** | string | Field delimiter every function reads, default is `,`; `tab` or `\t` names a tab |

### 🚀 Highlights

- [`dybatpho::csv_read`](#dybatphocsv_read) — Parse CSV into an array of records. Every element is one record whose fields are joined by the ASCII unit separator; `dybatpho::csv_fields` splits one back apart. Quoted fields are parsed the way RFC 4180 describes, so a delimiter, a doubled quote, or a line break inside a value stays part of that value.
- [`dybatpho::csv_fields`](#dybatphocsv_fields) — Split one record from `dybatpho::csv_read` into a named array of field values.
- [`dybatpho::csv_write`](#dybatphocsv_write) — Serialize records back to CSV. A field is quoted only when it has to be: when it contains the delimiter, a quote, or a line break.
- [`dybatpho::csv_convert`](#dybatphocsv_convert) — Rewrite CSV with another delimiter. The input is read with `DYBATPHO_CSV_DELIMITER` and written with the delimiter given, quoting each field for the delimiter it is written with: a comma inside a value no longer needs quotes in a TSV file, and a tab inside one does. This is how a comma-separated export becomes TSV, or a semicolon-separated one becomes plain CSV.
- [`dybatpho::csv_header`](#dybatphocsv_header) — Print the column names from the first record.
- [`dybatpho::csv_col`](#dybatphocsv_col) — Print one column's values, chosen by its header name. A row shorter than the header reads as an empty value, and a row longer than the header stops the script rather than dropping the extra field.
- [`dybatpho::csv_select`](#dybatphocsv_select) — Print chosen columns, in the order given, as CSV with the header. A column is named by its header, or by its position counting from `1` when no header carries that name, so `3` picks the third column unless a column is literally called `3`. A column may be chosen more than once, and a row shorter than the header reads as empty values.
- [`dybatpho::csv_sort`](#dybatphocsv_sort) — Sort the data rows by one column and print them as CSV with the header first. The sort is stable, so rows with equal keys keep their input order, and it happens in Bash rather than through `sort`, because a value may hold a line break. `auto` compares as numbers when every non-empty value in the column is one, and as text otherwise; text compares byte by byte, the same on every machine whatever its locale. An empty value sorts last in either direction, so blanks never push the rows that matter off the top.
- [`dybatpho::csv_join`](#dybatphocsv_join) — Join two CSV inputs on a key column and print the result as CSV. The output header is every left column followed by every right column except the right key, which would repeat the left one. Rows come out in the left input's order, and a left row matching several right rows gives one output row per match, in the right input's order, the way SQL does. `inner` keeps only the left rows with a match; `left` keeps every left row and leaves the right columns empty where nothing matched. An empty key matches nothing, the way SQL's `NULL` does, so blank cells never pair up into rows nobody meant to relate.
- [`dybatpho::csv_filter`](#dybatphocsv_filter) — Keep the rows whose column satisfies a comparison, and print them as CSV with the header. `gt` and `lt` compare as numbers when both values are numeric, and as text otherwise, so a version column sorts the way a reader expects and a size column the way arithmetic does.
- [`dybatpho::csv_to_json`](#dybatphocsv_to_json) — Convert CSV to a JSON array of objects, keyed by the header. Every value is a JSON string, because CSV carries no types and guessing them is how an identifier with leading zeros or a version number becomes the wrong value. Cast in `jq` when a consumer needs numbers.
- [`dybatpho::csv_from_json`](#dybatphocsv_from_json) — Convert a JSON array of objects to CSV. The keys of the first object become the header, in their document order, and a later object missing one of them writes an empty value there.

<a id="see-also"></a>
## 🔗 See also

- [example/csv_ops.sh](../example/csv_ops.sh)

<a id="tips"></a>
## 💡 Tips

- The whole input is held in memory as a Bash array, which is comfortable into the low tens of thousands of rows; past that, reach for a real CSV tool
- Values are read and written as text, because CSV carries no types; cast in `jq` after `dybatpho::csv_to_json` when a consumer needs numbers

### `dybatpho::csv_col`

- A value containing a line break spans lines here; read through `dybatpho::csv_read` when every value has to stay one item

### `dybatpho::csv_join`

- A column named the same on both sides appears twice in the output; `dybatpho::csv_col` and the other by-name helpers then read the left one

<a id="reference"></a>
## 📚 Reference

### `dybatpho::csv_read`

Parse CSV into an array of records.
Every element is one record whose fields are joined by the ASCII unit
separator; `dybatpho::csv_fields` splits one back apart. Quoted fields are
parsed the way RFC 4180 describes, so a delimiter, a doubled quote, or a
line break inside a value stays part of that value.

**🧪 Example**

```bash
dybatpho::csv_read report.csv rows
dybatpho::csv_fields "${rows[1]}" first
printf '%s\n' "${first[0]}"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$2` | string | Name of the array variable to fill |

**🧩 Variable sets**

- **`The`** (named): array

**🚦 Exit codes**

- `0`: The input was parsed
- `1`: The input contains the ASCII unit separator, or the name is not bindable


---

### `dybatpho::csv_fields`

Split one record from `dybatpho::csv_read` into a named array of
field values.

**🧪 Example**

```bash
dybatpho::csv_fields "${rows[0]}" header
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | One record |
| `$2` | string | Name of the array variable to fill |

**🧩 Variable sets**

- **`The`** (named): array

**🚦 Exit codes**

- `0`: The record was split
- `1`: The name is not bindable


---

### `dybatpho::csv_write`

Serialize records back to CSV.
A field is quoted only when it has to be: when it contains the delimiter, a
quote, or a line break.

**🧪 Example**

```bash
dybatpho::csv_read input.csv rows
dybatpho::csv_write rows > normalized.csv
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array of records |

**📤 Output on stdout**

- CSV text, one record per line

**🚦 Exit codes**

- `0`: The records were written
- `1`: The name is not bindable


---

### `dybatpho::csv_convert`

Rewrite CSV with another delimiter.
The input is read with `DYBATPHO_CSV_DELIMITER` and written with the
delimiter given, quoting each field for the delimiter it is written with:
a comma inside a value no longer needs quotes in a TSV file, and a tab
inside one does. This is how a comma-separated export becomes TSV, or a
semicolon-separated one becomes plain CSV.

**🧪 Example**

```bash
dybatpho::csv_convert report.csv tab > report.tsv
DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_convert report.tsv ","
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$2` | string | Delimiter to write with: one character, or `tab` |

**📤 Output on stdout**

- The records, written with the new delimiter

**🚦 Exit codes**

- `0`: The input was rewritten
- `1`: Either delimiter is invalid, or the input contains the ASCII unit separator


---

### `dybatpho::csv_header`

Print the column names from the first record.

**🧪 Example**

```bash
dybatpho::csv_header report.csv
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |

**📤 Output on stdout**

- One column name per line

**🚦 Exit codes**

- `0`: The header was read, or the input was empty


---

### `dybatpho::csv_col`

Print one column's values, chosen by its header name.
A row shorter than the header reads as an empty value, and a row longer
than the header stops the script rather than dropping the extra field.

**🧪 Example**

```bash
dybatpho::csv_col report.csv "Region"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$2` | string | Column name |

**📤 Output on stdout**

- One value per line, excluding the header

**🚦 Exit codes**

- `0`: The column was printed
- `1`: No column has that name, or a row has more fields than the header


---

### `dybatpho::csv_select`

Print chosen columns, in the order given, as CSV with the header.
A column is named by its header, or by its position counting from `1` when
no header carries that name, so `3` picks the third column unless a column
is literally called `3`. A column may be chosen more than once, and a row
shorter than the header reads as empty values.

**🧪 Example**

```bash
dybatpho::csv_select billing.csv owner cost
dybatpho::csv_select billing.csv 4 1   # cost first, then service
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$@` | string | Columns to keep: header names or 1-based positions |

**📤 Output on stdout**

- CSV text: the chosen header, then every row's chosen fields

**🚦 Exit codes**

- `0`: The columns were printed, or the input was empty
- `1`: A column matches neither a name nor a position, or a row is wider than the header


---

### `dybatpho::csv_sort`

Sort the data rows by one column and print them as CSV with
the header first.
The sort is stable, so rows with equal keys keep their input order, and it
happens in Bash rather than through `sort`, because a value may hold a line
break. `auto` compares as numbers when every non-empty value in the column
is one, and as text otherwise; text compares byte by byte, the same on
every machine whatever its locale. An empty value sorts last in either
direction, so blanks never push the rows that matter off the top.

**🧪 Example**

```bash
dybatpho::csv_sort billing.csv cost desc
dybatpho::csv_sort billing.csv owner asc text
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$2` | string | Column: header name, or 1-based position |
| `$3` | string | Order: `asc` (default) or `desc` |
| `$4` | string | Comparison: `auto` (default), `text`, or `number` |

**📤 Output on stdout**

- CSV text: the header, then the sorted rows

**🚦 Exit codes**

- `0`: The rows were sorted, or the input was empty
- `1`: An unknown column, order or comparison, a non-number under `number`, or a row wider than the header


---

### `dybatpho::csv_join`

Join two CSV inputs on a key column and print the result as
CSV.
The output header is every left column followed by every right column
except the right key, which would repeat the left one. Rows come out in
the left input's order, and a left row matching several right rows gives
one output row per match, in the right input's order, the way SQL does.
`inner` keeps only the left rows with a match; `left` keeps every left row
and leaves the right columns empty where nothing matched. An empty key
matches nothing, the way SQL's `NULL` does, so blank cells never pair up
into rows nobody meant to relate.

**🧪 Example**

```bash
dybatpho::csv_join services.csv owners.csv team
dybatpho::csv_join services.csv costs.csv service left name
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Left CSV: file path, `-` for stdin, or CSV text |
| `$2` | string | Right CSV: file path, `-` for stdin, or CSV text |
| `$3` | string | Key column name in the left input |
| `$4` | string | Join type: `inner` (default) or `left` |
| `$5` | string | Key column name in the right input, default is the left one |

**📤 Output on stdout**

- CSV text: the joined header, then the joined rows

**🚦 Exit codes**

- `0`: The inputs were joined
- `1`: An unknown join type or key column, both inputs read from stdin, or a row wider than its header


---

### `dybatpho::csv_filter`

Keep the rows whose column satisfies a comparison, and print
them as CSV with the header.
`gt` and `lt` compare as numbers when both values are numeric, and as text
otherwise, so a version column sorts the way a reader expects and a size
column the way arithmetic does.

**🧪 Example**

```bash
dybatpho::csv_filter billing.csv "Cost" gt 100
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |
| `$2` | string | Column name |
| `$3` | string | Operator: `eq`, `ne`, `gt`, `lt`, or `contains` |
| `$4` | string | Value to compare against |

**📤 Output on stdout**

- CSV text: the header, then the matching rows

**🚦 Exit codes**

- `0`: The rows were filtered
- `1`: No column has that name, the operator is unknown, or a row is wider than the header


---

### `dybatpho::csv_to_json`

Convert CSV to a JSON array of objects, keyed by the header.
Every value is a JSON string, because CSV carries no types and guessing
them is how an identifier with leading zeros or a version number becomes
the wrong value. Cast in `jq` when a consumer needs numbers.

**🧪 Example**

```bash
dybatpho::csv_to_json report.csv | dybatpho::json_pretty -
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CSV file path, `-` for stdin, or CSV text |

**📤 Output on stdout**

- Compact JSON array

**🚦 Exit codes**

- `0`: The conversion succeeded
- `1`: A row has more fields than the header


---

### `dybatpho::csv_from_json`

Convert a JSON array of objects to CSV.
The keys of the first object become the header, in their document order,
and a later object missing one of them writes an empty value there.

**🧪 Example**

```bash
dybatpho::csv_from_json pods.json > pods.csv
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path, `-` for stdin, or JSON text |

**📤 Output on stdout**

- CSV text

**🚦 Exit codes**

- `0`: The conversion succeeded
- `1`: The document is not an array of objects
- `127`: Neither `yq` nor `jq` is installed
