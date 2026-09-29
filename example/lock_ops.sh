#!/usr/bin/env bash
# @file lock_ops.sh
# @brief Example showing portable process locking utilities
# @description Demonstrates dybatpho::lock_acquire, lock_release, lock_is_held,
#              lock_info, and with_lock to prevent concurrent script runs
# shellcheck disable=SC2034 # DYBATPHO_LOCK_DIR is read by the lock module, not by this script
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules lock

dybatpho::register_common_handlers

DYBATPHO_LOCK_DIR="${TMPDIR:-/tmp}"
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

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_acquire_release
  _demo_prevent_concurrent_run
  _demo_lock_info
  _demo_wait_with_timeout
  _demo_with_lock
  dybatpho::success "Lock operations demo complete"
}

_main "$@"
