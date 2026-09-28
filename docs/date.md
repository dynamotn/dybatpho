# date.sh

Utilities for working with dates and timestamps

> 🧭 Source: [src/date.sh](../src/date.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains helpers for reading the current time, validating date
strings, converting between Unix timestamps and formatted dates, shifting a
date by a span of time, measuring the distance between two dates, bounding
the month a date falls in, and writing a number of seconds as a clock.

Spans are measured in units that are a fixed number of seconds: seconds,
minutes, hours, days, and weeks. Months and years are left out, because
their length depends on where in the calendar they fall and the two `date`
implementations this module supports shift by them differently.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used by date helpers, default is `UTC` |

### 🚀 Highlights

- [`__dybatpho_date_flavor`](#__dybatpho_date_flavor) — Print which `date` this system has: `gnu`, `bsd` or `busybox`. Detected by asking for something only one of them accepts, rather than by matching a name. BSD stays the default it always was; the new question is whether this is BusyBox, which answers to neither `--version` nor `-j`. A two-way GNU-or-BSD guess sent every BusyBox system down the BSD path, where `-r` means "read the time off this file" and the whole module failed. The answer is cached: probing twice per call is a lot for a helper that formats a date.
- [`__dybatpho_date_is_gnu`](#__dybatpho_date_is_gnu) — 
- [`__dybatpho_date_parse`](#__dybatpho_date_parse) — 
- [`__dybatpho_date_parse_with`](#__dybatpho_date_parse_with) — Parse a date string with an explicit input format.
- [`dybatpho::date_now`](#dybatphodate_now) — Print the current time using a `date` format string.
- [`dybatpho::date_today`](#dybatphodate_today) — Print today's date using a `date` format string.
- [`dybatpho::date_is_valid`](#dybatphodate_is_valid) — Return success when a date string can be parsed by `date`.
- [`dybatpho::date_parse`](#dybatphodate_parse) — Parse a date string and print its Unix timestamp.
- [`dybatpho::date_format`](#dybatphodate_format) — Format a Unix timestamp with a `date` format string.
- [`dybatpho::date_add_days`](#dybatphodate_add_days) — Add or subtract days from a date string and print the result.
- [`dybatpho::date_diff_days`](#dybatphodate_diff_days) — Print the whole-day difference between two date strings.
- [`__dybatpho_date_unit_seconds`](#__dybatpho_date_unit_seconds) — Print how many seconds one unit of time is worth. Only units that are a fixed number of seconds are offered. A month and a year are not: their length depends on where in the calendar they fall, and GNU and BSD `date` disagree on how to shift by one, so a helper that took them would give a different answer per platform.
- [`dybatpho::date_is_leap_year`](#dybatphodate_is_leap_year) — Return success when a year is a leap year. Every fourth year, except centuries, except every fourth century. The middle rule is the one that gets left out, and 1900 is the year that catches it.
- [`dybatpho::date_days_in_month`](#dybatphodate_days_in_month) — Print how many days a month has.
- [`dybatpho::date_month_start`](#dybatphodate_month_start) — Print the first day of the month a date falls in.
- [`dybatpho::date_month_end`](#dybatphodate_month_end) — Print the last day of the month a date falls in. This is the date a billing period or a report window ends on, worked out from the calendar rather than by adding a month and stepping back a day, which lands in the wrong place whenever the two months differ in length.
- [`dybatpho::date_add`](#dybatphodate_add) — Add or subtract a span of time from a date string. The units are the ones that are a fixed number of seconds: seconds, minutes, hours, days, and weeks. Months and years are left out on purpose, since their length depends on the calendar and the two `date` implementations this module supports shift by them differently.
- [`dybatpho::date_diff`](#dybatphodate_diff) — Print the difference between two dates in a chosen unit. The result is truncated toward zero, so a span of 47 hours is one day rather than two, and it is signed: an end before the start is negative.
- [`dybatpho::date_seconds_to_hms`](#dybatphodate_seconds_to_hms) — Print a number of seconds as `H:MM:SS`. The hours are not wrapped at a day, so a span of 90000 seconds reads as `25:00:00`: this is a length of time rather than a time of day. A negative span keeps its sign. For a duration written the way a sentence would put it, in the reader's own language, `dybatpho::i18n_duration` is the one to call.

<a id="see-also"></a>
## 🔗 See also

- [example/date_ops.sh](../example/date_ops.sh)

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_date_flavor`

Print which `date` this system has: `gnu`, `bsd` or `busybox`.
Detected by asking for something only one of them accepts, rather than by
matching a name. BSD stays the default it always was; the new question is
whether this is BusyBox, which answers to neither `--version` nor `-j`. A
two-way GNU-or-BSD guess sent every BusyBox system down the BSD path, where
`-r` means "read the time off this file" and the whole module failed.

The answer is cached: probing twice per call is a lot for a helper that
formats a date.

**📤 Output on stdout**

- `gnu`, `bsd` or `busybox`


---

### `__dybatpho_date_is_gnu`



---

### `__dybatpho_date_parse`



---

### `__dybatpho_date_parse_with`

Parse a date string with an explicit input format.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date flavor, `bsd` or `busybox` |
| `$2` | string | Input format |
| `$3` | string | Date string |

**📤 Output on stdout**

- Unix timestamp

**🚦 Exit codes**

- `1`: The string does not match the format


---

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


---

### `__dybatpho_date_unit_seconds`

Print how many seconds one unit of time is worth.
Only units that are a fixed number of seconds are offered. A month and a
year are not: their length depends on where in the calendar they fall, and
GNU and BSD `date` disagree on how to shift by one, so a helper that took
them would give a different answer per platform.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Unit name, singular or plural |

**📤 Output on stdout**

- Seconds in one unit

**🚦 Exit codes**

- `1`: Stop the script when the unit is not one this module measures


---

### `dybatpho::date_is_leap_year`

Return success when a year is a leap year.
Every fourth year, except centuries, except every fourth century. The middle
rule is the one that gets left out, and 1900 is the year that catches it.

**🧪 Example**

```bash
dybatpho::date_is_leap_year 2024   # yes
dybatpho::date_is_leap_year 1900   # no
dybatpho::date_is_leap_year 2000   # yes

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Year |

**🚦 Exit codes**

- `0`: The year is a leap year
- `1`: It is not
- `1`: Stop the script when the year is not a number


---

### `dybatpho::date_days_in_month`

Print how many days a month has.

**🧪 Example**

```bash
dybatpho::date_days_in_month 2024 2   # 29
dybatpho::date_days_in_month 2023 2   # 28

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Year |
| `$2` | number | Month, from 1 to 12, with or without a leading zero |

**📤 Output on stdout**

- Number of days

**🚦 Exit codes**

- `1`: Stop the script when the year or the month is out of range


---

### `dybatpho::date_month_start`

Print the first day of the month a date falls in.

**🧪 Example**

```bash
dybatpho::date_month_start 2024-02-17          # 2024-02-01
dybatpho::date_month_start 2024-02-17 '%F %T'  # 2024-02-01 00:00:00

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string |
| `$2` | string | Optional output format, default is `%F` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing and formatting |

**📤 Output on stdout**

- The first day of that month

**🚦 Exit codes**

- `1`: The date cannot be parsed


---

### `dybatpho::date_month_end`

Print the last day of the month a date falls in.
This is the date a billing period or a report window ends on, worked out
from the calendar rather than by adding a month and stepping back a day,
which lands in the wrong place whenever the two months differ in length.

**🧪 Example**

```bash
dybatpho::date_month_end 2024-02-17   # 2024-02-29
dybatpho::date_month_end 2023-02-17   # 2023-02-28

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string |
| `$2` | string | Optional output format, default is `%F` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing and formatting |

**📤 Output on stdout**

- The last day of that month

**🚦 Exit codes**

- `1`: The date cannot be parsed


---

### `dybatpho::date_add`

Add or subtract a span of time from a date string.
The units are the ones that are a fixed number of seconds: seconds,
minutes, hours, days, and weeks. Months and years are left out on purpose,
since their length depends on the calendar and the two `date`
implementations this module supports shift by them differently.

**🧪 Example**

```bash
dybatpho::date_add 2024-02-28 1 days                 # 2024-02-29
dybatpho::date_add "2024-02-28 23:00:00" 2 hours '%F %T'
dybatpho::date_add 2024-03-01 -1 weeks               # 2024-02-23

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Base date string |
| `$2` | number | Amount, may be negative |
| `$3` | string | Unit: seconds, minutes, hours, days, or weeks |
| `$4` | string | Optional output format, default is `%F %T` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing and formatting |

**📤 Output on stdout**

- The shifted date

**🚦 Exit codes**

- `1`: The date cannot be parsed, the amount is not a whole number, or the unit is unknown

**🔗 See also**

- [- `dybatpho::date_add_days](#dybatphodate_add_days)


---

### `dybatpho::date_diff`

Print the difference between two dates in a chosen unit.
The result is truncated toward zero, so a span of 47 hours is one day
rather than two, and it is signed: an end before the start is negative.

**🧪 Example**

```bash
dybatpho::date_diff 2024-01-01 2024-03-01 days          # 60
dybatpho::date_diff "2024-01-01 00:00:00" "2024-01-01 01:30:00" minutes

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Start date string |
| `$2` | string | End date string |
| `$3` | string | Optional unit: seconds (default), minutes, hours, days, or weeks |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing both dates |

**📤 Output on stdout**

- Signed difference calculated as `end - start`

**🚦 Exit codes**

- `1`: Either date cannot be parsed, or the unit is unknown

**🔗 See also**

- [- `dybatpho::date_diff_days](#dybatphodate_diff_days)


---

### `dybatpho::date_seconds_to_hms`

Print a number of seconds as `H:MM:SS`.
The hours are not wrapped at a day, so a span of 90000 seconds reads as
`25:00:00`: this is a length of time rather than a time of day. A negative
span keeps its sign.

For a duration written the way a sentence would put it, in the reader's own
language, `dybatpho::i18n_duration` is the one to call.

**🧪 Example**

```bash
dybatpho::date_seconds_to_hms 3661    # 1:01:01
dybatpho::date_seconds_to_hms 90000   # 25:00:00
dybatpho::date_seconds_to_hms -61     # -0:01:01

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Whole number of seconds, may be negative |

**📤 Output on stdout**

- The span as `H:MM:SS`

**🚦 Exit codes**

- `1`: Stop the script when the value is not a whole number

**🔗 See also**

- [- `dybatpho::i18n_duration](#dybatphoi18n_duration)
