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
  local -a __dybatpho_expect_names=()
  local __dybatpho_expect_unsplit=1

  while (($#)); do
    if [[ "$1" = -- ]]; then
      __dybatpho_expect_unsplit=0
      shift
      break
    fi
    __dybatpho_expect_names+=("$1")
    shift
  done

  ((__dybatpho_expect_unsplit)) \
    && dybatpho::die "${FUNCNAME[1]:--}: Expected variable names, \`--\`, and args:" 'arg1 .. argN -- "$@"' # kcov(skip)

  local __dybatpho_expect_name
  for __dybatpho_expect_name in "${__dybatpho_expect_names[@]}"; do
    [[ "${__dybatpho_expect_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
      || dybatpho::die "${FUNCNAME[1]:--}: Invalid variable name: ${__dybatpho_expect_name}"
    if ! (($#)); then
      dybatpho::die "${FUNCNAME[1]:--}: Expected args: ${__dybatpho_expect_names[*]:-}" # kcov(skip)
    fi
    printf -v "${__dybatpho_expect_name}" '%s' "$1"
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
  local arg
  for arg in "$@"; do
    if [[ -z "${!arg:-}" ]]; then
      dybatpho::die "Environment variable \`${arg}\` isn't set." # kcov(skip)
    fi
  done
}

#######################################
# @description Stop the script unless an optional module is loaded, saying who
#   needs it and how to load it. A module that calls another one only from a
#   few of its functions guards those functions with this rather than loading
#   the other module for every script.
#
#   The marker has to be an internal `__dybatpho_` helper of the needed module,
#   never a public function: public functions are exported, so a child shell
#   inherits them without the internals they call, and a guard on a public name
#   would pass there and then fail on the first internal call.
# @arg $1 string Module that is needed
# @arg $2 string Internal helper of that module whose presence means it is loaded
# @arg $3 string What needs the module, usually the public function's name
# @arg $4 number Exit code to stop with, default is `1`
# @exitcode 0 The module is loaded
# @internal
#######################################
function __dybatpho_helpers_need_module {
  declare -F "$2" > /dev/null \
    || dybatpho::die "$3 needs the $1 module, load it with: dybatpho::load $1" "${4:-1}"
}

#######################################
# @description Set a variable to the public function a script called, for a
#   helper several frames below it to report under. A helper that names
#   `FUNCNAME[1]` names whatever called it, which is an internal function as soon
#   as a public one delegates to an internal one; this walks up to the first
#   `dybatpho::` frame above the helper's caller instead.
# @arg $1 string Name of the variable receiving the function name
# @set The named variable: the nearest public caller, or the helper's caller when there is none
# @internal
#######################################
function __dybatpho_helpers_public_caller_into {
  local -n __dybatpho_helpers_pc_ref="$1"
  local __dybatpho_helpers_pc_fn
  __dybatpho_helpers_pc_ref="${FUNCNAME[2]-main}"
  for __dybatpho_helpers_pc_fn in "${FUNCNAME[@]:2}"; do
    if [[ "${__dybatpho_helpers_pc_fn}" == dybatpho::* ]]; then
      __dybatpho_helpers_pc_ref="${__dybatpho_helpers_pc_fn}"
      return 0
    fi
  done
}

#######################################
# @description Sort an array in place, bottom-up and stable, deciding the order
#   through a comparator function.
#   Runs of length one are already sorted, so the passes merge pairs of them
#   and double the run length until one run covers everything: `n log n`
#   comparisons whatever order the values arrive in, where an insertion sort
#   pays `n²`. The merge takes from the left run unless the right value
#   strictly comes first, which is what keeps equal values in the order they
#   arrived in. Everything stays in Bash, so a value holding a newline is
#   sorted whole and no external `sort` is needed.
#
#   The comparator is called as `<comparator> <a> <b> [args...]` and succeeds
#   exactly when `a` has to come before `b`; for values that compare equal it
#   fails. A module that sorts by a key rather than by the value itself sorts
#   an array of indexes and has the comparator look the keys up, so each key is
#   worked out once rather than on every comparison.
#
#   `@int-key <keys>` in place of a comparator sorts an array of indexes by the
#   whole numbers the named array holds for them, smallest first, and
#   `@bytes-key <keys>` by the strings it holds, in byte order. Both compare
#   inline: a function call per comparison is most of what a sort costs in
#   Bash, and a list of timings is exactly where that shows.
# @arg $1 string Name of the array to sort in place
# @arg $2 string Comparator function, `@int-key` or `@bytes-key`
# @arg $@ string Extra arguments passed to every comparator call, or the name of the keys array for a key mode
# @set The named array, reindexed from zero
# @internal
#######################################
function __dybatpho_helpers_sort {
  local -n __dybatpho_helpers_sort_ref="$1"
  local __dybatpho_helpers_sort_before="$2"
  shift 2
  local -a __dybatpho_helpers_sort_from=(${__dybatpho_helpers_sort_ref[@]+"${__dybatpho_helpers_sort_ref[@]}"})
  local -a __dybatpho_helpers_sort_into=()
  local __dybatpho_helpers_sort_n="${#__dybatpho_helpers_sort_from[@]}"
  local __dybatpho_helpers_sort_width=1 __dybatpho_helpers_sort_lo __dybatpho_helpers_sort_mid
  local __dybatpho_helpers_sort_hi __dybatpho_helpers_sort_l __dybatpho_helpers_sort_r
  local __dybatpho_helpers_sort_left __dybatpho_helpers_sort_right __dybatpho_helpers_sort_key
  local __dybatpho_helpers_sort_mode=call
  case "${__dybatpho_helpers_sort_before}" in
    @int-key | @bytes-key)
      __dybatpho_helpers_sort_mode="${__dybatpho_helpers_sort_before}"
      local -n __dybatpho_helpers_sort_keys="$1"
      # Byte order whatever the caller's collation; it only reaches the
      # inline comparison, since no comparator is called in a key mode.
      local LC_ALL=C
      ;;
    *) ;; # kcov(skip) - a case arm with no command has nothing for the trap to fire on
  esac

  while ((__dybatpho_helpers_sort_width < __dybatpho_helpers_sort_n)); do
    __dybatpho_helpers_sort_into=()
    for ((__dybatpho_helpers_sort_lo = 0; __dybatpho_helpers_sort_lo < __dybatpho_helpers_sort_n;  \
    __dybatpho_helpers_sort_lo += 2 * __dybatpho_helpers_sort_width)); do
      __dybatpho_helpers_sort_mid=$((__dybatpho_helpers_sort_lo + __dybatpho_helpers_sort_width))
      ((__dybatpho_helpers_sort_mid <= __dybatpho_helpers_sort_n)) \
        || __dybatpho_helpers_sort_mid="${__dybatpho_helpers_sort_n}"
      __dybatpho_helpers_sort_hi=$((__dybatpho_helpers_sort_mid + __dybatpho_helpers_sort_width))
      ((__dybatpho_helpers_sort_hi <= __dybatpho_helpers_sort_n)) \
        || __dybatpho_helpers_sort_hi="${__dybatpho_helpers_sort_n}"
      __dybatpho_helpers_sort_l="${__dybatpho_helpers_sort_lo}"
      __dybatpho_helpers_sort_r="${__dybatpho_helpers_sort_mid}"
      while ((__dybatpho_helpers_sort_l < __dybatpho_helpers_sort_mid && \
        __dybatpho_helpers_sort_r < __dybatpho_helpers_sort_hi)); do
        __dybatpho_helpers_sort_right="${__dybatpho_helpers_sort_from[__dybatpho_helpers_sort_r]}"
        __dybatpho_helpers_sort_left="${__dybatpho_helpers_sort_from[__dybatpho_helpers_sort_l]}"
        if case "${__dybatpho_helpers_sort_mode}" in
          @int-key)
            ((__dybatpho_helpers_sort_keys[__dybatpho_helpers_sort_right] < \
            __dybatpho_helpers_sort_keys[__dybatpho_helpers_sort_left]))
            ;;
          @bytes-key)
            # shfmt joins a `[[ ]]` test onto one line, so one side is read
            # first to keep that line short.
            __dybatpho_helpers_sort_key="${__dybatpho_helpers_sort_keys[__dybatpho_helpers_sort_right]}"
            [[ "${__dybatpho_helpers_sort_key}" < "${__dybatpho_helpers_sort_keys[__dybatpho_helpers_sort_left]}" ]]
            ;;
          *)
            "${__dybatpho_helpers_sort_before}" \
              "${__dybatpho_helpers_sort_right}" "${__dybatpho_helpers_sort_left}" "$@"
            ;;
        esac then
          __dybatpho_helpers_sort_into+=("${__dybatpho_helpers_sort_right}")
          ((__dybatpho_helpers_sort_r += 1))
        else
          __dybatpho_helpers_sort_into+=("${__dybatpho_helpers_sort_left}")
          ((__dybatpho_helpers_sort_l += 1))
        fi
      done
      # Index loops rather than `${array[@]:offset:length}`: a Bash array is a
      # linked list, so a slice walks from the start every time and the narrow
      # early passes would cost `n²`.
      for (( ; __dybatpho_helpers_sort_l < __dybatpho_helpers_sort_mid; __dybatpho_helpers_sort_l++)); do
        __dybatpho_helpers_sort_into+=("${__dybatpho_helpers_sort_from[__dybatpho_helpers_sort_l]}")
      done
      for (( ; __dybatpho_helpers_sort_r < __dybatpho_helpers_sort_hi; __dybatpho_helpers_sort_r++)); do
        __dybatpho_helpers_sort_into+=("${__dybatpho_helpers_sort_from[__dybatpho_helpers_sort_r]}")
      done
    done
    __dybatpho_helpers_sort_from=("${__dybatpho_helpers_sort_into[@]}")
    ((__dybatpho_helpers_sort_width *= 2))
  done

  __dybatpho_helpers_sort_ref=(${__dybatpho_helpers_sort_from[@]+"${__dybatpho_helpers_sort_from[@]}"})
}

