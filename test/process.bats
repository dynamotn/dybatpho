setup() {
  load test_helper
}

@test 'dybatpho::die output' {
  local exit_code=7
  run --separate-stderr -"${exit_code}" dybatpho::die loioday "${exit_code}"
  assert_failure
  refute_output
  assert_stderr --partial "loioday"
}

@test 'dybatpho::register_err_handler output' {
  run --separate-stderr dybatpho::register_err_handler
  assert_success
  refute_output
  refute_stderr
}

@test 'dybatpho::register_killed_handler output' {
  run --separate-stderr dybatpho::register_killed_handler
  assert_success
  refute_output
  refute_stderr
}

@test 'dybatpho::register_common_handlers output' {
  run --separate-stderr dybatpho::register_common_handlers
  assert_success
  refute_output
  refute_stderr
}

@test 'dybatpho::register_common_handlers installs traps in the current shell' {
  dybatpho::register_common_handlers
  local err_trap sigint_trap sigterm_trap
  err_trap="$(trap -p ERR)"
  sigint_trap="$(trap -p SIGINT)"
  sigterm_trap="$(trap -p SIGTERM)"
  # Restore the default traps before asserting so a failure can't loop back in.
  trap - ERR SIGINT SIGTERM
  set +E

  assert_equal "${DYBATPHO_USED_ERR_HANDLER}" "true"
  assert_equal "${DYBATPHO_USED_KILLED_HANDLER}" "true"
  assert_regex "${err_trap}" "run_err_handler"
  # A signal inherited as ignored (bats --jobs does this) can't be trapped again.
  if [[ "${sigint_trap}" != *"-- ''"* ]]; then
    assert_regex "${sigint_trap}" "killed_process_handler SIGINT"
    assert_regex "${sigterm_trap}" "killed_process_handler SIGTERM"
  fi
}

@test 'dybatpho::run_err_handler output' {
  local exit_code=7
  run --separate-stderr -"${exit_code}" dybatpho::run_err_handler "${exit_code}"
  assert_failure
  refute_output
  assert_stderr
}

@test 'dybatpho::killed_process_handler output' {
  run --separate-stderr dybatpho::killed_process_handler SIGTERM
  assert_failure
  refute_output
  assert_stderr

  run --separate-stderr dybatpho::killed_process_handler SIGINT
  assert_failure
  refute_output
  assert_stderr
}

@test 'dybatpho::trap on exit' {
  run --separate-stderr dybatpho::trap 'echo 2; echo 3' ERR EXIT
  assert_success
  assert_line --index 0 2
  assert_line --index 1 3
  refute_stderr
}

@test 'dybatpho::trap preserves existing trap handlers' {
  # shellcheck disable=2329
  _trap_chain() {
    trap 'echo first' EXIT
    dybatpho::trap 'echo second' EXIT
  }
  # The chained EXIT trap must fire in a subshell, so keep the isolating `run`.
  run _trap_chain
  assert_success
  assert_line --index 0 first
  assert_line --index 1 second
}

@test 'dybatpho::cleanup_file_on_exit action' {
  # Just test that function runs without error and registers trap
  local filepath="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  run --separate-stderr dybatpho::cleanup_file_on_exit "${filepath}"
  assert_success
  refute_output
  refute_stderr

  # Cleanup is triggered on EXIT, file may or may not be deleted immediately
  # Verify cleanup script was created
  local cleanup_scripts=$(ls /tmp/dybatpho_cleanup-*.sh 2> /dev/null | wc -l)
  [[ "${cleanup_scripts}" -gt 0 ]]
}

@test 'dybatpho::cleanup_file_on_exit removes file on shell exit' {
  local filepath="${BATS_TEST_TMPDIR}/cleanup-me"
  # shellcheck disable=2329
  _register_cleanup() {
    local file="$1"
    touch "${file}"
    dybatpho::cleanup_file_on_exit "${file}"
    echo "${file}"
  }
  run _register_cleanup "${filepath}"
  assert_success
  assert_output "${filepath}"
  assert_file_not_exist "${filepath}"
}

