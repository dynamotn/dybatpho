setup() {
  load test_helper
}

teardown() {
  export LOG_LEVEL=info
}

@test "__log output message" {
  run --separate-stderr __log info test
  assert_success
  refute_stderr
  assert_output --partial test
  run --separate-stderr __log info test stderr
  assert_success
  refute_output
  assert_stderr --partial test
}

@test "__log with NO_COLOR" {
  export NO_COLOR="true"
  run --separate-stderr __log info test
  assert_success
  refute_output --partial "$(echo -e "\e[0;32m")"
}

@test "dybatpho::compare_log_level with same level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=info
  run dybatpho::compare_log_level "info"
  assert_success
}

@test "dybatpho::compare_log_level with lower level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=info
  run dybatpho::compare_log_level "error"
  assert_success
}

@test "dybatpho::compare_log_level with higher level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=error
  run dybatpho::compare_log_level "debug"
  assert_failure
}

@test "dybatpho::compare_log_level with trace and fatal" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=trace
  run dybatpho::compare_log_level "fatal"
  assert_success
}

@test "dybatpho::compare_log_level case insensitive" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=INFO
  run dybatpho::compare_log_level "info"
  assert_success
}

@test "dybatpho::validate_log_level succeeds with valid level" {
  run --separate-stderr dybatpho::validate_log_level error
  assert_success
  refute_output
  run --separate-stderr dybatpho::validate_log_level ERROR
  assert_success
  refute_output
}

@test "dybatpho::validate_log_level succeeds with invalid level" {
  run --separate-stderr dybatpho::validate_log_level foo
  assert_failure
}

@test "dybatpho::debug doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::debug foo
  assert_success
  refute_output
  refute_stderr "foo"
}

@test "dybatpho::debug output when using debug level" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=debug
  run --separate-stderr dybatpho::debug foo
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;36m")"
  assert_stderr --partial "foo"
  assert_stderr --partial "‖ DEBUG"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::debug_command output" {
  # shellcheck disable=2030,2031
  export LOG_LEVEL=debug
  run --separate-stderr dybatpho::debug_command "Who am I" "whoami"
  assert_success
  refute_output
  assert_stderr --partial "${USER}"
}

@test "dybatpho::info output" {
  run --separate-stderr dybatpho::info daylathongtin
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;34m")"
  assert_stderr --partial daylathongtin
  assert_stderr --partial "‖ INFO"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::print output" {
  run --separate-stderr dybatpho::print daylathongtin
  assert_success
  refute_stderr
  refute_output --partial "$(echo -e "\e[0;32m")"
  assert_output --partial daylathongtin
  refute_output --partial "‖ INFO"
}

@test "dybatpho::progress output" {
  run --separate-stderr dybatpho::progress daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[0;3;34m")"
  assert_output --partial "daylathongtin..."
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::progress_bar output" {
  run --separate-stderr dybatpho::progress_bar 3
  assert_success
  refute_stderr
  assert_output --partial "[#                                                 ]"
  run --separate-stderr dybatpho::progress_bar 0 20
  assert_success
  refute_stderr
  assert_output --partial "[                    ]"
  run --separate-stderr dybatpho::progress_bar 10 20
  assert_success
  refute_stderr
  assert_output --partial "[##                  ]"
  run --separate-stderr dybatpho::progress_bar 100 20
  assert_success
  refute_stderr
  assert_output --partial "[####################]"
}

@test "dybatpho::header output" {
  run --separate-stderr dybatpho::header daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[1;5;30;47m")"
  assert_output --partial "╔══════════════════════════════════════════════════════════════════════════════╗"
  assert_output --partial daylathongtin
  assert_output --partial "╚══════════════════════════════════════════════════════════════════════════════╝"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::success output" {
  run --separate-stderr dybatpho::success daylathongtin
  assert_success
  refute_stderr
  assert_output --partial "$(echo -e "\e[1;3;32m")"
  assert_output --partial "╭──────────────────────────────────────────────────────────────────────────────╮"
  assert_output --partial "DONE:"
  assert_output --partial daylathongtin
  assert_output --partial "╰──────────────────────────────────────────────────────────────────────────────╯"
  assert_output --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::warn output" {
  run --separate-stderr dybatpho::warn haycanthan
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;33")"
  assert_stderr --partial haycanthan
  assert_stderr --partial "‖ WARN"
  assert_stderr --partial bats # show source file
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::error output" {
  run --separate-stderr dybatpho::error loiroine
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[1;31m")"
  assert_stderr --partial loiroine
  assert_stderr --partial "‖ ERROR"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::fatal output" {
  run --separate-stderr dybatpho::fatal loiroine
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;31m")"
  assert_stderr --partial loiroine
  assert_stderr --partial "‖ FATAL"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::start_trace doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::start_trace
  assert_success
  refute_output
  refute_stderr "Start tracing"
}

@test "dybatpho::start_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run --separate-stderr dybatpho::start_trace
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;37m")"
  assert_stderr --partial "‖ TRACE"
  assert_stderr --partial "Start tracing"
  assert_stderr --partial "$(echo -e "\e[0m")"
}

@test "dybatpho::end_trace doesn't output anything when using default log level" {
  run --separate-stderr dybatpho::end_trace
  assert_success
  refute_output
  refute_stderr "End tracing"
}

@test "dybatpho::end_trace output when using trace level" {
  # shellcheck disable=SC2030,SC2031
  export LOG_LEVEL=trace
  run --separate-stderr dybatpho::end_trace
  assert_success
  refute_output
  assert_stderr --partial "$(echo -e "\e[0;37m")"
  assert_stderr --partial "‖ TRACE"
  assert_stderr --partial "End tracing"
  assert_stderr --partial "$(echo -e "\e[0m")"
}
