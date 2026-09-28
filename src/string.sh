#!/usr/bin/env bash
# @file string.sh
# @brief Utilities for working with string
# @description
#   This module contains helpers for trimming, splitting, matching, replacing,
#   trimming exact prefixes/suffixes and characters, slugifying, truncating,
#   counting lines, testing blank strings, wrapping text, repeating, padding,
#   encoding, decoding, and case-converting shell strings.
#
#   The naming-convention helpers convert between `snake_case`, `kebab-case`,
#   `camelCase`, and `PascalCase`, reading the word boundaries whichever
#   convention the input arrived in. `dybatpho::string_quote` prepares a value
#   to be written into shell code that will be evaluated later.
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
  local value="${1-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

#######################################
# @description Split a string on an exact delimiter.
#   The delimiter is matched literally, never as a glob pattern, so `*`, `?`
#   and `[` are ordinary characters in it. An empty delimiter prints the input
#   unchanged.
#
#   A run of `n` delimiters yields `n + 1` fields, including the empty ones at
#   either end: splitting `a,b,,` on `,` gives `a`, `b`, an empty field and a
#   trailing empty field. Consumers that do not want the empty fields drop them
#   themselves, because only the caller knows whether an empty field is data.
# @arg $1 string String to split
# @arg $2 string Delimiter string
# @stdout Print each split part on its own line
#######################################
function dybatpho::split {
  local input="${1-}" delimiter="${2-}"
  if [[ -z "${delimiter}" ]]; then
    printf '%s\n' "${input}"
    return 0
  fi
  local -a parts=()
  local rest="${input}"
  while [[ "${rest}" == *"${delimiter}"* ]]; do
    parts+=("${rest%%"${delimiter}"*}")
    rest="${rest#*"${delimiter}"}"
  done
  parts+=("${rest}")
  printf '%s\n' "${parts[@]}"
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
  [[ -z "${prefix}" || "${input#"${prefix}"}" != "${input}" ]]
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
  [[ -z "${suffix}" || "${input%"${suffix}"}" != "${input}" ]]
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
  [[ -z "${needle}" || "${input#*"${needle}"}" != "${input}" ]]
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
  printf '%s\n' "${input//"${needle}"/"${replacement}"}"
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
    printf '%s\n' "${input#"${prefix}"}"
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
    printf '%s\n' "${input%"${suffix}"}"
  else
    printf '%s\n' "${input}"
  fi
}

# Latin letters carrying a diacritic, and the ASCII they stand in for. Slugs
# are ASCII by definition, and dropping the letter outright turned `Thế Giới`
# into `th-gi-i` -- a slug that names nothing. Only lowercase forms are listed,
# because the slug is lowercased before the table is consulted.
#
# The empty targets are the combining marks: text that arrives decomposed is a
# plain letter followed by one of them, so the mark is removed and the letter
# it sits on is kept.
declare -gA __DYBATPHO_STRING_ASCII=()

