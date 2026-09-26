#!/usr/bin/env bash
# @file process.sh
# @brief Utilities for process handling
# @description
#   This module contains helpers for script termination, signal handling, trap
#   composition, deferred cleanup, and dry-run execution. It also bounds how
#   long a command may run, supervises named background jobs, and reads and
#   writes PID files.
#
# @see
#   - `example/process_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_USED_ERR_HANDLER bool Internal flag set after `dybatpho::register_err_handler`
DYBATPHO_USED_ERR_HANDLER=false
# @env DYBATPHO_USED_KILLED_HANDLER bool Internal flag set after `dybatpho::register_killed_handler`
DYBATPHO_USED_KILLED_HANDLER=false
# @env DRY_RUN string When true-like, `dybatpho::dry_run` prints commands instead of executing them
DRY_RUN="${DRY_RUN:-}"
export DRY_RUN
# @env DYBATPHO_CLEANUP_PATHS array Paths registered by `dybatpho::cleanup_file_on_exit`, each as `<pid>:<path>`
declare -ga DYBATPHO_CLEANUP_PATHS=()
# Shell that already owns the cleanup trap, so it is installed exactly once.
__dybatpho_cleanup_trap_pid=""
# @env DYBATPHO_TIMEOUT_KILL_AFTER number Seconds between SIGTERM and SIGKILL when a timed or background job is ended, default is `5`
DYBATPHO_TIMEOUT_KILL_AFTER="${DYBATPHO_TIMEOUT_KILL_AFTER:-5}"
export DYBATPHO_TIMEOUT_KILL_AFTER
# @env DYBATPHO_BACKGROUND_NAMES array Names of the background jobs started by `dybatpho::background_run`, in submission order
declare -ga DYBATPHO_BACKGROUND_NAMES=()
# @env DYBATPHO_BACKGROUND_PIDS array Process ID of each background job, keyed by job name
declare -gA DYBATPHO_BACKGROUND_PIDS=()
# @env DYBATPHO_BACKGROUND_STATUS array Exit code of each background job that `dybatpho::wait_all` has reaped, keyed by job name
declare -gA DYBATPHO_BACKGROUND_STATUS=()
# Whether each background job leads its own process group, so `kill_children`
# never signals the caller's own group by mistake.
declare -gA DYBATPHO_BACKGROUND_GROUPS=()
# Cached answer of the one-off probe for a usable `timeout` binary.
__dybatpho_process_timeout_probe=""

#######################################
# @description Log a fatal message and stop the current script or process.
# @arg $1 string Message
# @arg $2 number Exit code, default is 1
# @exitcode $2 Exit the current shell with the requested code
#######################################
function dybatpho::die {
  # kcov(disabled) - always terminates the shell, so it only runs in subshells
  local message exit_code
  dybatpho::expect_args message -- "$@"
  exit_code=${2:-1}
  dybatpho::fatal "${message}" 1
  exit "${exit_code}"
  # kcov(enabled)
}

#######################################
# @description Register the ERR trap handler used by dybatpho scripts.
# @set DYBATPHO_USED_ERR_HANDLER
# @noargs
#######################################
function dybatpho::register_err_handler {
  set -E
  # shellcheck disable=SC2034
  DYBATPHO_USED_ERR_HANDLER=true
  dybatpho::trap 'dybatpho::run_err_handler $?' ERR
}

#######################################
# @description Register handlers for SIGINT and SIGTERM.
# @set DYBATPHO_USED_KILLED_HANDLER
# @noargs
#######################################
function dybatpho::register_killed_handler {
  # shellcheck disable=SC2034
  DYBATPHO_USED_KILLED_HANDLER=true
  dybatpho::trap 'dybatpho::killed_process_handler SIGINT' SIGINT
  dybatpho::trap 'dybatpho::killed_process_handler SIGTERM' SIGTERM
}

#######################################
# @description Register both error and signal handlers.
# @noargs
# @tip This is the usual one-line setup at the top of scripts that want both error and signal handling
#######################################
function dybatpho::register_common_handlers {
  dybatpho::register_err_handler
  dybatpho::register_killed_handler
}

