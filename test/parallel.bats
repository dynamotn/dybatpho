setup() {
  load test_helper
  LOG="${BATS_TEST_TMPDIR}/log"
  : > "${LOG}"
}

# Records when a job starts and ends, so a test can tell serial execution from
# overlapping execution without depending on how long anything took.
_traced_job() {
  printf 'start %s\n' "$1" >> "${LOG}"
  sleep 0.2
  printf 'end %s\n' "$1" >> "${LOG}"
}

_echo_job() {
  printf 'out %s\n' "$1"
  printf 'err %s\n' "$1" >&2
}

_failing_job() {
  printf 'ran %s\n' "$1" >> "${LOG}"
  [[ "$1" == bad* ]] && return 3
  return 0
}

@test "dybatpho::parallel_map runs the command once per item" {
  run --separate-stderr -0 dybatpho::parallel_map 2 _echo_job alpha bravo charlie
  assert_line --index 0 "out alpha"
  assert_line --index 1 "out bravo"
  assert_line --index 2 "out charlie"
  # Counted from a direct call, because `run` would report on its own subshell.
  dybatpho::parallel_map 2 _echo_job alpha bravo charlie > /dev/null 2>&1
  assert_equal "$(dybatpho::parallel_count)" "3"
}

@test "each job's output is replayed whole, in submission order" {
  # Interleaved output is the failure this module exists to prevent, so the
  # lines of one job must stay together even though the jobs overlapped.
  _pair_job() {
    printf 'first %s\n' "$1"
    sleep "0.$((RANDOM % 3))"
    printf 'second %s\n' "$1"
  }
  run -0 dybatpho::parallel_map 4 _pair_job a b c
  assert_line --index 0 "first a"
  assert_line --index 1 "second a"
  assert_line --index 2 "first b"
  assert_line --index 3 "second b"
  assert_line --index 4 "first c"
  assert_line --index 5 "second c"
}

@test "standard error is replayed too, and kept off standard output" {
  run --separate-stderr -0 dybatpho::parallel_map 2 _echo_job one two
  assert_output "$(printf 'out one\nout two')"
  assert_equal "${stderr}" "$(printf 'err one\nerr two')"
}

@test "one job at a time really does serialize the work" {
  dybatpho::parallel_map 1 _traced_job a b > /dev/null
  assert_equal "$(cat "${LOG}")" "$(printf 'start a\nend a\nstart b\nend b')"
}

@test "several jobs at a time really do overlap" {
  dybatpho::parallel_map 3 _traced_job a b c > /dev/null
  # With a pool of three, every job starts before the first one ends.
  assert_equal "$(head -3 "${LOG}" | grep -c '^start ')" "3"
}

@test "the pool never exceeds the requested width" {
  dybatpho::parallel_map 2 _traced_job a b c d > /dev/null
  # A width of two means the third job cannot start until one of the first two
  # has ended, so an end must appear before the third start.
  assert_equal "$(sed -n '3p' "${LOG}")" "end a"
}

@test "each job keeps its own exit code" {
  # Called directly: `run` would execute the pool in a subshell, where the
  # recorded statuses die with it.
  ! dybatpho::parallel_map 3 _failing_job good1 bad1 good2 bad2 > /dev/null
  assert_equal "$(dybatpho::parallel_count)" "4"
  assert_equal "$(dybatpho::parallel_failed)" "2"
  assert_equal "$(dybatpho::parallel_status 0)" "0"
  assert_equal "$(dybatpho::parallel_status 1)" "3"
  assert_equal "$(dybatpho::parallel_status 2)" "0"
  assert_equal "$(dybatpho::parallel_status 3)" "3"
}

@test "a run where everything succeeds reports success" {
  dybatpho::parallel_map 2 _failing_job good1 good2 > /dev/null
  assert_equal "$(dybatpho::parallel_failed)" "0"
}

@test "an item containing spaces and quotes stays one item" {
  _capture_job() { printf '[%s]\n' "$1"; }
  run --separate-stderr -0 dybatpho::parallel_map 2 _capture_job 'two words' "it's quoted" '$(echo hi)'
  assert_line --index 0 "[two words]"
  assert_line --index 1 "[it's quoted]"
  # The item must not be re-parsed as shell syntax.
  assert_line --index 2 '[$(echo hi)]'
}

@test "fail-fast leaves the remaining jobs unstarted" {
  # shellcheck disable=2030
  DYBATPHO_PARALLEL_FAILFAST=true
  ! dybatpho::parallel_map 1 _failing_job a bad1 c d > /dev/null
  DYBATPHO_PARALLEL_FAILFAST=false
  assert_equal "$(tr '\n' ' ' < "${LOG}")" "ran a ran bad1 "
  assert_equal "$(dybatpho::parallel_status 1)" "3"
  # A job that never ran did not fail; it is reported as skipped.
  assert_equal "$(dybatpho::parallel_status 2)" "skipped"
  assert_equal "$(dybatpho::parallel_status 3)" "skipped"
  assert_equal "$(dybatpho::parallel_failed)" "1"
}

