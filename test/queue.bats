setup() {
  load test_helper
  QUEUE="${BATS_TEST_TMPDIR}/work"
  # A short wait keeps a test that deliberately holds the lock quick.
  export DYBATPHO_QUEUE_TIMEOUT=2
}

@test "dybatpho::queue_push stores a job and returns its id" {
  run_traced dybatpho::queue_push "${QUEUE}" "first job"
  assert_success
  assert_output --regexp '^[0-9]{12}-[0-9]+$'
  assert_file_exist "${QUEUE}/pending/${output}.job"
}

@test "dybatpho::queue_push hands out ids in the order the jobs arrive" {
  # Strict FIFO is the point of taking the sequence under the lock: a
  # second-resolution clock cannot order two pushes in the same second.
  local first second third
  first="$(dybatpho::queue_push "${QUEUE}" one)"
  second="$(dybatpho::queue_push "${QUEUE}" two)"
  third="$(dybatpho::queue_push "${QUEUE}" three)"

  assert_equal "${first%%-*}" "000000000001"
  assert_equal "${second%%-*}" "000000000002"
  assert_equal "${third%%-*}" "000000000003"
}

@test "dybatpho::queue_push reads a payload from stdin and keeps its line breaks" {
  local id payload
  id="$(printf 'line one\nline two' | dybatpho::queue_push "${QUEUE}" -)"

  dybatpho::queue_read "${QUEUE}" "${id}" payload
  assert_equal "${payload}" "$(printf 'line one\nline two')"
}

@test "dybatpho::queue_pop claims the oldest job, oldest first" {
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_push "${QUEUE}" two > /dev/null

  local id payload
  run_traced dybatpho::queue_pop "${QUEUE}" id payload
  assert_success

  dybatpho::queue_pop "${QUEUE}" id payload
  assert_equal "${payload}" "two"
}

@test "dybatpho::queue_pop moves the job to claimed rather than deleting it" {
  # A worker that dies must leave its job somewhere it can be found, which is
  # what separates this from reading and removing in one step.
  local id payload
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload

  assert_file_not_exist "${QUEUE}/pending/${id}.job"
  assert_file_exist "${QUEUE}/claimed/${id}.job"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" claimed)" "1"
}

@test "dybatpho::queue_pop reports an empty queue" {
  local id payload
  run_traced -1 dybatpho::queue_pop "${QUEUE}" id payload
}

@test "dybatpho::queue_pop refuses a variable name that belongs to the library" {
  run --separate-stderr dybatpho::queue_pop "${QUEUE}" __dybatpho_id payload
  assert_failure
  assert_stderr --partial "is reserved"
}

@test "dybatpho::queue_pop, queue_peek and queue_read fill caller variables named like their locals" {
  # A nameref bound to a name the function also declares as a local resolves
  # to that local, and the caller's variable is silently left alone.
  dybatpho::queue_push "${QUEUE}" "first" > /dev/null
  dybatpho::queue_push "${QUEUE}" "second" > /dev/null

  local identifier="" lock=""
  dybatpho::queue_peek "${QUEUE}" identifier > /dev/null
  assert_equal "${identifier%%-*}" "000000000001"

  dybatpho::queue_pop "${QUEUE}" identifier lock
  assert_equal "${identifier%%-*}" "000000000001"
  assert_equal "${lock}" "first"

  local directory="" state=""
  dybatpho::queue_pop "${QUEUE}" directory state
  assert_equal "${state}" "second"
  local target=""
  dybatpho::queue_read "${QUEUE}" "${directory}" target
  assert_equal "${target}" "second"
  dybatpho::queue_read "${QUEUE}" "${directory}" state claimed
  assert_equal "${state}" "second"
}

