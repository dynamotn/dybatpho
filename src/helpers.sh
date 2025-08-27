#!/usr/bin/env bash
# @file helpers.sh
# @brief Utilities for writing efficient script
# @description
#   This module contains functions to write efficient script.
#
# **DYBATPHO_REPL_HISTORY_FILE** (string): Path of REPL history file for dybatpho, used in `dybatpho::breakpoint`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

DYBATPHO_REPL_HISTORY_FILE="${HOME}/.cache/dybatpho_repl.history"

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

  ((is_error)) && dybatpho::die "${FUNCNAME[1]:--}: Expected variable names, \`--\`, and args:" 'arg1 .. argN -- "$@"'

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
# @description Check that function still has next argument after shift.
# This function is useful to check argument of function that you don't now
# count of arguments when triggered, and you just only need to process next
# argument
# @example
#   while dybatpho::still_has_args "$@" && shift; do
#     echo "Function has next argument is $1"
#   done
# @exitcode 0 Still has an argument
# @exitcode 1 Not has any arguments
#######################################
function dybatpho::still_has_args {
  [ $# -gt 1 ]
}

#######################################
# @description Check that environment variables are set
# @example
#   dybatpho::expect_envs ENV_VAR1 ENV_VAR2
# @arg $@ string Environment variables to check
# @exitcode 1 Stop script if not set
#######################################
function dybatpho::expect_envs {
  for arg in "$@"; do
    if [ -z "${!arg:-}" ]; then
      dybatpho::die "Environment variable \`${arg}\` isn't set."
    fi
  done
}

#######################################
# @description Check command dependency is installed.
# @arg $1 string Command need to be installed
# @arg $2 number Exit code if not installed (default 127)
# @exitcode 127 Stop script if command isn't installed
# @exitcode 0 Otherwise run seamlessly
# @exitcode other Exit code if command isn't installed and second argument is set
#######################################
function dybatpho::require {
  hash "$1" > /dev/null 2>&1 || dybatpho::die "$1 isn't installed" "${2:-127}"
}

#######################################
# @description Check input is matching with a condition
# @arg $1 string Condition (command|function|file|dir|link|exist|readable|writable|executable
# |set|empty|number|int|true|false)
# @arg $2 string Input need to check
# @exitcode 0 If matched
# @exitcode 1 If not matched
#######################################
function dybatpho::is {
  local condition input
  dybatpho::expect_args condition input -- "$@"
  case "${condition}" in
    command)
      command -v "${input}"
      return "$?"
      ;;
    function)
      declare -F "${input}"
      return "$?"
      ;;
    file)
      [ -f "${input}" ]
      return "$?"
      ;;
    dir)
      [ -d "${input}" ]
      return "$?"
      ;;
    link)
      [ -L "${input}" ]
      return "$?"
      ;;
    exist)
      [ -e "${input}" ]
      return "$?"
      ;;
    readable)
      [ -r "${input}" ]
      return "$?"
      ;;
    writeable)
      [ -w "${input}" ]
      return "$?"
      ;;
    executable)
      [ -x "${input}" ]
      return "$?"
      ;;
    set)
      [ "${input+x}" = "x" ] && [ "${#input}" -gt "0" ]
      return "$?"
      ;;
    empty)
      [ "${input+x}" = "x" ] && [ "${#input}" -eq "0" ]
      return "$?"
      ;;
    number)
      printf -- '%f' "${input:-null}"
      return "$?"
      ;;
    int)
      printf -- '%d' "${input:-null}"
      return "$?"
      ;;
    true)
      case "${input}" in
        0 | [tT][rR][uU][eE] | [yY][eE][sS] | [oO][nN]) return 0 ;;
        '' | *) return 1 ;;
      esac
      ;;
    false)
      case "${input}" in
        1 | [fF][aA][lL][sS][eE] | [nN][oO] | [oO][fF][fF]) return 0 ;;
        '' | *) return 1 ;;
      esac
      ;;
  esac > /dev/null 2>&1 # kcov(skip)
  return 1
}

#######################################
# @description Retry a command multiple times until it succeeds,
# with escalating delay between attempts.
# @arg $1 number Number of retries
# @arg $2 string Command to run
# @arg $3 string Description of command
# @exitcode 0 Run command successfully
# @exitcode 1 Out of retries
#######################################
function dybatpho::retry {
  local retries command
  dybatpho::expect_args retries command -- "$@"
  shift 2
  local exit_code count delay

  count=0
  until eval "${command}"; do
    exit_code="$?"
    count="$((count + 1))"
    if [ "${count}" -le "${retries}" ]; then
      delay="$((2 * count))"
      dybatpho::progress "Retrying in ${delay} seconds (${count}/${retries})..."
      sleep "${delay}" || true
    else
      # Out of retries :(
      dybatpho::warn "No more retries left to run ${1:-${command}}."
      return "${exit_code}"
    fi
  done
}

#######################################
# @description Hit breakpoint to debug script.
# @noargs
#######################################
function dybatpho::breakpoint {
  local dybatpho_key_pressed
  local dybatpho_section="--------------------------------------------------------------------------------"
  local dybatpho_help="${dybatpho_section}
    d: run debugger
    c: display source file
    o: list options
    p: list parameters
    a: list indexed array
    A: list associative array
    q: quit"
  local source_file="${BASH_SOURCE[1]:-bash}"
  __log fatal "Breakpoint hit. Current line: ${source_file}:${BASH_LINENO[0]}" stderr "1;36"
  while true; do
    printf "%s\n" "${dybatpho_help}" >&2
    read -n1 -s -r dybatpho_key_pressed
    case "${dybatpho_key_pressed}" in
      o) # kcov(skip)
        shopt -s >&2
        set -o >&2
        ;;
      p) declare -p >&2 ;;
      a) declare -a >&2 ;;
      A) declare -A >&2 ;;
      q) # kcov(skip)
        echo "${dybatpho_section}" >&2
        return
        ;;
      # kcov(disabled)
      d)
        set +xv              # Disable tracing for better verbose output
        set +eou pipefail    # Disable strict mode
        set +E && trap - ERR # Disable exit and error handling
        if [[ -f ${DYBATPHO_REPL_HISTORY_FILE} ]]; then
          history -r "${DYBATPHO_REPL_HISTORY_FILE}"
        fi
        # shellcheck disable=SC2162
        while read -e -p "Debugger (Ctrl-d to exit)> " line; do
          [[ "${line}" == "exit" ]] && break
          if [[ "${line}" =~ ^rm ]] || [[ "${line}" =~ ^dd ]]; then
            dybatpho::error "Ignore dangerous command."
            continue
          fi
          echo "${line}" >> "${DYBATPHO_REPL_HISTORY_FILE}"
          history -s "${line}"
          eval "${line} >&2"
        done
        echo >&2
        set -eou pipefail # Enable strict mode
        dybatpho::is true "${DYBATPHO_USED_ERR_HANDLER}" \
          && dybatpho::register_err_handler      # Rerun register_err_handler
        [ "${LOG_LEVEL}" == "trace" ] && set -xv # Re-enable tracing if needed
        ;;
      c)
        if [ "${source_file}" != "bash" ]; then
          echo "${dybatpho_section}" >&2
          dybatpho::show_file "${BASH_SOURCE[1]}"
        fi
        ;;
      # kcov(enabled)
      *) continue ;;
    esac
  done # kcov(skip)
}