#######################################
# @description Handle a command failure captured by `dybatpho::register_err_handler`.
# @arg $1 number Exit code of last command
#######################################
function dybatpho::run_err_handler {
  # kcov(disabled) - always terminates the shell, so it only runs in subshells
  local exit_code
  dybatpho::expect_args exit_code -- "$@"
  local i=0
  printf -- '%s\n' "Aborting on error ${exit_code}:" "--------------------" >&2
  while caller "${i}" >&2; do
    ((i++))
  done
  exit "${exit_code}"
  # kcov(enabled)
}

#######################################
# @description Handle SIGINT or SIGTERM received by the current process.
# @arg $1 string Signal
#######################################
function dybatpho::killed_process_handler {
  # kcov(disabled) - always terminates the shell, so it only runs in subshells
  local signal
  dybatpho::expect_args signal -- "$@"

  trap - SIGINT SIGTERM EXIT
  case ${signal} in
    SIGINT)
      dybatpho::error 'Interrupt by CTRL+C'
      exit 130
      ;;
    SIGTERM)
      dybatpho::error 'Terminated'
      exit 143
      ;;
    *)
      exit 1
      ;;
  esac
  # kcov(enabled)
}

#######################################
# @description Append a command to one or more trap handlers without discarding existing traps.
# @arg $1 string Command to run when the signal is trapped
# @arg $@ string Signals to trap
#######################################
function dybatpho::trap {
  local command
  dybatpho::expect_args command -- "$@"
  shift
  #######################################
  # @description Read the current trap command registered for a signal.
  # @arg $1 string Signal name
  # @stdout Existing trap command, or an empty string when none is registered
  #######################################
  __dybatpho_process_gen_finalize_command() {
    local cmds=$(trap -p "$1")
    cmds="${cmds#*\'}"
    cmds="${cmds%\'*}"
    echo "${cmds}"
  }

  local finalize_command
  for signal in "$@"; do
    finalize_command=$(__dybatpho_process_gen_finalize_command "${signal}")
    finalize_command="${finalize_command}${finalize_command:+; }${command}"
    # shellcheck disable=SC2064,SC2086
    trap "${finalize_command}" "${signal}"
  done
}

#######################################
# @description Remove every path registered by `dybatpho::cleanup_file_on_exit`
#   from the current shell. Paths registered by another shell are left alone, so
#   a subshell exiting does not delete the temporary files its parent still
#   needs.
# @noargs
# @exitcode 0 Always, so a failed removal cannot change the shell's exit status
#######################################
function __dybatpho_cleanup_run {
  local entry pid path
  local -a remaining=()
  for entry in ${DYBATPHO_CLEANUP_PATHS[@]+"${DYBATPHO_CLEANUP_PATHS[@]}"}; do
    pid="${entry%%:*}"
    path="${entry#*:}"
    if [[ "${pid}" == "${BASHPID}" ]]; then
      [[ -e "${path}" ]] && rm -rf -- "${path}" > /dev/null 2>&1
    else
      remaining+=("${entry}")
    fi
  done
  DYBATPHO_CLEANUP_PATHS=(${remaining[@]+"${remaining[@]}"})
  return 0
}

