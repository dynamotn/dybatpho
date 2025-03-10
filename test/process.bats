setup() {
  load test_helper
}

@test 'dybatpho::die output' {
  local exit_code=7
  run -"${exit_code}" dybatpho::die loioday "${exit_code}"
  assert_failure
  assert_output --partial "loioday"
}

@test 'dybatpho::register_err_handler output' {
  run dybatpho::register_err_handler
  assert_success
}

@test 'dybatpho::run_err_handler output' {
  local exit_code=7
  run -"${exit_code}" dybatpho::run_err_handler "${exit_code}"
  assert_failure
}

@test 'dybatpho::trap on exit' {
  run dybatpho::trap 'echo 2; echo 3' ERR EXIT
  assert_success
  assert_line --index 0 2
  assert_line --index 1 3
}

@test 'dybatpho::cleanup_file_on_exit action' {
  local filepath=$(mktemp)
  run dybatpho::cleanup_file_on_exit "${filepath}"
  assert_success
  assert_file_not_exist "${filepath}"
}
