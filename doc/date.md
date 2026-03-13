# date.sh

Utilities for working with dates and timestamps

> 🧭 Source: [src/date.sh](../src/date.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for reading the current time, validating date
strings, converting between Unix timestamps and formatted dates, adding day
offsets, and calculating day differences.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used by date helpers, default is `UTC` |

### 🚀 Highlights

- [`dybatpho::date_now`](#dybatphodate_now) — Print the current time using a `date` format string.
- [`dybatpho::date_today`](#dybatphodate_today) — Print today's date using a `date` format string.
- [`dybatpho::date_is_valid`](#dybatphodate_is_valid) — Return success when a date string can be parsed by `date`.
- [`dybatpho::date_parse`](#dybatphodate_parse) — Parse a date string and print its Unix timestamp.
- [`dybatpho::date_format`](#dybatphodate_format) — Format a Unix timestamp with a `date` format string.
- [`dybatpho::date_add_days`](#dybatphodate_add_days) — Add or subtract days from a date string and print the result.
- [`dybatpho::date_diff_days`](#dybatphodate_diff_days) — Print the whole-day difference between two date strings.

<a id="see-also"></a>
## 🔗 See also

- [example/date_ops.sh](../example/date_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `dybatpho::date_now`

Print the current time using a `date` format string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional output format, default is `%s` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used for formatting the current time |

**📤 Output on stdout**

- Current time formatted by `date`


---

### `dybatpho::date_today`

Print today's date using a `date` format string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional output format, default is `%F` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used for formatting the current date |

**📤 Output on stdout**

- Current date formatted by `date`


---

### `dybatpho::date_is_valid`

Return success when a date string can be parsed by `date`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string to validate |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing the date string |

**🚦 Exit codes**

- `0`: The input is a valid date string
- `1`: The input cannot be parsed


---

### `dybatpho::date_parse`

Parse a date string and print its Unix timestamp.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string to parse |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing the date string |

**📤 Output on stdout**

- Unix timestamp

**🚦 Exit codes**

- `0`: The input is parsed successfully
- `1`: The input cannot be parsed


---

### `dybatpho::date_format`

Format a Unix timestamp with a `date` format string.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Unix timestamp |
| `$2` | string | Optional output format, default is `%F %T` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used for formatting the timestamp |

**📤 Output on stdout**

- Formatted date string


---

### `dybatpho::date_add_days`

Add or subtract days from a date string and print the result.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Base date string |
| `$2` | number | Day offset, may be negative |
| `$3` | string | Optional output format, default is `%F` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing and formatting |

**📤 Output on stdout**

- Shifted date string


---

### `dybatpho::date_diff_days`

Print the whole-day difference between two date strings.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Start date string |
| `$2` | string | End date string |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing both date strings |

**📤 Output on stdout**

- Signed whole-day difference calculated as `end - start`

