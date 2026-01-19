#!/usr/bin/env bash
# @file array.sh
# @brief Utilities for working with array
# @description
#   This module contains functions to work with array.
#
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Print an array
# @arg $1 string Name of array
# @stdout Print array with each element separated by newline
#######################################
function dybatpho::array_print {
  local -n input_arr="$1"
  printf '%s\n' "${input_arr[@]}"
}

#######################################
# @description Reverse an array
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print array if $2 is `--`
#######################################
function dybatpho::array_reverse {
  local -n input_arr="$1"
  local result_arr=()
  [ "${#input_arr[@]}" -eq 0 ] && return

  for ((i = 1; i <= "${#input_arr[@]}"; i++)); do
    # shellcheck disable=SC2190
    result_arr+=("${input_arr[$((-i))]}")
  done

  input_arr=("${result_arr[@]}")
  if [[ "${2-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Remove duplicate elements in array
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print array if $2 is `--`
#######################################
function dybatpho::array_unique {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  declare -A result_arr

  for i in "${input_arr[@]}"; do
    [[ ${i} ]] && IFS=" " result_arr["${i:- }"]=1
  done

  input_arr=("${!result_arr[@]}")
  if [[ "${2-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Join array with given separator into a string
# @arg $1 string Name of array
# @arg $2 string Separator
# @stdout Print outputted string
#######################################
function dybatpho::array_join {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local separator="$2"

  if [[ ${#input_arr[@]} -eq 0 ]]; then
    return
  fi
  printf -- "%s" "${input_arr[0]}"
  if [[ ${#input_arr[@]} -gt 1 ]]; then
    printf -- "${separator}%s" "${input_arr[@]:1}"
  fi
}
