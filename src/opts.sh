#!/usr/bin/env bash
#
# @file opts.sh
# @brief Utilities for getting options when calling command in script or from CLI
# @description
#   This module contains functions to define, get options (flags, parameters...) for command or subcommand
#   when calling it from CLI or in shell script.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @section Theses are type of functions' arguments that defined in this file
# - `switch`: A type as a string with format `-?`, `--*`, `--no-*`,
#             `--with-*`, `--without-*`,
#             `--{no-}*` (expand to use both `--flag` and `--no-flag`),
#             `--with{out}-*` (expand to `--with-flag` and `--without-flag`)
# - `key:value`: `key1:value1` style arguments,
#                if `:value` is omitted, it is the same as `key:key`
#   - `action:<statement>`: A function name with arguments as `key:value`,
#                           eg `action:foo` or `"action:foo 1 2 3"`
#   - `action:<code>`: List of multiple statements, split by `;` as `key:value`,
#                      eg `"action:foo; bar"`
#   - `init:<method>`: Method to initial value of variable from spec by
#                      variable name with key 'init:', include:
#     - `init:@empty`: Initial value as empty. It's default behavior
#     - `init:@on`: Initial value with same as `on` key,
#     - `init:@off`: Initial value with same as `off` key
#     - `init:@unset`: Unset the variable
#     - `init:@keep`: Do not initialization (Use the current value as it is)
#     - `init:action:<statement|code>`: Initialize by run statement(s)
#   - `export:<bool>`: Export variable in spec command or not, default is true
#   - `on:<string>`: The positive value whether option is switch as
#                    `--flag`, `--with-flag`, default is `"true"`
#   - `off:<string>`: The negative value whether option is not presence,
#                     or as `--no-flag`, `--without-flag`, default is empty `''`
# - `switch_or_key:value`: Any values that match `switch` or `key:value` type

# @section Functions are triggered by `dybatpho::generate_from_spec`
#######################################
# @description Parse options with a spec from `dybatpho::opts::flag`,
# `dybatpho::opts::param`
# @arg $1 bool Flag that defined option that take argument in spec
# @arg $@ string Passed arguments from `dybatpho::opts::(flag|param)`
# @exitcode 0
#######################################
function __parse_opt {
  if dybatpho::is false "${__done_initial}"; then
    local need_argument=$1 && shift
    __on="true" __off="" __init="@empty" __export="true"
    while dybatpho::still_has_args "$@" && shift; do
      case $1 in
        [!-]*) __parse_key_value "$1" "__" ;;
        -?)
          dybatpho::is true "${need_argument}" \
            && __params="${__params}${1#-}" \
            || __flags="${__flags}${1#-}"
          ;;
      esac
    done
  else
    __validate="" __on="true" __off="" __export="true" __optional="true" __switch=""
    shift # ignore flag $1
    while dybatpho::still_has_args "$@" && shift; do
      case $1 in
        --\{no-\}*)
          i=${1#--?no-?}
          __switch="'--${i}'|'--no-${i}'"
          ;;
        --with\{out\}-*)
          i=${1#--*-}
          __switch="'--with-${i}'|'--without-${i}'"
          ;;
        -? | --*) __switch="'$1'" ;;
        *) __parse_key_value "$1" "__" ;;
      esac
    done
    __assign_quoted __on "${__on}"
    __assign_quoted __off "${__off}"
  fi
}