@test "concurrent workers never claim the same job twice" {
  # This is the whole reason the module exists: a directory-of-files queue
  # without a lock lets two workers read the same oldest job and both run it.
  local worker="${BATS_TEST_TMPDIR}/worker.sh"
  cat > "${worker}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules queue
while dybatpho::queue_pop "\$1" id payload; do
  printf '%s\n' "\${payload}" >> "\$2"
  dybatpho::queue_complete "\$1" "\${id}"
done
SCRIPT

  local at
  for at in $(seq 1 40); do
    dybatpho::queue_push "${QUEUE}" "job-${at}" > /dev/null
  done

  for at in 1 2 3 4; do
    bash "${worker}" "${QUEUE}" "${BATS_TEST_TMPDIR}/done-${at}.txt" &
  done
  wait

  local handled unique
  handled="$(cat "${BATS_TEST_TMPDIR}"/done-*.txt | wc -l)"
  unique="$(sort -u "${BATS_TEST_TMPDIR}"/done-*.txt | wc -l)"
  assert_equal "${handled// /}" "40"
  assert_equal "${unique// /}" "40"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" claimed)" "0"
}

@test "dybatpho::queue_peek reads the oldest job without claiming it" {
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_push "${QUEUE}" two > /dev/null

  run_traced dybatpho::queue_peek "${QUEUE}"
  assert_success
  assert_output "one"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "2"
}

@test "dybatpho::queue_peek reports the id it read and an empty queue" {
  local id
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_peek "${QUEUE}" id > /dev/null
  assert_file_exist "${QUEUE}/pending/${id}.job"

  run_traced -1 dybatpho::queue_peek "${BATS_TEST_TMPDIR}/absent"
  assert_output ""
}

@test "dybatpho::queue_len counts each state and an absent queue" {
  run_traced dybatpho::queue_len "${BATS_TEST_TMPDIR}/absent"
  assert_success
  assert_output "0"

  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_push "${QUEUE}" two > /dev/null
  local id payload
  dybatpho::queue_pop "${QUEUE}" id payload
  dybatpho::queue_dead_letter "${QUEUE}" "${id}"

  assert_equal "$(dybatpho::queue_len "${QUEUE}" pending)" "1"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" claimed)" "0"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" dead)" "1"
}

@test "dybatpho::queue_len and queue_list reject a state the queue does not keep" {
  run --separate-stderr dybatpho::queue_len "${QUEUE}" running
  assert_failure
  assert_stderr --partial "Not a queue state: running"

  run --separate-stderr dybatpho::queue_list "${QUEUE}" running
  assert_failure
  assert_stderr --partial "Not a queue state: running"
}

@test "dybatpho::queue_list prints ids oldest first and nothing for an absent queue" {
  local first second
  first="$(dybatpho::queue_push "${QUEUE}" one)"
  second="$(dybatpho::queue_push "${QUEUE}" two)"

  run_traced dybatpho::queue_list "${QUEUE}"
  assert_success
  assert_line --index 0 "${first}"
  assert_line --index 1 "${second}"

  run_traced dybatpho::queue_list "${BATS_TEST_TMPDIR}/absent"
  assert_success
  assert_output ""
}

@test "dybatpho::queue_complete removes a claimed job" {
  local id payload
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload

  run_traced dybatpho::queue_complete "${QUEUE}" "${id}"
  assert_success
  assert_file_not_exist "${QUEUE}/claimed/${id}.job"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" claimed)" "0"
}

@test "dybatpho::queue_complete reports a job that is not claimed" {
  run --separate-stderr dybatpho::queue_complete "${QUEUE}" "000000000099-1700000000"
  assert_failure
  assert_stderr --partial "No claimed job with id"
}

@test "dybatpho::queue_requeue puts a job back at the end of the queue" {
  # Keeping the old id would put a failing job back at the head, where it
  # would be retried ahead of everything pushed since.
  local first second id payload requeued
  first="$(dybatpho::queue_push "${QUEUE}" one)"
  second="$(dybatpho::queue_push "${QUEUE}" two)"
  dybatpho::queue_pop "${QUEUE}" id payload
  assert_equal "${id}" "${first}"

  requeued="$(dybatpho::queue_requeue "${QUEUE}" "${id}")"
  run_traced dybatpho::queue_list "${QUEUE}"
  assert_line --index 0 "${second}"
  assert_line --index 1 "${requeued}"
}

