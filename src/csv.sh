# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file csv.sh
# @brief Utilities for reading, filtering and writing CSV data
# @namespace dybatpho
# @description
#   This module reads the tabular format ops scripts keep receiving --
#   spreadsheet exports, cloud billing reports, CI artifacts -- and it parses
#   the quoting that `awk -F,` and `cut -d,` get wrong. A field may contain the
#   delimiter, a doubled quote, or a line break, and none of them end the field.
#
#   `table.sh` renders comma-delimited text and says so: it splits on every
#   comma and refuses a quoted field rather than turning one into two columns.
#   This module is the parser that refusal points at. Render through
#   `table.sh` afterwards by writing the parsed rows back out with
#   `dybatpho::csv_write`.
#
#   Rows are exchanged as an array whose every element is one record, its
#   fields joined by the ASCII unit separator. Splitting a record is then a
#   single unambiguous operation, which is what `dybatpho::csv_fields` does.
#   Data containing that byte is rejected rather than silently re-split.
# @tip The whole input is held in memory as a Bash array, which is comfortable
#   into the low tens of thousands of rows; past that, reach for a real CSV tool
# @tip Values are read and written as text, because CSV carries no types; cast
#   in `jq` after `dybatpho::csv_to_json` when a consumer needs numbers
# @env DYBATPHO_CSV_DELIMITER string Field delimiter, default is `,`; set it to `;`, or to `tab` for TSV
# @see
#   - `example/csv_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CSV_DELIMITER string Field delimiter every function reads, default is `,`; `tab` or `\t` names a tab
DYBATPHO_CSV_DELIMITER="${DYBATPHO_CSV_DELIMITER:-,}"

# The byte that joins the fields of one record. A record is exchanged as a
# single string so that an array of records stays a flat Bash array; the unit
# separator is what makes splitting it back apart unambiguous, because unlike
# the delimiter it can never be part of a value.
__dybatpho_csv_unit=$'\037'

