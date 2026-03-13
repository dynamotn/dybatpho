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
#   | `init:<value>` | `flag`, `param` | Initial variable value |
#   | `on:<string>` | `flag`, `param` | Positive value when the option is enabled |
#   | `off:<string>` | `flag`, `param` | Negative value when the option is disabled or absent |
#   | `export:<bool>` | `flag`, `param` | Export the variable |
#   | `optional:<bool>` | `param` | Whether the option value is optional when the switch appears |
#   | `required:<bool>` | `param` | Whether the option itself must appear |
#   | `validate:<code>` | `flag`, `param` | Validation logic using `\$OPTARG` |
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
#   ### Parsing and dispatch
#
#   `dybatpho::generate_from_spec` generates and runs parser logic from a spec. It:
#
#   - initializes variables from the spec
#   - parses switches and arguments
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
    __on="true" __off="" __init="@empty" __export="true" __required="false" __label=""
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
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
    __validate="" __on="true" __off="" __export="true" __optional="false" __required="false" __switch=""
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
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

  local IFS=" "                                         # For get list of options, separated by space
  local __rest=""                                       # For get all rest arguments
  local __error="" __validate=""                        # For get function name of custom error handler, validation and
  local __flags="" __params=""                          # For get all flags and params of command
  local __on="1" __off="" __init="@empty"               # For handle argument of param, effective for rest arguments and options
  local __export="true"                                 # For handle export variable of `dybatpho::opts::*` commands via name
  local __optional="true" __required="false" __label="" # Param value optionality, option presence, preferred switch label
  local __action="" __setup_action=""                   # For get action after parse all options and action of each options in spec
  local __switch=""                                     # For get switch of options
  declare -a __required_checks=()
  local __has_sub_cmd="false"
  declare -a __sub_specs=()

  __print_get_arg() {
    __print_indent 4 "eval 'set -- $1' \${1+'\"\$@\"'}"
  }

  __print_rest() {
    __print_indent 4 'while [ $# -gt 0 ]; do'
    __print_indent 5 "${__rest}=\"\${${__rest}} \$1\""
    __print_indent 5 "shift"
    __print_indent 4 "done"
    __print_indent 4 "break"
    __print_indent 4 ";;"
  }

  # Initial all variables before get value of options
  local __done_initial
  __done_initial=false && "${spec}" "$*"
  __print_indent 0 "dybatpho::opts::parse::${spec}() {"
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
  __done_initial=true && "${spec}" "$*"
  __print_indent 3 "--)"
  __print_indent 4 "shift"
  __print_rest
  __print_indent 3 "*)"
  if dybatpho::is false "${__has_sub_cmd}"; then
    __print_rest
  else
    __print_indent 4 "case \$1 in"
    for sub_spec in "${__sub_specs[@]}"; do
      local _cmd_name="${sub_spec#*:}"
      _cmd_name="${_cmd_name#\'}" && _cmd_name="${_cmd_name%\'}"
      __print_indent 5 "${sub_spec#*:})"
      __print_indent 6 "__current_cmd_path=\"\${__current_cmd_path:+\${__current_cmd_path} }${_cmd_name}\""
      __print_indent 6 "shift"
      __print_indent 6 "dybatpho::opts::parse::${sub_spec%%:*} \"\$@\""
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
  __print_indent 2 '[ $# -eq 0 ] && {'
  __print_indent 3 "${__setup_action}"
  __print_indent 3 'return 0'
  __print_indent 2 '}'
  __print_indent 1 '}'
  __print_indent 1 'case $1 in'
  __print_indent 2 'unknown) set "Unrecognized option: $2" "$@" ;;'
  __print_indent 2 'noarg) set "Does not allow an argument: $2" "$@" ;;'
  __print_indent 2 'needarg) set "Requires an argument: $2" "$@" ;;'
  __print_indent 2 'missingopt) set "Missing required option: $2" "$@" ;;'
  __print_indent 2 'notcmd) set "Invalid command: $2" "$@" ;;'
  __print_indent 2 '*) set "Validation error ($1): $2" "$@"'
  __print_indent 1 "esac"
  [ "${__error}" ] && __print_indent 1 "${__error}" '"$@" >&2 || exit $?'
  __print_indent 1 'dybatpho::die "$1" 1'
  __print_indent 0 "} # End of dybatpho::opts::parse::${spec}"

  # Generate sub-command logics
  for sub_spec in "${__sub_specs[@]}"; do
    __generate_logic "${sub_spec%%:*}" "${sub_spec#*:}" "$@"
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
  local sw="" label="" hidden="" required="false"
  while [ $# -gt 0 ]; do
    local _i=$1 && shift
    case ${_i} in
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
      *) : ;;
    esac
  done

  [ "${hidden}" ] && return 0
  if [ "${_type}" = "param" ] && dybatpho::is true "${required}"; then
    _desc="${_desc:+${_desc} }(required)"
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