@test "dybatpho::queue_requeue dead-letters a job once its budget runs out" {
  local id payload out
  dybatpho::queue_push "${QUEUE}" "always fails" > /dev/null

  local attempt
  for attempt in 1 2; do
    dybatpho::queue_pop "${QUEUE}" id payload
    out="$(dybatpho::queue_requeue "${QUEUE}" "${id}" 2)"
    [ -n "${out}" ]
  done

  dybatpho::queue_pop "${QUEUE}" id payload
  run_traced dybatpho::queue_requeue "${QUEUE}" "${id}" 2
  assert_success
  assert_output ""

  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" dead)" "1"
}

@test "dybatpho::queue_requeue keeps the retry count when a worker claims the job at once" {
  # A requeued job becomes claimable the moment its job file appears. A count
  # written after that is left behind in `pending` when a worker is quick, the
  # next requeue starts again from one, and the job never dead-letters. The
  # stub replays the quick worker: it claims the job as soon as the push that
  # made it visible returns.
  local id payload
  dybatpho::queue_push "${QUEUE}" "always fails" > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload

  eval "__dybatpho_test_real_push() $(declare -f dybatpho::queue_push | tail -n +2)"
  dybatpho::queue_push() {
    local fresh
    fresh="$(__dybatpho_test_real_push "$@")" || return 1
    local quick_id quick_payload
    dybatpho::queue_pop "${QUEUE}" quick_id quick_payload
    printf '%s\n' "${fresh}"
  }

  local requeued
  requeued="$(dybatpho::queue_requeue "${QUEUE}" "${id}" 5)"
  unset -f dybatpho::queue_push
  eval "dybatpho::queue_push() $(declare -f __dybatpho_test_real_push | tail -n +2)"

  # Whether the stub ran (old protocol) or not (new one), claim the job now if
  # it is still waiting, then look at the count it carries.
  if [[ -e "${QUEUE}/pending/${requeued}.job" ]]; then
    dybatpho::queue_pop "${QUEUE}" id payload
  fi
  assert_file_exist "${QUEUE}/claimed/${requeued}.retries"
  assert_equal "$(< "${QUEUE}/claimed/${requeued}.retries")" "1"
  run_traced find "${QUEUE}/pending" -name '*.retries'
  assert_output ""
}

@test "dybatpho::queue_requeue carries the retry count through a claim" {
  # The count lives beside the job; left behind in pending when the job was
  # claimed, it would restart at one and the budget would never run out.
  local id payload requeued
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload
  requeued="$(dybatpho::queue_requeue "${QUEUE}" "${id}")"
  assert_file_exist "${QUEUE}/pending/${requeued}.retries"

  dybatpho::queue_pop "${QUEUE}" id payload
  assert_file_exist "${QUEUE}/claimed/${id}.retries"
  assert_equal "$(< "${QUEUE}/claimed/${id}.retries")" "1"
}

@test "dybatpho::queue_requeue rejects a budget that is not a number" {
  local id payload
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload

  run --separate-stderr dybatpho::queue_requeue "${QUEUE}" "${id}" many
  assert_failure
  assert_stderr --partial "retry budget must be a number"
}

@test "dybatpho::queue_dead_letter keeps the job instead of dropping it" {
  local id payload recovered
  dybatpho::queue_push "${QUEUE}" "poison" > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload

  run_traced dybatpho::queue_dead_letter "${QUEUE}" "${id}"
  assert_success
  assert_file_exist "${QUEUE}/dead/${id}.job"

  dybatpho::queue_read "${QUEUE}" "${id}" recovered dead
  assert_equal "${recovered}" "poison"
}

