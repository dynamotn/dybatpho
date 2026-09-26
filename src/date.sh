#!/usr/bin/env bash
# @file date.sh
# @brief Utilities for working with dates and timestamps
# @description
#   This module contains helpers for reading the current time, validating date
#   strings, converting between Unix timestamps and formatted dates, shifting a
#   date by a span of time, measuring the distance between two dates, bounding
#   the month a date falls in, and writing a number of seconds as a clock.
#
#   Spans are measured in units that are a fixed number of seconds: seconds,
#   minutes, hours, days, and weeks. Months and years are left out, because
#   their length depends on where in the calendar they fall and the two `date`
#   implementations this module supports shift by them differently.
# @see
#   - `example/date_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_DATE_TIMEZONE string Timezone used by date helpers, default is `UTC`
DYBATPHO_DATE_TIMEZONE="${DYBATPHO_DATE_TIMEZONE:-UTC}"

# Which `date` this system has, filled in on first use by
# `__dybatpho_date_flavor`. Per shell, so a test that stubs `date` gets its own
# answer: each Bats test runs in its own process and starts with this empty.
__dybatpho_date_flavor_cache=""

# @description Print which `date` this system has: `gnu`, `bsd` or `busybox`.
#   Detected by asking for something only one of them accepts, rather than by
#   matching a name. BSD stays the default it always was; the new question is
#   whether this is BusyBox, which answers to neither `--version` nor `-j`. A
#   two-way GNU-or-BSD guess sent every BusyBox system down the BSD path, where
#   `-r` means "read the time off this file" and the whole module failed.
#
#   The answer is cached: probing twice per call is a lot for a helper that
#   formats a date.
# @stdout `gnu`, `bsd` or `busybox`
function __dybatpho_date_flavor {
  if [[ -n "${__dybatpho_date_flavor_cache}" ]]; then
    printf '%s\n' "${__dybatpho_date_flavor_cache}"
    return 0
  fi

  if date --version > /dev/null 2>&1; then
    __dybatpho_date_flavor_cache="gnu"
  elif date -D "%Y" -d "2024" +%s > /dev/null 2>&1; then
    # Only BusyBox takes the input format through `-D`.
    __dybatpho_date_flavor_cache="busybox"
  else
    __dybatpho_date_flavor_cache="bsd"
  fi
  printf '%s\n' "${__dybatpho_date_flavor_cache}"
}

function __dybatpho_date_is_gnu {
  [[ "$(__dybatpho_date_flavor)" == "gnu" ]]
}

function __dybatpho_date_parse {
  local input
  dybatpho::expect_args input -- "$@"
  local flavor
  flavor="$(__dybatpho_date_flavor)"
  if [[ "${flavor}" == "gnu" ]]; then
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "${input}" +%s
    return
  fi
  # Neither BSD `date -j -f` nor BusyBox `date -D` rejects an impossible date:
  # both roll `2024-02-30` over into `2024-03-01`. The parsed timestamp is
  # therefore formatted back and compared with the input before it is accepted.
  local input_format timestamp
  for input_format in "%Y-%m-%d %H:%M:%S" "%Y-%m-%d"; do
    timestamp="$(__dybatpho_date_parse_with "${flavor}" "${input_format}" "${input}")" || continue
    if [[ "$(dybatpho::date_format "${timestamp}" "${input_format}" 2> /dev/null)" == "${input}" ]]; then
      printf '%s\n' "${timestamp}"
      return 0
    fi
  done
  # Offset-aware timestamps cannot round-trip literally, so a plain parse wins.
  __dybatpho_date_parse_with "${flavor}" "%Y-%m-%dT%H:%M:%S%z" "${input}"
}

#######################################
# @description Parse a date string with an explicit input format.
# @arg $1 string Date flavor, `bsd` or `busybox`
# @arg $2 string Input format
# @arg $3 string Date string
# @stdout Unix timestamp
# @exitcode 1 The string does not match the format
#######################################
function __dybatpho_date_parse_with {
  local flavor input_format input
  dybatpho::expect_args flavor input_format input -- "$@"
  if [[ "${flavor}" == "busybox" ]]; then
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -D "${input_format}" -d "${input}" +%s 2> /dev/null
    return
  fi
  # BSD `date -j -f` fills every field the format leaves out from the current
  # time, so a bare date would land at this moment's hour rather than midnight.
  if [[ "${input_format}" != *%H* ]]; then
    input_format+=" %H:%M:%S"
    input+=" 00:00:00"
  fi
  TZ="${DYBATPHO_DATE_TIMEZONE}" date -j -f "${input_format}" "${input}" +%s 2> /dev/null
}

