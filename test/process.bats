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
  run --separate-stderr dybatpho::run_err_handler SIGTERM
  assert_failure
  refute_output
  assert_stderr

  run --separate-stderr dybatpho::run_err_handler SIGINT
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

@test 'dybatpho::cleanup_file_on_exit action' {
  local filepath="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  run --separate-stderr dybatpho::cleanup_file_on_exit "${filepath}"
  assert_success
  refute_output
  refute_stderr
  assert_file_not_exist "${filepath}"
}

@test "dybatpho::dry_run with DRY_RUN=true should print dry run message and not execute command" {
  DRY_RUN="true"
  local test_file="dry_run_test_file.tmp"
  rm -f "${test_file}"
  run dybatpho::dry_run touch "${test_file}"
  assert_output --partial "DRY RUN: touch ${test_file}"
  assert_file_not_exist "${test_file}"
  unset DRY_RUN
}

@test "dybatpho::dry_run with DRY_RUN=false should execute command and produce no dry run output" {
  DRY_RUN="false"
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
