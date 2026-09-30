# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file table.sh
# @brief Utilities for rendering aligned plain-text tables
# @namespace dybatpho
# @description
#   This module contains helpers for rendering delimited row data as aligned
#   plain text, Unicode boxed tables, or Markdown tables. It also supports
#   explicit plain-table alignment rules and lightweight CSV rendering. It
#   targets small script-generated tables where readability matters more than
#   strict CSV parsing.
# @tip Rows are provided as a single multi-line string (or stdin with `-`), and cells are split on an exact delimiter
#   such
#   as `|`, `,`, or `::`
# @see
#   - `example/table_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Return the display width of a table cell.
# @arg $1 string Cell text
# @stdout Cell width
# @internal
#######################################
function __dybatpho_table_cell_width {
  local __dybatpho_cell_width
  __dybatpho_table_width_into __dybatpho_cell_width "${1-}"
  printf '%s\n' "${__dybatpho_cell_width}"
}

#######################################
# @description Measure a cell, writing the width into a named variable.
#   The renderers measure every cell of every row, and reaching the measurement
#   through `$( )` forked once per cell -- the single largest cost in drawing a
#   table.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Cell text
# @set The named variable
# @internal
#######################################
function __dybatpho_table_width_into {
  local __dybatpho_table_width_name="$1"
  local __dybatpho_table_width_text="${2-}"
  if dybatpho::is function __dybatpho_log_width_into; then
    __dybatpho_log_width_into "${__dybatpho_table_width_name}" "${__dybatpho_table_width_text}"
    return 0
  fi
  # kcov(skip) - only when table.sh is used without logging.sh
  local -n __dybatpho_table_width_out="${__dybatpho_table_width_name}"
  __dybatpho_table_width_out="${#__dybatpho_table_width_text}"
}

#######################################
# @description Repeat a string into a named variable, without a subshell.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to repeat
# @arg $3 number Number of repetitions
# @set The named variable
# @internal
#######################################
function __dybatpho_table_repeat_into {
  if dybatpho::is function __dybatpho_log_repeat_into; then
    __dybatpho_log_repeat_into "$@"
    return 0
  fi
  # kcov(skip) - only when table.sh is used without logging.sh
  local -n __dybatpho_table_repeat_out="$1"
  local __dybatpho_table_repeat_index
  __dybatpho_table_repeat_out=""
  for ((__dybatpho_table_repeat_index = 0;  \
  __dybatpho_table_repeat_index < ${3:-0};  \
  __dybatpho_table_repeat_index++)); do
    __dybatpho_table_repeat_out+="${2-}"
  done
}

#######################################
# @description Pad a cell to the requested display width.
# @arg $1 string Cell text
# @arg $2 number Target width
# @stdout Right-padded cell text
# @internal
#######################################
function __dybatpho_table_pad {
  local __dybatpho_pad_result
  __dybatpho_table_pad_into __dybatpho_pad_result "${1-}" "${2-}"
  printf '%s' "${__dybatpho_pad_result}"
}

#######################################
# @description Pad a cell to a width, writing the result into a named variable.
# @arg $1 string Name of the variable receiving the padded cell
# @arg $2 string Cell text
# @arg $3 number Target width
# @set The named variable
# @internal
#######################################
function __dybatpho_table_pad_into {
  local __dybatpho_pad_name="$1"
  local __dybatpho_pad_text="${2-}"
  local __dybatpho_pad_target="${3-}"
  local -n __dybatpho_pad_out="${__dybatpho_pad_name}"

  local __dybatpho_pad_width __dybatpho_pad_padding=""
  __dybatpho_table_width_into __dybatpho_pad_width "${__dybatpho_pad_text}"
  if ((__dybatpho_pad_target > __dybatpho_pad_width)); then
    __dybatpho_table_repeat_into __dybatpho_pad_padding " " \
      "$((__dybatpho_pad_target - __dybatpho_pad_width))"
  fi
  __dybatpho_pad_out="${__dybatpho_pad_text}${__dybatpho_pad_padding}"
}

