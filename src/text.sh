#!/usr/bin/env bash
# @file text.sh
# @brief Utilities for working with multi-line text blocks
# @description
#   This module contains helpers for formatting larger text blocks: indenting
#   each line, removing shared indentation, stripping ANSI escape sequences,
#   turning lines into bullet lists, and aligning simple delimited columns. It
#   is useful when shell scripts need to prepare readable console output, embed
#   heredocs, or normalize text before writing files.
# @see
#   - `example/text_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Read a text argument or stdin into a target array of lines.
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Name of the array variable to fill
#######################################
function __text_read_lines {
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

  __text_read_lines "${input}" lines
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

  __text_read_lines "${input}" lines

  for line in "${lines[@]}"; do
    if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
      continue
    fi

    if [[ "${line}" =~ ^([[:space:]]*)[^[:space:]] ]]; then
      indent_length=${#BASH_REMATCH[1]}
    else
      indent_length=0
    fi

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

  __text_read_lines "${input}" lines
  for line in "${lines[@]}"; do
    printf '%s\n' "$(printf '%s' "${line}" | sed -E $'s/\x1B\\[[0-?]*[ -/]*[@-~]//g')"
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

  __text_read_lines "${input}" lines
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
# @arg $1 string Input text or `-` for stdin
# @arg $2 string Optional exact delimiter, default is `|`
# @arg $3 number Optional gap width between columns, default is 2
# @stdout Plain aligned columns
#######################################
function dybatpho::text_columns {
  local input
  dybatpho::expect_args input -- "$@"
  local delimiter="${2:-|}"
  local gap="${3:-2}"
  dybatpho::is function dybatpho::table_align || dybatpho::die "dybatpho::table_align is required for dybatpho::text_columns"
  dybatpho::table_align "${input}" "${delimiter}" "" "${gap}"
}
