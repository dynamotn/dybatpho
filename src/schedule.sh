# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# parses its own options, so the raw form is what the reader sees.
# dyshellint disable=BSG050,BSG051,BSG033
# @file schedule.sh
# @brief Deciding when a command should run, and running it on a cadence
# @namespace dybatpho
# @description
#   `helpers.sh` retries a call that failed. This module answers a different
#   question: should this run at all, and when next. It covers the three
#   shapes a script keeps reimplementing as a `sleep` loop — run every N
#   seconds, collapse a burst of triggers into one run, and run at most once
#   per day — plus a predicate for a cron expression, so a script can tell
#   whether it is due without a crontab entry.
#
#   The state that has to outlive the process lives on disk, under
#   `DYBATPHO_SCHEDULE_DIR`. That is what makes "at most once a day" hold
#   across separate invocations rather than only within one run, which is the
#   case a variable cannot cover.
# @tip An interval is in whole seconds: `sleep` takes fractions on GNU but not
#   everywhere, and this module keeps to what BusyBox also accepts
# @env DYBATPHO_SCHEDULE_DIR string Where markers live, default is `schedule` under the XDG state directory
# @see
#   - `example/schedule_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_SCHEDULE_DIR string Directory holding the markers that outlive a run
DYBATPHO_SCHEDULE_DIR="${DYBATPHO_SCHEDULE_DIR:-}"

#######################################
# @description Resolve the directory markers are kept in, into a named
#   variable, creating it if needed.
# @arg $1 string Name of the variable receiving the directory
# @set The named variable
#######################################
function __dybatpho_schedule_dir_into {
  local -n __dybatpho_schedule_dir_ref="$1"
  __dybatpho_schedule_dir_ref="${DYBATPHO_SCHEDULE_DIR}"
  if [[ -z "${__dybatpho_schedule_dir_ref}" ]]; then
    __dybatpho_schedule_dir_ref="$(dybatpho::xdg_state_dir)/schedule"
  fi
  dybatpho::ensure_dir "${__dybatpho_schedule_dir_ref}" > /dev/null
}

#######################################
# @description Stop when a key could name a file outside the marker directory.
# @arg $1 string Key
# @exitcode 0 The key is safe to use as a file name
# @exitcode 1 Stop the script when it is not
#######################################
function __dybatpho_schedule_expect_key {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Not a usable key: $1. Use letters, digits, dot, dash or underscore"
}

