# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it uses `eval`, which is how the spec engine builds
# a parser.
# dyshellint disable=BSG050,BSG011,BSG040
# @file parallel.sh
# @brief Utilities for running work concurrently with a bounded worker pool
# @namespace dybatpho
# @description
#   This module runs a list of jobs several at a time and reports what each one
#   did. It exists because the hand-written version of this loop gets three
#   things wrong: it launches every job at once and overwhelms the machine, it
#   lets concurrent jobs interleave their output into an unreadable mess, and it
#   loses the exit code of everything except the last job.
#
#   Each job's output is captured while it runs and replayed afterwards in the
#   order the jobs were submitted, so the result reads as though the jobs had
#   run one after another. Each job's exit code is recorded separately, and the
#   run as a whole fails when any job failed.
#
#   A job runs in a subshell of the calling shell, so it can call any function
#   the caller has defined without exporting anything.
# @see
#   - `example/parallel_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_PARALLEL_JOBS number Default number of jobs to run at once, default is the CPU count
DYBATPHO_PARALLEL_JOBS="${DYBATPHO_PARALLEL_JOBS:-0}"
# @env DYBATPHO_PARALLEL_FAILFAST string When true-like, stop launching and end running jobs once one fails
DYBATPHO_PARALLEL_FAILFAST="${DYBATPHO_PARALLEL_FAILFAST:-false}"
# @env DYBATPHO_PARALLEL_TIMEOUT string Longest a job may run, such as `90`, `5m` or `1h30m`; empty or `0` is no limit
DYBATPHO_PARALLEL_TIMEOUT="${DYBATPHO_PARALLEL_TIMEOUT:-}"
# @env DYBATPHO_PARALLEL_PROGRESS string When true-like, report on standard error how many jobs have finished
DYBATPHO_PARALLEL_PROGRESS="${DYBATPHO_PARALLEL_PROGRESS:-false}"
# @env DYBATPHO_PARALLEL_STATUS array Exit code of each job of the last run, in submission order
declare -ga DYBATPHO_PARALLEL_STATUS=()

