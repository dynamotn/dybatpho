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
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _echo_job alpha bravo charlie
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
  run_traced -0 dybatpho::parallel_map 4 _pair_job a b c
  assert_line --index 0 "first a"
  assert_line --index 1 "second a"
  assert_line --index 2 "first b"
  assert_line --index 3 "second b"
  assert_line --index 4 "first c"
  assert_line --index 5 "second c"
}

@test "standard error is replayed too, and kept off standard output" {
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _echo_job one two
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
  #
  # Which of the first two ends first is a race — they run concurrently and
  # sleep for the same time — so the line is matched by kind, not by job name.
  # Asserting "end a" here made this test fail roughly one run in ten.
  assert_regex "$(sed -n '3p' "${LOG}")" '^end '
  assert_equal "$(head -3 "${LOG}" | grep -c '^start ')" "2"
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
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _capture_job 'two words' "it's quoted" '$(echo hi)'
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
  run_traced -1 dybatpho::parallel_map 1 _failing_job a bad1 c d
  assert_equal "$(grep -c '^ran ' "${LOG}")" "4"
}

@test "--fail-fast stops the pool the way the variable does" {
  ! dybatpho::parallel_map --fail-fast 1 _failing_job a bad1 c > /dev/null 2>&1
  assert_equal "$(tr '\n' ' ' < "${LOG}")" "ran a ran bad1 "
  assert_equal "$(dybatpho::parallel_status 2)" "skipped"
}

@test "fail-fast ends a job still running when another fails" {
  # Both jobs start at once, so the failure arrives while the pool is draining:
  # the slow job must be ended there rather than waited for.
  _slow_or_bad() {
    if [[ "$1" == "slow" ]]; then
      sleep 30 &
      printf '%s' "$!" > "${BATS_TEST_TMPDIR}/sleeper"
      wait
      printf 'slow finished\n' >> "${LOG}"
      return 0
    fi
    while [[ ! -s "${BATS_TEST_TMPDIR}/sleeper" ]]; do sleep 0.05; done
    return 3
  }
  local started="${SECONDS}"
  ! dybatpho::parallel_map --fail-fast 3 _slow_or_bad slow bad \
    > /dev/null 2> "${BATS_TEST_TMPDIR}/stderr"
  ((SECONDS - started < 10))
  assert_equal "$(dybatpho::parallel_status 0)" "terminated"
  assert_equal "$(dybatpho::parallel_status 1)" "3"
  # Ended because another job failed, so it is not a failure of its own.
  assert_equal "$(dybatpho::parallel_failed)" "1"
  refute grep -q 'slow finished' "${LOG}"
  # The job's own child goes with it, since the whole process group is ended.
  assert_process_dead "$(cat "${BATS_TEST_TMPDIR}/sleeper")"
  run_traced grep -c 'Job 1 (bad) failed with exit 3' "${BATS_TEST_TMPDIR}/stderr"
  assert_output "1"
}

@test "dybatpho::parallel_run takes --fail-fast too" {
  ! dybatpho::parallel_run --fail-fast 1 "true" "exit 4" "true" > /dev/null 2> "${BATS_TEST_TMPDIR}/stderr"
  assert_equal "$(dybatpho::parallel_status 1)" "4"
  assert_equal "$(dybatpho::parallel_status 2)" "skipped"
  run_traced grep -c 'Job 1 (exit 4) failed with exit 4' "${BATS_TEST_TMPDIR}/stderr"
  assert_output "1"
}

@test "-- ends the options, and an unknown option is refused" {
  run_traced --separate-stderr -0 dybatpho::parallel_map -- 2 _echo_job a
  assert_output "out a"
  run ! dybatpho::parallel_map --fast 2 _echo_job a
  assert_output --partial "Unknown option '--fast'"
  run ! dybatpho::parallel_run --fast 2 "true"
}

@test "an item that looks like an option is still an item" {
  _capture_job() { printf '[%s]\n' "$1"; }
  run_traced --separate-stderr -0 dybatpho::parallel_map 1 _capture_job --fail-fast
  assert_output "[--fail-fast]"
}

