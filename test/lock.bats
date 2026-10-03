setup() {
  load test_helper
  export DYBATPHO_LOCK_DIR="${BATS_TEST_TMPDIR}"
  export DYBATPHO_LOCK_POLL_INTERVAL="0.1"
  # A pid one above the kernel's ceiling can never be running. A fixed number
  # such as 999999 can: Linux allows pids up to 4194304, and on a busy machine
  # a real process held one, which made a dead lock look alive.
  local pid_max=99999
  [[ -r /proc/sys/kernel/pid_max ]] && pid_max="$(< /proc/sys/kernel/pid_max)"
  DEAD_PID="$((pid_max + 1))"
}

teardown() {
  rm -rf "${DYBATPHO_LOCK_DIR}"/dybatpho-*.lock 2> /dev/null || true
}

@test "dybatpho::lock_path resolves bare name under DYBATPHO_LOCK_DIR" {
  assert_equal "$(dybatpho::lock_path "myjob")" "${DYBATPHO_LOCK_DIR}/dybatpho-myjob.lock"
}

@test "dybatpho::lock_path keeps an explicit path as-is" {
  assert_equal "$(dybatpho::lock_path "/tmp/custom/myjob")" "/tmp/custom/myjob.lock"
}

@test "dybatpho::lock_path doesn't double the .lock suffix" {
  assert_equal "$(dybatpho::lock_path "myjob.lock")" "${DYBATPHO_LOCK_DIR}/dybatpho-myjob.lock"
}

@test "dybatpho::lock_acquire then dybatpho::lock_is_held reports success" {
  run_traced dybatpho::lock_acquire "acquire-test"
  assert_success

  run_traced dybatpho::lock_is_held "acquire-test"
  assert_success

  dybatpho::lock_release "acquire-test"
}

@test "dybatpho::lock_acquire fails fast without waiting when already held" {
  dybatpho::lock_acquire "busy"

  run_traced --separate-stderr dybatpho::lock_acquire "busy"
  assert_failure
  assert_stderr --partial "Could not acquire lock"
  assert_stderr --partial "pid=$$"

  dybatpho::lock_release "busy"
}

@test "dybatpho::lock_acquire waits up to the timeout then succeeds after release" {
  dybatpho::lock_acquire "waiter"
  (
    sleep 0.3
    dybatpho::lock_release "waiter"
  ) &
  local releaser_pid=$!

  run_traced dybatpho::lock_acquire "waiter" 2
  assert_success
  wait "${releaser_pid}"
  dybatpho::lock_release "waiter"
}

@test "dybatpho::lock_acquire waits up to the timeout then fails when still held" {
  dybatpho::lock_acquire "still-busy"
  run_traced --separate-stderr dybatpho::lock_acquire "still-busy" 1
  assert_failure
  dybatpho::lock_release "still-busy"
}

@test "dybatpho::lock_info prints the current holder metadata" {
  dybatpho::lock_acquire "info-test"
  run_traced dybatpho::lock_info "info-test"
  assert_success
  assert_output --partial "pid=$$"
  assert_output --partial "host=$(dybatpho::lock_hostname)"
  assert_output --partial "acquired_at="
  dybatpho::lock_release "info-test"
}

@test "dybatpho::lock_info fails when the lock isn't held" {
  run_traced dybatpho::lock_info "never-acquired"
  assert_failure
  refute_output
}

@test "dybatpho::lock_release removes a lock held by the current process" {
  dybatpho::lock_acquire "release-test"
  run_traced dybatpho::lock_release "release-test"
  assert_success
  run_traced dybatpho::lock_is_held "release-test"
  assert_failure
}

@test "dybatpho::lock_release is a no-op when the lock was never held" {
  run_traced dybatpho::lock_release "never-held"
  assert_success
}

@test "dybatpho::lock_release refuses to remove a lock held by another live process" {
  # Long enough to outlast a slow run; it is killed at the end. A few seconds
  # was not: on a loaded machine the stand-in exited before the release was
  # attempted, and the lock then read as stale rather than foreign.
  sleep 120 &
  local foreign_pid=$!

  local lock_path
  lock_path="$(dybatpho::lock_path "foreign")"
  mkdir "${lock_path}"
  printf '%s' "${foreign_pid}" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run_traced --separate-stderr dybatpho::lock_release "foreign"
  assert_failure
  assert_stderr --partial "is held by pid ${foreign_pid}"
  assert_dir_exist "${lock_path}"

  kill "${foreign_pid}" 2> /dev/null || true
  rm -rf "${lock_path}"
}