@test 'dybatpho::cleanup_file_on_exit leaves the Bats reporter on EXIT alone' {
  # Bats reports a test result from its own EXIT trap. Replacing that trap in
  # the test shell hid every failure in every test that made a temporary file:
  # the test vanished from the report and the run ended with "Executed N-1
  # instead of N tests", which reads as a dead worker rather than a failure.
  local before after
  before="$(trap -p EXIT)"
  assert_regex "${before}" 'bats_teardown_trap'

  dybatpho::cleanup_file_on_exit "${BATS_TEST_TMPDIR}/never-created"

  after="$(trap -p EXIT)"
  assert_equal "${after}" "${before}"
}

@test 'dybatpho::cleanup_file_on_exit still cleans up when a subshell ends' {
  # The other half of the rule: a subshell has no reporter to protect, and its
  # exit is the only chance to remove what it registered.
  local marker="${BATS_TEST_TMPDIR}/subshell-path"
  (
    local scratch
    dybatpho::create_temp scratch ".txt" "subshell-cleanup"
    printf '%s' "${scratch}" > "${marker}"
    [[ -f "${scratch}" ]]
  )
  assert_file_not_exist "$(cat "${marker}")"
}

@test 'dybatpho::cleanup_file_on_exit removes directory on shell exit' {
  local dirpath="${BATS_TEST_TMPDIR}/cleanup-dir"
  _register_cleanup_dir() {
    local dir="$1"
    mkdir -p "${dir}"
    dybatpho::cleanup_file_on_exit "${dir}"
    echo "${dir}"
  }
  assert_equal "$(_register_cleanup_dir "${dirpath}")" "${dirpath}"
  [[ ! -e "${dirpath}" ]]
}

@test 'dybatpho::cleanup_file_on_exit removes a path containing spaces' {
  local target="${BATS_TEST_TMPDIR}/dir with space"
  mkdir -p "${target}"
  # A `bash -c` shell has an empty `BASH_SOURCE`, which the kcov hook expands on
  # every command and `set -u` then turns into a failure that shows up only
  # under `scripts/test.sh --coverage`. Spawn from a script file instead.
  local script="${BATS_TEST_TMPDIR}/cleanup_spaces.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::cleanup_file_on_exit "${2}"
SCRIPT
  bash "${script}" "${DYBATPHO_DIR}" "${target}"
  assert_dir_not_exist "${target}"
}

@test 'dybatpho::cleanup_file_on_exit installs one trap for many paths' {
  local first="${BATS_TEST_TMPDIR}/first" second="${BATS_TEST_TMPDIR}/second"
  touch "${first}" "${second}"
  # Every registration used to append its own command, so the trap grew with
  # each temporary file. It is now a single call into the path registry.
  local script="${BATS_TEST_TMPDIR}/cleanup_one_trap.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::cleanup_file_on_exit "${2}"
dybatpho::cleanup_file_on_exit "${3}"
trap -p EXIT
SCRIPT
  run bash "${script}" "${DYBATPHO_DIR}" "${first}" "${second}"
  assert_success
  assert_equal "$(printf '%s\n' "${output}" | grep -c '__dybatpho_cleanup_run')" "1"
}

@test 'dybatpho::cleanup_file_on_exit leaves paths registered by another shell alone' {
  local outer="${BATS_TEST_TMPDIR}/outer"
  touch "${outer}"
  # The subshell inherits the registry, so it must remove only what it
  # registered itself; the parent still needs `outer`.
  local script="${BATS_TEST_TMPDIR}/cleanup_other_shell.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::cleanup_file_on_exit "${2}"
(:)
[[ -e "${2}" ]] || {
  echo 'removed too early'
  exit 1
}
SCRIPT
  run bash "${script}" "${DYBATPHO_DIR}" "${outer}"
  assert_success
  assert_file_not_exist "${outer}"
}

