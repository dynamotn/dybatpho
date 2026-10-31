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
  run_traced --separate-stderr dybatpho::register_err_handler
  assert_success
  refute_output
  refute_stderr
}

@test 'dybatpho::register_killed_handler output' {
  run_traced --separate-stderr dybatpho::register_killed_handler
  assert_success
  refute_output
  refute_stderr
}

@test 'dybatpho::register_common_handlers output' {
  run_traced --separate-stderr dybatpho::register_common_handlers
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

@test 'dybatpho::run_err_handler exits with the failing status and the whole stack' {
  # The frame counter was advanced with `((i++))`, which fails when it is 0,
  # so the handler stopped after the first frame and the script exited 1
  # instead of with the status of the command that failed.
  local script="${BATS_TEST_TMPDIR}/err.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh" \
    'dybatpho::register_err_handler' \
    'inner() { (exit 7); }' \
    'middle() { inner; }' \
    'outer() { middle; }' \
    'outer' > "${script}"
  run --separate-stderr bash "${script}"
  assert_equal "${status}" 7
  assert_stderr --partial "Aborting on error 7:"
  assert_stderr --partial " inner "
  assert_stderr --partial " middle "
  assert_stderr --partial " outer "
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

@test 'dybatpho::killed_process_handler still runs the EXIT handlers' {
  # The handler cleared EXIT along with the signals, so every EXIT handler
  # composed through `dybatpho::trap` was skipped on Ctrl-C or TERM: temporary
  # files stayed behind, and a full-screen script left the terminal raw.
  local script="${BATS_TEST_TMPDIR}/killed.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::register_killed_handler
# A signal inherited as ignored (bats --jobs does this) can't be trapped.
[[ "$(trap -p "SIG${3}")" == *killed_process_handler* ]] || exit 99
dybatpho::cleanup_file_on_exit "${2}"
kill -"${3}" "$$"
sleep 5
SCRIPT
  local signal code file
  for signal in TERM INT; do
    file="${BATS_TEST_TMPDIR}/left-by-${signal}"
    touch "${file}"
    code=0
    bash "${script}" "${DYBATPHO_DIR}" "${file}" "${signal}" 2> /dev/null || code=$?
    [[ "${code}" == 99 ]] && continue
    if [[ "${signal}" == TERM ]]; then
      assert_equal "${code}" 143
    else
      assert_equal "${code}" 130
    fi
    assert_file_not_exist "${file}"
  done
}

@test 'dybatpho::trap on exit' {
  run --separate-stderr dybatpho::trap 'echo 2; echo 3' ERR EXIT
  assert_success
  assert_line --index 0 2
  assert_line --index 1 3
  refute_stderr
}

@test 'dybatpho::trap preserves existing trap handlers' {
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

@test 'dybatpho::trap keeps an existing handler that contains quotes' {
  # The existing handler was read by cutting `trap -p` at its first and last
  # quote, which left a quote inside it in its escaped `'\''` form, so the
  # handler put back was a different command from the one it replaced.
  _trap_quoted() {
    trap "printf '%s\\n' \"it's here\"" EXIT
    dybatpho::trap 'echo second' EXIT
  }
  run _trap_quoted
  assert_success
  assert_line --index 0 "it's here"
  assert_line --index 1 second
}

@test 'dybatpho::trap leaves the parent EXIT handler out of a subshell' {
  # A subshell lists its parent's handlers without running them, and appending
  # to that text made the parent's cleanup run when `$(...)` created a
  # temporary file: the work directory was gone before the parent used it.
  # Run as a plain script, because Bats replaces the subshell trap itself.
  local script="${BATS_TEST_TMPDIR}/inherited.sh" work="${BATS_TEST_TMPDIR}/work"
  mkdir "${work}"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::trap "rm -rf -- '${2}'" EXIT
function make_scratch {
  local scratch
  dybatpho::create_temp scratch ".txt"
  printf 'made'
}
captured="$(make_scratch)"
[[ -d "${2}" ]] && printf '%s, kept\n' "${captured}"
SCRIPT
  run bash "${script}" "${DYBATPHO_DIR}" "${work}"
  assert_success
  assert_output "made, kept"
  assert_file_not_exist "${work}"
}

@test 'dybatpho::trap drops the parent EXIT handler when the spare signals start ignored' {
  # A signal ignored at start is listed in a subshell, so no spare was free,
  # nothing was reset and the parent's cleanup ran in `$(...)` again.
  local script="${BATS_TEST_TMPDIR}/ignored.sh" work="${BATS_TEST_TMPDIR}/work"
  mkdir "${work}"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::trap "rm -rf -- '${2}'" EXIT
captured="$(dybatpho::trap ':' USR1 && printf 'made')"
[[ -d "${2}" ]] && printf '%s, kept\n' "${captured}"
SCRIPT
  run bash -c 'trap "" SYS XCPU XFSZ VTALRM PROF; exec bash "$@"' _ "${script}" "${DYBATPHO_DIR}" "${work}"
  assert_success
  assert_output "made, kept"
}

@test '__dybatpho_process_traps_save_into skips the handlers a subshell inherited' {
  # Saved inside `$(...)` and run back, the parent's listed TERM handler came
  # alive there: the subshell survived a TERM by running the parent's handler.
  local script="${BATS_TEST_TMPDIR}/saved.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
trap 'printf "parent handler "' TERM
captured="$(
  __dybatpho_process_traps_save_into saved INT TERM
  __dybatpho_process_traps_restore "${saved}" INT TERM
  kill -TERM "${BASHPID}"
  printf 'survived'
)" || true
printf '[%s]\n' "${captured}"
SCRIPT
  run bash "${script}" "${DYBATPHO_DIR}"
  assert_success
  assert_output "[]"
}

@test 'dybatpho::trap does not leak its loop variable' {
  local signal=kept
  dybatpho::trap ':' USR1
  trap - USR1
  assert_equal "${signal}" kept
  unset signal
  dybatpho::trap ':' USR2
  trap - USR2
  [[ ! -v signal ]]
}

@test 'saved trap handlers come back exactly, and an empty one stays empty' {
  trap "printf '%s\\n' \"it's USR1\"" USR1
  trap - USR2
  local saved before_usr1
  before_usr1="$(trap -p USR1)"
  __dybatpho_process_traps_save_into saved USR1 USR2

  dybatpho::trap 'echo added' USR1 USR2
  __dybatpho_process_traps_restore "${saved}" USR1 USR2

  assert_equal "$(trap -p USR1)" "${before_usr1}"
  assert_equal "$(trap -p USR2)" ""
  trap - USR1
}

@test 'dybatpho::cleanup_file_on_exit action' {
  # The call itself must stay quiet, and it must remember the path.
  local filepath
  filepath="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  run_traced --separate-stderr dybatpho::cleanup_file_on_exit "${filepath}"
  assert_success
  refute_output
  refute_stderr

  # Registering happens in the calling shell, and `run` uses a subshell, so
  # register once more here to inspect what the current shell kept: the path,
  # tagged with this shell's pid. Removal on EXIT is covered by the next test.
  dybatpho::cleanup_file_on_exit "${filepath}"
  assert_equal \
    "${DYBATPHO_CLEANUP_PATHS[$((${#DYBATPHO_CLEANUP_PATHS[@]} - 1))]}" \
    "${BASHPID}:${filepath}"
}

@test 'dybatpho::cleanup_file_on_exit removes file on shell exit' {
  local filepath="${BATS_TEST_TMPDIR}/cleanup-me"
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
  run_traced bash "${script}" "${DYBATPHO_DIR}" "${first}" "${second}"
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
  run_traced bash "${script}" "${DYBATPHO_DIR}" "${outer}"
  assert_success
  assert_file_not_exist "${outer}"
}

@test "dybatpho::dry_run with DRY_RUN=true should print dry run message and not execute command" {
  export DRY_RUN="true"
  local test_file="dry_run_test_file.tmp"
  rm -f "${test_file}"
  run_traced dybatpho::dry_run touch "${test_file}"
  assert_output --partial "DRY RUN: touch ${test_file}"
  assert_file_not_exist "${test_file}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=true displays args with spaces as single quoted tokens" {
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
  export DRY_RUN="false"
  # Use printf to write args one-per-line; verify "hello world" stays as one arg
  local temp_file="${BATS_TEST_TMPDIR}/dry_run_exec"
  assert_equal "$(dybatpho::dry_run bash -c "printf '%s\n' \"\$@\"" -- "hello world" "second")" "$(printf 'hello world\nsecond')"

  # A single argument is evaluated as a shell command string.
  assert_equal "$(dybatpho::dry_run "printf 'evaluated\n'")" "evaluated"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=false should execute command and produce no dry run output" {
  export DRY_RUN="false"
  local test_file="actual_run_test_file.tmp"
  rm -f "${test_file}"
  run_traced dybatpho::dry_run touch "${test_file}"
  assert_output ""
  refute_output --regexp "DRY RUN:"
  assert_file_exist "${test_file}"
  rm -f "${test_file}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN unset runs the command" {
  # Nothing is assigned when the library loads, so an unset switch is simply
  # off rather than an unbound variable under `set -u`.
  unset DRY_RUN DYBATPHO_DRY_RUN
  local test_file="${BATS_TEST_TMPDIR}/unset_dry_run_test_file.tmp"
  run_traced dybatpho::dry_run touch "${test_file}"
  assert_success
  refute_output --partial "DRY RUN"
  assert_file_exist "${test_file}"
}

@test "dry-run mode reads DYBATPHO_DRY_RUN first and DRY_RUN as a fallback" {
  unset DRY_RUN DYBATPHO_DRY_RUN
  local test_file="${BATS_TEST_TMPDIR}/fallback.tmp"
  DRY_RUN=true run_traced dybatpho::dry_run -- touch "${test_file}"
  assert_output --partial "DRY RUN"
  assert_file_not_exist "${test_file}"

  DYBATPHO_DRY_RUN=true DRY_RUN=false run_traced dybatpho::dry_run -- touch "${test_file}"
  assert_output --partial "DRY RUN"
  assert_file_not_exist "${test_file}"

  DYBATPHO_DRY_RUN=false DRY_RUN=true run_traced dybatpho::dry_run -- touch "${test_file}"
  refute_output --partial "DRY RUN"
  assert_file_exist "${test_file}"
}

# --- dybatpho::run_with_timeout -------------------------------------------

@test "dybatpho::run_with_timeout returns the command's own exit code when it finishes in time" {
  local status=0
  run_traced dybatpho::run_with_timeout 60 bash -c 'printf "in time\n"; exit 0'
  assert_success
  assert_output "in time"

  status=0
  dybatpho::run_with_timeout 60 bash -c 'exit 3' || status=$?
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

  run_traced dybatpho::run_with_timeout 60 __dybatpho_test_quick argument
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

  run_traced dybatpho::run_with_timeout 60 bash -c 'printf "fallback\n"'
  assert_success
  assert_output "fallback"

  status=0
  dybatpho::run_with_timeout 60 bash -c 'exit 7' || status=$?
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
  dybatpho::run_with_timeout 60 bash -c 'exit 143' || status=$?
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
  assert_process_dead "${grandchild}"
}

@test "dybatpho::run_with_timeout kills a grandchild that ignores SIGTERM" {
  # The watchdog was cut off as soon as the command itself had gone, so a
  # process it started that ignored SIGTERM never got the SIGKILL.
  __dybatpho_process_timeout_probe=no
  local pid_file="${BATS_TEST_TMPDIR}/stubborn-grandchild.pid"
  __dybatpho_test_stubborn_nest() {
    bash -c "trap '' TERM; printf '%s\n' \"\$\$\" > '${pid_file}'; sleep 30" &
    wait
  }

  local status=0
  DYBATPHO_TIMEOUT_KILL_AFTER=1 dybatpho::run_with_timeout 1 __dybatpho_test_stubborn_nest || status=$?
  assert_equal "${status}" 124
  sleep 1
  assert_process_dead "$(< "${pid_file}")"
}

@test "dybatpho::run_with_timeout with no grace kills a stubborn program at once" {
  # `timeout -k 0` turns SIGKILL off, so a program ignoring SIGTERM ran to its
  # end on the `timeout` path, while the Bash path killed it at once.
  __dybatpho_process_has_timeout || skip "no coreutils timeout"
  local status=0
  SECONDS=0
  DYBATPHO_TIMEOUT_KILL_AFTER=0 dybatpho::run_with_timeout 1 bash -c "trap '' TERM; sleep 8" || status=$?
  # `timeout` reports the SIGKILL it had to send as 137.
  [[ "${status}" == 124 || "${status}" == 137 ]] || fail "unexpected status ${status}"
  ((SECONDS < 5)) || fail "the program ran for ${SECONDS}s"
}

@test "dybatpho::run_with_timeout returns at once inside a command substitution" {
  # The watchdog's `sleep` outlived the watchdog and held the substitution's
  # pipe open, so a function that returned at once still took the whole limit.
  __dybatpho_process_timeout_probe=no
  __dybatpho_test_quick() { printf 'quick\n'; }
  local answer
  SECONDS=0
  answer="$(dybatpho::run_with_timeout 20 __dybatpho_test_quick)"
  assert_equal "${answer}" "quick"
  ((SECONDS < 10)) || fail "the substitution took ${SECONDS}s"
}

@test "dybatpho::run_with_timeout leaves the caller's EXIT trap to the caller" {
  # A command that returns at once has its watchdog ended moments after the
  # fork, and a subshell that SIGTERM reaches that early still runs the EXIT
  # trap it inherited: the caller's cleanup ran again in the watchdog.
  #
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/exit-trap.sh" log="${BATS_TEST_TMPDIR}/exit-trap.log"
  cat > "${script}" << SCRIPT
. $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules process
__dybatpho_process_timeout_probe=no
trap 'printf "%s\n" "\${BASHPID}" >> $(printf '%q' "${log}")' EXIT
quick() { :; }
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  dybatpho::run_with_timeout 20 quick
done
printf '%s\n' "\${BASHPID}"
SCRIPT
  run_traced bash "${script}"
  assert_success
  assert_equal "$(cat "${log}")" "${output}"
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
  run_traced dybatpho::background_status first
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
  run_traced dybatpho::background_pid nosuch
  assert_failure
  refute_output
  run_traced dybatpho::background_status nosuch
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

@test "dybatpho::kill_children and background_run ignore a reaped job whose PID was reused" {
  __dybatpho_test_ok() { return 0; }
  dybatpho::background_run reaped __dybatpho_test_ok
  dybatpho::wait_all
  # Stand in for the kernel handing the reaped job's PID to an unrelated process.
  sleep 30 &
  local unrelated=$!
  DYBATPHO_BACKGROUND_PIDS["reaped"]="${unrelated}"

  run_traced dybatpho::background_run reaped __dybatpho_test_ok
  assert_success
  dybatpho::wait_all
  DYBATPHO_BACKGROUND_PIDS["reaped"]="${unrelated}"
  DYBATPHO_TIMEOUT_KILL_AFTER=1 dybatpho::kill_children
  kill -0 "${unrelated}"
  kill "${unrelated}"
}

@test "dybatpho::kill_children ends every background job and empties the registry" {
  dybatpho::background_run sleeper sleep 30
  local pid
  pid="$(dybatpho::background_pid sleeper)"

  dybatpho::kill_children
  assert_equal "${#DYBATPHO_BACKGROUND_NAMES[@]}" 0
  assert_equal "${#DYBATPHO_BACKGROUND_PIDS[@]}" 0

  assert_process_dead "${pid}"
}

@test "dybatpho::kill_children does not wait a second for every job that ends at once" {
  # Each job was looked at again only after a whole second, so four jobs that
  # all ended on SIGTERM still took four seconds to clear.
  local name
  for name in one two three four; do
    dybatpho::background_run "${name}" sleep 30
  done
  SECONDS=0
  dybatpho::kill_children
  ((SECONDS < 3)) || fail "kill_children took ${SECONDS}s for four jobs"
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
  assert_process_dead "$(< "${pid_file}")"
}

@test "dybatpho::kill_children kills a child that ignores SIGTERM after its job has exited" {
  local pid_file="${BATS_TEST_TMPDIR}/stubborn.pid"
  __dybatpho_test_stubborn() {
    (
      trap '' TERM
      printf '%s\n' "${BASHPID}" > "${pid_file}"
      sleep 30
    ) &
  }
  dybatpho::background_run stubborn __dybatpho_test_stubborn
  local waited=0
  while [[ ! -s "${pid_file}" ]] && ((waited < 5)); do
    sleep 1
    waited=$((waited + 1))
  done
  # The job itself is gone; only the child that ignores SIGTERM is left.
  local leader
  leader="$(dybatpho::background_pid stubborn)"
  waited=0
  while kill -0 "${leader}" 2> /dev/null && ((waited < 5)); do
    sleep 1
    waited=$((waited + 1))
  done
  assert_process_dead "${leader}"

  DYBATPHO_TIMEOUT_KILL_AFTER=1 dybatpho::kill_children
  sleep 1
  assert_process_dead "$(< "${pid_file}")"
}

@test "dybatpho::kill_children is safe to call when no job was ever started" {
  run_traced dybatpho::kill_children
  assert_success
  refute_output
}

# --- PID files ------------------------------------------------------------

@test "dybatpho::pid_file_write refuses a path it cannot write and leaves nothing behind" {
  # An empty path staged `.<pid>.tmp` in the working directory and then failed
  # to move it onto nothing, leaving the staging file there.
  local work="${BATS_TEST_TMPDIR}/pid work"
  mkdir -p "${work}/taken"
  local script="${BATS_TEST_TMPDIR}/pid.sh"
  printf '%s\n' \
    "cd $(printf '%q' "${work}")" \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh" \
    "(dybatpho::pid_file_write '') 2> /dev/null || printf 'empty refused\\n'" \
    "(dybatpho::pid_file_write taken/) 2> /dev/null || printf 'directory refused\\n'" \
    "(dybatpho::pid_file_write taken) 2> /dev/null || printf 'existing directory refused\\n'" > "${script}"
  run_traced bash "${script}"
  assert_output "$(printf 'empty refused\ndirectory refused\nexisting directory refused')"
  assert_equal "$(ls -A "${work}" | tr '\n' ' ')" "taken "
  assert_equal "$(ls -A "${work}/taken")" ""
}

@test "dybatpho::pid_file_write records a process id, creating the directory it needs" {
  local pid_file="${BATS_TEST_TMPDIR}/run/app.pid"
  dybatpho::pid_file_write "${pid_file}"
  assert_file_exist "${pid_file}"
  assert_equal "$(< "${pid_file}")" "$$"

  dybatpho::pid_file_write "${pid_file}" 4242
  assert_equal "$(< "${pid_file}")" "4242"
  # The staging file used for the atomic move must not be left behind.
  run_traced bash -c "ls '${BATS_TEST_TMPDIR}/run' | grep -c tmp"
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
  run_traced dybatpho::pid_file_is_running "${pid_file}"
  assert_success

  # A process id that is valid but has long since exited.
  printf '%s\n' "99999999" > "${pid_file}"
  run_traced dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  printf '%s\n' "garbage" > "${pid_file}"
  run_traced dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  : > "${pid_file}"
  run_traced dybatpho::pid_file_is_running "${pid_file}"
  assert_failure

  run_traced dybatpho::pid_file_is_running "${BATS_TEST_TMPDIR}/absent.pid"
  assert_failure
}

@test "dybatpho::pid_file_is_running sees a process it is not allowed to signal" {
  # `kill -0` fails with EPERM for another user's process. PID 1 belongs to
  # root on every host, and a `kill` that refuses everything stands in for the
  # case when the suite itself runs as root.
  local pid_file="${BATS_TEST_TMPDIR}/daemon.pid"
  printf '1\n' > "${pid_file}"
  run_traced -0 dybatpho::pid_file_is_running "${pid_file}"

  printf '%s\n' "$$" > "${pid_file}"
  kill() { return 1; }
  run_traced -0 dybatpho::pid_file_is_running "${pid_file}"
  printf '%s\n' "99999999" > "${pid_file}"
  run_traced -1 dybatpho::pid_file_is_running "${pid_file}"
  unset -f kill
}

@test "dybatpho::pid_file_is_running tolerates the padding a foreign PID file may carry" {
  local pid_file="${BATS_TEST_TMPDIR}/padded.pid"
  printf ' %s \n' "$$" > "${pid_file}"
  run_traced dybatpho::pid_file_is_running "${pid_file}"
  assert_success
}

@test "dybatpho::pid_file_remove leaves a file that records another process alone" {
  local pid_file="${BATS_TEST_TMPDIR}/owned.pid"
  dybatpho::pid_file_write "${pid_file}" 4242

  # The guard is what stops an exiting service from deleting the PID file its
  # replacement has already written.
  run_traced dybatpho::pid_file_remove "${pid_file}"
  assert_failure
  assert_file_exist "${pid_file}"

  run_traced dybatpho::pid_file_remove "${pid_file}" 4242
  assert_success
  assert_file_not_exist "${pid_file}"

  # Removing a file that is already gone is not a failure.
  run_traced dybatpho::pid_file_remove "${pid_file}"
  assert_success
}

@test "a function run under a time limit sees the caller's variables, not the library's" {
  # A shell function runs in the library's scope, where its locals hid the
  # caller's variables of the same names.
  local seconds="caller" kill_after="caller" marker="caller" monitor="caller"
  local seen="${BATS_TEST_TMPDIR}/seen"
  look() { printf '%s %s %s %s\n' "${seconds}" "${kill_after}" "${marker}" "${monitor}" > "${seen}"; }
  dybatpho::run_with_timeout 60 look
  assert_equal "$(cat "${seen}")" "caller caller caller caller"
}

@test "a background job sees the caller's variables, not the starter's" {
  # The job is a subshell of the starter, where its locals hid the caller's
  # variables of the same names.
  local name="caller" monitor="caller" pid="caller"
  local seen="${BATS_TEST_TMPDIR}/seen"
  look() { printf '%s %s %s\n' "${name}" "${monitor}" "${pid}" > "${seen}"; }
  dybatpho::background_run scoped look
  dybatpho::wait_all
  assert_equal "$(cat "${seen}")" "caller caller caller"
}

@test "dybatpho::dry_run -- runs a single argument as a command, never as shell" {
  export DRY_RUN=false
  run_traced dybatpho::dry_run -- 'echo first; echo INJECTED'
  assert_failure 127
  refute_output --partial "INJECTED"
  run_traced dybatpho::dry_run -- printf 'plain %s\n' 'a b'
  assert_output "plain a b"
  export DRY_RUN=true
  run_traced dybatpho::dry_run -- rm -rf -- "/tmp/x y"
  assert_output "🧪 DRY RUN: rm -rf -- /tmp/x\ y"
  run -1 dybatpho::dry_run --
  export DRY_RUN=false
  run -1 dybatpho::dry_run
}

@test "a temporary file does not stop TERM from ending the script, and is still removed" {
  # The cleanup used to trap INT and TERM themselves, which replaced what they
  # do: the script carried on past the signal and exited 0.
  local script="${BATS_TEST_TMPDIR}/signalled.sh" marker="${BATS_TEST_TMPDIR}/temp-path"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::create_temp temp ".txt" "signalled"
printf '%s' "${temp}" > "${2}"
kill -s TERM "$$"
printf 'carried on\n'
SCRIPT
  run_traced -143 bash "${script}" "${DYBATPHO_DIR}" "${marker}"
  refute_output --partial "carried on"
  assert_file_not_exist "$(< "${marker}")"
}

@test 'dybatpho::try captures the message of a die and returns its status' {
  _dies() {
    printf 'partial\n'
    dybatpho::die "cannot go on" 3
  }
  local out="" err="" status=0
  dybatpho::try out err -- _dies || status=$?
  assert_equal "${status}" "3"
  assert_equal "${out}" "partial"
  [[ "${err}" == *"cannot go on"* ]]
}

@test 'dybatpho::try returns 0 and both streams for a command that succeeds' {
  _speaks() {
    printf 'to stdout\n\n'
    printf 'to stderr\n' >&2
  }
  local out="" err=""
  run_traced -0 dybatpho::try out err -- _speaks
  # Trailing newlines go, as they would from `$(...)`.
  assert_equal "${out}" "to stdout"
  assert_equal "${err}" "to stderr"
}

@test 'dybatpho::try catches an exit and keeps the caller running' {
  local out="" err="" status=0
  dybatpho::try out err -- exit 5 || status=$?
  assert_equal "${status}" "5"
  assert_equal "${out}" ""
  assert_equal "${err}" ""
}

@test 'dybatpho::try discards a stream given an empty name' {
  local err=""
  run_traced -0 dybatpho::try '' err -- printf 'dropped\n'
  refute_output
  assert_equal "${err}" ""
}

@test 'dybatpho::try passes standard input to the command' {
  local out="" err=""
  dybatpho::try out err -- cat <<< "piped in"
  assert_equal "${out}" "piped in"
}

@test 'dybatpho::try runs the command in a subshell' {
  local changed="before" out="" err=""
  _changes() { changed="after"; }
  dybatpho::try out err -- _changes
  assert_equal "${changed}" "before"
}

@test 'dybatpho::try does not fire the caller ERR handler or errexit' {
  # In a script of its own: an ERR handler and `set -e` in the test shell would
  # take Bats down with them.
  local script="${BATS_TEST_TMPDIR}/try_handlers.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh"
dybatpho::register_common_handlers
_fails() { dybatpho::die "boom" 4; }
if ! dybatpho::try out err -- _fails; then
  [[ "${err}" == *boom* ]] && printf 'recovered\n'
fi
status=0
dybatpho::try out err -- false || status=$?
printf 'status %s\n' "${status}"
SCRIPT
  run_traced -0 bash "${script}" "${DYBATPHO_DIR}"
  assert_line --index 0 "recovered"
  assert_line --index 1 "status 1"
}

@test 'dybatpho::try leaves no temporary file behind' {
  local out="" err="" before after
  before="$(find "${BATS_TEST_TMPDIR}" -name 'dybatpho_try_*' | wc -l)"
  dybatpho::try out err -- printf 'x'
  after="$(find "${BATS_TEST_TMPDIR}" -name 'dybatpho_try_*' | wc -l)"
  assert_equal "${after}" "${before}"
}

@test 'dybatpho::try rejects a call without the separator or the command' {
  run --separate-stderr dybatpho::try out err printf 'x'
  assert_failure
  assert_stderr --partial "Expected: out_var err_var -- command"

  run --separate-stderr dybatpho::try out err --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"
}

@test 'dybatpho::try rejects a reserved or invalid variable name' {
  run --separate-stderr dybatpho::try __dybatpho_try_x err -- true
  assert_failure
  assert_stderr --partial "is reserved"

  run --separate-stderr dybatpho::try out 'bad name' -- true
  assert_failure
  assert_stderr --partial "Invalid variable name"
}

@test "a job outside a process group of its own is ended with SIGKILL when it ignores SIGTERM" {
  (
    trap '' TERM
    exec sleep 30
  ) &
  local pid=$!
  run_traced -0 __dybatpho_process_end_job "${pid}" false 1
  wait "${pid}" 2> /dev/null || true
  assert_process_dead "${pid}"
}

@test "the timeout fallback leaves job control on when the caller had it on" {
  __dybatpho_process_timeout_probe=no
  set -m
  run_traced -0 dybatpho::run_with_timeout 60 true
  local options="$-"
  set +m
  [[ "${options}" == *m* ]]
}

@test "dybatpho::background_run leaves job control on when the caller had it on" {
  set -m
  run_traced -0 dybatpho::background_run monitor_on sleep 0
  local options="$-"
  set +m
  dybatpho::wait_all > /dev/null 2>&1 || true
  [[ "${options}" == *m* ]]
}

@test "dybatpho::pid_file_write stops and cleans up when the file cannot be moved into place" {
  local path="${BATS_TEST_TMPDIR}/run/app.pid"
  mv() { return 1; }
  run -1 dybatpho::pid_file_write "${path}" 4242
  unset -f mv
  assert_output --partial "Cannot move"
  assert_file_not_exist "${path}"
  run_traced -1 compgen -G "${path}.*.tmp"
  assert_output ""
}

@test "dybatpho::run_with_timeout reads seconds with a leading zero in base ten" {
  # Arithmetic read `08` as an invalid octal number: each check failed with an
  # error, and a grace of `09` became an immediate SIGKILL.
  # shellcheck disable=SC2329 # run through the Bash watchdog
  _in_time() { printf 'in time\n'; }
  run_traced --separate-stderr dybatpho::run_with_timeout 08 _in_time
  assert_success
  assert_output "in time"
  assert_stderr ""
  DYBATPHO_TIMEOUT_KILL_AFTER=09 run_traced --separate-stderr dybatpho::run_with_timeout 08 printf 'binary\n'
  assert_success
  assert_output "binary"
  assert_stderr ""
}
