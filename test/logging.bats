setup() {
  load test_helper
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
  assert_output --partial "DEBUG:"
}

@test "dybatpho::info output" {
  run dybatpho::info daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[0;40m")"
  assert_output --partial daylathongtin
  assert_output --partial "INFO:"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::progress output" {
  run dybatpho::progress daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[0;36m")"
  assert_output --partial "daylathongtin..."
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::notice output" {
  run dybatpho::notice daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[1;30;44m")"
  assert_output --partial "================================================================================"
  assert_output --partial daylathongtin
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::success output" {
  run dybatpho::success daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[1;32;40m")"
  assert_output --partial "DONE:"
  assert_output --partial daylathongtin
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::warn output" {
  run dybatpho::warn haycanthan
  assert_success
  assert_output --partial "$(echo -e "\e[0;33;40m")"
  assert_output --partial haycanthan
  assert_output --partial "[WARNING]:"
  assert_output --partial bats # show source file
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::error output" {
  run dybatpho::error loiroine CHIDAN
  assert_success
  assert_output --partial "$(echo -e "\e[1;31;40m")"
  assert_output --partial loiroine
  assert_output --partial "[ERROR]:"
  assert_output --partial CHIDAN # show indicator
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::fatal output" {
  run dybatpho::fatal loiroine
  assert_success
  assert_output --partial "$(echo -e "\e[1;37;41m")"
  assert_output --partial loiroine
  assert_output --partial "[FATAL]:"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::start_trace doesn't output anything when using default log level" {
  run dybatpho::start_trace
  assert_failure
  refute_output "START TRACE"
}

@test "dybatpho::start_trace output when using trace level" {
  export LOG_LEVEL=trace
  run dybatpho::start_trace
  assert_success
  assert_output --partial "$(echo -e "\e[1;30;47m")"
  assert_output --partial "START TRACE"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::pause_trace doesn't output anything when using default log level" {
  run dybatpho::pause_trace
  assert_failure
}

@test "dybatpho::pause_trace wait for output" {
  export LOG_LEVEL=trace
  run dybatpho::breakpoint 2>&1 <<< "q"
  assert_success
}

@test "dybatpho::breakpoint doesn't output anything when using default log level" {
  run dybatpho::breakpoint
  assert_failure
}

@test "dybatpho::breakpoint wait for output" {
  export LOG_LEVEL=trace
  run dybatpho::breakpoint 2>&1 <<< "hoaApq"
  assert_success
}

@test "dybatpho::end_trace doesn't output anything when using default log level" {
  run dybatpho::end_trace
  assert_failure
  refute_output "END TRACE"
}

@test "dybatpho::end_trace output when using trace level" {
  export LOG_LEVEL=trace
  run dybatpho::end_trace
  assert_success
  assert_output --partial "$(echo -e "\e[1;30;47m")"
  assert_output --partial "END TRACE"
  assert_output --partial "$(echo -e "\e[0m")"
}
