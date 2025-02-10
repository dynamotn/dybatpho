#!/usr/bin/env bash
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# Trim leading and trailing white-space from string.
# Arguments:
#   1: string to change
# Outputs:
#   Trimmed string
#######################################
# shellcheck disable=SC2317
_trim() {
  : "${1#"${1%%[![:space:]]*}"}"
  : "${_%"${_##*[![:space:]]}"}"
  printf '%s\n' "$_"
}

#######################################
# Split a string on a delimiter.
# Arguments:
#   1: string to split
#   2: delimiter
# Outputs:
#   Show each part of splited string
#######################################
_split() {
  IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
  printf '%s\n' "${arr[@]}"
}

#######################################
# URL-encode a string.
# Arguments:
#   1: string to encode
# Outputs:
#   Encoded string
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
# URL-decode a string.
# Arguments:
#   1: string to decode
# Outputs:
#   Decoded string
#######################################
_url_decode() {
  : "${1//+/ }"
  printf '%b\n' "${_//%/\\x}"
}

#######################################
# Convert a string to lowercase.
# Arguments:
#   1: string to change
# Outputs:
#   Converted string
#######################################
_lower() {
  printf '%s\n' "${1,,}"
}

#######################################
# Convert a string to uppercase.
# Arguments:
#   1: string to change
# Outputs:
#   Converted string
#######################################
_upper() {
  printf '%s\n' "${1^^}"
}

#######################################
# Reverse a string case.
# Arguments:
#   1: string to convert
# Outputs:
#   Converted string
#######################################
_reverse() {
  printf '%s\n' "${1~~}"
}
