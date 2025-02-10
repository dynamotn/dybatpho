#!/usr/bin/env bash
# @file string.sh
# @brief Utilities for working with string
# @description
#   This module contains functions to manipulate, convert, etc with string.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Trim leading and trailing white-space from string.
# @arg $1 string String to change
# @stdout Trimmed string
#######################################
# shellcheck disable=SC2317
_trim() {
  : "${1#"${1%%[![:space:]]*}"}"
  : "${_%"${_##*[![:space:]]}"}"
  printf '%s\n' "$_"
}

#######################################
# @description Split a string on a delimiter.
# @arg $1 string String to split
# @arg $2 string Delimiter
# @stdout Show each part of splited string
#######################################
_split() {
  IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
  printf '%s\n' "${arr[@]}"
}

#######################################
# @description URL-encode a string.
# @arg $1 string String to encode
# @stdout Encoded string
#######################################
_url_encode() {
  local LC_ALL=C
  for (( i = 0; i < ${#1}; i++ )); do
    : "${1:i:1}"
    case "$_" in
      [a-zA-Z0-9.~_-])
        printf '%s' "$_"
        ;;

      *)
        printf '%%%02X' "'$_"
        ;;
    esac
  done
  printf '\n'
}

#######################################
# @description URL-decode a string.
# @arg $1 string String to decode
# @stdout Decoded string
#######################################
_url_decode() {
  : "${1//+/ }"
  printf '%b\n' "${_//%/\\x}"
}

#######################################
# @description Convert a string to lowercase.
# @arg $1 string String to convert
# @stdout Converted string
#######################################
_lower() {
  printf '%s\n' "${1,,}"
}

#######################################
# @description Convert a string to uppercase.
# @arg $1 string String to convert
# @stdout Converted string
#######################################
_upper() {
  printf '%s\n' "${1^^}"
}

#######################################
# @description Reverse a string case.
# @arg $1 string String to convert
# @stdout Converted string
#######################################
_reverse() {
  printf '%s\n' "${1~~}"
}
