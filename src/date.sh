# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break.
# dyshellint disable=BSG050,BSG011
# @file date.sh
# @brief Utilities for working with dates and timestamps
# @namespace dybatpho
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
# `__dybatpho_date_flavor_into`, and the `PATH` it was found under. Per shell,
# so a test that stubs `date` gets its own answer: each Bats test runs in its
# own process and starts with this empty, and a stub that changes `PATH` makes
# the next call look again.
__dybatpho_date_flavor_cache=""
__dybatpho_date_flavor_path=""

#######################################
# @description Work out which `date` this system has: `gnu`, `bsd` or
#   `busybox`, into a variable.
#   Detected by asking for the flags the module goes on to use, rather than by
#   matching a name or a `--version` banner. Only BusyBox takes an input format
#   through `-D`, so it is asked first; then `-d @0` is the GNU way to read a
#   timestamp, which a GNU-compatible `date` without `--version` also accepts.
#   BSD stays the default it always was. A two-way GNU-or-BSD guess sent every
#   BusyBox system down the BSD path, where `-r` means "read the time off this
#   file" and the whole module failed.
#
#   The answer is cached in the calling shell, which is why this fills a
#   variable rather than printing: a cache written inside `$(...)` is gone
#   when the substitution ends, and every call probed `date` again.
# @arg $1 string Name of the variable receiving the flavour
# @set The named variable
# @internal
#######################################
function __dybatpho_date_flavor_into {
  local __dybatpho_date_flavor_var
  dybatpho::expect_args __dybatpho_date_flavor_var -- "$@"
  local -n __dybatpho_date_flavor_out="${__dybatpho_date_flavor_var}"
  if [[ -z "${__dybatpho_date_flavor_cache}" || "${__dybatpho_date_flavor_path}" != "${PATH}" ]]; then
    if date -D "%Y" -d "2024" +%s > /dev/null 2>&1; then
      # Only BusyBox takes the input format through `-D`.
      __dybatpho_date_flavor_cache="busybox"
    elif date -d "@0" +%s > /dev/null 2>&1; then
      __dybatpho_date_flavor_cache="gnu"
    else
      __dybatpho_date_flavor_cache="bsd"
    fi
    __dybatpho_date_flavor_path="${PATH}"
  fi
  __dybatpho_date_flavor_out="${__dybatpho_date_flavor_cache}"
}

#######################################
# @description Report whether `date` is the GNU one, which is what decides
#   between `-d` and BSD's `-j -f` everywhere else in this module.
# @noargs
# @exitcode 0 `date` is GNU
# @exitcode 1 `date` is the BSD one
# @internal
#######################################
function __dybatpho_date_is_gnu {
  local date_flavor
  __dybatpho_date_flavor_into date_flavor
  [[ "${date_flavor}" == "gnu" ]]
}

