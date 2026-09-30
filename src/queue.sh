# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file queue.sh
# @brief A durable job queue backed by the filesystem
# @namespace dybatpho
# @description
#   `parallel.sh` runs a bounded worker pool over a job list that has to be
#   known up front, and nothing of it survives the script dying: the jobs still
#   waiting are gone with it. This module is the other half — a queue that
#   lives on disk, that a producer can add to while workers are already
#   running, and that a crashed run can be resumed from.
#
#   A job is claimed rather than consumed. `dybatpho::queue_pop` moves it out
#   of `pending` and into `claimed`, and it stays there until the worker says
#   what happened: `dybatpho::queue_complete` removes it,
#   `dybatpho::queue_requeue` puts it back, and
#   `dybatpho::queue_dead_letter` files it under `dead` rather than dropping
#   it. A worker that dies leaves its job in `claimed`, where it can be seen
#   and requeued, instead of vanishing between the read and the work.
#
#   Ordering is strict FIFO. The sequence number in a job's id is handed out
#   under the queue's lock rather than taken from the clock, so two producers
#   in the same second still come out in the order they arrived — a
#   second-resolution timestamp could not tell them apart, and `date` has no
#   portable sub-second field.
# @tip A payload is text, and may be anything including newlines; encode a
#   structured payload with `json.sh` before pushing it and decode it after
# @tip A bare queue name lives under `DYBATPHO_QUEUE_DIR`; a name containing a
#   slash is used as the directory itself
# @env DYBATPHO_QUEUE_DIR string Base directory for bare queue names, default is the XDG state directory
# @env DYBATPHO_QUEUE_TIMEOUT number Seconds to wait for the queue lock, default is `10`
# @see
#   - `example/queue_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_QUEUE_DIR string Where a bare queue name resolves to
DYBATPHO_QUEUE_DIR="${DYBATPHO_QUEUE_DIR:-}"
# @env DYBATPHO_QUEUE_TIMEOUT number Seconds a queue operation waits for the lock, default is `10`
DYBATPHO_QUEUE_TIMEOUT="${DYBATPHO_QUEUE_TIMEOUT:-10}"