@test "dybatpho::queue_dead_letter reports a job that is not claimed" {
  run --separate-stderr dybatpho::queue_dead_letter "${QUEUE}" "000000000099-1700000000"
  assert_failure
  assert_stderr --partial "No claimed job with id"
}

@test "dybatpho::queue_read finds a job in any state and reports an unknown id" {
  local id payload found
  dybatpho::queue_push "${QUEUE}" "waiting" > /dev/null
  dybatpho::queue_read "${QUEUE}" "$(dybatpho::queue_list "${QUEUE}")" found
  assert_equal "${found}" "waiting"

  dybatpho::queue_pop "${QUEUE}" id payload
  dybatpho::queue_read "${QUEUE}" "${id}" found
  assert_equal "${found}" "waiting"

  run_traced -1 dybatpho::queue_read "${QUEUE}" "000000000099-1700000000" found
}

@test "a job id that would escape the queue directory is refused" {
  # An id reaches the filesystem as a path component, so one carrying a slash
  # or `..` would name a file outside the queue.
  run --separate-stderr dybatpho::queue_complete "${QUEUE}" "../../etc/passwd"
  assert_failure
  assert_stderr --partial "Not a job id"

  run --separate-stderr dybatpho::queue_dead_letter "${QUEUE}" "000000000001-1/../x"
  assert_failure
  assert_stderr --partial "Not a job id"
}

@test "a bare queue name resolves under DYBATPHO_QUEUE_DIR" {
  local base="${BATS_TEST_TMPDIR}/queues"
  DYBATPHO_QUEUE_DIR="${base}" dybatpho::queue_push deploys "a job" > /dev/null
  assert_dir_exist "${base}/deploys/pending"
  assert_equal "$(DYBATPHO_QUEUE_DIR="${base}" dybatpho::queue_len deploys)" "1"
}

@test "a bare queue name falls back to the XDG state directory" {
  # This is where a caller's queues land when they configure nothing, so the
  # fallback is worth pinning. `XDG_STATE_HOME` keeps the test out of the
  # real one.
  DYBATPHO_QUEUE_DIR="" XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state" \
    run_traced dybatpho::queue_push deploys "a job"
  assert_success
  assert_dir_exist "${BATS_TEST_TMPDIR}/state/queues/deploys/pending"
}

@test "an empty queue name is refused" {
  run --separate-stderr dybatpho::queue_push "" "a job"
  assert_failure
  assert_stderr --partial "Expected a queue name"
}

@test "dybatpho::queue_pop claims a higher priority first, oldest first within one" {
  dybatpho::queue_push "${QUEUE}" low > /dev/null
  dybatpho::queue_push --priority 5 "${QUEUE}" urgent-1 > /dev/null
  dybatpho::queue_push --priority=5 "${QUEUE}" urgent-2 > /dev/null
  dybatpho::queue_push --priority -3 "${QUEUE}" background > /dev/null
  dybatpho::queue_push "${QUEUE}" normal > /dev/null

  local id payload
  local -a order=()
  while dybatpho::queue_pop "${QUEUE}" id payload; do
    order+=("${payload}")
    dybatpho::queue_complete "${QUEUE}" "${id}"
  done
  assert_equal "${order[*]}" "urgent-1 urgent-2 low normal background"
}

@test "dybatpho::queue_peek answers the job a claim would take next" {
  dybatpho::queue_push "${QUEUE}" low > /dev/null
  dybatpho::queue_push --priority 1 "${QUEUE}" high > /dev/null

  run_traced dybatpho::queue_peek "${QUEUE}"
  assert_success
  assert_output "high"
}

