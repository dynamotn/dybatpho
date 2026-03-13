#!/usr/bin/env bash
# @file string.sh
# @brief Utilities for working with string
# @description
#   This module contains helpers for trimming, splitting, encoding, decoding,
#   and case-converting shell strings.
# @see
#   - `example/string_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Trim leading and trailing whitespace from a string.
# @arg $1 string String to trim
# @stdout Trimmed string
#######################################
# shellcheck disable=SC2317
function dybatpho::trim {
  : "${1#"${1%%[![:space:]]*}"}"
  : "${_%"${_##*[![:space:]]}"}"
  printf '%s\n' "${_}"
}

#######################################
# @description Split a string on an exact delimiter.
# @arg $1 string String to split
# @arg $2 string Delimiter string
# @stdout Print each split part on its own line
#######################################
function dybatpho::split {
  IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}" || true
  printf '%s\n' "${arr[@]}"
}

#######################################
# @description URL-encode a string.
# @arg $1 string String to encode
# @stdout Encoded string
#######################################
function dybatpho::url_encode {
  local LC_ALL=C
  local i
  for ((i = 0; i < ${#1}; i++)); do
    : "${1:i:1}"
    case "${_}" in
      [a-zA-Z0-9.~_-])
        printf '%s' "${_}"
        ;;

      *)
        printf '%%%02X' "'${_}"
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
function dybatpho::url_decode {
  : "${1//+/ }"
  printf '%b\n' "${_//%/\\x}"
}

#######################################
# @description Convert a string to lowercase.
# @arg $1 string String to convert
# @stdout Converted string
#######################################
function dybatpho::lower {
  printf '%s\n' "${1,,}"
}

#######################################
# @description Convert a string to uppercase.
# @arg $1 string String to convert
# @stdout Converted string
#######################################
function dybatpho::upper {
  printf '%s\n' "${1^^}"
}
