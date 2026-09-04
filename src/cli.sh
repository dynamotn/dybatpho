#!/usr/bin/env bash
# @file cli.sh
# @brief Utilities for building CLI parsers from shell specs.
# @description
#   `src/cli.sh` lets you describe a command with shell functions, then generate:
#
#   - option parsing
#   - subcommand dispatch
#   - help output
#   - validation and error handling
#   - automatic `--help` / `-h` for commands that do not define their own help option
# @usage
#   ### Basic workflow
#
#   1. Write a spec function.
#   2. Call `dybatpho::opts::setup` once inside that spec.
#   3. Define flags, params, display options, and subcommands.
#   4. Call `dybatpho::generate_from_spec <spec> "$@"`.
#   5. Optionally expose `--help` with `dybatpho::generate_help <spec>`.
#
#   #### Minimal example
#
#   ```bash
#   function _run {
#     dybatpho::print "Hello, ${NAME}!"
#     exit 0
#   }
#
#   function _spec {
#     dybatpho::opts::setup "A minimal greeter CLI" ARGS action:"_run"
#     dybatpho::opts::param "Your name" NAME -n --name required:true
#     dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
#   }
#
#   dybatpho::generate_from_spec _spec "$@"
#   ```
#
#   ### Spec argument types
#
#   Functions in this module accept two kinds of extra arguments:
#
#   | Type | Description |
#   | ---- | ----------- |
#   | `switch` | Option switch such as `-f`, `--flag`, `--{no-}flag`, `--with{out}-feature` |
#   | `key:value` | Attribute in `name:value` form |
#
#   ### Supported switch forms
#
#   | Form | Meaning |
#   | ---- | ------- |
#   | `-x` | short option |
#   | `--name` | long option |
#   | `--{no-}name` | expands to `--name` and `--no-name` |
#   | `--with{out}-name` | expands to `--with-name` and `--without-name` |
#
#   ### Shared attributes
#
#   These attributes are parsed by `dybatpho::opts::flag` and/or `dybatpho::opts::param`.
#
#   | Attribute | Applies to | Description |
#   | --------- | ---------- | ----------- |
#   | `action:<code>` | `setup`, `disp` | Code to run when parsing finishes or a display option is used |
#   | `prerun:<code>` | `setup` | Code to run after validation and before `action:<code>` |
#   | `postrun:<code>` | `setup` | Code to run after `action:<code>` |
#   | `args:<rule>` | `setup` | Positional argument rule: `none`, `exact:N`, `min:N`, `max:N`, or `range:M:N` |
#   | `alias:<name>` | `flag`, `param`, `disp`, `cmd` | Add one alias switch or command name |
#   | `aliases:<a,b>` | `flag`, `param`, `disp`, `cmd` | Add multiple aliases separated by commas |
#   | `init:<value>` | `flag`, `param` | Initial variable value |
#   | `on:<string>` | `flag`, `param` | Positive value when the option is enabled |
#   | `off:<string>` | `flag`, `param` | Negative value when the option is disabled or absent |
#   | `persistent:<bool>` | `flag`, `param`, `disp` | Make the option available in descendant subcommands |
#   | `export:<bool>` | `flag`, `param` | Export the variable |
#   | `env:<NAME>` | `flag`, `param` | Use environment variable `NAME` as the option's initial value |
#   | `optional:<bool>` | `param` | Whether the option value is optional when the switch appears |
#   | `required:<bool>` | `param` | Whether the option itself must appear |
#   | `prompt:<text>` | `param` | Prompt for a missing value with the supplied text |
#   | `choices:<a,b>` | `param` | Restrict values to a comma-separated list of choices |
#   | `multiple:<bool>` | `param` | Append repeated or multi-selected values instead of replacing the value; interactive selection accepts comma-separated values and ranges such as `1-3` |
#   | `validate:<code>` | `flag`, `param` | Validation logic using `\$OPTARG` |
#   | `deprecated:<text>` | `flag`, `param`, `disp`, `cmd` | Warn when the item is used and annotate it in help |
#   | `error:<code>` | `flag`, `param`, `setup` | Custom error handler |
#   | `hidden:<bool>` | help output | Hide the row from generated help |
#   | `label:<string>` | help output | Override the label shown in generated help |
#
#   ### `init:` forms
#
#   | Form | Description |
#   | ---- | ----------- |
#   | `init:@empty` | Initialize with empty string |
#   | `init:@on` | Initialize with the current `on:` value |
#   | `init:@off` | Initialize with the current `off:` value |
#   | `init:@unset` | Unset the variable |
#   | `init:@keep` | Keep the current variable value |
#   | `init:action:<code>` | Run code without assignment |
#   | `init:=<code>` | Assign the raw shell expression |
#
#   ### Positional argument rules
#
#   Use `args:<rule>` in `dybatpho::opts::setup` to validate positional arguments
#   the same way Cobra-style commands often do.
#
#   | Rule | Meaning |
#   | ---- | ------- |
#   | `args:none` | Reject all positional arguments |
#   | `args:exact:2` | Require exactly 2 positional arguments |
#   | `args:min:1` | Require at least 1 positional argument |
#   | `args:max:3` | Allow at most 3 positional arguments |
#   | `args:range:1:2` | Require between 1 and 2 positional arguments |
#
#   ### Parsing and dispatch
#
#   `dybatpho::generate_from_spec` generates and runs parser logic from a spec. It:
#
#   - initializes variables from the spec
#   - parses switches and arguments
#   - counts positional arguments for `args:` rules
#   - validates input
#   - dispatches subcommands
#   - runs the `action:` from `dybatpho::opts::setup`
#
#   ### Help generation
#
#   `dybatpho::generate_help` automatically handles:
#
#   - usage line
#   - description from `dybatpho::opts::setup`
#   - option rows
#   - command rows
#   - current subcommand path
#   - automatic `(required)` suffix for `required:true` params
#
#   By default:
#
#   - `flag` rows show switches only
#   - `param` rows show switches plus `<VARNAME>`
#   - `disp` rows show switches only
#   - `cmd` rows show the command name
#
#   You can override the rendered label with `label:<string>`.
#
#   Commands automatically accept `--help` and `-h` unless the spec defines a
#   help display option itself. Define a custom display option when the command
#   needs a different help action or aliases.
#
#   ### Common patterns
#
#   #### Required positional-like option
#
#   ```bash
#   function _run {
#     dybatpho::print "Hello, ${NAME}"
#     exit 0
#   }
#
#   function _spec {
#     dybatpho::opts::setup "Greeter" -
#     dybatpho::opts::param "Your name" NAME --name required:true
#     dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
#   }
#   ```
#
#   #### Exact positional args
#
#   ```bash
#   function _spec_sum {
#     dybatpho::opts::setup "Add two numbers" SUM_ARGS args:exact:2 action:"_run_sum"
#   }
#   ```
#
#   #### Aliases
#
#   ```bash
#   dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
#   dybatpho::opts::cmd config _spec_config alias:cfg aliases:conf,settings
#   ```
#
#   #### Persistent parent options
#
#   ```bash
#   function _spec_root {
#     dybatpho::opts::setup "Root command" -
#     dybatpho::opts::flag "Verbose output" VERBOSE --verbose persistent:true
#     dybatpho::opts::cmd deploy _spec_deploy
#   }
#   ```
#
#   #### Hidden and deprecated items
#
#   ```bash
#   dybatpho::opts::flag "Legacy flag" LEGACY --legacy hidden:true
#   dybatpho::opts::cmd old-run _spec_old deprecated:"Use 'run' instead"
#   ```
#
#   #### PreRun / PostRun hooks
#
#   ```bash
#   function _spec_run {
#     dybatpho::opts::setup "Run command" - prerun:"echo pre" action:"echo main" postrun:"echo post"
#   }
#   ```
#
#   #### Boolean toggle
#
#   ```bash
#   dybatpho::opts::flag "Color output" COLOR --{no-}color on:true off:false init:="true"
#   ```
#
#   #### Validation
#
#   ```bash
#   _validate_port() {
#     [[ "${1}" =~ ^[0-9]+$ ]] && [ "${1}" -ge 1 ] && [ "${1}" -le 65535 ]
#   }
#
#   dybatpho::opts::param "Port" PORT --port validate:"_validate_port \$OPTARG"
#   ```
#
#   #### Subcommand tree
#
#   ```bash
#   function _spec_root {
#     dybatpho::opts::setup "Tool root" ROOT_ARGS action:"dybatpho::generate_help _spec_root"
#     dybatpho::opts::cmd user _spec_user
#     dybatpho::opts::cmd config _spec_config
#   }
#
#   function _spec_user {
#     dybatpho::opts::setup "User commands" USER_ARGS action:"dybatpho::generate_help _spec_user"
#     dybatpho::opts::cmd add _spec_user_add
#   }
#   ```
#
#   ### Error messages
#
#   The parser reports these standard errors:
#
#   - `Unrecognized option: ...`
#   - `Does not allow an argument: ...`
#   - `Requires an argument: ...`
#   - `Missing required option: ...`
#   - `Expected ... arguments, got ...`
#   - `Invalid command: ...`
#   - `Validation error (...): ...`
#
#   ### Debugging
#
#   Set `DYBATPHO_CLI_DEBUG=true` to print the generated parser script.
#
#   ```bash
#   DYBATPHO_CLI_DEBUG=true bash example/cli_basic.sh --help
#   ```
#
#   This is useful when debugging:
#
#   - dispatch flow
#   - generated actions
#   - switch matching
#   - help generation
#
# @see
#   - `example/cli_basic.sh`
#   - `example/cli_advanced.sh`
# @tip Set `DYBATPHO_CLI_DEBUG=true` while developing a spec to inspect the generated parser and help logic.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CLI_DEBUG bool Set to `true` to dump generated parser details while developing specs
DYBATPHO_CLI_DEBUG="${DYBATPHO_CLI_DEBUG:-false}"

