#!/usr/bin/env bash
# @file string.sh
# @brief Utilities for working with string
# @description
#   This module contains helpers for trimming, splitting, matching, replacing,
#   trimming exact prefixes/suffixes and characters, slugifying, truncating,
#   counting lines, testing blank strings, wrapping text, repeating, padding,
#   encoding, decoding, and case-converting shell strings.
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
# @description Return success when a string starts with the given prefix.
# @arg $1 string Input string
# @arg $2 string Prefix to match
# @exitcode 0 The input starts with the prefix
# @exitcode 1 The input does not start with the prefix
#######################################
function dybatpho::string_starts_with {
  local input="${1-}"
  local prefix="${2-}"
  [[ -z "${prefix}" || "${input#"$prefix"}" != "${input}" ]]
}

#######################################
# @description Return success when a string ends with the given suffix.
# @arg $1 string Input string
# @arg $2 string Suffix to match
# @exitcode 0 The input ends with the suffix
# @exitcode 1 The input does not end with the suffix
#######################################
function dybatpho::string_ends_with {
  local input="${1-}"
  local suffix="${2-}"
  [[ -z "${suffix}" || "${input%"$suffix"}" != "${input}" ]]
}

#######################################
# @description Return success when a string contains the given substring.
# @arg $1 string Input string
# @arg $2 string Substring to match
# @exitcode 0 The input contains the substring
# @exitcode 1 The input does not contain the substring
#######################################
function dybatpho::string_contains {
  local input="${1-}"
  local needle="${2-}"
  [[ -z "${needle}" || "${input#*"$needle"}" != "${input}" ]]
}

#######################################
# @description Replace all exact substring matches in a string.
# @arg $1 string Input string
# @arg $2 string Substring to replace
# @arg $3 string Replacement text
# @stdout String with all matches replaced
#######################################
function dybatpho::string_replace {
  local input="${1-}"
  local needle="${2-}"
  local replacement="${3-}"
  if [[ -z "${needle}" ]]; then
    printf '%s\n' "${input}"
    return 0
  fi
  printf '%s\n' "${input//"$needle"/"$replacement"}"
}

#######################################
# @description Remove an exact prefix from a string when it matches.
# @arg $1 string Input string
# @arg $2 string Prefix to remove
# @stdout String without the matching prefix, or the original string
#######################################
function dybatpho::string_trim_prefix {
  local input prefix
  dybatpho::expect_args input prefix -- "$@"
  if dybatpho::string_starts_with "${input}" "${prefix}"; then
    printf '%s\n' "${input#"$prefix"}"
  else
    printf '%s\n' "${input}"
  fi
}

#######################################
# @description Remove an exact suffix from a string when it matches.
# @arg $1 string Input string
# @arg $2 string Suffix to remove
# @stdout String without the matching suffix, or the original string
#######################################
function dybatpho::string_trim_suffix {
  local input suffix
  dybatpho::expect_args input suffix -- "$@"
  if dybatpho::string_ends_with "${input}" "${suffix}"; then
    printf '%s\n' "${input%"$suffix"}"
  else
    printf '%s\n' "${input}"
  fi
}

