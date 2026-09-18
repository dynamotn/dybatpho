#!/usr/bin/env bash
# @file config.sh
# @brief Utilities for loading configuration from files and environment variables.
# @description
#   Configuration files are loaded in the order provided, so later files
#   override earlier files. Environment variables loaded with
#   `dybatpho::config_env` are applied last.
#
#   Keys can also be given a typed schema with `dybatpho::config_schema`.
#   `dybatpho::config_validate` then applies declared defaults, enforces
#   required keys, types, ranges, and enum choices, and reports every
#   violation together with the key that caused it. The same schema renders a
#   configuration reference through `dybatpho::config_doc`.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

declare -gA DYBATPHO_CONFIG=()
declare -gA DYBATPHO_CONFIG_SCHEMA=()
declare -ga DYBATPHO_CONFIG_SCHEMA_KEYS=()
declare -ga DYBATPHO_CONFIG_ERRORS=()

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
# @description Normalize a schema type name to its canonical form.
# @arg $1 string Declared type
# @stdout Canonical type: string, int, bool, url, or enum
# @exitcode 1 The type is not supported
#######################################
function __dybatpho_config_schema_type {
  local input="${1,,}"
  case "${input}" in
    string) printf 'string' ;;
    int | integer) printf 'int' ;;
    bool | boolean) printf 'bool' ;;
    url) printf 'url' ;;
    enum) printf 'enum' ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Drop every attribute previously declared for a key.
# @arg $1 string Configuration key
#######################################
function __dybatpho_config_schema_clear {
  local key attribute
  dybatpho::expect_args key -- "$@"
  for attribute in "${!DYBATPHO_CONFIG_SCHEMA[@]}"; do
    if [[ "${attribute}" == "${key}."* ]]; then
      unset "DYBATPHO_CONFIG_SCHEMA[${attribute}]"
    fi
  done
  return 0
}

#######################################
# @description Print a schema attribute, or a fallback when it is not declared.
# @arg $1 string Configuration key
# @arg $2 string Attribute name
# @arg $3 string Optional fallback value
# @stdout Attribute value
#######################################
function __dybatpho_config_schema_attr {
  local key attribute
  dybatpho::expect_args key attribute -- "$@"
  printf '%s' "${DYBATPHO_CONFIG_SCHEMA[${key}.${attribute}]-${3-}}"
}

#######################################
# @description Describe the range and choice constraints declared for a key.
# @arg $1 string Configuration key
# @stdout Human readable constraints, or an empty string when none are declared
#######################################
function __dybatpho_config_schema_constraints {
  local key type min max choices unit
  dybatpho::expect_args key -- "$@"
  type="$(__dybatpho_config_schema_attr "${key}" type string)"
  min="$(__dybatpho_config_schema_attr "${key}" min)"
  max="$(__dybatpho_config_schema_attr "${key}" max)"
  choices="$(__dybatpho_config_schema_attr "${key}" choices)"
  if [[ "${type}" == enum ]]; then
    printf 'one of: %s' "${choices//,/, }"
    return 0
  fi
  if [[ "${type}" == int ]]; then
    unit=""
  else
    unit=" characters"
  fi
  if [[ -n "${min}" && -n "${max}" ]]; then
    printf '%s..%s%s' "${min}" "${max}" "${unit}"
  elif [[ -n "${min}" ]]; then
    printf '>= %s%s' "${min}" "${unit}"
  elif [[ -n "${max}" ]]; then
    printf '<= %s%s' "${max}" "${unit}"
  fi
  return 0
}

