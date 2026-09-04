#!/usr/bin/env bash
# @file config.sh
# @brief Utilities for loading configuration from files and environment variables.
# @description
#   Configuration files are loaded in the order provided, so later files
#   override earlier files. Environment variables loaded with
#   `dybatpho::config_env` are applied last.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

declare -gA DYBATPHO_CONFIG=()
declare -gA DYBATPHO_CONFIG_SCHEMA=()

function __dybatpho_config_set {
  local key value
  dybatpho::expect_args key value -- "$@"
  [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
    || dybatpho::die "Invalid configuration key: ${key}"
  DYBATPHO_CONFIG["${key}"]="${value}"
}

function __dybatpho_config_load_dotenv {
  local file line key value
  dybatpho::expect_args file -- "$@"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line:0:1}" == "#" ]] && continue
    [[ "${line}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] \
      || dybatpho::die "Invalid dotenv entry in ${file}: ${line}"
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "${value}" == \"*\" && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
      printf -v value '%b' "${value}"
    elif [[ "${value}" == \'*\' && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    else
      value="${value%%[[:space:]]#*}"
      value="${value%"${value##*[![:space:]]}"}"
    fi
    __dybatpho_config_set "${key}" "${value}"
  done < "${file}" # kcov(skip)
}

function __dybatpho_config_load_structured {
  local file format key value entries
  format="${1}"
  file="${2}"
  if [[ "${format}" == json ]]; then
    dybatpho::require jq
    entries=$(jq -r 'if type != "object" then error("root must be an object") else to_entries[] | [.key, (.value | tostring)] | @tsv end' "${file}") \
      || dybatpho::die "Invalid JSON configuration: ${file}"
  else
    dybatpho::require yq
    entries=$(yq -r 'if type != "!!map" then error("root must be a mapping") else to_entries[] | [.key, (.value | tostring)] | @tsv end' "${file}") \
      || dybatpho::die "Invalid YAML configuration: ${file}"
  fi
  if [[ -n "${entries}" ]]; then
    while IFS=$'\t' read -r key value; do
      __dybatpho_config_set "${key}" "${value}"
    done <<< "${entries}"
  fi
}

#######################################
# @description Load one or more configuration files.
# @arg $@ string Files in dotenv, JSON, or YAML format, in increasing precedence order
# @exitcode 1 A file is missing or has invalid configuration
#######################################
function dybatpho::config_load {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one configuration file"
  local file extension
  for file in "$@"; do
    dybatpho::is file "${file}" || dybatpho::die "Configuration file not found: ${file}"
    extension="${file##*.}"
    case "${extension,,}" in
      env | dotenv) __dybatpho_config_load_dotenv "${file}" ;;
      json) __dybatpho_config_load_structured json "${file}" ;;
      yaml | yml) __dybatpho_config_load_structured yaml "${file}" ;;
      *) dybatpho::die "Unsupported configuration format: ${file}" ;; # kcov(skip)
    esac
  done
}

#######################################
# @description Load environment variables after an optional prefix.
# @arg $1 string Optional prefix, such as `APP_`
# @tip Environment variables override values loaded from configuration files.
#######################################
function dybatpho::config_env {
  local prefix="${1-}" variable key
  while IFS= read -r variable; do
    [[ -n "${prefix}" && "${variable}" != "${prefix}"* ]] && continue
    key="${variable#"${prefix}"}"
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
    [[ -v "${variable}" ]] || continue
    __dybatpho_config_set "${key}" "${!variable}"
  done < <(compgen -v) # kcov(skip)
}

#######################################
# @description Print a configuration value.
# @arg $1 string Configuration key
# @arg $2 string Optional default value
# @stdout Configuration value
# @exitcode 1 Key is missing and no default was supplied
#######################################
function dybatpho::config_get {
  local key
  dybatpho::expect_args key -- "$@"
  [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
    || dybatpho::die "Invalid configuration key: ${key}"
  if [[ -v "DYBATPHO_CONFIG[${key}]" ]]; then
    printf '%s\n' "${DYBATPHO_CONFIG[${key}]}"
  elif (($# > 1)); then
    printf '%s\n' "$2"
  else
    return 1
  fi
}

#######################################
# @description Require configuration keys to be present.
# @arg $@ string Configuration keys
# @exitcode 1 At least one key is missing
#######################################
function dybatpho::config_require {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one key"
  local key
  for key in "$@"; do
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
      || dybatpho::die "Invalid configuration key: ${key}"
    [[ -v "DYBATPHO_CONFIG[${key}]" ]] \
      || dybatpho::die "Required configuration is missing: ${key}"
  done
}

#######################################
# @description Export loaded values as shell variables.
# @arg $1 string Optional prefix for exported variable names
# @exitcode 1 A key cannot be represented as a shell variable
#######################################
function dybatpho::config_export {
  local prefix="${1-}" key
  [[ -z "${prefix}" || "${prefix}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "Invalid configuration variable prefix: ${prefix}"
  for key in "${!DYBATPHO_CONFIG[@]}"; do
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "Cannot export configuration key as variable: ${key}"
    export "${prefix}${key}=${DYBATPHO_CONFIG[${key}]}"
  done
}

#######################################
# @description Declare validation rules for a configuration key.
# @arg $1 string Configuration key
# @arg $2 string Type: string, int, bool, url, or enum
# @arg $@ string Rules: required:true, default:value, min:number, max:number, choices:a,b
# @tip Call `dybatpho::config_validate` after all files and environment overlays are loaded.
#######################################
function dybatpho::config_schema {
  local key type rule name value
  dybatpho::expect_args key type -- "$@"
  [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
    || dybatpho::die "Invalid configuration key: ${key}"
  case "${type}" in
    string|int|bool|url|enum) ;; # kcov(skip)
    *) dybatpho::die "Unsupported configuration type: ${type}" ;; # kcov(skip)
  esac
  DYBATPHO_CONFIG_SCHEMA["${key}.type"]="${type}"
  shift 2
  for rule in "$@"; do
    [[ "${rule}" == *:* ]] || dybatpho::die "Invalid configuration schema rule: ${rule}"
    name="${rule%%:*}"
    value="${rule#*:}"
    case "${name}" in
      required|default|min|max|choices) ;; # kcov(skip)
      *) dybatpho::die "Unsupported configuration schema rule: ${name}" ;; # kcov(skip)
    esac
    DYBATPHO_CONFIG_SCHEMA["${key}.${name}"]="${value}"
  done
}

function __dybatpho_config_schema_error {
  # kcov(disabled) - this helper always terminates the shell
  local key reason
  dybatpho::expect_args key reason -- "$@"
  dybatpho::die "Invalid configuration \`${key}\`: ${reason}"
  # kcov(enabled)
}

#######################################
# @description Validate configured values against all declared schemas.
# @exitcode 1 A required key is missing or a value violates its schema
#######################################
function dybatpho::config_validate {
  local schema_key key type value required min max choices choice choice_value
  for schema_key in "${!DYBATPHO_CONFIG_SCHEMA[@]}"; do
    [[ "${schema_key}" == *.type ]] || continue
    key="${schema_key%.type}"
    type="${DYBATPHO_CONFIG_SCHEMA[${schema_key}]}"
    if [[ ! -v "DYBATPHO_CONFIG[${key}]" ]]; then
      required="${DYBATPHO_CONFIG_SCHEMA[${key}.required]-false}"
      if dybatpho::is true "${required}"; then
        __dybatpho_config_schema_error "${key}" "required value is missing" # kcov(skip)
      elif [[ -v "DYBATPHO_CONFIG_SCHEMA[${key}.default]" ]]; then
        DYBATPHO_CONFIG["${key}"]="${DYBATPHO_CONFIG_SCHEMA[${key}.default]}"
      else
        continue
      fi
    fi
    value="${DYBATPHO_CONFIG[${key}]}"
    case "${type}" in
      int)
        [[ "${value}" =~ ^-?[0-9]+$ ]] || __dybatpho_config_schema_error "${key}" "expected an integer"
        ;;
      bool)
        [[ "${value,,}" =~ ^(true|false|yes|no|1|0)$ ]] \
          || __dybatpho_config_schema_error "${key}" "expected a boolean"
        ;;
      url)
        [[ "${value}" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+$ ]] \
          || __dybatpho_config_schema_error "${key}" "expected a URL"
        ;;
      enum)
        choices="${DYBATPHO_CONFIG_SCHEMA[${key}.choices]-}"
        choice=false
        IFS=',' read -r -a __dybatpho_config_choices <<< "${choices}"
        for choice_value in "${__dybatpho_config_choices[@]}"; do
          [[ "${value}" == "${choice_value}" ]] && choice=true && break
        done
        [[ "${choice}" == true ]] \
          || __dybatpho_config_schema_error "${key}" "expected one of: ${choices}"
        ;;
    esac
    min="${DYBATPHO_CONFIG_SCHEMA[${key}.min]-}"
    max="${DYBATPHO_CONFIG_SCHEMA[${key}.max]-}"
    if [[ -n "${min}" || -n "${max}" ]]; then
      [[ -z "${min}" || "${min}" =~ ^-?[0-9]+$ ]] \
        || __dybatpho_config_schema_error "${key}" "minimum must be an integer"
      [[ -z "${max}" || "${max}" =~ ^-?[0-9]+$ ]] \
        || __dybatpho_config_schema_error "${key}" "maximum must be an integer"
      [[ "${value}" =~ ^-?[0-9]+$ ]] || __dybatpho_config_schema_error "${key}" "range requires an integer"
      [[ -z "${min}" || "${value}" -ge "${min}" ]] \
        || __dybatpho_config_schema_error "${key}" "must be at least ${min}"
      [[ -z "${max}" || "${value}" -le "${max}" ]] \
        || __dybatpho_config_schema_error "${key}" "must be at most ${max}"
    fi
  done
}
