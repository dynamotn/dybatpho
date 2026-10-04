setup() {
  load test_helper
  export DYBATPHO_SCHEDULE_DIR="${BATS_TEST_TMPDIR}/schedule"
  LOG="${BATS_TEST_TMPDIR}/log"
  : > "${LOG}"
  # 2026-10-02 14:30:00 UTC is a Friday, which several cron cases below rely on.
  FRIDAY="$(TZ=UTC dybatpho::date_parse "2026-10-02 14:30:00")"
}

# @description Append a line to the test log, as the command under schedule.
# @arg $1 string Text to record
note() {
  printf '%s\n' "$1" >> "${LOG}"
}

@test "dybatpho::schedule_every runs immediately and then on the interval" {
  run_traced dybatpho::schedule_every 1 --times 3 -- note tick
  assert_success
  assert_equal "$(wc -l < "${LOG}" | tr -d ' ')" "3"
}

@test "dybatpho::schedule_every rejects an interval or a count that is not a number" {
  run --separate-stderr dybatpho::schedule_every 0 --times 1 -- true
  assert_failure
  assert_stderr --partial "interval must be a positive number"

  run --separate-stderr dybatpho::schedule_every soon --times 1 -- true
  assert_failure
  assert_stderr --partial "interval must be a positive number"

  run --separate-stderr dybatpho::schedule_every 1 --times many -- true
  assert_failure
  assert_stderr --partial "--times must be a number"
}

@test "dybatpho::schedule_every needs a command after the separator" {
  run --separate-stderr dybatpho::schedule_every 1 --times 1 -- 
  assert_failure
  assert_stderr --partial "Expected a command"

  run --separate-stderr dybatpho::schedule_every 1 --times 1 note tick
  assert_failure
  assert_stderr --partial 'Expected `--` before the command'
}

@test "dybatpho::schedule_every keeps going when a run fails" {
  # A scheduled job that fails once must not end the loop; the next tick is
  # the whole point of running on a cadence.
  local script="${BATS_TEST_TMPDIR}/flaky.sh"
  printf '%s\n' "printf 'run\n' >> $(printf '%q' "${LOG}")" "exit 1" > "${script}"

  run_traced dybatpho::schedule_every 1 --times 2 -- bash "${script}"
  assert_success
  assert_equal "$(wc -l < "${LOG}" | tr -d ' ')" "2"
}

@test "dybatpho::schedule_every restores the signal handlers it replaced" {
  # A script calling this more than once must keep its own Ctrl-C handling.
  trap 'printf caller' INT
  local before
  before="$(trap -p INT)"

  dybatpho::schedule_every 1 --times 1 -- true

  assert_equal "$(trap -p INT)" "${before}"
  trap - INT
}

@test "dybatpho::schedule_every stops on a signal after the run in progress" {
  # The documented way to end an unbounded loop. Nothing exercised it, so the
  # flag the handler sets was only ever read on the `--times` path.
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/loop.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules schedule" \
    "dybatpho::schedule_every 1 -- printf 'tick\\n' >> $(printf '%q' "${LOG}")" \
    "printf 'clean exit\\n' >> $(printf '%q' "${LOG}")" > "${script}"

  bash "${script}" &
  local looping=$!
  sleep 2
  kill -TERM "${looping}"
  wait "${looping}"

  # The loop left on its own terms rather than being cut down mid-run.
  assert_equal "$(tail -n 1 "${LOG}")" "clean exit"
  # And it had ticked at least once before the signal arrived.
  grep -q '^tick$' "${LOG}"
}

@test "dybatpho::schedule_once_per runs once and skips the rest of the period" {
  run_traced dybatpho::schedule_once_per day greet -- note first
  assert_success

  run_traced -9 dybatpho::schedule_once_per day greet -- note second
  assert_equal "$(cat "${LOG}")" "first"
}

@test "dybatpho::schedule_once_per holds across separate invocations" {
  # The marker is on disk precisely so the limit survives the process; a
  # variable would reset on every run.
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/once.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules schedule" \
    "dybatpho::schedule_once_per day daily -- printf 'ran\n'" > "${script}"

  run_traced bash "${script}"
  assert_output "ran"

  run_traced -9 bash "${script}"
  assert_output ""
}

@test "dybatpho::schedule_once_per measures from the last run when given seconds" {
  run_traced dybatpho::schedule_once_per 3600 hourly -- note first
  assert_success
  run_traced -9 dybatpho::schedule_once_per 3600 hourly -- note second

  # Once the window has actually elapsed, the command runs again. The marker
  # was written a moment ago, so a one-second window needs that second to
  # pass first.
  sleep 1
  run_traced dybatpho::schedule_once_per 1 hourly -- note third
  assert_success
  assert_equal "$(tail -n 1 "${LOG}")" "third"
}

