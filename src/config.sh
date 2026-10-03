# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it parses its own arguments, so the raw form is
# what the reader sees.
# dyshellint disable=BSG050,BSG011,BSG051
# @file config.sh
# @brief Utilities for loading configuration from files and environment variables.
# @namespace dybatpho
# @description
#   Configuration files are loaded in the order provided, so later files
#   override earlier files. Environment variables loaded with
#   `dybatpho::config_env` are applied last.
#
#   `dybatpho::config_profile` builds the usual two-file overlay on top of that
#   order: a base `config.yaml` followed by the `config.<profile>.yaml` beside
#   it, which may be absent. `dybatpho::config_load --optional` is the same
#   tolerance for any other list of files.
#
#   `dybatpho::config_set` changes a value in memory and
#   `dybatpho::config_save` writes chosen keys back to a file in the format
#   that file already uses: a dotenv rewrite keeps its comments, its blank
#   lines, and the order of its assignments, while JSON, YAML, and TOML are
#   rewritten through `jq` and `yq` so the rest of the document survives.
#
#   Keys can also be given a typed schema with `dybatpho::config_schema`.
#   `dybatpho::config_validate` then applies declared defaults, enforces
#   required keys, types, ranges, and enum choices, and reports every
#   violation together with the key that caused it. The types come from the
#   `validate` module rather than from a list kept here, so a schema may
#   declare `email`, `port`, `ipv4`, `semver`, `dir` or any type registered
#   with `dybatpho::validate_register`, and the message a rejected value
#   produces is worded the same way everywhere in the library. The same schema renders a
#   configuration reference through `dybatpho::config_doc`, and tells
#   `dybatpho::config_save` which values to write as numbers or booleans
#   rather than as strings.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

declare -gA DYBATPHO_CONFIG=()
declare -gA DYBATPHO_CONFIG_SCHEMA=()
declare -ga DYBATPHO_CONFIG_SCHEMA_KEYS=()
declare -ga DYBATPHO_CONFIG_ERRORS=()

