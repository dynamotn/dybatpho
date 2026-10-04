# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# uses `eval`, which is how the spec engine builds a parser.
# dyshellint disable=BSG050,BSG040
# @file lock.sh
# @brief Utilities for process locking and coordination
# @namespace dybatpho
# @description
#   This module provides a portable file lock (Linux/macOS) built on the
#   atomicity of `mkdir`, so it works the same way without depending on
#   `flock`, which isn't shipped by default on macOS.
#
#   A lock is a directory containing metadata about the process holding it
#   (pid, hostname, command, and acquisition time), which lets callers:
#
#   - prevent two runs of the same script from executing concurrently
#   - wait for a lock with a timeout instead of failing immediately
#   - inspect which process currently holds a lock
#   - detect and reclaim stale locks left behind by a dead process
# @usage
#   ### Prevent concurrent runs of the same script
#
#   ```bash
#   dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"
#   trap 'dybatpho::lock_release "$(basename "$0")"' EXIT
#   ```
#
#   ### Wait up to 30s for a lock, then run a command while holding it
#
#   ```bash
#   dybatpho::with_lock "deploy" 30 -- ./deploy.sh
#   ```
#
#   ### Inspect who is holding a lock
#
#   ```bash
#   dybatpho::lock_info "deploy"
#   ```
# @see
#   - `example/lock_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_LOCK_DIR string Base directory used to resolve lock names into lock paths
DYBATPHO_LOCK_DIR="${DYBATPHO_LOCK_DIR:-${TMPDIR:-/tmp}}"
# @env DYBATPHO_LOCK_POLL_INTERVAL number Seconds to sleep between acquire attempts while waiting
DYBATPHO_LOCK_POLL_INTERVAL="${DYBATPHO_LOCK_POLL_INTERVAL:-1}"

#######################################
# @description Print the current host name using whichever mechanism is available.
#   Kept as the name a lock file is stamped with; the detection itself lives in
#   `dybatpho::hostname`.
# @stdout Host name reported by `hostname`, `uname -n`, the kernel, or the `HOSTNAME` env var
#######################################
# Suffix of the file holding the command that took a lock, beside the lock
# itself. See `dybatpho::lock_field`.
[[ -n "${__DYBATPHO_LOCK_COMMAND_SUFFIX-}" ]] || readonly __DYBATPHO_LOCK_COMMAND_SUFFIX=".command"

#######################################
# @description Return success when something holds this lock path, whichever
#   form it is in: a symbolic link, which is what the atomic claim writes, or a
#   directory, which is what versions before it wrote.
#
#   `[[ -L ]]` is deliberately first and deliberately not `[[ -e ]]`: the link
#   target is data rather than a path, so it never resolves, and `-e` reports a
#   dangling link as absent.
# @arg $1 string Lock path
# @exitcode 0 A lock is present
# @exitcode 1 Nothing is there
# @internal
#######################################
function __dybatpho_lock_exists {
  [[ -L "${1-}" ]] || dybatpho::is dir "${1-}"
}

#######################################
# @description Build the link target that identifies the holder of a lock,
#   as `pid:host:acquired_at`, into a variable.
#   The time comes from Bash's own clock, so building it starts no process: a
#   claim is attempted on every poll, and two processes per attempt -- `date`
#   and the host name -- were most of what polling a held lock cost.
# @arg $1 string Name of the variable receiving the target
# @set The named variable
# @internal
#######################################
function __dybatpho_lock_target_into {
  local -n __dybatpho_lock_target_out="$1"
  local __dybatpho_lock_target_at __dybatpho_lock_target_host
  TZ=UTC printf -v __dybatpho_lock_target_at '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  __dybatpho_lock_host_into __dybatpho_lock_target_host
  __dybatpho_lock_target_out="$$:${__dybatpho_lock_target_host}:${__dybatpho_lock_target_at}"
}

