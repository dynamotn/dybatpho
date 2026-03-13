#!/usr/bin/env bash
# @file table_ops.sh
# @brief Example showing text table utilities
# @description Demonstrates dybatpho::table_print, table_align, table_box, table_markdown, and table_csv
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _main {
  local rows=$'Name|Role|State\nAlice|Dev|Active\nBob|Ops|Paused'
  local csv_rows=$'Name,Count\nApples,3\nPears,12'

  dybatpho::header "PLAIN TABLE"
  dybatpho::table_print "${rows}"

  dybatpho::header "ALIGNED TABLE"
  dybatpho::table_align $'Name|Count\nApples|3\nPears|12' "|" "left,right" 3

  dybatpho::header "BOXED TABLE"
  dybatpho::table_box "${rows}"

  dybatpho::header "MARKDOWN TABLE"
  dybatpho::table_markdown "${rows}"

  dybatpho::header "CSV TABLE"
  dybatpho::table_csv "${csv_rows}" plain "left,right"

  dybatpho::success "Table operations demo complete"
}

_main "$@"