#######################################
# @description Read the options of a function that parses its own, setting
#   the caller's variables as the specification says.
#
#   Each entry of the specification is `names=targets`: switches joined by `|`,
#   then what each switch does to one or more of the caller's variables, joined
#   by `,`. A target is one of:
#
#   - `var`        a flag, which sets `var` to `true`
#   - `var=value`  a flag, which sets `var` to `value`
#   - `var+`       a flag, which appends the switch itself to the array `var`
#   - `var:`       an option, which sets `var` to the value that follows it
#   - `var+:`      an option, which appends that value to the array `var`
#   - `var++:`     an option, which appends the switch and the value to `var`
#
#   An option may name what its value is after the colon, `var:number`, which
#   is the `{noun}` of the message for a missing value; it is `value` otherwise.
#   The switch recorded by `var++:` is the switch's name, so a `--name=value`
#   form reads back as `--name` and `value`.
#
#   The mode is a comma-separated set of words. `leading` stops at the first
#   argument that is not an option, the way a command's own flags come before
#   its arguments; otherwise other arguments are collected as positionals
#   wherever they appear. `attached` also takes `--name=value`. `strict` takes
#   no positional at all, `--` included. `keep-dashes` leaves `--` alone instead
#   of reading it as the end of the options.
#
#   An argument that is not a known switch but matches the glob is refused with
#   the unknown-option message; an empty glob refuses nothing.
#
#   The caller's variables are set through dynamic scope, so every name here is
#   prefixed: an unprefixed local would capture the caller's variable of the
#   same name.
# @arg $1 string Name of the array receiving the positional arguments, or `-`
# @arg $2 string Name of the array receiving `[0]` the number of arguments read
#   and `[1]` how many positionals came before `--`, or `-1` without one; or `-`
# @arg $3 string Specification, whitespace-separated entries
# @arg $4 string Mode, comma-separated words, may be empty
# @arg $5 string Glob an unknown option matches, such as `-*` or `--?*`
# @arg $6 string Message for an unknown option, `{option}` is the argument
# @arg $7 string Message for a missing value, with `{option}` and `{noun}`
# @arg $8 string `--`, then the arguments to read
# @set The named arrays, and the caller's variables named by the specification
# @exitcode 0 The options were read
# @exitcode 1 Stop the script on an unknown option or a missing value
# @internal
#######################################
function __dybatpho_helpers_options_into {
  # `-` names an output the caller has no use for.
  local -a __dybatpho_helpers_po_unwanted_positional=() __dybatpho_helpers_po_unwanted_info=()
  local -n __dybatpho_helpers_po_positional="${1/#-/__dybatpho_helpers_po_unwanted_positional}"
  local -n __dybatpho_helpers_po_info="${2/#-/__dybatpho_helpers_po_unwanted_info}"
  local __dybatpho_helpers_po_spec="$3" __dybatpho_helpers_po_mode=",$4,"
  local __dybatpho_helpers_po_glob="$5" __dybatpho_helpers_po_unknown="$6"
  local __dybatpho_helpers_po_missing="$7"
  shift 8

  local -A __dybatpho_helpers_po_targets=()
  local __dybatpho_helpers_po_entry __dybatpho_helpers_po_name
  local -a __dybatpho_helpers_po_names=()
  for __dybatpho_helpers_po_entry in ${__dybatpho_helpers_po_spec}; do
    IFS='|' read -r -a __dybatpho_helpers_po_names <<< "${__dybatpho_helpers_po_entry%%=*}"
    for __dybatpho_helpers_po_name in "${__dybatpho_helpers_po_names[@]}"; do
      __dybatpho_helpers_po_targets["${__dybatpho_helpers_po_name}"]="${__dybatpho_helpers_po_entry#*=}"
    done
  done

  local -i __dybatpho_helpers_po_used=0 __dybatpho_helpers_po_split=-1
  local __dybatpho_helpers_po_arg __dybatpho_helpers_po_value __dybatpho_helpers_po_has_value
  local __dybatpho_helpers_po_target __dybatpho_helpers_po_noun __dybatpho_helpers_po_message
  local __dybatpho_helpers_po_ends __dybatpho_helpers_po_refused
  local -a __dybatpho_helpers_po_list=()
  __dybatpho_helpers_po_positional=()
  while (($#)); do
    __dybatpho_helpers_po_arg="$1"
    __dybatpho_helpers_po_has_value=false
    if [[ "${__dybatpho_helpers_po_mode}" == *,attached,* && "${__dybatpho_helpers_po_arg}" == --?*=* ]] \
      && [[ -n "${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg%%=*}]+set}" ]] \
      && [[ "${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg%%=*}]}" == *:* ]]; then
      __dybatpho_helpers_po_value="${__dybatpho_helpers_po_arg#*=}"
      __dybatpho_helpers_po_arg="${__dybatpho_helpers_po_arg%%=*}"
      __dybatpho_helpers_po_has_value=true
    fi

    if [[ -z "${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg}]+set}" ]]; then
      __dybatpho_helpers_po_ends=false __dybatpho_helpers_po_refused=false
      if [[ "${__dybatpho_helpers_po_arg}" == "--" && "${__dybatpho_helpers_po_mode}" != *,keep-dashes,* ]]; then
        __dybatpho_helpers_po_ends=true
      fi
      if [[ "${__dybatpho_helpers_po_mode}" == *,strict,* ]]; then
        __dybatpho_helpers_po_refused=true
      elif [[ "${__dybatpho_helpers_po_ends}" == false && -n "${__dybatpho_helpers_po_glob}" ]]; then
        # The glob is matched as a pattern on purpose, so it stays unquoted.
        # shellcheck disable=SC2053
        [[ "${__dybatpho_helpers_po_arg}" != ${__dybatpho_helpers_po_glob} ]] \
          || __dybatpho_helpers_po_refused=true
      fi
      [[ "${__dybatpho_helpers_po_refused}" == false ]] \
        || dybatpho::die "${__dybatpho_helpers_po_unknown//\{option\}/${__dybatpho_helpers_po_arg}}"
      if [[ "${__dybatpho_helpers_po_ends}" == true ]]; then
        shift
        __dybatpho_helpers_po_used+=1
        if [[ "${__dybatpho_helpers_po_mode}" != *,leading,* ]]; then
          __dybatpho_helpers_po_split="${#__dybatpho_helpers_po_positional[@]}"
          __dybatpho_helpers_po_positional+=("$@")
          __dybatpho_helpers_po_used+=$#
        fi
        break
      fi
      [[ "${__dybatpho_helpers_po_mode}" != *,leading,* ]] || break
      __dybatpho_helpers_po_positional+=("$1")
      shift
      __dybatpho_helpers_po_used+=1
      continue
    fi

    IFS=',' read -r -a __dybatpho_helpers_po_list <<< "${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg}]}"
    if [[ "${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg}]}" == *:* ]] \
      && [[ "${__dybatpho_helpers_po_has_value}" == false ]]; then
      if (($# < 2)); then
        __dybatpho_helpers_po_noun="${__dybatpho_helpers_po_targets[${__dybatpho_helpers_po_arg}]##*:}"
        __dybatpho_helpers_po_message="${__dybatpho_helpers_po_missing//\{option\}/${__dybatpho_helpers_po_arg}}"
        dybatpho::die "${__dybatpho_helpers_po_message//\{noun\}/${__dybatpho_helpers_po_noun:-value}}"
      fi
      __dybatpho_helpers_po_value="$2"
      shift
      __dybatpho_helpers_po_used+=1
    fi
    shift
    __dybatpho_helpers_po_used+=1

    for __dybatpho_helpers_po_target in "${__dybatpho_helpers_po_list[@]}"; do
      case "${__dybatpho_helpers_po_target}" in
        *++:*) __dybatpho_helpers_options_append "${__dybatpho_helpers_po_target%%++:*}" \
          "${__dybatpho_helpers_po_arg}" "${__dybatpho_helpers_po_value}" ;;
        *+:*) __dybatpho_helpers_options_append "${__dybatpho_helpers_po_target%%+:*}" \
          "${__dybatpho_helpers_po_value}" ;;
        *:*) printf -v "${__dybatpho_helpers_po_target%%:*}" '%s' "${__dybatpho_helpers_po_value}" ;;
        *+) __dybatpho_helpers_options_append "${__dybatpho_helpers_po_target%+}" \
          "${__dybatpho_helpers_po_arg}" ;;
        *=*) printf -v "${__dybatpho_helpers_po_target%%=*}" '%s' "${__dybatpho_helpers_po_target#*=}" ;;
        *) printf -v "${__dybatpho_helpers_po_target}" '%s' true ;;
      esac
    done
  done

  __dybatpho_helpers_po_info=("${__dybatpho_helpers_po_used}" "${__dybatpho_helpers_po_split}")
}