#######################################
# @description Resolve how many jobs to run at once.
#   The count is returned through a variable rather than printed, because a
#   command substitution would validate inside a subshell, where a rejected
#   count could not stop the caller from running the jobs anyway.
# @arg $1 string Name of the variable that receives the count
# @arg $2 string Requested count, or empty/`0` to decide automatically
# @set The named variable, to a positive job count
# @exitcode 1 The requested count is not a positive integer
# @internal
#######################################
function __dybatpho_parallel_jobs {
  local -n __jobs_out="$1"
  local requested="${2-}"
  [[ -n "${requested}" && "${requested}" != "0" ]] || requested="${DYBATPHO_PARALLEL_JOBS}"
  if [[ -z "${requested}" || "${requested}" == "0" ]]; then
    # One job per processor is the useful default; without a way to ask, four is
    # a middle ground that neither idles a big machine nor swamps a small one.
    requested="$(dybatpho::cpu_count || printf '4')"
  fi
  [[ "${requested}" =~ ^[1-9][0-9]*$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Job count must be a positive integer, got '${requested}'"
  __jobs_out="${requested}"
}

#######################################
# @description End every job still running in the pool.
#   A job is a subshell that usually has children of its own, and ending the
#   subshell alone would orphan them. The pool runs with job control on, which
#   puts each job in its own process group, so the whole group can be ended at
#   once.
# @arg $@ number Process IDs to end, each the leader of its job's process group
# @internal
#######################################
function __dybatpho_parallel_terminate {
  local pid
  for pid in "$@"; do
    kill -TERM -- -"${pid}" 2> /dev/null || kill -TERM "${pid}" 2> /dev/null || true
  done
  for pid in "$@"; do
    wait "${pid}" 2> /dev/null || true
  done
}

#######################################
# @description Replay each job's captured output, in submission order.
# @arg $1 string Directory holding the captured output
# @arg $2 number Number of jobs
# @stdout Standard output of every job, in order
# @stderr Standard error of every job, in order
# @internal
#######################################
function __dybatpho_parallel_flush {
  local directory total index
  dybatpho::expect_args directory total -- "$@"
  for ((index = 0; index < total; index++)); do
    [[ -s "${directory}/${index}.out" ]] && cat -- "${directory}/${index}.out"
    [[ -s "${directory}/${index}.err" ]] && cat -- "${directory}/${index}.err" >&2
  done
  return 0
}

#######################################
# @description Read the options that may lead a pool call.
#   Options come before the job count and nothing after it is read as one, so an
#   item that happens to start with `--` stays an item. Every option sets a
#   variable the calling entry point declared, which is how the pool reads them
#   without a second argument list.
# @arg $1 string Name of the variable that receives how many arguments were options
# @arg $@ string The arguments the entry point was called with
# @set __dybatpho_parallel_opt_failfast `true` when `--fail-fast` was given
# @set __dybatpho_parallel_opt_timeout The duration given to `--timeout`
# @set __dybatpho_parallel_opt_progress `true` when `--progress` was given
# @exitcode 1 Stop the script on an unknown option, or `--timeout` without a duration
# @internal
#######################################
function __dybatpho_parallel_options {
  local -n __dybatpho_parallel_consumed="$1"
  shift
  local -a __dybatpho_parallel_parsed=()
  local __dybatpho_parallel_spec="--fail-fast=__dybatpho_parallel_opt_failfast"
  __dybatpho_parallel_spec+=" --progress=__dybatpho_parallel_opt_progress"
  __dybatpho_parallel_spec+=" --timeout=__dybatpho_parallel_opt_timeout:duration"
  __dybatpho_helpers_options_into - __dybatpho_parallel_parsed "${__dybatpho_parallel_spec}" leading,attached '--*' \
    "${FUNCNAME[1]}: Unknown option '{option}'" "${FUNCNAME[1]}: {option} needs a {noun}" -- "$@"
  __dybatpho_parallel_consumed="${__dybatpho_parallel_parsed[0]}"
}

#######################################
# @description Resolve the per-job time limit into a number of seconds.
#   The limit is returned through a variable for the same reason as the job
#   count: a rejected duration has to be able to stop the caller.
#
#   A bare number of seconds is read here. Any other form, such as `5m` or
#   `1h30m`, is read by `dybatpho::date_parse_duration`, and the `date` module
#   is not a dependency of this one: a pool without a limit, or with a limit in
#   seconds, should not load it. The guard names an internal helper, since a
#   child shell inherits the exported `dybatpho::` functions without the
#   internals they call.
# @arg $1 string Name of the variable that receives the seconds, `0` for no limit
# @arg $2 string Duration from `--timeout`, or empty to read the configuration
# @exitcode 1 Stop the script when the duration cannot be read, is negative, or
#   needs the `date` module and it is not loaded
# @internal
#######################################
function __dybatpho_parallel_timeout {
  local -n __dybatpho_parallel_timeout_out="$1"
  local requested="${2:-${DYBATPHO_PARALLEL_TIMEOUT}}" seconds=0
  if [[ "${requested}" =~ ^[0-9]{1,9}$ ]]; then
    seconds=$((10#${requested}))
  elif [[ -n "${requested}" ]]; then
    # The refusal is exercised by "--timeout asks for the date module" in a
    # child shell, which kcov does not follow.
    local needs_date="${FUNCNAME[2]} --timeout ${requested} needs the date module"
    declare -F __dybatpho_date_parse > /dev/null \
      || dybatpho::die "${needs_date}, load it with: dybatpho::load date" # kcov(skip)
    # Exercised under `run` by "an invalid timeout is refused", which kcov
    # cannot see because `dybatpho::die` ends the shell.
    local invalid="Timeout must be a duration such as 90, 5m or 1h30m, got '${requested}'"
    dybatpho::date_parse_duration seconds "${requested}" 2> /dev/null \
      || dybatpho::die "${FUNCNAME[1]}: ${invalid}" # kcov(skip)
    ((seconds >= 0)) \
      || dybatpho::die "${FUNCNAME[1]}: Timeout must not be negative, got '${requested}'" # kcov(skip)
  fi
  __dybatpho_parallel_timeout_out="${seconds}"
}

#######################################
# @description End one job once it has run for too long.
#   The pool runs one of these beside every job when a limit is set. It asks the
#   job's process group to stop, then kills whatever is left after
#   `DYBATPHO_TIMEOUT_KILL_AFTER` seconds, the grace `dybatpho::run_with_timeout`
#   gives too. The marker it leaves is how the pool tells a job that timed out
#   from one that was ended for another reason, since an ended job writes no
#   status of its own.
# @arg $1 number Process ID of the job, the leader of its process group
# @arg $2 number Job index
# @arg $3 string Capture directory
# @arg $4 number Seconds the job may run
# @internal
#######################################
function __dybatpho_parallel_watch {
  local pid="$1" index="$2" directory="$3" seconds="$4"
  local grace="${DYBATPHO_TIMEOUT_KILL_AFTER:-5}" tick
  [[ "${grace}" =~ ^[0-9]+$ ]] || grace=5
  sleep "${seconds}"
  [[ ! -f "${directory}/${index}.status" ]] || return 0
  : > "${directory}/${index}.timeout"
  kill -TERM -- -"${pid}" 2> /dev/null || return 0
  for ((tick = 0; tick < grace * 10; tick++)); do
    kill -0 -- -"${pid}" 2> /dev/null || return 0
    sleep 0.1
  done
  kill -KILL -- -"${pid}" 2> /dev/null || true
}

#######################################
# @description Report how far the pool has got, when progress was asked for.
#   The `tui` progress bar draws it when that module is loaded, which also gives
#   a log line per percentage step when standard error is not a terminal. The
#   module is not a dependency: without it, each finished job prints one plain
#   line. Progress only ever goes to standard error, so the jobs' replayed
#   output on standard output stays exactly what the jobs wrote.
# @arg $1 string `start`, `step` or `stop`
# @arg $2 number Total jobs for `start`, jobs just finished for `step`
# @stderr The progress bar, or a `Jobs: <done>/<total> finished` line per step
# @internal
#######################################
function __dybatpho_parallel_progress {
  local action="$1" count="${2-0}"
  [[ "${__dybatpho_parallel_progress}" == true ]] || return 0
  if declare -F __dybatpho_tui_progress_render > /dev/null; then
    case "${action}" in
      start) dybatpho::tui_progress_start "Jobs" "${count}" ;;
      step) ((count == 0)) || dybatpho::tui_progress_step "${count}" ;;
      *) dybatpho::tui_progress_stop ;;
    esac
    return 0
  fi
  case "${action}" in
    start)
      __dybatpho_parallel_done=0
      __dybatpho_parallel_total="${count}"
      ;;
    step)
      ((count > 0)) || return 0
      __dybatpho_parallel_done=$((__dybatpho_parallel_done + count))
      printf 'Jobs: %s/%s finished\n' "${__dybatpho_parallel_done}" "${__dybatpho_parallel_total}" >&2
      ;;
    *) ;; # kcov(skip) empty arm: the plain report has nothing to close
  esac
}