#######################################
# @description Split `<args> -- <command...>`, leaving the command in a named
#   array and checking there is one.
# @arg $1 string Name of the array variable receiving the command
# @arg $@ string The arguments following the separator
# @set The named array
#######################################
function __dybatpho_schedule_command_into {
  local -n __dybatpho_schedule_cmd_ref="$1"
  shift
  [[ "${1-}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[1]}: Expected \`--\` before the command"
  shift
  (($#)) || dybatpho::die "${FUNCNAME[1]}: Expected a command after \`--\`"
  __dybatpho_schedule_cmd_ref=("$@")
}

#######################################
# @description Run a command on a fixed cadence until it is interrupted.
#   The first run is immediate. The cadence is measured from when each run was
#   due rather than from when the last one ended, so the schedule does not
#   drift; a run that overruns its slot makes the missed ticks be skipped
#   rather than queued, because catching up by running the same command four
#   times in a row is never what the caller meant.
#
#   `SIGINT`, `SIGTERM` and `SIGHUP` end the loop after the run in progress,
#   and the handlers in place before the call are put back afterwards.
# @arg $1 number Seconds between runs
# @arg $2 string Options, then `--`, then the command
# @opt --times <n> Stop after `n` runs instead of running until interrupted
# @arg $@ string Command and arguments, after `--`
# @exitcode 0 The loop finished its runs, or was interrupted
# @exitcode 1 The interval or the run count is not a positive number
# @example
#   dybatpho::schedule_every 60 --times 5 -- dybatpho::info "tick"
#######################################
function dybatpho::schedule_every {
  local interval
  dybatpho::expect_args interval -- "$@"
  shift

  local times=0
  while (($#)); do
    case "${1-}" in
      --times)
        times="${2-}"
        shift 2 || dybatpho::die "${FUNCNAME[0]}: --times needs a number"
        ;;
      *) break ;;
    esac
  done

  dybatpho::is int "${interval}" && ((interval > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: The interval must be a positive number of seconds, got: ${interval}"
  dybatpho::is int "${times}" && ((times >= 0)) \
    || dybatpho::die "${FUNCNAME[0]}: --times must be a number, got: ${times}"

  local -a command=()
  __dybatpho_schedule_command_into command "$@"

  # The previous handlers are restored rather than left replaced: a script may
  # call this more than once, and its own Ctrl-C handling has to survive.
  local previous_traps
  __dybatpho_process_traps_save_into previous_traps HUP INT TERM
  # The flag is a local, not a module global: a signal is handled inside this
  # function, so the handler sees this frame's variables and nothing leaks out
  # to the next caller.
  local stopped=0
  dybatpho::trap "stopped=1" HUP INT TERM

  local due now ran=0 waited
  due="$(dybatpho::date_now "%s")"
  while :; do
    "${command[@]}" || true
    ran=$((ran + 1))

    ((times > 0 && ran >= times)) && break
    ((stopped)) && break

    due=$((due + interval))
    now="$(dybatpho::date_now "%s")"
    # A run that took longer than its slot has already missed one or more
    # ticks. They are dropped, not queued.
    while ((due <= now)); do
      due=$((due + interval))
    done

    waited=$((due - now))
    sleep "${waited}"
    ((stopped)) && break
  done

  __dybatpho_process_traps_restore "${previous_traps}" HUP INT TERM
  return 0
}

#######################################
# @description Stop unless the `lock` module is loaded.
#   Only the debounce takes a lock, to read and bump its counter in one step.
#   Registering `lock` as a dependency would load it into every script that
#   only runs on a cadence or once a day, so the one function that needs it
#   asks for it instead.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `lock`
#   and then fail on the first internal call.
# @noargs
# @exitcode 1 The `lock` module is not loaded
# @internal
#######################################
function __dybatpho_schedule_need_lock {
  declare -F __dybatpho_lock_try > /dev/null \
    || dybatpho::die "${FUNCNAME[1]} needs the lock module, load it with: dybatpho::load lock"
}

#######################################
# @description Run a command once a burst of triggers has settled.
#   Every trigger calls this. Each call registers itself, waits out the
#   window, and then runs the command only if nothing else registered while it
#   waited — so a burst of events produces exactly one run, after the burst
#   ends rather than at its start. That is what an editor's
#   write-then-rename needs: running on the first event would read a file that
#   is still half written.
#
#   The call blocks for the length of the window, so a trigger loop should
#   call it in the background when it must keep reading events.
# @arg $1 number Seconds of quiet required before the command runs
# @arg $2 string Key identifying the burst, shared by the triggers that belong together
# @arg $3 string Literal `--` separating the key from the command
# @arg $@ string Command and arguments to run
# @exitcode 0 The command ran, and its own exit code is returned
# @exitcode 1 The window or the key is invalid, or the `lock` module is not loaded
# @exitcode 9 A later trigger arrived, so this call did nothing
# @tip Needs the `lock` module: load it with `--modules schedule lock`
# @example
#   dybatpho::schedule_debounce 2 rebuild -- make
#######################################
function dybatpho::schedule_debounce {
  local window key
  dybatpho::expect_args window key -- "$@"
  __dybatpho_schedule_need_lock
  shift 2
  dybatpho::is int "${window}" && ((window > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: The window must be a positive number of seconds, got: ${window}"
  __dybatpho_schedule_expect_key "${key}"

  local -a command=()
  __dybatpho_schedule_command_into command "$@"

  local directory
  __dybatpho_schedule_dir_into directory
  local ticket="${directory}/${key}.trigger"
  local lock="${directory}/${key}.lock"

  # Reading and bumping the counter is one step: two triggers arriving
  # together would otherwise take the same number, and both would believe they
  # were last.
  dybatpho::lock_acquire "${lock}" 10 || return 1
  local counter=0
  if dybatpho::is file "${ticket}"; then
    read -r counter < "${ticket}"
    [[ "${counter}" =~ ^[0-9]+$ ]] || counter=0
  fi
  counter=$((counter + 1))
  printf '%s\n' "${counter}" > "${ticket}"
  dybatpho::lock_release "${lock}"

  sleep "${window}"

  local latest=0
  read -r latest < "${ticket}"
  [[ "${latest}" =~ ^[0-9]+$ ]] || latest=0
  if ((latest != counter)); then
    return 9
  fi

  "${command[@]}"
}

#######################################
# @description Run a command at most once in each period.
#   The marker is a file, so the limit holds across separate invocations of
#   the script rather than only within one run. A named period is a calendar
#   bucket -- `hour` means "once in this clock hour", not "once in any sixty
#   minutes" -- while a number of seconds measures from the last run.
# @arg $1 string Period: `hour`, `day`, `month`, or a number of seconds
# @arg $2 string Key identifying what is being limited
# @arg $3 string Literal `--` separating the key from the command
# @arg $@ string Command and arguments to run
# @exitcode 0 The command ran, and its own exit code is returned
# @exitcode 1 The period or the key is invalid
# @exitcode 9 The command already ran in this period, so nothing was done
# @example
#   dybatpho::schedule_once_per day warn-expiry -- dybatpho::warn "The token expires soon"
#######################################
function dybatpho::schedule_once_per {
  local period key
  dybatpho::expect_args period key -- "$@"
  shift 2
  __dybatpho_schedule_expect_key "${key}"

  local -a command=()
  __dybatpho_schedule_command_into command "$@"

  local directory
  __dybatpho_schedule_dir_into directory
  local marker="${directory}/${key}.last"

  local bucket
  __dybatpho_schedule_bucket_into bucket "${period}"

  if dybatpho::is file "${marker}"; then
    local recorded=""
    read -r recorded < "${marker}" || true
    if [[ "${period}" =~ ^[0-9]+$ ]]; then
      local age
      age="$(dybatpho::file_age_seconds "${marker}")"
      ((age < period)) && return 9
    elif [[ "${recorded}" == "${bucket}" ]]; then
      return 9
    fi
  fi

  # The marker is written before the command runs. A command that fails would
  # otherwise run again on the next invocation, which is the opposite of what
  # "at most once per period" promises; a caller that wants a retry on failure
  # wants `dybatpho::retry`, not this.
  printf '%s\n' "${bucket}" > "${marker}"
  "${command[@]}"
}

#######################################
# @description Work out the bucket a period puts the current time in.
# @arg $1 string Name of the variable receiving the bucket
# @arg $2 string Period name or a number of seconds
# @set The named variable
#######################################
function __dybatpho_schedule_bucket_into {
  local -n __dybatpho_schedule_bucket_ref="$1"
  case "$2" in
    hour) __dybatpho_schedule_bucket_ref="$(dybatpho::date_now "%Y%m%d%H")" ;;
    day) __dybatpho_schedule_bucket_ref="$(dybatpho::date_now "%Y%m%d")" ;;
    month) __dybatpho_schedule_bucket_ref="$(dybatpho::date_now "%Y%m")" ;;
    *)
      [[ "$2" =~ ^[0-9]+$ ]] && (($2 > 0)) \
        || dybatpho::die "${FUNCNAME[1]}: Not a period: $2. Use hour, day, month, or a number of seconds"
      __dybatpho_schedule_bucket_ref="$(dybatpho::date_now "%s")"
      ;;
  esac
}

#######################################
# @description Forget what a key has recorded, so the next call runs.
# @arg $1 string Key
# @exitcode 0 The key's markers are gone, whether or not there were any
# @exitcode 1 The key is invalid
# @example
#   dybatpho::schedule_reset warn-expiry
#######################################
function dybatpho::schedule_reset {
  local key
  dybatpho::expect_args key -- "$@"
  __dybatpho_schedule_expect_key "${key}"

  local directory
  __dybatpho_schedule_dir_into directory
  rm -f -- "${directory}/${key}.last" "${directory}/${key}.trigger"
}

#######################################
# @description Return success when a time matches a cron expression.
#   This answers "am I due", which is what a script run from an existing
#   scheduler needs. It deliberately does not compute the next fire time: that
#   needs a full calendar walk, and a half-right answer about when something
#   will next run is worse than no answer.
#
#   Fields are the usual five -- minute, hour, day of month, month, day of
#   week -- each one `*`, a number, `a-b`, a comma-separated list, or any of
#   those with a `/n` step. Sunday is `0` or `7`.
#
#   When both day of month and day of week are restricted, the expression
#   matches if **either** does, which is what cron itself does and what a
#   hand-written check almost always gets wrong.
# @arg $1 string Cron expression, five fields
# @arg $2 number Optional Unix timestamp to test, default is now
# @exitcode 0 The time matches
# @exitcode 1 It does not
# @exitcode 2 The expression is malformed
# @example
#   dybatpho::schedule_cron_due "*/15 * * * *" && run_the_job
#######################################
function dybatpho::schedule_cron_due {
  local expression
  dybatpho::expect_args expression -- "$@"
  local moment="${2-}"
  [[ -n "${moment}" ]] || moment="$(dybatpho::date_now "%s")"

  local -a fields=()
  read -r -a fields <<< "${expression}"
  ((${#fields[@]} == 5)) || {
    dybatpho::error "${FUNCNAME[0]}: A cron expression has five fields, got ${#fields[@]}: ${expression}"
    return 2
  }

  local parts minute hour day month weekday
  parts="$(dybatpho::date_format "${moment}" "%M %H %d %m %w")"
  read -r minute hour day month weekday <<< "${parts}"

  # `10#` on every one: `%M` and friends are zero-padded, and `08` is an
  # invalid octal literal to Bash arithmetic.
  __dybatpho_schedule_field_matches "${fields[0]}" "$((10#${minute}))" 0 59 || return 1
  __dybatpho_schedule_field_matches "${fields[1]}" "$((10#${hour}))" 0 23 || return 1
  __dybatpho_schedule_field_matches "${fields[3]}" "$((10#${month}))" 1 12 || return 1

  local day_restricted=1 weekday_restricted=1
  [[ "${fields[2]}" == "*" ]] && day_restricted=0
  [[ "${fields[4]}" == "*" ]] && weekday_restricted=0

  local day_ok=1 weekday_ok=1
  __dybatpho_schedule_field_matches "${fields[2]}" "$((10#${day}))" 1 31 || day_ok=0
  __dybatpho_schedule_weekday_matches "${fields[4]}" "$((10#${weekday}))" || weekday_ok=0

  if ((day_restricted && weekday_restricted)); then
    ((day_ok || weekday_ok)) || return 1
    return 0
  fi
  ((day_ok && weekday_ok)) || return 1
  return 0
}

#######################################
# @description Match a day-of-week field, accepting `7` for Sunday.
# @arg $1 string Field specification
# @arg $2 number Day of week, `0` for Sunday
# @exitcode 0 The field matches
# @exitcode 1 It does not
#######################################
function __dybatpho_schedule_weekday_matches {
  __dybatpho_schedule_field_matches "$1" "$2" 0 7 && return 0
  # `7` and `0` are both Sunday, so an expression naming one must match a time
  # reported as the other.
  (($2 == 0)) && __dybatpho_schedule_field_matches "$1" 7 0 7 && return 0
  return 1
}

#######################################
# @description Match one cron field against one value.
# @arg $1 string Field specification
# @arg $2 number Value to test
# @arg $3 number Lowest value the field allows, used when a step has no range
# @arg $4 number Highest value the field allows
# @exitcode 0 The field matches
# @exitcode 1 It does not
#######################################
function __dybatpho_schedule_field_matches {
  local specification="$1" value="$2" lowest="$3" highest="$4"
  local -a alternatives=()
  IFS=',' read -r -a alternatives <<< "${specification}"

  local alternative step first last
  for alternative in "${alternatives[@]}"; do
    step=1
    if [[ "${alternative}" == */* ]]; then
      step="${alternative##*/}"
      alternative="${alternative%%/*}"
      [[ "${step}" =~ ^[1-9][0-9]*$ ]] || return 1
    fi

    if [[ "${alternative}" == "*" ]]; then
      first="${lowest}"
      last="${highest}"
    elif [[ "${alternative}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      first="$((10#${BASH_REMATCH[1]}))"
      last="$((10#${BASH_REMATCH[2]}))"
    elif [[ "${alternative}" =~ ^[0-9]+$ ]]; then
      first="$((10#${alternative}))"
      last="${first}"
    else
      return 1
    fi

    ((value >= first && value <= last)) || continue
    (((value - first) % step == 0)) && return 0
  done
  return 1
}
