setup() {
  load test_helper
}

@test 'dybatpho::die output' {
  local exit_code=7
  run -"$exit_code" dybatpho::die loioday "$exit_code"
  assert_failure
  assert_output --partial "loioday"
}

@test 'dybatpho::register_err_handler output' {
  run dybatpho::register_err_handler
  assert_success
}

@test 'dybatpho::run_err_handler output' {
  local exit_code=7
  run -"$exit_code" dybatpho::run_err_handler "$exit_code"
  assert_failure
}

@test 'dybatpho::trap on exit' {
  run dybatpho::trap 'echo 2; echo 3' ERR EXIT
  assert_success
  assert_line --index 0 2
  assert_line --index 1 3
}

@test 'dybatpho::gen_temp_file show path of generated file' {
  run dybatpho::gen_temp_file program
  assert_success
  assert_output --partial program
}

@test 'dybatpho::gen_temp_file create file' {
  stub mktemp ": touch ${BATS_TEST_TMPDIR}/program"
  run dybatpho::gen_temp_file program false
  assert_success
  assert_file_exist "${BATS_TEST_TMPDIR}/program"
  unstub mktemp
}