@test "dybatpho::queue_push --delay holds a job back until it falls due" {
  dybatpho::mock_time 1767225600
  dybatpho::queue_push --delay 5m "${QUEUE}" later > /dev/null
  dybatpho::queue_push "${QUEUE}" now > /dev/null

  local id payload
  dybatpho::queue_pop "${QUEUE}" id payload
  assert_equal "${payload}" "now"
  dybatpho::queue_complete "${QUEUE}" "${id}"

  # Waiting but not due: counted and listed, not claimed or peeked.
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "1"
  run_traced -1 dybatpho::queue_pop "${QUEUE}" id payload
  run_traced -1 dybatpho::queue_peek "${QUEUE}"

  dybatpho::mock_time_advance 300
  run_traced dybatpho::queue_pop "${QUEUE}" id payload
  assert_success
  assert_equal "${payload}" "later"
  dybatpho::unmock_time
}

@test "dybatpho::queue_push --at holds a job back until a timestamp" {
  dybatpho::mock_time 1767225600
  local id payload
  id="$(dybatpho::queue_push --at 1767225660 "${QUEUE}" scheduled)"
  assert_equal "$(< "${QUEUE}/pending/${id}.due")" "1767225660"
  run_traced -1 dybatpho::queue_pop "${QUEUE}" id payload

  dybatpho::mock_time 1767225660
  run_traced dybatpho::queue_pop "${QUEUE}" id payload
  assert_success
  dybatpho::unmock_time
}

@test "dybatpho::queue_push refuses an invalid scheduling option" {
  run --separate-stderr dybatpho::queue_push --priority high "${QUEUE}" job
  assert_failure
  assert_stderr --partial "Not a whole-number priority: high"

  run --separate-stderr dybatpho::queue_push --delay soon "${QUEUE}" job
  assert_failure
  assert_stderr --partial "Not a duration: soon"

  run --separate-stderr dybatpho::queue_push --delay -5m "${QUEUE}" job
  assert_failure
  assert_stderr --partial "delay cannot be negative"

  run --separate-stderr dybatpho::queue_push --at yesterday "${QUEUE}" job
  assert_failure
  assert_stderr --partial "--at takes a Unix timestamp"

  run --separate-stderr dybatpho::queue_push --delay 1m --at 1 "${QUEUE}" job
  assert_failure
  assert_stderr --partial "either --delay or --at"

  run --separate-stderr dybatpho::queue_push --priority
  assert_failure
  assert_stderr --partial "--priority needs a value"

  run --separate-stderr dybatpho::queue_push --urgent "${QUEUE}" job
  assert_failure
  assert_stderr --partial "Unknown option: --urgent"
}

@test "dybatpho::queue_push takes -- before a queue name that looks like an option" {
  run_traced dybatpho::queue_push --priority 2 -- "${QUEUE}" job
  assert_success
  assert_equal "$(< "${QUEUE}/pending/${output}.priority")" "2"
}

@test "dybatpho::queue_requeue keeps a job's priority and backs off with --delay" {
  dybatpho::mock_time 1767225600
  local id payload fresh
  dybatpho::queue_push --priority 7 "${QUEUE}" flaky > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload
  assert_file_exist "${QUEUE}/claimed/${id}.priority"

  run_traced dybatpho::queue_requeue --delay 30s "${QUEUE}" "${id}" 3
  assert_success
  fresh="${output}"
  assert_equal "$(< "${QUEUE}/pending/${fresh}.priority")" "7"
  assert_equal "$(< "${QUEUE}/pending/${fresh}.due")" "1767225630"
  assert_file_not_exist "${QUEUE}/claimed/${id}.priority"
  run_traced -1 dybatpho::queue_pop "${QUEUE}" id payload

  run --separate-stderr dybatpho::queue_requeue --priority 1 "${QUEUE}" "${id}"
  assert_failure
  assert_stderr --partial "Unknown option: --priority"
  dybatpho::unmock_time
}

@test "completing or dead-lettering a job takes its sidecars with it" {
  local id payload
  dybatpho::queue_push --priority 3 "${QUEUE}" done > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload
  dybatpho::queue_complete "${QUEUE}" "${id}"
  assert_file_not_exist "${QUEUE}/claimed/${id}.priority"

  dybatpho::queue_push --priority 3 "${QUEUE}" poison > /dev/null
  dybatpho::queue_pop "${QUEUE}" id payload
  dybatpho::queue_dead_letter "${QUEUE}" "${id}"
  assert_file_exist "${QUEUE}/dead/${id}.priority"
}