#######################################
# @description Resolve a delimiter to the character it names, into a named
#   variable, and stop on one the parser cannot work with.
#   `tab` and `\t` name a tab, because a literal tab is awkward to type in an
#   environment variable. Anything else must be exactly one character that is
#   neither a quote, a line break, nor the unit separator: an empty delimiter
#   never advances the parser, and the others are already part of the format.
# @arg $1 string Name of the variable receiving the delimiter
# @arg $2 string Delimiter as the caller wrote it
# @set The named variable
# @exitcode 0 The delimiter is usable
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_csv_delimiter_into {
  local -n __dybatpho_csv_delim_ref="$1"
  local __dybatpho_csv_wanted="$2"

  case "${__dybatpho_csv_wanted}" in
    tab | '\t') __dybatpho_csv_wanted=$'\t' ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac

  # The refusals below are covered by "DYBATPHO_CSV_DELIMITER refuses a
  # delimiter the parser cannot use", which has to use `run` because the path
  # ends in `dybatpho::die`; `run` clears the trap kcov instruments through.
  local __dybatpho_csv_problem=""
  if ((${#__dybatpho_csv_wanted} != 1)); then
    __dybatpho_csv_problem="it must be one character, or \`tab\`" # kcov(skip)
  else
    case "${__dybatpho_csv_wanted}" in
      '"' | $'\n' | $'\r' | "${__dybatpho_csv_unit}")
        __dybatpho_csv_problem="a quote, a line break, or the unit separator" # kcov(skip)
        __dybatpho_csv_problem+=" cannot separate fields" # kcov(skip)
        ;;
      *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    esac
  fi

  if [[ -n "${__dybatpho_csv_problem}" ]]; then
    local __dybatpho_csv_shown                                              # kcov(skip)
    printf -v __dybatpho_csv_shown '%q' "${__dybatpho_csv_wanted}"          # kcov(skip)
    dybatpho::die "${FUNCNAME[1]}: Invalid delimiter ${__dybatpho_csv_shown}: ${__dybatpho_csv_problem}" # kcov(skip)
  fi
  __dybatpho_csv_delim_ref="${__dybatpho_csv_wanted}"
}

#######################################
# @description Resolve an input argument to the text it names.
#   `-` is stdin, an existing file is its contents, and anything else is the
#   text itself, so a caller can pass a path, a pipe, or a here-string without
#   choosing a different function for each.
# @arg $1 string Name of the variable receiving the text
# @arg $2 string File path, `-`, or CSV text
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_input_into {
  local -n __dybatpho_csv_input_ref="$1"
  local __dybatpho_csv_source="$2"

  if [[ "${__dybatpho_csv_source}" == "-" ]]; then
    __dybatpho_csv_input_ref="$(cat)"
  elif dybatpho::is file "${__dybatpho_csv_source}"; then
    __dybatpho_csv_input_ref="$(cat -- "${__dybatpho_csv_source}")"
  else
    __dybatpho_csv_input_ref="${__dybatpho_csv_source}"
  fi

  local __dybatpho_csv_reason="The input contains the ASCII unit separator,"
  __dybatpho_csv_reason+=" which this module uses to join a record's fields"
  [[ "${__dybatpho_csv_input_ref}" != *"${__dybatpho_csv_unit}"* ]] || dybatpho::die \
    "${FUNCNAME[2]:-${FUNCNAME[0]}}: ${__dybatpho_csv_reason}"
}

#######################################
# @description Split one record into its fields, writing them into a named
#   array. Quoting follows RFC 4180: a field that starts with `\"` ends at the
#   next `\"` that is not doubled, and a doubled `\"\"` inside it is one literal
#   quote.
# @arg $1 string Name of the array variable to fill
# @arg $2 string One record
# @arg $3 string Field delimiter
# @set The named array
# @internal
#######################################
function __dybatpho_csv_split_into {
  local -n __dybatpho_csv_fields_ref="$1"
  local __dybatpho_csv_rest="$2"
  local __dybatpho_csv_delimiter="$3"
  __dybatpho_csv_fields_ref=()
  local __dybatpho_csv_field __dybatpho_csv_chunk

  while true; do
    if [[ "${__dybatpho_csv_rest}" == '"'* ]]; then
      __dybatpho_csv_rest="${__dybatpho_csv_rest:1}"
      __dybatpho_csv_field=""
      while true; do
        __dybatpho_csv_chunk="${__dybatpho_csv_rest%%\"*}"
        if [[ "${__dybatpho_csv_chunk}" == "${__dybatpho_csv_rest}" ]]; then
          # No closing quote. The record is malformed, and taking the remainder
          # as the field keeps the data the caller does have.
          __dybatpho_csv_field+="${__dybatpho_csv_rest}"
          __dybatpho_csv_rest=""
          break
        fi
        __dybatpho_csv_field+="${__dybatpho_csv_chunk}"
        __dybatpho_csv_rest="${__dybatpho_csv_rest:$((${#__dybatpho_csv_chunk} + 1))}"
        if [[ "${__dybatpho_csv_rest}" == '"'* ]]; then
          __dybatpho_csv_field+='"'
          __dybatpho_csv_rest="${__dybatpho_csv_rest:1}"
        else
          break
        fi
      done
      # Anything between the closing quote and the delimiter is not valid CSV.
      # It is kept rather than dropped, because dropping it is the silent data
      # loss this module exists to avoid.
      if [[ -n "${__dybatpho_csv_rest}" && "${__dybatpho_csv_rest}" != "${__dybatpho_csv_delimiter}"* ]]; then
        __dybatpho_csv_field+="${__dybatpho_csv_rest%%"${__dybatpho_csv_delimiter}"*}"
        __dybatpho_csv_rest="${__dybatpho_csv_rest#*"${__dybatpho_csv_delimiter}"}"
        __dybatpho_csv_fields_ref+=("${__dybatpho_csv_field}")
        continue
      fi
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_field}")
      [[ -n "${__dybatpho_csv_rest}" ]] || break
      __dybatpho_csv_rest="${__dybatpho_csv_rest#"${__dybatpho_csv_delimiter}"}"
      continue
    fi

    if [[ "${__dybatpho_csv_rest}" == *"${__dybatpho_csv_delimiter}"* ]]; then
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_rest%%"${__dybatpho_csv_delimiter}"*}")
      __dybatpho_csv_rest="${__dybatpho_csv_rest#*"${__dybatpho_csv_delimiter}"}"
    else
      __dybatpho_csv_fields_ref+=("${__dybatpho_csv_rest}")
      break
    fi
  done
}

