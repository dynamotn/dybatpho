# shellcheck shell=bash
# This file is sourced by `init.sh` and never run, so it carries no executable
# bit; it lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe; it uses `eval`,
# which is how the spec engine builds a parser; it parses its own arguments, so
# the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG033,BSG040,BSG051
# @file helpers.sh
# @brief Utilities for common shell-script helper patterns.
# @namespace dybatpho
# @description
#   `src/helpers.sh` groups together the small building blocks that many other
#   modules rely on:
#
#   - validating function arguments
#   - checking environment and tool dependencies
#   - testing common conditions
#   - checking several commands or env vars at once
#   - choosing the first usable value from fallbacks
#   - assigning default env values
#   - retrying flaky commands
#   - opening an interactive breakpoint
#   - asking the library about itself
#
#   That last one is `dybatpho::provides`, `dybatpho::describe` and
#   `dybatpho::function_list`. The library documents itself in `docs/`, which
#   answers the question while you are reading; these answer it from the
#   running shell, where the question actually comes up. They ask Bash rather
#   than the filesystem: `declare -F` under `extdebug` reports the file and line
#   a function was defined at, and the documentation comment is sitting just
#   above that line in the source that was loaded. They live here, in a core
#   module, because a helper you have to remember to load is one you will not
#   reach for at a prompt.
# @usage
#   ### When to use this module
#
#   Use `helpers.sh` when you want to:
#
#   - make shell functions fail fast on bad input
#   - avoid repeating `command -v`, `[[ -f ... ]]`, `[[ -d ... ]]`, and similar checks
#   - validate that any or all required commands and env vars are present
#   - choose the first non-empty value from environment, defaults, or arguments
#   - assign fallback defaults into environment variables
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
#   #### Pick the first configured value
#
#   ```bash
#   api_host="$(dybatpho::coalesce "${API_HOST:-}" "${FALLBACK_HOST:-}" "http://localhost:8080")"
#   ```
#
#   #### Pick the first available command
#
#   ```bash
#   json_tool="$(dybatpho::coalesce_cmd jq yq python3)"
#   ```
#
#   #### Add an optional breakpoint
#
#   ```bash
#   dybatpho::is true "${DEBUG_BREAK:-false}" && dybatpho::breakpoint
#   ```
# @see
#   - `example/process_ops.sh`
# @tip Combine `dybatpho::expect_envs` and `dybatpho::require` near the top of entrypoint scripts to fail fast on
#   missing
#   configuration or dependencies.
# The `dybatpho::is` family and the lookups below are questions, not work:
# a caller tests them, so `set -e` is not meant to reach inside.
# shellcheck disable=SC2310
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_RETRY_BASE_DELAY number First retry delay in seconds (default `2`)
# @env DYBATPHO_RETRY_MAX_DELAY number Longest a single retry waits (default `30`)
# @env DYBATPHO_RETRY_JITTER bool Add up to one base delay of random jitter (default `false`)
DYBATPHO_RETRY_BASE_DELAY=${DYBATPHO_RETRY_BASE_DELAY:-2}
DYBATPHO_RETRY_MAX_DELAY=${DYBATPHO_RETRY_MAX_DELAY:-30}
DYBATPHO_RETRY_JITTER=${DYBATPHO_RETRY_JITTER:-false}

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
# @arg $@ string Variable names, then `--`, then the arguments to bind
#######################################
function dybatpho::expect_args {
  local -a variable_names=()
  local is_error=1

  while (($#)); do
    if [[ "$1" = -- ]]; then
      is_error=0
      shift
      break
    fi
    variable_names+=("$1")
    shift
  done

  ((is_error)) \
    && dybatpho::die "${FUNCNAME[1]:--}: Expected variable names, \`--\`, and args:" 'arg1 .. argN -- "$@"' # kcov(skip)

  local variable_name
  for variable_name in "${variable_names[@]}"; do
    [[ "${variable_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "${FUNCNAME[1]:--}: Invalid variable name: ${variable_name}"
    if ! (($#)); then
      dybatpho::die "${FUNCNAME[1]:--}: Expected args: ${variable_names[*]:-}" # kcov(skip)
    fi
    printf -v "${variable_name}" '%s' "$1"
    shift
  done
}

#######################################
# @description Check that a caller-supplied variable name can safely be bound to
#   a nameref, and stop the script when it cannot.
#
#   A function that writes its answer into a variable the caller names does it
#   with `local -n`, and that has a failure mode with no error in it. When the
#   name the caller passes is also the name of one of the function's own local
#   variables, the nameref resolves to *that* local instead of to the caller's
#   variable, and every write lands somewhere the caller will never look. Bash
#   warns about the narrow case where the name collides with the nameref itself
#   — `circular name reference`, after which the writes are dropped — and says
#   nothing at all about the wider case where it collides with any other local.
#   That second case was real: `dybatpho::array_sort __sort_values` used to
#   return successfully and sort nothing.
#
#   The library closes this by reserving a prefix. Every local in a function
#   that takes a variable name is called `__dybatpho_...`, and this check
#   refuses a caller-supplied name in that namespace. A collision is then either
#   impossible or a loud error, never a silent wrong answer.
# @example
#   function my_helper {
#     local target
#     dybatpho::expect_args target -- "$@"
#     dybatpho::expect_ref "${target}"
#     local -n __dybatpho_out="${target}"
#     __dybatpho_out="value"
#   }
#
# @arg $1 string Variable name supplied by the caller
# @exitcode 0 The name is safe to bind
# @exitcode 1 Stop the script when the name is not an identifier, or is reserved
#######################################
function dybatpho::expect_ref {
  local name="${1-}"
  local caller="${FUNCNAME[1]:-dybatpho::expect_ref}"

  [[ "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "${caller}: Invalid variable name: '${name}'"

  # The prefix belongs to the library's own locals. A caller handing one over
  # would have its nameref bound to the library's variable rather than to its
  # own, and would never be told.
  local reserved_hint="is reserved: names starting with \`__dybatpho\` belong to the library,"
  reserved_hint+=" and passing one would write to the wrong place. Rename the variable in the caller."
  [[ "${name}" == __dybatpho* ]] \
    && dybatpho::die "${caller}: '${name}' ${reserved_hint}"

  return 0
}

#######################################
# @description Check whether at least one more positional argument remains after the current one.
# This helper is useful while manually parsing a shifting argument list.
# @noargs
# @example
#   while dybatpho::still_has_args "$@" && shift; do
#     echo "Function has next argument is $1"
#   done
# @exitcode 0 Still has an argument
# @exitcode 1 No additional arguments remain
#######################################
function dybatpho::still_has_args {
  [[ $# -gt 1 ]]
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
    if [[ -z "${!arg:-}" ]]; then
      dybatpho::die "Environment variable \`${arg}\` isn't set." # kcov(skip)
    fi
  done
}

# What tells a version range apart from the exit code that may sit in the same
# argument. The pattern is held in a variable for two reasons: written inline
# and unquoted, `<` and `>` are read as redirections before the conditional ever
# sees them, and escaping them as `\<` drags `\^` along, which quote removal
# turns into a leading `^` that negates the bracket expression and matches
# nearly everything. Here `^` is simply one more member of the set.
__DYBATPHO_HELPERS_RANGE_REGEX='^[<>=^~]'

#######################################
# @description Ensure that a required command is installed, and new enough.
#   With a version range, the command is asked what version it is through
#   `dybatpho::command_version`, the answer is normalized by
#   `dybatpho::semver_coerce`, and the result is matched with
#   `dybatpho::semver_satisfies`. The range is written the way that function
#   documents it: `>=1.6`, `^4`, `>=1.2 <2`, `1.2.x`, or alternatives with `||`.
#
#   The range has to open with one of `>`, `<`, `=`, `^`, or `~`. A bare `4`
#   is a valid range on its own elsewhere, but this argument has meant an exit
#   code since before ranges existed here, and no amount of cleverness makes
#   `require jq 3` mean both things at once.
#
#   Matching a version needs the optional `semver` module. Rather than let a
#   range pass unchecked in a script that did not load it, this stops with a
#   message naming what to load: a requirement that is silently not enforced is
#   worse than one that was never written.
#
#   A command whose version cannot be read is also a failure, for the same
#   reason. `dybatpho::doctor` treats that case as a report rather than a
#   failure, because a report is allowed to say "I could not tell".
# @example
#   dybatpho::require git
#   dybatpho::require jq '>=1.6'
#   dybatpho::require yq '^4' 3
#
# @arg $1 string Command that must be available
# @arg $2 string Version range opening with an operator, or the exit code
# @arg $3 number Exit code when a range was given (default 127)
# @tip Prefer this over repeating inline `command -v ... || exit` checks throughout a script
# @exitcode 127 Stop script if command isn't installed, or is outside the range
# @exitcode 0 The command is available and satisfies the range
# @exitcode other Exit code given as an argument, instead of 127
# @see
#   - `dybatpho::command_version`
#   - `dybatpho::semver_coerce`
#   - `dybatpho::semver_satisfies`
#######################################
function dybatpho::require {
  local command_name
  dybatpho::expect_args command_name -- "$@"
  local range="" exit_code
  if [[ "${2-}" =~ ${__DYBATPHO_HELPERS_RANGE_REGEX} ]]; then
    range="$2"
    exit_code="${3:-127}"
  else
    exit_code="${2:-127}"
  fi

  hash "${command_name}" > /dev/null 2>&1 \
    || dybatpho::die "${command_name} isn't installed" "${exit_code}"
  [[ -n "${range}" ]] || return 0

  # The guard names an internal helper on purpose: `dybatpho::` functions are
  # exported and a child shell inherits them without the internals they call,
  # so testing the public name would pass here in a child that never loaded
  # `semver` and then fail on the first internal call.
  declare -F __dybatpho_semver_holds > /dev/null \
    || dybatpho::die \
      "${command_name} ${range} needs the semver module, load it with: dybatpho::load semver" \
      "${exit_code}"

  local found
  found="$(dybatpho::command_version "${command_name}")" \
    || dybatpho::die \
      "${command_name} ${range} is required, but its version can't be determined" \
      "${exit_code}"
  dybatpho::semver_satisfies "$(dybatpho::semver_coerce "${found}")" "${range}" \
    || dybatpho::die \
      "${command_name} ${range} is required, found ${found}" "${exit_code}"
}

#######################################
# @description Return success when all listed commands are available.
# @arg $@ string Commands to check
# @exitcode 0 Every command exists
# @exitcode 1 At least one command is missing
#######################################
function dybatpho::command_exists_all {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one command"
  local command_name
  for command_name in "$@"; do
    dybatpho::is command "${command_name}" || return 1
  done
  return 0
}

#######################################
# @description Check whether a value matches a supported shell-oriented condition.
# @arg $1 string Condition
#   (command|function|file|dir|link|exist|readable|writeable|executable|set|empty|number|int|true|false)
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
      [[ -f "${input}" ]]
      return "$?"
      ;;
    dir)
      [[ -d "${input}" ]]
      return "$?"
      ;;
    link)
      [[ -L "${input}" ]]
      return "$?"
      ;;
    exist)
      [[ -e "${input}" ]]
      return "$?"
      ;;
    readable)
      [[ -r "${input}" ]]
      return "$?"
      ;;
    writeable)
      [[ -w "${input}" ]]
      return "$?"
      ;;
    executable)
      [[ -x "${input}" ]]
      return "$?"
      ;;
    set)
      [[ "${input+x}" == "x" ]] && [[ "${#input}" -gt "0" ]]
      return "$?"
      ;;
    empty)
      [[ "${input+x}" == "x" ]] && [[ "${#input}" -eq "0" ]]
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
    *) ;;
  esac > /dev/null 2>&1 # kcov(skip)
  return 1
}