#######################################
# @description Print the current time using a `date` format string.
# @arg $1 string Optional output format, default is `%s`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used for formatting the current time
# @stdout Current time formatted by `date`
#######################################
function dybatpho::date_now {
  local format="${1:-%s}"
  TZ="${DYBATPHO_DATE_TIMEZONE}" date +"${format}"
}

#######################################
# @description Print today's date using a `date` format string.
# @arg $1 string Optional output format, default is `%F`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used for formatting the current date
# @stdout Current date formatted by `date`
#######################################
function dybatpho::date_today {
  local format="${1:-%F}"
  dybatpho::date_now "${format}"
}

#######################################
# @description Return success when a date string can be parsed by `date`.
# @arg $1 string Date string to validate
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing the date string
# @exitcode 0 The input is a valid date string
# @exitcode 1 The input cannot be parsed
#######################################
function dybatpho::date_is_valid {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_date_parse "${input}" > /dev/null 2>&1
}

#######################################
# @description Parse a date string and print its Unix timestamp.
# @arg $1 string Date string to parse
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing the date string
# @stdout Unix timestamp
# @exitcode 0 The input is parsed successfully
# @exitcode 1 The input cannot be parsed
#######################################
function dybatpho::date_parse {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_date_parse "${input}"
}

#######################################
# @description Format a Unix timestamp with a `date` format string.
# @arg $1 number Unix timestamp
# @arg $2 string Optional output format, default is `%F %T`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used for formatting the timestamp
# @stdout Formatted date string
#######################################
function dybatpho::date_format {
  local timestamp
  dybatpho::expect_args timestamp -- "$@"
  local format="${2:-%F %T}"
  case "$(__dybatpho_date_flavor)" in
    # BusyBox spells this the way GNU does. Only BSD takes the seconds through
    # `-r`, which on the other two means "read the time off this file".
    gnu | busybox) TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "@${timestamp}" +"${format}" ;;
    *) TZ="${DYBATPHO_DATE_TIMEZONE}" date -r "${timestamp}" +"${format}" ;;
  esac
}

#######################################
# @description Add or subtract days from a date string and print the result.
# @arg $1 string Base date string
# @arg $2 number Day offset, may be negative
# @arg $3 string Optional output format, default is `%F`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing and formatting
# @stdout Shifted date string
#######################################
function dybatpho::date_add_days {
  local input days
  dybatpho::expect_args input days -- "$@"
  dybatpho::date_add "${input}" "${days}" days "${3:-%F}"
}

#######################################
# @description Print the whole-day difference between two date strings.
# @arg $1 string Start date string
# @arg $2 string End date string
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing both date strings
# @stdout Signed whole-day difference calculated as `end - start`
#######################################
function dybatpho::date_diff_days {
  local start_date end_date
  dybatpho::expect_args start_date end_date -- "$@"
  dybatpho::date_diff "${start_date}" "${end_date}" days
}

#######################################
# @description Print how many seconds one unit of time is worth.
#   Only units that are a fixed number of seconds are offered. A month and a
#   year are not: their length depends on where in the calendar they fall, and
#   GNU and BSD `date` disagree on how to shift by one, so a helper that took
#   them would give a different answer per platform.
# @arg $1 string Unit name, singular or plural
# @stdout Seconds in one unit
# @exitcode 1 Stop the script when the unit is not one this module measures
#######################################
function __dybatpho_date_unit_seconds {
  case "${1-}" in
    second | seconds) printf '1\n' ;;
    minute | minutes) printf '60\n' ;;
    hour | hours) printf '3600\n' ;;
    day | days) printf '86400\n' ;;
    week | weeks) printf '604800\n' ;;
    *) dybatpho::die "Unknown time unit '${1-}', expected seconds, minutes, hours, days or weeks" ;;
  esac
}

