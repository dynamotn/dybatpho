# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# parses its own arguments, so the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG051
# @file json.sh
# @brief Utilities for working with JSON and YAML data
# @namespace dybatpho
# @description
#   This module contains helpers for querying, validating, formatting, and
#   converting JSON and YAML documents through `yq`, with `jq` kept as a JSON
#   fallback where practical.
#
# @tip The YAML helpers target the Mike Farah `yq` command line (`yq eval ...`)
# @tip JSON helpers prefer `yq` because it can read JSON directly, and fall back to `jq` when needed
#
# @see
#   - `example/json_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Quote text as a JSON string, into a named variable.
#   Escaping a string is the one JSON operation that needs no parser, and
#   forking `yq` or `jq` for it cost ~12ms a call -- enough to dominate any
#   loop that builds a request body or a structured log line. The result
#   carries its own surrounding quotes.
#
#   Bytes below 0x20 that JSON has no short escape for go out as `\u00XX`, as
#   does `DEL`, which is what `jq` emits for it. Everything else is passed
#   through, which is what keeps UTF-8 text readable: JSON takes it verbatim
#   and only `"` and `\` need escaping.
# @arg $1 string Name of the variable receiving the quoted string
# @arg $2 string Text to encode
# @set The named variable
# @internal
#######################################
function __dybatpho_json_escape_into {
  local -n __dybatpho_json_escape_out="$1"
  local __dybatpho_json_escape_text="${2-}"
  local __dybatpho_json_escape_result='"'
  local __dybatpho_json_escape_char __dybatpho_json_escape_index __dybatpho_json_escape_code

  # The cheap path: text with nothing to escape is the common case, and this
  # avoids walking it character by character. `[[:cntrl:]]` rather than a
  # `\x01`-`\x1f` range, because a bracket range is resolved by the locale's
  # collation and a multi-byte character can fall inside one.
  if [[ "${__dybatpho_json_escape_text}" != *[\\\"]* &&
    "${__dybatpho_json_escape_text}" != *[[:cntrl:]]* ]]; then
    __dybatpho_json_escape_out="\"${__dybatpho_json_escape_text}\""
    return 0
  fi

  for ((__dybatpho_json_escape_index = 0;  \
  __dybatpho_json_escape_index < ${#__dybatpho_json_escape_text};  \
  __dybatpho_json_escape_index++)); do
    __dybatpho_json_escape_char="${__dybatpho_json_escape_text:__dybatpho_json_escape_index:1}"
    case "${__dybatpho_json_escape_char}" in
      '"') __dybatpho_json_escape_result+='\"' ;;
      $'\\') __dybatpho_json_escape_result+=$'\\\\' ;;
      $'\b') __dybatpho_json_escape_result+='\b' ;;
      $'\f') __dybatpho_json_escape_result+='\f' ;;
      $'\n') __dybatpho_json_escape_result+='\n' ;;
      $'\r') __dybatpho_json_escape_result+='\r' ;;
      $'\t') __dybatpho_json_escape_result+='\t' ;;
      *)
        # Anything else is passed through unless it is a control character
        # JSON has no short escape for. The code point decides that, so a
        # multi-byte character is never mistaken for one.
        printf -v __dybatpho_json_escape_code '%d' "'${__dybatpho_json_escape_char}"
        if ((__dybatpho_json_escape_code < 32 || __dybatpho_json_escape_code == 127)); then
          printf -v __dybatpho_json_escape_result '%s\\u%04x' \
            "${__dybatpho_json_escape_result}" "${__dybatpho_json_escape_code}"
        else
          __dybatpho_json_escape_result+="${__dybatpho_json_escape_char}"
        fi
        ;;
    esac
  done
  __dybatpho_json_escape_out="${__dybatpho_json_escape_result}\""
}

#######################################
# @description Query a JSON document with `yq`, or `jq` as a fallback.
# @arg $1 string JSON file path or `-` for stdin
# @arg $2 string Query filter
# @arg $@ string Extra arguments forwarded to the selected backend
# @stdout Result of the JSON query
# @exitcode 0 Query succeeded
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_query {
  local input filter
  dybatpho::expect_args input filter -- "$@"
  shift 2
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  if [[ "${json_cmd}" == "yq" ]]; then
    yq eval -o=json "${filter}" "${input}" "$@"
  else
    jq "${filter}" "${input}" "$@"
  fi
}

