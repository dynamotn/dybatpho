# shellcheck shell=bash
# @file text.sh
# @brief Utilities for working with multi-line text blocks
# @namespace dybatpho
# @description
#   This module contains helpers for formatting larger text blocks: indenting
#   each line, removing shared indentation, stripping ANSI escape sequences,
#   turning lines into bullet lists, aligning simple delimited columns,
#   drawing a border around a block, centering lines, numbering them, and
#   cutting a long block short. It is useful when shell scripts need to prepare
#   readable console output, embed heredocs, or normalize text before writing
#   files.
#
#   The helpers that pad or center measure each line by what a terminal shows:
#   ANSI escape sequences count for nothing, and when the `screen` module is
#   loaded its Unicode-aware measurement is used, so a CJK character or an emoji
#   counts for the two columns it occupies. Without `screen`, a line is measured
#   by its character count, which is exact for every character one column wide.
# @see
#   - `example/text_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Read a text argument or stdin into a target array of lines.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Name of the array variable to fill
# @internal
#######################################
function __dybatpho_text_read_lines {
  local input target_var
  dybatpho::expect_args input target_var -- "$@"
  local -n target_ref="${target_var}"
  target_ref=()

  if [[ "${input}" == "-" ]]; then
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
      target_ref+=("${line}")
    done
  else
    mapfile -t target_ref <<< "${input}"
  fi

  if ((${#target_ref[@]} == 0)); then
    target_ref=("")
  fi
}

#######################################
# @description Prefix every line in a text block with the given indent string.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Optional indent prefix, default is two spaces
# @stdout Indented text block
#######################################
function dybatpho::text_indent {
  local input
  dybatpho::expect_args input -- "$@"
  local prefix="${2:-  }"
  local -a lines=()
  local line

  __dybatpho_text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    printf '%s%s\n' "${prefix}" "${line}"
  done
}

#######################################
# @description Remove the shared leading indentation from a text block.
# @arg $1 string Input text or `-` for stdin
# @stdout Dedented text block
#######################################
function dybatpho::text_dedent {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()
  local line indent_length min_indent=-1

  __dybatpho_text_read_lines "${input}" lines

  for line in "${lines[@]}"; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      continue
    fi

    # Blank lines are skipped above, so every remaining line has this shape.
    [[ "${line}" =~ ^([[:space:]]*)[^[:space:]] ]]
    indent_length=${#BASH_REMATCH[1]}

    if ((min_indent == -1 || indent_length < min_indent)); then
      min_indent=${indent_length}
    fi
  done

  if ((min_indent < 0)); then
    min_indent=0
  fi

  for line in "${lines[@]}"; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      printf '\n'
    else
      printf '%s\n' "${line:min_indent}"
    fi
  done
}

#######################################
# @description Strip ANSI escape sequences from a text block.
# @arg $1 string Input text or `-` for stdin
# @stdout Text without ANSI color/control sequences
#######################################
function dybatpho::text_strip_ansi {
  local input
  dybatpho::expect_args input -- "$@"
  local -a lines=()
  local line

  __dybatpho_text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    # The ranges are byte ranges, and BSD sed rejects `[ -/]` as an invalid
    # range under a UTF-8 collation, so the match runs in the C locale.
    local printf
    printf=$(printf '%s' "${line}" | LC_ALL=C sed -E $'s/\x1B\\[[0-?]*[ -/]*[@-~]//g')
    printf '%s\n' "${printf}"
  done
}

#######################################
# @description Prefix each non-empty line in a text block as a bullet item.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Optional bullet marker, default is `-`
# @stdout Bullet-formatted text block
#######################################
function dybatpho::text_bullet_list {
  local input
  dybatpho::expect_args input -- "$@"
  local bullet="${2:--}"
  local -a lines=()
  local line

  __dybatpho_text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    if dybatpho::string_is_blank "${line}"; then
      printf '\n'
    else
      printf '%s %s\n' "${bullet}" "${line}"
    fi
  done
}

#######################################
# @description Align a delimited text block into plain columns.
#   The columns are laid out by `dybatpho::table_align`, so the `table` module
#   has to be loaded; `text` does not load it on its own.
# @example
#   . dybatpho/init.sh --modules text table
#   dybatpho::text_columns $'name|version\ndybatpho|6.0.0'
#
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @arg $3 number Optional gap width between columns, default is 2
# @stdout Plain aligned columns
# @exitcode 1 Stop the script when the `table` module is not loaded
#######################################
function dybatpho::text_columns {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_text_need_table
  local delimiter="${2:-|}"
  local gap="${3:-2}"
  dybatpho::table_align "${input}" "${delimiter}" "" "${gap}"
}

#######################################
# @description Stop unless the `table` module is loaded.
#   Only `dybatpho::text_columns` draws through `table`, and registering it as
#   a dependency would load it into every script that only indents or strips
#   text -- including, through `testing`, every test suite -- so the one
#   function that needs it asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `table`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `table` module is not loaded
# @internal
#######################################
function __dybatpho_text_need_table {
  declare -F __dybatpho_table_measure_widths > /dev/null \
    || dybatpho::die "${FUNCNAME[1]} needs the table module, load it with: dybatpho::load table"
}

#######################################
# @description Measure the columns a line occupies on a terminal.
#   ANSI escape sequences are removed before measuring. The Unicode-aware
#   measurement of the `screen` module is used when it is loaded; otherwise the
#   character count stands in for the width.
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Line to measure
# @set The named variable
# @internal
#######################################
function __dybatpho_text_width_into {
  local __dybatpho_text_w_target __dybatpho_text_w_line
  dybatpho::expect_args __dybatpho_text_w_target __dybatpho_text_w_line -- "$@"
  local -n __dybatpho_text_w_out="${__dybatpho_text_w_target}"

  if [[ "${__dybatpho_text_w_line}" == *$'\e'* ]]; then
    __dybatpho_text_w_line="$(dybatpho::text_strip_ansi "${__dybatpho_text_w_line}")"
  fi

  # A guard on the internal helper, not the public function: a child shell
  # inherits exported public functions without the internals they call.
  if declare -F __dybatpho_screen_width_into > /dev/null; then
    __dybatpho_screen_width_into __dybatpho_text_w_out "${__dybatpho_text_w_line}"
  else
    __dybatpho_text_w_out="${#__dybatpho_text_w_line}"
  fi
}

#######################################
# @description Draw a border around a text block, with an optional title set
#   into the top edge.
#   The box is as wide as the widest line or the title, whichever is wider,
#   with one space of padding on each side. Lines are padded by their visible
#   width, so colored text and, with the `screen` module loaded, wide
#   characters keep the right edge straight.
# @example
#   dybatpho::text_box $'alpha\nbeta' "Notes"
#   # ┌─ Notes ─┐
#   # │ alpha   │
#   # │ beta    │
#   # └─────────┘
#
#   dybatpho::text_box "plain" "" ascii
#   # +-------+
#   # | plain |
#   # +-------+
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Optional title shown in the top border, default is none
# @arg $3 string Optional border style: `single` (default), `double`, `rounded`, `heavy`, or `ascii`
# @stdout The boxed text block
# @exitcode 1 The border style is unknown
#######################################
function dybatpho::text_box {
  local input
  dybatpho::expect_args input -- "$@"
  local title="${2-}"
  local style="${3:-single}"
  local top_left top_right bottom_left bottom_right horizontal vertical

  case "${style}" in
    single) top_left="┌" top_right="┐" bottom_left="└" bottom_right="┘" horizontal="─" vertical="│" ;;
    double) top_left="╔" top_right="╗" bottom_left="╚" bottom_right="╝" horizontal="═" vertical="║" ;;
    rounded) top_left="╭" top_right="╮" bottom_left="╰" bottom_right="╯" horizontal="─" vertical="│" ;;
    heavy) top_left="┏" top_right="┓" bottom_left="┗" bottom_right="┛" horizontal="━" vertical="┃" ;;
    ascii) top_left="+" top_right="+" bottom_left="+" bottom_right="+" horizontal="-" vertical="|" ;;
    # "dybatpho::text_box rejects an unknown style" runs this arm under `run`.
    *) dybatpho::die "Unknown box style: ${style} (expected single, double, rounded, heavy, or ascii)" ;; # kcov(skip)
  esac

  local -a lines=() widths=()
  local line width inner=0 title_width=0 index
  __dybatpho_text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    __dybatpho_text_width_into width "${line}"
    widths+=("${width}")
    ((width > inner)) && inner=${width}
  done

  if [[ -n "${title}" ]]; then
    __dybatpho_text_width_into title_width "${title}"
    # The title sits as `─ title ─`, so it needs two more columns than itself.
    ((title_width + 2 > inner)) && inner=$((title_width + 2))
  fi

  # The rules are built by repeating the border character rather than by
  # slicing one long rule, since a slice counts bytes in the C locale.
  local rule title_rule
  printf -v rule '%*s' "$((inner + 2))" ""
  rule="${rule// /${horizontal}}"

  if [[ -n "${title}" ]]; then
    printf -v title_rule '%*s' "$((inner - title_width - 1))" ""
    title_rule="${title_rule// /${horizontal}}"
    printf '%s%s %s %s%s\n' "${top_left}" "${horizontal}" "${title}" \
      "${title_rule}" "${top_right}"
  else
    printf '%s%s%s\n' "${top_left}" "${rule}" "${top_right}"
  fi
  for index in "${!lines[@]}"; do
    printf '%s %s%*s %s\n' "${vertical}" "${lines[index]}" \
      "$((inner - widths[index]))" "" "${vertical}"
  done
  printf '%s%s%s\n' "${bottom_left}" "${rule}" "${bottom_right}"
}

