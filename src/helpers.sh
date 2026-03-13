#!/usr/bin/env bash
# @file helpers.sh
# @brief Utilities for common shell-script helper patterns.
# @description
#   `src/helpers.sh` groups together the small building blocks that many other
#   modules rely on:
#
#   - validating function arguments
#   - checking environment and tool dependencies
#   - testing common conditions
#   - retrying flaky commands
#   - opening an interactive breakpoint
# @usage
#   ### When to use this module
#
#   Use `helpers.sh` when you want to:
#
#   - make shell functions fail fast on bad input
#   - avoid repeating `command -v`, `[[ -f ... ]]`, `[[ -d ... ]]`, and similar checks
#   - retry transient commands without rewriting loop logic
#   - inspect runtime state interactively while debugging a script
#
#   ### Common patterns
#
#   #### Validate function input
#
#   ```bash
#   function copy_file() {
#     local src dst
#     dybatpho::expect_args src dst -- "$@"
#     cp "${src}" "${dst}"
#   }
#   ```
#
#   #### Require environment + binary before running
#
#   ```bash
#   dybatpho::expect_envs API_TOKEN
#   dybatpho::require curl
#   ```
#
#   #### Guard conditions
#
#   ```bash
#   if ! dybatpho::is file "${config_path}"; then
#     dybatpho::die "Config file not found: ${config_path}"
#   fi
#   ```
#
#   #### Retry transient network operations
#
#   ```bash
#   dybatpho::retry 4 "curl -fsSL '${health_url}'" "service health check"
#   ```
#
#   #### Add an optional breakpoint
#
#   ```bash
#   dybatpho::is true "${DEBUG_BREAK:-false}" && dybatpho::breakpoint
#   ```
# @see
#   - `example/process_ops.sh`
# @tip Combine `dybatpho::expect_envs` and `dybatpho::require` near the top of entrypoint scripts to fail fast on missing configuration or dependencies.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_REPL_HISTORY_FILE string History file used by `dybatpho::breakpoint`
DYBATPHO_REPL_HISTORY_FILE="${HOME}/.cache/dybatpho_repl.history"

#######################################
# @description Validate function arguments and assign them into named local variables.
# @example
#   local arg1 arg2 .. argN
#   dybatpho::expect_args arg1 arg2 .. argN -- "$@"
#
# @tip Prefer calling this at the top of reusable functions instead of manually unpacking `$@`
# @exitcode 1 Stop the script if the specification is invalid or required arguments are missing
# @exitcode 0 Assign arguments to the requested variable names and return successfully
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
    [[ "${variable_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "${FUNCNAME[1]:--}: Invalid variable name: ${variable_name}"
    if ! (($#)); then
      dybatpho::die "${FUNCNAME[1]:--}: Expected args: ${variable_names[*]:-}"
    fi
    printf -v "${variable_name}" '%s' "$1"
    shift
  done
}

#######################################
# @description Check whether at least one more positional argument remains after the current one.
# This helper is useful while manually parsing a shifting argument list.
# @example
#   while dybatpho::still_has_args "$@" && shift; do
#     echo "Function has next argument is $1"
#   done
# @exitcode 0 Still has an argument
# @exitcode 1 No additional arguments remain
#######################################
function dybatpho::still_has_args {
  [ $# -gt 1 ]
}

#######################################
# @description Ensure that required environment variables are set.
# @example
#   dybatpho::expect_envs ENV_VAR1 ENV_VAR2
# @arg $@ string Environment variables to check
# @exitcode 1 Stop the script if any variable is unset or empty
#######################################
function dybatpho::expect_envs {
  for arg in "$@"; do
    if [ -z "${!arg:-}" ]; then
      dybatpho::die "Environment variable \`${arg}\` isn't set."
    fi
  done
}

#######################################
# @description Ensure that a required command is installed.
# @arg $1 string Command that must be available
# @arg $2 number Exit code if not installed (default 127)
# @tip Prefer this over repeating inline `command -v ... || exit` checks throughout a script
# @exitcode 127 Stop script if command isn't installed
# @exitcode 0 The command is available
# @exitcode other Exit code if command isn't installed and second argument is set
#######################################
function dybatpho::require {
  hash "$1" > /dev/null 2>&1 || dybatpho::die "$1 isn't installed" "${2:-127}"
}

#######################################
# @description Check whether a value matches a supported shell-oriented condition.
# @arg $1 string Condition (command|function|file|dir|link|exist|readable|writeable|executable|set|empty|number|int|true|false)
# @arg $2 string Value to test
# @tip Use this helper to keep calling code readable instead of scattering shell test syntax across the script
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
# @description Retry a shell command with escalating delays until it succeeds or retries are exhausted.
# @example
#   dybatpho::retry 3 "curl -fsSL '${url}'" "health check"
#
# @arg $1 number Number of retries
# @arg $2 string Shell command string to run
# @arg $3 string Optional short description for retry logs
# @exitcode 0 The command eventually succeeds
# @exitcode 1 The command never succeeds and returns 1 on the final attempt
# @tip The command is executed with `eval`, so pass it as one shell command string
# @tip Pass a short description when the raw command is noisy so retry logs stay readable
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
# @description Open an interactive breakpoint for debugging a running script.
# @noargs
# @env DYBATPHO_REPL_HISTORY_FILE string Override where REPL history is persisted between breakpoint sessions
# @tip This helper is intended for interactive local debugging, not unattended CI or production runs
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
          if [[ "${line}" =~ ^[[:space:]]*(rm|dd)([[:space:]]|$) ]]; then
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