@test "dybatpho::schedule_once_per takes a named calendar period" {
  run_traced dybatpho::schedule_once_per hour h -- note hourly
  assert_success
  run_traced -9 dybatpho::schedule_once_per hour h -- note again

  run_traced dybatpho::schedule_once_per month m -- note monthly
  assert_success
  run_traced -9 dybatpho::schedule_once_per month m -- note again
}

@test "dybatpho::schedule_once_per runs once when many callers race for the same period" {
  # Reading the marker and writing it were two separate steps, so callers
  # started together could all read "not yet" and all run. Several rounds of
  # simultaneous callers, each on its own key, give the race room to show.
  local script="${BATS_TEST_TMPDIR}/racer.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules schedule" \
    'dybatpho::schedule_once_per "$1" "$2" -- printf "ran\n" >> "$3" || true' > "${script}"

  local round period caller
  for round in 1 2 3 4 5 6; do
    period=day
    ((round % 2)) || period=3600
    for caller in $(seq 1 12); do
      bash "${script}" "${period}" "race-${round}" "${LOG}.${round}" &
    done
    wait
    assert_equal "$(wc -l < "${LOG}.${round}" | tr -d ' ')" "1"
  done
}

@test "dybatpho::schedule_once_per clears a claim left by a caller that died" {
  # The claim guards two file operations, so one that has been held for
  # seconds belongs to a process that died inside them, not to a live caller.
  mkdir -p "${DYBATPHO_SCHEDULE_DIR}"
  printf '99999\n' > "${DYBATPHO_SCHEDULE_DIR}/stale.claim"
  touch -t 202001010000 "${DYBATPHO_SCHEDULE_DIR}/stale.claim"

  run_traced dybatpho::schedule_once_per day stale -- note ran
  assert_success
  assert_equal "$(cat "${LOG}")" "ran"
  assert_file_not_exist "${DYBATPHO_SCHEDULE_DIR}/stale.claim"
}

@test "dybatpho::schedule_once_per runs once when many callers find the same stale claim" {
  # Every waiter that judged the claim stale removed it, so one could remove
  # the fresh claim another had just taken in its place, and two callers then
  # ran in the same period. Several rounds give the race room to show.
  mkdir -p "${DYBATPHO_SCHEDULE_DIR}"
  local script="${BATS_TEST_TMPDIR}/racer.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules schedule" \
    'dybatpho::schedule_once_per day "$1" -- printf "ran\n" >> "$2" || true' > "${script}"

  local round caller
  for round in 1 2 3 4 5 6 7 8; do
    printf '1\n' > "${DYBATPHO_SCHEDULE_DIR}/stale-${round}.claim"
    touch -t 202001010000 "${DYBATPHO_SCHEDULE_DIR}/stale-${round}.claim"
    for caller in $(seq 1 12); do
      bash "${script}" "stale-${round}" "${LOG}.${round}" &
    done
    wait
    assert_equal "$(wc -l < "${LOG}.${round}" | tr -d ' ')" "1"
  done
  run_traced ls "${DYBATPHO_SCHEDULE_DIR}"
  refute_output --partial "claim"
  refute_output --partial "reclaim"
}

@test "dybatpho::schedule_once_per gives up on a claim another caller keeps" {
  # A fresh claim belongs to a live caller, so it is waited for rather than
  # removed; one that stays fresh for the whole wait makes the call give up
  # without running anything or touching the marker. The claim is kept fresh
  # by reporting its age as 0 -- a live caller re-taking it would look the
  # same -- and the pause between attempts is skipped, since neither is what
  # is under test.
  # shellcheck disable=SC2329
  sleep() { :; }
  # shellcheck disable=SC2329
  dybatpho::file_age_seconds() { printf '0\n'; }
  mkdir -p "${DYBATPHO_SCHEDULE_DIR}"
  printf '%s\n' "$$" > "${DYBATPHO_SCHEDULE_DIR}/held.claim"

  run_traced --separate-stderr -1 dybatpho::schedule_once_per day held -- note ran
  assert_stderr --partial "dybatpho::schedule_once_per: ${DYBATPHO_SCHEDULE_DIR}/held.claim is still claimed"
  assert_equal "$(cat "${LOG}")" ""
  assert_file_not_exist "${DYBATPHO_SCHEDULE_DIR}/held.last"
  assert_file_exist "${DYBATPHO_SCHEDULE_DIR}/held.claim"
  unset -f sleep
}