#######################################
# @description Store one configuration value, rejecting a key that is not a
#   name: the key becomes part of a variable name and of the schema, so a
#   stray character would land somewhere it cannot be looked up again.
# @arg $1 string Configuration key
# @arg $2 string Value
# @set DYBATPHO_CONFIG
# @exitcode 1 Stop the script when the key is not a valid name
# @internal
#######################################
function __dybatpho_config_set {
  local key value
  dybatpho::expect_args key value -- "$@"
  [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
    || dybatpho::die "Invalid configuration key: ${key}"
  DYBATPHO_CONFIG["${key}"]="${value}"
}

#######################################
# @description Read a dotenv file into the configuration: `KEY=value` a line,
#   with `export` prefixes, quotes and trailing comments removed.
# @arg $1 path File to read
# @set DYBATPHO_CONFIG
# @internal
#######################################
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

#######################################
# @description Read a JSON, YAML or TOML file into the configuration, flattening
#   it to the dotted keys the rest of the module uses.
#
#   Nested mappings are walked down to their values, so `server: {port: 8080}`
#   is stored under `server.port`, which is the key a `config:server.port`
#   binding and `dybatpho::config_get server.port` ask for. A sequence is a
#   value of its own rather than something to walk into: it is stored under its
#   key as compact JSON (`["a","b"]`), and so is an empty mapping (`{}`). A key
#   that already holds a dot, such as `"server.port": 1`, lands on the same
#   dotted key as the nested form; when a file spells it both ways, the one read
#   later wins.
#
#   Both backends print a key, a tab and the value with tabs, line breaks,
#   carriage returns and backslashes escaped, the way `jq`'s `@tsv` does; the
#   value is unescaped once it is read, so a line break inside a value survives.
#   `yq`'s own `@tsv` is not used for this: it quotes the way CSV does.
# @arg $1 string Format: `json`, `yaml` or `toml`
# @arg $2 path File to read
# @set DYBATPHO_CONFIG
# @exitcode 1 Stop the script when the document's root is not a mapping
# @internal
#######################################
function __dybatpho_config_load_structured {
  local file format key value entries label root
  format="$1"
  file="$2"
  if [[ "${format}" == json ]]; then
    dybatpho::require jq
    entries=$(jq -r '
      def flat($prefix):
        to_entries[]
        | ($prefix + [.key]) as $path
        | if (.value | type) == "object" and (.value | length) > 0
          then .value | flat($path)
          else [($path | join(".")), (.value | tostring)] | @tsv
          end;
      if type != "object" then error("root must be an object") else flat([]) end
    ' "${file}") \
      || dybatpho::die "Invalid JSON configuration: ${file}"
  else
    dybatpho::require yq
    local -a parse=()
    if [[ "${format}" == toml ]]; then
      label=TOML
      parse=(-p toml -o yaml)
    else
      label=YAML
      parse=(-p yaml -o yaml)
    fi
    # The root check is its own call on purpose. `yq` is not `jq`: it has no
    # `if ... then ... else ... end`, and its `select` does not hold back the
    # branch it guards here, so the check cannot ride along with the query.
    # Reading the tag first also keeps a sequence root from being loaded under
    # the keys `0`, `1`, ... instead of being rejected.
    root=$(yq "${parse[@]}" -r 'tag' "${file}" 2> /dev/null) \
      || dybatpho::die "Invalid ${label} configuration: ${file}"
    [[ "${root}" == "!!map" ]] \
      || dybatpho::die "Invalid ${label} configuration: ${file}"
    # `yq` has no recursive definitions, so the walk visits every node and keeps
    # the leaves no sequence encloses: values, sequences and empty mappings.
    # `${0}${0}` doubles a backslash; a replacement spelled with backslashes is
    # unescaped once more than it looks.
    # shellcheck disable=SC2016 # `${0}` is yq's match reference, not a shell expansion
    entries=$(yq "${parse[@]}" -r '
      ..
      | select(path | length > 0)
      | select(parents | all_c(tag != "!!seq"))
      | select(tag != "!!map" or length == 0)
      | (path | join(".")) + "\t" + (
          ((select(tag == "!!seq" or tag == "!!map") | to_json(0)) // tostring)
          | sub("\\x5c"; "${0}${0}") | sub("\t"; "\\\\t") | sub("\n"; "\\\\n") | sub("\r"; "\\\\r")
        )
    ' "${file}") \
      || dybatpho::die "Invalid ${label} configuration: ${file}"
  fi
  if [[ -n "${entries}" ]]; then
    while IFS=$'\t' read -r key value; do
      printf -v value '%b' "${value}"
      __dybatpho_config_set "${key}" "${value}"
    done <<< "${entries}"
  fi
}

#######################################
# @description Load one or more configuration files, merging them left to right.
# @example
#   dybatpho::config_load defaults.yaml production.yaml
#
# @example
#   # A machine-local override that may simply not be there.
#   dybatpho::config_load --optional /etc/app.env "${HOME}/.config/app.env"
#
# @arg $1 string Optional `--optional`, to skip files that do not exist instead of failing
# @arg $@ string Files in dotenv, JSON, YAML, or TOML format, in increasing precedence order
# @set DYBATPHO_CONFIG Merged values, where a later file replaces an earlier one
# @note A nested JSON, YAML, or TOML mapping is stored under dotted keys, so
#   `server: {port: 8080}` is read back with `dybatpho::config_get server.port`.
#   A sequence and an empty mapping are values of their own, kept as compact
#   JSON under their key.
# @exitcode 1 A required file is missing, or a file has an unsupported format or invalid configuration
# @tip Pass `--` before a file whose own name starts with `--`.
#######################################
function dybatpho::config_load {
  local optional=false
  while (($#)); do
    case "$1" in
      --optional)
        optional=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one configuration file"
  local file extension
  for file in "$@"; do
    if ! dybatpho::is file "${file}"; then
      [[ "${optional}" == true ]] \
        || dybatpho::die "Configuration file not found: ${file}"
      dybatpho::debug "Skipping missing configuration file: ${file}"
      continue
    fi
    extension="${file##*.}"
    case "${extension,,}" in
      env | dotenv) __dybatpho_config_load_dotenv "${file}" ;;
      json) __dybatpho_config_load_structured json "${file}" ;;
      yaml | yml) __dybatpho_config_load_structured yaml "${file}" ;;
      toml) __dybatpho_config_load_structured toml "${file}" ;;
      *) dybatpho::die "Unsupported configuration format: ${file}" ;; # kcov(skip)
    esac
  done
}