@test "a damaged priority or due sidecar reads as the default" {
  local id payload
  id="$(dybatpho::queue_push "${QUEUE}" job)"
  printf 'garbage\n' > "${QUEUE}/pending/${id}.priority"
  printf 'later\n' > "${QUEUE}/pending/${id}.due"
  run_traced dybatpho::queue_pop "${QUEUE}" id payload
  assert_success
}

@test "dybatpho::queue_work drains a queue and completes each job" {
  local log="${BATS_TEST_TMPDIR}/handled.txt"
  record() { printf '%s %s %s\n' "$1" "$2" "${DYBATPHO_QUEUE_JOB_ID%%-*}" >> "${log}"; }
  dybatpho::queue_push "${QUEUE}" one > /dev/null
  dybatpho::queue_push --priority 1 "${QUEUE}" two > /dev/null

  run_traced dybatpho::queue_work "${QUEUE}" record tag
  assert_success
  assert_equal "$(< "${log}")" "$(printf 'tag two 000000000002\ntag one 000000000001')"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" claimed)" "0"
}

@test "dybatpho::queue_work returns at once on an empty queue" {
  noop() { :; }
  run_traced dybatpho::queue_work "${QUEUE}" noop
  assert_success
}

@test "dybatpho::queue_work retries a failing job and dead-letters it past the budget" {
  local count="${BATS_TEST_TMPDIR}/count"
  fail() {
    printf 'x' >> "${count}"
    return 1
  }
  dybatpho::queue_push "${QUEUE}" poison > /dev/null

  run_traced --separate-stderr dybatpho::queue_work --retries 2 "${QUEUE}" fail
  assert_success
  assert_equal "$(< "${count}")" "xxx"
  assert_equal "$(dybatpho::queue_len "${QUEUE}" dead)" "1"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
  [[ "${stderr}" == *"failed 3 times; moved to dead letters"* ]]
}

@test "dybatpho::queue_work isolates a handler that exits" {
  quits() { exit 3; }
  dybatpho::queue_push "${QUEUE}" job > /dev/null

  run_traced --separate-stderr dybatpho::queue_work --retries=0 "${QUEUE}" quits
  assert_success
  assert_equal "$(dybatpho::queue_len "${QUEUE}" dead)" "1"
}

@test "dybatpho::queue_work backs off exponentially up to the cap" {
  dybatpho::mock_time 1767225600
  fail() { return 1; }
  local id payload
  dybatpho::queue_push "${QUEUE}" flaky > /dev/null

  # First failure: held back by the base delay.
  dybatpho::queue_work --backoff 10s --max-backoff 25s --max-jobs 1 "${QUEUE}" fail
  id="$(dybatpho::queue_list "${QUEUE}")"
  assert_equal "$(< "${QUEUE}/pending/${id}.due")" "1767225610"

  # Second: doubled. Third: doubled again, but capped.
  dybatpho::mock_time_advance 10
  dybatpho::queue_work --backoff 10s --max-backoff 25s --max-jobs 1 "${QUEUE}" fail
  id="$(dybatpho::queue_list "${QUEUE}")"
  assert_equal "$(< "${QUEUE}/pending/${id}.due")" "1767225630"

  dybatpho::mock_time_advance 20
  dybatpho::queue_work --backoff 10s --max-backoff 25s --max-jobs 1 "${QUEUE}" fail
  id="$(dybatpho::queue_list "${QUEUE}")"
  assert_equal "$(< "${QUEUE}/pending/${id}.due")" "1767225655"

  # Not due yet, so a draining worker leaves it alone.
  run_traced dybatpho::queue_work "${QUEUE}" fail
  assert_success
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "1"
  dybatpho::unmock_time
}