#######################################
# @description Fill the transliteration table, once, when the module loads.
# @set __DYBATPHO_STRING_ASCII
#######################################
function __dybatpho_string_build_ascii {
  local spec target chars index
  for spec in \
    "a:àáâãäåāăąạảấầẩẫậắằẳẵặ" \
    "e:èéêëēĕėęěẹẻẽếềểễệ" \
    "i:ìíîïĩīĭįıỉị" \
    "o:òóôõöøōŏőơọỏốồổỗộớờởỡợ" \
    "u:ùúûüũūŭůűųưụủứừửữự" \
    "y:ýÿŷỳỷỹỵ" \
    "d:đďð" \
    "c:çćĉċč" \
    "n:ñńņňŋ" \
    "s:śŝşš" \
    "z:źżž" \
    "g:ĝğġģ" \
    "l:ĺļľŀł" \
    "r:ŕŗř" \
    "t:ţťŧþ" \
    "h:ĥħ" \
    "j:ĵ" \
    "k:ķ" \
    "w:ŵ" \
    "ae:æ" \
    "oe:œ" \
    "ss:ß" \
    ":̧̨̣̀́̂̃̈̉̌̄̆̇̊̋"; do
    target="${spec%%:*}"
    chars="${spec#*:}"
    for ((index = 0; index < ${#chars}; index++)); do
      __DYBATPHO_STRING_ASCII["${chars:index:1}"]="${target}"
    done
  done
}
__dybatpho_string_build_ascii
unset -f __dybatpho_string_build_ascii

#######################################
# @description Convert a string into a lowercase ASCII slug.
#   A letter carrying a diacritic becomes the ASCII letter underneath it, so
#   `Thế Giới` slugs to `the-gioi` rather than to `th-gi-i`. Anything else
#   outside `a-z0-9` is a separator, and a run of separators collapses into a
#   single `-`.
# @example
#   dybatpho::string_slugify "Thế Giới"   # the-gioi
#   dybatpho::string_slugify "Crème brûlée 2024" # creme-brulee-2024
#
# @arg $1 string Input string
# @stdout Slugified string
# @note The input is walked character by character, so a locale that reports
#   UTF-8 text as single bytes (`LC_ALL=C`) transliterates nothing
#######################################
function dybatpho::string_slugify {
  local input slug char mapped
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
        if [[ -v "__DYBATPHO_STRING_ASCII[${char}]" ]]; then
          mapped="${__DYBATPHO_STRING_ASCII[${char}]}"
          # A combining mark maps to nothing: it leaves the letter before it
          # alone rather than standing in for a separator.
          [[ -z "${mapped}" ]] && continue
          slug+="${mapped}"
          last_was_separator=false
          continue
        fi
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
  local i character
  for ((i = 0; i < ${#1}; i++)); do
    character="${1:i:1}"
    case "${character}" in
      [a-zA-Z0-9.~_-])
        printf '%s' "${character}"
        ;;

      *)
        printf '%%%02X' "'${character}"
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
  local value="${1//+/ }"
  printf '%b\n' "${value//%/\\x}"
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

#######################################
# @description Split a string into the words its naming convention implies.
#   Every case helper in this module goes through here, so they all accept the
#   same input whatever convention it arrived in: `fooBar`, `foo_bar`,
#   `foo-bar`, `Foo Bar` and `FOO_BAR` all give the same two words.
#
#   A capital opens a new word after a lowercase letter or a digit, and at the
#   end of a run of capitals that is followed by a lowercase one, which is what
#   keeps `XMLHttpRequest` reading as `xml http request` rather than as one
#   word or as one letter per word. A digit stays attached to the word it
#   follows, so `foo2bar` is one word: splitting there would be guessing.
#
#   The cost of that acronym rule is single-letter words: `ABC` reads as one
#   word, because nothing in it says whether it was an acronym or `a b c`. A
#   name that went through `dybatpho::string_to_pascal` as `a_b_c` does not come
#   back. There is no rule that gets both cases right, and acronyms are the ones
#   that turn up in real names.
# @arg $1 string String to split
# @arg $2 string Name of the array variable receiving the lower-cased words
# @set The named array
#######################################
function __dybatpho_string_words {
  local __words_input="${1-}"
  local -n __words_out="$2"
  __words_out=()
  local __words_current="" __words_previous="" __words_next="" __words_char
  local __words_index
  for ((__words_index = 0; __words_index < ${#__words_input}; __words_index++)); do
    __words_char="${__words_input:__words_index:1}"
    __words_next="${__words_input:__words_index+1:1}"
    case "${__words_char}" in
      [A-Z])
        if [[ "${__words_previous}" == [a-z0-9] ]] \
          || { [[ "${__words_previous}" == [A-Z] ]] && [[ "${__words_next}" == [a-z] ]]; }; then
          [[ -z "${__words_current}" ]] || {
            __words_out+=("${__words_current}")
            __words_current=""
          }
        fi
        __words_current+="${__words_char,,}"
        ;;
      [a-z0-9])
        __words_current+="${__words_char}"
        ;;
      *)
        [[ -z "${__words_current}" ]] || {
          __words_out+=("${__words_current}")
          __words_current=""
        }
        ;;
    esac
    __words_previous="${__words_char}"
  done
  [[ -z "${__words_current}" ]] || __words_out+=("${__words_current}")
}

#######################################
# @description Convert a string to `snake_case`.
# @example
#   dybatpho::string_to_snake "XMLHttpRequest"   # xml_http_request
#   dybatpho::string_to_snake "deploy-to-prod"   # deploy_to_prod
#
# @arg $1 string String to convert
# @stdout The string in snake case, empty when it holds no letters or digits
# @see
#   - `dybatpho::string_to_kebab`
#   - `dybatpho::string_slugify`
#######################################
function dybatpho::string_to_snake {
  local input
  dybatpho::expect_args input -- "$@"
  local -a words=()
  __dybatpho_string_words "${input}" words
  local IFS='_'
  printf '%s\n' "${words[*]-}"
}

#######################################
# @description Convert a string to `kebab-case`.
#   Unlike `dybatpho::string_slugify`, this reads the word boundaries a naming
#   convention implies, so `XMLHttpRequest` becomes `xml-http-request` rather
#   than `xmlhttprequest`. Slugify is for prose; this is for identifiers.
# @example
#   dybatpho::string_to_kebab "XMLHttpRequest"   # xml-http-request
#   dybatpho::string_to_kebab "deploy_to_prod"   # deploy-to-prod
#
# @arg $1 string String to convert
# @stdout The string in kebab case, empty when it holds no letters or digits
# @see
#   - `dybatpho::string_to_snake`
#   - `dybatpho::string_slugify`
#######################################
function dybatpho::string_to_kebab {
  local input
  dybatpho::expect_args input -- "$@"
  local -a words=()
  __dybatpho_string_words "${input}" words
  local IFS='-'
  printf '%s\n' "${words[*]-}"
}

#######################################
# @description Convert a string to `camelCase`.
# @example
#   dybatpho::string_to_camel "deploy_to_prod"   # deployToProd
#   dybatpho::string_to_camel "XMLHttpRequest"   # xmlHttpRequest
#
# @arg $1 string String to convert
# @stdout The string in camel case, empty when it holds no letters or digits
# @see
#   - `dybatpho::string_to_pascal`
#######################################
function dybatpho::string_to_camel {
  local input
  dybatpho::expect_args input -- "$@"
  local -a words=()
  __dybatpho_string_words "${input}" words
  ((${#words[@]} > 0)) || {
    printf '\n'
    return 0
  }
  local result="${words[0]}" index
  for ((index = 1; index < ${#words[@]}; index++)); do
    result+="${words[${index}]^}"
  done
  printf '%s\n' "${result}"
}

#######################################
# @description Convert a string to `PascalCase`.
# @example
#   dybatpho::string_to_pascal "deploy_to_prod"   # DeployToProd
#
# @arg $1 string String to convert
# @stdout The string in Pascal case, empty when it holds no letters or digits
# @see
#   - `dybatpho::string_to_camel`
#######################################
function dybatpho::string_to_pascal {
  local input
  dybatpho::expect_args input -- "$@"
  local -a words=()
  __dybatpho_string_words "${input}" words
  local result="" word
  for word in ${words[@]+"${words[@]}"}; do
    result+="${word^}"
  done
  printf '%s\n' "${result}"
}

#######################################
# @description Quote a string so the shell reads it back as one literal value.
#   This is what to reach for when a value is going into generated shell code:
#   a completion script, a `--command` argument, or anything that will be
#   evaluated later. Writing the value in by hand leaves whitespace, quotes and
#   `$` to be read as syntax rather than as data.
#
#   The empty string quotes to `''` rather than to nothing, which is the whole
#   point: an unquoted empty value disappears from the command it was part of.
# @example
#   dybatpho::string_quote "a b"          # a\ b
#   dybatpho::string_quote ""             # ''
#   printf 'ssh host %s\n' "$(dybatpho::string_quote "${remote_command}")"
#
# @arg $1 string Value to quote
# @stdout The value quoted for the shell
#######################################
function dybatpho::string_quote {
  printf '%q\n' "${1-}"
}