#######################################
# @description Read a line from the terminal (or stdin) with an optional default.
# @arg $1 string Prompt text
# @arg $2 string Optional default value
# @stdout Entered value
# @exitcode 0
#######################################
function dybatpho::prompt {
  local prompt="${1:-}" default="${2:-}" value
  printf "%s" "${prompt}" >&2
  [ -n "${default}" ] && printf " [%s]" "${default}" >&2
  printf ": " >&2
  IFS= read -r value || return 1
  [ -n "${value}" ] || value="${default}"
  printf "%s" "${value}"
}

#######################################
# @description Prompt for one or more values from a comma-separated list or numeric range.
# @arg $1 string Prompt text
# @arg $2 string Comma-separated choices
# @arg $3 bool Allow multiple selections
# @stdout Selected value(s), separated by spaces
# @exitcode 0
#######################################
function dybatpho::select {
  local prompt="${1:-}" choices="${2:-}" multiple="${3:-false}"
  local -a items=() selected=()
  local item answer index
  IFS=',' read -r -a items <<< "${choices}"
  printf "%s\n" "${prompt}" >&2
  for index in "${!items[@]}"; do
    printf "  %d) %s\n" "$((index + 1))" "${items[index]}" >&2
  done
  while :; do
    local selection_prompt="Select"
    dybatpho::is true "${multiple}" && selection_prompt+=" (comma-separated or ranges, e.g. 1-3)"
    answer="$(dybatpho::prompt "${selection_prompt}")" || return 1
    selected=()
    local -a answers=()
    IFS=',' read -r -a answers <<< "${answer}"
    local token range_start range_end range_index
    for token in "${answers[@]}"; do
      if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        range_start="${BASH_REMATCH[1]}"
        range_end="${BASH_REMATCH[2]}"
        if dybatpho::is false "${multiple}"; then
          continue
        fi
        if ((range_start < 1 || range_end > ${#items[@]} || range_start > range_end)); then
          continue
        fi
        for ((range_index = range_start; range_index <= range_end; range_index++)); do
          selected+=("${items[$((range_index - 1))]}")
        done
      elif [[ "${token}" =~ ^[0-9]+$ ]] && [ "${token}" -ge 1 ] && [ "${token}" -le "${#items[@]}" ]; then
        selected+=("${items[$((token - 1))]}")
      else
        for item in "${items[@]}"; do
          [ "${token}" = "${item}" ] && selected+=("${item}") && break
        done
      fi
    done
    [ "${#selected[@]}" -gt 0 ] || {
      dybatpho::warn "Choose a valid selection."
      continue
    }
    if dybatpho::is false "${multiple}"; then
      [ "${#selected[@]}" -eq 1 ] || {
        dybatpho::warn "Choose one selection."
        continue
      }
    fi
    printf "%s" "${selected[*]}"
    return 0
  done
}

#######################################
# @description Check that a value belongs to a comma-separated choice list.
# @arg $1 string Value
# @arg $2 string Comma-separated choices
# @exitcode 0 Value is allowed
#######################################
function dybatpho::opts::validate_choice {
  local value="${1-}" choices="${2-}" choice
  IFS=',' read -r -a __choice_items <<< "${choices}"
  for choice in "${__choice_items[@]}"; do
    [ "${value}" = "${choice}" ] && return 0
  done
  return 1
}

# @section Internal functions
# @description Functions are triggered by `dybatpho::generate_from_spec`

#######################################
# @description Parse options with a spec from `dybatpho::opts::flag`,
#              `dybatpho::opts::param`
# @arg $1 bool Flag that defined option that take argument in spec
# @arg $2 number Count of non-option metadata args to skip after the mode flags
# @arg $@ string Passed arguments from `dybatpho::opts::(flag|param|disp)`
# @exitcode 0
#######################################
function __parse_opt {
  local need_argument=$1
  local skip_meta=$2
  shift 2

  if dybatpho::is false "${__done_initial}"; then
    __on="true" __off="" __init="@empty" __export="true" __required="false" __persistent="false" __hidden="false" __deprecated="" __label="" __env="" __multiple="false" __prompt="" __choices=""
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
        alias:*)
          case ${1#alias:} in
            --*)
              if [ -z "${__label}" ] || [ "${__label#--}" = "${__label}" ]; then
                __label="${1#alias:}"
              fi
              ;;
            -?)
              [ -n "${__label}" ] || __label="${1#alias:}"
              local __alias_switch="${1#alias:}"
              dybatpho::is true "${need_argument}" \
                && __params="${__params}${__alias_switch#-}" \
                || __flags="${__flags}${__alias_switch#-}"
              ;;
            *)
              dybatpho::die "Invalid switch alias: ${1#alias:}" # kcov(skip)
              ;;
          esac
          ;;
        aliases:*)
          local -a __opt_aliases=()
          local __opt_alias
          __parse_alias_list __opt_aliases "${1#aliases:}"
          for __opt_alias in "${__opt_aliases[@]}"; do
            case ${__opt_alias} in
              --*)
                if [ -z "${__label}" ] || [ "${__label#--}" = "${__label}" ]; then
                  __label="${__opt_alias}"
                fi
                ;;
              -?)
                [ -n "${__label}" ] || __label="${__opt_alias}"
                dybatpho::is true "${need_argument}" \
                  && __params="${__params}${__opt_alias#-}" \
                  || __flags="${__flags}${__opt_alias#-}"
                ;;
              *)
                dybatpho::die "Invalid switch alias: ${__opt_alias}" # kcov(skip)
                ;;
            esac
          done
          ;;
        [!-]*) __parse_key_value "$1" "__" ;;
        --*)
          if [ -z "${__label}" ] || [ "${__label#--}" = "${__label}" ]; then
            __label="$1"
          fi
          ;;
        -?)
          [ -n "${__label}" ] || __label="$1"
          dybatpho::is true "${need_argument}" \
            && __params="${__params}${1#-}" \
            || __flags="${__flags}${1#-}"
          ;;
      esac
      shift
    done
  else
    __validate="" __on="true" __off="" __export="true" __optional="false" __required="false" __persistent="false" __hidden="false" __deprecated="" __switch="" __env="" __multiple="false" __prompt="" __choices=""
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
        alias:*)
          case ${1#alias:} in
            --\{no-\}*)
              i=${1#alias:--?no-?}
              __add_switch "'--${i}'|'--no-${i}'"
              ;;
            --with\{out\}-*)
              i=${1#alias:--*-}
              __add_switch "'--with-${i}'|'--without-${i}'"
              ;;
            -? | --*) __add_switch "'${1#alias:}'" ;;
            *) dybatpho::die "Invalid switch alias: ${1#alias:}" ;; # kcov(skip)
          esac
          ;;
        aliases:*)
          local -a __opt_aliases=()
          local __opt_alias
          __parse_alias_list __opt_aliases "${1#aliases:}"
          for __opt_alias in "${__opt_aliases[@]}"; do
            case ${__opt_alias} in
              --\{no-\}*)
                i=${__opt_alias#--?no-?}
                __add_switch "'--${i}'|'--no-${i}'"
                ;;
              --with\{out\}-*)
                i=${__opt_alias#--*-}
                __add_switch "'--with-${i}'|'--without-${i}'"
                ;;
              -? | --*) __add_switch "'${__opt_alias}'" ;;
              *) dybatpho::die "Invalid switch alias: ${__opt_alias}" ;; # kcov(skip)
            esac
          done
          ;;
        --\{no-\}*)
          i=${1#--?no-?}
          __add_switch "'--${i}'|'--no-${i}'"
          ;;
        --with\{out\}-*)
          i=${1#--*-}
          __add_switch "'--with-${i}'|'--without-${i}'"
          ;;
        -? | --*) __add_switch "'$1'" ;;
        *) __parse_key_value "$1" "__" ;;
      esac
      shift
    done
    __assign_quoted __on "${__on}"
    __assign_quoted __off "${__off}"
  fi
}

