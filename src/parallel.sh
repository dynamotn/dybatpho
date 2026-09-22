#!/usr/bin/env bash
# @file parallel.sh
# @brief Utilities for running work concurrently with a bounded worker pool
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
#######################################
function __dybatpho_parallel_jobs {
  local -n __jobs_out="$1"
  local requested="${2-}"
  [[ -n "${requested}" && "${requested}" != "0" ]] || requested="${DYBATPHO_PARALLEL_JOBS}"
  if [[ -z "${requested}" || "${requested}" == "0" ]]; then
    # One job per processor is the useful default; without a way to ask, four is
    # a middle ground that neither idles a big machine nor swamps a small one.
    requested="$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || printf '4')"
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
# @description Return success when a finished job has failed.
# @arg $1 string Directory holding the captured output
# @arg $2 number Number of jobs
# @exitcode 0 A finished job failed
# @exitcode 1 Every job that finished so far succeeded
#######################################
function __dybatpho_parallel_any_failed {
  local directory total index status
  dybatpho::expect_args directory total -- "$@"
  for ((index = 0; index < total; index++)); do
    [[ -f "${directory}/${index}.status" ]] || continue
    status="$(cat -- "${directory}/${index}.status")"
    [[ "${status}" == "0" ]] || return 0
  done
  return 1
}

#######################################
# @description Drop the process IDs that have already been reaped.
#   `wait -n` reaps one child, so at least one entry disappears on every pass
#   and the pool always makes progress.
# @arg $1 string Name of the array holding the process IDs
#######################################
function __dybatpho_parallel_prune {
  local -n __pids="$1"
  local pid
  local -a alive=()
  for pid in ${__pids[@]+"${__pids[@]}"}; do
    kill -0 "${pid}" 2> /dev/null && alive+=("${pid}")
  done
  __pids=(${alive[@]+"${alive[@]}"})
}

#######################################
# @description Run a bounded pool over jobs started by a launcher function.
#   The launcher receives a job index and the capture directory, and starts that
#   one job. The pool waits with `wait -n`, so a finished job is replaced right
#   away rather than at the end of a batch. Exit codes travel through files
#   rather than through `wait`, because `wait -n` reports a status without
#   saying which job it belongs to.
# @arg $1 number Jobs to run at once
# @arg $2 string Launcher function name
# @arg $3 number Number of jobs
# @set DYBATPHO_PARALLEL_STATUS
# @exitcode 0 Every job that ran succeeded
# @exitcode 1 At least one job failed
#######################################
function __dybatpho_parallel_pool {
  local concurrency launcher total directory index status failed=0 stop=false
  dybatpho::expect_args concurrency launcher total -- "$@"

  dybatpho::create_temp directory "/" "parallel"
  DYBATPHO_PARALLEL_STATUS=()

  # Job control gives every job its own process group, which is what makes it
  # possible to end a job together with whatever it started. It is restored
  # afterwards so the caller's shell is left as it was found.
  local __dybatpho_parallel_monitor="off"
  case "$-" in
    *m*) __dybatpho_parallel_monitor="on" ;;
  esac
  set -m
  for ((index = 0; index < total; index++)); do
    DYBATPHO_PARALLEL_STATUS[index]=""
  done

  # A job left running after an interrupt keeps working on output nobody will
  # read, so the pool ends its children before the shell goes away.
  declare -ga __dybatpho_parallel_pids=()
  # The list of process IDs has to expand when the signal arrives, not now,
  # which is why this is a single-quoted string.
  # shellcheck disable=SC2016
  dybatpho::trap '__dybatpho_parallel_terminate ${__dybatpho_parallel_pids[@]+"${__dybatpho_parallel_pids[@]}"}' \
    SIGINT SIGTERM

  for ((index = 0; index < total; index++)); do
    # Fail-fast leaves the remaining jobs unstarted, which the status of an
    # unstarted job records as empty rather than as a failure.
    [[ "${stop}" == true ]] && continue

    "${launcher}" "${index}" "${directory}" &
    __dybatpho_parallel_pids+=("$!")

    if ((${#__dybatpho_parallel_pids[@]} >= concurrency)); then
      # `wait -n` blocks until one job finishes, which keeps the pool full
      # instead of draining it between batches.
      wait -n 2> /dev/null || true
      __dybatpho_parallel_prune __dybatpho_parallel_pids
      if dybatpho::is true "${DYBATPHO_PARALLEL_FAILFAST}" \
        && __dybatpho_parallel_any_failed "${directory}" "${total}"; then
        stop=true
        __dybatpho_parallel_terminate ${__dybatpho_parallel_pids[@]+"${__dybatpho_parallel_pids[@]}"}
        __dybatpho_parallel_pids=()
      fi
    fi
  done

  __dybatpho_parallel_wait_all

  for ((index = 0; index < total; index++)); do
    [[ -f "${directory}/${index}.status" ]] || continue
    status="$(cat -- "${directory}/${index}.status")"
    DYBATPHO_PARALLEL_STATUS[index]="${status}"
    [[ "${status}" == "0" ]] || failed=$((failed + 1))
  done

  [[ "${__dybatpho_parallel_monitor}" == "on" ]] || set +m

  __dybatpho_parallel_flush "${directory}" "${total}"
  ((failed == 0))
}

#######################################
# @description Wait for every job the pool still tracks.
# @noargs
#######################################
function __dybatpho_parallel_wait_all {
  local pid
  for pid in ${__dybatpho_parallel_pids[@]+"${__dybatpho_parallel_pids[@]}"}; do
    wait "${pid}" 2> /dev/null || true
  done
  __dybatpho_parallel_pids=()
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
# @arg $1 number Jobs to run at once, or `0` to use the CPU count
# @arg $2 string Command or function to run for each item
# @arg $@ string Items, one job each
# @set DYBATPHO_PARALLEL_STATUS
# @stdout Standard output of every job, replayed in submission order
# @stderr Standard error of every job, replayed in submission order
# @env DYBATPHO_PARALLEL_JOBS number Job count used when `0` is requested
# @env DYBATPHO_PARALLEL_FAILFAST string When true-like, stop at the first failure
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
  local concurrency command
  dybatpho::expect_args concurrency command -- "$@"
  shift 2
  __dybatpho_parallel_jobs concurrency "${concurrency}"
  (($#)) || return 0

  local -a __dybatpho_parallel_items=("$@")
  if dybatpho::is true "${DRY_RUN}"; then
    local item
    for item in "${__dybatpho_parallel_items[@]}"; do
      dybatpho::dry_run "${command}" "${item}"
    done
    return 0
  fi

  #######################################
  # @description Start one item's job, capturing its output and exit code.
  # @arg $1 number Job index
  # @arg $2 string Capture directory
  #######################################
  # shellcheck disable=SC2329 # run by the pool through its name
  __dybatpho_parallel_launch_item() {
    local index="$1" directory="$2" code=0
    # The job runs one subshell deeper so that a command calling `exit` ends
    # only itself. Without that, the exit would skip the line below and the job
    # would be reported as never having run.
    ("${command}" "${__dybatpho_parallel_items[index]}") \
      > "${directory}/${index}.out" 2> "${directory}/${index}.err" || code=$?
    printf '%s' "${code}" > "${directory}/${index}.status"
  }

  __dybatpho_parallel_pool "${concurrency}" __dybatpho_parallel_launch_item \
    "${#__dybatpho_parallel_items[@]}"
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
# @arg $1 number Jobs to run at once, or `0` to use the CPU count
# @arg $@ string Shell command strings, one job each
# @set DYBATPHO_PARALLEL_STATUS
# @stdout Standard output of every job, replayed in submission order
# @stderr Standard error of every job, replayed in submission order
# @env DYBATPHO_PARALLEL_FAILFAST string When true-like, stop at the first failure
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
  #######################################
  # shellcheck disable=SC2329 # run by the pool through its name
  __dybatpho_parallel_launch_command() {
    local index="$1" directory="$2" code=0
    # `exit` is ordinary inside a command string, so the evaluation runs one
    # subshell deeper: otherwise the exit would skip the line below and the job
    # would be reported as never having run.
    (eval "${__dybatpho_parallel_commands[index]}") \
      > "${directory}/${index}.out" 2> "${directory}/${index}.err" || code=$?
    printf '%s' "${code}" > "${directory}/${index}.status"
  }

  __dybatpho_parallel_pool "${concurrency}" __dybatpho_parallel_launch_command \
    "${#__dybatpho_parallel_commands[@]}"
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
# @stdout The job's exit code, or `skipped` when fail-fast stopped it from running
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
#   A job that fail-fast prevented from starting is not counted: it did not run,
#   so it did not fail.
# @noargs
# @stdout Number of failed jobs
#######################################
function dybatpho::parallel_failed {
  local status failed=0
  for status in ${DYBATPHO_PARALLEL_STATUS[@]+"${DYBATPHO_PARALLEL_STATUS[@]}"}; do
    [[ -n "${status}" && "${status}" != "0" ]] && failed=$((failed + 1))
  done
  printf '%s\n' "${failed}"
}
