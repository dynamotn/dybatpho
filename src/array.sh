# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file array.sh
# @brief Utilities for working with array
# @namespace dybatpho
# @description
#   This module contains helpers for printing, reversing, deduplicating,
#   compacting, filtering, mapping, rejecting, finding values, checking
#   membership, checking every/some values, finding positions, and joining Bash
#   arrays by name. It also sorts and slices them, and treats them as sets for
#   union, intersection, and difference.
#
#   Every helper takes an array by name and changes it in place, with a final
#   `--` to print the result as well.
# @see
#   - `example/array_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Print each element of an array on its own line.
# @arg $1 string Name of array
# @stdout Print array with each element separated by newline
#######################################
function dybatpho::array_print {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_array_ref="$1"
  printf '%s\n' "${__dybatpho_array_ref[@]}"
}

#######################################
# @description Reverse an array in place.
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print the reversed array if $2 is `--`
#######################################
function dybatpho::array_reverse {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_array_ref="$1"
  local -a __dybatpho_array_result=()
  [[ "${#__dybatpho_array_ref[@]}" -eq 0 ]] && return
  local -a __dybatpho_array_indices=("${!__dybatpho_array_ref[@]}")

  for ((__dybatpho_array_i = ${#__dybatpho_array_indices[@]} - 1; __dybatpho_array_i >= 0; __dybatpho_array_i--)); do
    # shellcheck disable=SC2190 # __dybatpho_array_result is indexed; the nameref misleads ShellCheck
    __dybatpho_array_result+=("${__dybatpho_array_ref[${__dybatpho_array_indices[${__dybatpho_array_i}]}]}")
  done

  __dybatpho_array_ref=("${__dybatpho_array_result[@]}")
  if [[ "${2-""}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Remove duplicate elements from an array in place, keeping the
#   first occurrence of each value.
#
#   The surviving elements stay in the order they arrived in, which is what
#   `dybatpho::array_union` already does and what a caller deduplicating a list
#   of hosts or services expects to print. An earlier version collected the
#   values as the keys of an associative array and handed back whatever order
#   Bash happened to hash them into, so `1 2 3 4 5` came out as `5 4 3 2 1` and
#   the order changed with the contents.
#
#   Empty elements are dropped, as before.
# @arg $1 string Name of array
# @arg $2 string Set `--` to print to stdout
# @stdout Print the deduplicated array if $2 is `--`
#######################################
function dybatpho::array_unique {
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local -A __dybatpho_array_unique_seen=()
  local -a __dybatpho_array_unique_result=()
  local __dybatpho_array_unique_value

  for __dybatpho_array_unique_value in ${__dybatpho_array_ref[@]+"${__dybatpho_array_ref[@]}"}; do
    [[ -n "${__dybatpho_array_unique_value}" ]] || continue
    [[ -v "__dybatpho_array_unique_seen[${__dybatpho_array_unique_value}]" ]] && continue
    __dybatpho_array_unique_seen["${__dybatpho_array_unique_value}"]=1
    __dybatpho_array_unique_result+=("${__dybatpho_array_unique_value}")
  done

  # shellcheck disable=SC2190 # __dybatpho_array_ref is indexed; the nameref misleads ShellCheck
  __dybatpho_array_ref=(${__dybatpho_array_unique_result[@]+"${__dybatpho_array_unique_result[@]}"})
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_needle="${2-}"
  local __dybatpho_array_i
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    [[ "${__dybatpho_array_ref[${__dybatpho_array_i}]}" == "${__dybatpho_array_needle}" ]] && return 0
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_needle="${2-}"
  local __dybatpho_array_i
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    if [[ "${__dybatpho_array_ref[${__dybatpho_array_i}]}" == "${__dybatpho_array_needle}" ]]; then
      printf '%s\n' "${__dybatpho_array_i}"
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local -a __dybatpho_array_compacted=()
  local __dybatpho_array_i
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    [[ -n "${__dybatpho_array_ref[${__dybatpho_array_i}]}" ]] \
      && __dybatpho_array_compacted+=("${__dybatpho_array_ref[${__dybatpho_array_i}]}")
  done
  __dybatpho_array_ref=("${__dybatpho_array_compacted[@]}")
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_predicate="${2-}"
  local -a __dybatpho_array_filtered=()
  local __dybatpho_array_i
  dybatpho::is function "${__dybatpho_array_predicate}" || dybatpho::die \
    "Invalid predicate function: ${__dybatpho_array_predicate}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    if "${__dybatpho_array_predicate}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}"; then
      __dybatpho_array_filtered+=("${__dybatpho_array_ref[${__dybatpho_array_i}]}")
    fi
  done
  __dybatpho_array_ref=("${__dybatpho_array_filtered[@]}")
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_mapper="${2-}"
  local -a __dybatpho_array_mapped=()
  local __dybatpho_array_mapped_value __dybatpho_array_i status
  dybatpho::is function "${__dybatpho_array_mapper}" || dybatpho::die \
    "Invalid mapper function: ${__dybatpho_array_mapper}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    __dybatpho_array_mapped_value=$("${__dybatpho_array_mapper}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}")
    status=$?
    ((status == 0)) || return "${status}"
    __dybatpho_array_mapped+=("${__dybatpho_array_mapped_value}")
  done
  __dybatpho_array_ref=("${__dybatpho_array_mapped[@]}")
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_predicate="${2-}"
  local __dybatpho_array_i
  dybatpho::is function "${__dybatpho_array_predicate}" || dybatpho::die \
    "Invalid predicate function: ${__dybatpho_array_predicate}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    if "${__dybatpho_array_predicate}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}"; then
      printf '%s\n' "${__dybatpho_array_ref[${__dybatpho_array_i}]}"
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_predicate="${2-}"
  local __dybatpho_array_i
  dybatpho::is function "${__dybatpho_array_predicate}" || dybatpho::die \
    "Invalid predicate function: ${__dybatpho_array_predicate}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    "${__dybatpho_array_predicate}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}" || return 1
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_predicate="${2-}"
  local __dybatpho_array_i
  dybatpho::is function "${__dybatpho_array_predicate}" || dybatpho::die \
    "Invalid predicate function: ${__dybatpho_array_predicate}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    if "${__dybatpho_array_predicate}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}"; then
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_predicate="${2-}"
  local -a __dybatpho_array_rejected=()
  local __dybatpho_array_i
  dybatpho::is function "${__dybatpho_array_predicate}" || dybatpho::die \
    "Invalid predicate function: ${__dybatpho_array_predicate}"
  for __dybatpho_array_i in "${!__dybatpho_array_ref[@]}"; do
    if ! "${__dybatpho_array_predicate}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}"; then
      __dybatpho_array_rejected+=("${__dybatpho_array_ref[${__dybatpho_array_i}]}")
    fi
  done
  __dybatpho_array_ref=("${__dybatpho_array_rejected[@]}")
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
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local -a __dybatpho_array_indices=("${!__dybatpho_array_ref[@]}")
  ((${#__dybatpho_array_indices[@]} > 0)) || return 1
  printf '%s\n' "${__dybatpho_array_ref[${__dybatpho_array_indices[0]}]}"
}

#######################################
# @description Print the last element of an array.
# @arg $1 string Name of array
# @stdout Last array element
# @exitcode 0 The array contains at least one element
# @exitcode 1 The array is empty
#######################################
function dybatpho::array_last {
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local -a __dybatpho_array_indices=("${!__dybatpho_array_ref[@]}")
  local __dybatpho_array_last_index
  ((${#__dybatpho_array_indices[@]} > 0)) || return 1
  __dybatpho_array_last_index=$((${#__dybatpho_array_indices[@]} - 1))
  printf '%s\n' "${__dybatpho_array_ref[${__dybatpho_array_indices[${__dybatpho_array_last_index}]}]}"
}

#######################################
# @description Join array elements with a separator into one string.
# @arg $1 string Name of array
# @arg $2 string Separator
# @stdout Print outputted string
#######################################
function dybatpho::array_join {
  dybatpho::expect_ref "$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_ref="$1"
  local __dybatpho_array_separator="$2"
  local __dybatpho_array_i

  if [[ ${#__dybatpho_array_ref[@]} -eq 0 ]]; then
    return
  fi
  printf -- "%s" "${__dybatpho_array_ref[0]}"
  for ((__dybatpho_array_i = 1; __dybatpho_array_i < ${#__dybatpho_array_ref[@]}; __dybatpho_array_i++)); do
    printf -- "%s%s" "${__dybatpho_array_separator}" "${__dybatpho_array_ref[${__dybatpho_array_i}]}"
  done
}

#######################################
# @description Copy the values of one array into another.
#   Bash 4.3 treats `"${empty[@]}"` as unset under `nounset`, so every copy in
#   this module goes through the length check here rather than repeating it.
# @arg $1 string Name of the array to fill
# @arg $2 string Name of the array to read
# @set The named array
# @internal
#######################################
function __dybatpho_array_copy {
  local -n __dybatpho_array_copy_out="$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_copy_in="$2"
  __dybatpho_array_copy_out=()
  ((${#__dybatpho_array_copy_in[@]} == 0)) || __dybatpho_array_copy_out=("${__dybatpho_array_copy_in[@]}")
}

#######################################
# @description Build a lookup of the values an array holds.
# @arg $1 string Name of the associative array to fill
# @arg $2 string Name of the array to read
# @set The named associative array, one key per distinct value
# @internal
#######################################
function __dybatpho_array_index {
  local -n __dybatpho_array_index_out="$1"
  # shellcheck disable=SC2178
  local -n __dybatpho_array_index_in="$2"
  __dybatpho_array_index_out=()
  local __dybatpho_array_index_value
  for __dybatpho_array_index_value in ${__dybatpho_array_index_in[@]+"${__dybatpho_array_index_in[@]}"}; do
    __dybatpho_array_index_out["${__dybatpho_array_index_value}"]=1
  done
}

#######################################
# @description Return success when one value must sort after another.
# @arg $1 string Left value
# @arg $2 string Right value
# @arg $3 bool Compare as numbers rather than as text
# @arg $4 bool Reverse the order
# @exitcode 0 The left value belongs after the right one
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_array_sorts_after {
  local left="$1" right="$2" numeric="$3" reverse="$4"
  local order
  if [[ "${numeric}" == true ]]; then
    if ((left > right)); then
      order=1
    elif ((left < right)); then
      order=-1
    else
      order=0
    fi
  else
    if [[ "${left}" > "${right}" ]]; then
      order=1
    elif [[ "${left}" < "${right}" ]]; then
      order=-1
    else
      order=0
    fi
  fi
  if [[ "${reverse}" == true ]]; then
    ((order < 0))
  else
    ((order > 0))
  fi
}

#######################################
# @description Sort an array of values in place, bottom-up and stable.
#   Runs of length one are already sorted, so the passes start by merging pairs
#   of them and double the run length until one run covers everything. That is
#   `n log n` comparisons instead of the `n²` an insertion sort pays, and the
#   comparison stays in `__dybatpho_array_sorts_after` so text, numeric and
#   reversed order are all decided in one place.
#
#   The merge takes the left run whenever the two compare equal, which is what
#   makes the sort stable.
# @arg $1 string Name of the array to sort in place
# @arg $2 bool Compare as numbers rather than as text
# @arg $3 bool Reverse the order
# @set The named array
# @internal
#######################################
function __dybatpho_array_merge_sort {
  local -n __dybatpho_array_merge_values="$1"
  local __dybatpho_array_merge_numeric="$2" __dybatpho_array_merge_reverse="$3"
  local __dybatpho_array_merge_count="${#__dybatpho_array_merge_values[@]}"
  ((__dybatpho_array_merge_count > 1)) || return 0

  local -a __dybatpho_array_merge_buffer=()
  local __dybatpho_array_merge_width=1
  local __dybatpho_array_merge_start __dybatpho_array_merge_middle __dybatpho_array_merge_end
  local __dybatpho_array_merge_left __dybatpho_array_merge_right __dybatpho_array_merge_out

  while ((__dybatpho_array_merge_width < __dybatpho_array_merge_count)); do
    __dybatpho_array_merge_buffer=()
    __dybatpho_array_merge_start=0
    while ((__dybatpho_array_merge_start < __dybatpho_array_merge_count)); do
      __dybatpho_array_merge_middle=$((__dybatpho_array_merge_start + __dybatpho_array_merge_width))
      ((__dybatpho_array_merge_middle > __dybatpho_array_merge_count)) \
        && __dybatpho_array_merge_middle=${__dybatpho_array_merge_count}
      __dybatpho_array_merge_end=$((__dybatpho_array_merge_middle + __dybatpho_array_merge_width))
      ((__dybatpho_array_merge_end > __dybatpho_array_merge_count)) \
        && __dybatpho_array_merge_end=${__dybatpho_array_merge_count}

      __dybatpho_array_merge_left=${__dybatpho_array_merge_start}
      __dybatpho_array_merge_right=${__dybatpho_array_merge_middle}
      while ((__dybatpho_array_merge_left < __dybatpho_array_merge_middle)) \
        && ((__dybatpho_array_merge_right < __dybatpho_array_merge_end)); do
        if __dybatpho_array_sorts_after \
          "${__dybatpho_array_merge_values[${__dybatpho_array_merge_left}]}" \
          "${__dybatpho_array_merge_values[${__dybatpho_array_merge_right}]}" \
          "${__dybatpho_array_merge_numeric}" "${__dybatpho_array_merge_reverse}"; then
          __dybatpho_array_merge_buffer+=("${__dybatpho_array_merge_values[${__dybatpho_array_merge_right}]}")
          __dybatpho_array_merge_right=$((__dybatpho_array_merge_right + 1))
        else
          __dybatpho_array_merge_buffer+=("${__dybatpho_array_merge_values[${__dybatpho_array_merge_left}]}")
          __dybatpho_array_merge_left=$((__dybatpho_array_merge_left + 1))
        fi
      done
      for ((__dybatpho_array_merge_out = __dybatpho_array_merge_left;  \
      __dybatpho_array_merge_out < __dybatpho_array_merge_middle;  \
      __dybatpho_array_merge_out++)); do
        __dybatpho_array_merge_buffer+=("${__dybatpho_array_merge_values[${__dybatpho_array_merge_out}]}")
      done
      for ((__dybatpho_array_merge_out = __dybatpho_array_merge_right;  \
      __dybatpho_array_merge_out < __dybatpho_array_merge_end;  \
      __dybatpho_array_merge_out++)); do
        __dybatpho_array_merge_buffer+=("${__dybatpho_array_merge_values[${__dybatpho_array_merge_out}]}")
      done

      __dybatpho_array_merge_start=${__dybatpho_array_merge_end}
    done
    __dybatpho_array_merge_values=("${__dybatpho_array_merge_buffer[@]}")
    __dybatpho_array_merge_width=$((__dybatpho_array_merge_width * 2))
  done
}

#######################################
# @description Sort an array in place.
#   Text is ordered by the current locale's collation, the same rule `sort`
#   follows, so a script that needs one fixed order everywhere sets `LC_ALL` as
#   it would for `sort`.
#
#   `--numeric` compares values as numbers, which is the reason a shell script
#   wants a sort at all: as text, `10` comes before `9`. It takes integers,
#   negative ones included, and stops the script on anything else rather than
#   quietly ordering it as text.
#
#   The sort is a bottom-up merge sort rather than a pipe through `sort(1)`: it
#   keeps an element containing a newline intact and needs no external command.
#   It is also stable, so values that compare equal stay in the order they
#   arrived in. The insertion sort it replaces cost a comparison per pair and
#   took ~39s over 2000 elements, which is a size a list of files or packages
#   reaches without trying.
# @example
#   releases=(1.10 1.9 2.0)
#   dybatpho::array_sort releases --
#   # 1.10
#   # 1.9
#   # 2.0
#
# @example
#   sizes=(10 9 100 -3)
#   dybatpho::array_sort sizes --numeric --          # -3 9 10 100
#   dybatpho::array_sort sizes --numeric --reverse
#
# @arg $1 string Name of array
# @arg $@ string Any of `--numeric`/`-n`, `--reverse`/`-r`, and `--` to print
# @stdout Print the sorted array if `--` is given
# @exitcode 1 Stop the script on an unknown option, or on a value that is not an integer under `--numeric`
# @see
#   - `dybatpho::semver_sort`
#######################################
function dybatpho::array_sort {
  dybatpho::expect_ref "$1"
  # The locals carry a distinctive prefix because a nameref resolves in the
  # caller's scope: a plainly named local here would shadow a caller's array of
  # the same name, and this function would then sort its own empty copy.
  local __dybatpho_array_sort_numeric=false __dybatpho_array_sort_reverse=false __dybatpho_array_sort_print=false
  local __dybatpho_array_sort_option
  for __dybatpho_array_sort_option in "${@:2}"; do
    case "${__dybatpho_array_sort_option}" in
      -n | --numeric) __dybatpho_array_sort_numeric=true ;;
      -r | --reverse) __dybatpho_array_sort_reverse=true ;;
      --) __dybatpho_array_sort_print=true ;;
      *) dybatpho::die "dybatpho::array_sort: Unknown option '${__dybatpho_array_sort_option}'" ;;
    esac
  done

  local -a __dybatpho_array_sort_values=()
  __dybatpho_array_copy __dybatpho_array_sort_values "$1"
  local __dybatpho_array_sort_count="${#__dybatpho_array_sort_values[@]}"
  local __dybatpho_array_sort_value
  local __dybatpho_array_sort_hint="is not an integer; drop --numeric, or compare with the math module"
  if [[ "${__dybatpho_array_sort_numeric}" == true ]]; then
    for __dybatpho_array_sort_value in ${__dybatpho_array_sort_values[@]+"${__dybatpho_array_sort_values[@]}"}; do
      [[ "${__dybatpho_array_sort_value}" =~ ^-?[0-9]+$ ]] \
        || dybatpho::die \
          "dybatpho::array_sort: '${__dybatpho_array_sort_value}' ${__dybatpho_array_sort_hint}"
    done
  fi

  __dybatpho_array_merge_sort __dybatpho_array_sort_values \
    "${__dybatpho_array_sort_numeric}" "${__dybatpho_array_sort_reverse}"

  __dybatpho_array_copy "$1" __dybatpho_array_sort_values
  if [[ "${__dybatpho_array_sort_print}" == true ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Keep a run of an array in place and drop the rest.
#   A negative start counts back from the end, so `-2` takes the last two
#   elements without the caller working out the length first. A start past
#   either end leaves an empty array rather than failing: asking for elements
#   that are not there is a shape the data can have, not a mistake in the call.
# @example
#   items=(a b c d e)
#   dybatpho::array_slice items 1 3 --   # b c d
#   dybatpho::array_slice items -2 --    # the last two
#
# @arg $1 string Name of array
# @arg $2 number Index to start at, negative to count back from the end
# @arg $3 number Optional count, defaulting to everything from the start on
# @arg $4 string Set `--` to print to stdout
# @stdout Print the sliced array if `--` is given
# @exitcode 1 Stop the script when the start or the count is not a whole number
#######################################
function dybatpho::array_slice {
  dybatpho::expect_ref "$1"
  local __dybatpho_array_slice_start="${2-}"
  [[ "${__dybatpho_array_slice_start}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "dybatpho::array_slice: '${__dybatpho_array_slice_start}' is not a whole number"

  local -a __dybatpho_array_slice_values=()
  __dybatpho_array_copy __dybatpho_array_slice_values "$1"
  local __dybatpho_array_slice_count="${#__dybatpho_array_slice_values[@]}"

  # The count is optional, so the third argument is either it or the `--` that
  # would otherwise be fourth.
  local __dybatpho_array_slice_length="${__dybatpho_array_slice_count}" __dybatpho_array_slice_print="${4-}"
  if [[ "${3-}" == "--" ]]; then
    __dybatpho_array_slice_print="--"
  elif [[ -n "${3-}" ]]; then
    [[ "$3" =~ ^[0-9]+$ ]] \
      || dybatpho::die "dybatpho::array_slice: '$3' is not a count"
    __dybatpho_array_slice_length="$3"
  fi

  if ((__dybatpho_array_slice_start < 0)); then
    __dybatpho_array_slice_start=$((__dybatpho_array_slice_count + __dybatpho_array_slice_start))
    ((__dybatpho_array_slice_start >= 0)) || __dybatpho_array_slice_start=0
  fi

  local -a __dybatpho_array_slice_result=()
  local __dybatpho_array_slice_index
  # One bound rather than two comparisons a step: the slice ends at its own
  # length or at the end of the array, whichever comes first.
  local __dybatpho_array_slice_end=$((__dybatpho_array_slice_start + __dybatpho_array_slice_length))
  ((__dybatpho_array_slice_end <= __dybatpho_array_slice_count)) \
    || __dybatpho_array_slice_end="${__dybatpho_array_slice_count}"
  for ((__dybatpho_array_slice_index = __dybatpho_array_slice_start;  \
  __dybatpho_array_slice_index < __dybatpho_array_slice_end;  \
  __dybatpho_array_slice_index++)); do
    __dybatpho_array_slice_result+=("${__dybatpho_array_slice_values[${__dybatpho_array_slice_index}]}")
  done

  __dybatpho_array_copy "$1" __dybatpho_array_slice_result
  if [[ "${__dybatpho_array_slice_print}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Replace an array with the union of it and another, in place.
#   The result is a set: every value appears once, in the order it was first
#   seen, the first array's values ahead of the second's. A set operation that
#   kept duplicates would not be one, so `dybatpho::array_unique` afterwards has
#   nothing left to do.
# @example
#   allowed=(read write read)
#   extra=(write admin)
#   dybatpho::array_union allowed extra --   # read write admin
#
# @arg $1 string Name of the array to replace
# @arg $2 string Name of the array to merge in
# @arg $3 string Set `--` to print to stdout
# @stdout Print the union if $3 is `--`
#######################################
function dybatpho::array_union {
  dybatpho::expect_ref "$1"
  dybatpho::expect_ref "$2"
  local -a __dybatpho_array_set_values=() __dybatpho_array_set_addition=()
  __dybatpho_array_copy __dybatpho_array_set_values "$1"
  __dybatpho_array_copy __dybatpho_array_set_addition "$2"
  ((${#__dybatpho_array_set_addition[@]} == 0)) || __dybatpho_array_set_values+=("${__dybatpho_array_set_addition[@]}")

  local -A __dybatpho_array_set_seen=()
  local -a __dybatpho_array_set_result=()
  local __dybatpho_array_set_value
  for __dybatpho_array_set_value in ${__dybatpho_array_set_values[@]+"${__dybatpho_array_set_values[@]}"}; do
    if [[ ! -v "__dybatpho_array_set_seen[${__dybatpho_array_set_value}]" ]]; then
      __dybatpho_array_set_seen["${__dybatpho_array_set_value}"]=1
      __dybatpho_array_set_result+=("${__dybatpho_array_set_value}")
    fi
  done

  __dybatpho_array_copy "$1" __dybatpho_array_set_result
  if [[ "${3-}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Keep only the values an array shares with another, in place.
#   The result is a set, in the order the first array had them.
# @example
#   requested=(read write admin)
#   granted=(write read)
#   dybatpho::array_intersect requested granted --   # read write
#
# @arg $1 string Name of the array to replace
# @arg $2 string Name of the array to intersect with
# @arg $3 string Set `--` to print to stdout
# @stdout Print the intersection if $3 is `--`
#######################################
function dybatpho::array_intersect {
  dybatpho::expect_ref "$1"
  dybatpho::expect_ref "$2"
  local -A __dybatpho_array_set_other=()
  __dybatpho_array_index __dybatpho_array_set_other "$2"
  local -a __dybatpho_array_set_values=()
  __dybatpho_array_copy __dybatpho_array_set_values "$1"

  local -A __dybatpho_array_set_seen=()
  local -a __dybatpho_array_set_result=()
  local __dybatpho_array_set_value
  for __dybatpho_array_set_value in ${__dybatpho_array_set_values[@]+"${__dybatpho_array_set_values[@]}"}; do
    if [[ -v "__dybatpho_array_set_other[${__dybatpho_array_set_value}]" ]] \
      && [[ ! -v "__dybatpho_array_set_seen[${__dybatpho_array_set_value}]" ]]; then
      __dybatpho_array_set_seen["${__dybatpho_array_set_value}"]=1
      __dybatpho_array_set_result+=("${__dybatpho_array_set_value}")
    fi
  done

  __dybatpho_array_copy "$1" __dybatpho_array_set_result
  if [[ "${3-}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}

#######################################
# @description Drop the values an array shares with another, in place.
#   The result is a set, in the order the first array had them. The operation is
#   one-sided: values only the second array holds are not added.
# @example
#   wanted=(read write admin)
#   granted=(write)
#   dybatpho::array_difference wanted granted --   # read admin
#
# @arg $1 string Name of the array to replace
# @arg $2 string Name of the array to subtract
# @arg $3 string Set `--` to print to stdout
# @stdout Print the difference if $3 is `--`
#######################################
function dybatpho::array_difference {
  dybatpho::expect_ref "$1"
  dybatpho::expect_ref "$2"
  local -A __dybatpho_array_set_other=()
  __dybatpho_array_index __dybatpho_array_set_other "$2"
  local -a __dybatpho_array_set_values=()
  __dybatpho_array_copy __dybatpho_array_set_values "$1"

  local -A __dybatpho_array_set_seen=()
  local -a __dybatpho_array_set_result=()
  local __dybatpho_array_set_value
  for __dybatpho_array_set_value in ${__dybatpho_array_set_values[@]+"${__dybatpho_array_set_values[@]}"}; do
    if [[ ! -v "__dybatpho_array_set_other[${__dybatpho_array_set_value}]" ]] \
      && [[ ! -v "__dybatpho_array_set_seen[${__dybatpho_array_set_value}]" ]]; then
      __dybatpho_array_set_seen["${__dybatpho_array_set_value}"]=1
      __dybatpho_array_set_result+=("${__dybatpho_array_set_value}")
    fi
  done

  __dybatpho_array_copy "$1" __dybatpho_array_set_result
  if [[ "${3-}" == "--" ]]; then
    dybatpho::array_print "$1"
  fi
}
