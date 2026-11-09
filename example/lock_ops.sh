#!/usr/bin/env bash
# @file lock_ops.sh
# @brief Example showing portable process locking utilities
# @description Demonstrates dybatpho::lock_acquire, lock_release, lock_is_held,
#              lock_info, and with_lock to prevent concurrent script runs, and
#              flock_acquire, flock_release and with_flock to share a lock with
#              programs that `flock` the same file
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules lock

dybatpho::register_common_handlers

# A directory of its own, removed when the script ends, so two copies of this
# example running at once -- as the test suite does -- never share a lock.
dybatpho::create_temp_dir DYBATPHO_LOCK_DIR "lock-example"
LOCK_NAME="lock_ops_demo"

# --- acquire / release ------------------------------------------------------

# @description Run the `ACQUIRE / RELEASE` section of this example.
# @noargs
function _demo_acquire_release {
  dybatpho::header "ACQUIRE / RELEASE"
  if dybatpho::lock_acquire "${LOCK_NAME}"; then
    dybatpho::success "Lock acquired by pid $$"
  fi
  local lock_is_held_2
  lock_is_held_2=$(dybatpho::lock_is_held "${LOCK_NAME}" && echo yes || echo no)
  dybatpho::info "Currently held? ${lock_is_held_2}"
  dybatpho::lock_release "${LOCK_NAME}"
  local lock_is_held
  lock_is_held=$(dybatpho::lock_is_held "${LOCK_NAME}" && echo yes || echo no)
  dybatpho::info "Released. Currently held? ${lock_is_held}"
}

# --- prevent a concurrent run ------------------------------------------------

# @description Run the `PREVENT CONCURRENT RUN` section of this example.
# @noargs
function _demo_prevent_concurrent_run {
  dybatpho::header "PREVENT CONCURRENT RUN"
  dybatpho::lock_acquire "${LOCK_NAME}"
  dybatpho::info "First 'run' holds the lock"

  if ! dybatpho::lock_acquire "${LOCK_NAME}"; then
    dybatpho::warn "A second concurrent 'run' was rejected (expected)"
  fi

  dybatpho::lock_release "${LOCK_NAME}"
}

# --- inspect the holder ------------------------------------------------------

# @description Run the `LOCK INFO` section of this example.
# @noargs
function _demo_lock_info {
  dybatpho::header "LOCK INFO"
  dybatpho::lock_acquire "${LOCK_NAME}"
  local lock_info
  lock_info=$(dybatpho::lock_info "${LOCK_NAME}")
  dybatpho::info "Holder: ${lock_info}"
  dybatpho::lock_release "${LOCK_NAME}"
}

# --- wait with a timeout ------------------------------------------------------

# @description Run the `WAIT WITH TIMEOUT` section of this example.
# @noargs
function _demo_wait_with_timeout {
  dybatpho::header "WAIT WITH TIMEOUT"
  dybatpho::lock_acquire "${LOCK_NAME}"
  (
    sleep 1
    dybatpho::lock_release "${LOCK_NAME}"
  ) &
  local releaser_pid=$!

  dybatpho::info "Waiting up to 3s for the lock to free up..."
  if dybatpho::lock_acquire "${LOCK_NAME}" 3; then
    dybatpho::success "Lock acquired after waiting"
    dybatpho::lock_release "${LOCK_NAME}"
  fi
  wait "${releaser_pid}" 2> /dev/null || true
}

# --- with_lock convenience wrapper -------------------------------------------

# @description Run the `WITH_LOCK` section of this example.
# @noargs
function _demo_with_lock {
  dybatpho::header "WITH_LOCK"
  dybatpho::with_lock "${LOCK_NAME}" 5 -- bash -c 'echo "running while holding the lock"'
  dybatpho::success "Command ran and lock was released automatically"
}

# --- semaphore --------------------------------------------------------------

# @description Run the `SEMAPHORE` section of this example: two slots, three
#   workers, and the third waits for one of the first two to finish.
# @noargs
function _demo_semaphore {
  dybatpho::header "SEMAPHORE"
  local name="${LOCK_NAME}-pool" first second
  dybatpho::lock_semaphore_acquire "${name}" 2 0 first
  dybatpho::lock_semaphore_acquire "${name}" 2 0 second
  dybatpho::info "Holding slots ${first} and ${second}:"
  dybatpho::lock_semaphore_holders "${name}" 2 | cut -d' ' -f1-2

  if ! dybatpho::lock_semaphore_acquire "${name}" 2 2> /dev/null; then
    dybatpho::warn "A third worker is turned away while both slots are held"
  fi

  (
    sleep 1
    dybatpho::lock_semaphore_release "${name}" 2 "${first}"
  ) &
  local releaser_pid=$!
  dybatpho::with_semaphore "${name}" 2 3 -- bash -c 'echo "third worker ran once a slot freed"'
  wait "${releaser_pid}" 2> /dev/null || true
  dybatpho::lock_semaphore_release "${name}" 2
  dybatpho::success "Every slot given back"
}

# --- flock -----------------------------------------------------------------

# @description Count one more update of the demo state; run under `with_flock`,
#   in the current shell, so the count reaches the caller.
# @noargs
function _bump_state {
  STATE_UPDATES=$((STATE_UPDATES + 1))
}

# @description Run the `FLOCK` section of this example: a lock shared with a
#   program that `flock`s the same file, two locks held at once, and a function
#   run under the lock. Skipped where `flock` isn't installed, as on macOS.
# @noargs
function _demo_flock {
  dybatpho::header "FLOCK"
  if ! command -v flock > /dev/null; then
    dybatpho::warn "flock isn't installed; skipping (install util-linux, or 'brew install flock')"
    return 0
  fi
  local state index state_fd index_fd
  state="$(dybatpho::lock_path "${LOCK_NAME}-state")"
  index="$(dybatpho::lock_path "${LOCK_NAME}-index")"
  dybatpho::flock_acquire state_fd "${state}"
  dybatpho::flock_acquire index_fd "${index}" 0
  dybatpho::info "Holding both locks, on descriptors ${state_fd} and ${index_fd}"
  if ! flock -n "${state}" true; then
    dybatpho::warn "Another program running 'flock -n' on the file is turned away (expected)"
  fi
  dybatpho::flock_release "${index_fd}"
  dybatpho::flock_release "${state_fd}"

  STATE_UPDATES=0
  dybatpho::with_flock "${state}" 5 -- _bump_state
  dybatpho::success "Updated the state ${STATE_UPDATES} time under the lock, then let it go"
}

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_acquire_release
  _demo_prevent_concurrent_run
  _demo_lock_info
  _demo_wait_with_timeout
  _demo_with_lock
  _demo_semaphore
  _demo_flock
  dybatpho::success "Lock operations demo complete"
}

_main "$@"