#######################################
# @description Write script with indentation to stdout
# @arg $1 Number of indentation level
# @arg $@ Line of code to generate
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
# @description Assign the quoted string to a variable
# @arg $1 Variable name to be assigned
# @arg $2 Input string to be quoted
# @exitcode 0
#######################################
function __assign_quoted {
  local quote="$2'" result=""
  while [ "${quote}" ]; do
    result="${result}${quote%%\'*}'\''" && quote=${quote#*\'}
  done
  quote="'${result%????}'" && quote=${quote#\'\'} && quote=${quote%\'\'}
  eval "$1=\${quote:-\"''\"}"
}

#######################################
# @description Prepend export of before string of command,
#              based on <export:bool> switch
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
  eval "${2-}${1%%:*}=\${1#*:}"
}

#######################################
# @description Generate logic from spec of script/function
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Generated logic
#######################################
function __generate_logic {
  __print_get_arg() {
    __print_indent 4 "eval 'set -- $1' \${1+'\"\$@\"'}"
  }

  # HACK: For initial all variables before get value of variables
  local __done_initial
  __done_initial=false && "$1"
  __print_indent 0 "dybatpho::opts::parse::${1}() {"
  # shellcheck disable=2016
  __print_indent 1 'OPTIND=$(($# + 1))'
  __print_indent 1 \
    "while OPTARG= && [ \"\${${__rest}}\" != end ] && [ \$# -gt 0 ]; do"
  __print_indent 2 "case \$1 in"
  __print_indent 3 "--?*=*)"
  __print_indent 4 "OPTARG=\$1; shift"
  # shellcheck disable=2016
  __print_get_arg '"${OPTARG%%\=*}" "${OPTARG#*\=}"'
  __print_indent 4 ";;"
  __print_indent 3 "--no-*|--without-*)"
  __print_indent 4 "unset OPTARG"
  __print_indent 4 ";;"
  [ "${__params}" ] && {
    __print_indent 3 "-[${__params}]?*)"
    __print_indent 4 "OPTARG=\$1; shift"
    # shellcheck disable=2016
    __print_get_arg '"${OPTARG%"${OPTARG#??}"}" "${OPTARG#??}"'
    __print_indent 4 ";;"
  }
  [ "${__flags}" ] && {
    __print_indent 3 "-[${__flags}]?*) OPTARG=\$1; shift"
    # shellcheck disable=2016
    __print_get_arg '"${OPTARG%"${OPTARG#??}"}" -"${OPTARG#??}"'
    # shellcheck disable=2016
    __print_indent 4 \
      'case $2 in --*) set -- "$1" unknown "$2" && '"${__rest}"'=end; esac'
    __print_indent 4 'OPTARG='
    __print_indent 4 ';;'
  }
  __print_indent 2 "esac"
  # shellcheck disable=2016
  __print_indent 2 'case $1 in'
  __done_initial=true && "$1"
  __print_indent 2 "esac"
  __print_indent 1 "done"
  __print_indent 0 "}"
}

function __print_validate {
  set -- "${__validate}" "$1"
  [ "$1" ] && __print_indent 4 "$1 || { set -- ${1%% *}:\$? \"\$1\" $1; break; }"
  __print_indent 4 "$(__prepend_export "$2=\$OPTARG")"
}

# @section Functions work in spec of script or function via
#          `dybatpho::generate_from_spec`.
#######################################
# @description Setup global settings for getting options (mandatory) in spec
# of script or function
# @arg $1 string Description of sub-command/root command
# @arg $2 string Variable name for getting rest arguments after parse options.
#                `-` if want to omit
# @arg $3 string Sub-command string to invoke, `-` if want to invoke from root
# @arg $4 action:statement Name of function to call after parse options
# @arg $@ key:value Settings `key:value` for sub-command/root command
# @exitcode 0 exit code
#######################################
function dybatpho::opts::setup {
  dybatpho::expect_args __description __rest __command -- "$@"

  if dybatpho::is false "${__done_initial}"; then
    [ "${__rest#-}" ]
    shift 3
    while dybatpho::still_has_args "$@" && shift; do
      __parse_key_value "$1" "__"
    done
    __define_var "${__rest}"
  fi
}

#######################################
# @description Define an option that take no argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch_or_key:value Other switches and settings `key:value` of this option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::flag {
  local var
  dybatpho::expect_args __description var -- "$@"

  __parse_opt false "$@"
  if dybatpho::is false "${__done_initial}"; then
    __define_var "${var}"
  else
    __print_indent 3 "${__switch})"
    # shellcheck disable=2016
    __print_indent 4 '[ "${OPTARG:-}" ] && OPTARG=${OPTARG#*\=} && set "noarg" "$1" && break'
    __print_indent 4 "eval '[ \${OPTARG+x} ] &&:' && OPTARG=${__on} || OPTARG=${__off}"
    # shellcheck disable=2016
    __print_validate "${var}" '$OPTARG'
    __print_indent 4 ";;"
  fi
}

#######################################
# @description Define an option that take an argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch_or_key:value Other switches and settings `key:value` of this option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::param {
  local var
  dybatpho::expect_args __description var -- "$@"

  __parse_opt true "$@"
  if dybatpho::is false "${__done_initial}"; then
    __define_var "${var}"
  else
    __print_indent 3 "${__switch})"
    # shellcheck disable=2016
    __print_indent 4 '[ $# -le 1 ] && set "required" "$1" && break'
    # shellcheck disable=2016
    __print_indent 4 'OPTARG=$2'
    # shellcheck disable=2016
    __print_validate "${var}" '$OPTARG'
    __print_indent 4 "shift"
    __print_indent 4 ";;"
  fi
}

#######################################
# @description Define an option that display only
# @arg $1 string Description of option to display
# @arg $@ switch_or_key:value Other switches and settings `key:value` of this option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::disp {
  dybatpho::expect_args __description -- "$@"

  __parse_opt false "$@"
}

#######################################
# @description Define a sub-command in spec
# @arg $1 string Name of function that has spec of sub-command
#######################################
function dybatpho::opts::cmd {
  dybatpho::expect_args __command_spec -- "$@"

  __parse_opt false "$@"
}

# @section Functions to parse spec and put value of options to variable with
# corresponding name

#######################################
# @description Define spec of parent function or script, spec contains below commands
# @arg $1 string Name of function that has spec of parent function or script
# @arg $2 string Name of function will be executed after parse, default is empty
#                (don't execute anything)
# @exitcode 0 exit code
#######################################
function dybatpho::generate_from_spec {
  local spec
  dybatpho::expect_args spec -- "$@"
  shift

  local IFS=" "                           # For get list of options, separated by space
  local __command="" __rest=""            # For get current sub-command (root is "") and all rest arguments
  local __error="" __validate=""          # For get function name of custom error handler, validation and
  local __flags="" __params=""            # For get all flags and params of command
  local __on="1" __off="" __init="@empty" # For handle argument of param, effective for rest arguments and options
  local __export="true"                   # For handle export variable of `dybatpho::opts::*` commands via name
  local __optional="true"                 # For set flag is optional or required
  local __action=""                       # For get action after parse all options
  local __description=""                  # For get description of command/option via `dybatpho::opts::*` command
  local __switch=""                       # For get switch of options
  dybatpho::debug \
    "Generated script:\n-----\n$(__generate_logic "${spec}")\n-----"
  eval "$(__generate_logic "${spec}")"
  "dybatpho::opts::parse::${spec}"
}

#######################################
# @description Get help description for option with a spec from
# `dybatpho::opts::flag`, `dybatpho::opts::param`
# @arg $1 bool Flag that defined option that take argument in spec
# @arg $@ string Arguments pass from `dybatpho::opts::(flag|param)`
# @exitcode 0 exit code
#######################################
function _help_opt {
  :
}

#######################################
# @description Show help description of root command/sub-command
# @stdout Help description
#######################################
function dybatpho::generate_help {
  echo "
    dybatpho::print 'Usage: ${0##*/} ${__command#-} [options...] [arguments...]'
    dybatpho::print '${__description}'
    dybatpho::print 'Options:'
  "
}
