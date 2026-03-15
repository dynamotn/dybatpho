#!/usr/bin/env bash
# @file table.sh
# @brief Utilities for rendering aligned plain-text tables
# @description
#   This module contains helpers for rendering delimited row data as aligned
#   plain text, Unicode boxed tables, or Markdown tables. It also supports
#   explicit plain-table alignment rules and lightweight CSV rendering. It
#   targets small script-generated tables where readability matters more than
#   strict CSV parsing.
# @tip Rows are provided as a single multi-line string (or stdin with `-`), and cells are split on an exact delimiter such as `|`, `,`, or `::`
# @see
#   - `example/table_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Return the display width of a table cell.
# @arg $1 string Cell text
# @stdout Cell width
#######################################
function __table_cell_width {
  local text="${1-}"
  if dybatpho::is function __string_display_width; then
    __string_display_width "${text}"
  else
    printf '%s\n' "${#text}"
  fi
}

#######################################
# @description Pad a cell to the requested display width.
# @arg $1 string Cell text
# @arg $2 number Target width
# @stdout Right-padded cell text
#######################################
function __table_pad {
  local text target_width
  dybatpho::expect_args text target_width -- "$@"
  local width padding_size=0 padding=""
  width=$(__table_cell_width "${text}")
  if ((target_width > width)); then
    padding_size=$((target_width - width))
    padding="$(dybatpho::string_repeat " " "${padding_size}")"
  fi
  printf '%s%s' "${text}" "${padding}"
}