#######################################
# @description Load a base configuration file and the profile overlay beside it.
#   The overlay is the base name with the profile inserted before the
#   extension, so `config.yaml` with profile `prod` reads `config.prod.yaml`
#   after it. The base file is required; the overlay is not, which is what lets
#   the same call work on a machine that has no profile-specific file.
# @example
#   dybatpho::config_profile ./config.yaml prod
#
# @example
#   # The profile comes from the environment when it is not passed.
#   DYBATPHO_CONFIG_PROFILE=staging dybatpho::config_profile ./config.json
#
# @arg $1 string Base configuration file, whose extension selects the format
# @arg $2 string Profile name, defaulting to `DYBATPHO_CONFIG_PROFILE`
# @env DYBATPHO_CONFIG_PROFILE string Profile used when none is passed
# @set DYBATPHO_CONFIG Base values, overlaid by the profile file when it exists
# @exitcode 1 No profile is given, the profile name is invalid, or the base file is missing or unreadable
#######################################
function dybatpho::config_profile {
  local file profile extension stem overlay
  dybatpho::expect_args file -- "$@"
  profile="${2-${DYBATPHO_CONFIG_PROFILE-}}"
  [[ -n "${profile}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected a profile name or DYBATPHO_CONFIG_PROFILE"
  [[ "${profile}" =~ ^[a-zA-Z0-9_-]+$ ]] \
    || dybatpho::die "Invalid configuration profile: ${profile}"
  [[ "$(dybatpho::path_basename "${file}")" == ?*.* ]] \
    || dybatpho::die "Configuration file has no extension: ${file}"
  extension="${file##*.}"
  stem="${file%.*}"
  overlay="${stem}.${profile}.${extension}"
  dybatpho::config_load "${file}"
  dybatpho::config_load --optional "${overlay}"
}

#######################################
# @description Load environment variables after an optional prefix.
# @arg $1 string Optional prefix, such as `APP_`
# @tip Environment variables override values loaded from configuration files.
#######################################
function dybatpho::config_env {
  local prefix="${1-}" variable key
  local compgen_output
  compgen_output=$(compgen -v) # kcov(skip)
  while IFS= read -r variable || [[ -n "${variable}" ]]; do
    [[ -n "${prefix}" && "${variable}" != "${prefix}"* ]] && continue
    key="${variable#"${prefix}"}"
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
    [[ -v "${variable}" ]] || continue
    __dybatpho_config_set "${key}" "${!variable}"
  done < <(printf '%s' "${compgen_output}")
}

#######################################
# @description Set a configuration value in memory.
#   The value joins the ones loaded from files and the environment, so a later
#   `dybatpho::config_validate` checks it like any other, and
#   `dybatpho::config_save` can write it back to a file.
# @example
#   dybatpho::config_set PORT 9090
#   dybatpho::config_save ./config.yaml PORT
#
# @arg $1 string Configuration key
# @arg $2 string Value
# @set DYBATPHO_CONFIG The key is added or replaced
# @exitcode 1 The key is invalid
#######################################
function dybatpho::config_set {
  local key value
  dybatpho::expect_args key value -- "$@"
  __dybatpho_config_set "${key}" "${value}"
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
# @description Render one value the way a dotenv file has to carry it.
#   A value made only of characters the loader reads back verbatim is written
#   bare; anything else is double-quoted, because that is the only form whose
#   escapes the loader expands. The double quote itself is left alone on
#   purpose: the loader strips the outer pair by position rather than by
#   parsing, and `printf '%b'` has no `\"` escape to undo.
# @arg $1 string Value
# @stdout The value, bare or double-quoted
# @internal
#######################################
function __dybatpho_config_dotenv_value {
  local value="${1-}"
  if [[ -n "${value}" && "${value}" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]]; then
    printf '%s' "${value}"
    return 0
  fi
  value="${value//\\/\\\\}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\r'/\\r}"
  printf '"%s"' "${value}"
}

#######################################
# @description Rewrite the named keys into a dotenv file.
#   Every line that assigns one of the keys is replaced in place, so comments,
#   blank lines, unrelated assignments, and the order of the file all survive.
#   Keys the file does not mention are appended in the order they were given.
# @arg $1 string Destination file, which is created when it does not exist
# @arg $@ string Configuration keys to write
# @exitcode 1 A key cannot be spelled as a dotenv name, or the write fails
# @internal
#######################################
function __dybatpho_config_save_dotenv {
  local file key line name rendered=""
  local -A wanted=() seen=()
  file="$1"
  shift
  for key in "$@"; do
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "Cannot save configuration key to a dotenv file: ${key}"
    wanted["${key}"]=1
  done

  if dybatpho::is file "${file}"; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      name=""
      if [[ "${line}" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
        name="${BASH_REMATCH[1]}"
      fi
      # Every occurrence is rewritten, not just the first: a repeated key means
      # the last assignment is the one the loader keeps, so leaving a stale
      # copy behind would quietly undo the save.
      if [[ -n "${name}" && -v "wanted[${name}]" ]]; then
        rendered+="${name}=$(__dybatpho_config_dotenv_value "${DYBATPHO_CONFIG[${name}]}")"$'\n'
        seen["${name}"]=1
      else
        rendered+="${line}"$'\n'
      fi
    done < "${file}" # kcov(skip)
  fi

  for key in "$@"; do
    [[ -v "seen[${key}]" ]] && continue
    rendered+="${key}=$(__dybatpho_config_dotenv_value "${DYBATPHO_CONFIG[${key}]}")"$'\n'
  done
  printf '%s' "${rendered}" | dybatpho::file_write_atomic "${file}"
}

#######################################
# @description Rewrite the named keys into a JSON, YAML, or TOML file.
#   Each key is assigned on its own rather than merged from a second document,
#   which is what keeps the file's own comments, indentation, and block style:
#   a node imported from JSON carries its flow style with it and reflows
#   everything around it.
#
#   Values reach `jq` and `yq` through the environment, never through the
#   command line, so a configured secret does not become world-readable in
#   `/proc`. Only the declared schema makes a value a number or a boolean;
#   without one it is written as a string.
# @arg $1 string Format: `json`, `yaml`, or `toml`
# @arg $2 string Destination file, which is created when it does not exist
# @arg $@ string Configuration keys to write
# @exitcode 1 `jq` or `yq` is missing, the file cannot be parsed, or the write fails
# @internal
#######################################
function __dybatpho_config_save_structured {
  local format file key setting type expression="" separator="" literal rendered
  local -a values=()
  format="$1"
  file="$2"
  shift 2

  for key in "$@"; do
    setting="${DYBATPHO_CONFIG[${key}]}"
    type="$(__dybatpho_config_schema_attr "${key}" type string)"
    literal=""
    if __dybatpho_validate_numeric_type "${type}" && [[ "${setting}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      literal="${setting}"
    elif [[ "${type}" == bool ]]; then
      # `dybatpho::is true` follows the shell's exit-code convention, where `0`
      # is success. A configuration file means the opposite by `1` and `0`, so
      # the mapping is spelled out here instead.
      case "${setting,,}" in
        true | yes | on | 1) literal=true ;;
        false | no | off | 0) literal=false ;;
        *) literal="" ;;
      esac
    fi
    if [[ -n "${literal}" ]]; then
      expression+="${separator}.[\"${key}\"] = ${literal}"
    elif [[ "${format}" == json ]]; then
      expression+="${separator}.[\"${key}\"] = \$ENV.__DYBATPHO_CONFIG_SAVE_${#values[@]}"
      values+=("${setting}")
    else
      expression+="${separator}.[\"${key}\"] = strenv(__DYBATPHO_CONFIG_SAVE_${#values[@]})"
      values+=("${setting}")
    fi
    separator=" | "
  done

  # `dybatpho::die` inside the command substitution below would end that
  # subshell alone, so the dependency is checked out here where a failure still
  # stops the caller.
  case "${format}" in
    json) dybatpho::require jq ;;
    *) dybatpho::require yq ;;
  esac

  rendered="$(
    index=0
    for setting in ${values[@]+"${values[@]}"}; do
      export "__DYBATPHO_CONFIG_SAVE_${index}=${setting}"
      index=$((index + 1))
    done
    case "${format}" in
      json)
        if dybatpho::is file "${file}"; then
          jq "${expression}" "${file}"
        else
          printf '{}\n' | jq "${expression}"
        fi
        ;;
      toml)
        if dybatpho::is file "${file}"; then
          yq -p toml -o toml "${expression}" "${file}"
        else
          printf '{}\n' | yq -p yaml -o toml "${expression}"
        fi
        ;;
      *)
        if dybatpho::is file "${file}"; then
          yq -p yaml -o yaml "${expression}" "${file}"
        else
          printf '{}\n' | yq -p yaml -o yaml "${expression}"
        fi
        ;;
    esac
  )" || dybatpho::die "Cannot rewrite ${format} configuration: ${file}"
  printf '%s\n' "${rendered}" | dybatpho::file_write_atomic "${file}"
}

