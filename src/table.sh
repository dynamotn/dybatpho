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
# @description Measure a cell, writing the width into a named variable.
#   The renderers measure every cell of every row, and reaching the measurement
#   through `$( )` forked once per cell -- the single largest cost in drawing a
#   table. The measurement is the one `text` uses: ANSI colour is stripped
#   first, so a coloured cell is padded by what the terminal shows.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Cell text
# @set The named variable
# @internal
#######################################
function __dybatpho_table_width_into {
  __dybatpho_text_width_into "$1" "${2-}"
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
    __dybatpho_log_repeat_into __dybatpho_pad_padding " " \
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
  # The character widths are learned once for the whole table, in this shell,
  # so measuring each cell afterwards reads them instead of asking again.
  for row in "${rows_ref[@]}"; do
    __dybatpho_log_learn_widths "${row}"
  done

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
      __dybatpho_log_repeat_into __dybatpho_format_left " " "${__dybatpho_format_pad_size}"
      __dybatpho_format_out="${__dybatpho_format_left}${__dybatpho_format_text}"
      ;;
    center)
      __dybatpho_log_repeat_into __dybatpho_format_left " " \
        "$((__dybatpho_format_pad_size / 2))"
      __dybatpho_log_repeat_into __dybatpho_format_right " " \
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
    __dybatpho_log_repeat_into segment "─" "$((widths_ref[index] + 2))"
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
  __dybatpho_log_repeat_into gap_text " " "${gap}"

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
    # Cells are trimmed, so anything after the last non-blank character is
    # padding the last column does not need.
    line="${line%"${line##*[! ]}"}"
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
        __dybatpho_log_repeat_into segment "-" "${width}"
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

#######################################
# @description Render real CSV as a table, quoting and all.
#   Unlike `dybatpho::table_csv`, which splits on every comma, this parses the
#   input with `dybatpho::csv_read` first, so a quoted comma stays inside its
#   cell, a doubled quote is one quote, and `DYBATPHO_CSV_DELIMITER` picks a
#   semicolon or `tab` file. A table row is one line, so a line break inside a
#   value is drawn as a space; the Markdown style also escapes `|` so a value
#   cannot open a column of its own. Cells are trimmed, as in every renderer
#   here.
# @arg $1 string CSV file path, `-` for stdin, or CSV text
# @arg $2 string Optional style: `plain`, `box`, or `markdown`, default is `plain`
# @arg $3 string Optional comma-separated alignments for `plain` style
# @stdout Rendered table, or nothing for an empty input
# @exitcode 0 The table was rendered
# @exitcode 1 The style is unknown, or the CSV cannot be read
# @example
#   dybatpho::table_from_csv billing.csv box
#   dybatpho::csv_sort billing.csv cost desc | dybatpho::table_from_csv - plain "left,left,right"
#######################################
function dybatpho::table_from_csv {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_table_need_csv
  local style="${2:-plain}"
  local align_spec="${3-}"
  __dybatpho_table_expect_style "${style}"

  local -a records=() fields=()
  dybatpho::csv_read "${input}" records
  ((${#records[@]})) || return 0

  # The unit separator is the one byte `dybatpho::csv_read` guarantees no value
  # holds, so it can stand between the cells without being mistaken for data.
  local unit=$'\037' record field text=""
  local -a cells=()
  local IFS
  for record in "${records[@]}"; do
    dybatpho::csv_fields "${record}" fields
    cells=()
    for field in "${fields[@]}"; do
      field="${field//$'\r\n'/ }"
      field="${field//[$'\r\n']/ }"
      [[ "${style}" != "markdown" ]] || field="${field//|/\\|}"
      cells+=("${field}")
    done
    IFS="${unit}"
    text+="${cells[*]}"$'\n'
    unset IFS
  done

  __dybatpho_table_render "${style}" "${unit}" "${align_spec}" <<< "${text%$'\n'}"
}

#######################################
# @description Render a JSON array of objects as a table.
#   The keys of the first object become the header, in document order, and a
#   later object missing one of them leaves that cell empty -- the conversion
#   `dybatpho::csv_from_json` performs, rendered through
#   `dybatpho::table_from_csv`.
# @arg $1 string JSON file path, `-` for stdin, or JSON text
# @arg $2 string Optional style: `plain`, `box`, or `markdown`, default is `plain`
# @arg $3 string Optional comma-separated alignments for `plain` style
# @stdout Rendered table, or nothing for an empty array
# @exitcode 0 The table was rendered
# @exitcode 1 The style is unknown, or the document is not an array of objects
# @exitcode 127 Neither `jq` nor `yq` is installed
# @example
#   kubectl get pods -o json | jq '[.items[] | {name: .metadata.name, phase: .status.phase}]' \
#     | dybatpho::table_from_json - box
#######################################
function dybatpho::table_from_json {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_table_need_csv
  local style="${2:-plain}"
  local align_spec="${3-}"
  __dybatpho_table_expect_style "${style}"

  local document
  if [[ "${input}" == "-" ]]; then
    document="$(cat)"
  elif dybatpho::is file "${input}"; then
    document="$(cat -- "${input}")"
  else
    document="${input}"
  fi
  # The conversion has to run in a command substitution to capture its CSV, so
  # its failure is carried out by status rather than lost with the subshell.
  local csv status=0
  csv="$(DYBATPHO_CSV_DELIMITER="," dybatpho::csv_from_json "${document}")" || status=$?
  ((status == 0)) || return "${status}"
  DYBATPHO_CSV_DELIMITER="," dybatpho::table_from_csv - "${style}" "${align_spec}" <<< "${csv}"
}

#######################################
# @description Stop unless the `csv` module is loaded.
#   Reading CSV and turning JSON records into rows is the `csv` module's work,
#   and it brings `json` and `math` with it. Registering it as a dependency
#   would load all three into every script that draws a plain table -- and
#   through `text`, `markdown` and `testing`, far more scripts than that -- so
#   the two renderers that need it ask for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `csv`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `csv` module is not loaded
# @internal
#######################################
function __dybatpho_table_need_csv {
  __dybatpho_helpers_need_module csv __dybatpho_csv_parse_into "${FUNCNAME[1]}"
}

#######################################
# @description Stop on a table style no renderer draws.
# @arg $1 string Style
# @exitcode 0 The style is `plain`, `box`, or `markdown`
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_table_expect_style {
  case "$1" in
    plain | box | markdown) ;; # kcov(skip) - a case arm has no command to fire on
    # "dybatpho::table_from_csv and table_from_json reject an unknown style"
    # covers this; `dybatpho::die` exits, so that test uses `run`.
    *) dybatpho::die "${FUNCNAME[1]}: Unsupported table style: $1. Use plain, box, or markdown" ;; # kcov(skip)
  esac
}

#######################################
# @description Draw rows read from stdin in one of the three styles.
#   Reading stdin rather than taking the text as an argument means a table whose
#   only cell is `-` is drawn, not taken for a request to read stdin.
# @arg $1 string Style: `plain`, `box`, or `markdown`
# @arg $2 string Exact delimiter between cells
# @arg $3 string Comma-separated alignments for `plain` style
# @stdout Rendered table
# @internal
#######################################
function __dybatpho_table_render {
  case "$1" in
    box) dybatpho::table_box - "$2" ;;
    markdown) dybatpho::table_markdown - "$2" ;;
    *) dybatpho::table_align - "$2" "$3" 2 ;;
  esac
}