#######################################
# @description Reap the jobs that have finished and act on what they reported.
#   `wait -n` blocks until at least one job ends, so every call makes progress.
#   Exit codes travel through files rather than through `wait`, because
#   `wait -n` reports a status without saying which job it belongs to. Under
#   fail-fast, the first failure seen ends every job still running and stops the
#   pool from starting more. A job its watchdog ended is recorded as exit `124`,
#   the code `timeout` uses, and that watchdog is left to finish its grace
#   period; every other job's watchdog is ended with the job.
# @arg $1 string Directory holding the captured output
# @set __dybatpho_parallel_pids Only the jobs still running
# @set __dybatpho_parallel_stop `true` once fail-fast has stopped the pool
# @internal
#######################################
function __dybatpho_parallel_reap {
  local directory="$1" pid index status message
  local -a alive=() finished=() finished_pids=()
  wait -n 2> /dev/null || true
  for pid in ${__dybatpho_parallel_pids[@]+"${__dybatpho_parallel_pids[@]}"}; do
    if kill -0 "${pid}" 2> /dev/null; then
      alive+=("${pid}")
    else
      finished+=("${__dybatpho_parallel_index_of[${pid}]}")
      finished_pids+=("${pid}")
    fi
  done
  __dybatpho_parallel_pids=(${alive[@]+"${alive[@]}"})

  for pid in ${finished_pids[@]+"${finished_pids[@]}"}; do
    index="${__dybatpho_parallel_index_of[${pid}]}"
    if [[ ! -f "${directory}/${index}.status" && -f "${directory}/${index}.timeout" ]]; then
      printf '124' > "${directory}/${index}.status"
      printf -v message 'Job %s (%s) timed out after %ss' \
        "${index}" "${__dybatpho_parallel_labels[index]}" "${__dybatpho_parallel_limit}"
      dybatpho::warn "${message}"
    elif [[ -n "${__dybatpho_parallel_watchdog_of[${pid}]-}" ]]; then
      __dybatpho_parallel_terminate "${__dybatpho_parallel_watchdog_of[${pid}]}"
    fi
  done

  __dybatpho_parallel_progress step "${#finished[@]}"

  for index in ${finished[@]+"${finished[@]}"}; do
    [[ -f "${directory}/${index}.status" ]] || continue
    status="$(< "${directory}/${index}.status")"
    [[ "${status}" != "0" && "${__dybatpho_parallel_stop}" != true ]] || continue
    dybatpho::is true "${__dybatpho_parallel_failfast}" || continue
    __dybatpho_parallel_stop=true
    printf -v message 'Job %s (%s) failed with exit %s, stopping the remaining jobs' \
      "${index}" "${__dybatpho_parallel_labels[index]}" "${status}"
    dybatpho::warn "${message}"
  done

  if [[ "${__dybatpho_parallel_stop}" == true ]] && ((${#__dybatpho_parallel_pids[@]})); then
    local -a watchdogs=()
    for pid in "${__dybatpho_parallel_pids[@]}"; do
      __dybatpho_parallel_terminated+=("${__dybatpho_parallel_index_of[${pid}]}")
      [[ -z "${__dybatpho_parallel_watchdog_of[${pid}]-}" ]] \
        || watchdogs+=("${__dybatpho_parallel_watchdog_of[${pid}]}")
    done
    __dybatpho_parallel_terminate "${__dybatpho_parallel_pids[@]}" ${watchdogs[@]+"${watchdogs[@]}"}
    __dybatpho_parallel_pids=()
  fi
  return 0
}

#######################################
# @description Run a bounded pool over jobs started by a launcher function.
#   The launcher receives a job index and the capture directory, and starts that
#   one job. A finished job is replaced right away rather than at the end of a
#   batch, and the pool keeps watching while the last jobs drain, so fail-fast
#   ends a long job that is still running when another one fails.
# @arg $1 number Jobs to run at once
# @arg $2 string Launcher function name
# @arg $3 number Number of jobs
# @arg $4 string Name of the array labelling each job in diagnostics
# @set DYBATPHO_PARALLEL_STATUS
# @exitcode 0 Every job that ran succeeded
# @exitcode 1 At least one job failed
# @internal
#######################################
function __dybatpho_parallel_pool {
  local concurrency launcher total labels directory index status failed=0
  dybatpho::expect_args concurrency launcher total labels -- "$@"
  local -n __dybatpho_parallel_labels="${labels}"

  # Resolved before anything is created, so a refused limit leaves nothing behind.
  local __dybatpho_parallel_limit
  __dybatpho_parallel_timeout __dybatpho_parallel_limit "${__dybatpho_parallel_opt_timeout:-}"

  dybatpho::create_temp directory "/" "parallel"
  DYBATPHO_PARALLEL_STATUS=()

  local __dybatpho_parallel_failfast="${DYBATPHO_PARALLEL_FAILFAST}"
  [[ "${__dybatpho_parallel_opt_failfast:-false}" != true ]] || __dybatpho_parallel_failfast=true
  local __dybatpho_parallel_progress=false
  if [[ "${__dybatpho_parallel_opt_progress:-false}" == true ]] \
    || dybatpho::is true "${DYBATPHO_PARALLEL_PROGRESS}"; then
    __dybatpho_parallel_progress=true
  fi
  local __dybatpho_parallel_done=0 __dybatpho_parallel_total=0
  local __dybatpho_parallel_stop=false
  local -A __dybatpho_parallel_index_of=() __dybatpho_parallel_watchdog_of=()
  local -a __dybatpho_parallel_terminated=()

  # Job control gives every job its own process group, which is what makes it
  # possible to end a job together with whatever it started. It is restored
  # afterwards so the caller's shell is left as it was found.
  local __dybatpho_parallel_monitor="off"
  case "$-" in
    *m*) __dybatpho_parallel_monitor="on" ;;
    *) ;;
  esac
  set -m
  for ((index = 0; index < total; index++)); do
    DYBATPHO_PARALLEL_STATUS[index]=""
  done

  # A job left running after an interrupt keeps working on output nobody will
  # read, so the pool ends its children before the shell goes away. The
  # handlers it found are put back at the end, so a script running pools in a
  # loop does not collect one more handler per call.
  local __dybatpho_parallel_traps
  __dybatpho_process_traps_save_into __dybatpho_parallel_traps SIGINT SIGTERM
  declare -ga __dybatpho_parallel_pids=() __dybatpho_parallel_watchdogs=()
  # The lists of process IDs have to expand when the signal arrives, not now,
  # which is why this is a single-quoted string; the escaped newline inside it
  # continues the command when the trap runs.
  # shellcheck disable=SC2016
  dybatpho::trap '__dybatpho_parallel_terminate \
    ${__dybatpho_parallel_pids[@]+"${__dybatpho_parallel_pids[@]}"} \
    ${__dybatpho_parallel_watchdogs[@]+"${__dybatpho_parallel_watchdogs[@]}"}' \
    SIGINT SIGTERM

  __dybatpho_parallel_progress start "${total}"
  for ((index = 0; index < total; index++)); do
    # Fail-fast leaves the remaining jobs unstarted, which the status of an
    # unstarted job records as empty rather than as a failure.
    [[ "${__dybatpho_parallel_stop}" != true ]] || break

    "${launcher}" "${index}" "${directory}" &
    __dybatpho_parallel_pids+=("$!")
    __dybatpho_parallel_index_of[$!]="${index}"
    if ((__dybatpho_parallel_limit > 0)); then
      # The watchdog leads a process group of its own, so ending the job never
      # ends the watchdog, and it holds no output stream the caller is reading.
      __dybatpho_parallel_watch "$!" "${index}" "${directory}" "${__dybatpho_parallel_limit}" \
        < /dev/null > /dev/null 2>&1 &
      __dybatpho_parallel_watchdog_of[${__dybatpho_parallel_pids[-1]}]="$!"
      __dybatpho_parallel_watchdogs+=("$!")
    fi

    while ((${#__dybatpho_parallel_pids[@]} >= concurrency)); do
      __dybatpho_parallel_reap "${directory}"
    done
  done

  while ((${#__dybatpho_parallel_pids[@]})); do
    __dybatpho_parallel_reap "${directory}"
  done
  # A watchdog still running is one finishing the grace period of a job it
  # ended; every other one was ended with its job and is only reaped here.
  local watchdog
  for watchdog in ${__dybatpho_parallel_watchdogs[@]+"${__dybatpho_parallel_watchdogs[@]}"}; do
    wait "${watchdog}" 2> /dev/null || true
  done
  __dybatpho_parallel_watchdogs=()
  __dybatpho_parallel_progress stop

  for index in ${__dybatpho_parallel_terminated[@]+"${__dybatpho_parallel_terminated[@]}"}; do
    DYBATPHO_PARALLEL_STATUS[index]="terminated"
  done
  for ((index = 0; index < total; index++)); do
    [[ -f "${directory}/${index}.status" ]] || continue
    status="$(< "${directory}/${index}.status")"
    DYBATPHO_PARALLEL_STATUS[index]="${status}"
    [[ "${status}" == "0" ]] || failed=$((failed + 1))
  done

  [[ "${__dybatpho_parallel_monitor}" == "on" ]] || set +m
  __dybatpho_process_traps_restore "${__dybatpho_parallel_traps}" SIGINT SIGTERM

  __dybatpho_parallel_flush "${directory}" "${total}"
  ((failed == 0))
}

#######################################
# @description Run one command once per item, several items at a time.
#   The command and each item are passed as separate arguments, so an item
#   containing a space or a quote is handled as one value rather than re-parsed
#   as shell syntax.
# @example
#   function _convert { dybatpho::info "converting $1"; convert "$1" "${1%.png}.webp"; }
#   dybatpho::parallel_map 4 _convert ./images/*.png
#
# @example
#   # Let the job count follow the machine.
#   dybatpho::parallel_map 0 _check "${hosts[@]}"
#
# @example
#   # Stop everything as soon as one host fails.
#   dybatpho::parallel_map --fail-fast 4 _deploy "${hosts[@]}"
#
# @example
#   # Give up on a host that takes more than half a minute.
#   dybatpho::parallel_map --timeout 30s 8 _check "${hosts[@]}"
#
# @example
#   # Show a bar while a long list converts; the output stays clean.
#   dybatpho::parallel_map --progress 4 _convert ./images/*.png > converted.log
#
# @option --fail-fast Stop starting jobs and end the running ones once a job fails
# @option --timeout <duration> End a job that runs longer than this, recording exit `124`
# @option --progress Report on standard error how many jobs have finished
# @option -- End of options, for a job count that is not one
# @arg $1 number Jobs to run at once, or `0` to use the CPU count
# @arg $2 string Command or function to run for each item
# @arg $@ string Items, one job each
# @set DYBATPHO_PARALLEL_STATUS
# @stdout Standard output of every job, replayed in submission order
# @stderr Standard error of every job, replayed in submission order
# @env DYBATPHO_PARALLEL_JOBS number Job count used when `0` is requested
# @env DYBATPHO_PARALLEL_FAILFAST string When true-like, stop at the first failure
# @env DYBATPHO_PARALLEL_TIMEOUT string Per-job limit used when `--timeout` is not given
# @env DYBATPHO_PARALLEL_PROGRESS string When true-like, report progress as `--progress` does
# @env DYBATPHO_TIMEOUT_KILL_AFTER number Seconds a timed-out job has to stop before it is killed, default is `5`
# @env DRY_RUN string When true-like, report the jobs instead of running them
# @exitcode 0 Every job succeeded
# @exitcode 1 At least one job failed
# @tip A function defined by the caller works as the command, because each job
#   runs in a subshell of the calling shell
# @tip The per-job exit codes are kept in the calling shell, so a call made
#   inside `$(...)` or a pipeline reports its own output but leaves
#   `dybatpho::parallel_status` unchanged
#######################################
function dybatpho::parallel_map {
  local __dybatpho_parallel_opt_failfast=false __dybatpho_parallel_opt_timeout=""
  local __dybatpho_parallel_opt_progress=false consumed
  __dybatpho_parallel_options consumed "$@"
  shift "${consumed}"
  local concurrency command
  dybatpho::expect_args concurrency command -- "$@"
  shift 2
  __dybatpho_parallel_jobs concurrency "${concurrency}"
  (($#)) || return 0

  local -a __dybatpho_parallel_items=("$@")
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    local job
    for job in "${__dybatpho_parallel_items[@]}"; do
      dybatpho::dry_run "${command}" "${job}"
    done
    return 0
  fi

  #######################################
  # @description Start one item's job, capturing its output and exit code.
  # @arg $1 number Job index
  # @arg $2 string Capture directory
  # @internal
  #######################################
  # shellcheck disable=SC2329 # run by the pool through its name
  function __dybatpho_parallel_launch_item {
    local index="$1" directory="$2" code=0
    # The job runs one subshell deeper so that a command calling `exit` ends
    # only itself. Without that, the exit would skip the line below and the job
    # would be reported as never having run.
    ("${command}" "${__dybatpho_parallel_items[index]}") \
      > "${directory}/${index}.out" 2> "${directory}/${index}.err" || code=$?
    printf '%s' "${code}" > "${directory}/${index}.status"
  }

  __dybatpho_parallel_pool "${concurrency}" __dybatpho_parallel_launch_item \
    "${#__dybatpho_parallel_items[@]}" __dybatpho_parallel_items
}

#######################################
# @description Run several shell commands at once, each given as one string.
#   Use this when the jobs differ from one another; use `dybatpho::parallel_map`
#   when the same command runs over a list, because that form needs no quoting.
# @example
#   dybatpho::parallel_run 3 \
#     "npm run build" \
#     "cargo build --release" \
#     "go build ./..."
#
# @option --fail-fast Stop starting jobs and end the running ones once a job fails
# @option --timeout <duration> End a job that runs longer than this, recording exit `124`
# @option --progress Report on standard error how many jobs have finished
# @option -- End of options
# @arg $1 number Jobs to run at once, or `0` to use the CPU count
# @arg $@ string Shell command strings, one job each
# @set DYBATPHO_PARALLEL_STATUS
# @stdout Standard output of every job, replayed in submission order
# @stderr Standard error of every job, replayed in submission order
# @env DYBATPHO_PARALLEL_FAILFAST string When true-like, stop at the first failure
# @env DYBATPHO_PARALLEL_TIMEOUT string Per-job limit used when `--timeout` is not given
# @env DYBATPHO_PARALLEL_PROGRESS string When true-like, report progress as `--progress` does
# @env DYBATPHO_TIMEOUT_KILL_AFTER number Seconds a timed-out job has to stop before it is killed, default is `5`
# @env DRY_RUN string When true-like, report the commands instead of running them
# @exitcode 0 Every job succeeded
# @exitcode 1 At least one job failed
# @tip Each string is evaluated as a shell command, so quote anything inside it
#   that must survive that second round of parsing
# @tip The per-job exit codes are kept in the calling shell, so a call made
#   inside `$(...)` or a pipeline reports its own output but leaves
#   `dybatpho::parallel_status` unchanged
#######################################
function dybatpho::parallel_run {
  local __dybatpho_parallel_opt_failfast=false __dybatpho_parallel_opt_timeout=""
  local __dybatpho_parallel_opt_progress=false consumed
  __dybatpho_parallel_options consumed "$@"
  shift "${consumed}"
  local concurrency
  dybatpho::expect_args concurrency -- "$@"
  shift
  __dybatpho_parallel_jobs concurrency "${concurrency}"
  (($#)) || return 0

  local -a __dybatpho_parallel_commands=("$@")
  if dybatpho::is true "${DRY_RUN}"; then
    local command
    for command in "${__dybatpho_parallel_commands[@]}"; do
      dybatpho::dry_run "${command}"
    done
    return 0
  fi

  #######################################
  # @description Start one command's job, capturing its output and exit code.
  # @arg $1 number Job index
  # @arg $2 string Capture directory
  # @internal
  #######################################
  # shellcheck disable=SC2329 # run by the pool through its name
  function __dybatpho_parallel_launch_command {
    local index="$1" directory="$2" code=0
    # `exit` is ordinary inside a command string, so the evaluation runs one
    # subshell deeper: otherwise the exit would skip the line below and the job
    # would be reported as never having run.
    (eval "${__dybatpho_parallel_commands[index]}") \
      > "${directory}/${index}.out" 2> "${directory}/${index}.err" || code=$?
    printf '%s' "${code}" > "${directory}/${index}.status"
  }

  __dybatpho_parallel_pool "${concurrency}" __dybatpho_parallel_launch_command \
    "${#__dybatpho_parallel_commands[@]}" __dybatpho_parallel_commands
}

#######################################
# @description Print the exit code of one job of the last run.
# @example
#   dybatpho::parallel_map 4 _check "${hosts[@]}" || true
#   for index in $(seq 0 $(($(dybatpho::parallel_count) - 1))); do
#     dybatpho::print "${hosts[index]} -> $(dybatpho::parallel_status "${index}")"
#   done
#
# @arg $1 number Job index, counting from zero in submission order
# @stdout The job's exit code (`124` when `--timeout` ended it), `skipped` when fail-fast stopped it from
#   starting, or `terminated` when fail-fast ended it while it was running
# @exitcode 1 There is no job with that index
#######################################
function dybatpho::parallel_status {
  local index
  dybatpho::expect_args index -- "$@"
  [[ "${index}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Job index must be a non-negative integer, got '${index}'"
  ((index < ${#DYBATPHO_PARALLEL_STATUS[@]})) \
    || dybatpho::die "${FUNCNAME[0]}: No job with index ${index} in the last run"
  if [[ -z "${DYBATPHO_PARALLEL_STATUS[index]}" ]]; then
    printf 'skipped\n'
  else
    printf '%s\n' "${DYBATPHO_PARALLEL_STATUS[index]}"
  fi
}

#######################################
# @description Print how many jobs the last run had.
# @noargs
# @stdout Job count
#######################################
function dybatpho::parallel_count {
  printf '%s\n' "${#DYBATPHO_PARALLEL_STATUS[@]}"
}

#######################################
# @description Print how many jobs of the last run failed.
#   A job that fail-fast prevented from starting, or ended while it ran, is not
#   counted: it was stopped because another job failed, not because it did.
# @noargs
# @stdout Number of failed jobs
#######################################
function dybatpho::parallel_failed {
  local status failed=0
  for status in ${DYBATPHO_PARALLEL_STATUS[@]+"${DYBATPHO_PARALLEL_STATUS[@]}"}; do
    case "${status}" in
      "" | 0 | terminated) ;; # kcov(skip) empty arm, taken by every passing job
      *) failed=$((failed + 1)) ;;
    esac
  done
  printf '%s\n' "${failed}"
}
