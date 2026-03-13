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

@test 'dybatpho::cleanup_file_on_exit removes directory on shell exit' {
  local dirpath="${BATS_TEST_TMPDIR}/cleanup-dir"
  _register_cleanup_dir() {
    local dir="$1"
    mkdir -p "${dir}"
    dybatpho::cleanup_file_on_exit "${dir}"
    echo "${dir}"
  }
  run _register_cleanup_dir "${dirpath}"
  assert_success
  assert_output "${dirpath}"
  [[ ! -e "${dirpath}" ]]
}

@test 'dybatpho::cleanup_file_on_exit generates quoted cleanup commands' {
  local target="${BATS_TEST_TMPDIR}/dir with space"
  dybatpho::cleanup_file_on_exit "${target}"
  run trap -p EXIT
  assert_success
  local quoted_target
  quoted_target=$(printf '%q' "${target}")
  assert_output --partial "> /dev/null 2>&1"
  assert_output --partial "[[ -e ${quoted_target} ]] && rm -rf ${quoted_target} > /dev/null 2>&1"
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
