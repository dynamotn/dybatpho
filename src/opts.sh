#!/usr/bin/env bash
# @file opts.sh
# @brief Utilities for getting options when calling command in script or from CLI
# @description
#   This module contains functions to define, get options (flags, parameters...) for command or subcommand
#   when calling it from CLI or in shell script.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @section Theses are type of functions' arguments that defined in this file
# - `switch`: A type as a string with format `-?`, `--*`, `--no-*`, `--with-*`, `--without-*`,
#             `--{no-}*` (expand to use both `--flag` and `--no-flag`),
#             `--with{out}-*` (expand to `--with-flag` and `--without-flag`)
# - `statement`: A function name with arguments with prefix 'action:', eg `action:foo` or `"action:foo 1 2 3"`
# - `code`: List of multiple statements with prefix 'action:', split by `;`, eg `"action:foo; bar"`
# - `key:value`: `key1:value1` style arguments, if `:value` is omitted, it is the same as `key:key`
# - `init_method`: Method to initial value of variable from spec by variable name, include: `@on`, `@off`, `@unset`, `@keep`, `@empty`, `@export`
#   - `@on`: Initial value with same as `on` key, whether option is switch as `--flag`, `--with-flag`, default is `1`
#   - `@off`: Initial value with same as `off` key, whether option is not presence, or as `--no-flag`, `--without-flag`, default is empty `''`
#   - `@unset`: Unset the variable
#   - `@keep`: Do not initialization (Use the current value as it is)

# @section Functions are triggered by `dybatpho::generate_from_spec`
#######################################
# @description Parse options with a spec from `dybatpho::opts::flag`,
# `dybatpho::opts::param`
# @arg $1 bool Flag that defined option that take argument in spec
# @arg $@ string Passed arguments from `dybatpho::opts::(flag|param)`
# @exitcode 0
#######################################
function __parse_opt {
  local need_argument=$1 && shift
  while dybatpho::still_has_args "$@" && shift; do
    case $1 in
      [!-]*) __key_value "$1" "__" ;;
      -?)
        [ "${need_argument}" ] && __params="${__params}${1#-}" || __flags="${__flags}${1#-}"
        ;;
    esac
  done
}

#######################################
# @description Write script with indentation to stdout, trigger by `__generate_logic`
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
# @description Condition write script code
#######################################
__code() {
  [ "${2#:}" = "$2" ] && c=3 || c=4
  eval "[ ! \${${c}:+x} ] || __print_indent $1 \"\$${c}\""
}

#######################################
# @description Define variable from spec from `dybatpho::opts::flag`,
# `dybatpho::opts::param`
# @arg $1 string Name of variable to be defined
#######################################
function __define_var {
  case ${__init} in
    @keep) : ;;
    @empty) __code 0 "$1" "$1=''" ;;
    @unset) __code 0 "$1" "unset $1 ||:" "unset OPTARG ||:; ${1#:}" ;;
    @on) __init=${__on} ;;
    @off) __init=${__off} ;;
    *)
      case ${__init} in [!=]*)
        __print_indent 0 "${__init}"
        return 0
        ;;
      esac
      # quote __init "${__init#=}"
      __code 0 "$1" "${export:+export }$1=${__init}" "OPTARG=${__init}; ${1#:}"
      ;;
  esac
}

#######################################
# @description Extract key value from spec with format `x:y`, to get settings of option
# @arg $1
# @arg $2 string Prefix of key to set as variable
#######################################
__key_value() {
  eval "${2-}${1%%:*}=\${1#*:}"
}

# Generate logic to eval in below commands
__generate_logic() {
  "$1"
  # __print_indent 0 "${__rest:?}=''"
  __print_indent 0 "dybatpho::opts::parse::${1}() {"
  __print_indent 1 "OPTIND=$(($# + 1))"
  __print_indent 1 "while OPTARG= && [ \"\${${__rest}}\" != x ] && [ \$# -gt 0 ]; do"
  __print_indent 2 "case \$1 in"
  __print_indent 2 "$1) OPTARG=\$1; shift"
  __print_indent 2 "esac"
  __print_indent 1 "done"
  __print_indent 0 "}"
}

# @section Functions work in spec of script or function via `dybatpho::generate_from_spec`.
#######################################
# @description Setup global settings for getting options (mandatory) in spec
# of script or function
# @arg $1 string Description of sub-command/root command
# @arg $2 string Variable name for getting rest arguments after parse options.
#                `-` if want to omit
# @arg $3 string Sub-command string to invoke, `-` if want to invoke from root
# @arg $@ key_value Key value of settings for sub-command/root command with keys as below:
#   - `error`:
# @exitcode 0 exit code
#######################################
function dybatpho::opts::setup {
  dybatpho::expect_args __description __rest __command -- "$@"
  [ "${__rest#-}" ]
  shift 3
  while dybatpho::still_has_args "$@" && shift; do
    __key_value "$1" "__"
  done
  __define_var "${__rest}"
}

#######################################
# @description Define an option that take no argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $3 switch Switch of option
# @arg $@ switch Other switches and settings (key:value) of this option:
#   - `export:<bool>`: Export variable in $2 or not
#   - `init:<init value>`: Initial value
#   - `on:<string>`:
# @exitcode 0 exit code
#######################################
function dybatpho::opts::flag {
  local var
  dybatpho::expect_args __description var switch -- "$@"

  __parse_opt false "$@"
  __define_var "${var}"
}

#######################################
# @description Define an option that take an argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $3 switch Switch of option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::param {
  local var switch
  dybatpho::expect_args __description var switch -- "$@"

  __parse_opt true "$@"
  __define_var "${var}"
}

#######################################
# @description Define an option that display only
# @arg $1 string Description of option to display
# @arg $2 string Action to render
# @arg $3 switch Switch of option
# @exitcode 0 exit code
#######################################
function dybatpho::opts::disp {
  local action
  dybatpho::expect_args __description action -- "$@"

  __parse_opt false "$@"
}

#######################################
# @description Define a sub-command in spec
# @arg $1 string Description of sub-command to display
# @arg $2 string Sub-command string
# @arg $3 switch Name of function will be executed, # @exitcode 0 exit code
#######################################
function dybatpho::opts::cmd {
  local action
  dybatpho::expect_args __description action -- "$@"

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
  local __error=""                        # For get function name of custom error handler
  local __on="1" __off="" __init="@empty" # For handle argument of param, effective for rest arguments and options
  local __export=false                    # For handle export variable of `dybatpho::opts::*` commands via name
  local __flags="" __params=""            # For get all flags and params of command
  local __optional=true                   # For set flag is optional or required
  local __action=""                       # For get description of command/option via `dybatpho::opts::*` command
  local __description=""                  # For get description of command/option via `dybatpho::opts::*` command
  dybatpho::debug "Generated script:
------
$(__generate_logic "${spec}")
------
"
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