#######################################
# @description Split one delimited row into trimmed cells.
# @arg $1 string Row text
# @arg $2 string Exact delimiter
# @arg $3 string Name of the array variable to fill
#######################################
function __table_split_row {
  local row delimiter target_var
  dybatpho::expect_args row delimiter target_var -- "$@"
  local -n target_ref="${target_var}"
  local index
  target_ref=()

  mapfile -t target_ref < <(dybatpho::split "${row}" "${delimiter}")
  if ((${#target_ref[@]} == 0)); then
    target_ref=("")
  fi

  for index in "${!target_ref[@]}"; do
    target_ref[${index}]="$(dybatpho::trim "${target_ref[${index}]}")"
  done
}

#######################################
# @description Measure the widest cell in each column across all rows.
# @arg $1 string Name of the row array variable
# @arg $2 string Exact delimiter
# @arg $3 string Name of the width array variable to fill
#######################################
function __table_measure_widths {
  local rows_var delimiter widths_var
  dybatpho::expect_args rows_var delimiter widths_var -- "$@"
  local -n rows_ref="${rows_var}"
  local -n widths_ref="${widths_var}"
  local row cell_width index
  local -a cells=()
  widths_ref=()

  for row in "${rows_ref[@]}"; do
    __table_split_row "${row}" "${delimiter}" cells
    for index in "${!cells[@]}"; do
      cell_width=$(__table_cell_width "${cells[${index}]}")
      if [[ -z "${widths_ref[${index}]+x}" ]] || ((cell_width > widths_ref[${index}])); then
        widths_ref[${index}]=${cell_width}
      fi
    done
  done
}

#######################################
# @description Normalize a per-column alignment specification.
# @arg $1 string Comma-separated alignments (`left,right,center`)
# @arg $2 string Name of the widths array variable
# @arg $3 string Name of the alignments array variable to fill
#######################################
function __table_parse_alignments {
  local spec widths_var alignments_var
  dybatpho::expect_args spec widths_var alignments_var -- "$@"
  local -n widths_ref="${widths_var}"
  local -n alignments_ref="${alignments_var}"
  local -a requested=()
  local index alignment

  alignments_ref=()
  if [[ -n "${spec}" ]]; then
    mapfile -t requested < <(dybatpho::split "${spec}" ",")
  fi

  for index in "${!widths_ref[@]}"; do
    alignment="$(dybatpho::lower "$(dybatpho::trim "${requested[${index}]-left}")")"
    case "${alignment}" in
      "" | left | l)
        alignments_ref[${index}]="left"
        ;;
      right | r)
        alignments_ref[${index}]="right"
        ;;
      center | centre | c)
        alignments_ref[${index}]="center"
        ;;
      *)
        dybatpho::die "Unsupported table alignment: ${alignment}"
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
#######################################
function __table_format_cell {
  local text target_width alignment
  dybatpho::expect_args text target_width alignment -- "$@"
  local width padding_size left_pad_size right_pad_size padding=""
  width=$(__table_cell_width "${text}")
  padding_size=$((target_width - width))
  if ((padding_size < 0)); then
    padding_size=0
  fi

  case "${alignment}" in
    right)
      padding="$(dybatpho::string_repeat " " "${padding_size}")"
      printf '%s%s' "${padding}" "${text}"
      ;;
    center)
      left_pad_size=$((padding_size / 2))
      right_pad_size=$((padding_size - left_pad_size))
      printf '%s%s%s' \
        "$(dybatpho::string_repeat " " "${left_pad_size}")" \
        "${text}" \
        "$(dybatpho::string_repeat " " "${right_pad_size}")"
      ;;
    *)
      __table_pad "${text}" "${target_width}"
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
#######################################
function _table_rule {
  local left join right widths_var
  dybatpho::expect_args left join right widths_var -- "$@"
  local -n widths_ref="${widths_var}"
  local rule="${left}" index segment

  for index in "${!widths_ref[@]}"; do
    segment="$(dybatpho::string_repeat "─" "$((widths_ref[${index}] + 2))")"
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
  local row index line gap_text=""

  [[ "${gap}" =~ ^[0-9]+$ ]] || dybatpho::die "Gap width must be a non-negative integer: ${gap}"
  __text_read_lines "${input}" rows
  __table_measure_widths rows "${delimiter}" widths
  __table_parse_alignments "${align_spec}" widths alignments
  gap_text="$(dybatpho::string_repeat " " "${gap}")"

  for row in "${rows[@]}"; do
    __table_split_row "${row}" "${delimiter}" cells
    line=""
    for ((index = 0; index < ${#widths[@]}; index++)); do
      line+="$(__table_format_cell "${cells[${index}]-}" "${widths[${index}]}" "${alignments[${index}]}")"
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
  local row row_index index line

  __text_read_lines "${input}" rows
  __table_measure_widths rows "${delimiter}" widths

  _table_rule "┌" "┬" "┐" widths
  for row_index in "${!rows[@]}"; do
    row="${rows[${row_index}]}"
    __table_split_row "${row}" "${delimiter}" cells
    line="│"
    for ((index = 0; index < ${#widths[@]}; index++)); do
      line+=" $(__table_pad "${cells[${index}]-}" "${widths[${index}]}") │"
    done
    printf '%s\n' "${line}"
    if ((row_index == 0 && ${#rows[@]} > 1)); then
      _table_rule "├" "┼" "┤" widths
    fi
  done
  _table_rule "└" "┴" "┘" widths
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
  local row row_index index line separator segment width

  __text_read_lines "${input}" rows
  __table_measure_widths rows "${delimiter}" widths

  for row_index in "${!rows[@]}"; do
    row="${rows[${row_index}]}"
    __table_split_row "${row}" "${delimiter}" cells
    line="|"
    for ((index = 0; index < ${#widths[@]}; index++)); do
      line+=" $(__table_pad "${cells[${index}]-}" "${widths[${index}]}") |"
    done
    printf '%s\n' "${line}"

    if ((row_index == 0)); then
      separator="|"
      for width in "${widths[@]}"; do
        if ((width < 3)); then
          width=3
        fi
        segment="$(dybatpho::string_repeat "-" "${width}")"
        separator+=" ${segment} |"
      done
      printf '%s\n' "${separator}"
    fi
  done
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
      dybatpho::die "Unsupported table CSV style: ${style}"
      ;;
  esac
}