#######################################
# @description Return success when a year is a leap year.
#   Every fourth year, except centuries, except every fourth century. The middle
#   rule is the one that gets left out, and 1900 is the year that catches it.
# @example
#   dybatpho::date_is_leap_year 2024   # yes
#   dybatpho::date_is_leap_year 1900   # no
#   dybatpho::date_is_leap_year 2000   # yes
#
# @arg $1 number Year
# @exitcode 0 The year is a leap year
# @exitcode 1 It is not
# @exitcode 1 Stop the script when the year is not a number
#######################################
function dybatpho::date_is_leap_year {
  local year
  dybatpho::expect_args year -- "$@"
  [[ "${year}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${year}' is not a year"
  year="$((10#${year}))"
  ((year % 4 == 0 && year % 100 != 0 || year % 400 == 0))
}

#######################################
# @description Print how many days a month has.
# @example
#   dybatpho::date_days_in_month 2024 2   # 29
#   dybatpho::date_days_in_month 2023 2   # 28
#
# @arg $1 number Year
# @arg $2 number Month, from 1 to 12, with or without a leading zero
# @stdout Number of days
# @exitcode 1 Stop the script when the year or the month is out of range
#######################################
function dybatpho::date_days_in_month {
  local year month
  dybatpho::expect_args year month -- "$@"
  [[ "${month}" =~ ^[0-9]{1,2}$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${month}' is not a month"
  month="$((10#${month}))"
  ((month >= 1 && month <= 12)) \
    || dybatpho::die "${FUNCNAME[0]}: '${month}' is not a month"
  case "${month}" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) printf '31\n' ;;
    4 | 6 | 9 | 11) printf '30\n' ;;
    *)
      if dybatpho::date_is_leap_year "${year}"; then
        printf '29\n'
      else
        printf '28\n'
      fi
      ;;
  esac
}

#######################################
# @description Print the first day of the month a date falls in.
# @example
#   dybatpho::date_month_start 2024-02-17          # 2024-02-01
#   dybatpho::date_month_start 2024-02-17 '%F %T'  # 2024-02-01 00:00:00
#
# @arg $1 string Date string
# @arg $2 string Optional output format, default is `%F`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing and formatting
# @stdout The first day of that month
# @exitcode 1 The date cannot be parsed
#######################################
function dybatpho::date_month_start {
  local input
  dybatpho::expect_args input -- "$@"
  local format="${2:-%F}"
  local timestamp
  timestamp=$(dybatpho::date_parse "${input}") || return $?
  local first first_ts
  first="$(dybatpho::date_format "${timestamp}" '%Y-%m')-01"
  first_ts=$(dybatpho::date_parse "${first}") || return $?
  dybatpho::date_format "${first_ts}" "${format}"
}

#######################################
# @description Print the last day of the month a date falls in.
#   This is the date a billing period or a report window ends on, worked out
#   from the calendar rather than by adding a month and stepping back a day,
#   which lands in the wrong place whenever the two months differ in length.
# @example
#   dybatpho::date_month_end 2024-02-17   # 2024-02-29
#   dybatpho::date_month_end 2023-02-17   # 2023-02-28
#
# @arg $1 string Date string
# @arg $2 string Optional output format, default is `%F`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing and formatting
# @stdout The last day of that month
# @exitcode 1 The date cannot be parsed
#######################################
function dybatpho::date_month_end {
  local input
  dybatpho::expect_args input -- "$@"
  local format="${2:-%F}"
  local timestamp
  timestamp=$(dybatpho::date_parse "${input}") || return $?
  local year month last last_ts
  year="$(dybatpho::date_format "${timestamp}" '%Y')"
  month="$(dybatpho::date_format "${timestamp}" '%m')"
  last="$(dybatpho::date_days_in_month "${year}" "${month}")" || return 1
  last_ts=$(dybatpho::date_parse "${year}-${month}-${last}") || return $?
  dybatpho::date_format "${last_ts}" "${format}"
}

#######################################
# @description Add or subtract a span of time from a date string.
#   The units are the ones that are a fixed number of seconds: seconds,
#   minutes, hours, days, and weeks. Months and years are left out on purpose,
#   since their length depends on the calendar and the two `date`
#   implementations this module supports shift by them differently.
# @example
#   dybatpho::date_add 2024-02-28 1 days                 # 2024-02-29
#   dybatpho::date_add "2024-02-28 23:00:00" 2 hours '%F %T'
#   dybatpho::date_add 2024-03-01 -1 weeks               # 2024-02-23
#
# @arg $1 string Base date string
# @arg $2 number Amount, may be negative
# @arg $3 string Unit: seconds, minutes, hours, days, or weeks
# @arg $4 string Optional output format, default is `%F %T`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing and formatting
# @stdout The shifted date
# @exitcode 1 The date cannot be parsed, the amount is not a whole number, or the unit is unknown
# @see
#   - `dybatpho::date_add_days`
#######################################
function dybatpho::date_add {
  local input amount unit
  dybatpho::expect_args input amount unit -- "$@"
  local format="${4:-%F %T}"
  [[ "${amount}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${amount}' is not a whole number"
  local unit_seconds
  # `dybatpho::die` inside a command substitution only leaves that subshell, and
  # a caller that wrote `date_add ... || handler` has `errexit` switched off for
  # the whole call, so the status is checked here rather than assumed.
  unit_seconds="$(__dybatpho_date_unit_seconds "${unit}")" || return 1

  if __dybatpho_date_is_gnu; then
    # GNU's relative syntax walks the calendar itself, which keeps the answer
    # right across a daylight-saving change in a non-UTC timezone.
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "${input} ${amount} ${unit}" +"${format}"
    return
  fi
  # No other `date` understands a relative offset, so the shift is arithmetic
  # and the result goes back through the one function that knows how each
  # system formats a timestamp — BusyBox reads `-r` as a file, not a time.
  local timestamp
  timestamp=$(__dybatpho_date_parse "${input}") || return $?
  dybatpho::date_format "$((timestamp + amount * unit_seconds))" "${format}"
}

#######################################
# @description Print the difference between two dates in a chosen unit.
#   The result is truncated toward zero, so a span of 47 hours is one day
#   rather than two, and it is signed: an end before the start is negative.
# @example
#   dybatpho::date_diff 2024-01-01 2024-03-01 days          # 60
#   dybatpho::date_diff "2024-01-01 00:00:00" "2024-01-01 01:30:00" minutes
#
# @arg $1 string Start date string
# @arg $2 string End date string
# @arg $3 string Optional unit: seconds (default), minutes, hours, days, or weeks
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing both dates
# @stdout Signed difference calculated as `end - start`
# @exitcode 1 Either date cannot be parsed, or the unit is unknown
# @see
#   - `dybatpho::date_diff_days`
#######################################
function dybatpho::date_diff {
  local start_date end_date
  dybatpho::expect_args start_date end_date -- "$@"
  local unit="${3:-seconds}"
  local unit_seconds
  # `dybatpho::die` inside a command substitution only leaves that subshell, and
  # a caller that wrote `date_add ... || handler` has `errexit` switched off for
  # the whole call, so the status is checked here rather than assumed.
  unit_seconds="$(__dybatpho_date_unit_seconds "${unit}")" || return 1
  local start_ts end_ts
  start_ts=$(dybatpho::date_parse "${start_date}") || return $?
  end_ts=$(dybatpho::date_parse "${end_date}") || return $?
  printf '%s\n' "$(((end_ts - start_ts) / unit_seconds))"
}

#######################################
# @description Print a number of seconds as `H:MM:SS`.
#   The hours are not wrapped at a day, so a span of 90000 seconds reads as
#   `25:00:00`: this is a length of time rather than a time of day. A negative
#   span keeps its sign.
#
#   For a duration written the way a sentence would put it, in the reader's own
#   language, `dybatpho::i18n_duration` is the one to call.
# @example
#   dybatpho::date_seconds_to_hms 3661    # 1:01:01
#   dybatpho::date_seconds_to_hms 90000   # 25:00:00
#   dybatpho::date_seconds_to_hms -61     # -0:01:01
#
# @arg $1 number Whole number of seconds, may be negative
# @stdout The span as `H:MM:SS`
# @exitcode 1 Stop the script when the value is not a whole number
# @see
#   - `dybatpho::i18n_duration`
#######################################
function dybatpho::date_seconds_to_hms {
  local total
  dybatpho::expect_args total -- "$@"
  [[ "${total}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: '${total}' is not a whole number of seconds"
  local sign=""
  if ((total < 0)); then
    sign="-"
    total=$((-total))
  fi
  printf '%s%d:%02d:%02d\n' \
    "${sign}" "$((total / 3600))" "$(((total % 3600) / 60))" "$((total % 60))"
}