#######################################
# @description Split one delimited row into trimmed cells.
# @arg $1 string Row text
# @arg $2 string Exact delimiter
# @arg $3 string Name of the array variable to fill
# @internal
#######################################
function __dybatpho_table_split_row {
  local row delimiter target_var
  dybatpho::expect_args row delimiter target_var -- "$@"
  local -n target_ref="${target_var}"
  target_ref=()

  # Splitting and trimming in place. `mapfile < <(dybatpho::split ...)` is a
  # process substitution and `$(dybatpho::trim ...)` is another process per
  # cell, and a table pays both for every cell of every row -- which was most of
  # what drawing one cost.
  local rest="${row}" field
  if [[ -z "${delimiter}" ]]; then
    target_ref=("${row}")
  else
    while [[ "${rest}" == *"${delimiter}"* ]]; do
      field="${rest%%"${delimiter}"*}"
      rest="${rest#*"${delimiter}"}"
      field="${field#"${field%%[![:space:]]*}"}"
      field="${field%"${field##*[![:space:]]}"}"
      target_ref+=("${field}")
    done
    rest="${rest#"${rest%%[![:space:]]*}"}"
    rest="${rest%"${rest##*[![:space:]]}"}"
    target_ref+=("${rest}")
  fi

  if ((${#target_ref[@]} == 0)); then
    target_ref=("") # kcov(skip) - defensive; splitting always yields one field
  fi
}

#######################################
# @description Measure the widest cell in each column across all rows.
# @arg $1 string Name of the row array variable
# @arg $2 string Exact delimiter
# @arg $3 string Name of the width array variable to fill
# @internal
#######################################
function __dybatpho_table_measure_widths {
  local rows_var delimiter widths_var
  dybatpho::expect_args rows_var delimiter widths_var -- "$@"
  local -n rows_ref="${rows_var}"
  local -n widths_ref="${widths_var}"
  local row cell_width index
  local -a cells=()
  widths_ref=()
  # Measuring a cell happens inside `$(...)`, and a subshell cannot hand its
  # learned character widths back, so the whole table is learned once here, in
  # this shell, before any measuring starts.
  if dybatpho::is function __dybatpho_log_learn_widths; then
    for row in "${rows_ref[@]}"; do
      __dybatpho_log_learn_widths "${row}"
    done
  fi

  for row in "${rows_ref[@]}"; do
    __dybatpho_table_split_row "${row}" "${delimiter}" cells
    for index in "${!cells[@]}"; do
      __dybatpho_table_width_into cell_width "${cells[${index}]}"
      if [[ -z "${widths_ref[${index}]+x}" ]] || ((cell_width > widths_ref[index])); then
        widths_ref[index]=${cell_width}
      fi
    done
  done
}

#######################################
# @description Normalize a per-column alignment specification.
# @arg $1 string Comma-separated alignments (`left,right,center`)
# @arg $2 string Name of the widths array variable
# @arg $3 string Name of the alignments array variable to fill
# @internal
#######################################
function __dybatpho_table_parse_alignments {
  local spec widths_var alignments_var
  dybatpho::expect_args spec widths_var alignments_var -- "$@"
  # shellcheck disable=SC2178 # nameref to the caller's array
  local -n widths_ref="${widths_var}"
  # shellcheck disable=SC2178 # nameref to the caller's array
  local -n alignments_ref="${alignments_var}"
  local -a requested=()
  local index alignment

  alignments_ref=()
  if [[ -n "${spec}" ]]; then
    mapfile -t requested < <(dybatpho::split "${spec}" ",")
  fi

  # shellcheck disable=SC2034 # alignments_ref is a nameref: assigning it is the output
  for index in "${!widths_ref[@]}"; do
    local trim
    trim=$(dybatpho::trim "${requested[${index}]-left}")
    alignment="$(dybatpho::lower "${trim}")"
    case "${alignment}" in
      "" | left | l)
        alignments_ref[index]="left"
        ;;
      right | r)
        alignments_ref[index]="right"
        ;;
      center | centre | c)
        alignments_ref[index]="center"
        ;;
      *)
        dybatpho::die "Unsupported table alignment: ${alignment}" # kcov(skip)
        ;;
    esac
  done
}

#######################################
# @description Format a cell according to width and alignment.
# @arg $1 string Cell text
# @arg $2 number Target width
# @arg $3 string Alignment (`left`, `right`, `center`)
# @stdout Formatted cell text
# @internal
#######################################
function __dybatpho_table_format_cell {
  local __dybatpho_format_result
  __dybatpho_table_format_cell_into __dybatpho_format_result "${1-}" "${2-}" "${3-}"
  printf '%s' "${__dybatpho_format_result}"
}

#######################################
# @description Align a cell in its column, writing the result into a named
#   variable rather than onto stdout, so building a row costs no processes.
# @arg $1 string Name of the variable receiving the cell
# @arg $2 string Cell text
# @arg $3 number Column width
# @arg $4 string Alignment: `left`, `right` or `center`
# @set The named variable
# @internal
#######################################
function __dybatpho_table_format_cell_into {
  local __dybatpho_format_name="$1"
  local __dybatpho_format_text="${2-}"
  local __dybatpho_format_target="${3-}"
  local __dybatpho_format_alignment="${4-}"
  local -n __dybatpho_format_out="${__dybatpho_format_name}"

  local __dybatpho_format_width __dybatpho_format_pad_size
  local __dybatpho_format_left __dybatpho_format_right
  __dybatpho_table_width_into __dybatpho_format_width "${__dybatpho_format_text}"
  __dybatpho_format_pad_size=$((__dybatpho_format_target - __dybatpho_format_width))
  if ((__dybatpho_format_pad_size < 0)); then
    __dybatpho_format_pad_size=0 # kcov(skip) - defensive; column widths always cover their cells
  fi

  case "${__dybatpho_format_alignment}" in
    right)
      __dybatpho_table_repeat_into __dybatpho_format_left " " "${__dybatpho_format_pad_size}"
      __dybatpho_format_out="${__dybatpho_format_left}${__dybatpho_format_text}"
      ;;
    center)
      __dybatpho_table_repeat_into __dybatpho_format_left " " \
        "$((__dybatpho_format_pad_size / 2))"
      __dybatpho_table_repeat_into __dybatpho_format_right " " \
        "$((__dybatpho_format_pad_size - __dybatpho_format_pad_size / 2))"
      __dybatpho_format_out="${__dybatpho_format_left}${__dybatpho_format_text}${__dybatpho_format_right}"
      ;;
    *)
      __dybatpho_table_pad_into __dybatpho_format_out \
        "${__dybatpho_format_text}" "${__dybatpho_format_target}"
      ;;
  esac
}