#######################################
# @description Return success when a string holds an odd number of quotes,
#   which is how a record that continues on the next line is recognized.
# @arg $1 string Text so far
# @exitcode 0 The quotes are unbalanced, so the record is not finished
# @exitcode 1 The quotes are balanced
# @internal
#######################################
function __dybatpho_csv_quotes_unbalanced {
  local quotes="${1//[^\"]/}"
  ((${#quotes} % 2 == 1))
}

#######################################
# @description Parse CSV text into an array of records.
# @arg $1 string Name of the array variable to fill
# @arg $2 string CSV text
# @arg $3 string Field delimiter
# @set The named array
# @internal
#######################################
function __dybatpho_csv_parse_into {
  local -n __dybatpho_csv_records_ref="$1"
  local __dybatpho_csv_text="$2"
  local __dybatpho_csv_delimiter="$3"
  __dybatpho_csv_records_ref=()

  [[ -n "${__dybatpho_csv_text}" ]] || return 0

  local -a __dybatpho_csv_lines=()
  mapfile -t __dybatpho_csv_lines <<< "${__dybatpho_csv_text}"

  local __dybatpho_csv_line __dybatpho_csv_buffer="" __dybatpho_csv_pending=0
  local -a __dybatpho_csv_row=()
  local IFS

  for __dybatpho_csv_line in "${__dybatpho_csv_lines[@]}"; do
    # A CRLF file leaves the carriage return at the end of every line, and a
    # value compared against one would never match what the caller typed.
    __dybatpho_csv_line="${__dybatpho_csv_line%$'\r'}"

    if ((__dybatpho_csv_pending)); then
      __dybatpho_csv_buffer+=$'\n'"${__dybatpho_csv_line}"
    else
      __dybatpho_csv_buffer="${__dybatpho_csv_line}"
    fi

    if __dybatpho_csv_quotes_unbalanced "${__dybatpho_csv_buffer}"; then
      # An open quote means the value runs on into the next line.
      __dybatpho_csv_pending=1
      continue
    fi
    __dybatpho_csv_pending=0

    __dybatpho_csv_split_into __dybatpho_csv_row "${__dybatpho_csv_buffer}" "${__dybatpho_csv_delimiter}"
    IFS="${__dybatpho_csv_unit}"
    __dybatpho_csv_records_ref+=("${__dybatpho_csv_row[*]}")
    unset IFS
  done

  # A file whose last quote is never closed still has data worth returning.
  if ((__dybatpho_csv_pending)); then
    __dybatpho_csv_split_into __dybatpho_csv_row "${__dybatpho_csv_buffer}" "${__dybatpho_csv_delimiter}"
    IFS="${__dybatpho_csv_unit}"
    __dybatpho_csv_records_ref+=("${__dybatpho_csv_row[*]}")
    unset IFS
  fi
}

#######################################
# @description Quote one field for output, into a named variable.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Field value
# @arg $3 string Field delimiter
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_quote_into {
  local -n __dybatpho_csv_quoted_ref="$1"
  local __dybatpho_csv_value="$2"
  local __dybatpho_csv_delimiter="$3"

  local __dybatpho_csv_special=0
  case "${__dybatpho_csv_value}" in
    *'"'* | *$'\n'* | *$'\r'*) __dybatpho_csv_special=1 ;;
    *"${__dybatpho_csv_delimiter}"*) __dybatpho_csv_special=1 ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac

  if ((__dybatpho_csv_special)); then
    __dybatpho_csv_quoted_ref="\"${__dybatpho_csv_value//\"/\"\"}\""
    return 0
  fi
  __dybatpho_csv_quoted_ref="${__dybatpho_csv_value}"
}

#######################################
# @description Read the header of a parsed record set into a named array, and
#   report the column count.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Name of the array of records
# @set The named array
# @internal
#######################################
function __dybatpho_csv_header_into {
  local -n __dybatpho_csv_head_ref="$1"
  local -n __dybatpho_csv_all_ref="$2"
  __dybatpho_csv_head_ref=()

  ((${#__dybatpho_csv_all_ref[@]})) || return 0
  __dybatpho_csv_split_fields_into __dybatpho_csv_head_ref "${__dybatpho_csv_all_ref[0]}"
}

#######################################
# @description Split a record on the unit separator into a named array.
# @arg $1 string Name of the array variable to fill
# @arg $2 string One record
# @set The named array
# @internal
#######################################
function __dybatpho_csv_split_fields_into {
  local -n __dybatpho_csv_parts_ref="$1"
  local __dybatpho_csv_remaining="$2"
  __dybatpho_csv_parts_ref=()

  # Not word splitting on `IFS`: it drops a trailing empty field, so a row
  # ending in the delimiter would come back one column short of its header.
  while [[ "${__dybatpho_csv_remaining}" == *"${__dybatpho_csv_unit}"* ]]; do
    __dybatpho_csv_parts_ref+=("${__dybatpho_csv_remaining%%"${__dybatpho_csv_unit}"*}")
    __dybatpho_csv_remaining="${__dybatpho_csv_remaining#*"${__dybatpho_csv_unit}"}"
  done
  __dybatpho_csv_parts_ref+=("${__dybatpho_csv_remaining}")
}

#######################################
# @description Resolve a column name to its index, into a named variable.
# @arg $1 string Name of the variable receiving the index
# @arg $2 string Name of the array of header names
# @arg $3 string Column name
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_column_into {
  local -n __dybatpho_csv_index_ref="$1"
  local -n __dybatpho_csv_names_ref="$2"
  local __dybatpho_csv_wanted="$3"
  local __dybatpho_csv_at

  for __dybatpho_csv_at in "${!__dybatpho_csv_names_ref[@]}"; do
    if [[ "${__dybatpho_csv_names_ref[${__dybatpho_csv_at}]}" == "${__dybatpho_csv_wanted}" ]]; then
      __dybatpho_csv_index_ref="${__dybatpho_csv_at}"
      return 0
    fi
  done

  local __dybatpho_csv_complaint="No such column: ${__dybatpho_csv_wanted}."
  __dybatpho_csv_complaint+=" The header has: ${__dybatpho_csv_names_ref[*]}"
  dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_complaint}"
}

#######################################
# @description Parse CSV into an array of records.
#   Every element is one record whose fields are joined by the ASCII unit
#   separator; `dybatpho::csv_fields` splits one back apart. Quoted fields are
#   parsed the way RFC 4180 describes, so a delimiter, a doubled quote, or a
#   line break inside a value stays part of that value.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Name of the array variable to fill
# @set The named array
# @exitcode 0 The input was parsed
# @exitcode 1 The input contains the ASCII unit separator, or the name is not bindable
# @example
#   dybatpho::csv_read report.csv rows
#   dybatpho::csv_fields "${rows[1]}" first
#   printf '%s\n' "${first[0]}"
#######################################
function dybatpho::csv_read {
  local input target
  dybatpho::expect_args input target -- "$@"
  dybatpho::expect_ref "${target}"

  local text delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into "${target}" "${text}" "${delimiter}"
}

#######################################
# @description Split one record from `dybatpho::csv_read` into a named array of
#   field values.
# @arg $1 string One record
# @arg $2 string Name of the array variable to fill
# @set The named array
# @exitcode 0 The record was split
# @exitcode 1 The name is not bindable
# @example
#   dybatpho::csv_fields "${rows[0]}" header
#######################################
function dybatpho::csv_fields {
  local record target
  dybatpho::expect_args record target -- "$@"
  dybatpho::expect_ref "${target}"

  __dybatpho_csv_split_fields_into "${target}" "${record}"
}

#######################################
# @description Serialize records back to CSV.
#   A field is quoted only when it has to be: when it contains the delimiter, a
#   quote, or a line break.
# @arg $1 string Name of the array of records
# @stdout CSV text, one record per line
# @exitcode 0 The records were written
# @exitcode 1 The name is not bindable
# @example
#   dybatpho::csv_read input.csv rows
#   dybatpho::csv_write rows > normalized.csv
#######################################
function dybatpho::csv_write {
  local source
  dybatpho::expect_args source -- "$@"
  dybatpho::expect_ref "${source}"

  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_write_with "${source}" "${delimiter}"
}

#######################################
# @description Serialize records with a delimiter the caller has resolved.
# @arg $1 string Name of the array of records
# @arg $2 string Field delimiter
# @stdout CSV text, one record per line
# @internal
#######################################
function __dybatpho_csv_write_with {
  local -n __dybatpho_csv_out_ref="$1"
  local __dybatpho_csv_delimiter="$2"
  local __dybatpho_csv_record __dybatpho_csv_quoted __dybatpho_csv_line __dybatpho_csv_at
  local -a __dybatpho_csv_parts=()

  for __dybatpho_csv_record in "${__dybatpho_csv_out_ref[@]}"; do
    __dybatpho_csv_split_fields_into __dybatpho_csv_parts "${__dybatpho_csv_record}"
    __dybatpho_csv_line=""
    for __dybatpho_csv_at in "${!__dybatpho_csv_parts[@]}"; do
      __dybatpho_csv_quote_into __dybatpho_csv_quoted \
        "${__dybatpho_csv_parts[${__dybatpho_csv_at}]}" "${__dybatpho_csv_delimiter}"
      if ((__dybatpho_csv_at == 0)); then
        __dybatpho_csv_line="${__dybatpho_csv_quoted}"
      else
        __dybatpho_csv_line+="${__dybatpho_csv_delimiter}${__dybatpho_csv_quoted}"
      fi
    done
    printf '%s\n' "${__dybatpho_csv_line}"
  done
}

#######################################
# @description Rewrite CSV with another delimiter.
#   The input is read with `DYBATPHO_CSV_DELIMITER` and written with the
#   delimiter given, quoting each field for the delimiter it is written with:
#   a comma inside a value no longer needs quotes in a TSV file, and a tab
#   inside one does. This is how a comma-separated export becomes TSV, or a
#   semicolon-separated one becomes plain CSV.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Delimiter to write with: one character, or `tab`
# @stdout The records, written with the new delimiter
# @exitcode 0 The input was rewritten
# @exitcode 1 Either delimiter is invalid, or the input contains the ASCII unit separator
# @example
#   dybatpho::csv_convert report.csv tab > report.tsv
#   DYBATPHO_CSV_DELIMITER=tab dybatpho::csv_convert report.tsv ","
#######################################
function dybatpho::csv_convert {
  local input target
  dybatpho::expect_args input target -- "$@"

  local -a records=()
  local text from to
  __dybatpho_csv_delimiter_into from "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_delimiter_into to "${target}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into records "${text}" "${from}"
  __dybatpho_csv_write_with records "${to}"
}

#######################################
# @description Print the column names from the first record.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @stdout One column name per line
# @exitcode 0 The header was read, or the input was empty
# @example
#   dybatpho::csv_header report.csv
#######################################
function dybatpho::csv_header {
  local input
  dybatpho::expect_args input -- "$@"

  local -a records=() names=()
  local text
  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into records "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_header_into names records
  printf '%s\n' "${names[@]}"
}

#######################################
# @description Print one column's values, chosen by its header name.
#   A row shorter than the header reads as an empty value, and a row longer
#   than the header stops the script rather than dropping the extra field.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column name
# @stdout One value per line, excluding the header
# @exitcode 0 The column was printed
# @exitcode 1 No column has that name, or a row has more fields than the header
# @tip A value containing a line break spans lines here; read through
#   `dybatpho::csv_read` when every value has to stay one item
# @example
#   dybatpho::csv_col report.csv "Region"
#######################################
function dybatpho::csv_col {
  local input column
  dybatpho::expect_args input column -- "$@"

  local -a records=() names=() fields=()
  local text index at
  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into records "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_header_into names records
  __dybatpho_csv_column_into index names "${column}"

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    printf '%s\n' "${fields[${index}]-}"
  done
}

#######################################
# @description Stop when a row carries more fields than the header names.
#   Printing such a row would drop the extra field, which is the silent loss
#   this module exists to prevent.
# @arg $1 string Name of the array of fields
# @arg $2 string Name of the array of header names
# @arg $3 number Row number, counting the header as row 0
# @exitcode 0 The row fits the header
# @exitcode 1 The row has more fields than the header
# @internal
#######################################
function __dybatpho_csv_expect_width {
  local -n __dybatpho_csv_row_ref="$1"
  local -n __dybatpho_csv_names_ref="$2"

  ((${#__dybatpho_csv_row_ref[@]} <= ${#__dybatpho_csv_names_ref[@]})) || {
    local __dybatpho_csv_complaint="Row $3 has ${#__dybatpho_csv_row_ref[@]} fields"
    __dybatpho_csv_complaint+=" but the header names ${#__dybatpho_csv_names_ref[@]}:"
    __dybatpho_csv_complaint+=" ${__dybatpho_csv_row_ref[*]}"
    dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_complaint}"
  }
}

#######################################
# @description Keep the rows whose column satisfies a comparison, and print
#   them as CSV with the header.
#   `gt` and `lt` compare as numbers when both values are numeric, and as text
#   otherwise, so a version column sorts the way a reader expects and a size
#   column the way arithmetic does.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column name
# @arg $3 string Operator: `eq`, `ne`, `gt`, `lt`, or `contains`
# @arg $4 string Value to compare against
# @stdout CSV text: the header, then the matching rows
# @exitcode 0 The rows were filtered
# @exitcode 1 No column has that name, the operator is unknown, or a row is wider than the header
# @example
#   dybatpho::csv_filter billing.csv "Cost" gt 100
#######################################
function dybatpho::csv_filter {
  local input column operator value
  dybatpho::expect_args input column operator value -- "$@"

  local operators="eq, ne, gt, lt, or contains"
  case "${operator}" in
    eq | ne | gt | lt | contains) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_filter rejects an operator it does not have" covers this.
    # `dybatpho::die` exits, so that test uses `run`, which clears the trap
    # kcov instruments through; `--exclude-line` reads the marker on the line.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown operator: ${operator}. Use ${operators}" ;; # kcov(skip)
  esac

  local -a records=() names=() fields=() kept=()
  local text index at
  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into records "${text}" "${delimiter}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_header_into names records
  __dybatpho_csv_column_into index names "${column}"
  kept=("${records[0]}")

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    if __dybatpho_csv_matches "${fields[${index}]-}" "${operator}" "${value}"; then
      kept+=("${records[${at}]}")
    fi
  done

  dybatpho::csv_write kept
}

#######################################
# @description Compare one field against a value.
# @arg $1 string Field value
# @arg $2 string Operator
# @arg $3 string Value to compare against
# @exitcode 0 The field satisfies the comparison
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_csv_matches {
  local field="$1" operator="$2" value="$3"

  case "${operator}" in
    eq) [[ "${field}" == "${value}" ]] ;;
    ne) [[ "${field}" != "${value}" ]] ;;
    contains) [[ "${field}" == *"${value}"* ]] ;;
    gt)
      if dybatpho::math_is_number "${field}" && dybatpho::math_is_number "${value}"; then
        dybatpho::math_gt "${field}" "${value}"
      else
        [[ "${field}" > "${value}" ]]
      fi
      ;;
    lt)
      if dybatpho::math_is_number "${field}" && dybatpho::math_is_number "${value}"; then
        dybatpho::math_lt "${field}" "${value}"
      else
        [[ "${field}" < "${value}" ]]
      fi
      ;;
    *) ;; # kcov(skip) - dybatpho::csv_filter rejects an unknown operator first
  esac
}

