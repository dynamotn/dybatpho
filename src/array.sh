#!/usr/bin/env bash
# @file array.sh
# @brief Utilities for working with array
# @description
#   This module contains helpers for printing, reversing, deduplicating,
#   compacting, filtering, mapping, rejecting, finding values, checking
#   membership, checking every/some values, finding positions, and joining Bash
#   arrays by name.
# @see
#   - `example/array_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Print each element of an array on its own line.
# @arg $1 string Name of array
# @stdout Print array with each element separated by newline
#######################################
function dybatpho::array_print {
  local -n input_arr="$1"
  printf '%s\n' "${input_arr[@]}"
}

#######################################
# @description Reverse an array in place.
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print the reversed array if $2 is `--`
#######################################
function dybatpho::array_reverse {
  local -n input_arr="$1"
  local result_arr=()
  [ "${#input_arr[@]}" -eq 0 ] && return
  local -a indices=("${!input_arr[@]}")

  for ((i = ${#indices[@]} - 1; i >= 0; i--)); do
    result_arr+=("${input_arr[${indices[${i}]}]}")
  done

  input_arr=("${result_arr[@]}")
  if [[ "${2-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Remove duplicate elements from an array in place.
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print the deduplicated array if $2 is `--`
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
# @description Return success when an array contains the given element.
# @arg $1 string Name of array
# @arg $2 string Element to search for
# @exitcode 0 The element exists in the array
# @exitcode 1 The element does not exist in the array
#######################################
function dybatpho::array_contains {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local needle="${2-}"
  local i
  for i in "${!input_arr[@]}"; do
    [[ "${input_arr[${i}]}" == "${needle}" ]] && return 0
  done
  return 1
}

#######################################
# @description Print the first index of an array element that matches exactly.
# @arg $1 string Name of array
# @arg $2 string Element to search for
# @stdout First matching index
# @exitcode 0 A matching element is found
# @exitcode 1 No matching element is found
#######################################
function dybatpho::array_index_of {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local needle="${2-}"
  local i
  for i in "${!input_arr[@]}"; do
    if [[ "${input_arr[${i}]}" == "${needle}" ]]; then
      printf '%s\n' "${i}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Remove empty-string elements from an array in place.
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print the compacted array if $2 is `--`
#######################################
function dybatpho::array_compact {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local compacted_arr=()
  local i
  for i in "${!input_arr[@]}"; do
    [[ -n "${input_arr[${i}]}" ]] && compacted_arr+=("${input_arr[${i}]}")
  done
  input_arr=("${compacted_arr[@]}")
  if [[ "${2-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Keep only array elements accepted by a predicate function.
# @arg $1 string Name of array
# @arg $2 string Predicate function name, called with each element
# @arg $3 string Set `--` to print to stdout
# @stdout Print the filtered array if $3 is `--`
#######################################
function dybatpho::array_filter {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local predicate="${2-}"
  local filtered_arr=()
  local i
  dybatpho::is function "${predicate}" || dybatpho::die "Invalid predicate function: ${predicate}"
  for i in "${!input_arr[@]}"; do
    if "${predicate}" "${input_arr[${i}]}"; then
      filtered_arr+=("${input_arr[${i}]}")
    fi
  done
  input_arr=("${filtered_arr[@]}")
  if [[ "${3-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Transform each array element with a mapper function.
# @arg $1 string Name of array
# @arg $2 string Mapper function name, called with each element
# @arg $3 string Set `--` to print to stdout
# @stdout Print the mapped array if $3 is `--`
#######################################
function dybatpho::array_map {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local mapper="${2-}"
  local mapped_arr=()
  local mapped_value i status
  dybatpho::is function "${mapper}" || dybatpho::die "Invalid mapper function: ${mapper}"
  for i in "${!input_arr[@]}"; do
    mapped_value=$("${mapper}" "${input_arr[${i}]}")
    status=$?
    ((status == 0)) || return "${status}"
    mapped_arr+=("${mapped_value}")
  done
  input_arr=("${mapped_arr[@]}")
  if [[ "${3-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Print the first array element accepted by a predicate function.
# @arg $1 string Name of array
# @arg $2 string Predicate function name, called with each element
# @stdout First matching array element
# @exitcode 0 A matching element is found
# @exitcode 1 No matching element is found
#######################################
function dybatpho::array_find {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local predicate="${2-}"
  local i
  dybatpho::is function "${predicate}" || dybatpho::die "Invalid predicate function: ${predicate}"
  for i in "${!input_arr[@]}"; do
    if "${predicate}" "${input_arr[${i}]}"; then
      printf '%s\n' "${input_arr[${i}]}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Return success when every array element is accepted by a predicate function.
# @arg $1 string Name of array
# @arg $2 string Predicate function name, called with each element
# @exitcode 0 Every element matches, or the array is empty
# @exitcode 1 At least one element does not match
#######################################
function dybatpho::array_every {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local predicate="${2-}"
  local i
  dybatpho::is function "${predicate}" || dybatpho::die "Invalid predicate function: ${predicate}"
  for i in "${!input_arr[@]}"; do
    "${predicate}" "${input_arr[${i}]}" || return 1
  done
  return 0
}

#######################################
# @description Return success when at least one array element is accepted by a predicate function.
# @arg $1 string Name of array
# @arg $2 string Predicate function name, called with each element
# @exitcode 0 At least one element matches
# @exitcode 1 No elements match
#######################################
function dybatpho::array_some {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local predicate="${2-}"
  local i
  dybatpho::is function "${predicate}" || dybatpho::die "Invalid predicate function: ${predicate}"
  for i in "${!input_arr[@]}"; do
    if "${predicate}" "${input_arr[${i}]}"; then
      return 0
    fi
  done
  return 1
}

#######################################
# @description Keep only array elements rejected by a predicate function.
# @arg $1 string Name of array
# @arg $2 string Predicate function name, called with each element
# @arg $3 string Set `--` to print to stdout
# @stdout Print the rejected array if $3 is `--`
#######################################
function dybatpho::array_reject {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local predicate="${2-}"
  local rejected_arr=()
  local i
  dybatpho::is function "${predicate}" || dybatpho::die "Invalid predicate function: ${predicate}"
  for i in "${!input_arr[@]}"; do
    if ! "${predicate}" "${input_arr[${i}]}"; then
      rejected_arr+=("${input_arr[${i}]}")
    fi
  done
  input_arr=("${rejected_arr[@]}")
  if [[ "${3-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Print the first element of an array.
# @arg $1 string Name of array
# @stdout First array element
# @exitcode 0 The array contains at least one element
# @exitcode 1 The array is empty
#######################################
function dybatpho::array_first {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local -a indices=("${!input_arr[@]}")
  ((${#indices[@]} > 0)) || return 1
  printf '%s\n' "${input_arr[${indices[0]}]}"
}

#######################################
# @description Print the last element of an array.
# @arg $1 string Name of array
# @stdout Last array element
# @exitcode 0 The array contains at least one element
# @exitcode 1 The array is empty
#######################################
function dybatpho::array_last {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local -a indices=("${!input_arr[@]}")
  local last_index
  ((${#indices[@]} > 0)) || return 1
  last_index=$((${#indices[@]} - 1))
  printf '%s\n' "${input_arr[${indices[${last_index}]}]}"
}

#######################################
# @description Join array elements with a separator into one string.
# @arg $1 string Name of array
# @arg $2 string Separator
# @stdout Print outputted string
#######################################
function dybatpho::array_join {
  # shellcheck disable=SC2178
  local -n input_arr="$1"
  local separator="$2"
  local i

  if [[ ${#input_arr[@]} -eq 0 ]]; then
    return
  fi
  printf -- "%s" "${input_arr[0]}"
  for ((i = 1; i < ${#input_arr[@]}; i++)); do
    printf -- "%s%s" "${separator}" "${input_arr[${i}]}"
  done
}