#######################################
# @description Append values to an array named by the caller's caller, for
#   `__dybatpho_helpers_options_into`. It is a function of its own so that the
#   reference is declared afresh for every array it is pointed at.
# @arg $1 string Name of the array
# @arg $@ string Values to append
# @set The named array
# @internal
#######################################
function __dybatpho_helpers_options_append {
  local -n __dybatpho_helpers_pa_ref="$1"
  shift
  __dybatpho_helpers_pa_ref+=("$@")
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

  # `hash` looks a bare name up on `PATH`, but takes a name holding a `/` on
  # trust and succeeds without checking that anything is there, so a path has
  # to be an executable file in its own right.
  if [[ "${command_name}" == */* ]]; then
    [[ -f "${command_name}" && -x "${command_name}" ]] \
      || dybatpho::die "${command_name} isn't installed" "${exit_code}"
  else
    hash "${command_name}" > /dev/null 2>&1 \
      || dybatpho::die "${command_name} isn't installed" "${exit_code}"
  fi
  [[ -n "${range}" ]] || return 0

  __dybatpho_helpers_need_module semver __dybatpho_semver_holds \
    "${command_name} ${range}" "${exit_code}"

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

# What `dybatpho::is int` and `dybatpho::is number` accept. `number` is the
# expression `validate.sh` uses for its own `number` type, so the two checks
# agree; `int` also refuses a leading zero, which Bash arithmetic reads as
# octal, so every int it passes can go straight into `(( ))` as written.
__DYBATPHO_HELPERS_RE_INT='^[+-]?(0|[1-9][0-9]*)$'
__DYBATPHO_HELPERS_RE_NUMBER='^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
# A shell variable name, as `validate.sh` names it for its `identifier` type.
# Exported `dybatpho::` functions spell these expressions out instead of reading
# the constants, because a child shell inherits the functions without the
# variables; `test/helpers.bats` pins the two spellings together.
__DYBATPHO_HELPERS_RE_IDENTIFIER='^[a-zA-Z_][a-zA-Z0-9_]*$'

# One group of an IPv6 address: one to four hexadecimal digits.
__DYBATPHO_HELPERS_RE_IPV6_GROUP='^[0-9A-Fa-f]{1,4}$'

# The address parsers live here, in a core module, because two modules answer
# address questions: `network` with its public `is_ipv4`, `is_cidr` and
# `cidr_contains`, and `validate` with its `ipv4`, `ipv6` and `cidr` types,
# which may depend on core modules only. One parser keeps the two from
# drifting apart.

#######################################
# @description Split an IPv4 address into its four octets as numbers.
#   A leading zero is rejected rather than ignored. `inet_aton` and much of the
#   software built on it read `010` as octal, so `127.0.0.010` is one host to
#   one parser and another host to the next. An address that means two things
#   is not an address this library will agree to.
# @arg $1 string Address to split
# @arg $2 string Name of the array variable receiving the four octets, or `-`
# @set The named array, to four numbers from 0 to 255
# @exitcode 1 The value is not an IPv4 address
# @internal
#######################################
function __dybatpho_helpers_ipv4_octets {
  local __ipv4_address="$1"
  local -a __ipv4_unwanted=()
  local -n __ipv4_out="${2/#-/__ipv4_unwanted}"
  [[ "${__ipv4_address}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] \
    || return 1
  local -a __ipv4_matched=("${BASH_REMATCH[@]:1:4}")
  local __ipv4_octet
  __ipv4_out=()
  for __ipv4_octet in "${__ipv4_matched[@]}"; do
    [[ "${__ipv4_octet}" == "0" || "${__ipv4_octet}" != 0* ]] || return 1
    ((10#${__ipv4_octet} <= 255)) || return 1
    __ipv4_out+=("$((10#${__ipv4_octet}))")
  done
}

#######################################
# @description Expand an IPv6 address into its eight groups as numbers.
#   Everything an IPv6 address may leave out is put back here: the `::` that
#   stands for a run of zero groups, and the dotted IPv4 tail that occupies the
#   last two groups of a mapped address. Comparing addresses is only simple once
#   both are written out in full.
#
#   A zone index such as `%eth0` is rejected. It names an interface rather than
#   a part of the address, and it is not comparable between two hosts.
# @arg $1 string Address to expand
# @arg $2 string Name of the array variable receiving the eight groups, or `-`
# @set The named array, to eight numbers from 0 to 65535
# @exitcode 1 The value is not an IPv6 address
# @internal
#######################################
function __dybatpho_helpers_ipv6_groups {
  local __ipv6_address="$1"
  local -a __ipv6_unwanted=()
  local -n __ipv6_out="${2/#-/__ipv6_unwanted}"
  [[ "${__ipv6_address}" != *%* ]] || return 1
  [[ "${__ipv6_address}" == *:* ]] || return 1
  # A single colon at either end belongs to a `::` or to nothing at all. Without
  # this, `read -a` drops the empty trailing field and `1:2:3:4:5:6:7:8:` would
  # count as eight groups.
  [[ "${__ipv6_address}" != *: || "${__ipv6_address}" == *:: ]] || return 1
  [[ "${__ipv6_address}" != :* || "${__ipv6_address}" == ::* ]] || return 1

  local __ipv6_head __ipv6_tail __ipv6_has_double=0
  if [[ "${__ipv6_address}" == *::* ]]; then
    __ipv6_has_double=1
    __ipv6_head="${__ipv6_address%%::*}"
    __ipv6_tail="${__ipv6_address#*::}"
    # `::` stands for "the rest is zero", so a second one has nothing left to say.
    [[ "${__ipv6_tail}" != *::* ]] || return 1
  else
    __ipv6_head="${__ipv6_address}"
    __ipv6_tail=""
  fi

  local -a __ipv6_head_parts=() __ipv6_tail_parts=()
  [[ -z "${__ipv6_head}" ]] || IFS=':' read -r -a __ipv6_head_parts <<< "${__ipv6_head}"
  [[ -z "${__ipv6_tail}" ]] || IFS=':' read -r -a __ipv6_tail_parts <<< "${__ipv6_tail}"

  # A dotted tail, as in `::ffff:192.0.2.1`, is two groups written in decimal.
  local -a __ipv6_mapped=()
  local __ipv6_mapped_in_tail=0 __ipv6_last=""
  if ((${#__ipv6_tail_parts[@]})); then
    __ipv6_last="${__ipv6_tail_parts[-1]}"
    __ipv6_mapped_in_tail=1
  elif ((${#__ipv6_head_parts[@]})); then
    __ipv6_last="${__ipv6_head_parts[-1]}"
  fi
  if [[ "${__ipv6_last}" == *.* ]]; then
    local -a __ipv6_octets=()
    __dybatpho_helpers_ipv4_octets "${__ipv6_last}" __ipv6_octets || return 1
    __ipv6_mapped=(
      "$(((__ipv6_octets[0] << 8) | __ipv6_octets[1]))"
      "$(((__ipv6_octets[2] << 8) | __ipv6_octets[3]))"
    )
    if ((__ipv6_mapped_in_tail)); then
      unset '__ipv6_tail_parts[-1]'
    else
      unset '__ipv6_head_parts[-1]'
    fi
  else
    __ipv6_mapped_in_tail=0
  fi

  local -a __ipv6_lead=() __ipv6_trail=()
  local __ipv6_part
  for __ipv6_part in ${__ipv6_head_parts[@]+"${__ipv6_head_parts[@]}"}; do
    [[ "${__ipv6_part}" =~ ${__DYBATPHO_HELPERS_RE_IPV6_GROUP} ]] || return 1
    __ipv6_lead+=("$((16#${__ipv6_part}))")
  done
  for __ipv6_part in ${__ipv6_tail_parts[@]+"${__ipv6_tail_parts[@]}"}; do
    [[ "${__ipv6_part}" =~ ${__DYBATPHO_HELPERS_RE_IPV6_GROUP} ]] || return 1
    __ipv6_trail+=("$((16#${__ipv6_part}))")
  done
  if ((${#__ipv6_mapped[@]})); then
    if ((__ipv6_mapped_in_tail)); then
      __ipv6_trail+=("${__ipv6_mapped[@]}")
    else
      __ipv6_lead+=("${__ipv6_mapped[@]}")
    fi
  fi

  local __ipv6_have=$((${#__ipv6_lead[@]} + ${#__ipv6_trail[@]}))
  local __ipv6_index
  if ((__ipv6_has_double)); then
    # `::` has to stand for at least one group, or it would be spelled `:`.
    ((__ipv6_have <= 7)) || return 1
    for ((__ipv6_index = __ipv6_have; __ipv6_index < 8; __ipv6_index++)); do
      __ipv6_lead+=(0)
    done
  else
    ((__ipv6_have == 8)) || return 1
  fi

  __ipv6_out=("${__ipv6_lead[@]}" ${__ipv6_trail[@]+"${__ipv6_trail[@]}"})
}

#######################################
# @description Split a CIDR block into its address and prefix length.
#   Each output may be `-` when the caller only wants to know whether the
#   value is a CIDR block.
# @arg $1 string Block such as `10.0.0.0/8` or `2001:db8::/32`
# @arg $2 string Name of the variable receiving the address, or `-`
# @arg $3 string Name of the variable receiving the prefix length, or `-`
# @arg $4 string Name of the variable receiving the IP version, or `-`
# @set The three named variables
# @exitcode 1 The value is not a CIDR block
# @internal
#######################################
function __dybatpho_helpers_parse_cidr {
  local __cidr_block="$1"
  local __cidr_unwanted_address __cidr_unwanted_prefix __cidr_unwanted_version
  local -n __cidr_address_out="${2/#-/__cidr_unwanted_address}"
  local -n __cidr_prefix_out="${3/#-/__cidr_unwanted_prefix}"
  local -n __cidr_version_out="${4/#-/__cidr_unwanted_version}"
  [[ "${__cidr_block}" == */* ]] || return 1
  local __cidr_address="${__cidr_block%/*}"
  local __cidr_prefix="${__cidr_block##*/}"
  [[ "${__cidr_prefix}" =~ ^[0-9]{1,3}$ ]] || return 1
  # A leading zero here is the same ambiguity as in an octet, and `/08` is not a
  # prefix length anyone writes on purpose.
  [[ "${__cidr_prefix}" == "0" || "${__cidr_prefix}" != 0* ]] || return 1

  local __cidr_version
  local -a __cidr_parts=()
  if __dybatpho_helpers_ipv4_octets "${__cidr_address}" __cidr_parts; then
    __cidr_version=4
  elif __dybatpho_helpers_ipv6_groups "${__cidr_address}" __cidr_parts; then
    __cidr_version=6
  else
    return 1
  fi
  if ((__cidr_version == 4)); then
    ((10#${__cidr_prefix} <= 32)) || return 1
  else
    ((10#${__cidr_prefix} <= 128)) || return 1
  fi

  __cidr_address_out="${__cidr_address}"
  __cidr_prefix_out="$((10#${__cidr_prefix}))"
  __cidr_version_out="${__cidr_version}"
}

#######################################
# @description Check whether a value matches a supported shell-oriented condition.
#   `number` is a plain decimal, optionally signed, with an optional fraction
#   and exponent (`-1.5`, `.5`, `1e3`), the same as `validate_is number`.
#   `int` is an optionally signed decimal integer with no leading zero, since
#   Bash arithmetic reads one as octal. Neither accepts blanks, `0x`, a
#   locale's decimal comma, or the quoted character codes `printf` takes.
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
      # Written out rather than read from the constants above: a child shell
      # inherits this exported function without the module's variables.
      [[ "${input}" =~ ^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]
      return "$?"
      ;;
    int)
      [[ "${input}" =~ ^[+-]?(0|[1-9][0-9]*)$ ]]
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
  local __dybatpho_default_env_name __dybatpho_default_env_value
  dybatpho::expect_args __dybatpho_default_env_name __dybatpho_default_env_value -- "$@"
  [[ "${__dybatpho_default_env_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] \
    || dybatpho::die "Invalid environment variable name: ${__dybatpho_default_env_name}"
  if [[ -z "${!__dybatpho_default_env_name:-}" ]]; then
    printf -v "${__dybatpho_default_env_name}" '%s' "${__dybatpho_default_env_value}"
    # shellcheck disable=SC2163 # exporting the variable this name refers to, as intended
    export "${__dybatpho_default_env_name}"
  fi
  printf '%s\n' "${!__dybatpho_default_env_name}"
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
  local __dybatpho_helpers_assert_condition
  dybatpho::expect_args __dybatpho_helpers_assert_condition -- "$@"
  local __dybatpho_helpers_assert_message="${2:-Assertion failed: ${__dybatpho_helpers_assert_condition}}"
  eval "${__dybatpho_helpers_assert_condition}" || dybatpho::die "${__dybatpho_helpers_assert_message}"
}

#######################################
# @description Compute how long the nth retry waits.
#   Exponential from a base delay, capped, with optional jitter. This is the one
#   policy behind `dybatpho::retry`, the HTTP retries in `network.sh` and the
#   requeue delays of `dybatpho::queue_work`. Jitter matters when several
#   machines retry the same failing dependency: without it they all come back
#   at the same instant, which is the load that kept it down.
#
#   The delay doubles until it reaches the cap rather than being raised to a
#   power, so a long run of retries never overflows the arithmetic. An override,
#   such as a server's `Retry-After`, replaces the computed delay and is still
#   capped and jittered.
# @arg $1 string Name of the variable receiving the delay in seconds
# @arg $2 number Attempt number, counting from 1
# @arg $3 number Base delay, default is `DYBATPHO_RETRY_BASE_DELAY`
# @arg $4 number Longest delay, default is `DYBATPHO_RETRY_MAX_DELAY`
# @arg $5 bool Add up to one base delay of random jitter, default is `DYBATPHO_RETRY_JITTER`
# @arg $6 number Delay to use instead of the computed one, when not empty
# @set The named variable
# @internal
#######################################
function __dybatpho_helpers_backoff_into {
  local -n __dybatpho_helpers_bo_ref="$1"
  local -i __dybatpho_helpers_bo_attempt="$2"
  local -i __dybatpho_helpers_bo_base="${3:-${DYBATPHO_RETRY_BASE_DELAY}}"
  local -i __dybatpho_helpers_bo_max="${4:-${DYBATPHO_RETRY_MAX_DELAY}}"
  local __dybatpho_helpers_bo_jitter="${5:-${DYBATPHO_RETRY_JITTER}}"
  local __dybatpho_helpers_bo_override="${6-}"

  local -i __dybatpho_helpers_bo_delay="${__dybatpho_helpers_bo_base}"
  while ((__dybatpho_helpers_bo_attempt > 1 && __dybatpho_helpers_bo_delay < __dybatpho_helpers_bo_max)); do
    __dybatpho_helpers_bo_delay=$((__dybatpho_helpers_bo_delay * 2))
    __dybatpho_helpers_bo_attempt=$((__dybatpho_helpers_bo_attempt - 1))
  done
  [[ -z "${__dybatpho_helpers_bo_override}" ]] \
    || __dybatpho_helpers_bo_delay="${__dybatpho_helpers_bo_override}"
  ((__dybatpho_helpers_bo_delay <= __dybatpho_helpers_bo_max)) \
    || __dybatpho_helpers_bo_delay="${__dybatpho_helpers_bo_max}"
  if dybatpho::is true "${__dybatpho_helpers_bo_jitter}"; then
    ((__dybatpho_helpers_bo_delay += RANDOM % (__dybatpho_helpers_bo_base + 1)))
    ((__dybatpho_helpers_bo_delay <= __dybatpho_helpers_bo_max)) \
      || __dybatpho_helpers_bo_delay="${__dybatpho_helpers_bo_max}"
  fi
  __dybatpho_helpers_bo_ref="${__dybatpho_helpers_bo_delay}"
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
  # Prefixed: the command is evaluated in this function's scope, so a plain
  # `count` or `delay` here would shadow the caller's own variable of that name.
  local __dybatpho_retry_retries __dybatpho_retry_command
  dybatpho::expect_args __dybatpho_retry_retries __dybatpho_retry_command -- "$@"
  shift 2
  local __dybatpho_retry_exit_code __dybatpho_retry_count __dybatpho_retry_delay

  __dybatpho_retry_count=0
  until eval "${__dybatpho_retry_command}"; do
    __dybatpho_retry_exit_code="$?"
    __dybatpho_retry_count="$((__dybatpho_retry_count + 1))"
    if [[ "${__dybatpho_retry_count}" -le "${__dybatpho_retry_retries}" ]]; then
      __dybatpho_helpers_backoff_into __dybatpho_retry_delay "${__dybatpho_retry_count}"
      if declare -F __dybatpho_metrics_key > /dev/null; then
        dybatpho::metrics_counter_inc dybatpho_retry_attempts_total
      fi
      dybatpho::progress "Retrying in ${__dybatpho_retry_delay} seconds" \
        "(${__dybatpho_retry_count}/${__dybatpho_retry_retries})..."
      sleep "${__dybatpho_retry_delay}" || true
    else
      # Out of retries :(
      if declare -F __dybatpho_metrics_key > /dev/null; then
        dybatpho::metrics_counter_inc dybatpho_retry_exhausted_total
      fi
      dybatpho::warn "No more retries left to run ${1:-${__dybatpho_retry_command}}."
      return "${__dybatpho_retry_exit_code}"
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
  # Prefixed for the same reason as `dybatpho::retry`: the command runs in this
  # function's scope and must see the caller's variables, not these.
  local __dybatpho_retry_retries __dybatpho_retry_delay_seconds __dybatpho_retry_command
  dybatpho::expect_args __dybatpho_retry_retries __dybatpho_retry_delay_seconds \
    __dybatpho_retry_command -- "$@"
  shift 3
  local __dybatpho_retry_exit_code=0 __dybatpho_retry_count=0
  until eval "${__dybatpho_retry_command}"; do
    __dybatpho_retry_exit_code=$?
    __dybatpho_retry_count=$((__dybatpho_retry_count + 1))
    if ((__dybatpho_retry_count > __dybatpho_retry_retries)); then
      dybatpho::warn "No more retries left to run ${1:-${__dybatpho_retry_command}}."
      return "${__dybatpho_retry_exit_code}"
    fi
    dybatpho::progress "Retrying in ${__dybatpho_retry_delay_seconds} seconds" \
      "(${__dybatpho_retry_count}/${__dybatpho_retry_retries})..."
    sleep "${__dybatpho_retry_delay_seconds}" || true
  done
}

#######################################
# @description Open an interactive breakpoint for debugging a running script.
# @noargs
# @env DYBATPHO_REPL_HISTORY_FILE string Override where REPL history is persisted between breakpoint sessions
# @tip This helper is intended for interactive local debugging, not unattended CI or production runs
#######################################
function dybatpho::breakpoint {
  local __dybatpho_helpers_bp_key
  local __dybatpho_helpers_bp_section="--------------------------------------------------------------------------------"
  local __dybatpho_helpers_bp_help
  local __dybatpho_helpers_bp_format='%s\n    d: run debugger\n    c: display source file\n    o: list options\n'
  __dybatpho_helpers_bp_format+='    p: list parameters\n    a: list indexed array\n    A: list associative array\n'
  __dybatpho_helpers_bp_format+='    q: quit'
  # shellcheck disable=SC2059 # the format is built above, not taken from input
  printf -v __dybatpho_helpers_bp_help "${__dybatpho_helpers_bp_format}" \
    "${__dybatpho_helpers_bp_section}"
  local __dybatpho_helpers_bp_source_file="${BASH_SOURCE[1]:-bash}"
  __dybatpho_log fatal "Breakpoint hit. Current line: ${__dybatpho_helpers_bp_source_file}:${BASH_LINENO[0]}" stderr \
    "1;36"
  while true; do
    printf "%s\n" "${__dybatpho_helpers_bp_help}" >&2
    read -n1 -s -r __dybatpho_helpers_bp_key
    case "${__dybatpho_helpers_bp_key}" in
      o) # kcov(skip)
        shopt -s >&2
        set -o >&2
        ;;
      p) declare -p >&2 ;;
      a) declare -a >&2 ;;
      A) declare -A >&2 ;;
      q) # kcov(skip)
        echo "${__dybatpho_helpers_bp_section}" >&2
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
        local __dybatpho_helpers_bp_line
        # shellcheck disable=SC2162
        while read -e -p "Debugger (Ctrl-d to exit)> " __dybatpho_helpers_bp_line; do
          [[ "${__dybatpho_helpers_bp_line}" == "exit" ]] && break
          if [[ "${__dybatpho_helpers_bp_line}" =~ ^[[:space:]]*(rm|dd)([[:space:]]|$) ]]; then
            dybatpho::error "Ignore dangerous command."
            continue
          fi
          echo "${__dybatpho_helpers_bp_line}" >> "${DYBATPHO_REPL_HISTORY_FILE}"
          history -s "${__dybatpho_helpers_bp_line}"
          eval "${__dybatpho_helpers_bp_line} >&2"
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
        if [[ "${__dybatpho_helpers_bp_source_file}" != "bash" ]]; then
          echo "${__dybatpho_helpers_bp_section}" >&2
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
# @internal
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
# @description Write a function name with the `dybatpho::` prefix it may have
#   been given without into a named variable.
# @arg $1 string Name of the variable receiving the full function name
# @arg $2 string Function name, with or without a prefix
# @set The named variable
# @internal
#######################################
function __dybatpho_helpers_qualify_into {
  local -n __dybatpho_helpers_qualify_out="$1"
  local __dybatpho_helpers_qualify_name="${2-}"
  if [[ "${__dybatpho_helpers_qualify_name}" == dybatpho::* ||
    "${__dybatpho_helpers_qualify_name}" == __dybatpho_* ]]; then
    __dybatpho_helpers_qualify_out="${__dybatpho_helpers_qualify_name}"
  else
    __dybatpho_helpers_qualify_out="dybatpho::${__dybatpho_helpers_qualify_name}"
  fi
}

#######################################
# @description Write the module a loaded source file belongs to into a named
#   variable.
#   A module is recognised by its place rather than its name: a file directly
#   inside a `src` directory is that module, and the bootstrap is `init`.
#   Anything else is refused, because a bundle holds every module in one file
#   and answering with that file's name would attribute every function in the
#   library to a module called `dybatpho.bundle`.
# @arg $1 string Name of the variable receiving the module name
# @arg $2 string Path of a file the library was loaded from
# @set The named variable
# @exitcode 1 The file is not a module source
# @internal
#######################################
function __dybatpho_helpers_module_of_into {
  local -n __dybatpho_helpers_module_out="$1"
  local __dybatpho_helpers_module_file="$2"
  local __dybatpho_helpers_module_name="${__dybatpho_helpers_module_file##*/}"
  # The bootstrap is recognised by its own name rather than by comparing against
  # `DYBATPHO_DIR`: that variable is fully resolved while the path Bash reports
  # is whatever was written at the `source`, and a library reached through a
  # symlink would never match.
  if [[ "${__dybatpho_helpers_module_name}" == "init.sh" ]]; then
    __dybatpho_helpers_module_out=init
    return 0
  fi
  local __dybatpho_helpers_module_directory="${__dybatpho_helpers_module_file%/*}"
  [[ "${__dybatpho_helpers_module_directory##*/}" == "src" ]] || return 1
  __dybatpho_helpers_module_out="${__dybatpho_helpers_module_name%.sh}"
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
  __dybatpho_helpers_qualify_into name "${name}"

  local -a location=()
  mapfile -t location < <(__dybatpho_helpers_locate "${name}")
  ((${#location[@]} == 2)) || return 1

  if [[ "${want_path}" == true ]]; then
    printf '%s:%s\n' "${location[0]}" "${location[1]}"
    return 0
  fi
  local module
  __dybatpho_helpers_module_of_into module "${location[0]}" || return 1
  printf '%s\n' "${module}"
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
  __dybatpho_helpers_qualify_into name "${name}"

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
  if __dybatpho_helpers_module_of_into origin "${file}"; then
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

  # Every name is located by one `declare -F` under `extdebug`, switched on in
  # the process substitution only, so the caller's shell never sees the option
  # and the list costs one process rather than several per function.
  local name line file owner attributable=false
  while read -r name line file; do
    [[ -n "${file}" && "${line}" =~ ^[0-9]+$ ]] || continue
    # Bash reports the path as it was written at the `source`; a `.` or `..`
    # segment would hide the `src` directory a module is recognised by.
    if [[ "${file}" == *'//'* || "${file}" == *'/./'* || "${file}" == *'/../'* ]]; then
      file="$(dybatpho::path_normalize "${file}" 2> /dev/null || printf '%s' "${file}")"
    fi
    if __dybatpho_helpers_module_of_into owner "${file}"; then
      attributable=true
      if [[ "${owner}" == "${module}" ]]; then
        printf '%s\n' "${name}"
      fi
    fi
  done < <(
    shopt -s extdebug
    declare -F "${names[@]}" 2> /dev/null
  )
  # An empty list would read as "that module exports nothing", which is not what
  # happened: a bundle holds every module in one file and none of them can be
  # told apart.
  [[ "${attributable}" == true ]] \
    || dybatpho::die \
      "${FUNCNAME[0]}: No function belongs to a module, which is how a bundle looks; ask without a module"
}