#######################################
# @description Register a file or directory to be removed when the current shell exits.
# @arg $1 string File or directory path
# @tip `dybatpho::create_temp` already uses this internally, so call it directly only for custom temporary paths
# @note Paths are collected in `DYBATPHO_CLEANUP_PATHS` and removed by a single
#   trap installed on first use, rather than one trap command per path: a script
#   that creates many temporary files would otherwise build a trap string that
#   grows with every one of them.
#######################################
function dybatpho::cleanup_file_on_exit {
  local filepath
  dybatpho::expect_args filepath -- "$@"

  DYBATPHO_CLEANUP_PATHS+=("${BASHPID}:${filepath}")

  # One trap per shell. A subshell inherits the registry but not ownership of
  # the trap, so it installs its own and removes only what it registered.
  [[ "${__dybatpho_cleanup_trap_pid}" == "${BASHPID}" ]] && return 0
  __dybatpho_cleanup_trap_pid="${BASHPID}"

  local running_under_bats_test=false source_file
  for source_file in "${BASH_SOURCE[@]}"; do
    if [[ "${source_file}" == *.bats ]] || [[ "${source_file}" == */bats-core/* ]]; then
      running_under_bats_test=true
      break
    fi
  done

  if [[ "${running_under_bats_test}" == true ]]; then
    # `BASHPID` still equals `$$` only in the Bats test shell itself; every
    # subshell gets its own. The two need opposite treatment.
    if [[ "${BASHPID}" == "$$" ]]; then
      # The test shell's EXIT trap is how Bats reports the result. Taking it
      # over does not merely lose cleanup: a *passing* test still looks normal,
      # because Bats re-arms its trap after the body, while a *failing* one
      # disappears from the report entirely — the run ends with "Executed N-1
      # instead of N tests" and never names the test, so an intermittent
      # failure reads as a dead worker rather than as a failure. Nothing is
      # lost by staying out of the way here, because `dybatpho::create_temp`
      # already places test temporaries inside the directory Bats removes
      # itself.
      return 0
    fi
    # A subshell is the opposite case: its exit is the only chance to remove
    # what it registered, and nothing of Bats' is at stake. Replacing rather
    # than composing is deliberate — `trap -p` reports the inherited text even
    # though the trap will not fire here, so composing would append Bats'
    # teardown and report a test result once per subshell.
    trap '__dybatpho_cleanup_run' EXIT HUP INT TERM
    return 0
  fi
  dybatpho::trap '__dybatpho_cleanup_run' EXIT HUP INT TERM # kcov(skip) - tests always run under bats
}

#######################################
# @description Print a shell command instead of executing it when `DRY_RUN` is enabled.
# @example
#   DRY_RUN=true
#   dybatpho::dry_run "rm -rf ./build"
#
# @example
#   dybatpho::dry_run "ssh ${host} 'systemctl restart app'"
#
# @arg $@ string Shell command string to run
# @env DRY_RUN string Set to `true`, `yes`, `on`, or `0` to print commands instead of executing them
# @stdout Show the command instead of executing it when `DRY_RUN` is true
# @tip Pass a single shell command string because this helper executes the command with `eval`
#######################################
function dybatpho::dry_run {
  if dybatpho::is true "${DRY_RUN}"; then
    printf '🧪 DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    # shellcheck disable=2294
    if (($# == 1)); then
      eval "$1"
    else
      "$@"
    fi
  fi
}

#######################################
# @description Drop a path from the deferred-cleanup registry.
#   A temporary file that a function removes itself leaves its registration
#   behind, and a script that times hundreds of commands would carry one dead
#   entry per call to the end of the run.
# @arg $1 string Path to forget
# @set DYBATPHO_CLEANUP_PATHS
#######################################
function __dybatpho_process_forget_cleanup {
  local path
  dybatpho::expect_args path -- "$@"
  local entry
  local -a remaining=()
  for entry in ${DYBATPHO_CLEANUP_PATHS[@]+"${DYBATPHO_CLEANUP_PATHS[@]}"}; do
    if [[ "${entry#*:}" != "${path}" ]]; then
      remaining+=("${entry}")
    fi
  done
  DYBATPHO_CLEANUP_PATHS=(${remaining[@]+"${remaining[@]}"})
}

#######################################
# @description Report whether the system `timeout` is a coreutils one.
#   Only GNU and uutils coreutils are trusted: BusyBox `timeout` accepts `-k`
#   but reports a timeout as 143 rather than 124, which would break the exit
#   code this helper promises. The probe runs once and its answer is cached,
#   because the alternative is spawning a process on every timed command.
# @noargs
# @exitcode 0 A coreutils `timeout -k` is usable
# @exitcode 1 There is no `timeout`, or it is not a coreutils one
#######################################
function __dybatpho_process_has_timeout {
  if [[ -z "${__dybatpho_process_timeout_probe}" ]]; then
    if command -v timeout > /dev/null 2>&1 \
      && [[ "$(timeout --version 2> /dev/null)" == *coreutils* ]] \
      && timeout -k 1 1 true > /dev/null 2>&1; then
      __dybatpho_process_timeout_probe=yes
    else
      __dybatpho_process_timeout_probe=no
    fi
  fi
  [[ "${__dybatpho_process_timeout_probe}" == yes ]]
}

#######################################
# @description End a background job, and whatever it started, with SIGTERM and
#   then SIGKILL.
#   A job launched under job control leads its own process group, so the group
#   is signalled first: ending the job alone would orphan its children, which is
#   the usual way a "killed" build leaves a compiler running. The group kill is
#   only attempted for a job that does lead its own group, never as a blind
#   fallback, because a job that shares the caller's process group would take
#   the calling script down with it.
# @arg $1 number Process ID of the job, which is also its process group ID
# @arg $2 bool Whether the job leads its own process group
# @arg $3 number Seconds to wait after SIGTERM before sending SIGKILL
# @exitcode 0 Always, so a job that already exited cannot fail the caller
#######################################
function __dybatpho_process_end_job {
  local pid own_group kill_after
  dybatpho::expect_args pid own_group kill_after -- "$@"

  kill -0 "${pid}" 2> /dev/null || return 0
  if [[ "${own_group}" == true ]]; then
    kill -TERM -- "-${pid}" 2> /dev/null || kill -TERM "${pid}" 2> /dev/null || true
  else
    kill -TERM "${pid}" 2> /dev/null || true
  fi

  local waited=0
  while ((waited < kill_after)); do
    kill -0 "${pid}" 2> /dev/null || return 0
    sleep 1
    waited=$((waited + 1))
  done

  kill -0 "${pid}" 2> /dev/null || return 0
  if [[ "${own_group}" == true ]]; then
    kill -KILL -- "-${pid}" 2> /dev/null || kill -KILL "${pid}" 2> /dev/null || true
  else
    kill -KILL "${pid}" 2> /dev/null || true
  fi
  return 0
}

#######################################
# @description Run a command under a time limit without the `timeout` binary.
#   The command runs under job control so it leads its own process group, and a
#   watchdog subshell ends that group once the limit elapses. The watchdog
#   records that it fired by creating a marker file, rather than leaving the
#   answer to the exit status: a command killed by SIGTERM and a command that
#   chose to exit 143 are indistinguishable otherwise, and only the first is a
#   timeout.
# @arg $1 number Seconds to allow
# @arg $2 number Seconds between SIGTERM and SIGKILL
# @arg $@ string Command and arguments
# @exitcode 124 The command was still running when the limit elapsed
# @exitcode * Exit code of the command
#######################################
function __dybatpho_process_timeout_fallback {
  local seconds kill_after
  dybatpho::expect_args seconds kill_after -- "$@"
  shift 2

  local marker
  dybatpho::create_temp marker ".timeout"
  # `dybatpho::create_temp` creates the file; the watchdog signals a timeout by
  # putting something in it, so an empty marker means the command finished in
  # time.

  # Job control is what gives the command its own process group; it is restored
  # afterwards so the caller's shell is left as it was found.
  local monitor="off"
  case "$-" in
    *m*) monitor="on" ;;
  esac
  set -m

  "$@" &
  local command_pid=$!

  (
    sleep "${seconds}"
    kill -0 "${command_pid}" 2> /dev/null || exit 0
    printf 'timeout\n' > "${marker}"
    __dybatpho_process_end_job "${command_pid}" true "${kill_after}"
  ) &
  local watchdog_pid=$!

  local status=0
  wait "${command_pid}" || status=$?

  # The watchdog is still sleeping on every run that did not time out, and
  # leaving it behind would hold the script open for the whole limit.
  kill -TERM "${watchdog_pid}" 2> /dev/null || true
  wait "${watchdog_pid}" 2> /dev/null || true

  [[ "${monitor}" == "on" ]] || set +m

  local timed_out=false
  [[ -s "${marker}" ]] && timed_out=true
  rm -f -- "${marker}" > /dev/null 2>&1 || true
  __dybatpho_process_forget_cleanup "${marker}"
  [[ "${timed_out}" == true ]] && return 124
  return "${status}"
}

#######################################
# @description Run a command and end it if it takes too long.
#   The system `timeout` is used when it is available and usable, and a
#   pure-Bash watchdog takes over when it is not, which is the common case on
#   macOS, where coreutils is not installed by default. A shell function always
#   takes the Bash path, because `timeout` executes a program and cannot see the
#   caller's functions.
#
#   The command is ended with SIGTERM first and SIGKILL afterwards, so a job
#   that traps SIGTERM still gets to clean up before it is removed, and one that
#   ignores it is still removed.
# @example
#   dybatpho::run_with_timeout 30 curl -fsSL https://example.com
#
# @example
#   # A shell function works too, unlike with the `timeout` binary.
#   dybatpho::run_with_timeout 5 my_slow_function argument
#
# @example
#   dybatpho::run_with_timeout 30 ./deploy.sh || {
#     (($? == 124)) && dybatpho::die "Deploy did not finish in 30s"
#   }
#
# @arg $1 number Seconds to allow, or `0` to run without a limit
# @arg $@ string Command and arguments
# @env DYBATPHO_TIMEOUT_KILL_AFTER number Seconds between SIGTERM and SIGKILL, default is `5`
# @exitcode 124 The command was still running when the limit elapsed
# @exitcode * Exit code of the command
# @tip Compare the exit code against 124 to tell a timeout apart from a command that failed on its own
#######################################
function dybatpho::run_with_timeout {
  local seconds
  dybatpho::expect_args seconds -- "$@"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Expected: seconds command [args...]"
  [[ "${seconds}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Timeout must be a non-negative integer, got '${seconds}'"

  local kill_after="${DYBATPHO_TIMEOUT_KILL_AFTER:-5}"
  [[ "${kill_after}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: DYBATPHO_TIMEOUT_KILL_AFTER must be a non-negative integer, got '${kill_after}'"

  # Zero is "no limit", the same meaning `timeout` gives it.
  if ((seconds == 0)); then
    "$@"
    return $?
  fi

  if ! dybatpho::is function "$1" > /dev/null 2>&1 \
    && __dybatpho_process_has_timeout; then
    timeout -k "${kill_after}" "${seconds}" "$@"
    return $?
  fi
  __dybatpho_process_timeout_fallback "${seconds}" "${kill_after}" "$@"
}

#######################################
# @description Start a command in the background under a name.
#   The name is how every other helper in this group refers to the job, because
#   a process ID is both unreadable in a script and unusable once the job has
#   been reaped. Starting a second job under a name whose job is still running
#   is refused rather than silently forgetting the first one.
#
#   The job runs in a subshell of the calling shell, so it can call any function
#   the caller has defined, and it leads its own process group, so
#   `dybatpho::kill_children` can end its children along with it.
# @example
#   dybatpho::background_run api ./serve.sh --port 8080
#   dybatpho::background_run worker ./worker.sh
#   dybatpho::wait_all || dybatpho::die "A background job failed"
#
# @arg $1 string Name for the job
# @arg $@ string Command and arguments
# @set DYBATPHO_BACKGROUND_PIDS
# @set DYBATPHO_BACKGROUND_NAMES
# @exitcode 0 The job was started
# @exitcode 1 Stop the script when the name is invalid, already running, or no command was given
#######################################
function dybatpho::background_run {
  local name
  dybatpho::expect_args name -- "$@"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Expected: name command [args...]"
  [[ "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid job name: ${name}"
  if [[ -n "${DYBATPHO_BACKGROUND_PIDS[${name}]+set}" ]] \
    && kill -0 "${DYBATPHO_BACKGROUND_PIDS[${name}]}" 2> /dev/null; then
    dybatpho::die "${FUNCNAME[0]}: Job '${name}' is already running"
  fi

  local monitor="off"
  case "$-" in
    *m*) monitor="on" ;;
  esac
  set -m
  "$@" &
  local pid=$!
  [[ "${monitor}" == "on" ]] || set +m

  # A name started again after its previous job was reaped keeps its original
  # place in the order, so the order stays the submission order.
  [[ -n "${DYBATPHO_BACKGROUND_PIDS[${name}]+set}" ]] \
    || DYBATPHO_BACKGROUND_NAMES+=("${name}")
  DYBATPHO_BACKGROUND_PIDS["${name}"]="${pid}"
  DYBATPHO_BACKGROUND_GROUPS["${name}"]=true
  unset "DYBATPHO_BACKGROUND_STATUS[${name}]"
  dybatpho::debug "Started background job '${name}' as pid ${pid}"
}

#######################################
# @description Print the process ID of a background job.
# @arg $1 string Job name
# @stdout Process ID of the job
# @exitcode 0 The job is known
# @exitcode 1 No job was started under that name
#######################################
function dybatpho::background_pid {
  local name
  dybatpho::expect_args name -- "$@"
  [[ -n "${DYBATPHO_BACKGROUND_PIDS[${name}]+set}" ]] || return 1
  printf '%s\n' "${DYBATPHO_BACKGROUND_PIDS[${name}]}"
}

#######################################
# @description Print the exit code of a background job that has finished.
#   The code is only known once the job has been waited for, which is what
#   `dybatpho::wait_all` does; before that the job has no exit code to report.
# @arg $1 string Job name
# @stdout Exit code of the job
# @exitcode 0 The job has finished and its exit code was printed
# @exitcode 1 The job is unknown, or has not been waited for yet
#######################################
function dybatpho::background_status {
  local name
  dybatpho::expect_args name -- "$@"
  [[ -n "${DYBATPHO_BACKGROUND_STATUS[${name}]+set}" ]] || return 1
  printf '%s\n' "${DYBATPHO_BACKGROUND_STATUS[${name}]}"
}

#######################################
# @description Wait for every background job started by `dybatpho::background_run`.
#   Each job's exit code is recorded under its name instead of being collapsed
#   into one status, because `wait` on its own reports only the last job and a
#   script that started three of them needs to know which one failed.
# @noargs
# @set DYBATPHO_BACKGROUND_STATUS
# @exitcode 0 Every job succeeded, or there were none
# @exitcode 1 At least one job failed
# @tip Call `dybatpho::background_status <name>` afterwards to see which job failed and how
#######################################
function dybatpho::wait_all {
  local name pid status failed=0
  for name in ${DYBATPHO_BACKGROUND_NAMES[@]+"${DYBATPHO_BACKGROUND_NAMES[@]}"}; do
    pid="${DYBATPHO_BACKGROUND_PIDS[${name}]-}"
    [[ -n "${pid}" ]] || continue
    status=0
    wait "${pid}" 2> /dev/null || status=$?
    DYBATPHO_BACKGROUND_STATUS["${name}"]="${status}"
    ((status == 0)) || failed=$((failed + 1))
  done
  ((failed == 0))
}

#######################################
# @description End every background job started by `dybatpho::background_run`,
#   together with the processes those jobs started.
#   Each job is signalled with SIGTERM and then, if it is still there, SIGKILL,
#   and is waited for afterwards so it does not linger as a zombie. The registry
#   is emptied, so the same names can be started again.
# @noargs
# @env DYBATPHO_TIMEOUT_KILL_AFTER number Seconds between SIGTERM and SIGKILL, default is `5`
# @set DYBATPHO_BACKGROUND_PIDS
# @set DYBATPHO_BACKGROUND_NAMES
# @exitcode 0 Always, so a job that had already exited cannot fail the caller
# @tip Register it on a trap (`dybatpho::trap dybatpho::kill_children EXIT INT TERM`) so an interrupted script leaves nothing behind
#######################################
function dybatpho::kill_children {
  local kill_after="${DYBATPHO_TIMEOUT_KILL_AFTER:-5}"
  [[ "${kill_after}" =~ ^[0-9]+$ ]] || kill_after=5

  local name pid
  for name in ${DYBATPHO_BACKGROUND_NAMES[@]+"${DYBATPHO_BACKGROUND_NAMES[@]}"}; do
    pid="${DYBATPHO_BACKGROUND_PIDS[${name}]-}"
    [[ -n "${pid}" ]] || continue
    __dybatpho_process_end_job "${pid}" "${DYBATPHO_BACKGROUND_GROUPS[${name}]-false}" "${kill_after}"
    wait "${pid}" 2> /dev/null || true
  done

  DYBATPHO_BACKGROUND_NAMES=()
  DYBATPHO_BACKGROUND_PIDS=()
  DYBATPHO_BACKGROUND_GROUPS=()
  DYBATPHO_BACKGROUND_STATUS=()
  return 0
}

#######################################
# @description Write a process ID to a PID file.
#   The file is written to a neighbouring temporary file and moved into place,
#   so a reader never sees a half-written or empty PID file, the state that
#   makes a supervisor believe a healthy service is dead.
# @example
#   dybatpho::pid_file_write /var/run/app.pid
#   dybatpho::trap 'dybatpho::pid_file_remove /var/run/app.pid' EXIT
#
# @arg $1 string Path of the PID file
# @arg $2 number Process ID to record, default is the current script's `$$`
# @exitcode 0 The PID file was written
# @exitcode 1 Stop the script when the process ID is not a number or the file cannot be written
# @note `$$` is the script's own process ID and stays the same inside a subshell, which is what a PID file is expected to hold. Pass `${BASHPID}` explicitly to record a subshell instead.
#######################################
function dybatpho::pid_file_write {
  local path
  dybatpho::expect_args path -- "$@"
  local pid="${2:-$$}"
  [[ "${pid}" =~ ^[1-9][0-9]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Process ID must be a positive integer, got '${pid}'"

  local directory="${path%/*}"
  [[ "${directory}" == "${path}" ]] && directory="."
  [[ -d "${directory}" ]] || mkdir -p -- "${directory}" \
    || dybatpho::die "${FUNCNAME[0]}: Cannot create directory ${directory}"

  local staged="${path}.${BASHPID}.tmp"
  printf '%s\n' "${pid}" > "${staged}" \
    || dybatpho::die "${FUNCNAME[0]}: Cannot write ${path}"
  mv -f -- "${staged}" "${path}" \
    || dybatpho::die "${FUNCNAME[0]}: Cannot move ${staged} to ${path}"
  dybatpho::debug "Wrote pid ${pid} to ${path}"
}

#######################################
# @description Report whether the process recorded in a PID file is still alive.
#   A missing file, an empty one, one holding something other than a number, and
#   one holding a process that has since exited all answer the same way: nothing
#   is running. That is what callers act on, and separating "no PID file" from
#   "stale PID file" only moves the decision up one level.
# @example
#   if dybatpho::pid_file_is_running /var/run/app.pid; then
#     dybatpho::die "Already running"
#   fi
#
# @arg $1 string Path of the PID file
# @exitcode 0 The recorded process is running
# @exitcode 1 There is no readable PID file, its contents are not a process ID, or that process has exited
# @note A PID file whose process has exited can be reused by an unrelated process that happens to receive the same ID, which no PID file can detect; use `dybatpho::lock_acquire` when the answer has to be exact.
#######################################
function dybatpho::pid_file_is_running {
  local path
  dybatpho::expect_args path -- "$@"
  [[ -r "${path}" ]] || return 1

  local pid=""
  IFS= read -r pid < "${path}" 2> /dev/null || true
  # A PID file written by another tool can carry surrounding whitespace.
  pid="${pid//[[:space:]]/}"
  [[ "${pid}" =~ ^[1-9][0-9]*$ ]] || return 1
  kill -0 "${pid}" 2> /dev/null
}

#######################################
# @description Remove a PID file, but only when it records the given process.
#   The guard is the point: a service that exits after a replacement has already
#   written its own PID file would otherwise delete the live one on its way out,
#   and the supervisor would then start a second copy.
# @arg $1 string Path of the PID file
# @arg $2 number Process ID the file must record, default is the current script's `$$`
# @exitcode 0 The file was removed, or was already gone
# @exitcode 1 The file records a different process and was left alone
#######################################
function dybatpho::pid_file_remove {
  local path
  dybatpho::expect_args path -- "$@"
  local pid="${2:-$$}"
  [[ -e "${path}" ]] || return 0

  local recorded=""
  IFS= read -r recorded < "${path}" 2> /dev/null || true
  recorded="${recorded//[[:space:]]/}"
  if [[ -n "${recorded}" && "${recorded}" != "${pid}" ]]; then
    dybatpho::debug "Left ${path} alone: it records pid ${recorded}, not ${pid}"
    return 1
  fi
  rm -f -- "${path}"
}
