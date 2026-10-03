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
#   Ordering is FIFO within a priority. The sequence number in a job's id is
#   handed out under the queue's lock rather than taken from the clock, so two
#   producers in the same second still come out in the order they arrived — a
#   second-resolution timestamp could not tell them apart, and `date` has no
#   portable sub-second field. A job pushed with `--priority` is claimed ahead
#   of every waiting job of a lower priority, and one pushed with `--delay` or
#   `--at` waits in `pending` without being claimed until it falls due.
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
# @description Move or remove the sidecars that travel with a job: its retry
#   count, its priority and the time it falls due.
# @arg $1 string Queue directory
# @arg $2 string Job id
# @arg $3 string Source state
# @arg $4 string Destination state, or empty to remove the sidecars
# @internal
#######################################
function __dybatpho_queue_sidecars {
  local suffix source
  for suffix in retries priority due; do
    source="$1/$3/$2.${suffix}"
    dybatpho::is file "${source}" || continue
    if [[ -n "${4-}" ]]; then
      mv -- "${source}" "$1/$4/$2.${suffix}"
    else
      rm -f -- "${source}"
    fi
  done
}

#######################################
# @description Read a number from a job's sidecar, into a named variable.
#   A missing or damaged sidecar reads as the fallback, so a job written by an
#   older copy of the module, which kept no such file, behaves as it did then.
# @arg $1 string Name of the variable receiving the number
# @arg $2 string Sidecar path
# @arg $3 number Value when the sidecar is missing or not a number
# @set The named variable
# @internal
#######################################
function __dybatpho_queue_sidecar_number_into {
  local -n __dybatpho_queue_number_ref="$1"
  local __dybatpho_queue_number_value="$3"
  if dybatpho::is file "$2"; then
    read -r __dybatpho_queue_number_value < "$2" || true
    [[ "${__dybatpho_queue_number_value}" =~ ^-?[0-9]+$ ]] \
      || __dybatpho_queue_number_value="$3"
  fi
  __dybatpho_queue_number_ref="${__dybatpho_queue_number_value}"
}

#######################################
# @description Choose the job a claim takes next, into a named variable: the
#   highest priority among the jobs that are due, and the oldest of those.
# @arg $1 string Name of the variable receiving the job id
# @arg $2 string Queue directory
# @set The named variable, empty when no job is due
# @exitcode 0 A job is due
# @exitcode 1 Nothing is waiting, or nothing waiting is due yet
# @internal
#######################################
function __dybatpho_queue_next_into {
  local -n __dybatpho_queue_next_ref="$1"
  local __dybatpho_queue_directory="$2"
  __dybatpho_queue_next_ref=""

  local __dybatpho_queue_now __dybatpho_queue_best="" __dybatpho_queue_best_priority=0
  local __dybatpho_queue_id __dybatpho_queue_priority __dybatpho_queue_due
  __dybatpho_queue_now="$(dybatpho::date_now "%s")"
  # The listing is oldest first, so a later job only replaces the choice when
  # it outranks it; within one priority the first one seen, the oldest, stays.
  while IFS= read -r __dybatpho_queue_id; do
    [[ -n "${__dybatpho_queue_id}" ]] || continue
    __dybatpho_queue_sidecar_number_into __dybatpho_queue_due \
      "${__dybatpho_queue_directory}/pending/${__dybatpho_queue_id}.due" 0
    ((__dybatpho_queue_due <= __dybatpho_queue_now)) || continue
    __dybatpho_queue_sidecar_number_into __dybatpho_queue_priority \
      "${__dybatpho_queue_directory}/pending/${__dybatpho_queue_id}.priority" 0
    if [[ -z "${__dybatpho_queue_best}" ]] || ((__dybatpho_queue_priority > __dybatpho_queue_best_priority)); then
      __dybatpho_queue_best="${__dybatpho_queue_id}"
      __dybatpho_queue_best_priority="${__dybatpho_queue_priority}"
    fi
  # kcov never marks a loop's redirected `done` as run; every claim test runs it.
  done < <(__dybatpho_queue_ids "${__dybatpho_queue_directory}" pending) # kcov(skip)

  [[ -n "${__dybatpho_queue_best}" ]] || return 1
  __dybatpho_queue_next_ref="${__dybatpho_queue_best}"
}

