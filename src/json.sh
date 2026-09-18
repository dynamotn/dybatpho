#!/usr/bin/env bash
# @file json.sh
# @brief Utilities for working with JSON and YAML data
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
# @description Resolve the preferred command for JSON helpers.
# @stdout `yq` or `jq`
# @exitcode 0 A supported JSON helper command exists
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function __dybatpho_json_cmd {
  local command_name
  command_name=$(dybatpho::coalesce_cmd yq jq) || dybatpho::die "Neither yq nor jq is installed" 127
  printf '%s\n' "${command_name}"
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
  json_cmd=$(__dybatpho_json_cmd)
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
  json_cmd=$(__dybatpho_json_cmd)
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
  json_cmd=$(__dybatpho_json_cmd)
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
# @exitcode 127 Neither `yq` nor `jq` is installed
#######################################
function dybatpho::json_string {
  local text
  dybatpho::expect_args text -- "$@"
  local json_cmd
  json_cmd=$(__dybatpho_json_cmd)
  if [[ "${json_cmd}" == "yq" ]]; then
    __dybatpho_json_text="${text}" yq -n -o=json -I=0 'strenv(__dybatpho_json_text)'
  else
    printf '%s' "${text}" | jq -Rs .
  fi
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
  local json_cmd
  json_cmd=$(__dybatpho_json_cmd)

  local document='{}' name value raw
  while (($# >= 2)); do
    name="$1"
    value="$2"
    shift 2
    raw=false
    if [[ "${name}" == *:json ]]; then
      raw=true
      name="${name%:json}"
    fi
    if [[ "${json_cmd}" == "yq" ]]; then
      if [[ "${raw}" == true ]]; then
        document=$(__dybatpho_json_name="${name}" __dybatpho_json_value="${value}" \
          yq -o=json -I=0 '.[strenv(__dybatpho_json_name)] = (strenv(__dybatpho_json_value) | from_json)' <<< "${document}")
      else
        document=$(__dybatpho_json_name="${name}" __dybatpho_json_value="${value}" \
          yq -o=json -I=0 '.[strenv(__dybatpho_json_name)] = strenv(__dybatpho_json_value)' <<< "${document}")
      fi
    else
      if [[ "${raw}" == true ]]; then
        document=$(jq -c --arg name "${name}" --argjson value "${value}" \
          '.[$name] = $value' <<< "${document}")
      else
        document=$(jq -c --arg name "${name}" --arg value "${value}" \
          '.[$name] = $value' <<< "${document}")
      fi
    fi
  done
  printf '%s\n' "${document}"
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
  json_cmd=$(__dybatpho_json_cmd)
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
  json_cmd=$(__dybatpho_json_cmd)
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
  json_cmd=$(__dybatpho_json_cmd)
  if [[ "${json_cmd}" == "yq" ]]; then
    yq -o=json -I=0 -p=json '.' <<< "${document}" > /dev/null 2>&1
  else
    jq -e . <<< "${document}" > /dev/null 2>&1
  fi
}