#######################################
# @description Read the host name a lock records, at most once per wait.
#   A waiting call declares `__dybatpho_lock_host_cache` local, and the name is
#   asked for the first time it is needed and kept for the rest of that call.
#   Outside such a call it is asked every time, so a test that replaces
#   `dybatpho::lock_hostname` is always heard.
# @arg $1 string Name of the variable receiving the host name
# @set The named variable
# @internal
#######################################
function __dybatpho_lock_host_into {
  local -n __dybatpho_lock_host_out="$1"
  if [[ -v __dybatpho_lock_host_cache ]]; then
    # The waiting call declared it local; filling it is how the name is kept.
    # dyshellint disable=BSG011 written through to the caller's local on purpose
    [[ -n "${__dybatpho_lock_host_cache}" ]] \
      || __dybatpho_lock_host_cache="$(dybatpho::lock_hostname)"
    __dybatpho_lock_host_out="${__dybatpho_lock_host_cache}"
    return 0
  fi
  __dybatpho_lock_host_out="$(dybatpho::lock_hostname)"
}

#######################################
# @description Retry an attempt until it succeeds or a timeout runs out.
#   The one wait loop both a lock and a semaphore use. Elapsed time is read from
#   Bash's own clock rather than from `date`, so a poll starts no process for
#   it, and a clock frozen by `dybatpho::mock_time` does not hold a wait open.
# @arg $1 number Seconds to keep trying; `0` tries once
# @arg $@ string The attempt command and its arguments
# @env DYBATPHO_LOCK_POLL_INTERVAL number Seconds to sleep between attempts
# @exitcode 0 An attempt succeeded
# @exitcode 1 The timeout ran out first
# @internal
#######################################
function __dybatpho_lock_wait {
  local __dybatpho_lock_wait_timeout="$1"
  shift
  local __dybatpho_lock_wait_start __dybatpho_lock_wait_now
  printf -v __dybatpho_lock_wait_start '%(%s)T' -1
  while true; do
    "$@" && return 0
    printf -v __dybatpho_lock_wait_now '%(%s)T' -1
    ((__dybatpho_lock_wait_now - __dybatpho_lock_wait_start >= __dybatpho_lock_wait_timeout)) \
      && return 1
    sleep "${DYBATPHO_LOCK_POLL_INTERVAL}"
  done
}

#######################################
# @description Print the host name a lock records as its owner. It is its own
#   function so a test can replace it, which is how the stale-lock paths are
#   exercised without a second machine.
# @noargs
# @stdout The host name
#######################################
function dybatpho::lock_hostname {
  dybatpho::hostname
}

