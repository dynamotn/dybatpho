#!/usr/bin/env bash
# @file date_ops.sh
# @brief Example showing date and timestamp utilities
# @description Demonstrates dybatpho::date_now, date_today, date_is_valid, date_parse, date_format, date_add_days, and date_diff_days
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_now {
  dybatpho::header "CURRENT TIME"
  dybatpho::info "Unix timestamp : $(dybatpho::date_now)"
  dybatpho::info "RFC3339-ish    : $(dybatpho::date_now "%Y-%m-%dT%H:%M:%SZ")"
  dybatpho::info "Today          : $(dybatpho::date_today)"
}

function _demo_parse_format {
  dybatpho::header "PARSE / FORMAT"
  local stamp
  stamp=$(dybatpho::date_parse "2024-02-29 12:34:56")
  dybatpho::info "Parsed timestamp: ${stamp}"
  dybatpho::info "Formatted again : $(dybatpho::date_format "${stamp}")"
}

function _demo_math {
  dybatpho::header "DATE MATH"
  dybatpho::info "Add 10 days : $(dybatpho::date_add_days "2024-03-01" 10)"
  dybatpho::info "Subtract 1 day: $(dybatpho::date_add_days "2024-03-01" -1)"
  dybatpho::info "Day diff    : $(dybatpho::date_diff_days "2024-03-01" "2024-03-11")"
}

function _demo_validate {
  dybatpho::header "VALIDATION"
  dybatpho::info "2024-02-29 valid? $(dybatpho::date_is_valid "2024-02-29" && echo yes || echo no)"
  dybatpho::info "2024-02-30 valid? $(dybatpho::date_is_valid "2024-02-30" && echo yes || echo no)"
}

function _main {
  _demo_now
  _demo_parse_format
  _demo_math
  _demo_validate
  dybatpho::success "Date operations demo complete"
}

_main "$@"
