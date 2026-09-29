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
readonly __DYBATPHO_LOCK_COMMAND_SUFFIX=".command"

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
#######################################
function __dybatpho_lock_exists {
  [[ -L "${1-}" ]] || dybatpho::is dir "${1-}"
}

#######################################
# @description Print the link target that identifies the holder of a lock,
#   as `pid:host:acquired_at`.
# @noargs
# @stdout The target
#######################################
function __dybatpho_lock_target {
  local date
  local date_2
  date_2=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  date=${date_2}
  local lock_hostname
  lock_hostname=$(dybatpho::lock_hostname)
  printf '%s:%s:%s' \
    "$$" "${lock_hostname}" "${date}"
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
    lock_path="${DYBATPHO_LOCK_DIR%/}/dybatpho-${name}"
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

  local pid host
  pid="$(dybatpho::lock_field "${lock_path}" pid)"
  host="$(dybatpho::lock_field "${lock_path}" host)"

  [[ -n "${pid}" ]] || return 1
  # A lock recorded on a different host can't be checked for liveness locally,
  # so conservatively treat it as still held.
  if [[ -n "${host}" && "${host}" != "$(dybatpho::lock_hostname)" ]]; then
    return 0
  fi
  kill -0 "${pid}" > /dev/null 2>&1
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
  local lock_field
  lock_field=$(dybatpho::lock_field "${lock_path}" command)
  local lock_field_2
  lock_field_2=$(dybatpho::lock_field "${lock_path}" pid)
  local lock_field_3
  lock_field_3=$(dybatpho::lock_field "${lock_path}" acquired_at)
  local lock_field_4
  lock_field_4=$(dybatpho::lock_field "${lock_path}" host)
  printf 'pid=%s host=%s acquired_at=%s command=%s\n' \
    "${lock_field_2}" \
    "${lock_field_4}" \
    "${lock_field_3}" \
    "${lock_field}"
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
  dybatpho::lock_is_alive "${lock_path}" && return 0
  pid="$(dybatpho::lock_field "${lock_path}" pid)"

  # A name no other process can be moving a lock to: two reclaimers of the same
  # lock must not collide on the destination, or the rename would succeed for
  # both and the check below would lose its meaning.
  local aside="${lock_path}.stale.$$.${RANDOM}"
  mv -- "${lock_path}" "${aside}" 2> /dev/null || return 0

  local moved
  moved="$(__dybatpho_lock_identity "${aside}")"
  if [[ -n "${holder}" && "${moved}" != "${holder}" ]]; then
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
# @description Print what identifies the holder of a lock, for comparing one
#   observation of a lock with a later one. It is the link target for the
#   atomic form, and the recorded pid for the directory form older copies of
#   the library wrote.
# @arg $1 string Lock path
# @stdout The identity, or nothing when the lock is gone
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

  local lock_path
  lock_path="$(dybatpho::lock_path "${name}")"

  local start_time elapsed
  start_time="$(date +%s)"
  while true; do
    dybatpho::lock_reclaim_stale "${lock_path}"

    # One syscall claims the lock and says who holds it. `symlink()` fails when
    # the name already exists, and the identity is already in the target, so
    # there is no window in which the lock exists without an owner. Claiming
    # with `mkdir` and writing the pid afterwards left exactly such a window,
    # and a second process read the missing pid as "nobody holds this", removed
    # the lock and took it.
    local lock_target
    lock_target=$(__dybatpho_lock_target)
    if ln -s "${lock_target}" "${lock_path}" 2> /dev/null; then
      printf '%s' "${DYBATPHO_LOCK_COMMAND:-$0}" \
        > "${lock_path}${__DYBATPHO_LOCK_COMMAND_SUFFIX}" 2> /dev/null || true
      return 0
    fi

    elapsed=$(($(date +%s) - start_time))
    if ((elapsed >= timeout)); then
      local holder
      holder="$(dybatpho::lock_info "${name}" 2> /dev/null || echo 'held by an unknown process')"
      dybatpho::error "Could not acquire lock ${lock_path}: ${holder}"
      return 1
    fi
    sleep "${DYBATPHO_LOCK_POLL_INTERVAL}"
  done
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
  local name timeout separator
  dybatpho::expect_args name timeout separator -- "$@"
  shift 3
  [[ "${separator}" == "--" ]] || dybatpho::die "${FUNCNAME[0]}: Expected: name timeout -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  dybatpho::lock_acquire "${name}" "${timeout}" || return 1

  # Without this, an interrupted command left the lock behind: the release below
  # is only reached when the command returns normally, so Ctrl-C during a long
  # job left the lock for the next run to trip over. Releasing is idempotent and
  # checks ownership, so the handler and the normal path can both run.
  #
  # EXIT is deliberately not handled. An EXIT handler installed here outlives
  # this function, runs in whatever context the script ends in, and collides
  # with handlers the caller already has -- Bats being the case that showed it.
  # The residual gap is a command that is a shell *function* calling `exit`,
  # which ends this shell without a signal; a command run as a program, which is
  # what the `--` form is for, returns its status here and is released normally.
  # The handlers are put back afterwards rather than left in place: `with_lock`
  # can be called many times in one script, and a handler per call would
  # accumulate, each one releasing a lock that is long gone.
  local quoted_name previous_traps signal
  printf -v quoted_name '%q' "${name}"
  previous_traps=""
  for signal in HUP INT TERM; do
    previous_traps+="$(trap -p "${signal}")"$'\n'
  done

  dybatpho::trap "dybatpho::lock_release ${quoted_name} > /dev/null 2>&1 || true" \
    HUP INT TERM

  local exit_code=0
  "$@" || exit_code=$?
  dybatpho::lock_release "${name}"

  trap - HUP INT TERM
  eval "${previous_traps}"
  return "${exit_code}"
}