#######################################
# @description Print the first non-empty value from a list of fallbacks.
# @arg $@ string Candidate values in priority order
# @stdout First non-empty value
# @exitcode 0 A non-empty value is found
# @exitcode 1 No values are provided or all values are empty
#######################################
function dybatpho::coalesce {
  if [[ $# -eq 0 ]]; then
    dybatpho::die "${FUNCNAME[0]}: Expected at least one value" # kcov(skip)
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -n "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Print the first available command from a list of candidates.
# @arg $@ string Candidate command names in priority order
# @stdout First available command name
# @exitcode 0 An available command is found
# @exitcode 1 No commands are available
#######################################
function dybatpho::coalesce_cmd {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one command"
  local command_name
  for command_name in "$@"; do
    if dybatpho::is command "${command_name}"; then
      printf '%s\n' "${command_name}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Assign and export a default value for an environment variable when it is empty.
# @arg $1 string Environment variable name
# @arg $2 string Default value
# @stdout Effective value after applying the default
#######################################
function dybatpho::default_env {
  local env_name default_value
  dybatpho::expect_args env_name default_value -- "$@"
  [[ "${env_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || dybatpho::die "Invalid environment variable name: ${env_name}"
  if [[ -z "${!env_name:-}" ]]; then
    printf -v "${env_name}" '%s' "${default_value}"
    # shellcheck disable=SC2163 # exporting the variable this name refers to, as intended
    export "${env_name}"
  fi
  printf '%s\n' "${!env_name}"
}

#######################################
# @description Ensure that at least one of the listed environment variables is set.
# @arg $@ string Environment variables to check
# @exitcode 0 At least one environment variable is set
# @exitcode 1 None of the environment variables are set
#######################################
function dybatpho::require_envs_any {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one environment variable"
  local env_name
  for env_name in "$@"; do
    [[ -n "${!env_name:-}" ]] && return 0
  done
  dybatpho::die "Expected at least one environment variable to be set: $*" # kcov(skip)
}

#######################################
# @description Evaluate a shell condition string and stop with a message when it fails.
# @arg $1 string Shell condition or command string to evaluate
# @arg $2 string Optional failure message
# @exitcode 0 The assertion condition succeeds
# @exitcode 1 The assertion condition fails
# @tip The assertion command is executed with `eval`
#######################################
function dybatpho::assert {
  local condition
  dybatpho::expect_args condition -- "$@"
  local message="${2:-Assertion failed: ${condition}}"
  eval "${condition}" || dybatpho::die "${message}"
}

#######################################
# @description Compute how long the nth retry waits.
#   Exponential from a base delay, capped, with optional jitter — the policy the
#   HTTP retries in `network.sh` already used, which the generic retry here did
#   not. Jitter matters when several machines retry the same failing dependency:
#   without it they all come back at the same instant, which is the load that
#   kept it down.
# @arg $1 number Attempt number, counting from 1
# @stdout Delay in seconds
#######################################
function __dybatpho_helpers_backoff {
  local attempt
  dybatpho::expect_args attempt -- "$@"
  local delay=$((DYBATPHO_RETRY_BASE_DELAY * (2 ** (attempt - 1))))
  ((delay > DYBATPHO_RETRY_MAX_DELAY)) && delay="${DYBATPHO_RETRY_MAX_DELAY}"
  if dybatpho::is true "${DYBATPHO_RETRY_JITTER}"; then
    ((delay += RANDOM % (DYBATPHO_RETRY_BASE_DELAY + 1)))
    ((delay > DYBATPHO_RETRY_MAX_DELAY)) && delay="${DYBATPHO_RETRY_MAX_DELAY}"
  fi
  printf '%s\n' "${delay}"
}

#######################################
# @description Retry a shell command with escalating delays until it succeeds or retries are exhausted.
# @example
#   dybatpho::retry 3 "curl -fsSL '${url}'" "health check"
#
# @arg $1 number Number of retries
# @arg $2 string Shell command string to run
# @arg $3 string Optional short description for retry logs
# @env DYBATPHO_RETRY_BASE_DELAY number First retry delay in seconds
# @env DYBATPHO_RETRY_MAX_DELAY number Longest a single retry waits
# @env DYBATPHO_RETRY_JITTER bool Add up to one base delay of random jitter
# @exitcode 0 The command eventually succeeds
# @exitcode 1 The command never succeeds and returns 1 on the final attempt
# @tip The command is executed with `eval`, so pass it as one shell command string
# @tip Turn on `DYBATPHO_RETRY_JITTER` when several machines retry the same
#   dependency, so they do not all come back at the same instant
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
    if [[ "${count}" -le "${retries}" ]]; then
      delay="$(__dybatpho_helpers_backoff "${count}")"
      if declare -F __dybatpho_metrics_key > /dev/null; then
        dybatpho::metrics_counter_inc dybatpho_retry_attempts_total
      fi
      dybatpho::progress "Retrying in ${delay} seconds (${count}/${retries})..."
      sleep "${delay}" || true
    else
      # Out of retries :(
      if declare -F __dybatpho_metrics_key > /dev/null; then
        dybatpho::metrics_counter_inc dybatpho_retry_exhausted_total
      fi
      dybatpho::warn "No more retries left to run ${1:-${command}}."
      return "${exit_code}"
    fi
  done
}

#######################################
# @description Retry a shell command until it succeeds or the retry budget is exhausted, using a fixed delay.
# @arg $1 number Number of retries
# @arg $2 number Delay in seconds between attempts
# @arg $3 string Shell command string to run
# @arg $4 string Optional short description for retry logs
# @exitcode 0 The command eventually succeeds
# @exitcode 1 The command never succeeds and returns its final exit code
# @tip The command is executed with `eval`, so pass it as one shell command string
#######################################
function dybatpho::retry_until {
  local retries delay_seconds command
  dybatpho::expect_args retries delay_seconds command -- "$@"
  shift 3
  local exit_code=0 count=0
  until eval "${command}"; do
    exit_code=$?
    count=$((count + 1))
    if ((count > retries)); then
      dybatpho::warn "No more retries left to run ${1:-${command}}."
      return "${exit_code}"
    fi
    dybatpho::progress "Retrying in ${delay_seconds} seconds (${count}/${retries})..."
    sleep "${delay_seconds}" || true
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
  local dybatpho_help
  local dybatpho_help_format='%s\n    d: run debugger\n    c: display source file\n    o: list options\n'
  dybatpho_help_format+='    p: list parameters\n    a: list indexed array\n    A: list associative array\n'
  dybatpho_help_format+='    q: quit'
  # shellcheck disable=SC2059 # the format is built above, not taken from input
  printf -v dybatpho_help "${dybatpho_help_format}" "${dybatpho_section}"
  local source_file="${BASH_SOURCE[1]:-bash}"
  __dybatpho_log fatal "Breakpoint hit. Current line: ${source_file}:${BASH_LINENO[0]}" stderr "1;36"
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
        # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
        dybatpho::is true "${DYBATPHO_USED_ERR_HANDLER}" \
          && dybatpho::register_err_handler # Rerun register_err_handler
        # dyshellint disable=BSG034 # the debugger restores the tracing it suspended
        # shellcheck disable=SC2154 # declared by `src/logging.sh`, a core module
        [[ "${LOG_LEVEL}" == "trace" ]] && set -xv # Re-enable tracing if needed
        ;;
      c)
        if [[ "${source_file}" != "bash" ]]; then
          echo "${dybatpho_section}" >&2
          dybatpho::show_file "${BASH_SOURCE[1]}"
        fi
        ;;
      # kcov(enabled)
      *) continue ;;
    esac
  done # kcov(skip)
}

#######################################
# @description Print the file and line a function was defined at.
#   `declare -F` names the file only while `extdebug` is on, and that option
#   also changes how `DEBUG` and `RETURN` traps behave, so it is switched on for
#   the one call and put back exactly as it was found. `shopt -p` reports a
#   non-zero status when the option is off, which under `errexit` would end the
#   caller before anything was looked up.
# @arg $1 string Function name, in full
# @stdout Two lines: the file, then the line number
# @exitcode 1 No such function, or Bash could not say where it came from
#######################################
function __dybatpho_helpers_locate {
  local restore
  restore="$(shopt -p extdebug || true)"
  shopt -s extdebug
  local spec
  spec="$(declare -F "$1" 2> /dev/null || true)"
  eval "${restore}"

  # `declare -F` answers `name line file`, and the path may hold spaces while
  # the first two fields cannot.
  local remainder="${spec#* }"
  local line="${remainder%% *}"
  local file="${remainder#* }"
  [[ -n "${spec}" && -n "${file}" && "${line}" =~ ^[0-9]+$ ]] || return 1
  # Bash reports the path as it was written when the file was sourced, so a
  # module loaded as `test/../init.sh` is named that way here. Tidying it up
  # makes the answer readable and keeps `..` out of a path a caller may print.
  file="$(dybatpho::path_normalize "${file}" 2> /dev/null || printf '%s' "${file}")"
  printf '%s\n%s\n' "${file}" "${line}"
}

#######################################
# @description Print a function name with the `dybatpho::` prefix it may have
#   been given without.
# @arg $1 string Function name, with or without a prefix
# @stdout The full function name
#######################################
function __dybatpho_helpers_qualify {
  local name="${1-}"
  if [[ "${name}" == dybatpho::* || "${name}" == __dybatpho_* ]]; then
    printf '%s\n' "${name}"
  else
    printf 'dybatpho::%s\n' "${name}"
  fi
}

#######################################
# @description Print the module a loaded source file belongs to.
#   A module is recognised by its place rather than its name: a file directly
#   inside a `src` directory is that module, and the bootstrap is `init`.
#   Anything else is refused, because a bundle holds every module in one file
#   and answering with that file's name would attribute every function in the
#   library to a module called `dybatpho.bundle`.
# @arg $1 string Path of a file the library was loaded from
# @stdout The module name
# @exitcode 1 The file is not a module source
#######################################
function __dybatpho_helpers_module_of {
  local file="$1"
  local name="${file##*/}"
  # The bootstrap is recognised by its own name rather than by comparing against
  # `DYBATPHO_DIR`: that variable is fully resolved while the path Bash reports
  # is whatever was written at the `source`, and a library reached through a
  # symlink would never match.
  if [[ "${name}" == "init.sh" ]]; then
    printf 'init\n'
    return 0
  fi
  local directory="${file%/*}"
  [[ "${directory##*/}" == "src" ]] || return 1
  printf '%s\n' "${name%.sh}"
}

#######################################
# @description Print the module that defines a function.
#   The answer comes from where Bash says the function was defined, so it
#   describes the code that is actually loaded rather than what a directory
#   listing suggests. Functions the bootstrap defines report `init`.
# @example
#   dybatpho::provides semver_valid            # semver
#   dybatpho::provides dybatpho::cache_run     # cache
#   dybatpho::provides --path cache_run        # /path/to/src/cache.sh:245
#
# @arg $1 string `--path` to print `file:line` instead of the module name
# @arg $@ string Function name, with or without the `dybatpho::` prefix
# @stdout The module name, or `file:line` with `--path`
# @exitcode 1 The function is not defined in this shell, or it came from a
#   bundle, where there are no module sources to name
# @note A bundle holds every module in one file, so only `--path` can answer
#   there, and it still points at the right line
# @see
#   - `dybatpho::describe`
#   - `dybatpho::function_list`
#######################################
function dybatpho::provides {
  local want_path=false
  if [[ "${1-}" == "--path" ]]; then
    want_path=true
    shift
  fi
  local name
  dybatpho::expect_args name -- "$@"
  name="$(__dybatpho_helpers_qualify "${name}")"

  local -a location=()
  mapfile -t location < <(__dybatpho_helpers_locate "${name}")
  ((${#location[@]} == 2)) || return 1

  if [[ "${want_path}" == true ]]; then
    printf '%s:%s\n' "${location[0]}" "${location[1]}"
    return 0
  fi
  __dybatpho_helpers_module_of "${location[0]}"
}

#######################################
# @description Print the documentation comment of a function.
#   The library documents itself in `docs/`, which answers the question when you
#   are reading it. At a prompt, mid-script, the question is what a function
#   takes and what it returns, and the answer is in a browser tab. This reads it
#   out of the source the shell actually loaded, so it describes the code that
#   will run, and it is there whether or not `docs/` was ever generated.
#
#   The banner rules and any `shellcheck` directive between the comment and the
#   function are dropped, one `#` and the space after it are taken off each
#   line, and the `@description` marker is removed from the prose it introduces.
#   Everything else, `@arg` and `@exitcode` tags included, is printed as the
#   source wrote it.
# @example
#   dybatpho::describe cache_run
#   dybatpho::describe dybatpho::semver_satisfies
#
# @arg $1 string Function name, with or without the `dybatpho::` prefix
# @stdout A heading naming the function and where it came from, then the comment
# @exitcode 1 The function is not defined in this shell, or its source is no
#   longer readable
# @see
#   - `dybatpho::provides`
#######################################
function dybatpho::describe {
  local name
  dybatpho::expect_args name -- "$@"
  name="$(__dybatpho_helpers_qualify "${name}")"

  local -a location=()
  mapfile -t location < <(__dybatpho_helpers_locate "${name}")
  ((${#location[@]} == 2)) || return 1
  local file="${location[0]}" line="${location[1]}"
  dybatpho::is readable "${file}" || return 1

  # Only the part of the file above the definition is needed, and a module can
  # be long, so reading stops there rather than slurping the whole file.
  local -a lines=()
  local text count=0
  while IFS= read -r text; do
    ((count < line)) || break
    lines+=("${text}")
    count=$((count + 1))
  done < "${file}"

  # The comment block is the run of comment lines directly above the definition.
  local -a block=()
  local index
  for ((index = line - 2; index >= 0; index--)); do
    text="${lines[${index}]}"
    [[ "${text}" == '#'* ]] || break
    block=("${text}" ${block[@]+"${block[@]}"})
  done

  local origin
  if origin="$(__dybatpho_helpers_module_of "${file}")"; then
    printf '%s  (%s, %s:%s)\n' "${name}" "${origin}" "${file}" "${line}"
  else
    printf '%s  (%s:%s)\n' "${name}" "${file}" "${line}"
  fi
  ((${#block[@]} > 0)) || return 0

  printf '\n'
  for text in "${block[@]}"; do
    # The banner rules carry no text, and a directive addressed to ShellCheck
    # is not documentation.
    if [[ "${text}" =~ ^#+$ || "${text}" == '# shellcheck '* ]]; then
      continue
    fi
    # One `#` and the space after it are the comment marker; anything further
    # in is the shape of the comment and is kept.
    text="${text#\#}"
    text="${text# }"
    text="${text#@description }"
    printf '%s\n' "${text}"
  done
}

#######################################
# @description Print the public functions this shell has loaded.
#   Without an argument this is the whole loaded API; with one it is what a
#   single module exports, which is the list to skim when reaching for a module
#   for the first time.
#
#   Only `dybatpho::` names are listed. The `__dybatpho_` helpers are internal,
#   and `declare -F` is right there for anyone debugging one.
# @example
#   dybatpho::function_list              # everything loaded
#   dybatpho::function_list cache        # just that module
#   dybatpho::function_list | wc -l
#
# @arg $1 string Optional module name to limit the list to
# @stdout One function name per line, in alphabetical order
# @exitcode 1 Stop the script when the named module is not loaded, or when the
#   library came from a bundle, where no function can be attributed to a module
# @see
#   - `dybatpho::module_list`
#   - `dybatpho::provides`
#######################################
function dybatpho::function_list {
  local module="${1-}"
  if [[ -n "${module}" && "${module}" != "init" ]]; then
    dybatpho::module_loaded "${module}" \
      || dybatpho::die "${FUNCNAME[0]}: Module '${module}' is not loaded"
  fi

  # `declare -F` prints `declare -f <name>`, already in order, so the list needs
  # no external command to build -- which is the point of a helper meant to
  # answer when nothing else is at hand.
  local -a names=()
  local candidate
  while read -r _ _ candidate; do
    [[ "${candidate}" == dybatpho::* ]] || continue
    names+=("${candidate}")
  done < <(declare -F)
  ((${#names[@]} > 0)) || return 0

  if [[ -z "${module}" ]]; then
    printf '%s\n' "${names[@]}"
    return 0
  fi

  local name owner attributable=false
  for name in "${names[@]}"; do
    if owner="$(dybatpho::provides "${name}" 2> /dev/null)"; then
      attributable=true
      if [[ "${owner}" == "${module}" ]]; then
        printf '%s\n' "${name}"
      fi
    fi
  done
  # An empty list would read as "that module exports nothing", which is not what
  # happened: a bundle holds every module in one file and none of them can be
  # told apart.
  [[ "${attributable}" == true ]] \
    || dybatpho::die \
      "${FUNCNAME[0]}: No function belongs to a module, which is how a bundle looks; ask without a module"
}