#######################################
# @description Return success when a JSON document satisfies a filter.
# @arg $1 string JSON file path or `-` for stdin
# @arg $2 string Query filter
# @exitcode 0 The filter succeeds
# @exitcode 1 The filter fails
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_has {
  local input filter
  dybatpho::expect_args input filter -- "$@"
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  if [[ "${json_cmd}" == "yq" ]]; then
    yq eval -e "${filter}" "${input}" > /dev/null
  else
    jq -e "${filter}" "${input}" > /dev/null
  fi
}

#######################################
# @description Pretty-print a JSON document.
# @arg $1 string JSON file path or `-` for stdin
# @arg $2 string Optional output file path
# @stdout Pretty JSON when no output file is provided
# @exitcode 0 Formatting succeeded
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_pretty {
  local input
  dybatpho::expect_args input -- "$@"
  local output="${2-}"
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  if [[ -n "${output}" ]]; then
    if [[ "${json_cmd}" == "yq" ]]; then
      yq eval -o=json '.' "${input}" > "${output}"
    else
      jq '.' "${input}" > "${output}"
    fi
  else
    if [[ "${json_cmd}" == "yq" ]]; then
      yq eval -o=json '.' "${input}"
    else
      jq '.' "${input}"
    fi
  fi
}

#######################################
# @description Convert a JSON document to YAML.
# @arg $1 string JSON file path or `-` for stdin
# @arg $2 string Optional output file path
# @stdout YAML output when no output file is provided
# @exitcode 0 Conversion succeeded
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::json_to_yaml {
  local input
  dybatpho::expect_args input -- "$@"
  local output="${2-}"
  dybatpho::require yq
  if [[ -n "${output}" ]]; then
    yq eval -P '.' "${input}" > "${output}"
  else
    yq eval -P '.' "${input}"
  fi
}

#######################################
# @description Query a YAML document with `yq`.
# @arg $1 string YAML file path or `-` for stdin
# @arg $2 string yq expression
# @arg $@ string Extra arguments forwarded to `yq eval`
# @stdout Result of the yq query
# @exitcode 0 Query succeeded
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_query {
  local input expression
  dybatpho::expect_args input expression -- "$@"
  shift 2
  dybatpho::require yq
  yq eval "${expression}" "${input}" "$@"
}

#######################################
# @description Return success when a YAML document satisfies a `yq` expression.
# @arg $1 string YAML file path or `-` for stdin
# @arg $2 string yq expression
# @exitcode 0 The expression succeeds
# @exitcode 1 The expression fails
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_has {
  local input expression
  dybatpho::expect_args input expression -- "$@"
  dybatpho::require yq
  yq eval -e "${expression}" "${input}" > /dev/null
}

#######################################
# @description Pretty-print a YAML document.
# @arg $1 string YAML file path or `-` for stdin
# @arg $2 string Optional output file path
# @stdout Pretty YAML when no output file is provided
# @exitcode 0 Formatting succeeded
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_pretty {
  local input
  dybatpho::expect_args input -- "$@"
  local output="${2-}"
  dybatpho::require yq
  if [[ -n "${output}" ]]; then
    yq eval -P '.' "${input}" > "${output}"
  else
    yq eval -P '.' "${input}"
  fi
}

#######################################
# @description Convert a YAML document to JSON.
# @arg $1 string YAML file path or `-` for stdin
# @arg $2 string Optional output file path
# @stdout JSON output when no output file is provided
# @exitcode 0 Conversion succeeded
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_to_json {
  local input
  dybatpho::expect_args input -- "$@"
  local output="${2-}"
  dybatpho::require yq
  if [[ -n "${output}" ]]; then
    yq eval -o=json '.' "${input}" > "${output}"
  else
    yq eval -o=json '.' "${input}"
  fi
}

#######################################
# @description Encode a string as a JSON string value, surrounding quotes included.
# Use this instead of wrapping text in quotes by hand: a value containing a
# quotation mark, a backslash, or a newline breaks hand-built JSON and this
# does not.
# @example
#   dybatpho::json_string 'he said "hi"' # "he said \"hi\""
#
# @arg $1 string Text to encode
# @stdout Quoted JSON string
# @exitcode 0 The value was encoded
# @exitcode 1 Missing argument
# @note Quoting is done in the shell, so this is the one JSON helper that needs
#   neither `yq` nor `jq`
#######################################
function dybatpho::json_string {
  local text
  dybatpho::expect_args text -- "$@"
  local quoted
  __dybatpho_json_escape_into quoted "${text}"
  printf '%s\n' "${quoted}"
}