@test "dybatpho::dry_run with DRY_RUN=true should print dry run message and not execute command" {
  # shellcheck disable=2030
  export DRY_RUN="true"
  local test_file="dry_run_test_file.tmp"
  rm -f "${test_file}"
  run dybatpho::dry_run touch "${test_file}"
  assert_output --partial "DRY RUN: touch ${test_file}"
  assert_file_not_exist "${test_file}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=true displays args with spaces as single quoted tokens" {
  # shellcheck disable=2030
  export DRY_RUN="true"
  run_traced dybatpho::dry_run curl -H "Authorization: Bearer token"
  assert_output --partial "DRY RUN:"
  # The header value must be shell-quoted as a single token (printf %q uses backslash escaping)
  assert_output --partial "Authorization:"
  assert_output --partial "Bearer"
  # All parts must appear on the same line, not split across lines
  local line
  while IFS= read -r line; do
    if [[ "${line}" == *"Authorization:"* ]]; then
      [[ "${line}" == *"Bearer"* ]] || {
        echo "header value was split across lines"
        return 1
      }
    fi
  done <<< "${output}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=false preserves argument quoting during execution" {
  # shellcheck disable=2031
  export DRY_RUN="false"
  # Use printf to write args one-per-line; verify "hello world" stays as one arg
  local temp_file="${BATS_TEST_TMPDIR}/dry_run_exec"
  assert_equal "$(dybatpho::dry_run bash -c "printf '%s\n' \"\$@\"" -- "hello world" "second")" "$(printf 'hello world\nsecond')"

  # A single argument is evaluated as a shell command string.
  assert_equal "$(dybatpho::dry_run "printf 'evaluated\n'")" "evaluated"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=false should execute command and produce no dry run output" {
  # shellcheck disable=2031
  export DRY_RUN="false"
  local test_file="actual_run_test_file.tmp"
  rm -f "${test_file}"
  run dybatpho::dry_run touch "${test_file}"
  assert_output ""
  refute_output --regexp "DRY RUN:"
  assert_file_exist "${test_file}"
  rm -f "${test_file}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN unset should error" {
  unset DRY_RUN
  local test_file="unset_dry_run_test_file.tmp"
  rm -f "${test_file}"
  run dybatpho::dry_run touch "${test_file}"
  assert_failure
}

# --- dybatpho::run_with_timeout -------------------------------------------

@test "dybatpho::run_with_timeout returns the command's own exit code when it finishes in time" {
  local status=0
  run_traced dybatpho::run_with_timeout 5 bash -c 'printf "in time\n"; exit 0'
  assert_success
  assert_output "in time"

  status=0
  dybatpho::run_with_timeout 5 bash -c 'exit 3' || status=$?
  assert_equal "${status}" 3
}

@test "dybatpho::run_with_timeout reports 124 when the command outlives the limit" {
  local status=0
  dybatpho::run_with_timeout 1 sleep 30 || status=$?
  assert_equal "${status}" 124
}

@test "dybatpho::run_with_timeout runs a shell function, which the timeout binary cannot" {
  # `timeout` executes a program, so it can never see a function the caller
  # defined; the Bash watchdog is what makes this work.
  __dybatpho_test_slow() { sleep 30; }
  __dybatpho_test_quick() { printf 'called with %s\n' "$1"; }

  local status=0
  dybatpho::run_with_timeout 1 __dybatpho_test_slow || status=$?
  assert_equal "${status}" 124

  run_traced dybatpho::run_with_timeout 5 __dybatpho_test_quick argument
  assert_success
  assert_output "called with argument"
}

@test "dybatpho::run_with_timeout without the timeout binary behaves the same" {
  # The fallback is the path macOS takes by default, where coreutils is absent,
  # so it is exercised explicitly rather than left to the runner's toolbox.
  __dybatpho_process_timeout_probe=no

  local status=0
  dybatpho::run_with_timeout 1 sleep 30 || status=$?
  assert_equal "${status}" 124

  run_traced dybatpho::run_with_timeout 5 bash -c 'printf "fallback\n"'
  assert_success
  assert_output "fallback"

  status=0
  dybatpho::run_with_timeout 5 bash -c 'exit 7' || status=$?
  assert_equal "${status}" 7
}

@test "dybatpho::run_with_timeout leaves a BusyBox timeout to the watchdog" {
  # BusyBox `timeout` takes `-k` but reports a timeout as 143, so accepting it
  # would break the 124 this helper promises.
  local bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin}"
  printf '#!/bin/sh\n[ "$1" = --version ] && exit 1\nexit 0\n' > "${bin}/timeout"
  chmod +x "${bin}/timeout"

  __dybatpho_process_timeout_probe=""
  PATH="${bin}:${PATH}" run __dybatpho_process_has_timeout
  assert_failure
}

@test "dybatpho::run_with_timeout does not mistake exit code 143 for a timeout" {
  # A command that chooses to exit 143 looks exactly like one killed by
  # SIGTERM, which is why the watchdog reports a timeout through a marker file
  # rather than through the exit status.
  __dybatpho_process_timeout_probe=no
  local status=0
  dybatpho::run_with_timeout 5 bash -c 'exit 143' || status=$?
  assert_equal "${status}" 143
}

@test "dybatpho::run_with_timeout ends the processes the command started" {
  # Ending the job alone would orphan its children, which is how a "killed"
  # build leaves a compiler running.
  __dybatpho_process_timeout_probe=no
  local pid_file="${BATS_TEST_TMPDIR}/grandchild.pid"
  __dybatpho_test_nest() {
    bash -c "printf '%s\n' \"\$\$\" > '${pid_file}'; sleep 30" &
    wait
  }

  local status=0
  dybatpho::run_with_timeout 1 __dybatpho_test_nest || status=$?
  assert_equal "${status}" 124

  local grandchild
  grandchild="$(< "${pid_file}")"
  # The kill is asynchronous, so give it a moment before asking.
  sleep 1
  run kill -0 "${grandchild}"
  assert_failure
}

@test "dybatpho::run_with_timeout with a limit of 0 runs without a limit" {
  run_traced dybatpho::run_with_timeout 0 bash -c 'printf "unbounded\n"'
  assert_success
  assert_output "unbounded"
}

@test "dybatpho::run_with_timeout rejects a limit that is not a number and a missing command" {
  run dybatpho::run_with_timeout abc true
  assert_failure
  assert_output --partial "non-negative integer"

  run dybatpho::run_with_timeout 5
  assert_failure
  assert_output --partial "Expected: seconds command"

  DYBATPHO_TIMEOUT_KILL_AFTER="soon" run dybatpho::run_with_timeout 5 true
  assert_failure
  assert_output --partial "DYBATPHO_TIMEOUT_KILL_AFTER"
}

# --- background jobs ------------------------------------------------------

@test "dybatpho::background_run records a job that dybatpho::wait_all reaps by name" {
  __dybatpho_test_ok() { return 0; }
  __dybatpho_test_bad() { return 4; }

  dybatpho::background_run first __dybatpho_test_ok
  dybatpho::background_run second __dybatpho_test_bad

  run_traced dybatpho::background_pid first
  assert_success
  assert_output --regexp '^[0-9]+$'

  # An exit code exists only once the job has been waited for.
  run dybatpho::background_status first
  assert_failure

  local status=0
  dybatpho::wait_all || status=$?
  assert_equal "${status}" 1

  run_traced dybatpho::background_status first
  assert_output "0"
  run_traced dybatpho::background_status second
  assert_output "4"
}

@test "dybatpho::wait_all succeeds when every job succeeded and when there are none" {
  local status=0
  dybatpho::wait_all || status=$?
  assert_equal "${status}" 0

  __dybatpho_test_ok() { return 0; }
  dybatpho::background_run only __dybatpho_test_ok
  status=0
  dybatpho::wait_all || status=$?
  assert_equal "${status}" 0
}

@test "dybatpho::background_pid and dybatpho::background_status fail for an unknown job" {
  run dybatpho::background_pid nosuch
  assert_failure
  refute_output
  run dybatpho::background_status nosuch
  assert_failure
  refute_output
}

@test "dybatpho::background_run refuses an invalid name, a missing command and a running duplicate" {
  run dybatpho::background_run '1bad' true
  assert_failure
  assert_output --partial "Invalid job name"

  run dybatpho::background_run lonely
  assert_failure
  assert_output --partial "Expected: name command"

  dybatpho::background_run busy sleep 30
  run dybatpho::background_run busy sleep 30
  assert_failure
  assert_output --partial "already running"
  dybatpho::kill_children
}

@test "dybatpho::background_run reuses a name once its job has been reaped" {
  __dybatpho_test_ok() { return 0; }
  dybatpho::background_run again __dybatpho_test_ok
  dybatpho::wait_all
  dybatpho::background_run again __dybatpho_test_ok
  dybatpho::wait_all
  # The name keeps its single place in the order rather than being listed twice.
  assert_equal "${#DYBATPHO_BACKGROUND_NAMES[@]}" 1
  run_traced dybatpho::background_status again
  assert_output "0"
}

@test "dybatpho::kill_children ends every background job and empties the registry" {
  dybatpho::background_run sleeper sleep 30
  local pid
  pid="$(dybatpho::background_pid sleeper)"

  dybatpho::kill_children
  assert_equal "${#DYBATPHO_BACKGROUND_NAMES[@]}" 0
  assert_equal "${#DYBATPHO_BACKGROUND_PIDS[@]}" 0

  run kill -0 "${pid}"
  assert_failure
}

@test "dybatpho::kill_children ends the processes a background job started" {
  local pid_file="${BATS_TEST_TMPDIR}/bg_grandchild.pid"
  __dybatpho_test_nest() {
    bash -c "printf '%s\n' \"\$\$\" > '${pid_file}'; sleep 30" &
    wait
  }
  dybatpho::background_run nested __dybatpho_test_nest
  # Wait for the grandchild to record itself before ending the job.
  local waited=0
  while [[ ! -s "${pid_file}" ]] && ((waited < 5)); do
    sleep 1
    waited=$((waited + 1))
  done

  dybatpho::kill_children
  sleep 1
  run kill -0 "$(< "${pid_file}")"
  assert_failure
}

@test "dybatpho::kill_children is safe to call when no job was ever started" {
  run dybatpho::kill_children
  assert_success
  refute_output
}

# --- PID files ------------------------------------------------------------

@test "dybatpho::pid_file_write records a process id, creating the directory it needs" {
  local pid_file="${BATS_TEST_TMPDIR}/run/app.pid"
  dybatpho::pid_file_write "${pid_file}"
  assert_file_exist "${pid_file}"
  assert_equal "$(< "${pid_file}")" "$$"

  dybatpho::pid_file_write "${pid_file}" 4242
  assert_equal "$(< "${pid_file}")" "4242"
  # The staging file used for the atomic move must not be left behind.
  run bash -c "ls '${BATS_TEST_TMPDIR}/run' | grep -c tmp"
  assert_output "0"
}

@test "dybatpho::pid_file_write rejects something that is not a process id" {
  run dybatpho::pid_file_write "${BATS_TEST_TMPDIR}/bad.pid" "not-a-pid"
  assert_failure
  assert_output --partial "positive integer"
}

@test "dybatpho::pid_file_is_running answers for a live, a dead, a malformed and a missing file" {
  local pid_file="${BATS_TEST_TMPDIR}/state.pid"

  dybatpho::pid_file_write "${pid_file}"
  run dybatpho::pid_file_is_running "${pid_file}"
  assert_success

  # A process id that is valid but has long since exited.
  printf '%s\n' "99999999" > "${pid_file}"
  run dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  printf '%s\n' "garbage" > "${pid_file}"
  run dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  : > "${pid_file}"
  run dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  run dybatpho::pid_file_is_running "${BATS_TEST_TMPDIR}/absent.pid"
  assert_failure
}

@test "dybatpho::pid_file_is_running tolerates the padding a foreign PID file may carry" {
  local pid_file="${BATS_TEST_TMPDIR}/padded.pid"
  printf ' %s \n' "$$" > "${pid_file}"
  run dybatpho::pid_file_is_running "${pid_file}"
  assert_success
}

@test "dybatpho::pid_file_remove leaves a file that records another process alone" {
  local pid_file="${BATS_TEST_TMPDIR}/owned.pid"
  dybatpho::pid_file_write "${pid_file}" 4242

  # The guard is what stops an exiting service from deleting the PID file its
  # replacement has already written.
  run dybatpho::pid_file_remove "${pid_file}"
  assert_failure
  assert_file_exist "${pid_file}"

  run dybatpho::pid_file_remove "${pid_file}" 4242
  assert_success
  assert_file_not_exist "${pid_file}"

  # Removing a file that is already gone is not a failure.
  run dybatpho::pid_file_remove "${pid_file}"
  assert_success
}