#######################################
# @description Write script with indentation to stdout
# @arg $1 number Number of indentation level
# @arg $@ string Line of code to generate
# @stdout Generated code
# @exitcode 0
#######################################
function __print_indent {
  local indent=$1
  shift
  for ((i = indent; i > 0; i--)); do
    echo -n "  "
  done
  echo "$@"
}

#######################################
# @description Validate a shell variable name used by generated parser code.
# @arg $1 string Variable name, or `-` to intentionally skip assignment
# @exitcode 0 The name is valid, or the sentinel `-` was used
#######################################
function __require_shell_name {
  local name="${1:-}"
  [[ "${name}" == "-" ]] && return 0
  [[ "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "Invalid shell variable name: ${name}"
}

#######################################
# @description Assign the quoted string to a variable
# @arg $1 string Variable name to be assigned
# @arg $2 string Input string to be quoted
# @exitcode 0
#######################################
function __assign_quoted {
  __require_shell_name "$1"
  local quote="$2'" result=""
  while [ "${quote}" ]; do
    result="${result}${quote%%\'*}'\''" && quote=${quote#*\'}
  done
  quote="'${result%????}'" && quote=${quote#\'\'} && quote=${quote%\'\'}
  printf -v "$1" '%s' "${quote:-"''"}"
}

#######################################
# @description Prepend export of before string of command,
#              based on `export:<bool>` switch
# @arg $1 string String of command
#######################################
function __prepend_export {
  echo "$(dybatpho::is true "${__export}" && echo "export ")$1"
}

#######################################
# @description Define variable from spec from `dybatpho::opts::flag`,
#              `dybatpho::opts::param`
# @arg $1 string Name of variable to be defined
#######################################
function __define_var {
  [ "$1" = "-" ] && return 0
  __require_shell_name "$1"
  local __env_name="${__env:-}"
  if [ "${__env_name}" = "true" ]; then __env_name="$1"; fi
  [ "${__env_name}" = "false" ] && __env_name=""
  [ -z "${__env_name}" ] || __require_shell_name "${__env_name}"
  if [ -n "${__env_name}" ] && [ "${__init}" != "@unset" ]; then
    __print_indent 0 "if [ \"\${${__env_name}+x}\" ]; then"
    __print_indent 1 "$(__prepend_export "$1=\${${__env_name}}")"
    __print_indent 0 "else"
    local __saved_env="${__env}"
    local __fallback
    __env=""
    __fallback="$(__define_var "$1")"
    __env="${__saved_env}"
    __print_indent 1 "${__fallback}"
    __print_indent 0 "fi"
    return 0
  fi
  case ${__init} in
    @keep) : ;;
    @empty) __print_indent 0 "$(__prepend_export "$1=''")" ;;
    @unset) __print_indent 0 "unset $1 ||:" ;;
    *)
      case ${__init} in @on) __init=${__on} ;; esac
      case ${__init} in @off) __init=${__off} ;; esac
      case ${__init} in =*)
        __print_indent 0 "$(__prepend_export "$1${__init}")"
        return 0
        ;;
      esac
      case ${__init} in action:*)
        local action=""
        __parse_key_value "${__init#init:}"
        __print_indent 0 "${action}"
        return 0
        ;;
      esac
      __assign_quoted __init "${__init#=}"
      __print_indent 0 "$(__prepend_export "$1=${__init}")"
      ;;
  esac
}

#######################################
# @description Extract key value from spec with format `x:y`,
#              to get settings of option
# @arg $1 key:value Key-value string to extract
# @arg $2 string Prefix of key to assign as variable
#######################################
function __parse_key_value() {
  local target="${2-}${1%%:*}"
  __require_shell_name "${target}"
  printf -v "${target}" '%s' "${1#*:}"
}