#######################################
# @description Convert a string into a lowercase ASCII slug.
# @arg $1 string Input string
# @stdout Slugified string
#######################################
function dybatpho::string_slugify {
  local input slug char
  dybatpho::expect_args input -- "$@"
  input=$(dybatpho::lower "${input}")
  slug=""
  local last_was_separator=false
  local i

  for ((i = 0; i < ${#input}; i++)); do
    char="${input:i:1}"
    case "${char}" in
      [a-z0-9])
        slug+="${char}"
        last_was_separator=false
        ;;
      *)
        if [[ "${last_was_separator}" == false && -n "${slug}" ]]; then
          slug+='-'
          last_was_separator=true
        fi
        ;;
    esac
  done

  printf '%s\n' "${slug%-}"
}

#######################################
# @description Return success when a string is empty or contains only whitespace.
# @arg $1 string Input string
# @exitcode 0 The input is blank
# @exitcode 1 The input contains non-whitespace characters
#######################################
function dybatpho::string_is_blank {
  local input trimmed
  dybatpho::expect_args input -- "$@"
  trimmed=$(dybatpho::trim "${input}")
  [[ -z "${trimmed}" ]]
}

#######################################
# @description Trim a set of exact characters from both ends of a string.
# @arg $1 string Input string
# @arg $2 string Characters to trim
# @stdout Trimmed string
#######################################
function dybatpho::string_trim_chars {
  local input trim_chars first_char last_char
  dybatpho::expect_args input trim_chars -- "$@"
  if [[ -z "${trim_chars}" ]]; then
    printf '%s\n' "${input}"
    return 0
  fi
  while [[ -n "${input}" ]]; do
    first_char="${input:0:1}"
    dybatpho::string_contains "${trim_chars}" "${first_char}" || break
    input="${input:1}"
  done
  while [[ -n "${input}" ]]; do
    last_char="${input: -1}"
    dybatpho::string_contains "${trim_chars}" "${last_char}" || break
    input="${input:0:${#input}-1}"
  done
  printf '%s\n' "${input}"
}

#######################################
# @description Truncate a string to a maximum width and append a suffix when needed.
# @arg $1 string Input string
# @arg $2 number Maximum width
# @arg $3 string Optional truncation suffix, default is `...`
# @stdout Truncated string
#######################################
function dybatpho::string_truncate {
  local input width suffix
  dybatpho::expect_args input width -- "$@"
  suffix="${3:-...}"
  if ((width <= 0)); then
    printf '\n'
    return 0
  fi
  if ((${#input} <= width)); then
    printf '%s\n' "${input}"
    return 0
  fi
  if ((${#suffix} >= width)); then
    printf '%s\n' "${suffix:0:${width}}"
    return 0
  fi
  printf '%s\n' "${input:0:$((width - ${#suffix}))}${suffix}"
}

#######################################
# @description Count the number of logical lines in a string.
# @arg $1 string Input string
# @stdout Number of lines
#######################################
function dybatpho::string_lines {
  local input
  dybatpho::expect_args input -- "$@"
  if [[ -z "${input}" ]]; then
    printf '0\n'
    return 0
  fi
  local lines=1
  local without_newlines="${input//$'\n'/}"
  printf '%s\n' "$((lines + ${#input} - ${#without_newlines}))"
}

#######################################
# @description Wrap a string to a maximum width, normalizing whitespace between words.
# @arg $1 string Input string
# @arg $2 number Maximum width
# @arg $3 string Optional indent prefix for wrapped continuation lines
# @stdout Wrapped lines
#######################################
function dybatpho::string_wrap {
  local input width indent
  dybatpho::expect_args input width -- "$@"
  indent="${3-}"
  if ((width <= 0)); then
    printf '%s\n' "${input}"
    return 0
  fi

  local -a words=()
  local word current_line=""
  read -r -a words <<< "${input}"
  if ((${#words[@]} == 0)); then
    printf '\n'
    return 0
  fi

  for word in "${words[@]}"; do
    if [[ -z "${current_line}" ]]; then
      current_line="${word}"
    elif ((${#current_line} + 1 + ${#word} <= width)); then
      current_line+=" ${word}"
    else
      printf '%s\n' "${current_line}"
      current_line="${indent}${word}"
    fi
  done
  printf '%s\n' "${current_line}"
}

#######################################
# @description Repeat a string a fixed number of times.
# @arg $1 string Input string
# @arg $2 number Repeat count
# @stdout Repeated string
#######################################
function dybatpho::string_repeat {
  local input count
  dybatpho::expect_args input count -- "$@"
  local repeated=""
  local i
  if ((count <= 0)); then
    printf '\n'
    return 0
  fi
  for ((i = 0; i < count; i++)); do
    repeated+="${input}"
  done
  printf '%s\n' "${repeated}"
}

#######################################
# @description Pad a string on the right to a minimum width.
# @arg $1 string Input string
# @arg $2 number Minimum width
# @arg $3 string Optional padding token, default is a space
# @stdout Padded string
#######################################
function dybatpho::string_pad {
  local input width pad_token
  dybatpho::expect_args input width -- "$@"
  pad_token="${3:- }"
  local padded="${input}"
  if [ "${#padded}" -ge "${width}" ]; then
    printf '%s\n' "${padded}"
    return 0
  fi
  if [[ -z "${pad_token}" ]]; then
    pad_token=' '
  fi
  while [ "${#padded}" -lt "${width}" ]; do
    padded="${padded}${pad_token}"
  done
  printf '%s\n' "${padded:0:${width}}"
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