@test "--timeout ends a job that runs too long and records 124" {
  _slow_or_quick() {
    if [[ "$1" == "slow" ]]; then
      sleep 30 &
      printf '%s' "$!" > "${BATS_TEST_TMPDIR}/sleeper"
      wait
      return 0
    fi
    printf 'quick done\n'
  }
  local started="${SECONDS}"
  ! dybatpho::parallel_map --timeout 1 2 _slow_or_quick slow quick \
    > "${BATS_TEST_TMPDIR}/stdout" 2> "${BATS_TEST_TMPDIR}/stderr"
  ((SECONDS - started < 10))
  assert_equal "$(dybatpho::parallel_status 0)" "124"
  assert_equal "$(dybatpho::parallel_status 1)" "0"
  assert_equal "$(dybatpho::parallel_failed)" "1"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/stdout")" "quick done"
  assert_process_dead "$(cat "${BATS_TEST_TMPDIR}/sleeper")"
  run_traced grep -c 'Job 0 (slow) timed out after 1s' "${BATS_TEST_TMPDIR}/stderr"
  assert_output "1"
}

@test "a job that ignores the stop request is killed after the grace period" {
  _stubborn() {
    trap '' TERM
    sleep 30 &
    printf '%s' "$!" > "${BATS_TEST_TMPDIR}/sleeper"
    wait
  }
  # shellcheck disable=2030
  DYBATPHO_TIMEOUT_KILL_AFTER=1
  local started="${SECONDS}"
  ! dybatpho::parallel_run --timeout=1s 1 "_stubborn" > /dev/null 2>&1
  DYBATPHO_TIMEOUT_KILL_AFTER=5
  ((SECONDS - started < 10))
  assert_equal "$(dybatpho::parallel_status 0)" "124"
  assert_process_dead "$(cat "${BATS_TEST_TMPDIR}/sleeper")"
}

@test "a generous limit does not hold the pool open" {
  # Each job's watchdog sleeps for the whole limit, so the pool must end it
  # with the job rather than wait for it.
  local started="${SECONDS}"
  run_traced --separate-stderr -0 dybatpho::parallel_map --timeout 1m 2 _echo_job a b
  ((SECONDS - started < 10))
  assert_output "$(printf 'out a\nout b')"
}

@test "DYBATPHO_PARALLEL_TIMEOUT sets the limit when no option does" {
  # shellcheck disable=2030
  DYBATPHO_PARALLEL_TIMEOUT=1
  ! dybatpho::parallel_run 1 "sleep 30" > /dev/null 2>&1
  DYBATPHO_PARALLEL_TIMEOUT=""
  assert_equal "$(dybatpho::parallel_status 0)" "124"
}

@test "a timed-out job counts as the failure fail-fast stops on" {
  ! dybatpho::parallel_run --fail-fast --timeout 1 1 "sleep 30" "true" > /dev/null 2>&1
  assert_equal "$(dybatpho::parallel_status 0)" "124"
  assert_equal "$(dybatpho::parallel_status 1)" "skipped"
}

@test "an interrupted pool ends its jobs and their watchdogs" {
  _sleeper() {
    sleep 30 &
    printf '%s' "$!" > "${BATS_TEST_TMPDIR}/sleeper"
    wait
  }
  local started="${SECONDS}" pool
  (dybatpho::parallel_map --timeout 1m 1 _sleeper a) > /dev/null 2>&1 &
  pool=$!
  while [[ ! -s "${BATS_TEST_TMPDIR}/sleeper" ]]; do sleep 0.05; done
  kill -TERM "${pool}"
  wait "${pool}" || true
  # A watchdog left sleeping out its minute would hold the pool open that long.
  ((SECONDS - started < 10))
  assert_process_dead "$(cat "${BATS_TEST_TMPDIR}/sleeper")"
}

