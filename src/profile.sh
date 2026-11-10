# shellcheck shell=bash
# @file profile.sh
# @brief Utilities for finding where a Bash script spends its time
# @namespace dybatpho
# @description
#   This module times named blocks of a script and reports, per name, how many
#   times it ran, its total time, and its self time -- the total less the time
#   of the blocks that ran inside it, so a nested block is never counted twice.
#
#   Blocks are marked by hand with `dybatpho::profile_begin` and
#   `dybatpho::profile_end`, or `dybatpho::profile_run` around one command. For
#   one run, `dybatpho::profile_start` times every function instead, through a
#   `DEBUG` trap; that costs time on every command, so it does nothing unless
#   `DYBATPHO_PROFILE` is set, and it needs Bash 5's `EPOCHREALTIME`.
# @usage
#   ### Time the blocks you suspect
#
#   ```bash
#   dybatpho::profile_begin "load config"
#   load_config
#   dybatpho::profile_end "load config"
#   dybatpho::profile_run sync -- sync_all
#   dybatpho::profile_report
#   ```
#
#   ### Time every function, for one run
#
#   ```bash
#   dybatpho::profile_start   # only with DYBATPHO_PROFILE=true
#   main "$@"
#   dybatpho::profile_stop
#   dybatpho::profile_report
#   ```
# @see
#   - `example/profile_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_PROFILE bool [default: false] Let `dybatpho::profile_start` time every function
DYBATPHO_PROFILE="${DYBATPHO_PROFILE:-false}"

# Per name: calls, total and self time in microseconds.
declare -gA __DYBATPHO_PROFILE_CALLS=() __DYBATPHO_PROFILE_TOTAL=() __DYBATPHO_PROFILE_SELF=()
# The open blocks, innermost last: name, start, and time of the blocks ended inside.
__DYBATPHO_PROFILE_NAMES=()
__DYBATPHO_PROFILE_STARTS=()
__DYBATPHO_PROFILE_CHILDREN=()
# Per-function timing: whether it is on, the functions it opened, and what to put back.
__DYBATPHO_PROFILE_AUTO=false
__DYBATPHO_PROFILE_AUTO_STACK=()
__DYBATPHO_PROFILE_SAVED_TRAP=""
__DYBATPHO_PROFILE_SAVED_FUNCTRACE=false