#######################################
# @description Turn a date expression into an epoch, through whichever `date`
#   the machine has.
# @arg $1 string Date expression, in any form the local `date` accepts
# @stdout Seconds since the epoch
# @exitcode 1 The expression could not be parsed
# @internal
#######################################
function __dybatpho_date_parse {
  local input
  dybatpho::expect_args input -- "$@"
  local flavor
  __dybatpho_date_flavor_into flavor
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
    local date_format
    date_format=$(dybatpho::date_format "${timestamp}" "${input_format}" 2> /dev/null)
    if [[ "${date_format}" == "${input}" ]]; then
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
# @internal
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
  local flavor
  __dybatpho_date_flavor_into flavor
  case "${flavor}" in
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
# @internal
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

#######################################
# @description Add one part of a duration to a running total, refusing an
#   amount that would carry the total past the largest number Bash can hold.
#   Bash arithmetic wraps silently, so a duration of a hundred quintillion weeks
#   would otherwise come back as a negative number of seconds.
# @arg $1 string Name of the variable holding the running total
# @arg $2 string Amount, as written: digits, possibly with leading zeros
# @arg $3 number Seconds in one unit of the amount
# @exitcode 0 The part was added
# @exitcode 1 The digits are too many or the total would overflow
# @internal
#######################################
function __dybatpho_date_duration_add {
  local -n __dybatpho_date_dur_total="$1"
  local __dybatpho_date_dur_digits="$2" __dybatpho_date_dur_unit="$3"
  local __dybatpho_date_dur_max=9223372036854775807
  # The digits are checked as text before they are read as a number, since a
  # number past the maximum has already wrapped by the time it can be compared.
  # Leading zeros do not count against the length.
  __dybatpho_date_dur_digits="${__dybatpho_date_dur_digits#"${__dybatpho_date_dur_digits%%[!0]*}"}"
  [[ -n "${__dybatpho_date_dur_digits}" ]] || return 0
  ((${#__dybatpho_date_dur_digits} <= ${#__dybatpho_date_dur_max})) || return 1
  if ((${#__dybatpho_date_dur_digits} == ${#__dybatpho_date_dur_max})); then
    # Compared in two halves that each fit in a number: the leading ten digits,
    # then the trailing nine.
    local __dybatpho_date_dur_high="$((10#${__dybatpho_date_dur_digits:0:10}))"
    local __dybatpho_date_dur_low="$((10#${__dybatpho_date_dur_digits:10}))"
    ((__dybatpho_date_dur_high <= 9223372036)) || return 1
    ((__dybatpho_date_dur_high < 9223372036 || __dybatpho_date_dur_low <= 854775807)) || return 1
  fi
  local __dybatpho_date_dur_amount="$((10#${__dybatpho_date_dur_digits}))"
  ((__dybatpho_date_dur_amount <= (__dybatpho_date_dur_max - __dybatpho_date_dur_total) / __dybatpho_date_dur_unit)) \
    || return 1
  __dybatpho_date_dur_total=$((__dybatpho_date_dur_total + __dybatpho_date_dur_amount * __dybatpho_date_dur_unit))
}

#######################################
# @description Parse a written length of time into a number of seconds.
#   Three spellings are understood, so a value can come from a person, from a
#   clock, or from a machine:
#
#   - a bare number of seconds, or parts with a unit, largest first, each used
#     at most once: `w`, `d`, `h`, `m` and `s`, optionally separated by spaces,
#     as in `90s`, `5m`, `1h30m`, `2d`, `1w 2d`;
#   - the `H:MM:SS` clock that `dybatpho::date_seconds_to_hms` writes, so the
#     two helpers undo each other;
#   - an ISO 8601 duration made of weeks, days, hours, minutes and seconds:
#     `PT1H30M`, `P1DT2H`, `P2W`.
#
#   Months and years are refused in every spelling, for the same reason
#   `dybatpho::date_add` refuses them: their length depends on where in the
#   calendar they fall. A leading `-` makes the span negative.
#
#   The result is returned through a variable rather than printed, because the
#   function validates its input, and a refusal inside a command substitution
#   would not reach the caller.
# @example
#   local seconds
#   dybatpho::date_parse_duration seconds 1h30m     # 5400
#   dybatpho::date_parse_duration seconds 1:01:01   # 3661
#   dybatpho::date_parse_duration seconds PT1H30M   # 5400
#   dybatpho::date_parse_duration seconds "${TIMEOUT}" || dybatpho::die "Bad timeout"
#
# @arg $1 string Name of the variable receiving the number of seconds
# @arg $2 string Duration to parse
# @set The named variable, only when the duration is valid
# @stderr Why the duration was refused
# @exitcode 0 The duration is valid
# @exitcode 1 The duration is empty, malformed, uses a calendar unit, or is too large to count
# @see
#   - `dybatpho::date_seconds_to_hms`
#######################################
function dybatpho::date_parse_duration {
  dybatpho::expect_ref "${1-}"
  local -n __dybatpho_date_pd_out="$1"
  local __dybatpho_date_pd_input="${2-}"
  local __dybatpho_date_pd_text="${__dybatpho_date_pd_input}"
  local __dybatpho_date_pd_sign="" __dybatpho_date_pd_total=0
  local __dybatpho_date_pd_ok=0
  local __dybatpho_date_pd_iso='^P(([0-9]+)W)?(([0-9]+)D)?(T(([0-9]+)H)?(([0-9]+)M)?(([0-9]+)S)?)?$'
  local __dybatpho_date_pd_parts_re='^(([0-9]+)w *)?(([0-9]+)d *)?(([0-9]+)h *)?(([0-9]+)m *)?(([0-9]+)s)?$'

  if [[ "${__dybatpho_date_pd_text}" == -* ]]; then
    __dybatpho_date_pd_sign="-"
    __dybatpho_date_pd_text="${__dybatpho_date_pd_text#-}"
  fi

  if [[ "${__dybatpho_date_pd_text}" =~ ^[0-9]+$ ]]; then
    __dybatpho_date_duration_add __dybatpho_date_pd_total "${__dybatpho_date_pd_text}" 1 \
      && __dybatpho_date_pd_ok=1
  elif [[ "${__dybatpho_date_pd_text}" =~ ^([0-9]+):([0-5][0-9]):([0-5][0-9])$ ]]; then
    __dybatpho_date_duration_add __dybatpho_date_pd_total "${BASH_REMATCH[1]}" 3600 \
      && __dybatpho_date_duration_add __dybatpho_date_pd_total "${BASH_REMATCH[2]}" 60 \
      && __dybatpho_date_duration_add __dybatpho_date_pd_total "${BASH_REMATCH[3]}" 1 \
      && __dybatpho_date_pd_ok=1
  else
    # Both remaining spellings name weeks, days, hours, minutes and seconds in
    # that order, and differ only in where their regular expression captures
    # each amount.
    local -a __dybatpho_date_pd_groups=()
    if [[ "${__dybatpho_date_pd_text}" =~ ${__dybatpho_date_pd_iso} ]] \
      && [[ "${__dybatpho_date_pd_text}" != "P" && "${__dybatpho_date_pd_text}" != *T ]]; then
      __dybatpho_date_pd_groups=(2 4 7 9 11)
    elif [[ "${__dybatpho_date_pd_text}" =~ ${__dybatpho_date_pd_parts_re} ]] \
      && [[ -n "${__dybatpho_date_pd_text}" && "${__dybatpho_date_pd_text}" != *" " ]]; then
      __dybatpho_date_pd_groups=(2 4 6 8 10)
    fi
    if ((${#__dybatpho_date_pd_groups[@]} > 0)); then
      # The amounts are copied out before anything else runs, since every call
      # below runs regular expressions of its own and would overwrite
      # `BASH_REMATCH`.
      local -a __dybatpho_date_pd_amounts=()
      local -a __dybatpho_date_pd_units=(604800 86400 3600 60 1)
      local __dybatpho_date_pd_i
      for __dybatpho_date_pd_i in "${__dybatpho_date_pd_groups[@]}"; do
        __dybatpho_date_pd_amounts+=("${BASH_REMATCH[__dybatpho_date_pd_i]}")
      done
      __dybatpho_date_pd_ok=1
      for __dybatpho_date_pd_i in 0 1 2 3 4; do
        __dybatpho_date_duration_add __dybatpho_date_pd_total \
          "${__dybatpho_date_pd_amounts[__dybatpho_date_pd_i]}" \
          "${__dybatpho_date_pd_units[__dybatpho_date_pd_i]}" \
          || {
            __dybatpho_date_pd_ok=0
            break
          }
      done
    fi
  fi

  if ((__dybatpho_date_pd_ok == 0)); then
    local __dybatpho_date_pd_hint="expected seconds, H:MM:SS, parts such as 1h30m, or ISO 8601 such as PT1H30M"
    dybatpho::error "${FUNCNAME[0]}: '${__dybatpho_date_pd_input}' is not a duration, ${__dybatpho_date_pd_hint}"
    return 1
  fi
  __dybatpho_date_pd_out="${__dybatpho_date_pd_sign}${__dybatpho_date_pd_total}"
  [[ "${__dybatpho_date_pd_out}" != "-0" ]] || __dybatpho_date_pd_out=0
}

#######################################
# @description Parse both dates a comparison is asked about into two named
#   variables, stopping the script when either one cannot be read. A
#   comparison that answered "no" for a date it could not parse would be
#   indistinguishable from a real answer. It runs in the caller's shell, so the
#   refusal stops the script there rather than only ending a substitution.
# @arg $1 string Name of the variable receiving the first timestamp
# @arg $2 string Name of the variable receiving the second timestamp
# @arg $3 string Name of the function asking, for the message
# @arg $4 string First date string
# @arg $5 string Second date string
# @set The two named variables
# @exitcode 1 Stop the script when either date cannot be parsed
# @internal
#######################################
function __dybatpho_date_compare_pair_into {
  local -n __dybatpho_date_pair_first="$1" __dybatpho_date_pair_second="$2"
  local __dybatpho_date_pair_caller="$3"
  __dybatpho_date_pair_first=$(__dybatpho_date_parse "$4" 2> /dev/null) \
    || dybatpho::die "${__dybatpho_date_pair_caller}: '$4' is not a valid date"
  __dybatpho_date_pair_second=$(__dybatpho_date_parse "$5" 2> /dev/null) \
    || dybatpho::die "${__dybatpho_date_pair_caller}: '$5' is not a valid date"
}

#######################################
# @description Return success when the first date comes strictly before the
#   second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`, so a bare date means
#   midnight there and two spellings of the same moment are equal, not ordered.
# @example
#   dybatpho::date_is_before 2024-02-28 2024-02-29            # yes
#   dybatpho::date_is_before "2024-02-29 12:00:00" 2024-02-29 # no
#
# @arg $1 string Date string that may come first
# @arg $2 string Date string to compare it with
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing both dates
# @exitcode 0 The first date is earlier
# @exitcode 1 It is the same moment or later
# @exitcode 1 Stop the script when either date cannot be parsed
# @see
#   - `dybatpho::date_is_after`
#######################################
function dybatpho::date_is_before {
  local first second
  dybatpho::expect_args first second -- "$@"
  local first_ts second_ts
  __dybatpho_date_compare_pair_into first_ts second_ts "${FUNCNAME[0]}" "${first}" "${second}"
  ((first_ts < second_ts))
}

#######################################
# @description Return success when the first date comes strictly after the
#   second. Both are parsed in `DYBATPHO_DATE_TIMEZONE`.
# @example
#   dybatpho::date_is_after 2024-03-01 2024-02-29   # yes
#   dybatpho::date_is_after 2024-02-29 2024-02-29   # no
#
# @arg $1 string Date string that may come last
# @arg $2 string Date string to compare it with
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing both dates
# @exitcode 0 The first date is later
# @exitcode 1 It is the same moment or earlier
# @exitcode 1 Stop the script when either date cannot be parsed
# @see
#   - `dybatpho::date_is_before`
#######################################
function dybatpho::date_is_after {
  local first second
  dybatpho::expect_args first second -- "$@"
  local first_ts second_ts
  __dybatpho_date_compare_pair_into first_ts second_ts "${FUNCNAME[0]}" "${first}" "${second}"
  ((first_ts > second_ts))
}

#######################################
# @description Print how many ISO 8601 weeks a year has: 53 when it starts on a
#   Thursday, or is a leap year that starts on a Wednesday, and 52 otherwise.
# @arg $1 number Year
# @stdout `52` or `53`
# @internal
#######################################
function __dybatpho_date_iso_weeks_in_year {
  local year="$1"
  local this=$(((year + year / 4 - year / 100 + year / 400) % 7))
  local prior=$((((year - 1) + (year - 1) / 4 - (year - 1) / 100 + (year - 1) / 400) % 7))
  if ((this == 4 || prior == 3)); then
    printf '53\n'
  else
    printf '52\n'
  fi
}

#######################################
# @description Print the ISO 8601 week a date falls in.
#   ISO weeks start on a Monday, and week 1 is the one holding the year's first
#   Thursday, so the first days of January can belong to the last week of the
#   year before, and the last days of December to week 1 of the next. That is
#   why the week-year is printed beside the week: `2021-01-01` is in `2020-W53`.
#
#   The week is worked out from the day of the year and the day of the week,
#   rather than from `%G` and `%V`, so the answer does not depend on which
#   `date` the system has.
#
#   The format takes three placeholders: `%G` for the week-year, `%V` for the
#   two-digit week, and `%u` for the day of the week from 1 (Monday) to 7.
#   `%%` writes a percent sign, and anything else is copied as it is.
# @example
#   dybatpho::date_iso_week 2024-02-29          # 2024-W09
#   dybatpho::date_iso_week 2021-01-01          # 2020-W53
#   dybatpho::date_iso_week 2024-12-30 '%G%V'   # 202501
#   dybatpho::date_iso_week 2024-02-29 '%G-W%V-%u'   # 2024-W09-4
#
# @arg $1 string Date string
# @arg $2 string Optional format, default is `%G-W%V`
# @env DYBATPHO_DATE_TIMEZONE string Timezone used while parsing the date
# @stdout The week, written with the format
# @exitcode 1 The date cannot be parsed
#######################################
function dybatpho::date_iso_week {
  local input
  dybatpho::expect_args input -- "$@"
  local format="${2:-%G-W%V}"
  local timestamp
  timestamp=$(dybatpho::date_parse "${input}") || return $?
  local fields year day_of_year weekday
  fields="$(dybatpho::date_format "${timestamp}" '%Y %j %u')"
  read -r year day_of_year weekday <<< "${fields}"
  year=$((10#${year}))
  day_of_year=$((10#${day_of_year}))
  weekday=$((10#${weekday}))

  local week=$(((day_of_year - weekday + 10) / 7))
  local weeks_in_year
  weeks_in_year="$(__dybatpho_date_iso_weeks_in_year "${year}")"
  if ((week < 1)); then
    year=$((year - 1))
    week="$(__dybatpho_date_iso_weeks_in_year "${year}")"
  elif ((week > weeks_in_year)); then
    year=$((year + 1))
    week=1
  fi

  local result="" char i
  for ((i = 0; i < ${#format}; i++)); do
    char="${format:i:1}"
    if [[ "${char}" != "%" || $((i + 1)) -ge ${#format} ]]; then
      result+="${char}"
      continue
    fi
    i=$((i + 1))
    case "${format:i:1}" in
      G) result+="${year}" ;;
      V) result+="$(printf '%02d' "${week}")" ;;
      u) result+="${weekday}" ;;
      %) result+="%" ;;
      *) result+="%${format:i:1}" ;;
    esac
  done
  printf '%s\n' "${result}"
}

#######################################
# @description Report whether a timezone name can be honored, rather than
#   letting `date` quietly fall back to UTC: GNU, BSD and BusyBox all answer in
#   UTC for a zone they cannot find, which would turn a typo into a wrong time.
#   `UTC` and `GMT` are always known; any other name must be a file under the
#   zone database, `TZDIR` or `/usr/share/zoneinfo`.
# @arg $1 string Timezone name
# @exitcode 0 The zone is known
# @exitcode 1 It is not, or the name is not a zone name at all
# @internal
#######################################
function __dybatpho_date_zone_known {
  local zone="$1"
  [[ "${zone}" == "UTC" || "${zone}" == "GMT" ]] && return 0
  # Path-shaped names only: no leading slash, no `..`, nothing a shell would
  # read twice. A POSIX rule string such as `EST5EDT,M3.2.0` is not accepted.
  [[ "${zone}" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || return 1
  [[ -f "${TZDIR:-/usr/share/zoneinfo}/${zone}" ]]
}

#######################################
# @description Print a date as it reads in another timezone.
#   The date is parsed in `DYBATPHO_DATE_TIMEZONE`, as everywhere else in this
#   module, and written in the zone asked for. The zone has to be in the
#   system's zone database: `date` itself answers in UTC for a name it cannot
#   find, on every platform this module supports, so an unknown zone is refused
#   rather than passed on.
# @example
#   dybatpho::date_in_tz "2024-02-29 12:00:00" Asia/Tokyo
#   # 2024-02-29 21:00:00 +0900
#   DYBATPHO_DATE_TIMEZONE=Europe/Paris dybatpho::date_in_tz "2024-07-01 09:00:00" America/New_York '%F %R %Z'
#   # 2024-07-01 03:00 EDT
#
# @arg $1 string Date string
# @arg $2 string Target timezone, such as `Asia/Ho_Chi_Minh` or `UTC`
# @arg $3 string Optional output format, default is `%F %T %z`
# @env DYBATPHO_DATE_TIMEZONE string Timezone the date is read in
# @env TZDIR string Zone database directory, default is `/usr/share/zoneinfo`
# @stdout The date in the target timezone
# @exitcode 1 The date cannot be parsed
# @exitcode 1 Stop the script when the timezone is not in the zone database
#######################################
function dybatpho::date_in_tz {
  local input zone
  dybatpho::expect_args input zone -- "$@"
  local format="${3:-%F %T %z}"
  __dybatpho_date_zone_known "${zone}" \
    || dybatpho::die "${FUNCNAME[0]}: '${zone}' is not a timezone in ${TZDIR:-/usr/share/zoneinfo}"
  local timestamp
  timestamp=$(dybatpho::date_parse "${input}") || return $?
  DYBATPHO_DATE_TIMEZONE="${zone}" dybatpho::date_format "${timestamp}" "${format}"
}
