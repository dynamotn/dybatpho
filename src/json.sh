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