@test "dybatpho::schedule_once_per rejects a period it does not know" {
  run --separate-stderr dybatpho::schedule_once_per fortnight k -- true
  assert_failure
  assert_stderr --partial "Not a period: fortnight"
}

@test "dybatpho::schedule_reset lets the next call run again" {
  dybatpho::schedule_once_per day greet -- note first
  run_traced -9 dybatpho::schedule_once_per day greet -- note blocked

  run_traced dybatpho::schedule_reset greet
  assert_success

  run_traced dybatpho::schedule_once_per day greet -- note after_reset
  assert_success
  assert_equal "$(tail -n 1 "${LOG}")" "after_reset"
}

@test "dybatpho::schedule_reset is quiet when the key recorded nothing" {
  run_traced dybatpho::schedule_reset never-used
  assert_success
  assert_output ""
}

@test "a key that would escape the marker directory is refused" {
  # A key becomes a file name, so one carrying a slash or `..` would write
  # outside the directory the module owns.
  run --separate-stderr dybatpho::schedule_once_per day "../../etc/passwd" -- true
  assert_failure
  assert_stderr --partial "Not a usable key"

  run --separate-stderr dybatpho::schedule_reset "a/b"
  assert_failure
  assert_stderr --partial "Not a usable key"

  run --separate-stderr dybatpho::schedule_debounce 1 "" -- true
  assert_failure
  assert_stderr --partial "Not a usable key"
}

@test "dybatpho::schedule_debounce runs a lone trigger" {
  run_traced dybatpho::schedule_debounce 1 solo -- note only
  assert_success
  assert_equal "$(cat "${LOG}")" "only"
}

@test "dybatpho::schedule_debounce collapses a burst into the last trigger" {
  # Running on the first event is what an editor's write-then-rename breaks:
  # the file is still half written. The run belongs after the burst settles.
  local at
  for at in 1 2 3; do
    (dybatpho::schedule_debounce 2 build -- note "built-by-${at}") &
    sleep 1
  done
  wait

  assert_equal "$(wc -l < "${LOG}" | tr -d ' ')" "1"
  assert_equal "$(cat "${LOG}")" "built-by-3"
}

@test "dybatpho::schedule_debounce returns 9 for a trigger a later one replaced" {
  (dybatpho::schedule_debounce 2 replaced -- note stale) &
  local first=$!
  sleep 1
  dybatpho::schedule_debounce 2 replaced -- note fresh

  run_traced -0 wait "${first}" || true
  assert_equal "$(cat "${LOG}")" "fresh"
}

@test "dybatpho::schedule_debounce rejects a window that is not a positive number" {
  run --separate-stderr dybatpho::schedule_debounce 0 k -- true
  assert_failure
  assert_stderr --partial "window must be a positive number"
}

@test "dybatpho::schedule_cron_due matches a plain expression" {
  run_traced -0 dybatpho::schedule_cron_due "30 14 * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "0 14 * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "30 15 * * *" "${FRIDAY}"
}

@test "dybatpho::schedule_cron_due handles steps, ranges and lists" {
  run_traced -0 dybatpho::schedule_cron_due "*/15 * * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "*/7 * * * *" "${FRIDAY}"
  run_traced -0 dybatpho::schedule_cron_due "30 9-17 * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "30 9-12 * * *" "${FRIDAY}"
  run_traced -0 dybatpho::schedule_cron_due "0,15,30,45 * * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "0,15,45 * * * *" "${FRIDAY}"
  run_traced -0 dybatpho::schedule_cron_due "30 8-18/2 * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "30 9-17/2 * * *" "${FRIDAY}"
}

@test "dybatpho::schedule_cron_due reads a day of week, with 7 as Sunday" {
  run_traced -0 dybatpho::schedule_cron_due "* * * * 5" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "* * * * 1" "${FRIDAY}"

  local sunday
  sunday="$(TZ=UTC dybatpho::date_parse "2026-10-04 09:00:00")"
  run_traced -0 dybatpho::schedule_cron_due "0 9 * * 0" "${sunday}"
  run_traced -0 dybatpho::schedule_cron_due "0 9 * * 7" "${sunday}"
}

