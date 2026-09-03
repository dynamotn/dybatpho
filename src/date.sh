#!/usr/bin/env bash
# @file date.sh
# @brief Utilities for working with dates and timestamps
# @description
#   This module contains helpers for reading the current time, validating date
#   strings, converting between Unix timestamps and formatted dates, adding day
#   offsets, and calculating day differences.
# @see
#   - `example/date_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_DATE_TIMEZONE string Timezone used by date helpers, default is `UTC`
DYBATPHO_DATE_TIMEZONE="${DYBATPHO_DATE_TIMEZONE:-UTC}"

function __dybatpho_date_is_gnu {
  date --version > /dev/null 2>&1
}

function __dybatpho_date_parse {
  local input
  dybatpho::expect_args input -- "$@"
  if __dybatpho_date_is_gnu; then
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "${input}" +%s
    return
  fi
  local input_format
  for input_format in "%Y-%m-%d %H:%M:%S" "%Y-%m-%d" "%Y-%m-%dT%H:%M:%S%z"; do
    if TZ="${DYBATPHO_DATE_TIMEZONE}" date -j -f "${input_format}" "${input}" +%s 2> /dev/null; then
      return 0
    fi
  done
  return 1
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
  if __dybatpho_date_is_gnu; then
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "@${timestamp}" +"${format}"
  else
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -r "${timestamp}" +"${format}"
  fi
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
  local format="${3:-%F}"
  if __dybatpho_date_is_gnu; then
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -d "${input} ${days} days" +"${format}"
  else
    local timestamp
    timestamp=$(__dybatpho_date_parse "${input}") || return $?
    TZ="${DYBATPHO_DATE_TIMEZONE}" date -r "$((timestamp + days * 86400))" +"${format}"
  fi
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
  local start_ts end_ts
  start_ts=$(dybatpho::date_parse "${start_date}") || return $?
  end_ts=$(dybatpho::date_parse "${end_date}") || return $?
  printf '%s\n' "$(((end_ts - start_ts) / 86400))"
}
