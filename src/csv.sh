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
  local __dybatpho_csv_wanted="$2" __dybatpho_csv_caller="${3:-${FUNCNAME[1]}}"

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
        __dybatpho_csv_problem+=" cannot separate fields"                     # kcov(skip)
        ;;
      *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
    esac
  fi

  if [[ -n "${__dybatpho_csv_problem}" ]]; then
    local __dybatpho_csv_shown                                                                    # kcov(skip)
    printf -v __dybatpho_csv_shown '%q' "${__dybatpho_csv_wanted}"                                # kcov(skip)
    __dybatpho_csv_problem="Invalid delimiter ${__dybatpho_csv_shown}: ${__dybatpho_csv_problem}" # kcov(skip)
    dybatpho::die "${__dybatpho_csv_caller}: ${__dybatpho_csv_problem}"                           # kcov(skip)
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
# @arg $3 string Name the unit-separator refusal is reported under, default is the calling function
# @set The named variable
# @internal
#######################################
function __dybatpho_csv_input_into {
  local -n __dybatpho_csv_input_ref="$1"
  local __dybatpho_csv_source="$2" __dybatpho_csv_who="${3:-${FUNCNAME[1]:-${FUNCNAME[0]}}}"

  __dybatpho_string_input_into __dybatpho_csv_input_ref "${__dybatpho_csv_source}" files

  local __dybatpho_csv_reason="The input contains the ASCII unit separator,"
  __dybatpho_csv_reason+=" which this module uses to join a record's fields"
  [[ "${__dybatpho_csv_input_ref}" != *"${__dybatpho_csv_unit}"* ]] || dybatpho::die \
    "${__dybatpho_csv_who}: ${__dybatpho_csv_reason}"
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
      # When no delimiter follows, the stray text is the end of the record:
      # leaving it in the remainder made the next pass read it again as a
      # field of its own.
      if [[ -n "${__dybatpho_csv_rest}" && "${__dybatpho_csv_rest}" != "${__dybatpho_csv_delimiter}"* ]]; then
        __dybatpho_csv_field+="${__dybatpho_csv_rest%%"${__dybatpho_csv_delimiter}"*}"
        __dybatpho_csv_fields_ref+=("${__dybatpho_csv_field}")
        [[ "${__dybatpho_csv_rest}" == *"${__dybatpho_csv_delimiter}"* ]] || break
        __dybatpho_csv_rest="${__dybatpho_csv_rest#*"${__dybatpho_csv_delimiter}"}"
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
# @description Read a public function's input the way every reader in this
#   module starts: resolve the delimiter, read the input, parse it into
#   records, and split the header into column names.
#   Errors are reported under the public function that called this.
# @arg $1 string Name of the array receiving the records
# @arg $2 string Name of the array receiving the header's column names, empty for empty input
# @arg $3 string Name of the variable receiving the delimiter
# @arg $4 string File path, `-` for stdin, or CSV text
# @set The three named variables
# @internal
#######################################
function __dybatpho_csv_load_into {
  local __dybatpho_csv_load_text
  __dybatpho_csv_delimiter_into "$3" "${DYBATPHO_CSV_DELIMITER}" "${FUNCNAME[1]}"
  __dybatpho_csv_input_into __dybatpho_csv_load_text "$4" "${FUNCNAME[1]}"
  local -n __dybatpho_csv_load_delim="$3"
  __dybatpho_csv_parse_into "$1" "${__dybatpho_csv_load_text}" "${__dybatpho_csv_load_delim}"
  __dybatpho_csv_header_into "$2" "$1"
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
  local delimiter
  __dybatpho_csv_load_into records names delimiter "${input}"
  ((${#records[@]})) || return 0

  printf '%s\n' "${names[@]}"
}

#######################################
# @description Print one column's values, chosen by its header name or by its
#   1-based position when no header carries that name.
#   A row shorter than the header reads as an empty value, and a row longer
#   than the header stops the script rather than dropping the extra field.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column: header name, or 1-based position
# @stdout One value per line, excluding the header
# @exitcode 0 The column was printed
# @exitcode 1 No column has that name or position, or a row has more fields than the header
# @tip A value containing a line break spans lines here; read through
#   `dybatpho::csv_read` when every value has to stay one item
# @example
#   dybatpho::csv_col report.csv "Region"
#######################################
function dybatpho::csv_col {
  local input column
  dybatpho::expect_args input column -- "$@"

  local -a records=() names=() fields=()
  local index at
  local delimiter
  __dybatpho_csv_load_into records names delimiter "${input}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"

  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    printf '%s\n' "${fields[${index}]-}"
  done
}

#######################################
# @description Print chosen columns, in the order given, as CSV with the header.
#   A column is named by its header, or by its position counting from `1` when
#   no header carries that name, so `3` picks the third column unless a column
#   is literally called `3`. A column may be chosen more than once, and a row
#   shorter than the header reads as empty values.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $@ string Columns to keep: header names or 1-based positions
# @stdout CSV text: the chosen header, then every row's chosen fields
# @exitcode 0 The columns were printed, or the input was empty
# @exitcode 1 A column matches neither a name nor a position, or a row is wider than the header
# @example
#   dybatpho::csv_select billing.csv owner cost
#   dybatpho::csv_select billing.csv 4 1   # cost first, then service
#######################################
function dybatpho::csv_select {
  local input
  dybatpho::expect_args input -- "$@"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Name at least one column to keep"

  local -a records=() names=() fields=() picks=() chosen=() kept=()
  local delimiter column index at pick
  local IFS
  __dybatpho_csv_load_into records names delimiter "${input}"
  ((${#records[@]})) || return 0

  for column in "$@"; do
    __dybatpho_csv_pick_into index names "${column}"
    picks+=("${index}")
  done

  for ((at = 0; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    chosen=()
    for pick in "${picks[@]}"; do
      chosen+=("${fields[${pick}]-}")
    done
    IFS="${__dybatpho_csv_unit}"
    kept+=("${chosen[*]}")
    unset IFS
  done

  __dybatpho_csv_write_with kept "${delimiter}"
}

#######################################
# @description Sort the data rows by one column and print them as CSV with
#   the header first.
#   The sort is stable, so rows with equal keys keep their input order, and it
#   happens in Bash rather than through `sort`, because a value may hold a line
#   break. `auto` compares as numbers when every non-empty value in the column
#   is one, and as text otherwise; text compares byte by byte, the same on
#   every machine whatever its locale. An empty value sorts last in either
#   direction, so blanks never push the rows that matter off the top.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Column: header name, or 1-based position
# @arg $3 string Order: `asc` (default) or `desc`
# @arg $4 string Comparison: `auto` (default), `text`, or `number`
# @stdout CSV text: the header, then the sorted rows
# @exitcode 0 The rows were sorted, or the input was empty
# @exitcode 1 An unknown column, order or comparison, a non-number under `number`, or a row wider than the header
# @example
#   dybatpho::csv_sort billing.csv cost desc
#   dybatpho::csv_sort billing.csv owner asc text
#######################################
function dybatpho::csv_sort {
  local input column order type
  dybatpho::expect_args input column -- "$@"
  order="${3:-asc}"
  type="${4:-auto}"

  case "${order}" in
    asc | desc) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_sort rejects an unknown order, comparison or value" covers
    # this; `dybatpho::die` exits, so that test uses `run`.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown order: ${order}. Use asc or desc" ;; # kcov(skip)
  esac
  case "${type}" in
    # A case arm has no command to fire on.
    auto | text | number) ;;                                                                     # kcov(skip)
    *) dybatpho::die "${FUNCNAME[0]}: Unknown comparison: ${type}. Use auto, text, or number" ;; # kcov(skip)
  esac

  local -a records=() names=() fields=() keys=() order_of=() sorted=()
  local delimiter index at key
  __dybatpho_csv_load_into records names delimiter "${input}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"

  local all_numbers=1
  for ((at = 1; at < ${#records[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${records[${at}]}"
    __dybatpho_csv_expect_width fields names "${at}"
    key="${fields[${index}]-}"
    keys[at]="${key}"
    order_of+=("${at}")
    [[ -z "${key}" ]] || dybatpho::math_is_number "${key}" || {
      [[ "${type}" != "number" ]] \
        || dybatpho::die "${FUNCNAME[0]}: Row ${at} has ${column}=${key}, which is not a number" # kcov(skip)
      all_numbers=0
    }
  done

  [[ "${type}" != "auto" ]] || {
    type="text"
    ((all_numbers == 0)) || type="number"
  }
  if [[ "${type}" == "number" ]]; then
    # Encode each number once into a key that orders correctly as text, so
    # the merge compares strings instead of parsing two numbers every time.
    for at in "${!keys[@]}"; do
      [[ -z "${keys[${at}]}" ]] || __dybatpho_math_sort_key_into "keys[${at}]" "${keys[${at}]}"
    done
  fi

  __dybatpho_helpers_sort order_of __dybatpho_csv_row_before keys "${order}"

  sorted=("${records[0]}")
  for at in "${order_of[@]}"; do
    sorted+=("${records[${at}]}")
  done
  __dybatpho_csv_write_with sorted "${delimiter}"
}

#######################################
# @description Join two CSV inputs on a key column and print the result as
#   CSV.
#   The output header is every left column followed by every right column
#   except the right key, which would repeat the left one. Rows come out in
#   the left input's order, and a left row matching several right rows gives
#   one output row per match, in the right input's order, the way SQL does.
#   `inner` keeps only the left rows with a match; `left` keeps every left row
#   and leaves the right columns empty where nothing matched. An empty key
#   matches nothing, the way SQL's `NULL` does, so blank cells never pair up
#   into rows nobody meant to relate.
# @arg $1 string Left CSV: file path, `-` for stdin, or CSV text
# @arg $2 string Right CSV: file path, `-` for stdin, or CSV text
# @arg $3 string Key column in the left input: header name, or 1-based position
# @arg $4 string Join type: `inner` (default) or `left`
# @arg $5 string Key column in the right input, the same way, default is the left one
# @stdout CSV text: the joined header, then the joined rows
# @exitcode 0 The inputs were joined
# @exitcode 1 An unknown join type or key column, both inputs read from stdin, or a row wider than its header
# @tip A column named the same on both sides appears twice in the output;
#   `dybatpho::csv_col` and the other by-name helpers then read the left one
# @example
#   dybatpho::csv_join services.csv owners.csv team
#   dybatpho::csv_join services.csv costs.csv service left name
#######################################
function dybatpho::csv_join {
  local left_input right_input key type right_key
  dybatpho::expect_args left_input right_input key -- "$@"
  type="${4:-inner}"
  right_key="${5:-${key}}"

  case "${type}" in
    inner | left) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::csv_join rejects an unknown type, a missing key and two
    # stdins" covers this; `dybatpho::die` exits, so that test uses `run`.
    *) dybatpho::die "${FUNCNAME[0]}: Unknown join type: ${type}. Use inner or left" ;; # kcov(skip)
  esac
  [[ "${left_input}" != "-" || "${right_input}" != "-" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Only one input can be read from stdin" # kcov(skip)

  local -a left=() right=() left_names=() right_names=() fields=() extra=() joined=()
  local delimiter left_index right_index at value row
  local -A matches=()
  local IFS
  __dybatpho_csv_load_into left left_names delimiter "${left_input}"
  __dybatpho_csv_load_into right right_names delimiter "${right_input}"
  ((${#left[@]})) || return 0

  __dybatpho_csv_pick_into left_index left_names "${key}"
  ((${#right[@]})) || right_names=("${right_key}")
  __dybatpho_csv_pick_into right_index right_names "${right_key}"

  # Index the right rows by key, keeping every match in input order.
  local -a right_rest=()
  for ((at = 1; at < ${#right[@]}; at++)); do
    __dybatpho_csv_split_fields_into fields "${right[${at}]}"
    __dybatpho_csv_expect_width fields right_names "${at}"
    value="${fields[${right_index}]-}"
    [[ -n "${value}" ]] || continue
    matches["${value}"]+="${matches[${value}]+ }${at}"
  done

  __dybatpho_csv_without_into extra right_names "${right_index}"
  IFS="${__dybatpho_csv_unit}"
  joined=("${left_names[*]}${__dybatpho_csv_unit}${extra[*]}")
  unset IFS

  local -a empty_right=()
  for ((at = 1; at < ${#right_names[@]}; at++)); do
    empty_right+=("")
  done

  local -a left_fields=()
  for ((at = 1; at < ${#left[@]}; at++)); do
    __dybatpho_csv_split_fields_into left_fields "${left[${at}]}"
    __dybatpho_csv_expect_width left_fields left_names "${at}"
    # Pad a short row, so the right columns line up under their header.
    while ((${#left_fields[@]} < ${#left_names[@]})); do
      left_fields+=("")
    done
    value="${left_fields[${left_index}]}"

    if [[ -n "${value}" && -n "${matches[${value}]+set}" ]]; then
      for row in ${matches[${value}]}; do
        __dybatpho_csv_split_fields_into fields "${right[${row}]}"
        while ((${#fields[@]} < ${#right_names[@]})); do
          fields+=("")
        done
        __dybatpho_csv_without_into right_rest fields "${right_index}"
        IFS="${__dybatpho_csv_unit}"
        joined+=("${left_fields[*]}${__dybatpho_csv_unit}${right_rest[*]}")
        unset IFS
      done
    elif [[ "${type}" == "left" ]]; then
      IFS="${__dybatpho_csv_unit}"
      joined+=("${left_fields[*]}${__dybatpho_csv_unit}${empty_right[*]}")
      unset IFS
    fi
  done

  # A right side holding nothing but its key leaves no column to append, and
  # the joined records then carry one trailing empty field too many.
  if ((${#right_names[@]} == 1)); then
    for at in "${!joined[@]}"; do
      joined[at]="${joined[${at}]%"${__dybatpho_csv_unit}"}"
    done
  fi
  __dybatpho_csv_write_with joined "${delimiter}"
}

#######################################
# @description Copy an array without the element at one index, into a named
#   array.
# @arg $1 string Name of the array variable to fill
# @arg $2 string Name of the source array
# @arg $3 number Index to leave out
# @set The named array
# @internal
#######################################
function __dybatpho_csv_without_into {
  local -n __dybatpho_csv_without_ref="$1"
  local -n __dybatpho_csv_source_ref="$2"
  local __dybatpho_csv_skip="$3" __dybatpho_csv_at
  __dybatpho_csv_without_ref=()

  for __dybatpho_csv_at in "${!__dybatpho_csv_source_ref[@]}"; do
    ((__dybatpho_csv_at == __dybatpho_csv_skip)) \
      || __dybatpho_csv_without_ref+=("${__dybatpho_csv_source_ref[${__dybatpho_csv_at}]}")
  done
}

#######################################
# @description Return success when one row's key strictly comes before
#   another's in the requested order, comparing bytes, for
#   `__dybatpho_helpers_sort`. An empty key comes after every other key,
#   whichever the direction.
# @arg $1 string Row number that might come first
# @arg $2 string Row number it is compared with
# @arg $3 string Name of the array mapping a row number to its key
# @arg $4 string `asc` or `desc`
# @exitcode 0 The first row comes first
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_csv_row_before {
  local -n __dybatpho_csv_before_keys="$3"
  local __dybatpho_csv_first="${__dybatpho_csv_before_keys[$1]}"
  local __dybatpho_csv_second="${__dybatpho_csv_before_keys[$2]}" LC_ALL=C

  [[ -n "${__dybatpho_csv_first}" ]] || return 1
  [[ -n "${__dybatpho_csv_second}" ]] || return 0
  if [[ "$4" == "desc" ]]; then
    [[ "${__dybatpho_csv_second}" < "${__dybatpho_csv_first}" ]]
  else
    [[ "${__dybatpho_csv_first}" < "${__dybatpho_csv_second}" ]]
  fi
}

#######################################
# @description Resolve a column given by name or by 1-based position to its
#   index, into a named variable. A header name wins over a position, so a
#   column literally called `2` is still reachable by name.
# @arg $1 string Name of the variable receiving the index
# @arg $2 string Name of the array of header names
# @arg $3 string Header name, or a position counting from `1`
# @set The named variable
# @exitcode 0 The column was found
# @exitcode 1 Neither a name nor a position matches
# @internal
#######################################
function __dybatpho_csv_pick_into {
  local -n __dybatpho_csv_pick_ref="$1"
  local -n __dybatpho_csv_header_ref="$2"
  local __dybatpho_csv_wanted="$3" __dybatpho_csv_at

  for __dybatpho_csv_at in "${!__dybatpho_csv_header_ref[@]}"; do
    if [[ "${__dybatpho_csv_header_ref[${__dybatpho_csv_at}]}" == "${__dybatpho_csv_wanted}" ]]; then
      __dybatpho_csv_pick_ref="${__dybatpho_csv_at}"
      return 0
    fi
  done

  if [[ "${__dybatpho_csv_wanted}" =~ ^[1-9][0-9]*$ ]] \
    && ((10#${__dybatpho_csv_wanted} <= ${#__dybatpho_csv_header_ref[@]})); then
    __dybatpho_csv_pick_ref="$((10#${__dybatpho_csv_wanted} - 1))"
    return 0
  fi

  local __dybatpho_csv_complaint="No such column: ${__dybatpho_csv_wanted}."
  __dybatpho_csv_complaint+=" The header has ${#__dybatpho_csv_header_ref[@]} columns:"
  __dybatpho_csv_complaint+=" ${__dybatpho_csv_header_ref[*]}"
  # "dybatpho::csv_select reports a column that is neither a name nor a
  # position" covers this; `dybatpho::die` exits, so that test uses `run`.
  dybatpho::die "${FUNCNAME[1]}: ${__dybatpho_csv_complaint}" # kcov(skip)
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
# @arg $2 string Column: header name, or 1-based position
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
  local index at
  local delimiter
  __dybatpho_csv_load_into records names delimiter "${input}"
  ((${#records[@]})) || return 0

  __dybatpho_csv_pick_into index names "${column}"
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
# @note Needs the `json` module: `dybatpho::load json`, or `--modules csv json`
#######################################
function dybatpho::csv_to_json {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_csv_need_json

  local -a records=() names=() fields=()
  local at index object document="" name_json value_json
  local delimiter
  __dybatpho_csv_load_into records names delimiter "${input}"

  if ((${#records[@]} == 0)); then
    printf '[]\n'
    return 0
  fi

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
# @description Stop unless the `json` module is loaded.
#   Encoding each value as a JSON string is the `json` module's work, and only
#   the conversion to JSON does it: reading, filtering, sorting, joining and
#   the conversion from JSON, which runs `jq` or `yq` itself, need nothing from
#   it. Registering it as a dependency would load it into every script that
#   only reads a spreadsheet -- and into every `table` that renders one -- so
#   the conversion asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `json`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `json` module is not loaded
# @internal
#######################################
function __dybatpho_csv_need_json {
  __dybatpho_helpers_need_module json __dybatpho_json_escape_into "${FUNCNAME[1]}"
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
  __dybatpho_string_input_into text "${input}" files

  # Both backends are asked for CSV and the result is then read back and
  # written out by this module, so the quoting a caller sees comes from one
  # place no matter which command was available.
  local converted
  if [[ "${command_name}" == "jq" ]]; then
    # An empty array has no first object to take a header from, and is still
    # an array of objects: it converts to nothing, as it does through `yq`.
    local filter='if . == [] then empty else'
    filter+=' (.[0] | keys_unsorted) as $k'
    filter+=' | ([$k] + [.[] | [ $k[] as $key | (.[$key] // "") | tostring ]])'
    filter+=' | .[] | @csv end'
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