# shellcheck disable=2016
#######################################
# @description Generate logic from spec of script/function to get options
# @arg $1 string Name of function that has spec of parent function or script
# @arg $2 string Command of spec (`-` for root command trigger from CLI, otherwise is sub-command)
# @stdout Generated logic
#######################################
function __generate_logic {
  local spec command
  dybatpho::expect_args spec command -- "$@"
  [ "$(type -t "${spec}")" != 'function' ] && return
  shift 2

  local IFS=" "                                                                                               # For get list of options, separated by space
  local __rest=""                                                                                             # For get all rest arguments
  local __error="" __validate=""                                                                              # For get function name of custom error handler, validation and
  local __flags="" __params=""                                                                                # For get all flags and params of command
  local __on="1" __off="" __init="@empty"                                                                     # For handle argument of param, effective for rest arguments and options
  local __export="true"                                                                                       # For handle export variable of `dybatpho::opts::*` commands via name
  local __optional="true" __required="false" __persistent="false" __hidden="false" __deprecated="" __label="" # Param value optionality, option presence, persistence, visibility, deprecation, preferred switch label
  local __action="" __setup_action="" __prerun="" __setup_prerun="" __postrun="" __setup_postrun=""           # For get action and setup hooks in spec
  local __args="any"                                                                                          # For validate positional argument count from opts::setup
  local __switch=""                                                                                           # For get switch of options
  declare -a __required_checks=()
  declare -a __persistent_defs=()
  local __has_sub_cmd="false"
  local __has_help="false"
  declare -a __sub_specs=()
  declare -a __prompt_defs=()

  #######################################
  # @description Emit generated code that rebuilds positional parameters from a serialized argument list.
  # @arg $1 string Shell expression that expands to serialized arguments
  # @stdout Generated parser code
  #######################################
  __print_get_arg() {
    __print_indent 4 "eval 'set -- $1' \${1+'\"\$@\"'}"
  }

  #######################################
  # @description Emit generated code that appends the remaining positional arguments to the configured rest variable and stops option parsing.
  # @noargs
  # @stdout Generated parser code
  #######################################
  __print_rest() {
    __print_indent 4 'while [ $# -gt 0 ]; do'
    __print_indent 5 "${__rest}=\"\${${__rest}} \$1\""
    __print_indent 5 '__rest_argc=$((__rest_argc + 1))'
    __print_indent 5 "shift"
    __print_indent 4 "done"
    __print_indent 4 "break"
    __print_indent 4 ";;"
  }

  # Initial all variables before get value of options
  local __done_initial=false
  __replay_persistent_defs
  "${spec}" "$*"
  __print_indent 0 "dybatpho::opts::parse::${spec}() {"
  __print_indent 1 'local __rest_argc=0'
  __print_persistent_help_defs
  # shellcheck disable=2016
  __print_indent 1 \
    "while OPTARG= && [ \"\${${__rest}}\" != end ] && [ \$# -gt 0 ]; do"
  __print_indent 2 "case \$1 in"
  __print_indent 3 "--?*=*)"
  __print_indent 4 "OPTARG=\$1; shift"
  __print_get_arg '"${OPTARG%%\=*}" "${OPTARG#*\=}"'
  __print_indent 4 ";;"
  __print_indent 3 "--no-*|--without-*)"
  __print_indent 4 "unset OPTARG"
  __print_indent 4 ";;"
  [ "${__params}" ] && {
    __print_indent 3 "-[${__params}]?*)"
    __print_indent 4 "OPTARG=\$1; shift"
    __print_get_arg '"${OPTARG%"${OPTARG#??}"}" "${OPTARG#??}"'
    __print_indent 4 ";;"
  }
  [ "${__flags}" ] && {
    __print_indent 3 "-[${__flags}]?*) OPTARG=\$1; shift"
    __print_get_arg '"${OPTARG%"${OPTARG#??}"}" -"${OPTARG#??}"'
    __print_indent 4 \
      'case $2 in --*) set -- "$1" unknown "$2" && '"${__rest}"'=end; esac'
    __print_indent 4 'OPTARG='
    __print_indent 4 ';;'
  }
  __print_indent 2 "esac"

  # Get value of options
  __print_indent 2 'case $1 in'
  __done_initial=true
  __replay_persistent_defs
  if dybatpho::is false "${__has_help}"; then
    __print_indent 3 "--help|-h)"
    __print_indent 4 "dybatpho::generate_help ${spec}"
    __print_indent 4 "exit 0"
    __print_indent 4 ";;"
  fi
  "${spec}" "$*"
  __print_indent 3 "--)"
  __print_indent 4 "shift"
  __print_rest
  __print_indent 3 "*)"
  if dybatpho::is false "${__has_sub_cmd}"; then
    __print_rest
  else
    __print_indent 4 "case \$1 in"
    for sub_spec in "${__sub_specs[@]}"; do
      local _sub_spec _cmd_match _cmd_name _cmd_deprecated
      IFS=$'\t' read -r _sub_spec _cmd_match _cmd_name _cmd_deprecated <<< "${sub_spec}"
      __print_indent 5 "${_cmd_match})"
      [ "${_cmd_deprecated}" ] && __print_deprecated_warning "command" "${_cmd_name}" "${_cmd_deprecated}"
      __print_indent 6 "__current_cmd_path=\"\${__current_cmd_path:+\${__current_cmd_path} }${_cmd_name}\""
      __print_indent 6 "shift"
      __print_indent 6 "dybatpho::opts::parse::${_sub_spec} \"\$@\""
      __print_indent 6 ";;"
    done
    __print_indent 5 "*)"
    __print_indent 6 'set "notcmd" "$1"'
    __print_indent 6 "break"
    __print_indent 6 ";;"
    __print_indent 4 "esac"
    __print_rest
  fi
  __print_indent 2 "esac"
  __print_indent 2 "shift"
  __print_indent 1 "done"

  # Show error messages if invalid, otherwise run action command
  __print_indent 1 '[ $# -eq 0 ] && {'
  __print_indent 2 'unset OPTARG'
  for __required_check in "${__required_checks[@]}"; do
    __print_indent 2 '[ $# -eq 0 ] && {'
    __print_indent 3 "${__required_check}"
    __print_indent 2 '}'
  done
  __print_args_check "${__args}"
  local __prompt_def __prompt_var __prompt_text __prompt_choices __prompt_multiple __prompt_export
  for __prompt_def in "${__prompt_defs[@]}"; do
    IFS=$'\x1f' read -r __prompt_var __prompt_text __prompt_choices __prompt_multiple __prompt_export <<< "${__prompt_def}"
    __assign_quoted __prompt_text "${__prompt_text}"
    # Quote the choices only after testing them: quoting an empty value yields `''`.
    if [ -n "${__prompt_choices}" ]; then
      __assign_quoted __prompt_choices "${__prompt_choices}"
      __print_indent 2 "if [ -z \"\${${__prompt_var}:-}\" ]; then"
      __print_indent 3 "${__prompt_var}=\$(dybatpho::select ${__prompt_text} ${__prompt_choices} ${__prompt_multiple})"
      [ "${__prompt_export}" = "true" ] && __print_indent 3 "export ${__prompt_var}"
      __print_indent 2 "fi"
    else
      __print_indent 2 "if [ -z \"\${${__prompt_var}:-}\" ]; then"
      __print_indent 3 "${__prompt_var}=\$(dybatpho::prompt ${__prompt_text})"
      [ "${__prompt_export}" = "true" ] && __print_indent 3 "export ${__prompt_var}"
      __print_indent 2 "fi"
    fi
  done
  __print_indent 2 '[ $# -eq 0 ] && {'
  [ "${__setup_prerun}" ] && __print_indent 3 "${__setup_prerun}"
  [ "${__setup_action}" ] && __print_indent 3 "${__setup_action}"
  [ "${__setup_postrun}" ] && __print_indent 3 "${__setup_postrun}"
  __print_indent 3 'return 0'
  __print_indent 2 '}'
  __print_indent 1 '}'
  __print_indent 1 'case $1 in'
  __print_indent 2 'unknown) set "Unrecognized option: $2" "$@" ;;'
  __print_indent 2 'noarg) set "Does not allow an argument: $2" "$@" ;;'
  __print_indent 2 'needarg) set "Requires an argument: $2" "$@" ;;'
  __print_indent 2 'missingopt) set "Missing required option: $2" "$@" ;;'
  __print_indent 2 'argcount) set "$2" "$@" ;;'
  __print_indent 2 'notcmd) set "Invalid command: $2" "$@" ;;'
  __print_indent 2 '*) set "Validation error ($1): $2" "$@"'
  __print_indent 1 "esac"
  [ "${__error}" ] && __print_indent 1 "${__error}" '"$@" >&2 || exit $?'
  __print_indent 1 'dybatpho::die "$1" 1'
  __print_indent 0 "} # End of dybatpho::opts::parse::${spec}"

  # Generate sub-command logics
  for sub_spec in "${__sub_specs[@]}"; do
    local _sub_spec _cmd_match _cmd_name _cmd_deprecated
    IFS=$'\t' read -r _sub_spec _cmd_match _cmd_name _cmd_deprecated <<< "${sub_spec}"
    [ "${_cmd_match}" = "${_cmd_name}" ] || continue
    __generate_child_logic "${_sub_spec}" "${_cmd_name}" "$@"
  done

  # Trigger root spec
  if [[ "${command}" == "-" ]]; then
    local trigger="dybatpho::opts::parse::${spec}"
    for param in "$@"; do
      trigger+=" \"${param//\"/\\\"}\""
    done
    __print_indent 0 "${trigger}"
  fi

}

#######################################
# @description Get help description for options from spec.
#              Sets __help_mode=true so dybatpho::opts::* collect help data
#              via dynamic scoping into dybatpho::generate_help's locals,
#              then prints the buffered sections in the correct order.
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Help description
# @exitcode 0 exit code
#######################################
function __generate_help {
  local spec
  dybatpho::expect_args spec -- "$@"
  [ "$(type -t "${spec}")" != 'function' ] && return

  __help_mode=true
  __replay_persistent_defs
  local __persistent_def
  local __persistent_replay=true
  for __persistent_def in "${__persistent_help_defs[@]}"; do
    eval "${__persistent_def}"
  done
  "${spec}"
  __help_mode=false

  dybatpho::print "${__help_usage}"
  if [ -n "${__help_description}" ]; then
    dybatpho::print ""
    dybatpho::print "${__help_description}"
  fi
  dybatpho::print ""
  dybatpho::print "Options:"
  printf "%s" "${__help_opts_output}"
  if [ -n "${__help_cmds_output}" ]; then
    dybatpho::print ""
    dybatpho::print "Commands:"
    printf "%s" "${__help_cmds_output}"
  fi
}

#######################################
# @description Generate a JSON CLI schema from the same option spec used by parsing.
# @arg $1 string Spec function
# @arg $2 string Optional command name
# @stdout JSON schema
#######################################
function dybatpho::generate_schema {
  local spec name="${2:-${0##*/}}"
  dybatpho::expect_args spec -- "$@"
  __generate_schema_command "${spec}" "${name}"
}

function __generate_schema_command {
  local spec="$1" name="$2" command_aliases="${3:-}" description
  local -a options=() commands=()
  __collect_spec_metadata "${spec}" options commands description
  local q_name q_description item first=true aliases="${command_aliases}"
  __json_quote q_name "${name}"
  __json_quote q_description "${description}"
  local alias alias_first=true
  printf '{"name":%s,"description":%s,"aliases":[' "${q_name}" "${q_description}"
  for alias in ${aliases:-}; do
    __json_quote alias "${alias}"
    [ "${alias_first}" = true ] || printf ","
    alias_first=false
    printf "%s" "${alias}"
  done
  printf '],"options":['
  for item in "${options[@]}"; do
    local type var desc switches env multiple choices prompt hidden required deprecated label
    IFS=$'\t' read -r type var desc switches env multiple choices prompt hidden required deprecated label <<< "${item}"
    [ "${env}" = "@none" ] && env=""
    [ "${choices}" = "@none" ] && choices=""
    [ "${prompt}" = "@none" ] && prompt=""
    [ "${deprecated}" = "@none" ] && deprecated=""
    [ "${label}" = "@none" ] && label=""
    local q_type q_var q_desc q_env q_choices q_prompt q_deprecated q_label
    __json_quote q_type "${type}"
    __json_quote q_var "${var}"
    __json_quote q_desc "${desc}"
    __json_quote q_env "${env}"
    __json_quote q_choices "${choices}"
    __json_quote q_prompt "${prompt}"
    __json_quote q_deprecated "${deprecated}"
    __json_quote q_label "${label}"
    [ "${first}" = true ] || printf ","
    first=false
    printf '{"type":%s,"name":%s,"description":%s,"switches":[' "${q_type}" "${q_var}" "${q_desc}"
    local switch switch_first=true
    for switch in ${switches}; do
      __json_quote switch "${switch}"
      [ "${switch_first}" = true ] || printf ","
      switch_first=false
      printf "%s" "${switch}"
    done
    printf '],"env":%s,"multiple":%s,"choices":%s,"prompt":%s,"hidden":%s,"required":%s,"deprecated":%s,"label":%s}' \
      "${q_env}" "${multiple:-false}" "${q_choices}" "${q_prompt}" "${hidden:-false}" "${required:-false}" "${q_deprecated}" "${q_label}"
  done
  printf '],"commands":['
  first=true
  for item in "${commands[@]}"; do
    local cmd child aliases child_hidden child_deprecated
    IFS=$'\t' read -r cmd child aliases child_hidden child_deprecated <<< "${item}"
    [ "${first}" = true ] || printf ","
    first=false
    __generate_schema_command "${child}" "${cmd}" "${aliases}"
  done
  printf "]}"
}

