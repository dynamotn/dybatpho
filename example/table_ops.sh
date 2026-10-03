#!/usr/bin/env bash
# @file table_ops.sh
# @brief Example showing text table utilities
# @description Demonstrates dybatpho::table_print, table_align, table_box, table_markdown, table_csv,
#   table_from_csv, and table_from_json
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules table csv

dybatpho::register_common_handlers

# @description Run the `PLAIN TABLE` section of this example.
# @noargs
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

  dybatpho::header "REAL CSV TABLE"
  # Quoted commas and doubled quotes stay inside their cells, which the
  # comma-splitting table_csv would refuse.
  dybatpho::table_from_csv $'owner,cost\n"Doe, John",120\n"O""Brien, Pat",45' box

  dybatpho::header "JSON TABLE"
  if dybatpho::command_exists_all jq || dybatpho::command_exists_all yq; then
    dybatpho::table_from_json '[{"service":"api","replicas":3},{"service":"worker"}]' markdown
  else
    dybatpho::warn "Neither jq nor yq is installed; skipping the JSON table"
  fi

  dybatpho::success "Table operations demo complete"
}

_main "$@"
