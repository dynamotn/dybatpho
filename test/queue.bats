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

@test "an empty queue name is refused" {
  run --separate-stderr dybatpho::queue_push "" "a job"
  assert_failure
  assert_stderr --partial "Expected a queue name"
}