@test "dybatpho::lock_acquire reclaims a stale lock left by a dead process" {
  local lock_path
  lock_path="$(dybatpho::lock_path "stale")"
  mkdir "${lock_path}"
  printf '%s' "${DEAD_PID}" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run_traced --separate-stderr dybatpho::lock_acquire "stale"
  assert_success
  assert_stderr --partial "Reclaiming stale lock"
  dybatpho::lock_release "stale"
}

@test "dybatpho::with_lock runs the command while holding the lock and releases it after" {
  run_traced dybatpho::with_lock "with-lock-test" 1 -- bash -c 'echo ran'
  assert_success
  assert_output "ran"
  run_traced dybatpho::lock_is_held "with-lock-test"
  assert_failure
}

@test "dybatpho::with_lock releases the lock even when the command fails" {
  run_traced dybatpho::with_lock "with-lock-fail" 1 -- bash -c 'exit 5'
  assert_failure 5
  run_traced dybatpho::lock_is_held "with-lock-fail"
  assert_failure
}

@test "dybatpho::with_lock requires a -- separator" {
  run dybatpho::with_lock "with-lock-sep" 1 bash -c 'echo ran'
  assert_failure
}

@test "dybatpho::lock_field prints a recorded field and stays empty for a missing one" {
  local lock_path
  lock_path="$(dybatpho::lock_path "field-test")"
  dybatpho::lock_acquire "field-test"

  assert_equal "$(dybatpho::lock_field "${lock_path}" pid)" "$$"
  assert_equal "$(dybatpho::lock_field "${lock_path}" host)" "$(dybatpho::lock_hostname)"
  assert_equal "$(dybatpho::lock_field "${lock_path}" nonexistent)" ""

  dybatpho::lock_release "field-test"
}

@test "dybatpho::lock_is_alive is true for the current process and false once reclaimed" {
  local lock_path
  lock_path="$(dybatpho::lock_path "alive-test")"
  dybatpho::lock_acquire "alive-test"

  run_traced dybatpho::lock_is_alive "${lock_path}"
  assert_success

  dybatpho::lock_release "alive-test"

  run_traced dybatpho::lock_is_alive "${lock_path}"
  assert_failure
}

@test "dybatpho::lock_is_alive is false for a dead pid but true for another host" {
  local lock_path
  lock_path="$(dybatpho::lock_path "alive-dead")"
  mkdir "${lock_path}"
  printf '%s' "${DEAD_PID}" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run_traced dybatpho::lock_is_alive "${lock_path}"
  assert_failure

  # A lock recorded on another host can't be probed locally, so it counts as held.
  printf '%s' "some-other-host" > "${lock_path}/host"
  run_traced dybatpho::lock_is_alive "${lock_path}"
  assert_success

  rm -rf "${lock_path}"
}

@test "dybatpho::lock_reclaim_stale leaves alone a lock handed over during the check" {
  # The race this pins: the holder releases between the reclaimer's reads, the
  # name is empty for a moment, and the next process claims it. Judging the
  # empty name as a dead holder moved the new claim aside and deleted it, and
  # two processes then held the same lock. The stubs replay that order: the
  # release lands on the first read, and the next claim on any read after it.
  sleep 120 &
  local next_pid=$!
  local lock_path claim
  lock_path="$(dybatpho::lock_path "handover")"
  claim="${next_pid}:$(dybatpho::lock_hostname):2026-01-01T00:00:00Z"
  ln -s "$$:$(dybatpho::lock_hostname):2026-01-01T00:00:00Z" "${lock_path}"

  local reads="${BATS_TEST_TMPDIR}/reads"
  : > "${reads}"
  eval "__dybatpho_lock_original_identity() $(declare -f __dybatpho_lock_identity | tail -n +2)"
  __dybatpho_lock_identity() {
    printf '.' >> "${reads}"
    if [[ "$(< "${reads}")" == "." ]]; then
      rm -f -- "${lock_path}"
      return 0
    fi
    __dybatpho_lock_original_identity "$@"
  }
  dybatpho::lock_field() {
    ln -s "${claim}" "${lock_path}" 2> /dev/null || true
  }

  run_traced --separate-stderr dybatpho::lock_reclaim_stale "${lock_path}"
  assert_success
  ln -s "${claim}" "${lock_path}" 2> /dev/null || true
  assert_equal "$(readlink "${lock_path}")" "${claim}"
  assert_equal "${stderr}" ""

  kill "${next_pid}" 2> /dev/null || true
}