#######################################
# @description Write configuration values back to a file, in the format that
#   file already uses. The extension selects the format, the file is created
#   when it does not exist, and the rewrite is atomic, so a reader sees either
#   the previous file or the complete new one.
#
#   A dotenv file keeps its comments, blank lines, and assignment order; JSON,
#   YAML, and TOML are rewritten with `jq` and `yq`, which leaves the keys this
#   call does not name untouched. A value is written as a number or a boolean
#   only when `dybatpho::config_schema` declared it as `int` or `bool`;
#   otherwise it is written as a string.
# @example
#   dybatpho::config_set PORT 9090
#   dybatpho::config_save ./config.yaml PORT
#
# @example
#   # Persist everything that is currently loaded.
#   dybatpho::config_save "${HOME}/.config/app.env"
#
# @arg $1 string Destination file in dotenv, JSON, YAML, or TOML format
# @arg $@ string Configuration keys to write, defaulting to every loaded key in name order
# @env DRY_RUN string When true-like, report the write instead of performing it
# @exitcode 1 A key is invalid or unset, the format is unsupported, or the write fails
# @tip Name the keys explicitly when `dybatpho::config_env` was used, so an unrelated environment variable is not
#   persisted
#   along with them.
#######################################
function dybatpho::config_save {
  local file key extension
  dybatpho::expect_args file -- "$@"
  shift
  local -a keys=()
  if (($#)); then
    keys=("$@")
  elif ((${#DYBATPHO_CONFIG[@]})); then
    local printf_output
    printf_output=$(printf '%s\n' "${!DYBATPHO_CONFIG[@]}" | LC_ALL=C sort) # kcov(skip)
    while IFS= read -r key || [[ -n "${key}" ]]; do
      keys+=("${key}")
    done < <(printf '%s' "${printf_output}")
  fi
  ((${#keys[@]} > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Expected at least one configuration key"

  for key in "${keys[@]}"; do
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] \
      || dybatpho::die "Invalid configuration key: ${key}"
    [[ -v "DYBATPHO_CONFIG[${key}]" ]] \
      || dybatpho::die "Cannot save a configuration key that is not set: ${key}"
  done

  extension="${file##*.}"
  case "${extension,,}" in
    env | dotenv) __dybatpho_config_save_dotenv "${file}" "${keys[@]}" ;;
    json) __dybatpho_config_save_structured json "${file}" "${keys[@]}" ;;
    yaml | yml) __dybatpho_config_save_structured yaml "${file}" "${keys[@]}" ;;
    toml) __dybatpho_config_save_structured toml "${file}" "${keys[@]}" ;;
    *) dybatpho::die "Unsupported configuration format: ${file}" ;; # kcov(skip)
  esac
}

#######################################
# @description Normalize a schema type name to its canonical form.
#   Every type the `validate` module knows is a configuration type, so a schema
#   can declare `email`, `port`, `semver`, `dir` or anything else registered
#   there without `config` carrying a second copy of the check. `enum` is the
#   one name `config` owns: it is not a type but a `choices` rule, which the
#   validator receives as such.
# @arg $1 string Name of the variable receiving the canonical type name, or `enum`
# @arg $2 string Declared type
# @set The named variable, when the type is supported
# @exitcode 1 The type is not supported
# @see
#   - `dybatpho::validate_types`
# @internal
#######################################
function __dybatpho_config_schema_type {
  local __dybatpho_config_type_var __dybatpho_config_type_input
  dybatpho::expect_args __dybatpho_config_type_var __dybatpho_config_type_input -- "$@"
  local -n __dybatpho_config_type_out="${__dybatpho_config_type_var}"
  if [[ "${__dybatpho_config_type_input,,}" == enum ]]; then
    __dybatpho_config_type_out=enum
    return 0
  fi
  __dybatpho_validate_canonical "${__dybatpho_config_type_var}" "${__dybatpho_config_type_input}"
}

#######################################
# @description Drop every attribute previously declared for a key.
# @arg $1 string Configuration key
# @internal
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
# @internal
#######################################
function __dybatpho_config_schema_attr {
  local key attribute
  dybatpho::expect_args key attribute -- "$@"
  printf '%s' "${DYBATPHO_CONFIG_SCHEMA["${key}.${attribute}"]-${3-}}"
}

#######################################
# @description Describe the range and choice constraints declared for a key.
# @arg $1 string Configuration key
# @stdout Human readable constraints, or an empty string when none are declared
# @internal
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
  if __dybatpho_validate_numeric_type "${type}"; then
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
# @arg $2 string Type: any name `dybatpho::validate_types` prints — `string`, `int`, `bool`, `url`, `email`, `port`,
#   `semver`, `dir`, a type of your own — or `enum`
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
  __dybatpho_config_schema_type type "${declared_type}" \
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
      default | description) ;;                                            # kcov(skip)
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
# @internal
#######################################
function __dybatpho_config_schema_error {
  local key reason
  dybatpho::expect_args key reason -- "$@"
  DYBATPHO_CONFIG_ERRORS+=("Invalid configuration \`${key}\`: ${reason}")
}

#######################################
# @description Validate a single value against the type declared for its key.
#   The checking itself belongs to the `validate` module: this turns the
#   declared attributes into its rules and gives each reason it reports the key
#   that caused it.
# @arg $1 string Configuration key
# @arg $2 string Effective value
# @set DYBATPHO_CONFIG_ERRORS Appends one message per violation
# @internal
#######################################
function __dybatpho_config_schema_check {
  local key value type min max reason
  dybatpho::expect_args key value -- "$@"
  type="$(__dybatpho_config_schema_attr "${key}" type string)"
  local -a rules=()
  if [[ "${type}" == enum ]]; then
    # An enum constrains the value to a list rather than to a shape, so it
    # reaches the validator as a `choices` rule over a plain string.
    rules+=("choices:$(__dybatpho_config_schema_attr "${key}" choices)")
  else
    rules+=("type:${type}")
  fi
  min="$(__dybatpho_config_schema_attr "${key}" min)"
  max="$(__dybatpho_config_schema_attr "${key}" max)"
  [[ -z "${min}" ]] || rules+=("min:${min}")
  [[ -z "${max}" ]] || rules+=("max:${max}")

  dybatpho::validate_value "${value}" "${rules[@]}" && return 0
  # shellcheck disable=SC2154 # filled by `src/validate.sh`
  for reason in "${DYBATPHO_VALIDATE_ERRORS[@]}"; do
    __dybatpho_config_schema_error "${key}" "${reason}"
  done
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
        DYBATPHO_CONFIG["${key}"]="${DYBATPHO_CONFIG_SCHEMA["${key}.default"]}"
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
# @internal
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
# @internal
#######################################
function __dybatpho_config_doc_json_value {
  local value="${1-}" declared="${2-}"
  if [[ -z "${value}" && "${declared}" != declared ]]; then
    printf 'null'
    return 0
  fi
  local log_json_escape
  log_json_escape=$(__dybatpho_log_json_escape "${value}")
  printf '"%s"' "${log_json_escape}"
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
    markdown | text | json) ;;                                                      # kcov(skip)
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
    *) ;;
  esac

  separator=""
  for key in ${DYBATPHO_CONFIG_SCHEMA_KEYS[@]+"${DYBATPHO_CONFIG_SCHEMA_KEYS[@]}"}; do
    type="$(__dybatpho_config_schema_attr "${key}" type string)"
    default="$(__dybatpho_config_schema_attr "${key}" default)"
    description="$(__dybatpho_config_schema_attr "${key}" description)"
    constraints="$(__dybatpho_config_schema_constraints "${key}")"
    local config_schema_attr
    config_schema_attr=$(__dybatpho_config_schema_attr "${key}" required false)
    if dybatpho::is true "${config_schema_attr}"; then
      required=true
    else
      required=false
    fi
    case "${format}" in
      markdown)
        local config_doc_cell
        config_doc_cell=$(__dybatpho_config_doc_cell "${description}")
        local config_doc_cell_2
        config_doc_cell_2=$(__dybatpho_config_doc_cell "${key}" code)
        local config_doc_cell_3
        config_doc_cell_3=$(__dybatpho_config_doc_cell "${constraints}")
        local config_doc_cell_4
        config_doc_cell_4=$(__dybatpho_config_doc_cell "${default}" code)
        printf '| %s | %s | %s | %s | %s | %s |\n' \
          "${config_doc_cell_2}" \
          "${type}" "${required}" \
          "${config_doc_cell_4}" \
          "${config_doc_cell_3}" \
          "${config_doc_cell}"
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
        local config_doc_json_value
        config_doc_json_value=$(__dybatpho_config_doc_json_value "${description}")
        local log_json_escape
        log_json_escape=$(__dybatpho_log_json_escape "${key}")
        local config_doc_json_value_2
        config_doc_json_value_2=$(__dybatpho_config_doc_json_value "${constraints}")
        local config_doc_json_value_3
        config_doc_json_value_3=$(__dybatpho_config_doc_json_value "${default}" "${declared}")
        printf '%s{"key":"%s","type":"%s","required":%s,"default":%s,"constraints":%s,"description":%s}' \
          "${separator}" \
          "${log_json_escape}" "${type}" "${required}" \
          "${config_doc_json_value_3}" \
          "${config_doc_json_value_2}" \
          "${config_doc_json_value}"
        separator=","
        ;;
      *) ;;
    esac
  done
  if [[ "${format}" == json ]]; then
    printf ']\n'
  fi
  return 0
}
