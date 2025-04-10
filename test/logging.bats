setup() {
  load test_helper
}

teardown() {
  export LOG_LEVEL=info
}

@test "__log output message" {
  run __log info test
  assert_success
  assert_output --partial test
  run __log info test stderr
  assert_success
  assert_output --partial test
}

@test "__log with NO_COLOR" {
  export NO_COLOR="true"
  run __log info test
  assert_success
  refute_output --partial "$(echo -e "\e[0;32m")"
}

@test "dybatpho::validate_log_level succeeds with valid level" {
  run dybatpho::validate_log_level error
  assert_success
  run dybatpho::validate_log_level ERROR
  assert_success
}

@test "dybatpho::validate_log_level succeeds with invalid level" {
  run dybatpho::validate_log_level foo
  assert_failure
}

@test "dybatpho::debug doesn't output anything when using default log level" {
  run dybatpho::debug foo
  assert_success
  refute_output "foo"
}

@test "dybatpho::debug output when using debug level" {
  # shellcheck disable=SC2030
  export LOG_LEVEL=debug
  run dybatpho::debug foo
  assert_success
  assert_output --partial "$(echo -e "\e[0;35m")"
  assert_output --partial "foo"
  assert_output --partial "‖ DEBUG"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::debug_command output" {
  # shellcheck disable=SC2030
  export LOG_LEVEL=debug
  run dybatpho::debug_command "Who am I" "whoami"
  assert_success
  assert_output --partial "${USER}"
}

@test "dybatpho::info output" {
  run dybatpho::info daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[0;32m")"
  assert_output --partial daylathongtin
  assert_output --partial "‖ INFO"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::print output" {
  run dybatpho::print daylathongtin
  assert_success
  refute_output --partial "$(echo -e "\e[0;32m")"
  assert_output --partial daylathongtin
  refute_output --partial "‖ INFO"
}

@test "dybatpho::progress output" {
  run dybatpho::progress daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[0;3;34m")"
  assert_output --partial "daylathongtin..."
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::progress_bar output" {
  run dybatpho::progress_bar 3
  assert_success
  assert_output --partial "[#                                                 ]"
  run dybatpho::progress_bar 0 20
  assert_success
  assert_output --partial "[                    ]"
  run dybatpho::progress_bar 10 20
  assert_success
  assert_output --partial "[##                  ]"
  run dybatpho::progress_bar 100 20
  assert_success
  assert_output --partial "[####################]"
}

@test "dybatpho::notice output" {
  run dybatpho::notice daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[1;5;44m")"
  assert_output --partial "================================================================================"
  assert_output --partial daylathongtin
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::success output" {
  run dybatpho::success daylathongtin
  assert_success
  assert_output --partial "$(echo -e "\e[1;4;32;40m")"
  assert_output --partial "DONE:"
  assert_output --partial daylathongtin
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::warn output" {
  run dybatpho::warn haycanthan
  assert_success
  assert_output --partial "$(echo -e "\e[0;33")"
  assert_output --partial haycanthan
  assert_output --partial "‖ WARN"
  assert_output --partial bats # show source file
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::error output" {
  run dybatpho::error loiroine
  assert_success
  assert_output --partial "$(echo -e "\e[1;31m")"
  assert_output --partial loiroine
  assert_output --partial "‖ ERROR"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::fatal output" {
  run dybatpho::fatal loiroine
  assert_success
  assert_output --partial "$(echo -e "\e[0;31m")"
  assert_output --partial loiroine
  assert_output --partial "‖ FATAL"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::start_trace doesn't output anything when using default log level" {
  run dybatpho::start_trace
  assert_success
  refute_output "START TRACE"
}

@test "dybatpho::start_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run dybatpho::start_trace
  assert_success
  assert_output --partial "$(echo -e "\e[0;36m")"
  assert_output --partial "‖ TRACE"
  assert_output --partial "Start tracing"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::end_trace doesn't output anything when using default log level" {
  run dybatpho::end_trace
  assert_success
  refute_output "END TRACE"
}

@test "dybatpho::end_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run dybatpho::end_trace
  assert_success
  assert_output --partial "$(echo -e "\e[0;36m")"
  assert_output --partial "‖ TRACE"
  assert_output --partial "End tracing"
  assert_output --partial "$(echo -e "\e[0m")"
}