#######################################
# @description Declare validation rules for a configuration key.
# @arg $1 string Configuration key
# @arg $2 string Type: `string`, `int` (`integer`), `bool` (`boolean`), `url`, or `enum`
# @arg $@ string Rules: `required:true`, `default:value`, `min:number`, `max:number`, `choices:a,b`, `description:text`
# @set DYBATPHO_CONFIG_SCHEMA Declared attributes, keyed by `<key>.<attribute>`
# @set DYBATPHO_CONFIG_SCHEMA_KEYS Declaration order used by validation and documentation
# @tip Call `dybatpho::config_validate` after all files and environment overlays are loaded.
# @tip Declaring the same key twice replaces its previous rules instead of merging them.
# @exitcode 1 The key, type, or a rule is invalid
#######################################
function dybatpho::config_schema {
  local key declared_type type rule name value known
  dybatpho::expect_args key declared_type -- "$@"
  [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
    || dybatpho::die "Invalid configuration key: ${key}"
  type="$(__dybatpho_config_schema_type "${declared_type}")" \
    || dybatpho::die "Unsupported configuration type: ${declared_type}"
  __dybatpho_config_schema_clear "${key}"
  DYBATPHO_CONFIG_SCHEMA["${key}.type"]="${type}"
  shift 2
  for rule in "$@"; do
    [[ "${rule}" == *:* ]] || dybatpho::die "Invalid configuration schema rule: ${rule}"
    name="${rule%%:*}"
    value="${rule#*:}"
    case "${name}" in
      required)
        dybatpho::is true "${value}" || dybatpho::is false "${value}" \
          || dybatpho::die "Invalid \`required\` rule for ${key}: ${value}"
        ;;
      min | max)
        [[ "${value}" =~ ^-?[0-9]+$ ]] \
          || dybatpho::die "Invalid \`${name}\` rule for ${key}: ${value}"
        ;;
      choices)
        [[ -n "${value}" ]] || dybatpho::die "Empty \`choices\` rule for ${key}"
        ;;
      default | description) ;; # kcov(skip)
      *) dybatpho::die "Unsupported configuration schema rule: ${name}" ;; # kcov(skip)
    esac
    DYBATPHO_CONFIG_SCHEMA["${key}.${name}"]="${value}"
  done
  if [[ "${type}" == enum && -z "$(__dybatpho_config_schema_attr "${key}" choices)" ]]; then
    dybatpho::die "Configuration schema for ${key} requires \`choices\`"
  fi
  known=false
  for name in ${DYBATPHO_CONFIG_SCHEMA_KEYS[@]+"${DYBATPHO_CONFIG_SCHEMA_KEYS[@]}"}; do
    if [[ "${name}" == "${key}" ]]; then
      known=true
      break
    fi
  done
  [[ "${known}" == true ]] || DYBATPHO_CONFIG_SCHEMA_KEYS+=("${key}")
}

#######################################
# @description Forget every declared configuration schema.
# @noargs
# @set DYBATPHO_CONFIG_SCHEMA Emptied
# @set DYBATPHO_CONFIG_SCHEMA_KEYS Emptied
#######################################
function dybatpho::config_schema_reset {
  DYBATPHO_CONFIG_SCHEMA=()
  DYBATPHO_CONFIG_SCHEMA_KEYS=()
}

#######################################
# @description Record a validation failure for a configuration key.
# @arg $1 string Configuration key
# @arg $2 string Reason describing the violation
# @set DYBATPHO_CONFIG_ERRORS Appends the formatted message
#######################################
function __dybatpho_config_schema_error {
  local key reason
  dybatpho::expect_args key reason -- "$@"
  DYBATPHO_CONFIG_ERRORS+=("Invalid configuration \`${key}\`: ${reason}")
}

