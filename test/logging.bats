setup() {
  . "${DYBATPHO_DIR}/test/lib/support/load.bash"
  . "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  . "${DYBATPHO_DIR}/init.sh"
}

teardown() {
  export LOG_LEVEL=info
}

@test "__verify_log_level succeeds with valid level" {
  run __verify_log_level error
  assert_success
  run __verify_log_level ERROR
  assert_success
}

@test "__verify_log_level succeeds with invalid level" {
  run __verify_log_level foo
  assert_failure
}

@test "__log output message" {
  run __log info test
  assert_success
  assert_output --partial test
  run __log info test stderr
  assert_success
  assert_output --partial test
}

@test "dybatpho::debug doesn't output anything when using default log level" {
  run dybatpho::debug foo
  assert_success
  refute_output "foo"
}

@test "dybatpho::debug output when using debug level" {
  export LOG_LEVEL=debug
  run dybatpho::debug foo
  assert_success
  assert_output --partial "foo"
}

@test "dybatpho::error correct color and reset color at the end" {
  run dybatpho::error loiroine
  assert_success
  assert_output --partial "$(echo -e "\e[1;31;40m")"
  assert_output --partial loiroine
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::fatal output and exit" {
  run dybatpho::fatal loiroine
  assert_failure
  assert_output --partial "$(echo -e "\e[1;37;41m")"
  assert_output --partial loiroine
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::trace doesn't output anything when using default log level" {
  run dybatpho::start_trace
  assert_failure
  refute_output "START TRACE"
}

@test "dybatpho::trace output when using trace level" {
  export LOG_LEVEL=trace
  run dybatpho::start_trace
  assert_success
  assert_output --partial "START TRACE"
}
