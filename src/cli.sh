#!/usr/bin/env bash
# @file cli.sh
# @brief Utilities for getting options when calling command from CLI or in script with CLI-like format
# @description
#   This module contains functions to define, get options (flags, parameters...) for command or subcommand
#   when calling it from CLI or in shell script.
#
# Theses are type of function arguments that defined in this file
#
# |Type|Description|
# |----|-----------|
# |`switch`|A type as a string with format `-?`, `--*`, `--no-*`, `--with-*`, `--without-*`, `--{no-}*` (expand to use both `--flag` and `--no-flag`), `--with{out}-*` (expand to `--with-flag` and `--without-flag`)|
# |`key:value`|`key1:value1` style arguments, if `:value` is omitted, it is the same as `key:key`|
#
# ### Key-value type
# |Format|Description|
# |------|-----------|
# |`action:<code>`|List of multiple statements, split by `;` as `key:value`, eg `"action:foo; bar"`|
# |`init:<method>`|Method to initial value of variable from spec by variable name with key `init:`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`, see `Initial variable kind` below|
# |`on:<string>`|The positive value whether option is switch as `--flag`, `--with-flag`, default is `"true"`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
# |`off:<string>`|The negative value whether option is not presence, or as `--no-flag`, `--without-flag`, default is empty `''`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
# |`export:<bool>`|Export variable in spec command or not, default is true, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
# |`optional:<bool>`|Used for `dybatpho::opts::param` whether option is optional, default is false (restrict)|
# |`validate:<code>`|Validate statements for options, eg: `"_function1 \$OPTARG"` (must have `\$OPTARG` to pass param value of option), used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
# |`error:<code>`|Custom error messages function for options, eg: `"_show_error1"`,  used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
#
# ### Initial variable kind
# |Format|Description|
# |------|-----------|
# |`init:@empty`|Initial value as empty. It's default behavior|
# |`init:@on`|Initial value with same as `on` key|
# |`init:@off`|Initial value with same as `off` key|
# |`init:@unset`|Unset the variable|
# |`init:@keep`|Do not initialization (Use the current value as it is)|
# |`init:action:<code>`|Initialize by run statement(s) and not assigned to variable|
# |`init:=<code>`| Initialize by plain code and assigned to variable|
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

DYBATPHO_CLI_DEBUG="${DYBATPHO_CLI_DEBUG:-false}"

# @section Internal functions
# @description Functions are triggered by `dybatpho::generate_from_spec`

#######################################
# @description Parse options with a spec from `dybatpho::opts::flag`,
#              `dybatpho::opts::param`
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
    __validate="" __on="true" __off="" __export="true" __optional="false" __switch=""
    shift # ignore flag $1
    while dybatpho::still_has_args "$@" && shift; do
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
# @description Assign the quoted string to a variable
# @arg $1 string Variable name to be assigned
# @arg $2 string Input string to be quoted
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

  local IFS=" "                           # For get list of options, separated by space
  local __rest=""                         # For get all rest arguments
  local __error="" __validate=""          # For get function name of custom error handler, validation and
  local __flags="" __params=""            # For get all flags and params of command
  local __on="1" __off="" __init="@empty" # For handle argument of param, effective for rest arguments and options
  local __export="true"                   # For handle export variable of `dybatpho::opts::*` commands via name
  local __optional="true"                 # For set flag is optional or required
  local __action="" __setup_action=""     # For get action after parse all options and action of each options in spec
  local __description=""                  # For get description of command/option via `dybatpho::opts::*` command
  local __switch=""                       # For get switch of options
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
      __print_indent 5 "${sub_spec#*:})"
      __print_indent 6 "shift"
      __print_indent 6 "dybatpho::opts::parse::${sub_spec%%:*} \$@"
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
  __print_indent 2 "${__setup_action}"
  __print_indent 2 'return 0'
  __print_indent 1 '}'
  __print_indent 1 'case $1 in'
  __print_indent 2 'unknown) set "Unrecognized option: $2" "$@" ;;'
  __print_indent 2 'noarg) set "Does not allow an argument: $2" "$@" ;;'
  __print_indent 2 'needarg) set "Requires an argument: $2" "$@" ;;'
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
# @description Get help description for options from spec
# @exitcode 0 exit code
#######################################
function __generate_help {
  eval "
    dybatpho::print 'Usage: ${0##*/} [options...] [arguments...]'
    dybatpho::print 'Options:'
  "
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
  __print_indent 4 "$(__prepend_export "$2=\$OPTARG")"
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
  dybatpho::expect_args __description __rest -- "$@"
  shift

  [ "${__rest#-}" ] || __rest="__rest"
  if dybatpho::is false "${__done_initial}"; then
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
  local var
  dybatpho::expect_args __description var -- "$@"

  __parse_opt false "$@"
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
    if dybatpho::is false "${__optional}"; then
      __print_indent 4 '[ $# -le 1 ] && set "needarg" "$1" && break'
      __print_indent 4 'OPTARG=$2'
    else
      __print_indent 4 'set -- "$1" "$@"'
      __print_indent 4 '[ ${OPTARG+x} ] && {'
      __print_indent 5 'case $1 in --no-*|--without-*) set "noarg" "${1%%\=*}"; break; esac'
      __print_indent 5 '[ "${OPTARG:-}" ] && { shift; OPTARG=$2; } ||' "OPTARG=${__on}"
      __print_indent 4 "} || OPTARG=${__off}"
    fi
    __print_validate "${var}" '$OPTARG'
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
  dybatpho::expect_args __description -- "$@"

  __parse_opt false "$@"
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
# @description Show help description of root command/sub-command
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Help description
#######################################
function dybatpho::generate_help {
  local spec
  dybatpho::expect_args spec -- "$@"

  local gen_file
  dybatpho::create_temp gen_file ".sh" "genhelp"
  __generate_logic "${spec}" - "$@" >> "${gen_file}"
  dybatpho::cleanup_file_on_exit "${gen_file}"
  if dybatpho::is true "${DYBATPHO_CLI_DEBUG}"; then
    dybatpho::debug_command "Generate script of \"${spec}\" - \"$*\"" "dybatpho::show_file '${gen_file}'"
  fi
  # shellcheck disable=1090
  . "${gen_file}"
  __generate_help "${spec}"
}