#######################################
# @description Validate a single value against the type declared for its key.
# @arg $1 string Configuration key
# @arg $2 string Effective value
# @set DYBATPHO_CONFIG_ERRORS Appends one message per violation
#######################################
function __dybatpho_config_schema_check {
  local key value type choices matched choice min max length subject
  dybatpho::expect_args key value -- "$@"
  type="$(__dybatpho_config_schema_attr "${key}" type string)"
  case "${type}" in
    int)
      if [[ ! "${value}" =~ ^-?[0-9]+$ ]]; then
        __dybatpho_config_schema_error "${key}" "expected an integer, got \`${value}\`"
        return 0
      fi
      ;;
    bool)
      if [[ ! "${value,,}" =~ ^(true|false|yes|no|on|off|1|0)$ ]]; then
        __dybatpho_config_schema_error "${key}" "expected a boolean, got \`${value}\`"
        return 0
      fi
      ;;
    url)
      if [[ ! "${value}" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+$ ]]; then
        __dybatpho_config_schema_error "${key}" "expected a URL, got \`${value}\`"
        return 0
      fi
      ;;
    enum)
      choices="$(__dybatpho_config_schema_attr "${key}" choices)"
      matched=false
      local -a choice_list=()
      IFS=',' read -r -a choice_list <<< "${choices}"
      for choice in ${choice_list[@]+"${choice_list[@]}"}; do
        if [[ "${value}" == "${choice}" ]]; then
          matched=true
          break
        fi
      done
      if [[ "${matched}" != true ]]; then
        __dybatpho_config_schema_error "${key}" "expected one of: ${choices}, got \`${value}\`"
        return 0
      fi
      ;;
  esac

  min="$(__dybatpho_config_schema_attr "${key}" min)"
  max="$(__dybatpho_config_schema_attr "${key}" max)"
  if [[ -z "${min}" && -z "${max}" ]]; then
    return 0
  fi
  if [[ "${type}" == int ]]; then
    length="${value}"
    subject=""
  else
    length="${#value}"
    subject=" characters"
  fi
  if [[ -n "${min}" ]] && ((length < min)); then
    __dybatpho_config_schema_error "${key}" "must be at least ${min}${subject}"
  fi
  if [[ -n "${max}" ]] && ((length > max)); then
    __dybatpho_config_schema_error "${key}" "must be at most ${max}${subject}"
  fi
  return 0
}

