setup() {
  . "${DYBATPHO_DIR}/test/lib/support/load.bash"
  . "${DYBATPHO_DIR}/test/lib/assert/load.bash"
  . "${DYBATPHO_DIR}/init.sh"
}

teardown() {
  export LOG_LEVEL=info
}

@test "_verify_log_level succeeds with valid level" {
  run _verify_log_level error
  assert_success
  run _verify_log_level ERROR
  assert_success
}

@test "_verify_log_level succeeds with invalid level" {
  run _verify_log_level foo
  assert_failure
}

@test "_log output message" {
  run _log info test
  assert_success
  assert_output --partial test
  run _log info test stderr
  assert_success
  assert_output --partial test
}

@test "_debug doesn't output anything when using default log level" {
  run _debug foo
  assert_success
  refute_output "foo"
}

@test "_debug output when using debug level" {
  export LOG_LEVEL=debug
  run _debug foo
  assert_success
  assert_output --partial "foo"
}

@test "_error correct color and reset color at the end" {
  run _error loiroine
  assert_success
  assert_output --partial "$(echo -e "\e[1;31;40m")"
  assert_output --partial loiroine
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "_fatal output and exit" {
  run _fatal loiroine
  assert_failure
  assert_output --partial "$(echo -e "\e[1;37;41m")"
  assert_output --partial loiroine
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "_trace doesn't output anything when using default log level" {
  run _start_trace
  assert_failure
  refute_output "START TRACE"
}

@test "_trace output when using trace level" {
  export LOG_LEVEL=trace
  run _start_trace
  assert_success
  assert_output --partial "START TRACE"
}