@test "an interrupted pool starts nothing more and ends as the signal would" {
  # The handler ended the jobs it knew about and returned, so the pool went on:
  # it started the remaining jobs, and a watchdog started after the signal kept
  # the pool waiting out its whole limit. The first job signals the pool itself,
  # which puts the interrupt between two jobs every time.
  _signals_pool() {
    if [[ "$1" == second ]]; then
      : > "${BATS_TEST_TMPDIR}/second-ran"
      return 0
    fi
    while [[ ! -s "${BATS_TEST_TMPDIR}/pool" ]]; do sleep 0.05; done
    sleep 30 &
    printf '%s' "$!" > "${BATS_TEST_TMPDIR}/sleeper"
    kill -TERM "$(< "${BATS_TEST_TMPDIR}/pool")"
    wait
  }
  local started="${SECONDS}" pool status=0
  (dybatpho::parallel_map --timeout 1m 1 _signals_pool first second) > /dev/null 2>&1 &
  pool=$!
  printf '%s' "${pool}" > "${BATS_TEST_TMPDIR}/pool"
  wait "${pool}" || status=$?
  ((SECONDS - started < 10))
  assert_equal "${status}" "143"
  assert_file_not_exist "${BATS_TEST_TMPDIR}/second-ran"
  assert_process_dead "$(cat "${BATS_TEST_TMPDIR}/sleeper")"
}

@test "a pool cleans up before a caller handler that exits on the signal" {
  # Handlers composed by appending ran the caller's first, and one that exits --
  # `killed_process_handler`, or a plain `trap 'exit' TERM` -- ended the shell
  # before the pool's cleanup ran, so its jobs were never told to stop. The job
  # records the TERM the pool sends it.
  local script="${BATS_TEST_TMPDIR}/killed_pool.sh"
  local ready="${BATS_TEST_TMPDIR}/ready" told="${BATS_TEST_TMPDIR}/told"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules parallel" \
    "dybatpho::register_killed_handler" \
    "_job() {" \
    "  trap 'printf told > $(printf '%q' "${told}"); exit 0' TERM" \
    "  printf ready > $(printf '%q' "${ready}")" \
    "  local i; for ((i = 0; i < 300; i++)); do sleep 0.1; done" \
    "}" \
    "( while [[ ! -s $(printf '%q' "${ready}") ]]; do sleep 0.05; done; kill -TERM \$\$ ) &" \
    "dybatpho::parallel_map 1 _job a > /dev/null 2>&1" \
    "printf 'carried on\\n'" > "${script}"
  run bash "${script}"
  assert_equal "${status}" "143"
  refute_output --partial "carried on"
  # The pool waits for the job it ends, so the record is there by now.
  assert_file_exist "${told}"
}

@test "an invalid timeout is refused" {
  run ! dybatpho::parallel_map --timeout abc 2 _echo_job a
  assert_output --partial "dybatpho::parallel_map: Timeout must be a duration"
  run ! dybatpho::parallel_run --timeout -5 2 -- true
  assert_output --partial "dybatpho::parallel_run: Timeout must not be negative"
  run ! dybatpho::parallel_run --timeout
  assert_output --partial "--timeout needs a duration"
}

@test "--progress reports on standard error and leaves standard output alone" {
  # No terminal here, so the bar logs one line per percentage step.
  run_traced --separate-stderr -0 dybatpho::parallel_map --progress 1 _echo_job a b c
  assert_output "$(printf 'out a\nout b\nout c')"
  assert_regex "${stderr}" 'Jobs: 100% \(3/3\)'
}

@test "DYBATPHO_PARALLEL_PROGRESS turns progress on without the option" {
  # shellcheck disable=2030
  DYBATPHO_PARALLEL_PROGRESS=true
  run_traced --separate-stderr -0 dybatpho::parallel_run 2 "true" "true"
  DYBATPHO_PARALLEL_PROGRESS=false
  assert_regex "${stderr}" 'Jobs: 100% \(2/2\)'
}

@test "without progress the pool reports nothing of its own" {
  run_traced --separate-stderr -0 dybatpho::parallel_map 1 _echo_job a
  assert_equal "${stderr}" "err a"
}

