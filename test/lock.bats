setup() {
  load test_helper
  export DYBATPHO_LOCK_DIR="${BATS_TEST_TMPDIR}"
  export DYBATPHO_LOCK_POLL_INTERVAL="0.1"
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
  run dybatpho::lock_acquire "acquire-test"
  assert_success

  run dybatpho::lock_is_held "acquire-test"
  assert_success

  dybatpho::lock_release "acquire-test"
}

@test "dybatpho::lock_acquire fails fast without waiting when already held" {
  dybatpho::lock_acquire "busy"

  run --separate-stderr dybatpho::lock_acquire "busy"
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

  run dybatpho::lock_acquire "waiter" 2
  assert_success
  wait "${releaser_pid}"
  dybatpho::lock_release "waiter"
}

@test "dybatpho::lock_acquire waits up to the timeout then fails when still held" {
  dybatpho::lock_acquire "still-busy"
  run --separate-stderr dybatpho::lock_acquire "still-busy" 1
  assert_failure
  dybatpho::lock_release "still-busy"
}

@test "dybatpho::lock_info prints the current holder metadata" {
  dybatpho::lock_acquire "info-test"
  run dybatpho::lock_info "info-test"
  assert_success
  assert_output --partial "pid=$$"
  assert_output --partial "host=$(dybatpho::lock_hostname)"
  assert_output --partial "acquired_at="
  dybatpho::lock_release "info-test"
}

@test "dybatpho::lock_info fails when the lock isn't held" {
  run dybatpho::lock_info "never-acquired"
  assert_failure
  refute_output
}

@test "dybatpho::lock_release removes a lock held by the current process" {
  dybatpho::lock_acquire "release-test"
  run dybatpho::lock_release "release-test"
  assert_success
  run dybatpho::lock_is_held "release-test"
  assert_failure
}

@test "dybatpho::lock_release is a no-op when the lock was never held" {
  run dybatpho::lock_release "never-held"
  assert_success
}

@test "dybatpho::lock_release refuses to remove a lock held by another live process" {
  sleep 5 &
  local foreign_pid=$!

  local lock_path
  lock_path="$(dybatpho::lock_path "foreign")"
  mkdir "${lock_path}"
  printf '%s' "${foreign_pid}" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run --separate-stderr dybatpho::lock_release "foreign"
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
  # 999999 is exceedingly unlikely to be a running pid in the test environment.
  printf '%s' "999999" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run --separate-stderr dybatpho::lock_acquire "stale"
  assert_success
  assert_stderr --partial "Reclaiming stale lock"
  dybatpho::lock_release "stale"
}

@test "dybatpho::with_lock runs the command while holding the lock and releases it after" {
  run dybatpho::with_lock "with-lock-test" 1 -- bash -c 'echo ran'
  assert_success
  assert_output "ran"
  run dybatpho::lock_is_held "with-lock-test"
  assert_failure
}

@test "dybatpho::with_lock releases the lock even when the command fails" {
  run dybatpho::with_lock "with-lock-fail" 1 -- bash -c 'exit 5'
  assert_failure 5
  run dybatpho::lock_is_held "with-lock-fail"
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

  run dybatpho::lock_is_alive "${lock_path}"
  assert_success

  dybatpho::lock_release "alive-test"

  run dybatpho::lock_is_alive "${lock_path}"
  assert_failure
}

@test "dybatpho::lock_is_alive is false for a dead pid but true for another host" {
  local lock_path
  lock_path="$(dybatpho::lock_path "alive-dead")"
  mkdir "${lock_path}"
  # 999999 is exceedingly unlikely to be a running pid in the test environment.
  printf '%s' "999999" > "${lock_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${lock_path}/host"

  run dybatpho::lock_is_alive "${lock_path}"
  assert_failure

  # A lock recorded on another host can't be probed locally, so it counts as held.
  printf '%s' "some-other-host" > "${lock_path}/host"
  run dybatpho::lock_is_alive "${lock_path}"
  assert_success

  rm -rf "${lock_path}"
}

@test "dybatpho::lock_reclaim_stale removes a dead lock and leaves a live one alone" {
  local stale_path live_path
  stale_path="$(dybatpho::lock_path "reclaim-stale")"
  mkdir "${stale_path}"
  printf '%s' "999999" > "${stale_path}/pid"
  printf '%s' "$(dybatpho::lock_hostname)" > "${stale_path}/host"

  run --separate-stderr dybatpho::lock_reclaim_stale "${stale_path}"
  assert_success
  assert_stderr --partial "Reclaiming stale lock"
  assert_dir_not_exist "${stale_path}"

  live_path="$(dybatpho::lock_path "reclaim-live")"
  dybatpho::lock_acquire "reclaim-live"
  run dybatpho::lock_reclaim_stale "${live_path}"
  assert_success
  # The assertion is that the lock is still held, not what it looks like on
  # disk: the claim is a symbolic link now, and that is an implementation
  # detail this test has no business pinning.
  dybatpho::lock_is_held "reclaim-live"

  dybatpho::lock_release "reclaim-live"
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
  run bash "${script}"
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
  run bash "${script}"
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