#######################################
# @description Resolve a queue name to its directory, into a named variable.
#   A name with a slash in it is a path; a bare name lives under
#   `DYBATPHO_QUEUE_DIR`, or the XDG state directory when that is unset.
# @arg $1 string Name of the variable receiving the directory
# @arg $2 string Queue name or path
# @set The named variable
# @internal
#######################################
function __dybatpho_queue_dir_into {
  local -n __dybatpho_queue_dir_ref="$1"
  local __dybatpho_queue_name="$2"

  [[ -n "${__dybatpho_queue_name}" ]] \
    || dybatpho::die "${FUNCNAME[1]}: Expected a queue name"

  if [[ "${__dybatpho_queue_name}" == */* ]]; then
    __dybatpho_queue_dir_ref="${__dybatpho_queue_name}"
    return 0
  fi

  local __dybatpho_queue_base="${DYBATPHO_QUEUE_DIR}"
  if [[ -z "${__dybatpho_queue_base}" ]]; then
    __dybatpho_queue_base="$(dybatpho::xdg_state_dir)/queues"
  fi
  __dybatpho_queue_dir_ref="${__dybatpho_queue_base}/${__dybatpho_queue_name}"
}

#######################################
# @description Create a queue's directories if they are not there yet.
# @arg $1 string Queue directory
# @internal
#######################################
function __dybatpho_queue_prepare {
  local state
  for state in pending claimed dead; do
    dybatpho::ensure_dir "$1/${state}" > /dev/null
  done
}

#######################################
# @description Print the lock name guarding a queue directory.
#   The lock lives inside the queue, so two queues never block each other and
#   a queue given as an explicit path carries its own lock with it.
# @arg $1 string Queue directory
# @stdout Lock path
# @internal
#######################################
function __dybatpho_queue_lock {
  printf '%s/.lock\n' "$1"
}

#######################################
# @description Reject a job id that could escape the queue directory.
#   An id reaches the filesystem as a path component, so one containing a
#   slash or `..` would let a caller name a file outside the queue.
# @arg $1 string Job id
# @exitcode 0 The id is safe to use as a file name
# @exitcode 1 Stop the script when it is not
# @internal
#######################################
function __dybatpho_queue_expect_id {
  [[ "$1" =~ ^[0-9]{12}-[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Not a job id: $1"
}

#######################################
# @description Print a queue's job ids for one state, oldest first.
# @arg $1 string Queue directory
# @arg $2 string State directory: `pending`, `claimed`, or `dead`
# @stdout One job id per line
# @internal
#######################################
function __dybatpho_queue_ids {
  local path
  # The id starts with a zero-padded sequence number, so the glob's own
  # ascending order is the order the jobs were pushed in.
  for path in "$1/$2"/*.job; do
    dybatpho::is file "${path}" || continue
    path="${path##*/}"
    printf '%s\n' "${path%.job}"
  done
}

#######################################
# @description Take the next sequence number for a queue, into a named
#   variable. The caller must already hold the queue's lock.
# @arg $1 string Name of the variable receiving the number
# @arg $2 string Queue directory
# @set The named variable, zero-padded to twelve digits
# @internal
#######################################
function __dybatpho_queue_next_sequence_into {
  local -n __dybatpho_queue_seq_ref="$1"
  local __dybatpho_queue_counter="$2/.sequence"
  local __dybatpho_queue_value=0

  if dybatpho::is file "${__dybatpho_queue_counter}"; then
    read -r __dybatpho_queue_value < "${__dybatpho_queue_counter}"
    [[ "${__dybatpho_queue_value}" =~ ^[0-9]+$ ]] || __dybatpho_queue_value=0
  fi

  __dybatpho_queue_value=$((__dybatpho_queue_value + 1))
  printf '%s\n' "${__dybatpho_queue_value}" > "${__dybatpho_queue_counter}"
  printf -v __dybatpho_queue_seq_ref '%012d' "${__dybatpho_queue_value}"
}

#######################################
# @description Add a job to a queue.
#   The payload is written to a temporary file and renamed into `pending`, so
#   a worker never sees a job whose payload is still being written.
# @arg $1 string Queue name or path
# @arg $2 string Payload text, or `-` to read it from stdin
# @stdout The new job's id
# @exitcode 0 The job was added
# @exitcode 1 The queue lock could not be taken
# @example
#   id="$(dybatpho::queue_push deploys "restart api")"
#######################################
function dybatpho::queue_push {
  local queue payload
  dybatpho::expect_args queue payload -- "$@"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  __dybatpho_queue_prepare "${directory}"

  local text="${payload}"
  [[ "${payload}" != "-" ]] || text="$(cat)"

  local lock
  lock="$(__dybatpho_queue_lock "${directory}")"
  dybatpho::lock_acquire "${lock}" "${DYBATPHO_QUEUE_TIMEOUT}" || return 1

  local sequence identifier
  __dybatpho_queue_next_sequence_into sequence "${directory}"
  identifier="${sequence}-$(dybatpho::date_now "%s")"
  printf '%s\n' "${text}" > "${directory}/pending/${identifier}.job"

  dybatpho::lock_release "${lock}"
  printf '%s\n' "${identifier}"
}

#######################################
# @description Claim the oldest job in a queue.
#   The job moves from `pending` to `claimed` and stays there until the caller
#   completes, requeues, or dead-letters it, so a worker that dies leaves its
#   job where it can be found rather than losing it.
# @arg $1 string Queue name or path
# @arg $2 string Name of the variable receiving the job id
# @arg $3 string Name of the variable receiving the payload
# @set Both named variables
# @exitcode 0 A job was claimed
# @exitcode 1 The queue is empty, or its lock could not be taken
# @example
#   while dybatpho::queue_pop deploys id payload; do
#     if handle "${payload}"; then
#       dybatpho::queue_complete deploys "${id}"
#     else
#       dybatpho::queue_requeue deploys "${id}" 3
#     fi
#   done
#######################################
function dybatpho::queue_pop {
  local queue id_target payload_target
  dybatpho::expect_args queue id_target payload_target -- "$@"
  dybatpho::expect_ref "${id_target}"
  dybatpho::expect_ref "${payload_target}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  __dybatpho_queue_prepare "${directory}"

  local lock
  lock="$(__dybatpho_queue_lock "${directory}")"
  dybatpho::lock_acquire "${lock}" "${DYBATPHO_QUEUE_TIMEOUT}" || return 1

  # Choosing and moving the job happen under one lock. Apart, two workers
  # would both read the same oldest job and both go on to run it.
  local -a waiting=()
  local identifier
  while IFS= read -r identifier; do
    [[ -n "${identifier}" ]] || continue
    waiting+=("${identifier}")
    break
  done < <(__dybatpho_queue_ids "${directory}" pending)

  if ((${#waiting[@]} == 0)); then
    dybatpho::lock_release "${lock}"
    return 1
  fi

  identifier="${waiting[0]}"
  mv -- "${directory}/pending/${identifier}.job" "${directory}/claimed/${identifier}.job"
  # The retry count travels with the job. Left behind in `pending`, it would
  # not be found on the next requeue, the count would restart at one, and a
  # job that always fails would circulate forever instead of dead-lettering.
  if dybatpho::is file "${directory}/pending/${identifier}.retries"; then
    mv -- "${directory}/pending/${identifier}.retries" "${directory}/claimed/${identifier}.retries"
  fi
  dybatpho::lock_release "${lock}"

  local -n id_ref="${id_target}"
  local -n payload_ref="${payload_target}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  id_ref="${identifier}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  payload_ref="$(< "${directory}/claimed/${identifier}.job")"
}

#######################################
# @description Read the oldest waiting job without claiming it.
# @arg $1 string Queue name or path
# @arg $2 string Optional name of a variable receiving the job id
# @set The named variable, when one is given
# @stdout The payload of the oldest waiting job
# @exitcode 0 A job was read
# @exitcode 1 The queue is empty
# @example
#   dybatpho::queue_peek deploys
#######################################
function dybatpho::queue_peek {
  local queue
  dybatpho::expect_args queue -- "$@"
  local id_target="${2-}"
  [[ -z "${id_target}" ]] || dybatpho::expect_ref "${id_target}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  dybatpho::is dir "${directory}/pending" || return 1

  local identifier=""
  while IFS= read -r identifier; do
    [[ -n "${identifier}" ]] && break
  done < <(__dybatpho_queue_ids "${directory}" pending)
  [[ -n "${identifier}" ]] || return 1

  if [[ -n "${id_target}" ]]; then
    local -n peek_id_ref="${id_target}"
    # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
    peek_id_ref="${identifier}"
  fi
  printf '%s\n' "$(< "${directory}/pending/${identifier}.job")"
}

#######################################
# @description Count the jobs in one of a queue's states.
# @arg $1 string Queue name or path
# @arg $2 string Optional state: `pending` (default), `claimed`, or `dead`
# @stdout The number of jobs
# @exitcode 0 The count was printed
# @exitcode 1 The state is not one this module keeps
# @example
#   (($(dybatpho::queue_len deploys) > 0)) && dybatpho::info "Work is waiting"
#######################################
function dybatpho::queue_len {
  local queue
  dybatpho::expect_args queue -- "$@"
  local state="${2:-pending}"
  __dybatpho_queue_expect_state "${state}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  if ! dybatpho::is dir "${directory}/${state}"; then
    printf '0\n'
    return 0
  fi

  local -a found=()
  local identifier
  while IFS= read -r identifier; do
    [[ -n "${identifier}" ]] || continue
    found+=("${identifier}")
  done < <(__dybatpho_queue_ids "${directory}" "${state}")
  printf '%s\n' "${#found[@]}"
}

#######################################
# @description List a queue's job ids for one state, oldest first.
# @arg $1 string Queue name or path
# @arg $2 string Optional state: `pending` (default), `claimed`, or `dead`
# @stdout One job id per line
# @exitcode 0 The listing was printed, empty when there is nothing to list
# @exitcode 1 The state is not one this module keeps
# @example
#   dybatpho::queue_list deploys dead
#######################################
function dybatpho::queue_list {
  local queue
  dybatpho::expect_args queue -- "$@"
  local state="${2:-pending}"
  __dybatpho_queue_expect_state "${state}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  dybatpho::is dir "${directory}/${state}" || return 0
  __dybatpho_queue_ids "${directory}" "${state}"
}

#######################################
# @description Stop when a state is not one of the three a queue keeps.
# @arg $1 string State name
# @exitcode 0 The state is known
# @exitcode 1 Stop the script when it is not
# @internal
#######################################
function __dybatpho_queue_expect_state {
  case "$1" in
    pending | claimed | dead) ;; # kcov(skip) - a case arm has no command to fire on
    *) dybatpho::die "${FUNCNAME[1]}: Not a queue state: $1. Use pending, claimed, or dead" ;; # kcov(skip)
  esac
}

#######################################
# @description Remove a claimed job, marking the work as done.
# @arg $1 string Queue name or path
# @arg $2 string Job id
# @exitcode 0 The job was removed
# @exitcode 1 No such job is claimed
# @example
#   dybatpho::queue_complete deploys "${id}"
#######################################
function dybatpho::queue_complete {
  local queue identifier
  dybatpho::expect_args queue identifier -- "$@"
  __dybatpho_queue_expect_id "${identifier}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  local job="${directory}/claimed/${identifier}.job"
  dybatpho::is file "${job}" \
    || dybatpho::die "${FUNCNAME[0]}: No claimed job with id: ${identifier}"

  rm -f -- "${job}" "${directory}/claimed/${identifier}.retries"
}

#######################################
# @description Put a claimed job back at the end of the queue.
#   Each requeue counts, and when a job has been requeued as many times as the
#   budget allows it is dead-lettered instead, so a job that always fails stops
#   circulating without being thrown away.
# @arg $1 string Queue name or path
# @arg $2 string Job id
# @arg $3 number Optional retry budget; past it the job is dead-lettered instead
# @stdout The job's new id when it is requeued
# @exitcode 0 The job was requeued, or dead-lettered because its budget ran out
# @exitcode 1 No such job is claimed, or the queue lock could not be taken
# @example
#   dybatpho::queue_requeue deploys "${id}" 3
#######################################
function dybatpho::queue_requeue {
  local queue identifier
  dybatpho::expect_args queue identifier -- "$@"
  local budget="${3-}"
  __dybatpho_queue_expect_id "${identifier}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  local job="${directory}/claimed/${identifier}.job"
  dybatpho::is file "${job}" \
    || dybatpho::die "${FUNCNAME[0]}: No claimed job with id: ${identifier}"

  local attempts=0 counter="${directory}/claimed/${identifier}.retries"
  if dybatpho::is file "${counter}"; then
    read -r attempts < "${counter}"
    [[ "${attempts}" =~ ^[0-9]+$ ]] || attempts=0
  fi
  attempts=$((attempts + 1))

  if [[ -n "${budget}" ]]; then
    dybatpho::is int "${budget}" \
      || dybatpho::die "${FUNCNAME[0]}: The retry budget must be a number, got: ${budget}"
    if ((attempts > budget)); then
      dybatpho::queue_dead_letter "${queue}" "${identifier}"
      return 0
    fi
  fi

  # The job goes back with a new id rather than its old one: keeping the id
  # would put a failing job back at the head of the queue, where it would be
  # retried before everything pushed since.
  local payload fresh
  payload="$(< "${job}")"
  fresh="$(dybatpho::queue_push "${queue}" "${payload}")" || return 1
  printf '%s\n' "${attempts}" > "${directory}/pending/${fresh}.retries"
  rm -f -- "${job}" "${counter}"
  printf '%s\n' "${fresh}"
}

#######################################
# @description Move a claimed job to the queue's dead letters.
#   A job that cannot be handled is kept rather than deleted, so an operator
#   can read it, fix the cause, and push it again.
# @arg $1 string Queue name or path
# @arg $2 string Job id
# @exitcode 0 The job was filed under dead letters
# @exitcode 1 No such job is claimed
# @example
#   dybatpho::queue_dead_letter deploys "${id}"
#######################################
function dybatpho::queue_dead_letter {
  local queue identifier
  dybatpho::expect_args queue identifier -- "$@"
  __dybatpho_queue_expect_id "${identifier}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"
  local job="${directory}/claimed/${identifier}.job"
  dybatpho::is file "${job}" \
    || dybatpho::die "${FUNCNAME[0]}: No claimed job with id: ${identifier}"

  __dybatpho_queue_prepare "${directory}"
  mv -- "${job}" "${directory}/dead/${identifier}.job"
  local counter="${directory}/claimed/${identifier}.retries"
  dybatpho::is file "${counter}" && mv -- "${counter}" "${directory}/dead/${identifier}.retries"
  return 0
}

#######################################
# @description Read a job's payload from any state, into a named variable.
# @arg $1 string Queue name or path
# @arg $2 string Job id
# @arg $3 string Name of the variable receiving the payload
# @arg $4 string Optional state: `pending`, `claimed`, or `dead`, default is to search all three
# @set The named variable
# @exitcode 0 The job was read
# @exitcode 1 No job with that id is in the queue
# @example
#   dybatpho::queue_read deploys "${id}" payload dead
#######################################
function dybatpho::queue_read {
  local queue identifier target
  dybatpho::expect_args queue identifier target -- "$@"
  __dybatpho_queue_expect_id "${identifier}"
  dybatpho::expect_ref "${target}"
  local wanted="${4-}"
  [[ -z "${wanted}" ]] || __dybatpho_queue_expect_state "${wanted}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"

  local -a states=(pending claimed dead)
  [[ -z "${wanted}" ]] || states=("${wanted}")

  local -n payload_ref="${target}"
  local state
  for state in "${states[@]}"; do
    if dybatpho::is file "${directory}/${state}/${identifier}.job"; then
      # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
      payload_ref="$(< "${directory}/${state}/${identifier}.job")"
      return 0
    fi
  done
  return 1
}