#######################################
# @description Read the scheduling options `dybatpho::queue_push` and
#   `dybatpho::queue_requeue` accept, into named variables.
# @arg $1 string Name of the variable receiving the priority, or empty when the option is not accepted
# @arg $2 string Name of the variable receiving the epoch the job falls due, empty when it is due now
# @arg $3 string Name of the variable receiving how many arguments were options
# @arg $@ string The caller's arguments
# @set The named variables
# @exitcode 0 The options were read
# @exitcode 1 Stop the script on an unknown option or an invalid value
# @internal
#######################################
function __dybatpho_queue_options_into {
  local __dybatpho_queue_priority_name="$1"
  local -n __dybatpho_queue_due_ref="$2"
  local -n __dybatpho_queue_used_ref="$3"
  shift 3
  local __dybatpho_queue_caller="${FUNCNAME[1]}"

  local __dybatpho_queue_option __dybatpho_queue_value queue_delay_seconds
  local __dybatpho_queue_when="" __dybatpho_queue_count=0
  while (($# > 0)); do
    __dybatpho_queue_option="$1"
    case "${__dybatpho_queue_option}" in
      --)
        __dybatpho_queue_count=$((__dybatpho_queue_count + 1))
        break
        ;;
      --priority | --delay | --at)
        (($# >= 2)) \
          || dybatpho::die "${__dybatpho_queue_caller}: ${__dybatpho_queue_option} needs a value"
        __dybatpho_queue_value="$2"
        shift 2
        __dybatpho_queue_count=$((__dybatpho_queue_count + 2))
        ;;
      --priority=* | --delay=* | --at=*)
        __dybatpho_queue_value="${__dybatpho_queue_option#*=}"
        __dybatpho_queue_option="${__dybatpho_queue_option%%=*}"
        shift
        __dybatpho_queue_count=$((__dybatpho_queue_count + 1))
        ;;
      # Tested under `run` ("refuses an invalid scheduling option"): it exits.
      --?*) dybatpho::die "${__dybatpho_queue_caller}: Unknown option: ${__dybatpho_queue_option}" ;; # kcov(skip)
      *) break ;;
    esac

    if [[ "${__dybatpho_queue_option}" == "--priority" ]]; then
      [[ -n "${__dybatpho_queue_priority_name}" ]] \
        || dybatpho::die "${__dybatpho_queue_caller}: Unknown option: --priority"
      # Nine digits keep every comparison well inside Bash's integers.
      [[ "${__dybatpho_queue_value}" =~ ^-?[0-9]{1,9}$ ]] \
        || dybatpho::die "${__dybatpho_queue_caller}: Not a whole-number priority: ${__dybatpho_queue_value}"
      local -n __dybatpho_queue_priority_ref="${__dybatpho_queue_priority_name}"
      # Forced to base ten, so a leading zero is not read as octal.
      if [[ "${__dybatpho_queue_value}" == -* ]]; then
        __dybatpho_queue_priority_ref=$((-10#${__dybatpho_queue_value#-}))
      else
        __dybatpho_queue_priority_ref=$((10#${__dybatpho_queue_value}))
      fi
      continue
    fi

    # `--delay` and `--at` both name the moment the job falls due.
    [[ -z "${__dybatpho_queue_when}" ]] \
      || dybatpho::die "${__dybatpho_queue_caller}: Use either --delay or --at, not both"
    if [[ "${__dybatpho_queue_option}" == "--delay" ]]; then
      dybatpho::date_parse_duration queue_delay_seconds "${__dybatpho_queue_value}" \
        || dybatpho::die "${__dybatpho_queue_caller}: Not a duration: ${__dybatpho_queue_value}"
      ((queue_delay_seconds >= 0)) \
        || dybatpho::die "${__dybatpho_queue_caller}: The delay cannot be negative, got: ${__dybatpho_queue_value}"
      __dybatpho_queue_when=$(($(dybatpho::date_now "%s") + queue_delay_seconds))
    else
      [[ "${__dybatpho_queue_value}" =~ ^[0-9]{1,15}$ ]] \
        || dybatpho::die "${__dybatpho_queue_caller}: --at takes a Unix timestamp, got: ${__dybatpho_queue_value}"
      __dybatpho_queue_when=$((10#${__dybatpho_queue_value}))
    fi
  done

  __dybatpho_queue_due_ref="${__dybatpho_queue_when}"
  __dybatpho_queue_used_ref="${__dybatpho_queue_count}"
}

#######################################
# @description Add a job to a queue.
#   The payload is written to a temporary file and renamed into `pending`, so
#   a worker never sees a job whose payload is still being written.
#
#   `--priority` puts the job ahead of every waiting job of a lower priority;
#   jobs of one priority still leave in the order they arrived. `--delay` and
#   `--at` keep the job in `pending`, counted and listed but not claimed, until
#   the moment they name.
# @option --priority <n> Whole number, higher is claimed first, default is `0`
# @option --delay <duration> Wait this long before the job can be claimed, such as `90s`, `5m` or `PT1H`
# @option --at <epoch> Unix timestamp before which the job cannot be claimed
# @arg $1 string Queue name or path
# @arg $2 string Payload text, or `-` to read it from stdin
# @stdout The new job's id
# @exitcode 0 The job was added
# @exitcode 1 The queue lock could not be taken; stop the script on an invalid option
# @example
#   id="$(dybatpho::queue_push deploys "restart api")"
#   dybatpho::queue_push --priority 10 deploys "rollback api"
#   dybatpho::queue_push --delay 15m deploys "warm caches"
#######################################
function dybatpho::queue_push {
  local priority=0 due="" used=0
  __dybatpho_queue_options_into priority due used "$@"
  shift "${used}"

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
  # The sidecars go first: the job file appearing is what makes a job visible
  # to a claim, so it must not be seen before its priority and due time are.
  ((priority == 0)) || printf '%s\n' "${priority}" > "${directory}/pending/${identifier}.priority"
  [[ -z "${due}" ]] || printf '%s\n' "${due}" > "${directory}/pending/${identifier}.due"
  printf '%s\n' "${text}" > "${directory}/pending/${identifier}.job"

  dybatpho::lock_release "${lock}"
  printf '%s\n' "${identifier}"
}

#######################################
# @description Claim the next job in a queue: the oldest of the highest
#   priority among the jobs that are due.
#   The job moves from `pending` to `claimed` and stays there until the caller
#   completes, requeues, or dead-letters it, so a worker that dies leaves its
#   job where it can be found rather than losing it.
# @arg $1 string Queue name or path
# @arg $2 string Name of the variable receiving the job id
# @arg $3 string Name of the variable receiving the payload
# @set Both named variables
# @exitcode 0 A job was claimed
# @exitcode 1 No job is due, or the queue lock could not be taken
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
  # Every local carries the library's prefix: the namerefs below bind to names
  # the caller chooses, and one that matched a plain local here would resolve
  # to that local and leave the caller's variable untouched.
  local __dybatpho_queue_name __dybatpho_queue_id_target __dybatpho_queue_payload_target
  dybatpho::expect_args __dybatpho_queue_name __dybatpho_queue_id_target __dybatpho_queue_payload_target -- "$@"
  dybatpho::expect_ref "${__dybatpho_queue_id_target}"
  dybatpho::expect_ref "${__dybatpho_queue_payload_target}"

  local __dybatpho_queue_directory
  __dybatpho_queue_dir_into __dybatpho_queue_directory "${__dybatpho_queue_name}"
  __dybatpho_queue_prepare "${__dybatpho_queue_directory}"

  local __dybatpho_queue_lock_path
  __dybatpho_queue_lock_path="$(__dybatpho_queue_lock "${__dybatpho_queue_directory}")"
  dybatpho::lock_acquire "${__dybatpho_queue_lock_path}" "${DYBATPHO_QUEUE_TIMEOUT}" || return 1

  # Choosing and moving the job happen under one lock. Apart, two workers
  # would both read the same oldest job and both go on to run it.
  local __dybatpho_queue_identifier
  if ! __dybatpho_queue_next_into __dybatpho_queue_identifier "${__dybatpho_queue_directory}"; then
    dybatpho::lock_release "${__dybatpho_queue_lock_path}"
    return 1
  fi

  mv -- "${__dybatpho_queue_directory}/pending/${__dybatpho_queue_identifier}.job" \
    "${__dybatpho_queue_directory}/claimed/${__dybatpho_queue_identifier}.job"
  # The retry count travels with the job. Left behind in `pending`, it would
  # not be found on the next requeue, the count would restart at one, and a
  # job that always fails would circulate forever instead of dead-lettering.
  # The priority goes with it for the same reason: a requeue keeps it.
  __dybatpho_queue_sidecars "${__dybatpho_queue_directory}" "${__dybatpho_queue_identifier}" pending claimed
  dybatpho::lock_release "${__dybatpho_queue_lock_path}"

  local -n __dybatpho_queue_id_ref="${__dybatpho_queue_id_target}"
  local -n __dybatpho_queue_payload_ref="${__dybatpho_queue_payload_target}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  __dybatpho_queue_id_ref="${__dybatpho_queue_identifier}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  __dybatpho_queue_payload_ref="$(< "${__dybatpho_queue_directory}/claimed/${__dybatpho_queue_identifier}.job")"
}

#######################################
# @description Read the job a claim would take next, without claiming it.
# @arg $1 string Queue name or path
# @arg $2 string Optional name of a variable receiving the job id
# @set The named variable, when one is given
# @stdout The payload of the next job
# @exitcode 0 A job was read
# @exitcode 1 No job is due
# @example
#   dybatpho::queue_peek deploys
#######################################
function dybatpho::queue_peek {
  local __dybatpho_queue_name
  dybatpho::expect_args __dybatpho_queue_name -- "$@"
  local __dybatpho_queue_id_target="${2-}"
  [[ -z "${__dybatpho_queue_id_target}" ]] || dybatpho::expect_ref "${__dybatpho_queue_id_target}"

  local __dybatpho_queue_directory
  __dybatpho_queue_dir_into __dybatpho_queue_directory "${__dybatpho_queue_name}"
  dybatpho::is dir "${__dybatpho_queue_directory}/pending" || return 1

  local __dybatpho_queue_identifier
  __dybatpho_queue_next_into __dybatpho_queue_identifier "${__dybatpho_queue_directory}" || return 1

  if [[ -n "${__dybatpho_queue_id_target}" ]]; then
    local -n __dybatpho_queue_peek_ref="${__dybatpho_queue_id_target}"
    # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
    __dybatpho_queue_peek_ref="${__dybatpho_queue_identifier}"
  fi
  printf '%s\n' "$(< "${__dybatpho_queue_directory}/pending/${__dybatpho_queue_identifier}.job")"
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
  # The first arm has no command to fire on, so kcov never marks it covered.
  case "$1" in
    pending | claimed | dead) ;;                                                               # kcov(skip)
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

  rm -f -- "${job}"
  __dybatpho_queue_sidecars "${directory}" "${identifier}" claimed
}

#######################################
# @description Put a claimed job back at the end of the queue.
#   Each requeue counts, and when a job has been requeued as many times as the
#   budget allows it is dead-lettered instead, so a job that always fails stops
#   circulating without being thrown away. The job keeps its priority, and
#   `--delay` or `--at` hold it back before it can be claimed again, which is
#   how a caller backs off from a failure.
# @option --delay <duration> Wait this long before the job can be claimed again
# @option --at <epoch> Unix timestamp before which the job cannot be claimed again
# @arg $1 string Queue name or path
# @arg $2 string Job id
# @arg $3 number Optional retry budget; past it the job is dead-lettered instead
# @stdout The job's new id when it is requeued
# @exitcode 0 The job was requeued, or dead-lettered because its budget ran out
# @exitcode 1 No such job is claimed, or the queue lock could not be taken
# @example
#   dybatpho::queue_requeue deploys "${id}" 3
#   dybatpho::queue_requeue --delay 30s deploys "${id}" 3
#######################################
function dybatpho::queue_requeue {
  local due="" used=0
  __dybatpho_queue_options_into "" due used "$@"
  shift "${used}"

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
  # would put a failing job back at the head of its priority, where it would
  # be retried before everything pushed since.
  local payload fresh priority
  payload="$(< "${job}")"
  __dybatpho_queue_sidecar_number_into priority "${directory}/claimed/${identifier}.priority" 0
  local -a options=(--priority "${priority}")
  [[ -z "${due}" ]] || options+=(--at "${due}")
  fresh="$(dybatpho::queue_push "${options[@]}" -- "${queue}" "${payload}")" || return 1
  printf '%s\n' "${attempts}" > "${directory}/pending/${fresh}.retries"
  rm -f -- "${job}"
  __dybatpho_queue_sidecars "${directory}" "${identifier}" claimed
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
  __dybatpho_queue_sidecars "${directory}" "${identifier}" claimed dead
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
  local __dybatpho_queue_name __dybatpho_queue_identifier __dybatpho_queue_target
  dybatpho::expect_args __dybatpho_queue_name __dybatpho_queue_identifier __dybatpho_queue_target -- "$@"
  __dybatpho_queue_expect_id "${__dybatpho_queue_identifier}"
  dybatpho::expect_ref "${__dybatpho_queue_target}"
  local __dybatpho_queue_wanted="${4-}"
  [[ -z "${__dybatpho_queue_wanted}" ]] || __dybatpho_queue_expect_state "${__dybatpho_queue_wanted}"

  local __dybatpho_queue_directory
  __dybatpho_queue_dir_into __dybatpho_queue_directory "${__dybatpho_queue_name}"

  local -a __dybatpho_queue_states=(pending claimed dead)
  [[ -z "${__dybatpho_queue_wanted}" ]] || __dybatpho_queue_states=("${__dybatpho_queue_wanted}")

  local -n __dybatpho_queue_read_ref="${__dybatpho_queue_target}"
  local __dybatpho_queue_state __dybatpho_queue_file
  for __dybatpho_queue_state in "${__dybatpho_queue_states[@]}"; do
    __dybatpho_queue_file="${__dybatpho_queue_directory}/${__dybatpho_queue_state}/${__dybatpho_queue_identifier}.job"
    if dybatpho::is file "${__dybatpho_queue_file}"; then
      # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
      __dybatpho_queue_read_ref="$(< "${__dybatpho_queue_file}")"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Read the options `dybatpho::queue_work` accepts, into an
#   associative array whose keys are the option names without their dashes,
#   plus `used`, the number of arguments that were options.
# @arg $1 string Name of the associative array receiving the settings
# @arg $@ string The caller's arguments
# @set The named array
# @exitcode 0 The options were read
# @exitcode 1 Stop the script on an unknown option or an invalid value
# @internal
#######################################
function __dybatpho_queue_work_options {
  local -n __dybatpho_queue_work_ref="$1"
  shift

  local option value work_seconds used=0
  while (($# > 0)); do
    option="$1"
    case "${option}" in
      --)
        used=$((used + 1))
        break
        ;;
      --retries | --backoff | --max-backoff | --max-jobs | --poll | --idle)
        (($# >= 2)) || dybatpho::die "dybatpho::queue_work: ${option} needs a value"
        value="$2"
        shift 2
        used=$((used + 2))
        ;;
      --retries=* | --backoff=* | --max-backoff=* | --max-jobs=* | --poll=* | --idle=*)
        value="${option#*=}"
        option="${option%%=*}"
        shift
        used=$((used + 1))
        ;;
      # Tested under `run` ("queue_work refuses an invalid option"): it exits.
      --?*) dybatpho::die "dybatpho::queue_work: Unknown option: ${option}" ;; # kcov(skip)
      *) break ;;
    esac

    if [[ "${option}" == "--retries" || "${option}" == "--max-jobs" ]]; then
      [[ "${value}" =~ ^[0-9]{1,9}$ ]] \
        || dybatpho::die "dybatpho::queue_work: ${option} takes a whole number, got: ${value}"
      __dybatpho_queue_work_ref["${option#--}"]=$((10#${value}))
      continue
    fi

    dybatpho::date_parse_duration work_seconds "${value}" \
      || dybatpho::die "dybatpho::queue_work: ${option} takes a duration, got: ${value}"
    ((work_seconds >= 0)) || dybatpho::die "dybatpho::queue_work: ${option} cannot be negative, got: ${value}"
    if [[ "${option}" == "--poll" ]]; then
      ((work_seconds > 0)) || dybatpho::die "dybatpho::queue_work: --poll must be at least one second"
    fi
    __dybatpho_queue_work_ref["${option#--}"]="${work_seconds}"
  done
  __dybatpho_queue_work_ref[used]="${used}"
}

#######################################
# @description Run a worker over a queue: claim each job that is due, hand its
#   payload to a handler, and settle the job by how the handler exited.
#
#   A handler that succeeds completes its job. One that fails has the job
#   requeued, held back by a backoff that doubles with every attempt, until
#   the retry budget is spent and the job is filed under dead letters instead.
#   The handler runs in a subshell, so one that calls `exit` or
#   `dybatpho::die` fails its own job rather than ending the worker.
#
#   Without `--poll` the worker returns as soon as no job is due, which drains
#   a queue and stops. With it, the worker sleeps that long whenever nothing is
#   due and looks again, for as long as `--idle` allows or, without it, until
#   `--max-jobs` is reached. Several workers may run over one queue at once:
#   each claim is made under the queue's lock.
#
#   A worker killed in the middle of a job leaves that job in `claimed`, where
#   `dybatpho::queue_list` shows it and `dybatpho::queue_requeue` puts it back.
# @option --retries <n> Requeues a failing job gets before it is dead-lettered, default is `3`
# @option --backoff <duration> Delay before the first retry, doubled for each one after, default is `0`
# @option --max-backoff <duration> Longest a retry is held back, default is `1h`
# @option --max-jobs <n> Return after handling this many jobs, `0` for no limit, default is `0`
# @option --poll <duration> Wait this long and look again when no job is due, instead of returning
# @option --idle <duration> With `--poll`, return after going this long without a job
# @arg $1 string Queue name or path
# @arg $2 string Handler command, a function or a program
# @arg $@ string Arguments passed to the handler before the payload
# @env DYBATPHO_QUEUE_JOB_ID string Set for the handler to the id of the job it is handling
# @stderr A warning for each job that is dead-lettered
# @exitcode 0 The worker stopped: nothing was due, the idle time ran out, or the job limit was reached
# @exitcode 1 Stop the script on an invalid option or a missing handler
# @example
#   handle_deploy() { ./deploy.sh "$1"; }
#   dybatpho::queue_work --retries 5 --backoff 10s deploys handle_deploy
#
# @example
#   # A long-running worker that gives up after ten quiet minutes.
#   dybatpho::queue_work --poll 5s --idle 10m deploys ./handle.sh --verbose
#######################################
function dybatpho::queue_work {
  local -A settings=([retries]=3 [backoff]=0 [max-backoff]=3600 [max-jobs]=0 [poll]="" [idle]="")
  __dybatpho_queue_work_options settings "$@"
  shift "${settings[used]}"
  local retries="${settings[retries]}" backoff="${settings[backoff]}"
  local max_backoff="${settings[max-backoff]}" max_jobs="${settings[max-jobs]}"
  local poll="${settings[poll]}" idle="${settings[idle]}"

  local queue handler
  dybatpho::expect_args queue handler -- "$@"
  shift 2
  dybatpho::command_exists_all "${handler}" \
    || dybatpho::die "${FUNCNAME[0]}: Handler not found: ${handler}"

  local directory
  __dybatpho_queue_dir_into directory "${queue}"

  local handled=0 waited=0 id payload attempts delay outcome
  while ((max_jobs == 0 || handled < max_jobs)); do
    if ! dybatpho::queue_pop "${queue}" id payload; then
      [[ -n "${poll}" ]] || return 0
      # Idle time is counted in polls rather than read from the clock, so a
      # frozen or jumping clock cannot keep a worker alive or end it early.
      if [[ -n "${idle}" ]] && ((waited >= idle)); then
        return 0
      fi
      sleep "${poll}"
      waited=$((waited + poll))
      continue
    fi
    waited=0
    handled=$((handled + 1))

    if (DYBATPHO_QUEUE_JOB_ID="${id}" "${handler}" "$@" "${payload}"); then
      dybatpho::queue_complete "${queue}" "${id}"
      continue
    fi

    __dybatpho_queue_sidecar_number_into attempts "${directory}/claimed/${id}.retries" 0
    delay=0
    if ((backoff > 0)); then
      # Doubling stops at the cap rather than after it, so a long retry run
      # never overflows the multiplication.
      delay="${backoff}"
      while ((attempts > 0 && delay < max_backoff)); do
        delay=$((delay * 2))
        attempts=$((attempts - 1))
      done
      ((delay <= max_backoff)) || delay="${max_backoff}"
    fi

    local -a requeue=(dybatpho::queue_requeue)
    ((delay == 0)) || requeue+=(--delay "${delay}")
    outcome="$("${requeue[@]}" -- "${queue}" "${id}" "${retries}")"
    [[ -n "${outcome}" ]] \
      || dybatpho::warn "Job ${id} in ${queue} failed $((retries + 1)) times; moved to dead letters"
  done
}
