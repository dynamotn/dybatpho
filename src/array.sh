#!/usr/bin/env bash
# @file array.sh
# @brief Utilities for working with array
# @description
#   This module contains functions to work with array.
#
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"

#######################################
# @description Reverse an array
# @arg $@ array
# @stdout Reversed array with each element separated by newline
#######################################
function dybatpho::array_reverse {
  local input_arr=("$@")
  local length=${#input_arr[@]}

  if ((length > 0)); then
    printf '%s\n' "${input_arr[-1]}"
    dybatpho::array_reverse "${input_arr[@]::length-1}"
  fi
}

#######################################
# @description Remove duplicate elements in array
# @arg $@ array
# @stdout Result array with each element separated by newline
#######################################
function dybatpho::array_unique {
  local result_arr=()

  for i in "$@"; do
    [[ $i ]] && IFS=" " result_arr["${i:- }"]=1
  done

  printf '%s\n' "${!result_arr[@]}"
}