function __print_validate {
  set -- "${__validate}" "$1"
  [ "$1" ] && __print_indent 4 "$1 || { set -- ${1%% *}:\$? \"\$1\" $1; break; }"
  [ "$2" = "-" ] || __print_indent 4 "$(__prepend_export "$2=\$OPTARG")"
}

# @section Spec functions
# @description Functions work in spec of script or function via `dybatpho::generate_from_spec`.

#######################################
# @description Setup global settings for getting options (mandatory) in spec
# of script or function
# @arg $1 string Description of sub-command/root command
# @arg $@ key:value Settings `key:value` for sub-command/root command
# @exitcode 0 exit code
#######################################
function dybatpho::opts::setup {
  local description
  dybatpho::expect_args description -- "$@"

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
    __setup_action="${__action}"
  fi
}

# shellcheck disable=2016
#######################################
# @description Define an option that take no argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch|key:value Other switches and settings `key:value` of this option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::flag {
  local description var
  dybatpho::expect_args description var -- "$@"
  __require_shell_name "${var}"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row flag "${var}" "${description}" "${@:3}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt false 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    __define_var "${var}"
  else
    __print_indent 3 "${__switch})"
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
# @arg $@ switch|key:value Other switches and settings `key:value` of this option
# @tip Use `required:true` when the option itself must be present
# @tip Use `optional:true` when the option may appear without an explicit value
# @tip `optional:true` controls whether a value is required after the switch appears, while `required:true` controls whether the switch itself must appear at all
# @tip Keep conditional requirements such as "required unless `--list` is set" in your action or validation logic
# @exitcode 0 exit code
#######################################
function dybatpho::opts::param {
  local description var
  dybatpho::expect_args description var -- "$@"
  __require_shell_name "${var}"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row param "${var}" "${description}" "${@:3}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt true 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    __define_var "${var}"
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
# @arg $@ switch|key:value Other switches and settings `key:value` of this option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::disp {
  local description
  dybatpho::expect_args description -- "$@"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__help_row disp "-" "${description}" "${@:2}")
    __help_opts_output="${__help_opts_output}${_line}"$'\n'
    return 0
  fi

  __parse_opt false 1 "$@"
  if ! dybatpho::is false "${__done_initial}"; then
    __print_indent 3 "${__switch})"
    [ "${__action}" ] && __print_indent 4 "${__action}"
    __print_indent 4 "exit 0"
    __print_indent 4 ";;"
  fi
}

#######################################
# @description Define a sub-command in spec
# @arg $1 string Name of function that has spec of sub-command
#######################################
function dybatpho::opts::cmd {
  local sub_cmd sub_spec
  dybatpho::expect_args sub_cmd sub_spec -- "$@"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local __cmd_desc="" __cmd_desc_mode=true
    "${sub_spec}"
    local _line
    _line=$(__help_row cmd "${sub_cmd}" "${__cmd_desc}")
    __help_cmds_output="${__help_cmds_output}${_line}"$'\n'
    return 0
  fi

  if dybatpho::is true "${__done_initial}"; then
    __has_sub_cmd="true"
    # shellcheck disable=2190
    __sub_specs+=("${sub_spec}:'${sub_cmd}'")
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
