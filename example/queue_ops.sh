#!/usr/bin/env bash
# @file queue_ops.sh
# @brief Example draining a durable job queue with several workers
# @description Demonstrates dybatpho::queue_push, queue_peek, queue_len, queue_pop,
#   queue_complete, queue_requeue, queue_dead_letter, queue_list, and queue_read
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules queue

dybatpho::register_common_handlers

# @description Build a queue directory of its own, so the example never
#   touches a real one under the XDG state directory.
# @arg $1 string Name of the variable receiving the queue path
# @set The named variable
function _make_queue {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  local -n queue_ref="${target}"

  local workspace
  dybatpho::create_temp workspace "/" "queue-demo"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  queue_ref="${workspace}/deploys"
}

# @description Fill the queue, including one job that will never succeed.
# @arg $1 string Queue path
function _demo_push {
  local queue
  dybatpho::expect_args queue -- "$@"

  dybatpho::header "PUSH"
  local service
  for service in api web worker; do
    dybatpho::queue_push "${queue}" "restart ${service}" > /dev/null
  done
  # A payload is text and may hold anything, line breaks included.
  dybatpho::queue_push "${queue}" "$(printf 'migrate db\n--dry-run')" > /dev/null
  dybatpho::queue_push "${queue}" "restart poison" > /dev/null

  dybatpho::info "Waiting: $(dybatpho::queue_len "${queue}")"
  dybatpho::info "Next up: $(dybatpho::queue_peek "${queue}")"
}

# @description Handle one job. The poison job always fails, which is what
#   drives the retry budget below.
# @arg $1 string Payload
# @exitcode 0 The job was handled
# @exitcode 1 It failed
function _handle {
  local payload
  dybatpho::expect_args payload -- "$@"
  [[ "${payload}" != *poison* ]]
}

# @description Drain the queue, retrying a failure up to a budget.
#   A job is claimed rather than consumed, so this loop always says what
#   happened to it: completed, requeued, or filed under dead letters.
# @arg $1 string Queue path
function _demo_drain {
  local queue
  dybatpho::expect_args queue -- "$@"

  dybatpho::header "DRAIN"
  local id payload outcome
  while dybatpho::queue_pop "${queue}" id payload; do
    if _handle "${payload}"; then
      dybatpho::queue_complete "${queue}" "${id}"
      printf 'done      %s\n' "${payload%%$'\n'*}"
      continue
    fi

    # Past the budget this dead-letters instead, and prints nothing.
    outcome="$(dybatpho::queue_requeue "${queue}" "${id}" 2)"
    if [[ -n "${outcome}" ]]; then
      printf 'retrying  %s\n' "${payload}"
    else
      printf 'gave up   %s\n' "${payload}"
    fi
  done
}

# @description Show what is left: nothing waiting, nothing in flight, and the
#   job that could not be handled kept for an operator to look at.
# @arg $1 string Queue path
function _demo_dead_letters {
  local queue
  dybatpho::expect_args queue -- "$@"

  dybatpho::header "AFTERWARDS"
  local counts
  printf -v counts 'pending=%s claimed=%s dead=%s' \
    "$(dybatpho::queue_len "${queue}")" \
    "$(dybatpho::queue_len "${queue}" claimed)" \
    "$(dybatpho::queue_len "${queue}" dead)"
  dybatpho::info "${counts}"

  local id payload
  while read -r id; do
    dybatpho::queue_read "${queue}" "${id}" payload dead
    printf 'dead letter %s: %s\n' "${id}" "${payload}"
  done < <(dybatpho::queue_list "${queue}" dead)
}

# @description Show that a claimed job outlives a worker that dies.
#   This is the difference between claiming a job and consuming it.
# @arg $1 string Queue path
function _demo_crash_recovery {
  local queue
  dybatpho::expect_args queue -- "$@"

  dybatpho::header "CRASH RECOVERY"
  dybatpho::queue_push "${queue}" "restart cache" > /dev/null

  local id payload
  dybatpho::queue_pop "${queue}" id payload
  dybatpho::warn "A worker claimed ${id} and then died"
  dybatpho::info "Still in flight: $(dybatpho::queue_len "${queue}" claimed)"

  # An operator, or a janitor run at startup, puts it back.
  dybatpho::queue_requeue "${queue}" "${id}" > /dev/null
  dybatpho::success "Requeued; waiting again: $(dybatpho::queue_len "${queue}")"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  local queue
  _make_queue queue
  _demo_push "${queue}"
  _demo_drain "${queue}"
  _demo_dead_letters "${queue}"
  _demo_crash_recovery "${queue}"
  dybatpho::success "Queue operations demo complete"
}

_main "$@"
