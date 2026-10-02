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

- [`dybatpho::date_now`](#dybatphodate_now) — Print the current time using a `date` format string.
- [`dybatpho::date_today`](#dybatphodate_today) — Print today's date using a `date` format string.
- [`dybatpho::date_is_valid`](#dybatphodate_is_valid) — Return success when a date string can be parsed by `date`.
- [`dybatpho::date_parse`](#dybatphodate_parse) — Parse a date string and print its Unix timestamp.
- [`dybatpho::date_format`](#dybatphodate_format) — Format a Unix timestamp with a `date` format string.
- [`dybatpho::date_add_days`](#dybatphodate_add_days) — Add or subtract days from a date string and print the result.
- [`dybatpho::date_diff_days`](#dybatphodate_diff_days) — Print the whole-day difference between two date strings.
- [`dybatpho::date_is_leap_year`](#dybatphodate_is_leap_year) — Return success when a year is a leap year. Every fourth year, except centuries, except every fourth century. The middle rule is the one that gets left out, and 1900 is the year that catches it.
- [`dybatpho::date_days_in_month`](#dybatphodate_days_in_month) — Print how many days a month has.
- [`dybatpho::date_month_start`](#dybatphodate_month_start) — Print the first day of the month a date falls in.
- [`dybatpho::date_month_end`](#dybatphodate_month_end) — Print the last day of the month a date falls in. This is the date a billing period or a report window ends on, worked out from the calendar rather than by adding a month and stepping back a day, which lands in the wrong place whenever the two months differ in length.
- [`dybatpho::date_add`](#dybatphodate_add) — Add or subtract a span of time from a date string. The units are the ones that are a fixed number of seconds: seconds, minutes, hours, days, and weeks. Months and years are left out on purpose, since their length depends on the calendar and the two `date` implementations this module supports shift by them differently.
- [`dybatpho::date_diff`](#dybatphodate_diff) — Print the difference between two dates in a chosen unit. The result is truncated toward zero, so a span of 47 hours is one day rather than two, and it is signed: an end before the start is negative.
- [`dybatpho::date_seconds_to_hms`](#dybatphodate_seconds_to_hms) — Print a number of seconds as `H:MM:SS`. The hours are not wrapped at a day, so a span of 90000 seconds reads as `25:00:00`: this is a length of time rather than a time of day. A negative span keeps its sign. For a duration written the way a sentence would put it, in the reader's own language, `dybatpho::i18n_duration` is the one to call.
- [`dybatpho::date_parse_duration`](#dybatphodate_parse_duration) — Parse a written length of time into a number of seconds. Three spellings are understood, so a value can come from a person, from a clock, or from a machine: - a bare number of seconds, or parts with a unit, largest first, each used at most once: `w`, `d`, `h`, `m` and `s`, optionally separated by spaces, as in `90s`, `5m`, `1h30m`, `2d`, `1w 2d`; - the `H:MM:SS` clock that `dybatpho::date_seconds_to_hms` writes, so the two helpers undo each other; - an ISO 8601 duration made of weeks, days, hours, minutes and seconds: `PT1H30M`, `P1DT2H`, `P2W`. Months and years are refused in every spelling, for the same reason `dybatpho::date_add` refuses them: their length depends on where in the calendar they fall. A leading `-` makes the span negative. The result is returned through a variable rather than printed, because the function validates its input, and a refusal inside a command substitution would not reach the caller.
- [`dybatpho::date_is_before`](#dybatphodate_is_before) — Return success when the first date comes strictly before the second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`, so a bare date means midnight there and two spellings of the same moment are equal, not ordered.
- [`dybatpho::date_is_after`](#dybatphodate_is_after) — Return success when the first date comes strictly after the second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`.
- [`dybatpho::date_iso_week`](#dybatphodate_iso_week) — Print the ISO 8601 week a date falls in. ISO weeks start on a Monday, and week 1 is the one holding the year's first Thursday, so the first days of January can belong to the last week of the year before, and the last days of December to week 1 of the next. That is why the week-year is printed beside the week: `2021-01-01` is in `2020-W53`. The week is worked out from the day of the year and the day of the week, rather than from `%G` and `%V`, so the answer does not depend on which `date` the system has. The format takes three placeholders: `%G` for the week-year, `%V` for the two-digit week, and `%u` for the day of the week from 1 (Monday) to 7. `%%` writes a percent sign, and anything else is copied as it is.
- [`dybatpho::date_in_tz`](#dybatphodate_in_tz) — Print a date as it reads in another timezone. The date is parsed in `DYBATPHO_DATE_TIMEZONE`, as everywhere else in this module, and written in the zone asked for. The zone has to be in the system's zone database: `date` itself answers in UTC for a name it cannot find, on every platform this module supports, so an unknown zone is refused rather than passed on.

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


---

### `dybatpho::date_parse_duration`

Parse a written length of time into a number of seconds.
Three spellings are understood, so a value can come from a person, from a
clock, or from a machine:

- a bare number of seconds, or parts with a unit, largest first, each used
  at most once: `w`, `d`, `h`, `m` and `s`, optionally separated by spaces,
  as in `90s`, `5m`, `1h30m`, `2d`, `1w 2d`;
- the `H:MM:SS` clock that `dybatpho::date_seconds_to_hms` writes, so the
  two helpers undo each other;
- an ISO 8601 duration made of weeks, days, hours, minutes and seconds:
  `PT1H30M`, `P1DT2H`, `P2W`.

Months and years are refused in every spelling, for the same reason
`dybatpho::date_add` refuses them: their length depends on where in the
calendar they fall. A leading `-` makes the span negative.

The result is returned through a variable rather than printed, because the
function validates its input, and a refusal inside a command substitution
would not reach the caller.

**🧪 Example**

```bash
local seconds
dybatpho::date_parse_duration seconds 1h30m     # 5400
dybatpho::date_parse_duration seconds 1:01:01   # 3661
dybatpho::date_parse_duration seconds PT1H30M   # 5400
dybatpho::date_parse_duration seconds "${TIMEOUT}" || dybatpho::die "Bad timeout"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the number of seconds |
| `$2` | string | Duration to parse |

**🧩 Variable sets**

- **`The`** (named): variable, only when the duration is valid

**📤 Output on stderr**

- Why the duration was refused

**🚦 Exit codes**

- `0`: The duration is valid
- `1`: The duration is empty, malformed, uses a calendar unit, or is too large to count

**🔗 See also**

- [- `dybatpho::date_seconds_to_hms](#dybatphodate_seconds_to_hms)


---

### `dybatpho::date_is_before`

Return success when the first date comes strictly before the
second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`, so a bare date means
midnight there and two spellings of the same moment are equal, not ordered.

**🧪 Example**

```bash
dybatpho::date_is_before 2024-02-28 2024-02-29            # yes
dybatpho::date_is_before "2024-02-29 12:00:00" 2024-02-29 # no

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string that may come first |
| `$2` | string | Date string to compare it with |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing both dates |

**🚦 Exit codes**

- `0`: The first date is earlier
- `1`: It is the same moment or later
- `1`: Stop the script when either date cannot be parsed

**🔗 See also**

- [- `dybatpho::date_is_after](#dybatphodate_is_after)


---

### `dybatpho::date_is_after`

Return success when the first date comes strictly after the
second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`.

**🧪 Example**

```bash
dybatpho::date_is_after 2024-03-01 2024-02-29   # yes
dybatpho::date_is_after 2024-02-29 2024-02-29   # no

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string that may come last |
| `$2` | string | Date string to compare it with |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing both dates |

**🚦 Exit codes**

- `0`: The first date is later
- `1`: It is the same moment or earlier
- `1`: Stop the script when either date cannot be parsed

**🔗 See also**

- [- `dybatpho::date_is_before](#dybatphodate_is_before)


---

### `dybatpho::date_iso_week`

Print the ISO 8601 week a date falls in.
ISO weeks start on a Monday, and week 1 is the one holding the year's first
Thursday, so the first days of January can belong to the last week of the
year before, and the last days of December to week 1 of the next. That is
why the week-year is printed beside the week: `2021-01-01` is in `2020-W53`.

The week is worked out from the day of the year and the day of the week,
rather than from `%G` and `%V`, so the answer does not depend on which
`date` the system has.

The format takes three placeholders: `%G` for the week-year, `%V` for the
two-digit week, and `%u` for the day of the week from 1 (Monday) to 7.
`%%` writes a percent sign, and anything else is copied as it is.

**🧪 Example**

```bash
dybatpho::date_iso_week 2024-02-29          # 2024-W09
dybatpho::date_iso_week 2021-01-01          # 2020-W53
dybatpho::date_iso_week 2024-12-30 '%G%V'   # 202501
dybatpho::date_iso_week 2024-02-29 '%G-W%V-%u'   # 2024-W09-4

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string |
| `$2` | string | Optional format, default is `%G-W%V` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone used while parsing the date |

**📤 Output on stdout**

- The week, written with the format

**🚦 Exit codes**

- `1`: The date cannot be parsed


---

### `dybatpho::date_in_tz`

Print a date as it reads in another timezone.
The date is parsed in `DYBATPHO_DATE_TIMEZONE`, as everywhere else in this
module, and written in the zone asked for. The zone has to be in the
system's zone database: `date` itself answers in UTC for a name it cannot
find, on every platform this module supports, so an unknown zone is refused
rather than passed on.

**🧪 Example**

```bash
dybatpho::date_in_tz "2024-02-29 12:00:00" Asia/Tokyo
# 2024-02-29 21:00:00 +0900
DYBATPHO_DATE_TIMEZONE=Europe/Paris dybatpho::date_in_tz "2024-07-01 09:00:00" America/New_York '%F %R %Z'
# 2024-07-01 03:00 EDT

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Date string |
| `$2` | string | Target timezone, such as `Asia/Ho_Chi_Minh` or `UTC` |
| `$3` | string | Optional output format, default is `%F %T %z` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DATE_TIMEZONE`** | string | Timezone the date is read in |
| **`TZDIR`** | string | Zone database directory, default is `/usr/share/zoneinfo` |

**📤 Output on stdout**

- The date in the target timezone

**🚦 Exit codes**

- `1`: The date cannot be parsed
- `1`: Stop the script when the timezone is not in the zone database
