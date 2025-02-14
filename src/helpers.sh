#!/usr/bin/env bash
# @file helpers.sh
# @brief Utilities for writing efficient script
# @description
#   This module contains functions to write efficient script.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"

#######################################
# @description Validate argument when invoke function. It adds a small performance penalty but is a sane option.
# @example
#   local arg1 arg2 .. argN
#   dybatpho::expect_args arg1 arg2 .. argN -- "$@"
#
# @exitcode 1 Stop script if not correct spec: enough variable names to get, `--`, and list of arguments to pass `$@`
#             or not have enough arguments that follow by spec
# @exitcode 0 Otherwise run seamlessly, pass value of argument to variable name
#######################################
function dybatpho::expect_args {
  local variable_names=()
  local is_error=1

  while (($#)); do
    if [ "$1" = -- ]; then
      is_error=0
      shift
      break
    fi
    variable_names+=("$1")
    shift
  done

  ((${is_error})) && dybatpho::die "${FUNCNAME[1]:--}: Expected variable names, \`--\`, and args:" 'arg1 .. argN -- "$@"'

  local variable_name
  for variable_name in "${variable_names[@]}"; do
    if ! (($#)); then
      dybatpho::die "${FUNCNAME[1]:--}: Expected args: ${variable_names[*]:-}"
    fi
    eval "${variable_name}=\$1"
    shift
  done
}

#######################################
# @description Check command dependency is installed.
# @arg $1 string Command need to be installed
# @exitcode 127 Stop script if command isn't installed
# @exitcode 0 Otherwise run seamlessly
#######################################
function dybatpho::require {
  hash "$1" || dybatpho::die "$1 isn't installed" 127
}

#######################################
# @description Check input is matching with a condition
# @arg $1 string Condition (command|file|dir|link|exist|readable|writing|executable|set|empty|number|int|true|false)
# @arg $2 string Input need to check
# @exitcode 0 If matched
# @exitcode 1 If not matched
#######################################
function dybatpho::is {
  local condition input
  dybatpho::expect_args condition input -- "$@"
  case "$condition" in
    command)
      command -v "$input"
      return "${?}"
      ;;
    file)
      [ -f "$input" ]
      return "${?}"
      ;;
    dir)
      [ -d "$input" ]
      return "${?}"
      ;;
    link)
      [ -L "$input" ]
      return "${?}"
      ;;
    exist)
      [ -e "$input" ]
      return "${?}"
      ;;
    readable)
      [ -r "$input" ]
      return "${?}"
      ;;
    writeable)
      [ -w "$input" ]
      return "${?}"
      ;;
    executable)
      [ -x "$input" ]
      return "${?}"
      ;;
    set)
      [ "${input+x}" = "x" ] && [ "${#input}" -gt "0" ]
      return "${?}"
      ;;
    empty)
      [ "${input+x}" = "x" ] && [ "${#input}" -eq "0" ]
      return "${?}"
      ;;
    number)
      printf -- '%f' "${input:-null}" > /dev/null 2>&1
      return "${?}"
      ;;
    int)
      printf -- '%d' "${input:-null}" > /dev/null 2>&1
      return "${?}"
      ;;
    true)
      case "$input" in
        0 | [tT][rR][uU][eE] | [yY][eE][sS] | [oO][nN]) return 0 ;;
        '' | *) return 1 ;;
      esac
      ;;
    false)
      case "$input" in
        1 | [fF][aA][lL][sS][eE] | [nN][oO] | [oO][fF][fF]) return 0 ;;
        '' | *) return 1 ;;
      esac
      ;;
  esac 2>&1 > /dev/null # kcov(skip)
  return 1
}