#######################################
# @description Build a JSON object from name and value pairs.
# Every value is escaped, so no caller has to think about quoting. A name
# ending in `:json` marks a value that is already a JSON document and is
# inserted as-is, which is how you nest an object or an array.
# @example
#   dybatpho::json_object status ok message 'it "worked"'
#   # {"status":"ok","message":"it \"worked\""}
#
# @example
#   dybatpho::json_object name api ports:json '[80,443]'
#   # {"name":"api","ports":[80,443]}
#
# @arg $@ string Alternating names and values
# @stdout Compact JSON object
# @exitcode 0 The object was built
# @exitcode 1 An odd number of arguments, or an invalid nested document
# @exitcode 127 Neither `yq` nor `jq` is installed
# @tip Build nested structures from the inside out, passing each finished document through a `:json` name
#######################################
function dybatpho::json_object {
  (($# % 2 == 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected an even number of arguments, got $#"
  if (($# == 0)); then
    printf '%s\n' '{}'
    return 0
  fi

  local json_cmd
  __dybatpho_json_cmd_into json_cmd

  # Every pair is assigned in a single backend invocation. Building the object
  # one key at a time would fork once per field, which is the difference
  # between a handful of processes per request and several dozen.
  local filter='{}' name value index=0
  local -a environment=() arguments=()
  while (($# >= 2)); do
    name="$1"
    value="$2"
    shift 2
    local raw=false
    if [[ "${name}" == *:json ]]; then
      raw=true
      name="${name%:json}"
    fi
    if [[ "${json_cmd}" == "yq" ]]; then
      environment+=("__dybatpho_json_n${index}=${name}" "__dybatpho_json_v${index}=${value}")
      if [[ "${raw}" == true ]]; then
        filter+=" | .[strenv(__dybatpho_json_n${index})] = (strenv(__dybatpho_json_v${index}) | from_json)"
      else
        filter+=" | .[strenv(__dybatpho_json_n${index})] = strenv(__dybatpho_json_v${index})"
      fi
    else
      arguments+=(--arg "n${index}" "${name}")
      if [[ "${raw}" == true ]]; then
        arguments+=(--argjson "v${index}" "${value}")
      else
        arguments+=(--arg "v${index}" "${value}")
      fi
      filter+=" | .[\$n${index}] = \$v${index}"
    fi
    index=$((index + 1))
  done

  if [[ "${json_cmd}" == "yq" ]]; then
    env "${environment[@]}" yq -n -o=json -I=0 "${filter}"
  else
    jq -n -c "${arguments[@]}" "${filter}"
  fi
}

#######################################
# @description Evaluate a filter against a JSON document held in a variable.
# Unlike `dybatpho::json_query`, which reads a file, this works on a document a
# script is still assembling.
# @example
#   local messages='[]'
#   messages=$(dybatpho::json_eval "${messages}" \
#     ". + [$(dybatpho::json_object role user content "${prompt}")]")
#
# @arg $1 string JSON document
# @arg $2 string Filter
# @stdout Compact JSON result
# @exitcode 0 The filter succeeded
# @exitcode 1 Invalid input or filter
# @exitcode 127 Neither `yq` nor `jq` is installed
# @tip Write filters in the subset both backends share: `yq` has no `def`, and spells `ascii_downcase` as `downcase`
# @see dybatpho::json_get
#######################################
function dybatpho::json_eval {
  local document filter
  dybatpho::expect_args document filter -- "$@"
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  if [[ "${json_cmd}" == "yq" ]]; then
    yq -o=json -I=0 "${filter}" <<< "${document}"
  else
    jq -c "${filter}" <<< "${document}"
  fi
}

#######################################
# @description Evaluate a filter and print the result as a bare scalar.
# Strings come back without surrounding quotes, so the result drops straight
# into a shell variable.
# @example
#   local text
#   text=$(dybatpho::json_get "${response}" '.choices[0].message.content // ""')
#
# @arg $1 string JSON document
# @arg $2 string Filter
# @stdout Filter result, unquoted for scalars
# @exitcode 0 The filter succeeded
# @exitcode 1 Invalid input or filter
# @exitcode 127 Neither `yq` nor `jq` is installed
# @see dybatpho::json_eval
#######################################
function dybatpho::json_get {
  local document filter
  dybatpho::expect_args document filter -- "$@"
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  if [[ "${json_cmd}" == "yq" ]]; then
    yq "${filter}" <<< "${document}"
  else
    jq -r "${filter}" <<< "${document}"
  fi
}

#######################################
# @description Return success when a JSON document held in a variable is valid.
# @example
#   dybatpho::json_valid "${answer}" || dybatpho::warn "The model did not return JSON"
#
# @arg $1 string Candidate document
# @exitcode 0 The document parses as JSON
# @exitcode 1 The document is not valid JSON
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_valid {
  local document
  dybatpho::expect_args document -- "$@"
  local json_cmd
  __dybatpho_json_cmd_into json_cmd
  __dybatpho_json_parses "${json_cmd}" "${document}"
}

#######################################
# @description Resolve the JSON backend into a named variable.
#   Every helper resolves the backend here rather than through `$(...)`, where a
#   missing tool reported from inside the substitution would end only the
#   subshell, and where each call cost two forks before `yq` or `jq` ran at all.
#   The answer is remembered for as long as `PATH` is unchanged: a test that
#   hides one backend, or a script that installs one, changes `PATH`, and the
#   next call looks again.
# @arg $1 string Name of the variable receiving `yq` or `jq`
# @set The named variable
# @set __DYBATPHO_JSON_CMD The backend last resolved
# @set __DYBATPHO_JSON_CMD_PATH The `PATH` it was resolved under
# @exitcode 0 A supported JSON helper command exists
# @exitcode 127 Neither `yq` nor `jq` is installed
# @internal
#######################################
function __dybatpho_json_cmd_into {
  local __dybatpho_json_cmd_var
  dybatpho::expect_args __dybatpho_json_cmd_var -- "$@"
  local -n __dybatpho_json_cmd_out="${__dybatpho_json_cmd_var}"
  if [[ -n "${__DYBATPHO_JSON_CMD-}" && "${__DYBATPHO_JSON_CMD_PATH-}" == "${PATH}" ]] \
    && dybatpho::is command "${__DYBATPHO_JSON_CMD}"; then
    __dybatpho_json_cmd_out="${__DYBATPHO_JSON_CMD}"
    return 0
  fi
  if dybatpho::is command yq; then
    __DYBATPHO_JSON_CMD=yq
  elif dybatpho::is command jq; then
    __DYBATPHO_JSON_CMD=jq
  else
    dybatpho::die "Neither yq nor jq is installed" 127
  fi
  __DYBATPHO_JSON_CMD_PATH="${PATH}"
  __dybatpho_json_cmd_out="${__DYBATPHO_JSON_CMD}"
}

#######################################
# @description Store one finished path segment, tagged with its kind.
#   A segment of digits only that was written without any escape addresses an
#   array element and is stored as `#<number>`; every other segment is an
#   object key, stored as `:<key>`.
# @arg $1 string Name of the array receiving the segment
# @arg $2 string Segment text
# @arg $3 string `true` when the segment contained an escape
# @set The named array
# @exitcode 0 The segment was stored
# @exitcode 1 The segment is empty, or an index too long to be a number
# @internal
#######################################
function __dybatpho_json_path_push {
  local -n __dybatpho_json_push_out="$1"
  local __dybatpho_json_push_segment="$2"
  [[ -n "${__dybatpho_json_push_segment}" ]] || return 1
  if [[ "$3" != true && "${__dybatpho_json_push_segment}" =~ ^[0-9]+$ ]]; then
    ((${#__dybatpho_json_push_segment} <= 18)) || return 1
    __dybatpho_json_push_out+=("#$((10#${__dybatpho_json_push_segment}))")
  else
    __dybatpho_json_push_out+=(":${__dybatpho_json_push_segment}")
  fi
}

#######################################
# @description Split a path such as `spec.ports.0.name` into tagged segments.
#   Segments are separated by `.`, and one leading `.` is accepted so a path
#   reads the way a filter would write it. A backslash makes the next character
#   literal: `\.` is a dot inside a key, `\\` a backslash, and `\0` the object
#   key `0` rather than the first array element.
# @arg $1 string Name of the array receiving the segments
# @arg $2 string Path to split
# @set The named array
# @exitcode 0 The path is valid
# @exitcode 1 The path is empty, has an empty segment, or ends in a lone `\`
# @internal
#######################################
function __dybatpho_json_path_split {
  local -n __dybatpho_json_split_out="$1"
  local __dybatpho_json_split_path="${2-}"
  __dybatpho_json_split_out=()
  [[ "${__dybatpho_json_split_path}" == .* ]] \
    && __dybatpho_json_split_path="${__dybatpho_json_split_path:1}"
  [[ -n "${__dybatpho_json_split_path}" ]] || return 1

  local __dybatpho_json_split_segment="" __dybatpho_json_split_char
  local __dybatpho_json_split_escaped=false __dybatpho_json_split_literal=false
  local __dybatpho_json_split_index
  for ((__dybatpho_json_split_index = 0;  \
  __dybatpho_json_split_index < ${#__dybatpho_json_split_path};  \
  __dybatpho_json_split_index++)); do
    __dybatpho_json_split_char="${__dybatpho_json_split_path:__dybatpho_json_split_index:1}"
    if [[ "${__dybatpho_json_split_escaped}" == true ]]; then
      __dybatpho_json_split_segment+="${__dybatpho_json_split_char}"
      __dybatpho_json_split_escaped=false
    elif [[ "${__dybatpho_json_split_char}" == $'\\' ]]; then
      __dybatpho_json_split_escaped=true
      __dybatpho_json_split_literal=true
    elif [[ "${__dybatpho_json_split_char}" == '.' ]]; then
      __dybatpho_json_path_push "$1" "${__dybatpho_json_split_segment}" \
        "${__dybatpho_json_split_literal}" || return 1
      __dybatpho_json_split_segment=""
      __dybatpho_json_split_literal=false
    else
      __dybatpho_json_split_segment+="${__dybatpho_json_split_char}"
    fi
  done
  [[ "${__dybatpho_json_split_escaped}" == false ]] || return 1
  __dybatpho_json_path_push "$1" "${__dybatpho_json_split_segment}" \
    "${__dybatpho_json_split_literal}"
}

#######################################
# @description Encode tagged path segments as a JSON array for `jq`.
# @arg $1 string Name of the variable receiving the array, such as `["a",0]`
# @arg $@ string Tagged segments from `__dybatpho_json_path_split`
# @set The named variable
# @internal
#######################################
function __dybatpho_json_path_array_into {
  local -n __dybatpho_json_array_out="$1"
  shift
  local __dybatpho_json_array_text="" __dybatpho_json_array_item __dybatpho_json_array_quoted
  for __dybatpho_json_array_item in "$@"; do
    [[ -n "${__dybatpho_json_array_text}" ]] && __dybatpho_json_array_text+=","
    if [[ "${__dybatpho_json_array_item}" == "#"* ]]; then
      __dybatpho_json_array_text+="${__dybatpho_json_array_item:1}"
    else
      __dybatpho_json_escape_into __dybatpho_json_array_quoted "${__dybatpho_json_array_item:1}"
      __dybatpho_json_array_text+="${__dybatpho_json_array_quoted}"
    fi
  done
  __dybatpho_json_array_out="[${__dybatpho_json_array_text}]"
}

#######################################
# @description Run a command and send its output to stdout or to a file.
#   The output is captured in full before anything is written, so a failing
#   backend leaves the destination untouched, and the destination may be the
#   very file the command reads.
# @arg $1 string Destination file, or empty for stdout
# @arg $@ string Command to run
# @stdout The command's output when no destination is given
# @exitcode 0 The command succeeded and its output was delivered
# @exitcode other The command's own exit code
# @internal
#######################################
function __dybatpho_json_emit {
  local output="$1"
  shift
  if [[ -z "${output}" ]]; then
    "$@"
    return
  fi
  local result
  result=$("$@") || return
  printf '%s\n' "${result}" | dybatpho::file_write_atomic "${output}"
}

#######################################
# @description Return success when text parses as a JSON value.
#   Unlike `jq -e`, this accepts `null` and `false`, which are values a caller
#   may well want to store. Blank text is refused on both backends: each reads
#   it as an empty stream and would call it valid, but it holds no value.
# @arg $1 string Backend, `yq` or `jq`
# @arg $2 string Candidate JSON text
# @exitcode 0 The text is a JSON value
# @exitcode 1 The text does not parse
# @internal
#######################################
function __dybatpho_json_parses {
  [[ "$2" == *[![:space:]]* ]] || return 1
  if [[ "$1" == yq ]]; then
    yq -o=json -I=0 -p=json '.' <<< "$2" > /dev/null 2>&1
  else
    jq empty <<< "$2" > /dev/null 2>&1
  fi
}

#######################################
# @description Shared body of `json_set` and `yaml_set`.
# @arg $1 string Public function name, for messages
# @arg $2 string `json` or `yaml`
# @arg $@ string The public function's own arguments
# @internal
#######################################
function __dybatpho_json_set {
  local caller="$1" format="$2"
  shift 2
  local typed=false
  if [[ "${1-}" == "--json" ]]; then
    typed=true
    shift
  fi
  (($# >= 3 && $# <= 4)) \
    || dybatpho::die "${caller}: Expected [--json] <input> <path> <value> [output], got $# arguments"
  local input="$1" path="$2" value="$3" output="${4-}"

  local -a segments=()
  __dybatpho_json_path_split segments "${path}" \
    || dybatpho::die "${caller}: Invalid path: '${path}'"

  local backend=yq
  if [[ "${format}" == json ]]; then
    __dybatpho_json_cmd_into backend
  else
    dybatpho::require yq
  fi
  if [[ "${typed}" == true ]]; then
    __dybatpho_json_parses "${backend}" "${value}" \
      || dybatpho::die "${caller}: Value is not valid JSON: ${value}"
  fi

  local message="Cannot set '${path}': it passes through a value that is not an object or array of the matching kind"

  if [[ "${backend}" == jq ]]; then
    local path_array
    __dybatpho_json_path_array_into path_array "${segments[@]}"
    local value_flag=--arg
    [[ "${typed}" == true ]] && value_flag=--argjson
    # shellcheck disable=SC2016 # `$path`, `$value` and `$message` are jq variables
    __dybatpho_json_emit "${output}" jq --argjson path "${path_array}" \
      "${value_flag}" value "${value}" --arg message "${message}" \
      'try setpath($path; $value) catch error($message)' "${input}"
    return
  fi

  # Each segment reaches yq through its own environment variable, so nothing
  # the caller wrote is ever parsed as part of the expression. The guards make
  # yq refuse what jq refuses: yq would otherwise ignore an assignment through
  # a scalar, and store a numeric segment as a key of an object.
  local -a environment=("__dybatpho_json_error=${message}" "__dybatpho_json_value=${value}")
  #
  # The guards read each parent as `.[a] | .[b]` and match its tag with one
  # regular expression: on a key that is missing, yq answers `!=`, `and` and
  # `or` wrongly, and a chained `.[a][b]` compares differently from a pipe.
  local filter="" parent="." target="" accessor kind index=0 segment
  for segment in "${segments[@]}"; do
    environment+=("__dybatpho_json_s${index}=${segment:1}")
    if [[ "${segment}" == "#"* ]]; then
      kind=seq
      accessor="[env(__dybatpho_json_s${index})]"
    else
      kind=map
      accessor="[strenv(__dybatpho_json_s${index})]"
    fi
    filter+="with(select(${parent} | tag | test(\"^!!(${kind}|null)\$\") | not);"
    filter+=" error(strenv(__dybatpho_json_error))) | "
    if [[ "${parent}" == "." ]]; then
      parent=".${accessor}"
    else
      parent+=" | .${accessor}"
    fi
    target+="${accessor}"
    index=$((index + 1))
  done
  parent=".${target}"
  if [[ "${typed}" == true ]]; then
    filter+="${parent} = (strenv(__dybatpho_json_value) | from_json)"
  else
    filter+="${parent} = strenv(__dybatpho_json_value)"
  fi
  __dybatpho_json_emit "${output}" env "${environment[@]}" \
    yq eval "-o=${format}" "${filter}" "${input}"
}

#######################################
# @description Shared body of `json_del` and `yaml_del`.
# @arg $1 string Public function name, for messages
# @arg $2 string `json` or `yaml`
# @arg $@ string The public function's own arguments
# @internal
#######################################
function __dybatpho_json_del {
  local caller="$1" format="$2"
  shift 2
  (($# >= 2 && $# <= 3)) \
    || dybatpho::die "${caller}: Expected <input> <path> [output], got $# arguments"
  local input="$1" path="$2" output="${3-}"

  local -a segments=()
  __dybatpho_json_path_split segments "${path}" \
    || dybatpho::die "${caller}: Invalid path: '${path}'"

  local backend=yq
  if [[ "${format}" == json ]]; then
    __dybatpho_json_cmd_into backend
  else
    dybatpho::require yq
  fi

  if [[ "${backend}" == jq ]]; then
    local path_array
    __dybatpho_json_path_array_into path_array "${segments[@]}"
    # A path that runs through a scalar, or indexes the wrong kind of
    # container, names nothing, and deleting nothing is not an error.
    # shellcheck disable=SC2016 # `$path` and `$document` are jq variables
    __dybatpho_json_emit "${output}" jq --argjson path "${path_array}" \
      '. as $document | try delpaths([$path]) catch $document' "${input}"
    return
  fi

  # Walking `.[] | select(key == ...)` rather than indexing keeps yq from
  # padding an array with nulls up to an index that was never there.
  local -a environment=()
  local selector="" index=0 segment
  for segment in "${segments[@]}"; do
    environment+=("__dybatpho_json_s${index}=${segment:1}")
    [[ -n "${selector}" ]] && selector+=" | "
    if [[ "${segment}" == "#"* ]]; then
      selector+=".[] | select(key == env(__dybatpho_json_s${index}))"
    else
      selector+=".[] | select(key == strenv(__dybatpho_json_s${index}))"
    fi
    index=$((index + 1))
  done
  __dybatpho_json_emit "${output}" env "${environment[@]}" \
    yq eval "-o=${format}" "del(${selector})" "${input}"
}

#######################################
# @description Shared body of `json_merge` and `yaml_merge`.
# @arg $1 string Public function name, for messages
# @arg $2 string `json` or `yaml`
# @arg $@ string The public function's own arguments
# @internal
#######################################
function __dybatpho_json_merge {
  local caller="$1" format="$2"
  shift 2
  (($# >= 2 && $# <= 3)) \
    || dybatpho::die "${caller}: Expected <base> <overlay> [output], got $# arguments"
  local base="$1" overlay="$2" output="${3-}"
  local message="Cannot merge: both documents must be objects"

  local backend=yq
  if [[ "${format}" == json ]]; then
    __dybatpho_json_cmd_into backend
  else
    dybatpho::require yq
  fi

  if [[ "${backend}" == jq ]]; then
    # shellcheck disable=SC2016 # `$message` is a jq variable
    __dybatpho_json_emit "${output}" jq -s --arg message "${message}" \
      'if length == 2 and (.[0] | type) == "object" and (.[1] | type) == "object"
       then .[0] * .[1] else error($message) end' "${base}" "${overlay}"
    return
  fi

  __dybatpho_json_emit "${output}" env "__dybatpho_json_error=${message}" \
    yq eval-all "-o=${format}" \
    '[.] | with(select((length == 2 and (.[0] | tag) == "!!map" and (.[1] | tag) == "!!map") | not);
     error(strenv(__dybatpho_json_error))) | .[0] * .[1]' "${base}" "${overlay}"
}

#######################################
# @description Set the value at a path in a JSON document.
#   The path is a list of keys separated by `.`, such as `spec.ports.0.name`,
#   where a segment of digits indexes an array. Missing objects and arrays on
#   the way are created. The value is stored as a string unless `--json` says
#   it is a JSON document, which is how a number, a boolean, `null`, an array,
#   or an object is written.
# @example
#   dybatpho::json_set package.json version 2.0.0 package.json
#
# @example
#   dybatpho::json_set --json config.json server.ports '[80,443]'
#
# @arg $1 string Optional `--json`: parse the value as JSON instead of storing a string
# @arg $2 string JSON file path or `-` for stdin
# @arg $3 string Path to set; `\.` is a dot inside a key, and `\0` the key `0`
# @arg $4 string Value to store
# @arg $5 string Optional output file path, which may be the input file
# @stdout Pretty JSON when no output file is provided
# @exitcode 0 The value was set
# @exitcode 1 Invalid arguments, path, or `--json` value
# @exitcode other The backend's exit code when the input is invalid or the path runs through a scalar
# @exitcode 127 Neither `yq` nor `jq` is installed
# @note The path and the value reach the backend as arguments, never as part of
#   the expression, so neither needs escaping
# @tip The output file is written atomically after the whole result is known, so a failure leaves it untouched
#######################################
function dybatpho::json_set {
  __dybatpho_json_set "${FUNCNAME[0]}" json "$@"
}

#######################################
# @description Remove the value at a path from a JSON document.
#   Paths use the same syntax as `dybatpho::json_set`. Deleting a path that does
#   not exist leaves the document unchanged, and deleting an array element
#   shifts the ones after it.
# @example
#   dybatpho::json_del package.json scripts.prepublish package.json
#
# @arg $1 string JSON file path or `-` for stdin
# @arg $2 string Path to remove
# @arg $3 string Optional output file path, which may be the input file
# @stdout Pretty JSON when no output file is provided
# @exitcode 0 The path was removed or was already absent
# @exitcode 1 Invalid arguments or path
# @exitcode other The backend's exit code when the input is invalid
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_del {
  __dybatpho_json_del "${FUNCNAME[0]}" json "$@"
}

#######################################
# @description Deep-merge two JSON objects, the overlay winning.
#   Objects present in both are merged key by key; any other value, arrays
#   included, is replaced by the overlay's. Both documents must be objects.
# @example
#   dybatpho::json_merge defaults.json local.json > effective.json
#
# @arg $1 string Base JSON file path, or `-` for stdin
# @arg $2 string Overlay JSON file path, or `-` for stdin
# @arg $3 string Optional output file path, which may be either input
# @stdout Pretty JSON when no output file is provided
# @exitcode 0 The documents were merged
# @exitcode 1 Invalid arguments
# @exitcode other The backend's exit code when a document is not an object or is invalid
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_merge {
  __dybatpho_json_merge "${FUNCNAME[0]}" json "$@"
}

#######################################
# @description Set the value at a path in a YAML document.
#   Paths and `--json` work as in `dybatpho::json_set`. Comments and the rest of
#   the document's layout are kept as `yq` keeps them.
# @example
#   dybatpho::yaml_set compose.yaml services.app.image 'app:2.0' compose.yaml
#
# @example
#   dybatpho::yaml_set --json values.yaml replicas 3
#
# @arg $1 string Optional `--json`: parse the value as JSON instead of storing a string
# @arg $2 string YAML file path or `-` for stdin
# @arg $3 string Path to set
# @arg $4 string Value to store
# @arg $5 string Optional output file path, which may be the input file
# @stdout YAML when no output file is provided
# @exitcode 0 The value was set
# @exitcode 1 Invalid arguments, path, or `--json` value
# @exitcode other The backend's exit code when the input is invalid or the path runs through a scalar
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_set {
  __dybatpho_json_set "${FUNCNAME[0]}" yaml "$@"
}

#######################################
# @description Remove the value at a path from a YAML document.
#   Paths work as in `dybatpho::json_set`, and an absent path is not an error.
# @example
#   dybatpho::yaml_del compose.yaml services.debug compose.yaml
#
# @arg $1 string YAML file path or `-` for stdin
# @arg $2 string Path to remove
# @arg $3 string Optional output file path, which may be the input file
# @stdout YAML when no output file is provided
# @exitcode 0 The path was removed or was already absent
# @exitcode 1 Invalid arguments or path
# @exitcode other The backend's exit code when the input is invalid
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_del {
  __dybatpho_json_del "${FUNCNAME[0]}" yaml "$@"
}

#######################################
# @description Deep-merge two YAML mappings, the overlay winning.
#   Merging follows `dybatpho::json_merge`: mappings merge key by key, and
#   every other value is replaced by the overlay's.
# @example
#   dybatpho::yaml_merge values.yaml values-prod.yaml > rendered.yaml
#
# @arg $1 string Base YAML file path, or `-` for stdin
# @arg $2 string Overlay YAML file path, or `-` for stdin
# @arg $3 string Optional output file path, which may be either input
# @stdout YAML when no output file is provided
# @exitcode 0 The documents were merged
# @exitcode 1 Invalid arguments
# @exitcode other The backend's exit code when a document is not a mapping or is invalid
# @exitcode 127 `yq` is not installed
#######################################
function dybatpho::yaml_merge {
  __dybatpho_json_merge "${FUNCNAME[0]}" yaml "$@"
}