#######################################
# @description Convert CSV to a JSON array of objects, keyed by the header.
#   Every value is a JSON string, because CSV carries no types and guessing
#   them is how an identifier with leading zeros or a version number becomes
#   the wrong value. Cast in `jq` when a consumer needs numbers.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @stdout Compact JSON array
# @exitcode 0 The conversion succeeded
# @exitcode 1 A row has more fields than the header
# @example
#   dybatpho::csv_to_json report.csv | dybatpho::json_pretty -
#######################################
function dybatpho::csv_to_json {
  local input
  dybatpho::expect_args input -- "$@"

  local -a records=() names=() fields=()
  local text at index object document="" name_json value_json
  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"
  __dybatpho_csv_input_into text "${input}"
  __dybatpho_csv_parse_into records "${text}" "${delimiter}"

  if ((${#records[@]} == 0)); then
    printf '[]\n'
    return 0
  fi

  __dybatpho_csv_header_into names records
  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    object=""
    for index in "${!names[@]}"; do
      name_json="$(dybatpho::json_string "${names[${index}]}")"
      value_json="$(dybatpho::json_string "${fields[${index}]-}")"
      [[ -z "${object}" ]] || object+=","
      object+="${name_json}:${value_json}"
    done
    [[ -z "${document}" ]] || document+=","
    document+="{${object}}"
  done

  printf '[%s]\n' "${document}"
}

#######################################
# @description Convert a JSON array of objects to CSV.
#   The keys of the first object become the header, in their document order,
#   and a later object missing one of them writes an empty value there.
# @arg $1 string JSON file path, `-` for stdin, or JSON text
# @stdout CSV text
# @exitcode 0 The conversion succeeded
# @exitcode 1 The document is not an array of objects
# @exitcode 127 Neither `yq` nor `jq` is installed
# @example
#   dybatpho::csv_from_json pods.json > pods.csv
#######################################
function dybatpho::csv_from_json {
  local input
  dybatpho::expect_args input -- "$@"

  local delimiter
  __dybatpho_csv_delimiter_into delimiter "${DYBATPHO_CSV_DELIMITER}"

  local command_name
  command_name=$(dybatpho::coalesce_cmd jq yq) \
    || dybatpho::die "${FUNCNAME[0]}: Neither jq nor yq is installed" 127

  local text
  if [[ "${input}" == "-" ]]; then
    text="$(cat)"
  elif dybatpho::is file "${input}"; then
    text="$(cat -- "${input}")"
  else
    text="${input}"
  fi

  # Both backends are asked for CSV and the result is then read back and
  # written out by this module, so the quoting a caller sees comes from one
  # place no matter which command was available.
  local converted
  if [[ "${command_name}" == "jq" ]]; then
    local filter='(.[0] | keys_unsorted) as $k'
    filter+=' | ([$k] + [.[] | [ $k[] as $key | (.[$key] // "") | tostring ]])'
    filter+=' | .[] | @csv'
    converted="$(printf '%s' "${text}" | jq -r "${filter}")" \
      || dybatpho::die "${FUNCNAME[0]}: The document is not an array of objects"
  else
    converted="$(printf '%s' "${text}" | yq eval -p=json -o=csv '.')" \
      || dybatpho::die "${FUNCNAME[0]}: The document is not an array of objects"
  fi

  local -a records=()
  # `jq` uses `,` whatever the caller set, so the conversion is read back with
  # the delimiter the backend wrote and written out with the configured one.
  __dybatpho_csv_parse_into records "${converted}" ","
  __dybatpho_csv_write_with records "${delimiter}"
}