#######################################
# @description Print a Unicode rule line for a boxed table.
# @arg $1 string Left corner character
# @arg $2 string Join character
# @arg $3 string Right corner character
# @arg $4 string Name of the widths array variable
# @stdout Rendered rule line
# @internal
#######################################
function __dybatpho_table_rule {
  local left join right widths_var
  dybatpho::expect_args left join right widths_var -- "$@"
  # shellcheck disable=SC2178 # nameref to the caller's array
  local -n widths_ref="${widths_var}"
  local rule="${left}" index segment

  for index in "${!widths_ref[@]}"; do
    __dybatpho_table_repeat_into segment "─" "$((widths_ref[index] + 2))"
    rule+="${segment}"
    if ((index < ${#widths_ref[@]} - 1)); then
      rule+="${join}"
    fi
  done
  rule+="${right}"
  printf '%s\n' "${rule}"
}

#######################################
# @description Render aligned columns without borders from delimited rows.
# @arg $1 string Input text block or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @stdout Aligned plain-text table
#######################################
function dybatpho::table_print {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  dybatpho::table_align "${input}" "${delimiter}" "" 2
}

#######################################
# @description Render aligned columns with optional per-column alignment rules.
# @arg $1 string Input text block or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @arg $3 string Optional comma-separated alignments (`left,right,center`)
# @arg $4 number Optional gap width between columns, default is 2
# @stdout Aligned plain-text table
#######################################
function dybatpho::table_align {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  local align_spec="${3-}"
  local gap="${4:-2}"
  local -a rows=() widths=() cells=() alignments=()
  local row index line gap_text="" cell_text

  [[ "${gap}" =~ ^[0-9]+$ ]] || dybatpho::die "Gap width must be a non-negative integer: ${gap}"
  __dybatpho_text_read_lines "${input}" rows
  __dybatpho_table_measure_widths rows "${delimiter}" widths
  __dybatpho_table_parse_alignments "${align_spec}" widths alignments
  __dybatpho_table_repeat_into gap_text " " "${gap}"

  for row in "${rows[@]}"; do
    __dybatpho_table_split_row "${row}" "${delimiter}" cells
    line=""
    for ((index = 0; index < ${#widths[@]}; index++)); do
      __dybatpho_table_format_cell_into cell_text \
        "${cells[${index}]-}" "${widths[${index}]}" "${alignments[${index}]}"
      line+="${cell_text}"
      if ((index < ${#widths[@]} - 1)); then
        line+="${gap_text}"
      fi
    done
    printf '%s\n' "${line}"
  done
}

#######################################
# @description Render a Unicode boxed table from delimited rows.
# @arg $1 string Input text block or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @stdout Boxed Unicode table
#######################################
function dybatpho::table_box {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  local -a rows=() widths=() cells=()
  local row row_index index line cell_text

  __dybatpho_text_read_lines "${input}" rows
  __dybatpho_table_measure_widths rows "${delimiter}" widths

  __dybatpho_table_rule "┌" "┬" "┐" widths
  for row_index in "${!rows[@]}"; do
    row="${rows[${row_index}]}"
    __dybatpho_table_split_row "${row}" "${delimiter}" cells
    line="│"
    for ((index = 0; index < ${#widths[@]}; index++)); do
      __dybatpho_table_pad_into cell_text "${cells[${index}]-}" "${widths[${index}]}"
      line+=" ${cell_text} │"
    done
    printf '%s\n' "${line}"
    if ((row_index == 0 && ${#rows[@]} > 1)); then
      __dybatpho_table_rule "├" "┼" "┤" widths
    fi
  done
  __dybatpho_table_rule "└" "┴" "┘" widths
}

#######################################
# @description Render a Markdown table from delimited rows.
# @arg $1 string Input text block or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @stdout Markdown table using the first row as the header
#######################################
function dybatpho::table_markdown {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  local -a rows=() widths=() cells=()
  local row row_index index line separator segment width cell_text

  __dybatpho_text_read_lines "${input}" rows
  __dybatpho_table_measure_widths rows "${delimiter}" widths

  for row_index in "${!rows[@]}"; do
    row="${rows[${row_index}]}"
    __dybatpho_table_split_row "${row}" "${delimiter}" cells
    line="|"
    for ((index = 0; index < ${#widths[@]}; index++)); do
      __dybatpho_table_pad_into cell_text "${cells[${index}]-}" "${widths[${index}]}"
      line+=" ${cell_text} |"
    done
    printf '%s\n' "${line}"

    if ((row_index == 0)); then
      separator="|"
      for width in "${widths[@]}"; do
        if ((width < 3)); then
          width=3
        fi
        __dybatpho_table_repeat_into segment "-" "${width}"
        separator+=" ${segment} |"
      done
      printf '%s\n' "${separator}"
    fi
  done
}

# @env DYBATPHO_TABLE_CSV_STRICT bool Refuse input whose fields are quoted, rather than splitting through the quotes.
#   Default `true`
DYBATPHO_TABLE_CSV_STRICT="${DYBATPHO_TABLE_CSV_STRICT:-true}"

#######################################
# @description Stop when a row looks like quoted CSV, which this module does not
#   parse.
#
#   `dybatpho::table_csv` splits on every comma. That is the right thing for the
#   delimiter-convenience case it exists for — `... | tr -s ' ' ',' |
#   dybatpho::table_csv -` — and the wrong thing for a real CSV file, where a
#   quoted field may contain a comma of its own. Splitting through the quotes
#   turned one field into two, so the row no longer matched its header, and
#   nothing said so: the table was simply wrong, and wrong in a way that looks
#   like data.
#
#   Refusing is not a parser, and does not pretend to be one. It converts silent
#   corruption into an error that names the limitation, which is the part that
#   actually hurt. `DYBATPHO_TABLE_CSV_STRICT=false` restores the old splitting
#   for callers who know their data carries no quoting.
# @arg $1 string Rows to inspect
# @env DYBATPHO_TABLE_CSV_STRICT bool Set to `false` to split through quotes anyway
# @exitcode 0 No row is quoted, or the check is switched off
# @exitcode 1 Stop the script when a field is quoted
# @internal
#######################################
function __dybatpho_table_reject_quoted {
  dybatpho::is true "${DYBATPHO_TABLE_CSV_STRICT}" || return 0

  local -a rows=()
  local row
  __dybatpho_text_read_lines "${1-}" rows

  for row in "${rows[@]}"; do
    # A quote right after a field boundary -- the start of the row or a comma,
    # either of them possibly followed by spaces -- is the shape of a quoted
    # field. A quote anywhere else is just a character in the data, such as the
    # inches in `5" pipe`, and is left alone.
    if [[ "${row}" =~ (^|,)[[:space:]]*\" ]]; then
      dybatpho::die "${FUNCNAME[1]}: This row has a quoted field, which this module does not parse: ${row}
It splits on every comma, so a comma inside a quoted field would silently become a column separator.
Parse it with the csv module first: dybatpho::csv_read reads the quoting,
and dybatpho::csv_write hands back text this renders.
Set DYBATPHO_TABLE_CSV_STRICT=false to split anyway."
    fi
  done

  return 0
}

#######################################
# @description Render lightweight comma-delimited table data using one of the supported styles.
# @arg $1 string Input CSV-like text block or `-` for stdin
# @arg $2 string Optional style: `plain`, `box`, or `markdown`, default is `plain`
# @arg $3 string Optional comma-separated alignments for `plain` style
# @stdout Rendered table
#######################################
function dybatpho::table_csv {
  local input
  dybatpho::expect_args input -- "$@"
  local style="${2:-plain}"
  local align_spec="${3-}"

  # Standard input can only be read once, and both the check below and the
  # renderer need it, so it is materialised here first.
  if [[ "${input}" == "-" ]]; then
    input="$(cat)"
  fi

  __dybatpho_table_reject_quoted "${input}"

  case "${style}" in
    plain)
      dybatpho::table_align "${input}" "," "${align_spec}" 2
      ;;
    box)
      dybatpho::table_box "${input}" ","
      ;;
    markdown)
      dybatpho::table_markdown "${input}" ","
      ;;
    *)
      dybatpho::die "Unsupported table CSV style: ${style}" # kcov(skip)
      ;;
  esac
}