#######################################
# @description Generate a roff man page from a CLI option spec.
# @arg $1 string Spec function
# @arg $2 string Optional command name
# @stdout Man page
#######################################
function dybatpho::generate_man {
  local spec name="${2:-${0##*/}}"
  dybatpho::expect_args spec -- "$@"
  __generate_man_command "${spec}" "${name}" 1
}

function __generate_man_command {
  local spec="$1" name="$2" section="${3:-1}" nested="${4:-false}" description
  local -a options=() commands=()
  __collect_spec_metadata "${spec}" options commands description
  local escaped
  escaped="${name//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  if [ "${nested}" = false ]; then
    printf '.TH "%s" "%s" "" "" "dybatpho"\n' "${escaped}" "${section}"
    printf '.SH NAME\n%s \\- %s\n' "${escaped}" "${description}"
    printf '.SH SYNOPSIS\n.B %s\n' "${escaped}"
    printf '.SH OPTIONS\n'
  else
    printf '.SS %s\n%s\n' "${escaped}" "${description}"
  fi
  for item in "${options[@]}"; do
    local type var desc switches env multiple choices prompt hidden required deprecated label
    IFS=$'\t' read -r type var desc switches env multiple choices prompt hidden required deprecated label <<< "${item}"
    [ "${env}" = "@none" ] && env=""
    [ "${deprecated}" = "@none" ] && deprecated=""
    [ "${label}" = "@none" ] && label=""
    [ "${hidden:-false}" = true ] && continue
    local option_label="${switches// /, }"
    [ "${type}" = param ] && option_label="${option_label} <${var}>"
    printf '.TP\n.B %s\n%s' "${option_label}" "${desc}"
    [ "${required:-false}" = true ] && printf ' (required)'
    [ -n "${env}" ] && printf ' [env: %s]' "${env}"
    printf '\n'
  done
  if [ "${#commands[@]}" -gt 0 ]; then
    printf '.SH COMMANDS\n'
    for item in "${commands[@]}"; do
      local cmd child aliases child_hidden child_deprecated
      IFS=$'\t' read -r cmd child aliases child_hidden child_deprecated <<< "${item}"
      [ "${child_hidden:-false}" = true ] && continue
      printf '.TP\n.B %s\n' "${cmd}"
      __generate_man_command "${child}" "${cmd}" "${section}" true
    done
  fi
}

#######################################
# @description Generate Bash, Zsh, or Fish completion from a CLI option spec.
# @arg $1 string Spec function
# @arg $2 string Shell (`bash`, `zsh`, or `fish`)
# @arg $3 string Optional command name
# @stdout Completion script
#######################################
function dybatpho::generate_completion {
  local spec shell name="${3:-${0##*/}}"
  dybatpho::expect_args spec shell -- "$@"
  case "${shell}" in
    bash | zsh | fish) ;;                                          # kcov(skip)
    *) dybatpho::die "Unsupported completion shell: ${shell}" 1 ;; # kcov(skip)
  esac
  __generate_completion_command "${spec}" "${shell}" "${name}" "${name}"
}

function __completion_words {
  local -n __completion_out="$1"
  local -a options=("${@:2}") item switches switch
  for item in "${options[@]}"; do
    IFS=$'\t' read -r _ _ _ switches _ _ _ _ hidden _ _ _ <<< "${item}"
    [ "${hidden:-false}" = true ] && continue
    for switch in ${switches}; do __completion_out+=("${switch}"); done
  done
}

function __generate_completion_command {
  local spec="$1" shell="$2" name="$3" root="$4" description
  local -a options=() commands=() words=()
  __collect_spec_metadata "${spec}" options commands description
  __completion_words words "${options[@]}"
  local word_list="${words[*]}" cmd_list="" item cmd child aliases hidden deprecated
  for item in "${commands[@]}"; do
    IFS=$'\t' read -r cmd child aliases hidden deprecated <<< "${item}"
    if [ "${hidden:-false}" != true ]; then
      cmd_list+=" ${cmd} ${aliases}"
      local -a child_options=() child_commands=()
      local child_description
      __collect_spec_metadata "${child}" child_options child_commands child_description
      __completion_words words "${child_options[@]}"
    fi
  done
  word_list="${words[*]}"
  case "${shell}" in
    bash)
      printf '_%s_completion() {\n  local cur="${COMP_WORDS[COMP_CWORD]}"\n  COMPREPLY=( $(compgen -W %q -- "${cur}") )\n}\ncomplete -F _%s_completion %s\n' \
        "${name//[^a-zA-Z0-9_]/_}" "${word_list} ${cmd_list} --help -h" \
        "${name//[^a-zA-Z0-9_]/_}" "${name}"
      ;;
    zsh)
      printf '_%s_completion() {\n  _arguments "*: :((%s))"\n}\ncompdef _%s_completion %s\n' \
        "${name//[^a-zA-Z0-9_]/_}" "${word_list} ${cmd_list} --help -h" \
        "${name//[^a-zA-Z0-9_]/_}" "${name}"
      ;;
    fish)
      local switch
      for switch in "${words[@]}"; do
        case "${switch}" in
          --*) printf "complete -c %s -l %s\n" "${name}" "${switch#--}" ;;
          -?) printf "complete -c %s -s %s\n" "${name}" "${switch#-}" ;;
        esac
      done
      for item in "${commands[@]}"; do
        IFS=$'\t' read -r cmd child aliases hidden deprecated <<< "${item}"
        [ "${hidden:-false}" = true ] || printf "complete -c %s -f -a %q\n" "${name}" "${cmd}"
      done
      ;;
  esac
}

#######################################
# @description Pad string $2 to at least length $3 and store result in variable $1
# @arg $1 string Variable name to store result
# @arg $2 string String to pad
# @arg $3 number Minimum length
#######################################
function __help_pad {
  __require_shell_name "$1"
  local __p=$2
  while [ "${#__p}" -lt "$3" ]; do __p="${__p} "; done
  printf -v "$1" '%s' "${__p}"
}

#######################################
# @description Append a formatted switch to caller-local variable `sw`.
# Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so
# that short+long pairs align as "-s, --long".
# @arg $1 number Minimum pad width before appending $2
# @arg $2 string Switch string to append
#######################################
function __help_sw {
  __help_pad sw "${sw}${sw:+, }" "$1"
  sw="${sw}$2"
}