#######################################
# @description Read the clock in microseconds: from `EPOCHREALTIME` where Bash
#   has it, starting no process, else from the library's millisecond clock.
# @arg $1 string Name of the variable receiving the time
# @set The named variable
# @internal
#######################################
function __dybatpho_profile_now_into {
  local -n __dybatpho_profile_now="$1"
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local whole="${EPOCHREALTIME%%[.,]*}" frac="${EPOCHREALTIME#*[.,]}000000"
    __dybatpho_profile_now=$((whole * 1000000 + 10#${frac:0:6}))
  else
    local ms
    __dybatpho_log_now_ms_into ms
    __dybatpho_profile_now=$((ms * 1000))
  fi
}

#######################################
# @description Open a block.
# @arg $1 string Block name
# @internal
#######################################
function __dybatpho_profile_push {
  local now
  __dybatpho_profile_now_into now
  __DYBATPHO_PROFILE_NAMES+=("$1")
  __DYBATPHO_PROFILE_STARTS+=("${now}")
  __DYBATPHO_PROFILE_CHILDREN+=(0)
}

#######################################
# @description End the innermost open block, record its times, and count its
#   time against its parent's self time.
# @noargs
# @internal
#######################################
function __dybatpho_profile_pop {
  local now last=$((${#__DYBATPHO_PROFILE_NAMES[@]} - 1))
  ((last >= 0)) || return 0
  __dybatpho_profile_now_into now
  local name="${__DYBATPHO_PROFILE_NAMES[last]}"
  local elapsed=$((now - __DYBATPHO_PROFILE_STARTS[last]))
  ((elapsed >= 0)) || elapsed=0
  __DYBATPHO_PROFILE_CALLS["${name}"]=$((${__DYBATPHO_PROFILE_CALLS["${name}"]:-0} + 1))
  __DYBATPHO_PROFILE_TOTAL["${name}"]=$((${__DYBATPHO_PROFILE_TOTAL["${name}"]:-0} + elapsed))
  __DYBATPHO_PROFILE_SELF["${name}"]=$((${__DYBATPHO_PROFILE_SELF["${name}"]:-0} + elapsed - \
    __DYBATPHO_PROFILE_CHILDREN[last]))
  unset '__DYBATPHO_PROFILE_NAMES[last]' '__DYBATPHO_PROFILE_STARTS[last]' '__DYBATPHO_PROFILE_CHILDREN[last]'
  if ((last > 0)); then
    __DYBATPHO_PROFILE_CHILDREN[last - 1]=$((__DYBATPHO_PROFILE_CHILDREN[last - 1] + elapsed))
  fi
}

#######################################
# @description Start timing a block. Blocks nest: one begun inside another is
#   counted in the outer block's total and not in its self time.
# @example
#   dybatpho::profile_begin "load config"
#   load_config
#   dybatpho::profile_end "load config"
#
# @arg $1 string Block name
#######################################
function dybatpho::profile_begin {
  local name
  dybatpho::expect_args name -- "$@"
  __dybatpho_profile_push "${name}"
}

#######################################
# @description Stop timing the innermost open block, which must be the one named.
# @arg $1 string Block name
# @exitcode 1 Stop script when no block is open, or the innermost is another one
#######################################
function dybatpho::profile_end {
  local name
  dybatpho::expect_args name -- "$@"
  local last=$((${#__DYBATPHO_PROFILE_NAMES[@]} - 1))
  ((last >= 0)) || dybatpho::die "${FUNCNAME[0]}: No profile block is open, ending ${name}"
  [[ "${__DYBATPHO_PROFILE_NAMES[last]}" == "${name}" ]] || dybatpho::die \
    "${FUNCNAME[0]}: profile_end ${name}, but the innermost open block is ${__DYBATPHO_PROFILE_NAMES[last]}"
  __dybatpho_profile_pop
}

#######################################
# @description Run a command inside a block, ending the block whatever the
#   command returns.
# @example
#   dybatpho::profile_run sync -- rsync -a src/ dest/
#
# @arg $1 string Block name
# @arg $2 string Literal `--`
# @arg $@ string Command and its arguments
# @exitcode other Exit code of the command
#######################################
function dybatpho::profile_run {
  local __dybatpho_profile_run_name __dybatpho_profile_run_separator
  dybatpho::expect_args __dybatpho_profile_run_name __dybatpho_profile_run_separator -- "$@"
  shift 2
  [[ "${__dybatpho_profile_run_separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: name -- command [args...]"
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Expected a command after --"
  local __dybatpho_profile_run_status=0
  __dybatpho_profile_push "${__dybatpho_profile_run_name}"
  "$@" || __dybatpho_profile_run_status=$?
  __dybatpho_profile_pop
  return "${__dybatpho_profile_run_status}"
}

#######################################
# @description The `DEBUG` trap of per-function timing: compare the functions
#   on the stack with the ones it has open, ending those that returned and
#   opening those that were entered. The profiler and the library's own
#   functions are left out.
# @noargs
# @internal
#######################################
function __dybatpho_profile_tick {
  local -a stack=()
  local i fn
  # FUNCNAME[0] is this function; the outermost call is last.
  for ((i = ${#FUNCNAME[@]} - 1; i >= 1; i--)); do
    fn="${FUNCNAME[i]}"
    case "${fn}" in
      main | source | dybatpho::* | __dybatpho*) ;;
      *) stack+=("${fn}") ;;
    esac
  done
  local same=0
  while ((same < ${#stack[@]} && same < ${#__DYBATPHO_PROFILE_AUTO_STACK[@]})) \
    && [[ "${stack[same]}" == "${__DYBATPHO_PROFILE_AUTO_STACK[same]}" ]]; do
    same=$((same + 1))
  done
  while ((${#__DYBATPHO_PROFILE_AUTO_STACK[@]} > same)); do
    __dybatpho_profile_pop
    unset '__DYBATPHO_PROFILE_AUTO_STACK[${#__DYBATPHO_PROFILE_AUTO_STACK[@]}-1]'
  done
  for ((i = same; i < ${#stack[@]}; i++)); do
    __dybatpho_profile_push "${stack[i]}"
    __DYBATPHO_PROFILE_AUTO_STACK+=("${stack[i]}")
  done
}

#######################################
# @description Time every function from now on, each as a block of its name,
#   until `dybatpho::profile_stop`. A `DEBUG` trap does the timing, so every
#   command costs more while it runs; it does nothing unless
#   `DYBATPHO_PROFILE` is true-like, and it needs Bash 5's `EPOCHREALTIME`.
# @example
#   DYBATPHO_PROFILE=true ./deploy.sh   # deploy.sh calls profile_start ... profile_stop
#
# @noargs
# @env DYBATPHO_PROFILE bool [default: false] Turn per-function timing on
# @stderr A warning when it was asked for on a Bash without `EPOCHREALTIME`
#######################################
function dybatpho::profile_start {
  dybatpho::is true "${DYBATPHO_PROFILE}" || return 0
  [[ "${__DYBATPHO_PROFILE_AUTO}" != true ]] || return 0
  if [[ -z "${EPOCHREALTIME:-}" ]]; then
    dybatpho::warn "Per-function profiling needs Bash 5 (EPOCHREALTIME); not starting it"
    return 0
  fi
  __DYBATPHO_PROFILE_SAVED_TRAP="$(trap -p DEBUG)"
  __DYBATPHO_PROFILE_SAVED_FUNCTRACE=false
  [[ "$-" != *T* ]] || __DYBATPHO_PROFILE_SAVED_FUNCTRACE=true
  __DYBATPHO_PROFILE_AUTO=true
  __DYBATPHO_PROFILE_AUTO_STACK=()
  set -T
  trap '__dybatpho_profile_tick' DEBUG
}

#######################################
# @description Stop timing every function, end the blocks it opened, and put
#   back the `functrace` setting the caller had and its `DEBUG` trap.
#   Bash shows a function the caller's `DEBUG` trap only when `functrace` is
#   on, as under Bats: a trap set without it cannot be saved, and is cleared.
# @noargs
#######################################
function dybatpho::profile_stop {
  [[ "${__DYBATPHO_PROFILE_AUTO}" == true ]] || return 0
  trap - DEBUG
  __DYBATPHO_PROFILE_AUTO=false
  while ((${#__DYBATPHO_PROFILE_AUTO_STACK[@]})); do
    __dybatpho_profile_pop
    unset '__DYBATPHO_PROFILE_AUTO_STACK[${#__DYBATPHO_PROFILE_AUTO_STACK[@]}-1]'
  done
  # The caller's trap goes back while `functrace` is still on: set from a
  # function without it, a `DEBUG` trap would be dropped when the function returns.
  # `trap -p` printed the command that sets the caller's trap again.
  # dyshellint disable=BSG040
  [[ -z "${__DYBATPHO_PROFILE_SAVED_TRAP}" ]] || eval "${__DYBATPHO_PROFILE_SAVED_TRAP}"
  [[ "${__DYBATPHO_PROFILE_SAVED_FUNCTRACE}" == true ]] || set +T
}

#######################################
# @description Format microseconds as milliseconds with three decimals.
# @arg $1 string Name of the variable receiving the text
# @arg $2 number Microseconds
# @set The named variable
# @internal
#######################################
function __dybatpho_profile_ms_into {
  printf -v "$1" '%d.%03d' $(($2 / 1000)) $(($2 % 1000))
}

#######################################
# @description Print the recorded blocks: name, calls, total and self time in
#   milliseconds, the most self time first, then by name. Blocks still open are
#   not counted.
# @example
#   dybatpho::profile_report
#   dybatpho::profile_report --tsv > profile.tsv
#
# @arg $1 string [optional] `--tsv` for tab-separated rows with a header, instead of an aligned table
# @stdout The report
#######################################
# dyshellint disable=BSG050 # its one argument is an optional flag, which expect_args cannot express
function dybatpho::profile_report {
  local format=table
  case "${1-}" in
    --tsv) format=tsv ;;
    '') ;;
    *) dybatpho::die "${FUNCNAME[0]}: Unknown option: $1" ;;
  esac
  # A report holds a few dozen names at most: sorted here, with no process.
  local -a names=()
  local name i j swap
  for name in "${!__DYBATPHO_PROFILE_CALLS[@]}"; do
    names+=("${name}")
  done
  for ((i = 1; i < ${#names[@]}; i++)); do
    for ((j = i; j > 0; j--)); do
      local a="${names[j - 1]}" b="${names[j]}"
      # Read out first: a name is caller text, and inside arithmetic a subscript
      # such as `x$(cmd)` would run as a command on older Bash.
      local self_a="${__DYBATPHO_PROFILE_SELF["${a}"]}" self_b="${__DYBATPHO_PROFILE_SELF["${b}"]}"
      ((self_b > self_a)) || { ((self_b == self_a)) && [[ "${b}" < "${a}" ]]; } || break
      swap="${names[j]}"
      names[j]="${names[j - 1]}"
      names[j - 1]="${swap}"
    done
  done
  local separator=$'\t' total self table="name|calls|total ms|self ms"
  [[ "${format}" != tsv ]] || printf 'name\tcalls\ttotal_ms\tself_ms\n'
  [[ "${format}" == tsv ]] || separator="|"
  for name in ${names[@]+"${names[@]}"}; do
    __dybatpho_profile_ms_into total "${__DYBATPHO_PROFILE_TOTAL[${name}]}"
    __dybatpho_profile_ms_into self "${__DYBATPHO_PROFILE_SELF[${name}]}"
    local row="${name}${separator}${__DYBATPHO_PROFILE_CALLS[${name}]}${separator}${total}${separator}${self}"
    if [[ "${format}" == tsv ]]; then
      printf '%s\n' "${row}"
    else
      table+=$'\n'"${row}"
    fi
  done
  [[ "${format}" != tsv ]] || return 0
  __dybatpho_helpers_need_module table __dybatpho_table_split_row "${FUNCNAME[0]}"
  dybatpho::table_align "${table}" "|" "left,right,right,right"
}

#######################################
# @description Forget every recorded block and every open one.
# @noargs
#######################################
function dybatpho::profile_reset {
  __DYBATPHO_PROFILE_CALLS=()
  __DYBATPHO_PROFILE_TOTAL=()
  __DYBATPHO_PROFILE_SELF=()
  __DYBATPHO_PROFILE_NAMES=()
  __DYBATPHO_PROFILE_STARTS=()
  __DYBATPHO_PROFILE_CHILDREN=()
}