#######################################
# @description Resolve a lock name or path into an absolute lock directory path.
# @arg $1 string Lock name (bare word) or an explicit absolute/relative path
# @stdout Absolute lock directory path, always suffixed with `.lock`
#######################################
function dybatpho::lock_path {
  local name
  dybatpho::expect_args name -- "$@"

  local lock_path
  if [[ "${name}" == */* ]]; then
    lock_path="${name}"
  else
    # Emptied after loading, the setting would put the lock at the root of the
    # filesystem; fall back to the default the module starts with.
    local directory="${DYBATPHO_LOCK_DIR:-${TMPDIR:-/tmp}}"
    lock_path="${directory%/}/dybatpho-${name}"
  fi
  dybatpho::string_ends_with "${lock_path}" ".lock" || lock_path="${lock_path}.lock"
  printf '%s\n' "${lock_path}"
}

#######################################
# @description Read a single metadata field recorded for a lock.
# @arg $1 string Lock directory path
# @arg $2 string Field name (pid|host|command|acquired_at)
# @stdout Recorded value, or empty when the lock or field doesn't exist
#######################################
function dybatpho::lock_field {
  local lock_path field
  dybatpho::expect_args lock_path field -- "$@"

  # `command` can hold anything, including the separator, so it never goes in
  # the link target. It is written beside the lock after the claim and is
  # diagnostic only: a missing one is not a correctness problem.
  if [[ "${field}" == "command" ]]; then
    local sidecar="${lock_path}${__DYBATPHO_LOCK_COMMAND_SUFFIX}"
    dybatpho::is file "${sidecar}" && cat "${sidecar}"
    return 0
  fi

  if [[ -L "${lock_path}" ]]; then
    local target rest
    target="$(readlink "${lock_path}" 2> /dev/null || true)"
    [[ -n "${target}" ]] || return 0
    # pid:host:acquired_at -- the timestamp holds colons of its own, so it is
    # last and takes everything after the second separator. A host name has no
    # colon in it, which is what makes the first two splits unambiguous.
    rest="${target#*:}"
    case "${field}" in
      pid) printf '%s' "${target%%:*}" ;;
      host) printf '%s' "${rest%%:*}" ;;
      acquired_at) printf '%s' "${rest#*:}" ;;
      *) return 0 ;;
    esac
    return 0
  fi

  # A directory is what versions before the atomic claim wrote. Reading it keeps
  # a lock taken by an older copy of the library legible to a newer one.
  local field_file="${lock_path}/${field}"
  if dybatpho::is file "${field_file}"; then
    cat "${field_file}"
  fi
}

#######################################
# @description Return success when the process that owns a lock is still alive on this host.
# @arg $1 string Lock directory path
# @exitcode 0 The recorded pid belongs to a live process on the current host
# @exitcode 1 The lock is missing, foreign to this host, or its process is gone (stale)
#######################################
function dybatpho::lock_is_alive {
  local lock_path
  dybatpho::expect_args lock_path -- "$@"
  __dybatpho_lock_exists "${lock_path}" || return 1

  local holder
  holder="$(__dybatpho_lock_identity "${lock_path}")"
  __dybatpho_lock_holder_alive "${lock_path}" "${holder}"
}

#######################################
# @description Return success when a lock is currently held by a live process.
# @arg $1 string Lock name or path
# @exitcode 0 The lock exists and is held by a live process
# @exitcode 1 The lock doesn't exist or is stale
#######################################
function dybatpho::lock_is_held {
  local name lock_path
  dybatpho::expect_args name -- "$@"
  lock_path="$(dybatpho::lock_path "${name}")"
  dybatpho::lock_is_alive "${lock_path}"
}

#######################################
# @description Print information about the process currently holding a lock.
# @arg $1 string Lock name or path
# @stdout `pid=<pid> host=<host> acquired_at=<timestamp> command=<command>` when held
# @exitcode 0 The lock is currently held and its info was printed
# @exitcode 1 The lock isn't held by anyone
#######################################
function dybatpho::lock_info {
  local name lock_path
  dybatpho::expect_args name -- "$@"
  lock_path="$(dybatpho::lock_path "${name}")"

  dybatpho::lock_is_alive "${lock_path}" || return 1
  local pid host acquired_at command
  pid=$(dybatpho::lock_field "${lock_path}" pid)
  host=$(dybatpho::lock_field "${lock_path}" host)
  acquired_at=$(dybatpho::lock_field "${lock_path}" acquired_at)
  command=$(dybatpho::lock_field "${lock_path}" command)
  printf 'pid=%s host=%s acquired_at=%s command=%s\n' \
    "${pid}" "${host}" "${acquired_at}" "${command}"
}

#######################################
# @description Remove a lock left behind by a process that is no longer running.
#   Deleting it in place was a way for two processes to end up holding the same
#   lock. Both read the dead holder, both decided to reclaim, the first one
#   removed it and took the lock, and the second one then removed *that* — a
#   live lock — and took it as well.
#
#   Reclaiming is therefore a rename rather than a delete. `rename()` fails when
#   the source is gone, so of two processes racing to reclaim the same lock
#   exactly one moves it aside and the loser touches nothing. The identity
#   recorded in the lock is re-read from the moved-aside copy and compared with
#   the one that was judged stale: they differ only when the lock was replaced
#   between the judgement and the move, and the fresh lock is put back rather
#   than deleted.
# @arg $1 string Lock directory path
# @stderr Notice when a stale lock is reclaimed
#######################################
function dybatpho::lock_reclaim_stale {
  local lock_path
  dybatpho::expect_args lock_path -- "$@"
  __dybatpho_lock_exists "${lock_path}" || return 0

  local holder pid
  holder="$(__dybatpho_lock_identity "${lock_path}")"
  # The holder released it between the two reads, so there is nothing to
  # reclaim. Going on would judge a lock this call never saw: the name is
  # empty for a moment, reads as dead, and is moved aside the instant the next
  # process claims it, leaving two processes holding the same lock.
  [[ -n "${holder}" ]] || return 0
  # Judge the holder that was read, not whatever holds the name by the time
  # the check runs, for the same reason.
  __dybatpho_lock_holder_alive "${lock_path}" "${holder}" && return 0
  pid="${holder%%:*}"

  # Another reclaimer may have finished between the judgement and here and
  # put a live lock in its place; that one is not stale.
  local current
  current="$(__dybatpho_lock_identity "${lock_path}")"
  [[ "${current}" == "${holder}" ]] || return 0

  # A name no other process can be moving a lock to: two reclaimers of the same
  # lock must not collide on the destination, or the rename would succeed for
  # both and the check below would lose its meaning.
  local aside="${lock_path}.stale.$$.${RANDOM}"
  mv -- "${lock_path}" "${aside}" 2> /dev/null || return 0

  local moved
  moved="$(__dybatpho_lock_identity "${aside}")"
  if [[ "${moved}" != "${holder}" ]]; then
    # Someone reclaimed and re-took the lock while this call was deciding, so
    # what was moved aside is a live lock. Put it back if the name is still
    # free; `ln -s` refuses to replace an existing name, so a third holder is
    # never overwritten.
    if ln -s "${moved}" "${lock_path}" 2> /dev/null; then
      rm -f -- "${aside}" > /dev/null 2>&1 || true
    else
      dybatpho::warn "Lock ${lock_path} changed hands while it was being reclaimed; the copy moved aside is at ${aside}"
    fi
    return 0
  fi

  dybatpho::warn "Reclaiming stale lock ${lock_path} (pid ${pid} is no longer running)"
  # `rm` on a symbolic link removes the link, never what it points at.
  rm -rf -- "${aside}" "${lock_path}${__DYBATPHO_LOCK_COMMAND_SUFFIX}" > /dev/null 2>&1 || true
}

#######################################
# @description Return success when the holder named by an identity, as
#   `__dybatpho_lock_identity` printed it, is still alive on this host. It
#   reads the pid and host out of the identity rather than out of the lock, so
#   the answer is about that holder even when the lock has since changed hands.
# @arg $1 string Lock path, for the host of a lock in the directory form
# @arg $2 string Identity of the holder
# @exitcode 0 The holder is alive, or recorded on another host
# @exitcode 1 The holder is gone
# @internal
#######################################
function __dybatpho_lock_holder_alive {
  local lock_path="$1" identity="$2" pid host
  if [[ "${identity}" == *:* ]]; then
    pid="${identity%%:*}"
    host="${identity#*:}"
    host="${host%%:*}"
  else
    # The directory form records the pid alone, with the host in a file beside it.
    pid="${identity}"
    host="$(dybatpho::lock_field "${lock_path}" host)"
  fi

  [[ -n "${pid}" ]] || return 1
  # A lock recorded on a different host can't be checked for liveness locally,
  # so conservatively treat it as still held.
  if [[ -n "${host}" ]]; then
    local local_host
    __dybatpho_lock_host_into local_host
    [[ "${host}" == "${local_host}" ]] || return 0
  fi
  kill -0 "${pid}" > /dev/null 2>&1
}

#######################################
# @description Print what identifies the holder of a lock, for comparing one
#   observation of a lock with a later one. It is the link target for the
#   atomic form, and the recorded pid for the directory form older copies of
#   the library wrote.
# @arg $1 string Lock path
# @stdout The identity, or nothing when the lock is gone
# @internal
#######################################
function __dybatpho_lock_identity {
  local lock_path="${1-}"
  if [[ -L "${lock_path}" ]]; then
    readlink "${lock_path}" 2> /dev/null || true
    return 0
  fi
  dybatpho::lock_field "${lock_path}" pid
}

#######################################
# @description Make one attempt at a lock path, reclaiming it first when its
#   holder is dead.
# @arg $1 string Lock path
# @exitcode 0 The lock was taken by the current process
# @exitcode 1 A live process holds it
# @internal
#######################################
function __dybatpho_lock_try {
  local lock_path="$1"
  dybatpho::lock_reclaim_stale "${lock_path}"

  # One syscall claims the lock and says who holds it. `symlink()` fails when
  # the name already exists, and the identity is already in the target, so
  # there is no window in which the lock exists without an owner. Claiming
  # with `mkdir` and writing the pid afterwards left exactly such a window,
  # and a second process read the missing pid as "nobody holds this", removed
  # the lock and took it.
  local lock_target
  __dybatpho_lock_target_into lock_target
  ln -s "${lock_target}" "${lock_path}" 2> /dev/null || return 1
  printf '%s' "${DYBATPHO_LOCK_COMMAND:-$0}" \
    > "${lock_path}${__DYBATPHO_LOCK_COMMAND_SUFFIX}" 2> /dev/null || true
}

#######################################
# @description Acquire a portable, cross-platform (Linux/macOS) file lock, waiting up to a timeout.
# @example
#   dybatpho::lock_acquire "$(basename "$0")" || dybatpho::die "Already running"
#
# @example
#   dybatpho::lock_acquire "deploy" 30
#
# @arg $1 string Lock name (bare word resolved under `DYBATPHO_LOCK_DIR`) or an explicit path
# @arg $2 number Seconds to wait for the lock before giving up, default 0 (try once, don't wait)
# @env DYBATPHO_LOCK_DIR string Base directory used to resolve bare lock names
# @env DYBATPHO_LOCK_POLL_INTERVAL number Seconds to sleep between acquire attempts while waiting
# @stderr Info about the current holder when the lock can't be acquired
# @exitcode 0 The lock was acquired by the current process
# @exitcode 1 The lock is still held by another live process after the timeout elapses
# @tip Uses `mkdir` for atomic lock creation, so no dependency on `flock` is required
# @tip Pair with `dybatpho::lock_release` in a trap so the lock is always freed on exit
#######################################
function dybatpho::lock_acquire {
  local name timeout
  dybatpho::expect_args name -- "$@"
  timeout="${2:-0}"
  dybatpho::is int "${timeout}" \
    || dybatpho::die "${FUNCNAME[0]}: The timeout must be a number of seconds, got: ${timeout}"

  local lock_path
  lock_path="$(dybatpho::lock_path "${name}")"

  local __dybatpho_lock_host_cache=""
  __dybatpho_lock_wait "${timeout}" __dybatpho_lock_try "${lock_path}" && return 0
  local holder
  holder="$(dybatpho::lock_info "${name}" 2> /dev/null || echo 'held by an unknown process')"
  dybatpho::error "Could not acquire lock ${lock_path}: ${holder}"
  return 1
}

#######################################
# @description Release a lock previously acquired by the current process.
# @arg $1 string Lock name or path
# @exitcode 0 The lock was released, or wasn't held by the current process to begin with
# @exitcode 1 The lock is held by a different, still-live process and was left untouched
# @tip Safe to call even when the lock was never acquired by this process
#######################################
function dybatpho::lock_release {
  local name lock_path
  dybatpho::expect_args name -- "$@"
  lock_path="$(dybatpho::lock_path "${name}")"

  __dybatpho_lock_exists "${lock_path}" || return 0

  local owner_pid
  owner_pid="$(dybatpho::lock_field "${lock_path}" pid)"
  if [[ -n "${owner_pid}" && "${owner_pid}" != "$$" ]] && dybatpho::lock_is_alive "${lock_path}"; then
    dybatpho::warn "Lock ${lock_path} is held by pid ${owner_pid}, not the current process; skipping release"
    return 1
  fi

  rm -rf -- "${lock_path}" "${lock_path}${__DYBATPHO_LOCK_COMMAND_SUFFIX}" > /dev/null 2>&1 || true
}

#######################################
# @description Acquire a lock, run a command while holding it, then release it, even if the command fails.
# @example
#   dybatpho::with_lock "deploy" 30 -- ./deploy.sh --env prod
#
# @arg $1 string Lock name or path
# @arg $2 number Seconds to wait for the lock before giving up
# @arg $3 string Literal `--` separating lock options from the command
# @arg $@ string Command and arguments to run while holding the lock
# @exitcode 1 The lock couldn't be acquired within the timeout
# @exitcode other Exit code of the wrapped command
#######################################
function dybatpho::with_lock {
  local __dybatpho_lock_with_name __dybatpho_lock_with_timeout __dybatpho_lock_with_separator
  dybatpho::expect_args __dybatpho_lock_with_name __dybatpho_lock_with_timeout __dybatpho_lock_with_separator -- "$@"
  shift 3
  [[ "${__dybatpho_lock_with_separator}" == "--" ]] || dybatpho::die \
    "${FUNCNAME[0]}: Expected: name timeout -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  dybatpho::lock_acquire "${__dybatpho_lock_with_name}" "${__dybatpho_lock_with_timeout}" || return 1
  local __dybatpho_lock_with_quoted_name
  printf -v __dybatpho_lock_with_quoted_name '%q' "${__dybatpho_lock_with_name}"
  __dybatpho_lock_run_holding "dybatpho::lock_release ${__dybatpho_lock_with_quoted_name}" "$@"
}

#######################################
# @description Run a command while a lock is held, then run the release, even
#   when the command fails or the shell is interrupted.
#
#   Without the handlers, an interrupted command left the lock behind: the
#   release is only reached when the command returns normally, so Ctrl-C during
#   a long job left the lock for the next run to trip over. Releasing is
#   idempotent and checks ownership, so the handler and the normal path can both
#   run.
#
#   EXIT is deliberately not handled. An EXIT handler installed here outlives
#   this function, runs in whatever context the script ends in, and collides
#   with handlers the caller already has -- Bats being the case that showed it.
#   The residual gap is a command that is a shell *function* calling `exit`,
#   which ends this shell without a signal; a command run as a program, which is
#   what the `--` form is for, returns its status here and is released normally.
#   The handlers are put back afterwards rather than left in place: the wrappers
#   can be called many times in one script, and a handler per call would
#   accumulate, each one releasing a lock that is long gone.
# @arg $1 string Shell code that releases the lock, already quoted
# @arg $@ string Command and arguments to run
# @exitcode other Exit code of the command
# @internal
#######################################
function __dybatpho_lock_run_holding {
  local __dybatpho_lock_hold_release="$1"
  shift

  local __dybatpho_lock_hold_previous_traps
  __dybatpho_process_traps_save_into __dybatpho_lock_hold_previous_traps HUP INT TERM

  # The release handler stands alone while the command runs: appended after the
  # caller's, it never ran when that handler exited. It records the signal, and
  # once the lock is released and the caller's handlers are back the signal is
  # raised again, so they run once, after the release -- or the shell ends, as
  # it would have without a lock.
  local __dybatpho_lock_caught="" __dybatpho_lock_signal
  for __dybatpho_lock_signal in HUP INT TERM; do
    # kcov records no hit here, though "with_lock installs a release handler"
    # runs it and asserts the handler it installs.
    __dybatpho_process_trap_only \
      "${__dybatpho_lock_hold_release} > /dev/null 2>&1 || true; __dybatpho_lock_caught=${__dybatpho_lock_signal}" \
      "${__dybatpho_lock_signal}" # kcov(skip)
  done

  local __dybatpho_lock_hold_exit_code=0
  "$@" || __dybatpho_lock_hold_exit_code=$?
  eval "${__dybatpho_lock_hold_release}"

  __dybatpho_process_traps_restore "${__dybatpho_lock_hold_previous_traps}" HUP INT TERM
  if [[ -n "${__dybatpho_lock_caught}" ]]; then
    kill -s "${__dybatpho_lock_caught}" "${BASHPID}"
  fi
  return "${__dybatpho_lock_hold_exit_code}"
}

#######################################
# @description Print the path of one slot of a semaphore.
#   Each slot is an ordinary lock beside the others, named after the semaphore,
#   so everything that inspects or reclaims a lock works on a slot unchanged.
# @arg $1 string Semaphore name or path
# @arg $2 number Slot number, from 1
# @stdout The slot's lock path
# @internal
#######################################
function __dybatpho_lock_slot_path {
  local base
  base="$(dybatpho::lock_path "$1")"
  printf '%s.slot%s.lock\n' "${base%.lock}" "$2"
}

#######################################
# @description Stop the script when a slot count is not a whole number from 1
#   to 9999.
# @arg $1 number Slot count
# @internal
#######################################
function __dybatpho_lock_expect_slots {
  [[ "$1" =~ ^[1-9][0-9]{0,3}$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: The slot count must be a whole number from 1 to 9999, got: $1"
}

#######################################
# @description Take one of a fixed number of slots, so that at most that many
#   processes run a section at once, waiting up to a timeout for one to free up.
#
#   A semaphore is a row of ordinary locks, one per slot, tried in order. Each
#   slot is claimed atomically and records its holder, so a slot left by a dead
#   process is reclaimed exactly as a stale lock is, and a refusal names every
#   process holding a slot. Every caller must give the same slot count.
# @example
#   local slot
#   dybatpho::lock_semaphore_acquire downloads 4 60 slot || exit 1
#   curl -fsSLO "${url}"
#   dybatpho::lock_semaphore_release downloads 4 "${slot}"
#
# @arg $1 string Semaphore name (bare word resolved under `DYBATPHO_LOCK_DIR`) or an explicit path
# @arg $2 number Number of slots, from 1 to 9999
# @arg $3 number Seconds to wait for a free slot before giving up, default 0 (try once, don't wait)
# @arg $4 string Optional name of a variable receiving the slot number taken
# @set The named variable, when one is given
# @env DYBATPHO_LOCK_POLL_INTERVAL number Seconds to sleep between attempts while waiting
# @stderr Every holder when no slot could be taken
# @exitcode 0 A slot was taken by the current process
# @exitcode 1 Every slot is still held by a live process after the timeout
#######################################
function dybatpho::lock_semaphore_acquire {
  local __dybatpho_lock_sem_name __dybatpho_lock_sem_slots
  dybatpho::expect_args __dybatpho_lock_sem_name __dybatpho_lock_sem_slots -- "$@"
  [[ -z "${4-}" ]] || dybatpho::expect_ref "$4"
  __dybatpho_lock_semaphore_acquire "$@"
}

#######################################
# @description Take a semaphore slot, as `dybatpho::lock_semaphore_acquire`
#   does, without refusing a library-owned variable for the slot number: the
#   library's own runners keep that number in a prefixed local, which the
#   public check rightly refuses from a caller.
# @arg $1 string Semaphore name or path
# @arg $2 number Number of slots
# @arg $3 number Seconds to wait for a free slot
# @arg $4 string Name of the variable receiving the slot number taken
# @exitcode 0 A slot was taken
# @exitcode 1 Every slot stayed held for the whole wait
# @internal
#######################################
function __dybatpho_lock_semaphore_acquire {
  # Every local carries the library's prefix, so a caller's variable for the
  # slot number is never shadowed by one of them, whatever it is called.
  local __dybatpho_lock_name __dybatpho_lock_slots
  dybatpho::expect_args __dybatpho_lock_name __dybatpho_lock_slots -- "$@"
  local __dybatpho_lock_timeout="${3:-0}" __dybatpho_lock_target="${4-}"
  __dybatpho_lock_expect_slots "${__dybatpho_lock_slots}"
  dybatpho::is int "${__dybatpho_lock_timeout}" \
    || dybatpho::die \
      "dybatpho::lock_semaphore_acquire: The timeout must be a number of seconds, got: ${__dybatpho_lock_timeout}"

  local __dybatpho_lock_host_cache="" __dybatpho_lock_taken="" __dybatpho_lock_base
  __dybatpho_lock_base="$(dybatpho::lock_path "${__dybatpho_lock_name}")"
  if __dybatpho_lock_wait "${__dybatpho_lock_timeout}" \
    __dybatpho_lock_try_slots __dybatpho_lock_taken "${__dybatpho_lock_base%.lock}" "${__dybatpho_lock_slots}"; then
    if [[ -n "${__dybatpho_lock_target}" ]]; then
      local -n __dybatpho_lock_slot_ref="${__dybatpho_lock_target}"
      # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
      __dybatpho_lock_slot_ref="${__dybatpho_lock_taken}"
    fi
    return 0
  fi

  local __dybatpho_lock_holders
  __dybatpho_lock_holders="$(dybatpho::lock_semaphore_holders \
    "${__dybatpho_lock_name}" "${__dybatpho_lock_slots}" 2> /dev/null || true)"
  local __dybatpho_lock_message="Could not acquire a slot of semaphore ${__dybatpho_lock_name}:"
  __dybatpho_lock_message+=" all ${__dybatpho_lock_slots} are held"$'\n'"${__dybatpho_lock_holders}"
  dybatpho::error "${__dybatpho_lock_message}"
  return 1
}

#######################################
# @description Make one pass over a semaphore's slots, taking the first free one.
# @arg $1 string Name of the variable receiving the slot number taken
# @arg $2 string Semaphore lock path without its `.lock` suffix, resolved once per wait
# @arg $3 number Number of slots
# @set The named variable, when a slot was taken
# @exitcode 0 A slot was taken by the current process
# @exitcode 1 Every slot is held by a live process
# @internal
#######################################
function __dybatpho_lock_try_slots {
  local -n __dybatpho_lock_try_slot_out="$1"
  local __dybatpho_lock_try_base="$2" __dybatpho_lock_try_slots_n="$3"
  local __dybatpho_lock_try_slot
  for ((__dybatpho_lock_try_slot = 1; __dybatpho_lock_try_slot <= __dybatpho_lock_try_slots_n;  \
  __dybatpho_lock_try_slot++)); do
    __dybatpho_lock_try "${__dybatpho_lock_try_base}.slot${__dybatpho_lock_try_slot}.lock" || continue
    __dybatpho_lock_try_slot_out="${__dybatpho_lock_try_slot}"
    return 0
  done
  return 1
}

#######################################
# @description Give back a semaphore slot taken by the current process.
#   Naming the slot releases that one; without it, every slot the current
#   process holds is released, which is what an exit handler wants.
# @arg $1 string Semaphore name or path
# @arg $2 number Number of slots, as given when acquiring
# @arg $3 number Optional slot number to release
# @exitcode 0 The slot was released, or was not held by the current process
# @exitcode 1 The named slot is held by another live process and was left untouched
#######################################
function dybatpho::lock_semaphore_release {
  local name slots
  dybatpho::expect_args name slots -- "$@"
  local wanted="${3-}"
  __dybatpho_lock_expect_slots "${slots}"

  local slot_path
  if [[ -n "${wanted}" ]]; then
    if ! [[ "${wanted}" =~ ^[0-9]{1,4}$ ]] || ((10#${wanted} < 1 || 10#${wanted} > slots)); then
      # Tested under `run` ("refuse a bad slot count, slot or timeout"): it exits.
      dybatpho::die "${FUNCNAME[0]}: Not a slot of ${name}: ${wanted}" # kcov(skip)
    fi
    slot_path="$(__dybatpho_lock_slot_path "${name}" "$((10#${wanted}))")"
    dybatpho::lock_release "${slot_path}"
    return
  fi

  local slot owner
  for ((slot = 1; slot <= slots; slot++)); do
    slot_path="$(__dybatpho_lock_slot_path "${name}" "${slot}")"
    owner="$(dybatpho::lock_field "${slot_path}" pid)"
    [[ "${owner}" == "$$" ]] || continue
    dybatpho::lock_release "${slot_path}"
  done
}

#######################################
# @description Print who holds each taken slot of a semaphore.
# @arg $1 string Semaphore name or path
# @arg $2 number Number of slots
# @stdout `slot=<n> pid=<pid> host=<host> acquired_at=<timestamp> command=<command>`, one line per held slot
# @exitcode 0 At least one slot is held
# @exitcode 1 No slot is held
#######################################
function dybatpho::lock_semaphore_holders {
  local name slots
  dybatpho::expect_args name slots -- "$@"
  __dybatpho_lock_expect_slots "${slots}"

  local slot slot_path info found=1
  for ((slot = 1; slot <= slots; slot++)); do
    slot_path="$(__dybatpho_lock_slot_path "${name}" "${slot}")"
    info="$(dybatpho::lock_info "${slot_path}")" || continue
    printf 'slot=%s %s\n' "${slot}" "${info}"
    found=0
  done
  return "${found}"
}

#######################################
# @description Take a semaphore slot, run a command while holding it, then give
#   the slot back, even if the command fails or the shell is interrupted.
# @example
#   dybatpho::with_semaphore builds 2 300 -- make -C "${project}"
#
# @arg $1 string Semaphore name or path
# @arg $2 number Number of slots
# @arg $3 number Seconds to wait for a free slot before giving up
# @arg $4 string Literal `--` separating semaphore options from the command
# @arg $@ string Command and arguments to run while holding the slot
# @exitcode 1 No slot could be taken within the timeout
# @exitcode other Exit code of the wrapped command
#######################################
function dybatpho::with_semaphore {
  local __dybatpho_lock_semrun_name __dybatpho_lock_semrun_slots __dybatpho_lock_semrun_timeout
  local __dybatpho_lock_semrun_separator
  dybatpho::expect_args __dybatpho_lock_semrun_name __dybatpho_lock_semrun_slots __dybatpho_lock_semrun_timeout \
    __dybatpho_lock_semrun_separator -- "$@"
  shift 4
  [[ "${__dybatpho_lock_semrun_separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: name slots timeout -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local __dybatpho_lock_semrun_slot
  __dybatpho_lock_semaphore_acquire "${__dybatpho_lock_semrun_name}" "${__dybatpho_lock_semrun_slots}" \
    "${__dybatpho_lock_semrun_timeout}" __dybatpho_lock_semrun_slot || return 1
  local __dybatpho_lock_semrun_release
  printf -v __dybatpho_lock_semrun_release 'dybatpho::lock_semaphore_release %q %q %q' \
    "${__dybatpho_lock_semrun_name}" "${__dybatpho_lock_semrun_slots}" "${__dybatpho_lock_semrun_slot}"
  __dybatpho_lock_run_holding "${__dybatpho_lock_semrun_release}" "$@"
}
