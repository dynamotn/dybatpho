#!/usr/bin/env bash
# @file csv_ops.sh
# @brief Example reading a billing export that quotes its fields
# @description Demonstrates dybatpho::csv_read, csv_fields, csv_write, csv_header, csv_col,
#   csv_filter, csv_to_json, csv_from_json, csv_convert, and csv_select
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules csv

dybatpho::register_common_handlers

# @description Write the fixture this example reads, into a temporary file.
#   It carries the three shapes a hand-rolled `cut -d,` parser gets wrong: a
#   delimiter inside a value, a doubled quote, and a line break inside a value.
# @arg $1 string Name of the variable receiving the path
# @set The named variable
function _write_fixture {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  local -n path_ref="${target}"
  dybatpho::create_temp path_ref "billing" ".csv"
  cat > "${path_ref}" << 'CSV'
service,owner,note,cost
api,"Doe, John",steady,120
web,"Tran, Nam","spiky, see the
incident notes",90
db,"O""Brien, Pat",steady,45
CSV
}

# @description Show the column names and one column's values.
# @arg $1 string Path of the CSV file
function _demo_read {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "HEADER AND COLUMN"
  dybatpho::csv_header "${file}"
  printf -- '--\n'
  # The owner values keep the comma that separates surname from given name.
  dybatpho::csv_col "${file}" "owner"
}

# @description Walk the parsed records field by field.
# @arg $1 string Path of the CSV file
function _demo_records {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "RECORDS"
  local -a rows=() fields=()
  dybatpho::csv_read "${file}" rows
  printf 'Parsed %s records, header included\n' "${#rows[@]}"

  # Row 2 is the one whose note runs over two lines.
  dybatpho::csv_fields "${rows[2]}" fields
  printf 'service=%s owner=%s cost=%s\n' "${fields[0]}" "${fields[1]}" "${fields[3]}"
  local -a note_lines=()
  mapfile -t note_lines <<< "${fields[2]}"
  printf 'note spans %s lines\n' "${#note_lines[@]}"
}

# @description Keep the rows above a cost threshold and render them.
# @arg $1 string Path of the CSV file
function _demo_filter {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "FILTER"
  # `gt` compares numbers as numbers, so 90 does not sort above 120 the way it
  # would as text.
  dybatpho::csv_filter "${file}" "cost" gt 50
}

# @description Keep only the columns a report needs, in the order it wants.
# @arg $1 string Path of the CSV file
function _demo_select {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "SELECT"
  # By name, then by position: column 1 is the service.
  dybatpho::csv_select "${file}" owner cost
  printf -- '--\n'
  dybatpho::csv_select "${file}" 4 1
}

# @description Convert to JSON and back, showing the values survive the trip.
# @arg $1 string Path of the CSV file
function _demo_json {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "JSON BRIDGE"
  local json
  json="$(dybatpho::csv_to_json "${file}")"
  printf '%s\n' "${json}"
  printf -- '--\n'
  dybatpho::csv_from_json "${json}"
}

# @description Normalize the file: parse it, then write it back with only the
#   quoting the data actually needs.
# @arg $1 string Path of the CSV file
function _demo_normalize {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "NORMALIZE"
  local -a rows=()
  dybatpho::csv_read "${file}" rows
  dybatpho::csv_write rows
}

# @description Rewrite the export as TSV, then read the TSV back by column.
# @arg $1 string Path of the CSV file
function _demo_tsv {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::header "TSV"
  local tsv
  # The commas inside the owner names need no quotes once tabs separate the
  # fields; the note that spans two lines still does.
  tsv="$(dybatpho::csv_convert "${file}" tab)"
  printf '%s\n' "${tsv}"
  printf -- '--\n'
  DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_col "${tsv}" "owner"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  local fixture
  _write_fixture fixture
  _demo_read "${fixture}"
  _demo_records "${fixture}"
  _demo_filter "${fixture}"
  _demo_select "${fixture}"
  _demo_json "${fixture}"
  _demo_normalize "${fixture}"
  _demo_tsv "${fixture}"
  dybatpho::success "CSV operations demo complete"
}

_main "$@"