@test "without fail-fast every job runs even after a failure" {
  run -1 dybatpho::parallel_map 1 _failing_job a bad1 c d
  assert_equal "$(grep -c '^ran ' "${LOG}")" "4"
}

@test "dybatpho::parallel_run evaluates each command string" {
  run -0 dybatpho::parallel_run 2 "printf 'one\n'" "printf 'two\n'; true"
  assert_line --index 0 "one"
  assert_line --index 1 "two"
}

@test "dybatpho::parallel_run reports the exit code of each command" {
  ! dybatpho::parallel_run 2 "true" "exit 7" "true" > /dev/null
  assert_equal "$(dybatpho::parallel_status 1)" "7"
  assert_equal "$(dybatpho::parallel_failed)" "1"
}

@test "an empty job list succeeds without running anything" {
  run --separate-stderr -0 dybatpho::parallel_map 2 _echo_job
  assert_output ""
  dybatpho::parallel_map 2 _echo_job
  assert_equal "$(dybatpho::parallel_count)" "0"
  dybatpho::parallel_run 2
  assert_equal "$(dybatpho::parallel_count)" "0"
}

@test "a job count of zero follows the configuration, then the machine" {
  # shellcheck disable=2030
  DYBATPHO_PARALLEL_JOBS=2
  run --separate-stderr -0 dybatpho::parallel_map 0 _echo_job a b c
  assert_line --index 0 "out a"
  DYBATPHO_PARALLEL_JOBS=0
  # With nothing configured the count comes from the CPU count, which only has
  # to be a workable positive number.
  run --separate-stderr -0 dybatpho::parallel_map 0 _echo_job a
  assert_output "out a"
}

@test "an invalid job count is rejected" {
  run ! dybatpho::parallel_map -1 _echo_job a
  run ! dybatpho::parallel_map abc _echo_job a
  run ! dybatpho::parallel_run 1.5 "true"
}

@test "dybatpho::parallel_status rejects an index that has no job" {
  dybatpho::parallel_map 2 _echo_job a b > /dev/null
  run ! dybatpho::parallel_status 5
  run ! dybatpho::parallel_status -1
  run ! dybatpho::parallel_status abc
}

@test "the pool runs nothing under DRY_RUN" {
  # shellcheck disable=2030,2031
  export DRY_RUN=true
  run --separate-stderr -0 dybatpho::parallel_map 2 _failing_job a bad1
  assert_output --partial "DRY RUN"
  run -0 dybatpho::parallel_run 2 "touch '${BATS_TEST_TMPDIR}/side-effect'"
  assert_output --partial "DRY RUN"
  unset DRY_RUN
  # Nothing ran: no job wrote to the log, and no command had its effect.
  assert_equal "$(wc -c < "${LOG}" | tr -d ' ')" "0"
  refute [ -e "${BATS_TEST_TMPDIR}/side-effect" ]
}

@test "the pool leaves the caller's job control setting alone" {
  local before after
  case "$-" in *m*) before=on ;; *) before=off ;; esac
  dybatpho::parallel_map 2 _echo_job a b > /dev/null
  case "$-" in *m*) after=on ;; *) after=off ;; esac
  assert_equal "${after}" "${before}"
}

@test "a job can call a function the caller defined, without exporting it" {
  _outer_helper() { printf 'helped %s\n' "$1"; }
  _inner_job() { _outer_helper "$1"; }
  run --separate-stderr -0 dybatpho::parallel_map 2 _inner_job x y
  assert_line --index 0 "helped x"
  assert_line --index 1 "helped y"
}

@test "a pool run inside a command substitution leaves the recorded status alone" {
  # The statuses live in the calling shell, so a capture keeps the output but
  # not the bookkeeping. This is a property callers have to know about.
  dybatpho::parallel_map 2 _echo_job a b > /dev/null
  local before captured
  before="$(dybatpho::parallel_count)"
  captured="$(dybatpho::parallel_map 2 _echo_job p q r 2> /dev/null)"
  assert_equal "${captured}" "$(printf 'out p\nout q\nout r')"
  assert_equal "$(dybatpho::parallel_count)" "${before}"
}

@test "a job that calls exit is recorded, not lost" {
  # `exit` inside a job used to end the worker before its exit code was
  # written, which reported the job as never having run — visible only under
  # coverage, where the traced worker dies with it.
  ! dybatpho::parallel_run 2 "true" "exit 7" "true" > /dev/null
  assert_equal "$(dybatpho::parallel_status 1)" "7"
  assert_equal "$(dybatpho::parallel_failed)" "1"
}

@test "a mapped command that calls exit is recorded too" {
  _exiting_job() {
    [[ "$1" == "bad" ]] && exit 5
    return 0
  }
  ! dybatpho::parallel_map 2 _exiting_job good bad > /dev/null
  assert_equal "$(dybatpho::parallel_status 0)" "0"
  assert_equal "$(dybatpho::parallel_status 1)" "5"
  assert_equal "$(dybatpho::parallel_failed)" "1"
}