@test "progress without the tui module prints one line per finished job" {
  # The child inherits the exported `dybatpho::tui_progress_*` names but not the
  # internals behind them, which is exactly the shell the guard has to detect.
  # Spawned from a script file, not `bash -c`, for the kcov hook's sake.
  local script="${BATS_TEST_TMPDIR}/child_progress.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules parallel
_job() { printf 'out %s\n' "$1"; }
dybatpho::parallel_map --progress 1 _job a b c 2> "${2}"
SCRIPT
  run -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${DYBATPHO_DIR}" "${BATS_TEST_TMPDIR}/stderr"
  assert_output "$(printf 'out a\nout b\nout c')"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/stderr")" \
    "$(printf 'Jobs: 1/3 finished\nJobs: 2/3 finished\nJobs: 3/3 finished')"
}

@test "dybatpho::parallel_run evaluates each command string" {
  run_traced -0 dybatpho::parallel_run 2 "printf 'one\n'" "printf 'two\n'; true"
  assert_line --index 0 "one"
  assert_line --index 1 "two"
}

@test "dybatpho::parallel_run reports the exit code of each command" {
  ! dybatpho::parallel_run 2 "true" "exit 7" "true" > /dev/null
  assert_equal "$(dybatpho::parallel_status 1)" "7"
  assert_equal "$(dybatpho::parallel_failed)" "1"
}

@test "an empty job list succeeds without running anything" {
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _echo_job
  assert_output ""
  dybatpho::parallel_map 2 _echo_job
  assert_equal "$(dybatpho::parallel_count)" "0"
  dybatpho::parallel_run 2
  assert_equal "$(dybatpho::parallel_count)" "0"
}

@test "a job count of zero follows the configuration, then the machine" {
  # shellcheck disable=2030
  DYBATPHO_PARALLEL_JOBS=2
  run_traced --separate-stderr -0 dybatpho::parallel_map 0 _echo_job a b c
  assert_line --index 0 "out a"
  DYBATPHO_PARALLEL_JOBS=0
  # With nothing configured the count comes from the CPU count, which only has
  # to be a workable positive number.
  run_traced --separate-stderr -0 dybatpho::parallel_map 0 _echo_job a
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
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _failing_job a bad1
  assert_output --partial "DRY RUN"
  run_traced -0 dybatpho::parallel_run 2 "touch '${BATS_TEST_TMPDIR}/side-effect'"
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
  run_traced --separate-stderr -0 dybatpho::parallel_map 2 _inner_job x y
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

@test "dybatpho::parallel_run --timeout asks for the date module only for a duration it cannot read itself" {
  # `parallel` does not load `date`, so a pool without a limit, or with one in
  # plain seconds, does not pay for it. A child shell started from a file,
  # without the functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules parallel\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::parallel_run --timeout "${1}" 1 "printf ran"'
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" 30
  assert_success
  assert_output --partial "ran"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" 5m
  assert_failure
  assert_output --partial "dybatpho::parallel_run --timeout 5m needs the date module, load it with: dybatpho::load date"
  refute_output --partial "ran"

  # Once the script loads it, the same duration is read.
  sed_in_place 's/--modules parallel$/--modules parallel date/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}" 5m
  assert_success
  assert_output --partial "ran"
}

@test "a pool puts back the signal handlers it found" {
  # Each pool appended its terminate handler to SIGINT and SIGTERM and never
  # took it out, so a script running pools in a loop collected one more handler
  # per call, each ending process IDs long since gone.
  local script="${BATS_TEST_TMPDIR}/pools.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules parallel
_job() { :; }
trap 'echo caller' SIGTERM
# The first pool registers its temporary directory for cleanup, which installs
# the one cleanup handler a shell keeps; the handlers are read after it.
dybatpho::parallel_map 2 _job a b > /dev/null 2>&1
before="$(trap -p SIGTERM)"
before_int="$(trap -p SIGINT)"
for _ in 1 2 3; do
  dybatpho::parallel_map 2 _job a b > /dev/null 2>&1
done
[[ "$(trap -p SIGTERM)" == "${before}" ]] || { trap -p SIGTERM; exit 1; }
[[ "$(trap -p SIGINT)" == "${before_int}" ]] || { trap -p SIGINT; exit 2; }
[[ "${before}${before_int}" != *parallel_terminate* ]] || exit 3
SCRIPT
  run_traced bash "${script}" "${DYBATPHO_DIR}"
  assert_success
}