#######################################
# @description Center each line of a text block within a width.
#   Lines are padded on the left only, so no trailing whitespace is added. When
#   the padding cannot be split evenly, the extra column goes to the right. A
#   line at least as wide as the width is printed unchanged, and a blank line
#   stays blank. Widths are measured as `dybatpho::text_box` measures them.
# @example
#   dybatpho::text_center $'title\nsubtitle here' 20
#   #        title
#   #    subtitle here
# @arg $1 string Input text or `-` for stdin
# @arg $2 number Optional width to center within, default is the terminal width
# @stdout The centered text block
# @exitcode 1 The width is not a positive integer
#######################################
function dybatpho::text_center {
  local input
  dybatpho::expect_args input -- "$@"
  local width="${2-}"
  if [[ -z "${width}" ]]; then
    width="$(dybatpho::terminal_width)"
  fi
  [[ "${width}" =~ ^[1-9][0-9]*$ ]] || dybatpho::die "Width must be a positive integer: ${width}"

  local -a lines=()
  local line line_width
  __dybatpho_text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    if dybatpho::string_is_blank "${line}"; then
      printf '\n'
      continue
    fi
    __dybatpho_text_width_into line_width "${line}"
    if ((line_width >= width)); then
      printf '%s\n' "${line}"
    else
      printf '%*s%s\n' "$(((width - line_width) / 2))" "" "${line}"
    fi
  done
}