@test "dybatpho::schedule_cron_due matches either day field when both are restricted" {
  # This is what cron itself does, and what a hand-written check gets wrong:
  # with both a day of month and a day of week given, either one is enough.
  # The 2nd of October 2026 is a Friday.
  run_traced -0 dybatpho::schedule_cron_due "30 14 2 10 *" "${FRIDAY}"
  run_traced -0 dybatpho::schedule_cron_due "30 14 1 10 5" "${FRIDAY}"
  run_traced -0 dybatpho::schedule_cron_due "30 14 2 10 1" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "30 14 1 10 1" "${FRIDAY}"

  # With only one of them restricted, it has to match on its own.
  run_traced -1 dybatpho::schedule_cron_due "30 14 1 10 *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "30 14 * 10 1" "${FRIDAY}"
}

@test "dybatpho::schedule_cron_due reads a zero-padded hour as decimal" {
  # `08` is not a valid octal literal, so an unguarded arithmetic expansion
  # fails on exactly the hours a nightly job cares about.
  local early
  early="$(TZ=UTC dybatpho::date_parse "2026-10-08 08:09:00")"
  run_traced -0 dybatpho::schedule_cron_due "9 8 8 10 *" "${early}"
}

@test "dybatpho::schedule_cron_due reports a malformed expression" {
  run --separate-stderr -2 dybatpho::schedule_cron_due "bad expr" "${FRIDAY}"
  assert_stderr --partial "five fields"

  run_traced -1 dybatpho::schedule_cron_due "x * * * *" "${FRIDAY}"
  run_traced -1 dybatpho::schedule_cron_due "*/0 * * * *" "${FRIDAY}"
}

@test "dybatpho::schedule_cron_due defaults to the current time" {
  # A frozen clock keeps "now" in one minute: read live, the minute could turn
  # between computing the expression and evaluating it.
  dybatpho::mock_time 1790946330
  local now minute hour
  now="$(dybatpho::date_now "%s")"
  minute="$(dybatpho::date_format "${now}" "%M")"
  hour="$(dybatpho::date_format "${now}" "%H")"

  run_traced -0 dybatpho::schedule_cron_due "$((10#${minute})) $((10#${hour})) * * *"
  run_traced -0 dybatpho::schedule_cron_due "* * * * *"
  dybatpho::unmock_time
}

@test "dybatpho::schedule_debounce asks for the lock module when it is not loaded" {
  # `schedule` does not load `lock`, so a script that only runs on a cadence
  # does not pay for it. A child shell started from a file, without the
  # functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules schedule\n' "${DYBATPHO_DIR}/init.sh"
    printf 'export DYBATPHO_SCHEDULE_DIR=%q\n' "${DYBATPHO_SCHEDULE_DIR}"
    # A second run inside the same day skips this, with status 9.
    printf '%s\n' 'dybatpho::schedule_once_per day narrow -- printf "once\n" || true'
    printf '%s\n' 'dybatpho::schedule_debounce 1 narrow -- printf "settled\n"'
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_line --index 0 "once"
  assert_output --partial "dybatpho::schedule_debounce needs the lock module, load it with: dybatpho::load lock"

  # Once the script loads it, the same call runs.
  sed_in_place 's/--modules schedule$/--modules schedule lock/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line "settled"
}

@test "a schedule with no state directory stops in the function that was called" {
  # Resolved inside a command substitution, the missing directory left the
  # markers under `/schedule`, at the root of the filesystem.
  local script="${BATS_TEST_TMPDIR}/no-home.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules schedule" \
    "unset HOME XDG_STATE_HOME; DYBATPHO_SCHEDULE_DIR=" \
    "if ! dybatpho::schedule_reset nightly; then :; fi" \
    "printf 'carried on\n'" > "${script}"

  run --separate-stderr bash "${script}"
  assert_failure
  assert_stderr --partial "dybatpho::schedule_reset: Neither XDG_STATE_HOME nor HOME is set"
  refute_stderr --partial "/schedule"
  refute_output --partial "carried on"
}

@test "a scheduled command sees the caller's variables, not the scheduler's" {
  # The command runs in the scheduler's scope, where its locals hid the
  # caller's variables of the same names, and `times` or `ran` could be
  # overwritten from inside the loop.
  local times="caller" ran="caller" command="caller" key="caller" directory="caller" period="caller"
  look() { printf '%s %s %s %s %s %s\n' "${times}" "${ran}" "${command}" "${key}" "${directory}" "${period}" >> "${LOG}"; }
  run_traced dybatpho::schedule_every 1 --times 1 -- look
  run_traced dybatpho::schedule_once_per day scoped -- look
  run_traced dybatpho::schedule_debounce 1 scoped -- look
  assert_equal "$(sort -u "${LOG}")" "caller caller caller caller caller caller"
  assert_equal "$(wc -l < "${LOG}" | tr -d ' ')" "3"
}
