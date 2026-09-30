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
| **`DYBATPHO_CSV_DELIMITER`** | string | Field delimiter, default is `,`; set it to `;` or a tab for the files that use one |
| **`DYBATPHO_CSV_DELIMITER`** | string | Field delimiter every function reads, default is `,` |

### 🚀 Highlights

- [`__dybatpho_csv_input_into`](#__dybatpho_csv_input_into) — Resolve an input argument to the text it names. `-` is stdin, an existing file is its contents, and anything else is the text itself, so a caller can pass a path, a pipe, or a here-string without choosing a different function for each.
- [`__dybatpho_csv_split_into`](#__dybatpho_csv_split_into) — Split one record into its fields, writing them into a named array. Quoting follows RFC 4180: a field that starts with `\"` ends at the next `\"` that is not doubled, and a doubled `\"\"` inside it is one literal quote.
- [`__dybatpho_csv_quotes_unbalanced`](#__dybatpho_csv_quotes_unbalanced) — Return success when a string holds an odd number of quotes, which is how a record that continues on the next line is recognized.
- [`__dybatpho_csv_parse_into`](#__dybatpho_csv_parse_into) — Parse CSV text into an array of records.
- [`__dybatpho_csv_quote_into`](#__dybatpho_csv_quote_into) — Quote one field for output, into a named variable.
- [`__dybatpho_csv_header_into`](#__dybatpho_csv_header_into) — Read the header of a parsed record set into a named array, and report the column count.
- [`__dybatpho_csv_split_fields_into`](#__dybatpho_csv_split_fields_into) — Split a record on the unit separator into a named array.
- [`__dybatpho_csv_column_into`](#__dybatpho_csv_column_into) — Resolve a column name to its index, into a named variable.
- [`dybatpho::csv_read`](#dybatphocsv_read) — Parse CSV into an array of records. Every element is one record whose fields are joined by the ASCII unit separator; `dybatpho::csv_fields` splits one back apart. Quoted fields are parsed the way RFC 4180 describes, so a delimiter, a doubled quote, or a line break inside a value stays part of that value.
- [`dybatpho::csv_fields`](#dybatphocsv_fields) — Split one record from `dybatpho::csv_read` into a named array of field values.
- [`dybatpho::csv_write`](#dybatphocsv_write) — Serialize records back to CSV. A field is quoted only when it has to be: when it contains the delimiter, a quote, or a line break.
- [`dybatpho::csv_header`](#dybatphocsv_header) — Print the column names from the first record.
- [`dybatpho::csv_col`](#dybatphocsv_col) — Print one column's values, chosen by its header name. A row shorter than the header reads as an empty value, and a row longer than the header stops the script rather than dropping the extra field.
- [`__dybatpho_csv_expect_width`](#__dybatpho_csv_expect_width) — Stop when a row carries more fields than the header names. Printing such a row would drop the extra field, which is the silent loss this module exists to prevent.
- [`dybatpho::csv_filter`](#dybatphocsv_filter) — Keep the rows whose column satisfies a comparison, and print them as CSV with the header. `gt` and `lt` compare as numbers when both values are numeric, and as text otherwise, so a version column sorts the way a reader expects and a size column the way arithmetic does.
- [`__dybatpho_csv_matches`](#__dybatpho_csv_matches) — Compare one field against a value.
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

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_csv_input_into`

Resolve an input argument to the text it names.
`-` is stdin, an existing file is its contents, and anything else is the
text itself, so a caller can pass a path, a pipe, or a here-string without
choosing a different function for each.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the text |
| `$2` | string | File path, `-`, or CSV text |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_csv_split_into`

Split one record into its fields, writing them into a named
array. Quoting follows RFC 4180: a field that starts with `\"` ends at the
next `\"` that is not doubled, and a doubled `\"\"` inside it is one literal
quote.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable to fill |
| `$2` | string | One record |
| `$3` | string | Field delimiter |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_csv_quotes_unbalanced`

Return success when a string holds an odd number of quotes,
which is how a record that continues on the next line is recognized.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text so far |

**🚦 Exit codes**

- `0`: The quotes are unbalanced, so the record is not finished
- `1`: The quotes are balanced


---

### `__dybatpho_csv_parse_into`

Parse CSV text into an array of records.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable to fill |
| `$2` | string | CSV text |
| `$3` | string | Field delimiter |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_csv_quote_into`

Quote one field for output, into a named variable.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the result |
| `$2` | string | Field value |
| `$3` | string | Field delimiter |

**🧩 Variable sets**

- **`The`** (named): variable


---

### `__dybatpho_csv_header_into`

Read the header of a parsed record set into a named array, and
report the column count.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable to fill |
| `$2` | string | Name of the array of records |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_csv_split_fields_into`

Split a record on the unit separator into a named array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable to fill |
| `$2` | string | One record |

**🧩 Variable sets**

- **`The`** (named): array


---

### `__dybatpho_csv_column_into`

Resolve a column name to its index, into a named variable.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the index |
| `$2` | string | Name of the array of header names |
| `$3` | string | Column name |

**🧩 Variable sets**

- **`The`** (named): variable


---

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

### `__dybatpho_csv_expect_width`

Stop when a row carries more fields than the header names.
Printing such a row would drop the extra field, which is the silent loss
this module exists to prevent.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array of fields |
| `$2` | string | Name of the array of header names |
| `$3` | number | Row number, counting the header as row 0 |

**🚦 Exit codes**

- `0`: The row fits the header
- `1`: The row has more fields than the header


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

### `__dybatpho_csv_matches`

Compare one field against a value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field value |
| `$2` | string | Operator |
| `$3` | string | Value to compare against |

**🚦 Exit codes**

- `0`: The field satisfies the comparison
- `1`: It does not


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