@test "dybatpho::queue_work stops after --max-jobs" {
  local log="${BATS_TEST_TMPDIR}/handled.txt"
  record() { printf '%s\n' "$1" >> "${log}"; }
  local job
  for job in a b c; do dybatpho::queue_push "${QUEUE}" "${job}" > /dev/null; done

  run_traced dybatpho::queue_work --max-jobs 2 "${QUEUE}" record
  assert_success
  assert_equal "$(< "${log}")" "$(printf 'a\nb')"
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "1"
}

@test "dybatpho::queue_work --poll waits for work and --idle ends the wait" {
  local log="${BATS_TEST_TMPDIR}/handled.txt"
  record() { printf '%s\n' "$1" >> "${log}"; }
  # A producer that arrives after the worker has started looking.
  (
    sleep 1
    dybatpho::queue_push "${QUEUE}" late > /dev/null
  ) &

  run_traced dybatpho::queue_work --poll 1s --idle 2s "${QUEUE}" record
  assert_success
  wait
  assert_equal "$(< "${log}")" "late"
}

@test "dybatpho::queue_work runs a program handler with arguments" {
  local handler="${BATS_TEST_TMPDIR}/handler.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$1" "$2" >> "%s"\n' "${BATS_TEST_TMPDIR}/out" > "${handler}"
  chmod +x "${handler}"
  dybatpho::queue_push "${QUEUE}" "a payload" > /dev/null

  run_traced dybatpho::queue_work "${QUEUE}" "${handler}" --flag
  assert_success
  assert_equal "$(< "${BATS_TEST_TMPDIR}/out")" "--flag|a payload"
}

@test "dybatpho::queue_work refuses an invalid option or a missing handler" {
  run --separate-stderr dybatpho::queue_work --retries many "${QUEUE}" true
  assert_failure
  assert_stderr --partial "--retries takes a whole number, got: many"

  run --separate-stderr dybatpho::queue_work --backoff soon "${QUEUE}" true
  assert_failure
  assert_stderr --partial "--backoff takes a duration, got: soon"

  run --separate-stderr dybatpho::queue_work --idle -5s "${QUEUE}" true
  assert_failure
  assert_stderr --partial "--idle cannot be negative"

  run --separate-stderr dybatpho::queue_work --poll 0 "${QUEUE}" true
  assert_failure
  assert_stderr --partial "--poll must be at least one second"

  run --separate-stderr dybatpho::queue_work --max-jobs
  assert_failure
  assert_stderr --partial "--max-jobs needs a value"

  run --separate-stderr dybatpho::queue_work --forever "${QUEUE}" true
  assert_failure
  assert_stderr --partial "Unknown option: --forever"

  run --separate-stderr dybatpho::queue_work "${QUEUE}" no-such-handler-here
  assert_failure
  assert_stderr --partial "Handler not found: no-such-handler-here"
}

@test "dybatpho::queue_work accepts -- before the queue name" {
  noop() { :; }
  dybatpho::queue_push "${QUEUE}" job > /dev/null
  run_traced dybatpho::queue_work --max-backoff=1m -- "${QUEUE}" noop
  assert_success
  assert_equal "$(dybatpho::queue_len "${QUEUE}")" "0"
}

@test "a queue with no state directory stops in the function that was called" {
  # The state directory was resolved inside a command substitution, so with
  # neither XDG_STATE_HOME nor HOME set the refusal ended only the substitution
  # and the queue was placed under `/queues`, at the root of the filesystem.
  local script="${BATS_TEST_TMPDIR}/no-home.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules queue" \
    "unset HOME XDG_STATE_HOME; DYBATPHO_QUEUE_DIR=" \
    "if ! dybatpho::queue_push jobs payload; then :; fi" \
    "printf 'carried on\n'" > "${script}"

  run --separate-stderr bash "${script}"
  assert_failure
  assert_stderr --partial "dybatpho::queue_push: Neither XDG_STATE_HOME nor HOME is set"
  refute_stderr --partial "/queues"
  refute_output --partial "carried on"
}
