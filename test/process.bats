setup() {
  load test_helper
}

@test 'dybatpho::die output' {
  bats_require_minimum_version 1.5.0
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
  bats_require_minimum_version 1.5.0
  local exit_code=7
  run -"$exit_code" dybatpho::run_err_handler "$exit_code"
  assert_failure
}