#######################################
# @description Validate configured values against all declared schemas.
#   Missing optional keys take their declared default, and every violation is
#   reported with the key that caused it.
# @noargs
# @set DYBATPHO_CONFIG Applies declared defaults for missing keys
# @set DYBATPHO_CONFIG_ERRORS One message per violation, in declaration order
# @exitcode 1 A required key is missing or a value violates its schema
#######################################
function dybatpho::config_validate {
  local key required
  DYBATPHO_CONFIG_ERRORS=()
  for key in ${DYBATPHO_CONFIG_SCHEMA_KEYS[@]+"${DYBATPHO_CONFIG_SCHEMA_KEYS[@]}"}; do
    if [[ ! -v "DYBATPHO_CONFIG[${key}]" ]]; then
      if [[ -v "DYBATPHO_CONFIG_SCHEMA[${key}.default]" ]]; then
        DYBATPHO_CONFIG["${key}"]="${DYBATPHO_CONFIG_SCHEMA[${key}.default]}"
      else
        required="$(__dybatpho_config_schema_attr "${key}" required false)"
        if dybatpho::is true "${required}"; then
          __dybatpho_config_schema_error "${key}" "required value is missing"
        fi
        continue
      fi
    fi
    __dybatpho_config_schema_check "${key}" "${DYBATPHO_CONFIG[${key}]}"
  done
  if ((${#DYBATPHO_CONFIG_ERRORS[@]} == 0)); then
    return 0
  fi
  local report
  printf -v report '%s\n' "${DYBATPHO_CONFIG_ERRORS[@]}"
  dybatpho::die "${report%$'\n'}" # kcov(skip)
}

#######################################
# @description Render one Markdown table cell, escaping pipes and marking empties.
# @arg $1 string Cell text
# @arg $2 string Optional `code` to wrap a non-empty cell in backticks
# @stdout Markdown cell text, or `-` when the value is empty
#######################################
function __dybatpho_config_doc_cell {
  local value="${1-}" style="${2-}"
  if [[ -z "${value}" ]]; then
    printf -- '-'
    return 0
  fi
  value="${value//|/\\|}"
  if [[ "${style}" == code ]]; then
    printf '%s%s%s' '`' "${value}" '`'
  else
    printf '%s' "${value}"
  fi
}

#######################################
# @description Render one JSON value, emitting `null` for an undeclared attribute.
# @arg $1 string Attribute value
# @arg $2 string Optional `declared` to emit an empty string instead of `null`
# @stdout Quoted JSON string, or `null`
#######################################
function __dybatpho_config_doc_json_value {
  local value="${1-}" declared="${2-}"
  if [[ -z "${value}" && "${declared}" != declared ]]; then
    printf 'null'
    return 0
  fi
  printf '"%s"' "$(__dybatpho_log_json_escape "${value}")"
}

#######################################
# @description Render documentation for every declared configuration key.
# @arg $1 string Optional format: `markdown` (default), `text`, or `json`
# @arg $2 string Optional title used by the `markdown` and `text` formats
# @stdout Configuration reference in the requested format
# @tip Pipe the Markdown output into a `CONFIGURATION.md` file to keep docs in sync with the schema.
# @exitcode 1 The format is not supported
#######################################
function dybatpho::config_doc {
  local format="${1:-markdown}" title="${2:-Configuration}"
  local key type required default constraints description separator
  case "${format}" in
    markdown | text | json) ;; # kcov(skip)
    *) dybatpho::die "Unsupported configuration documentation format: ${format}" ;; # kcov(skip)
  esac

  case "${format}" in
    markdown)
      printf '# %s\n\n' "${title}"
      printf '| Key | Type | Required | Default | Constraints | Description |\n'
      printf '| --- | --- | --- | --- | --- | --- |\n'
      ;;
    text) printf '%s\n\n' "${title}" ;;
    json) printf '[' ;;
  esac

  separator=""
  for key in ${DYBATPHO_CONFIG_SCHEMA_KEYS[@]+"${DYBATPHO_CONFIG_SCHEMA_KEYS[@]}"}; do
    type="$(__dybatpho_config_schema_attr "${key}" type string)"
    default="$(__dybatpho_config_schema_attr "${key}" default)"
    description="$(__dybatpho_config_schema_attr "${key}" description)"
    constraints="$(__dybatpho_config_schema_constraints "${key}")"
    if dybatpho::is true "$(__dybatpho_config_schema_attr "${key}" required false)"; then
      required=true
    else
      required=false
    fi
    case "${format}" in
      markdown)
        printf '| %s | %s | %s | %s | %s | %s |\n' \
          "$(__dybatpho_config_doc_cell "${key}" code)" \
          "${type}" "${required}" \
          "$(__dybatpho_config_doc_cell "${default}" code)" \
          "$(__dybatpho_config_doc_cell "${constraints}")" \
          "$(__dybatpho_config_doc_cell "${description}")"
        ;;
      text)
        printf '%s\n  type: %s\n  required: %s\n' "${key}" "${type}" "${required}"
        [[ -n "${default}" ]] && printf '  default: %s\n' "${default}" || true
        [[ -n "${constraints}" ]] && printf '  constraints: %s\n' "${constraints}" || true
        [[ -n "${description}" ]] && printf '  description: %s\n' "${description}" || true
        printf '\n'
        ;;
      json)
        local declared=""
        [[ -v "DYBATPHO_CONFIG_SCHEMA[${key}.default]" ]] && declared="declared" || true
        printf '%s{"key":"%s","type":"%s","required":%s,"default":%s,"constraints":%s,"description":%s}' \
          "${separator}" \
          "$(__dybatpho_log_json_escape "${key}")" "${type}" "${required}" \
          "$(__dybatpho_config_doc_json_value "${default}" "${declared}")" \
          "$(__dybatpho_config_doc_json_value "${constraints}")" \
          "$(__dybatpho_config_doc_json_value "${description}")"
        separator=","
        ;;
    esac
  done
  if [[ "${format}" == json ]]; then
    printf ']\n'
  fi
  return 0
}