#######################################
# @description Format one help row and print to stdout
# @arg $1 string Type: flag | param | disp | cmd
# @arg $2 string Variable name (or command name for cmd type)
# @arg $3 string Description
# @arg $@ switch|key:value Switches and settings of this option
# @stdout Formatted help row
#######################################
function __help_row {
  local _type=$1 _var=$2 _desc=$3
  shift 3
  local sw="" label="" hidden="" required="false" deprecated=""
  while [ $# -gt 0 ]; do
    local _i=$1 && shift
    case ${_i} in
      alias:*)
        case ${_i#alias:} in
          --\{no-\}*)
            local _name="${_i#alias:--?no-?}"
            __help_sw 4 "--${_name}"
            __help_sw 4 "--no-${_name}"
            ;;
          --with\{out\}-*)
            local _name="${_i#alias:--*-}"
            __help_sw 4 "--with-${_name}"
            __help_sw 4 "--without-${_name}"
            ;;
          --*) __help_sw 4 "${_i#alias:}" ;;
          -?) __help_sw 0 "${_i#alias:}" ;;
          *) : ;; # kcov(skip)
        esac
        ;;
      aliases:*)
        local -a _aliases=()
        local _alias_item
        __parse_alias_list _aliases "${_i#aliases:}"
        for _alias_item in "${_aliases[@]}"; do
          case ${_alias_item} in
            --\{no-\}*)
              local _name="${_alias_item#--?no-?}"
              __help_sw 4 "--${_name}"
              __help_sw 4 "--no-${_name}"
              ;;
            --with\{out\}-*)
              local _name="${_alias_item#--*-}"
              __help_sw 4 "--with-${_name}"
              __help_sw 4 "--without-${_name}"
              ;;
            --*) __help_sw 4 "${_alias_item}" ;;
            -?) __help_sw 0 "${_alias_item}" ;;
            *) : ;; # kcov(skip)
          esac
        done
        ;;
      --\{no-\}*)
        local _name="${_i#--?no-?}"
        __help_sw 4 "--${_name}"
        __help_sw 4 "--no-${_name}"
        ;;
      --with\{out\}-*)
        local _name="${_i#--*-}"
        __help_sw 4 "--with-${_name}"
        __help_sw 4 "--without-${_name}"
        ;;
      --*) __help_sw 4 "${_i}" ;;
      -?) __help_sw 0 "${_i}" ;;
      hidden:*) hidden="${_i#hidden:}" ;;
      label:*) label="${_i#label:}" ;;
      required:*) required="${_i#required:}" ;;
      deprecated:*) deprecated="${_i#deprecated:}" ;;
      *) : ;;
    esac
  done

  dybatpho::is true "${hidden}" && return 0
  if [ "${_type}" = "param" ] && dybatpho::is true "${required}"; then
    _desc="${_desc:+${_desc} }(required)"
  fi
  if [ -n "${deprecated}" ]; then
    _desc="${_desc:+${_desc} }(deprecated: ${deprecated})"
  fi

  local len=${__help_width%,*}
  [ "${label}" ] || case ${_type} in
    flag | disp) label="${sw} " ;;
    param) label="${sw} <${_var}> " ;;
    cmd) label="${_var} " len=${__help_width#*,} ;;
  esac

  __help_pad label "${label:+${__help_leading}}${label}" "${len}"
  if [ "${#label}" -le "${len}" ]; then
    printf "%s\n" "${label}${_desc}"
  else
    printf "%s\n" "${label}"
    if [ -n "${_desc}" ]; then
      local _pad
      __help_pad _pad "" "${len}"
      printf "%s\n" "${_pad}${_desc}"
    fi
  fi
}

#######################################
# @description Add to switches list if flag/param has multiple switches
# @arg $1 switch Switch
#######################################
function __add_switch {
  __switch="${__switch}${__switch:+|}$1"
}

#######################################
# @description Emit generated code that validates the current `OPTARG` and assigns it to the destination variable.
# @arg $1 string Destination variable name, or `-` to skip assignment
# @stdout Generated parser code
# @note Uses caller-local `__validate` when a custom validator was configured for the current option
#######################################
function __print_validate {
  set -- "${__validate}" "$1"
  if [ -n "${__choices:-}" ]; then
    local __choices_quoted
    __assign_quoted __choices_quoted "${__choices}"
    __print_indent 4 "dybatpho::opts::validate_choice \"\$OPTARG\" ${__choices_quoted} || { set \"choice\" \"\$OPTARG\"; break; }"
  fi
  [ "$1" ] && __print_indent 4 "$1 || { set -- ${1%% *}:\$? \"\$1\" $1; break; }"
  if [ "$2" != "-" ]; then
    if dybatpho::is true "${__multiple:-false}"; then
      __print_indent 4 "[ -n \"\${$2:-}\" ] && $2=\"\${$2} \$OPTARG\" || $2=\"\$OPTARG\""
      [ "${__export}" = "true" ] && __print_indent 4 "export $2"
    else
      __print_indent 4 "$(__prepend_export "$2=\$OPTARG")"
    fi
  fi
}

#######################################
# @description Split a comma-separated alias list into a caller-provided array.
# @arg $1 string Name of destination array variable
# @arg $2 string Comma-separated aliases
# @exitcode 0 Aliases appended to destination array
#######################################
function __parse_alias_list {
  __require_shell_name "$1"
  local -n __alias_out="$1"
  local __alias_raw="${2:-}" __alias_item
  IFS=',' read -r -a __alias_items <<< "${__alias_raw}"
  for __alias_item in "${__alias_items[@]}"; do
    [ -n "${__alias_item}" ] && __alias_out+=("${__alias_item}")
  done
}

#######################################
# @description Serialize an option definition so it can be replayed for persistent descendant commands.
# @arg $1 string Option type (`flag`, `param`, or `disp`)
# @arg $@ string Original arguments passed to the option helper
# @exitcode 0 Definition stored for later replay
#######################################
function __record_persistent_def {
  local __kind="$1" __serialized="dybatpho::opts::${1}" __part
  shift
  for __part in "$@"; do
    printf -v __part '%q' "${__part}"
    __serialized+=" ${__part}"
  done
  __persistent_defs+=("${__serialized}")
}

#######################################
# @description Replay inherited persistent option definitions inside the current parser/help generation context.
# @noargs
# @exitcode 0 All inherited persistent definitions were replayed
#######################################
function __replay_persistent_defs {
  local __persistent_def
  local __persistent_replay=true
  for __persistent_def in "${__persistent_inherited_defs[@]}"; do
    eval "${__persistent_def}"
  done
}

#######################################
# @description Emit generated code that seeds persistent option definitions for nested help output.
# @noargs
# @stdout Generated parser code
#######################################
function __print_persistent_help_defs {
  local __persistent_def __quoted_def __has_defs=false
  for __persistent_def in "${__persistent_inherited_defs[@]}" "${__persistent_defs[@]}"; do
    [ -n "${__persistent_def}" ] || continue
    if dybatpho::is false "${__has_defs}"; then
      __print_indent 1 'local -a __persistent_help_defs=()'
      __has_defs=true
    fi
    __assign_quoted __quoted_def "${__persistent_def}"
    __print_indent 1 "__persistent_help_defs+=( ${__quoted_def} )"
  done
}

#######################################
# @description Emit generated code that warns when a deprecated CLI item is used.
# @arg $1 string Item type label (`option` or `command`)
# @arg $2 string Item label shown in the warning
# @arg $3 string Deprecation message
# @stdout Generated parser code
#######################################
function __print_deprecated_warning {
  local __item_type="$1" __item_label="$2" __message="$3"
  local __warning
  __assign_quoted __warning "Deprecated ${__item_type}: ${__item_label}. ${__message}"
  __print_indent 4 "dybatpho::warn ${__warning}"
}

#######################################
# @description Generate parser logic for a child command with inherited persistent option definitions.
# @arg $1 string Child spec function
# @arg $2 string Child command name
# @arg $@ string Original CLI arguments
# @stdout Generated parser code
#######################################
function __generate_child_logic {
  local __child_spec="$1" __child_command="$2"
  shift 2
  local -a __persistent_inherited_defs=("${__persistent_inherited_defs[@]}" "${__persistent_defs[@]}")
  __generate_logic "${__child_spec}" "${__child_command}" "$@"
}