@test "dybatpho::lock_reclaim_stale removes a dead lock and leaves a live one alone" {
  local stale_path live_path
  stale_path="$(dybatpho::lock_path "reclaim-stale")"
  mkdir "${stale_path}"
  printf '%s' "${DEAD_PID}" > "${stale_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${stale_path}/host"

  run_traced --separate-stderr dybatpho::lock_reclaim_stale "${stale_path}"
  assert_success
  assert_stderr --partial "Reclaiming stale lock"
  assert_dir_not_exist "${stale_path}"

  live_path="$(dybatpho::lock_path "reclaim-live")"
  dybatpho::lock_acquire "reclaim-live"
  run_traced dybatpho::lock_reclaim_stale "${live_path}"
  assert_success
  # The assertion is that the lock is still held, not what it looks like on
  # disk: the claim is a symbolic link now, and that is an implementation
  # detail this test has no business pinning.
  dybatpho::lock_is_held "reclaim-live"

  dybatpho::lock_release "reclaim-live"
}

@test "dybatpho::lock_reclaim_stale doesn't hand the same lock to two processes" {
  # Both processes read the same dead holder and both decided to reclaim. The
  # first removed the lock and took it; the second then removed *that* one --
  # a live lock -- and took it as well, so two processes held the lock at once.
  #
  # The second process is made slow on purpose: without a stall the window is
  # a few microseconds wide and the race shows up once in a very long while,
  # which is not a test.
  local lock_path winners
  lock_path="$(dybatpho::lock_path "reclaim-race")"
  ln -s "${DEAD_PID}:$(dybatpho::lock_hostname):2020-01-01T00:00:00Z" "${lock_path}"
  winners="${BATS_TEST_TMPDIR}/race-winners"
  mkdir -p "${winners}"

  (
    # `lock_hostname` is read while the lock is being judged, so stalling it
    # holds the second process inside exactly the window that was unsafe.
    #
    # The stall goes in by renaming the original and wrapping it, rather than by
    # editing the text `declare -f` prints. Inserting a line that way needs
    # `sed '2a\ ...'`, which is GNU syntax: BSD sed wants the text on the line
    # after the `a\` and rejects the one-liner with "extra characters after \ at
    # the end of a command". On macOS the `sed` therefore failed, the stall was
    # never inserted, and the race this test exists to catch was left to be
    # decided by luck -- which is why the job passed and failed at random on the
    # same commit. Parameter expansion needs no external tool and behaves the
    # same everywhere.
    local definition
    definition="$(declare -f dybatpho::lock_hostname)"
    eval "slow_lock_hostname${definition#dybatpho::lock_hostname}"
    # Two seconds, not a fraction of one: the stall has to outlast however
    # long a loaded runner takes to get back to the foreground process below,
    # or the race is decided by scheduling rather than by the lock.
    dybatpho::lock_hostname() {
      sleep 2
      slow_lock_hostname "$@"
    }
    dybatpho::lock_acquire "reclaim-race" > /dev/null 2>&1 \
      && : > "${winners}/slow"
  ) &
  local slow_pid=$!
  sleep 0.1
  dybatpho::lock_acquire "reclaim-race" > /dev/null 2>&1 && : > "${winners}/fast"
  wait "${slow_pid}" || true

  local -a held=("${winners}"/*)
  assert_equal "${#held[@]}" "1"
  assert_equal "$(basename "${held[0]}")" "fast"

  dybatpho::lock_release "reclaim-race"
}

@test "a lock is claimed atomically, with its owner already in it" {
  local lock_path
  lock_path="$(dybatpho::lock_path "atomic-claim")"
  dybatpho::lock_acquire "atomic-claim"

  # The claim is one operation: `ln -s` fails when the name exists, and the
  # identity is in the target, so the lock is never on disk without an owner.
  # Claiming with `mkdir` and writing the pid afterwards left exactly that gap.
  [[ -L "${lock_path}" ]]
  assert_equal "$(dybatpho::lock_field "${lock_path}" pid)" "$$"
  assert_equal "$(dybatpho::lock_field "${lock_path}" host)" "$(dybatpho::lock_hostname)"
  [[ -n "$(dybatpho::lock_field "${lock_path}" acquired_at)" ]]

  dybatpho::lock_release "atomic-claim"
}

@test "a second acquire is refused while the lock is held" {
  dybatpho::lock_acquire "exclusive"
  # A fresh shell, so it is a different process asking.
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/second_acquire.sh"
  printf '%s\n' "DYBATPHO_LOCK_DIR=$(printf '%q' "${DYBATPHO_LOCK_DIR}") \
    LOG_LEVEL=fatal \
    . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules lock \
    && dybatpho::lock_acquire exclusive 0" > "${script}"
  run_traced bash "${script}"
  assert_failure
  dybatpho::lock_release "exclusive"
}

@test "dybatpho::with_lock installs a release handler and takes it away again" {
  # Run in a child shell rather than this one, and watch HUP rather than INT.
  # Bats runs tests with SIGINT *ignored*, and a shell that inherits a signal as
  # ignored cannot install a handler for it -- so `with_lock` genuinely gets no
  # INT handler under Bats, and neither would any caller that ignores it. HUP is
  # handled the same way and is not inherited ignored, so it is what this
  # asserts on. The probe is a shell function so it runs in that child and can
  # see its handlers; a command run as a program could not.
  local script="${BATS_TEST_TMPDIR}/trap_probe.sh"
  printf '%s\n' "
    export DYBATPHO_LOCK_DIR=$(printf '%q' "${DYBATPHO_LOCK_DIR}")
    export LOG_LEVEL=fatal
    . $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules lock
    probe() { printf 'during: %s\\n' \"\$(trap -p HUP)\"; }
    printf 'before: %s\\n' \"\$(trap -p HUP)\"
    dybatpho::with_lock trap-probe 1 -- probe
    printf 'after: %s\\n' \"\$(trap -p HUP)\"
  " > "${script}"
  run_traced bash "${script}"
  assert_success

  # Present while the command runs, so an interrupt during a long job releases.
  assert_line --partial "during:"
  assert_output --partial "lock_release"

  # Gone again afterwards, so calling with_lock N times does not leave N
  # handlers behind, each releasing a lock that no longer exists.
  assert_line "after: "
}

@test "a lock written by an older version is still understood" {
  # Before the atomic claim the lock was a directory of fields. A copy of the
  # library that meets one has to read it rather than treat it as free.
  local legacy_path
  legacy_path="$(dybatpho::lock_path "legacy-form")"
  mkdir "${legacy_path}"
  printf '%s' "$$" > "${legacy_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${legacy_path}/host"
  printf '%s' "2026-01-01T00:00:00Z" > "${legacy_path}/acquired_at"

  assert_equal "$(dybatpho::lock_field "${legacy_path}" pid)" "$$"
  assert_equal "$(dybatpho::lock_field "${legacy_path}" acquired_at)" "2026-01-01T00:00:00Z"
  dybatpho::lock_is_held "legacy-form"

  rm -rf "${legacy_path}"
}

@test "dybatpho::lock_semaphore_acquire hands out each slot once, then refuses" {
  local first second
  run_traced dybatpho::lock_semaphore_acquire "pool" 2 0 first
  assert_success
  assert_equal "${first}" "1"
  dybatpho::lock_semaphore_acquire "pool" 2 0 second
  assert_equal "${second}" "2"
  # A slot is a symbolic link whose target is data, so test for the link.
  [[ -L "${DYBATPHO_LOCK_DIR}/dybatpho-pool.slot1.lock" ]]

  run_traced --separate-stderr dybatpho::lock_semaphore_acquire "pool" 2
  assert_failure
  assert_stderr --partial "Could not acquire a slot of semaphore pool: all 2 are held"
  assert_stderr --partial "slot=1 pid=$$"
  assert_stderr --partial "slot=2 pid=$$"

  dybatpho::lock_semaphore_release "pool" 2
}

@test "dybatpho::lock_semaphore_acquire sets a caller variable called slot" {
  local slot
  dybatpho::lock_semaphore_acquire "pool" 3 0 slot
  assert_equal "${slot}" "1"
  dybatpho::lock_semaphore_release "pool" 3 "${slot}"
}

@test "dybatpho::lock_semaphore_acquire waits for a slot to free up" {
  dybatpho::lock_semaphore_acquire "pool" 1
  (
    sleep 0.3
    dybatpho::lock_semaphore_release "pool" 1 1
  ) &
  local releaser_pid=$!

  run_traced dybatpho::lock_semaphore_acquire "pool" 1 2
  assert_success
  wait "${releaser_pid}"
  dybatpho::lock_semaphore_release "pool" 1
}

@test "dybatpho::lock_semaphore_acquire reclaims a slot left by a dead process" {
  local slot_path="${DYBATPHO_LOCK_DIR}/dybatpho-pool.slot1.lock"
  ln -s "${DEAD_PID}:$(dybatpho::lock_hostname):2026-01-01T00:00:00Z" "${slot_path}"

  local slot
  run_traced --separate-stderr dybatpho::lock_semaphore_acquire "pool" 1 0 slot
  assert_success
  assert_stderr --partial "Reclaiming stale lock"
  assert_equal "${slot}" "1"
  dybatpho::lock_semaphore_release "pool" 1
}

@test "never more holders than slots, across concurrent processes" {
  local worker="${BATS_TEST_TMPDIR}/worker.sh"
  cat > "${worker}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules lock
export DYBATPHO_LOCK_DIR=$(printf '%q' "${DYBATPHO_LOCK_DIR}") DYBATPHO_LOCK_POLL_INTERVAL=0.05
dybatpho::with_semaphore pool 2 30 -- bash -c '
  printf "+\n" >> "\$1"
  inside=\$(grep -c + "\$1"); left=\$(grep -c - "\$1" || true)
  printf "%s\n" "\$((inside - left))" >> "\$2"
  sleep 0.2
  printf "%s\n" "-" >> "\$1"
' _ "\$1" "\$2"
SCRIPT
  local events="${BATS_TEST_TMPDIR}/events" peaks="${BATS_TEST_TMPDIR}/peaks"
  : > "${events}"
  local at
  for at in 1 2 3 4 5 6; do
    bash "${worker}" "${events}" "${peaks}" &
  done
  wait

  assert_equal "$(wc -l < "${peaks}" | tr -d ' ')" "6"
  local peak
  peak="$(sort -n "${peaks}" | tail -1)"
  ((peak >= 1 && peak <= 2))
  run_traced dybatpho::lock_semaphore_holders "pool" 2
  assert_failure
}

@test "dybatpho::lock_semaphore_release frees only the named slot or the caller's own" {
  # Long enough to outlast a slow run; it is killed at the end.
  sleep 120 &
  local foreign_pid=$!
  ln -s "${foreign_pid}:$(dybatpho::lock_hostname):2026-01-01T00:00:00Z" \
    "${DYBATPHO_LOCK_DIR}/dybatpho-pool.slot2.lock"
  dybatpho::lock_semaphore_acquire "pool" 3
  dybatpho::lock_semaphore_acquire "pool" 3

  # Without a slot number only this process's slots go; the foreign one stays.
  run_traced dybatpho::lock_semaphore_release "pool" 3
  assert_success
  run_traced dybatpho::lock_semaphore_holders "pool" 3
  assert_success
  assert_output --regexp "^slot=2 pid=${foreign_pid} "

  run_traced --separate-stderr dybatpho::lock_semaphore_release "pool" 3 2
  assert_failure
  assert_stderr --partial "is held by pid ${foreign_pid}"

  kill "${foreign_pid}" 2> /dev/null || true
  rm -f "${DYBATPHO_LOCK_DIR}/dybatpho-pool.slot2.lock"
}

@test "dybatpho::lock_semaphore_holders reports nothing for a free semaphore" {
  run_traced dybatpho::lock_semaphore_holders "idle" 4
  assert_failure
  assert_output ""
}

@test "the semaphore functions refuse a bad slot count, slot or timeout" {
  run --separate-stderr dybatpho::lock_semaphore_acquire "pool" 0
  assert_failure
  assert_stderr --partial "slot count must be a whole number from 1 to 9999, got: 0"

  run --separate-stderr dybatpho::lock_semaphore_acquire "pool" 2 soon
  assert_failure
  assert_stderr --partial "timeout must be a number of seconds, got: soon"

  run --separate-stderr dybatpho::lock_semaphore_release "pool" 2 3
  assert_failure
  assert_stderr --partial "Not a slot of pool: 3"

  run --separate-stderr dybatpho::lock_semaphore_holders "pool" many
  assert_failure
  assert_stderr --partial "got: many"
}

@test "dybatpho::with_semaphore runs the command and gives the slot back" {
  run_traced dybatpho::with_semaphore "pool" 2 1 -- bash -c 'echo ran; exit 4'
  assert_failure 4
  assert_output "ran"
  run_traced dybatpho::lock_semaphore_holders "pool" 2
  assert_failure
}

@test "dybatpho::with_semaphore fails when no slot frees up, and needs --" {
  dybatpho::lock_semaphore_acquire "pool" 1
  run_traced --separate-stderr dybatpho::with_semaphore "pool" 1 0 -- true
  assert_failure
  assert_stderr --partial "all 1 are held"
  dybatpho::lock_semaphore_release "pool" 1

  run --separate-stderr dybatpho::with_semaphore "pool" 1 0 true
  assert_failure
  assert_stderr --partial "Expected: name slots timeout -- command"

  run --separate-stderr dybatpho::with_semaphore "pool" 1 0 --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"
}