#######################################
# @description Prefix each line of a text block with its line number.
#   Numbers are right-aligned to the width of the last one, so a block of ten
#   or more lines keeps its text in one column. Blank lines are numbered too.
# @example
#   dybatpho::text_number_lines $'alpha\nbeta'
#   # 1  alpha
#   # 2  beta
#
#   dybatpho::text_number_lines $'alpha\nbeta' 9 ": "
#   #  9: alpha
#   # 10: beta
# @arg $1 string Input text or `-` for stdin
# @arg $2 number Optional number of the first line, default is `1`
# @arg $3 string Optional separator between number and text, default is two spaces
# @stdout The numbered text block
# @exitcode 1 The first line number is not a non-negative integer
#######################################
function dybatpho::text_number_lines {
  local input
  dybatpho::expect_args input -- "$@"
  local start="${2:-1}"
  local separator="${3-  }"
  [[ "${start}" =~ ^[0-9]+$ ]] || dybatpho::die "Start line must be a non-negative integer: ${start}"
  # Strip leading zeros so `08` is not read as an invalid octal number.
  start=$((10#${start}))

  local -a lines=()
  local index last digits
  __dybatpho_text_read_lines "${input}" lines
  last=$((start + ${#lines[@]} - 1))
  digits=${#last}
  for index in "${!lines[@]}"; do
    printf '%*d%s%s\n' "${digits}" "$((start + index))" "${separator}" "${lines[index]}"
  done
}

#######################################
# @description Keep the first lines of a text block and say how many were left
#   out.
#   A block that already fits is printed unchanged, with no marker. Otherwise
#   the first `count` lines are printed, followed by a marker line. The default
#   marker reads `… 1 more line` or `… N more lines`; a custom marker has every
#   `{count}` replaced by the number of lines left out.
# @example
#   dybatpho::text_truncate_lines $'one\ntwo\nthree\nfour' 2
#   # one
#   # two
#   # … 2 more lines
#
#   git log --oneline | dybatpho::text_truncate_lines - 5 "(+{count} commits)"
# @arg $1 string Input text or `-` for stdin
# @arg $2 number Number of lines to keep
# @arg $3 string Optional marker template, `{count}` is replaced by the number of lines left out
# @stdout The kept lines and, when lines were left out, the marker
# @exitcode 1 The count is not a non-negative integer
#######################################
function dybatpho::text_truncate_lines {
  local input count
  dybatpho::expect_args input count -- "$@"
  local marker="${3-}"
  [[ "${count}" =~ ^[0-9]+$ ]] || dybatpho::die "Line count must be a non-negative integer: ${count}"
  count=$((10#${count}))

  local -a lines=()
  local index hidden
  __dybatpho_text_read_lines "${input}" lines
  if ((${#lines[@]} <= count)); then
    printf '%s\n' "${lines[@]}"
    return 0
  fi

  for ((index = 0; index < count; index++)); do
    printf '%s\n' "${lines[index]}"
  done
  hidden=$((${#lines[@]} - count))
  if [[ -z "${marker}" ]]; then
    if ((hidden == 1)); then
      marker="… 1 more line"
    else
      marker="… ${hidden} more lines"
    fi
  else
    marker="${marker//\{count\}/${hidden}}"
  fi
  printf '%s\n' "${marker}"
}