#######################################
# @description Emit generated code that validates the positional argument count configured by `args:<rule>` in `dybatpho::opts::setup`.
# @arg $1 string Argument count rule (`none`, `exact:N`, `min:N`, `max:N`, `range:M:N`, `any`)
# @stdout Generated parser code
# @exitcode 0 Rule accepted and code emitted
#######################################
function __print_args_check {
  local rule="${1:-any}"
  local expected min max noun

  case "${rule}" in
    "" | any | arbitrary) return 0 ;;
    none | noargs)
      __print_indent 2 '[ $# -eq 0 ] && {'
      __print_indent 3 '[ "${__rest_argc}" -eq 0 ] || set "argcount" "Expected no arguments, got ${__rest_argc}"'
      __print_indent 2 '}'
      ;;
    exact:*)
      expected="${rule#exact:}"
      [[ "${expected}" =~ ^[0-9]+$ ]] || dybatpho::die "Invalid args rule: ${rule}"
      noun="arguments"
      [ "${expected}" -eq 1 ] && noun="argument"
      __print_indent 2 '[ $# -eq 0 ] && {'
      __print_indent 3 "[ \"\${__rest_argc}\" -eq ${expected} ] || set \"argcount\" \"Expected exactly ${expected} ${noun}, got \${__rest_argc}\""
      __print_indent 2 '}'
      ;;
    min:*)
      min="${rule#min:}"
      [[ "${min}" =~ ^[0-9]+$ ]] || dybatpho::die "Invalid args rule: ${rule}"
      noun="arguments"
      [ "${min}" -eq 1 ] && noun="argument"
      __print_indent 2 '[ $# -eq 0 ] && {'
      __print_indent 3 "[ \"\${__rest_argc}\" -ge ${min} ] || set \"argcount\" \"Expected at least ${min} ${noun}, got \${__rest_argc}\""
      __print_indent 2 '}'
      ;;
    max:*)
      max="${rule#max:}"
      [[ "${max}" =~ ^[0-9]+$ ]] || dybatpho::die "Invalid args rule: ${rule}"
      noun="arguments"
      [ "${max}" -eq 1 ] && noun="argument"
      __print_indent 2 '[ $# -eq 0 ] && {'
      __print_indent 3 "[ \"\${__rest_argc}\" -le ${max} ] || set \"argcount\" \"Expected at most ${max} ${noun}, got \${__rest_argc}\""
      __print_indent 2 '}'
      ;;
    range:*)
      min="${rule#range:}"
      max="${min#*:}"
      min="${min%%:*}"
      [[ "${min}" =~ ^[0-9]+$ && "${max}" =~ ^[0-9]+$ && "${min}" -le "${max}" ]] || dybatpho::die "Invalid args rule: ${rule}"
      __print_indent 2 '[ $# -eq 0 ] && {'
      __print_indent 3 "[ \"\${__rest_argc}\" -ge ${min} ] && [ \"\${__rest_argc}\" -le ${max} ] || set \"argcount\" \"Expected between ${min} and ${max} arguments, got \${__rest_argc}\""
      __print_indent 2 '}'
      ;;
    *)
      dybatpho::die "Invalid args rule: ${rule}" # kcov(skip)
      ;;
  esac
}

#######################################
# @description Expand option switches and aliases into a caller-provided array.
# @arg $1 string Name of destination array
# @arg $@ switch|key:value Option metadata
#######################################
function __collect_switches {
  __require_shell_name "$1"
  local -n __switch_out="$1"
  shift
  local __item __alias
  for __item in "$@"; do
    case "${__item}" in
      alias:*) __alias="${__item#alias:}" ;;
      aliases:*)
        local -a __aliases=()
        __parse_alias_list __aliases "${__item#aliases:}"
        for __alias in "${__aliases[@]}"; do
          case "${__alias}" in
            --\{no-\}*) __switch_out+=("--${__alias#--\{no-\}}" "--no-${__alias#--\{no-\}}") ;;
            --with\{out\}-*) __switch_out+=("--with-${__alias#--with\{out\}-}" "--without-${__alias#--with\{out\}-}") ;;
            -? | --*) __switch_out+=("${__alias}") ;;
          esac
        done
        continue
        ;;
      --\{no-\}*)
        __switch_out+=("--${__item#--\{no-\}}" "--no-${__item#--\{no-\}}")
        continue
        ;;
      --with\{out\}-*)
        __switch_out+=("--with-${__item#--with\{out\}-}" "--without-${__item#--with\{out\}-}")
        continue
        ;;
      -? | --*)
        __switch_out+=("${__item}")
        continue
        ;;
      *) continue ;;
    esac
    case "${__alias}" in
      --\{no-\}*) __switch_out+=("--${__alias#--\{no-\}}" "--no-${__alias#--\{no-\}}") ;;
      --with\{out\}-*) __switch_out+=("--with-${__alias#--with\{out\}-}" "--without-${__alias#--with\{out\}-}") ;;
      -? | --*) __switch_out+=("${__alias}") ;;
    esac
  done
}

#######################################
# @description Escape a value for JSON and store it in a caller variable.
#######################################
function __json_quote {
  __require_shell_name "$1"
  local __value="${2-}"
  __value="${__value//\\/\\\\}"
  __value="${__value//\"/\\\"}"
  __value="${__value//$'\n'/\\n}"
  __value="${__value//$'\r'/\\r}"
  __value="${__value//$'\t'/\\t}"
  printf -v "$1" '%s' "\"${__value}\""
}

#######################################
# @description Collect option and command metadata from a CLI spec.
#######################################
function __collect_spec_metadata {
  local __meta_spec="$1"
  local -n __meta_options_out="$2" __meta_commands_out="$3" __meta_description_out="$4"
  local __meta_mode=true __meta_description="" __meta_options=() __meta_commands=()
  local __done_initial=false __flags="" __params=""
  "${__meta_spec}"
  __meta_options_out=("${__meta_options[@]}")
  __meta_commands_out=("${__meta_commands[@]}")
  __meta_description_out="${__meta_description}"
}

# @section Spec functions
# @description Functions work in spec of script or function via `dybatpho::generate_from_spec`.

#######################################
# @description Setup global settings for getting options (mandatory) in spec
# of script or function
# @arg $1 string Description of sub-command/root command
# @arg $@ key:value Settings `key:value` for sub-command/root command such as `action:<code>`, `prerun:<code>`, `postrun:<code>`, and `args:<rule>`
# @note `args:<rule>` supports raw rules plus Cobra-like names such as `NoArgs`, `ExactArgs:N`, and `RangeArgs:M:N`
# @note `prerun:<code>` runs before `action:<code>`, and `postrun:<code>` runs after it
# @exitcode 0 exit code
#######################################
function dybatpho::opts::setup {
  local description
  dybatpho::expect_args description -- "$@"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __meta_description="${description}"
    return 0
  fi

  if dybatpho::is true "${__cmd_desc_mode:-false}"; then
    __cmd_desc="${description}"
    return 0
  fi

  shift

  if dybatpho::is true "${__help_mode:-false}"; then
    __help_usage="Usage: ${0##*/}${__help_subcmd:+ ${__help_subcmd}} [options...] [arguments...]"
    __help_description="${description}"
    return 0
  fi

  # HACK: __rest is defined in __generate_logic, so we need to define it here
  if [ "${1#-}" ]; then
    __require_shell_name "$1"
    __rest="$1"
  else
    __rest="__rest"
  fi

  if dybatpho::is false "${__done_initial}"; then
    __init="@empty"
    while dybatpho::still_has_args "$@" && shift; do
      __parse_key_value "$1" "__"
    done
    __define_var "${__rest}"
    __setup_prerun="${__prerun}"
    __setup_action="${__action}"
    __setup_postrun="${__postrun}"
  fi
}

