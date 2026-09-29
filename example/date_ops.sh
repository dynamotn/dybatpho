#!/usr/bin/env bash
# @file date_ops.sh
# @brief Example showing date and timestamp utilities
# @description
#   Demonstrates dybatpho::date_now, date_today, date_is_valid, date_parse, date_format, date_add_days, and
#   date_diff_days
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules date

dybatpho::register_common_handlers

# @description Run the `CURRENT TIME` section of this example.
# @noargs
function _demo_now {
  dybatpho::header "CURRENT TIME"
  local date_now_2
  date_now_2=$(dybatpho::date_now)
  dybatpho::info "Unix timestamp : ${date_now_2}"
  local date_now
  date_now=$(dybatpho::date_now "%Y-%m-%dT%H:%M:%SZ")
  dybatpho::info "RFC3339-ish    : ${date_now}"
  local date_today
  date_today=$(dybatpho::date_today)
  dybatpho::info "Today          : ${date_today}"
}

# @description Run the `PARSE / FORMAT` section of this example.
# @noargs
function _demo_parse_format {
  dybatpho::header "PARSE / FORMAT"
  local stamp
  stamp=$(dybatpho::date_parse "2024-02-29 12:34:56")
  dybatpho::info "Parsed timestamp: ${stamp}"
  local date_format
  date_format=$(dybatpho::date_format "${stamp}")
  dybatpho::info "Formatted again : ${date_format}"
}

# @description Run the `DATE MATH` section of this example.
# @noargs
function _demo_math {
  dybatpho::header "DATE MATH"
  local date_add_days_2
  date_add_days_2=$(dybatpho::date_add_days "2024-03-01" 10)
  dybatpho::info "Add 10 days : ${date_add_days_2}"
  local date_add_days
  date_add_days=$(dybatpho::date_add_days "2024-03-01" -1)
  dybatpho::info "Subtract 1 day: ${date_add_days}"
  local date_diff_days
  date_diff_days=$(dybatpho::date_diff_days "2024-03-01" "2024-03-11")
  dybatpho::info "Day diff    : ${date_diff_days}"
}

# @description Run the `VALIDATION` section of this example.
# @noargs
function _demo_validate {
  dybatpho::header "VALIDATION"
  local date_is_valid_2
  date_is_valid_2=$(dybatpho::date_is_valid "2024-02-29" && echo yes || echo no)
  dybatpho::info "2024-02-29 valid? ${date_is_valid_2}"
  local date_is_valid
  date_is_valid=$(dybatpho::date_is_valid "2024-02-30" && echo yes || echo no)
  dybatpho::info "2024-02-30 valid? ${date_is_valid}"
}

# @description Bound the month a date falls in, which is what a billing period
#   or a report window needs.
# @noargs
function _demo_calendar {
  dybatpho::header "CALENDAR"
  local date
  for date in 2024-02-17 2023-02-17 2024-04-05; do
    local date_month_end
    date_month_end=$(dybatpho::date_month_end "${date}")
    local date_month_start
    date_month_start=$(dybatpho::date_month_start "${date}")
    dybatpho::print "  ${date}: ${date_month_start} .. ${date_month_end}"
  done
  local year
  for year in 1900 2000 2024; do
    if dybatpho::date_is_leap_year "${year}"; then
      local date_days_in_month_2
      date_days_in_month_2=$(dybatpho::date_days_in_month "${year}" 2)
      dybatpho::print "  ${year} is a leap year, February has ${date_days_in_month_2} days"
    else
      local date_days_in_month
      date_days_in_month=$(dybatpho::date_days_in_month "${year}" 2)
      dybatpho::print "  ${year} is not, February has ${date_days_in_month} days"
    fi
  done
}

# @description Shift a date by a span and measure the distance between two,
#   in whichever unit the answer is wanted in.
# @noargs
function _demo_spans {
  dybatpho::header "SPANS"
  local date_add_3
  date_add_3=$(dybatpho::date_add 2024-02-28 1 days '%F')
  dybatpho::print "  2024-02-28 + 1 day   = ${date_add_3}"
  local date_add_2
  date_add_2=$(dybatpho::date_add 2023-02-28 1 days '%F')
  dybatpho::print "  2023-02-28 + 1 day   = ${date_add_2}"
  local date_add
  date_add=$(dybatpho::date_add 2024-03-01 -1 weeks '%F')
  dybatpho::print "  2024-03-01 - 1 week  = ${date_add}"

  local started="2024-01-01 09:00:00" finished="2024-01-02 11:30:00"
  local date_diff_3
  date_diff_3=$(dybatpho::date_diff "${started}" "${finished}" hours)
  dybatpho::print "  elapsed: ${date_diff_3} hours"
  # Truncated toward zero: 26 hours is one day, not two.
  local date_diff_2
  date_diff_2=$(dybatpho::date_diff "${started}" "${finished}" days)
  dybatpho::print "  elapsed: ${date_diff_2} whole days"
  local date_diff
  date_diff=$(dybatpho::date_diff "${started}" "${finished}")
  local date_seconds_to_hms
  date_seconds_to_hms=$(dybatpho::date_seconds_to_hms "${date_diff}")
  dybatpho::print "  on a clock: ${date_seconds_to_hms}"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_now
  _demo_parse_format
  _demo_math
  _demo_validate
  _demo_calendar
  _demo_spans
  dybatpho::success "Date operations demo complete"
}

_main "$@"