# shellcheck disable=2016
#######################################
# @description Define an option that take no argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>`
# @note Use `persistent:true` to make the flag available to descendant subcommands
# @exitcode 0 exit code
#######################################
function dybatpho::opts::flag {
  local description var
  dybatpho::expect_args description var -- "$@"
  __require_shell_name "${var}"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __parse_opt false 2 "$@"
    local -a __meta_switches=()
    __collect_switches __meta_switches "${@:3}"
    __meta_options+=("flag"$'\t'"${var}"$'\t'"${description}"$'\t'"${__meta_switches[*]}"$'\t'"${__env:-@none}"$'\t'"${__multiple:-false}"$'\t'"${__choices:-@none}"$'\t'"${__prompt:-@none}"$'\t'"${__hidden:-false}"$'\t'"${__required:-false}"$'\t'"${__deprecated:-@none}"$'\t'"${__label:-@none}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row flag "${var}" "${description}" "${@:3}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt false 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    if dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
      __record_persistent_def flag "$@"
    fi
    __define_var "${var}"
  else
    __print_indent 3 "${__switch})"
    [ "${__deprecated}" ] && __print_deprecated_warning "option" "${__label:-${var}}" "${__deprecated}"
    __print_indent 4 '[ "${OPTARG:-}" ] && OPTARG=${OPTARG#*\=} && set "noarg" "$1" && break'
    __print_indent 4 "eval '[ \${OPTARG+x} ] &&:' && OPTARG=${__on} || OPTARG=${__off}"
    __print_validate "${var}" '$OPTARG'
    __print_indent 4 ";;"
  fi
}

# shellcheck disable=2016
#######################################
# @description Define an option that take an argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>`
# @tip Use `required:true` when the option itself must be present
# @tip Use `optional:true` when the option may appear without an explicit value
# @tip `optional:true` controls whether a value is required after the switch appears, while `required:true` controls whether the switch itself must appear at all
# @tip Keep conditional requirements such as "required unless `--list` is set" in your action or validation logic
# @note Use `persistent:true` to make the param available to descendant subcommands
# @exitcode 0 exit code
#######################################
function dybatpho::opts::param {
  local description var
  dybatpho::expect_args description var -- "$@"
  __require_shell_name "${var}"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __parse_opt true 2 "$@"
    local -a __meta_switches=()
    __collect_switches __meta_switches "${@:3}"
    __meta_options+=("param"$'\t'"${var}"$'\t'"${description}"$'\t'"${__meta_switches[*]}"$'\t'"${__env:-@none}"$'\t'"${__multiple:-false}"$'\t'"${__choices:-@none}"$'\t'"${__prompt:-@none}"$'\t'"${__hidden:-false}"$'\t'"${__required:-false}"$'\t'"${__deprecated:-@none}"$'\t'"${__label:-@none}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row param "${var}" "${description}" "${@:3}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt true 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    if dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
      __record_persistent_def param "$@"
    fi
    __define_var "${var}"
    if [ -n "${__prompt}" ]; then
      # A unit separator keeps empty fields, which tabs would collapse on read.
      __prompt_defs+=("${var}"$'\x1f'"${__prompt}"$'\x1f'"${__choices}"$'\x1f'"${__multiple}"$'\x1f'"${__export}")
    fi
    if dybatpho::is true "${__required}"; then
      local __required_marker="__dybatpho_required_${spec//[^a-zA-Z0-9_]/_}_${var}"
      local __saved_init="${__init}" __saved_export="${__export}"
      __init="@empty"
      __export="false"
      __define_var "${__required_marker}"
      __init="${__saved_init}"
      __export="${__saved_export}"
      __required_checks+=("[ \"\${${__required_marker}}\" ] || set \"missingopt\" \"${__label:-${var}}\"")
    fi
  else
    local __required_marker=""
    if dybatpho::is true "${__required}"; then
      __required_marker="__dybatpho_required_${spec//[^a-zA-Z0-9_]/_}_${var}"
    fi
    __print_indent 3 "${__switch})"
    [ "${__deprecated}" ] && __print_deprecated_warning "option" "${__label:-${var}}" "${__deprecated}"
    if dybatpho::is false "${__optional}"; then
      __print_indent 4 '[ $# -le 1 ] && set "needarg" "$1" && break'
      __print_indent 4 'OPTARG=$2'
    else
      __print_indent 4 'set -- "$1" "$@"'
      __print_indent 4 '[ ${OPTARG+x} ] && {'
      __print_indent 5 'case $1 in --no-*|--without-*) set "noarg" "${1%%\=*}"; break; esac'
      __print_indent 5 '[ "${OPTARG:-}" ] && { shift; OPTARG=$2; } || {'
      __print_indent 6 'case ${3:-} in'
      __print_indent 7 '"") OPTARG='"${__on}"' ;;'
      __print_indent 7 '-*) OPTARG='"${__on}"' ;;'
      __print_indent 7 '*) shift; OPTARG=$2 ;;'
      __print_indent 6 'esac'
      __print_indent 5 '}'
      __print_indent 4 "} || OPTARG=${__off}"
    fi
    __print_validate "${var}" '$OPTARG'
    [ "${__required_marker}" ] && __print_indent 4 "${__required_marker}=true"
    __print_indent 4 "shift"
    __print_indent 4 ";;"
  fi
}

#######################################
# @description Define an option that display only
# @arg $1 string Description of option to display
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>`
# @note Use `persistent:true` to make the display option available to descendant subcommands
# @exitcode 0 exit code
#######################################
function dybatpho::opts::disp {
  local description
  dybatpho::expect_args description -- "$@"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__meta_mode:-false}"; then
    __parse_opt false 1 "$@"
    local -a __meta_switches=()
    __collect_switches __meta_switches "${@:2}"
    __meta_options+=("disp"$'\t'"-"$'\t'"${description}"$'\t'"${__meta_switches[*]}"$'\t@none\tfalse\t@none\t@none\t'"${__hidden:-false}"$'\tfalse\t'"${__deprecated:-@none}"$'\t'"${__label:-@none}")
    return 0
  fi

  if dybatpho::is false "${__done_initial:-false}"; then
    local __help_arg
    for __help_arg in "${@:2}"; do
      case "${__help_arg}" in
        --help | -h | alias:--help | alias:-h | aliases:--help,* | aliases:*,-h | aliases:--help,-h)
          __has_help=true
          break
          ;;
      esac
    done
  fi

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row disp "-" "${description}" "${@:2}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt false 1 "$@"
  if ! dybatpho::is false "${__done_initial}"; then
    __print_indent 3 "${__switch})"
    [ "${__deprecated}" ] && __print_deprecated_warning "option" "${__label:-${description}}" "${__deprecated}"
    [ "${__action}" ] && __print_indent 4 "${__action}"
    __print_indent 4 "exit 0"
    __print_indent 4 ";;"
  elif dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
    __record_persistent_def disp "$@"
  fi
}

#######################################
# @description Define a sub-command in spec
# @arg $1 string Command name
# @arg $2 string Name of function that has spec of sub-command
# @arg $@ key:value Optional metadata such as `alias:<name>` or `aliases:<a,b>`
#######################################
function dybatpho::opts::cmd {
  local sub_cmd sub_spec
  dybatpho::expect_args sub_cmd sub_spec -- "$@"
  shift 2

  local -a __cmd_aliases=()
  local __cmd_alias __cmd_hidden="false" __cmd_deprecated=""
  while [ $# -gt 0 ]; do
    case $1 in
      alias:*) __cmd_aliases+=("${1#alias:}") ;;
      aliases:*) __parse_alias_list __cmd_aliases "${1#aliases:}" ;;
      hidden:*) __cmd_hidden="${1#hidden:}" ;;
      deprecated:*) __cmd_deprecated="${1#deprecated:}" ;;
    esac
    shift
  done

  if dybatpho::is true "${__meta_mode:-false}"; then
    __meta_commands+=("${sub_cmd}"$'\t'"${sub_spec}"$'\t'"${__cmd_aliases[*]:-@none}"$'\t'"${__cmd_hidden:-false}"$'\t'"${__cmd_deprecated:-@none}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local __cmd_desc="" __cmd_desc_mode=true
    "${sub_spec}"
    local __cmd_label="${sub_cmd}"
    for __cmd_alias in "${__cmd_aliases[@]}"; do
      __cmd_label="${__cmd_label}, ${__cmd_alias}"
    done
    local _line
    _line=$(__help_row cmd "${__cmd_label}" "${__cmd_desc}" "hidden:${__cmd_hidden}" "deprecated:${__cmd_deprecated}")
    __help_cmds_output="${__help_cmds_output}${_line}"$'\n'
    return 0
  fi

  if dybatpho::is true "${__done_initial}"; then
    __has_sub_cmd="true"
    __sub_specs+=("${sub_spec}"$'\t'"${sub_cmd}"$'\t'"${sub_cmd}"$'\t'"${__cmd_deprecated}")
    for __cmd_alias in "${__cmd_aliases[@]}"; do
      __sub_specs+=("${sub_spec}"$'\t'"${__cmd_alias}"$'\t'"${sub_cmd}"$'\t'"${__cmd_deprecated}")
    done
  fi
}

# @section Parse functions
# @description Functions to parse spec and put value of options to variable with corresponding name

#######################################
# @description Define spec of parent function or script, spec contains below commands
# @arg $1 string Name of function that has spec of parent function or script
# @exitcode 0 exit code
#######################################
function dybatpho::generate_from_spec {
  local spec
  dybatpho::expect_args spec -- "$@"
  shift

  __current_cmd_path=""
  local gen_file
  dybatpho::create_temp gen_file ".sh" "genopts"
  __generate_logic "${spec}" - "$@" >> "${gen_file}"
  if dybatpho::is true "${DYBATPHO_CLI_DEBUG}"; then
    dybatpho::debug_command "Generate script of \"${spec}\" - \"$*\"" "dybatpho::show_file '${gen_file}'"
  fi
  # shellcheck disable=1090
  . "${gen_file}"
}

#######################################
# @description Show help description of root command/sub-command.
#              Declares help state as locals so dybatpho::opts::* in the call
#              chain can read/write them via bash dynamic scoping.
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Help description
# @tip The current subcommand path is tracked automatically during parser dispatch
#######################################
function dybatpho::generate_help {
  local spec
  dybatpho::expect_args spec -- "$@"

  # Help generation state — local here, visible to the whole call chain via
  # bash dynamic scoping (dybatpho::opts::* write, __generate_help reads)
  local __help_mode=false
  local __cmd_desc_mode=false
  local __help_width="30,16"
  local __help_leading="  "
  local __help_subcmd="${__current_cmd_path:-}"
  local __help_usage=""
  local __help_description=""
  local __help_opts_output=""
  local __help_cmds_output=""

  __generate_help "${spec}"
}
