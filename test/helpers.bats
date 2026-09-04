setup() {
  load test_helper
}

@test "dybatpho::expect_args have right spec" {
  # shellcheck disable=2329
  test_function() {
    local arg1 arg2
    dybatpho::expect_args arg1 arg2 -- "$@"
    assert_equal "${arg1}" "this is first arg"
    assert_equal "${arg2}" "this is second arg"
  }
  test_function "this is first arg" "this is second arg"
}

@test "dybatpho::expect_args not have right spec" {
  # shellcheck disable=2329
  test_function() {
    local arg1 arg2
    dybatpho::expect_args arg1 arg2 "$@"
  }
  run --separate-stderr test_function "this is first arg" "this is second arg"
  assert_failure
  assert_stderr --partial "Expected variable names,"
}

@test "dybatpho::expect_args not have enough args" {
  test_function() {
    local arg1 arg2
    dybatpho::expect_args arg1 arg2 -- "$@"
  }
  run --separate-stderr test_function
  assert_failure
  assert_stderr --partial "Expected args:"
  run --separate-stderr test_function "1"
  assert_failure
  assert_stderr --partial "Expected args:"
}

@test "dybatpho::expect_args with invalid variable name" {
  test_function() {
    dybatpho::expect_args bad-name -- "$@"
  }
  run --separate-stderr test_function "value"
  assert_failure
  assert_stderr --partial "Invalid variable name: bad-name"
}

@test "dybatpho::still_has_args logic" {
  declare -a opts=('opt1' 'opt2' '--opt3')
  run_traced dybatpho::still_has_args "${opts[@]}"
  assert_success
  refute_output
  opts=()
  run dybatpho::still_has_args "${opts[@]}"
  assert_failure
  refute_output
}

@test "dybatpho::still_has_args with single arg" {
  run dybatpho::still_has_args "single"
  assert_failure
  refute_output
}

@test "dybatpho::expect_envs have right envs" {
  # shellcheck disable=2030
  export DYBATPHO_TEST_ENV1="test1"
  export DYBATPHO_TEST_ENV2="test2"
  dybatpho::expect_envs DYBATPHO_TEST_ENV1 DYBATPHO_TEST_ENV2
}

@test "dybatpho::expect_envs not have right envs" {
  run --separate-stderr dybatpho::expect_envs DYBATPHO_TEST_ENV1 DYBATPHO_TEST_ENV2
  assert_failure
  assert_stderr --partial "Environment variable \`DYBATPHO_TEST_ENV1\` isn't set"
  # shellcheck disable=2031
  export DYBATPHO_TEST_ENV1="test1"
  run --separate-stderr dybatpho::expect_envs DYBATPHO_TEST_ENV1 DYBATPHO_TEST_ENV2
  assert_failure
  assert_stderr --partial "Environment variable \`DYBATPHO_TEST_ENV2\` isn't set"
}

@test "dybatpho::expect_envs not have enough envs" {
  dybatpho::expect_envs
}

@test "dybatpho::expect_envs with empty env value" {
  export EMPTY_ENV=""
  run --separate-stderr dybatpho::expect_envs EMPTY_ENV
  assert_failure
  assert_stderr --partial "Environment variable \`EMPTY_ENV\` isn't set"
}

@test "dybatpho::require installed tool" {
  dybatpho::require "bash"
}

@test "dybatpho::require not installed tool" {
  run --separate-stderr -127 dybatpho::require "dyfoooo"
  assert_failure
  assert_stderr --partial "dyfoooo isn't installed"
  run --separate-stderr -200 dybatpho::require "dyfoooo" 200
  assert_failure
  assert_stderr --partial "dyfoooo isn't installed"
}

@test "dybatpho::require with custom exit code" {
  run --separate-stderr -99 dybatpho::require "nonexistent_command_xyz" 99
  assert_failure
  assert_stderr --partial "nonexistent_command_xyz isn't installed"
}

@test "dybatpho::is with empty" {
  run dybatpho::is
  assert_failure
}

@test "dybatpho::is command" {
  run_traced dybatpho::is "command" "bash"
  assert_success
  refute_output
  run dybatpho::is "command" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is function" {
  dyfoo() {
    :
  }
  run_traced dybatpho::is "function" "dyfoo"
  assert_success
  refute_output
  run dybatpho::is "function" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is file" {
  run_traced dybatpho::is "file" "${BASH_SOURCE[0]}"
  assert_success
  refute_output
  run dybatpho::is "file" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is dir" {
  run_traced dybatpho::is "dir" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  refute_output
  run dybatpho::is "dir" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is link" {
  local temp="${BATS_TEST_TMPDIR}/link"
  ln -sf "${BASH_SOURCE[0]}" "${temp}"
  run_traced dybatpho::is "link" "${temp}"
  assert_success
  refute_output
  run dybatpho::is "link" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is exist" {
  run_traced dybatpho::is "exist" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  refute_output
  run dybatpho::is "exist" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is readable" {
  local temp="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  chmod +r "${temp}"
  run_traced dybatpho::is "readable" "${temp}"
  assert_success
  refute_output
  chmod a-r "${temp}"
  run dybatpho::is "readable" "${temp}"
  assert_failure
  refute_output
}

@test "dybatpho::is writeable" {
  local temp="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  chmod +w "${temp}"
  run_traced dybatpho::is "writeable" "${temp}"
  assert_success
  refute_output
  chmod -w "${temp}"
  run dybatpho::is "writeable" "${temp}"
  assert_failure
  refute_output
}

@test "dybatpho::is executable" {
  local temp="$(mktemp -p "${BATS_TEST_TMPDIR}")"
  chmod +x "${temp}"
  run_traced dybatpho::is "executable" "${temp}"
  assert_success
  refute_output
  chmod -x "${temp}"
  run dybatpho::is "executable" "${temp}"
  assert_failure
  refute_output
}

@test "dybatpho::is set" {
  local dyfoooo=""
  run dybatpho::is "set" "${dyfoooo}"
  assert_failure
  refute_output
  dyfoooo="v"
  run_traced dybatpho::is "set" "${dyfoooo}"
  assert_success
  refute_output
}

@test "dybatpho::is with unset variable" {
  local unset_var
  run dybatpho::is "set" "${unset_var:-}"
  assert_failure
}

@test "dybatpho::is empty" {
  local dyfoooo=""
  run_traced dybatpho::is "empty" "${dyfoooo}"
  assert_success
  refute_output
}

@test "dybatpho::is number" {
  run_traced dybatpho::is "number" "1.11"
  assert_success
  refute_output
  run dybatpho::is "number" "1a"
  assert_failure
  refute_output
}

@test "dybatpho::is number with negative number" {
  run_traced dybatpho::is "number" "-123.45"
  assert_success
  refute_output
}

@test "dybatpho::is int" {
  run_traced dybatpho::is "int" "11"
  assert_success
  refute_output
  run dybatpho::is "int" "1.11"
  assert_failure
  refute_output
  run dybatpho::is "int" "1a"
  assert_failure
  refute_output
}

@test "dybatpho::is int with negative int" {
  run_traced dybatpho::is "int" "-456"
  assert_success
  refute_output
}

@test "dybatpho::is true" {
  run_traced dybatpho::is "true" "0"
  assert_success
  refute_output
  run_traced dybatpho::is "true" "tRuE"
  assert_success
  refute_output
  run_traced dybatpho::is "true" "YeS"
  assert_success
  refute_output
  run_traced dybatpho::is "true" "oN"
  assert_success
  refute_output
  run dybatpho::is "true" ""
  assert_failure
  refute_output
  run dybatpho::is "true" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is false" {
  run_traced dybatpho::is "false" "1"
  assert_success
  refute_output
  run_traced dybatpho::is "false" "FaLsE"
  assert_success
  refute_output
  run_traced dybatpho::is "false" "nO"
  assert_success
  refute_output
  run_traced dybatpho::is "false" "oFf"
  assert_success
  refute_output
  run dybatpho::is "false" ""
  assert_failure
  refute_output
  run dybatpho::is "false" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is something undefined" {
  run dybatpho::is "fool" "I'm in love"
  assert_failure
  refute_output
}

@test "dybatpho::coalesce returns first non-empty value" {
  assert_equal "$(dybatpho::coalesce "" "" "fallback" "other")" "fallback"

  assert_equal "$(dybatpho::coalesce "" "0" "later")" "0"
}

@test "dybatpho::coalesce fails when all values are empty or missing" {
  run dybatpho::coalesce "" ""
  assert_failure
  refute_output

  run --separate-stderr dybatpho::coalesce
  assert_failure
  assert_stderr --partial "Expected at least one value"
}

@test "dybatpho::command_exists_all verifies every command" {
  dybatpho::command_exists_all bash cat

  run dybatpho::command_exists_all bash definitely_missing_command_xyz
  assert_failure
}

@test "dybatpho::coalesce_cmd prints first available command" {
  assert_equal "$(dybatpho::coalesce_cmd definitely_missing_command_xyz bash cat)" "bash"

  run dybatpho::coalesce_cmd definitely_missing_command_xyz another_missing_command_xyz
  assert_failure
}

@test "dybatpho::default_env assigns and preserves environment values" {
  _default_env_assigns() {
    unset DYBATPHO_SAMPLE_ENV
    dybatpho::default_env DYBATPHO_SAMPLE_ENV "fallback"
    printf '%s\n' "${DYBATPHO_SAMPLE_ENV}"
  }
  run_traced _default_env_assigns
  assert_success
  assert_output << EOF
fallback
fallback
EOF

  _default_env_preserves() {
    export DYBATPHO_SAMPLE_ENV="custom"
    dybatpho::default_env DYBATPHO_SAMPLE_ENV "fallback"
    printf '%s\n' "${DYBATPHO_SAMPLE_ENV}"
  }
  run_traced _default_env_preserves
  assert_success
  assert_output << EOF
custom
custom
EOF
}

@test "dybatpho::require_envs_any accepts any configured environment variable" {
  export DYBATPHO_ENV_ONE=""
  export DYBATPHO_ENV_TWO="configured"
  dybatpho::require_envs_any DYBATPHO_ENV_ONE DYBATPHO_ENV_TWO

  export DYBATPHO_ENV_ONE=""
  export DYBATPHO_ENV_TWO=""
  run --separate-stderr dybatpho::require_envs_any DYBATPHO_ENV_ONE DYBATPHO_ENV_TWO
  assert_failure
  assert_stderr --partial "Expected at least one environment variable"
}

@test "dybatpho::assert succeeds and fails with clear messages" {
  dybatpho::assert '[[ 1 -eq 1 ]]'

  run --separate-stderr dybatpho::assert '[[ 1 -eq 2 ]]' "numbers mismatch"
  assert_failure
  assert_stderr --partial "numbers mismatch"
}

# shellcheck disable=2329
_test_retry() {
  count=$((count + 1))
  if [ "${count}" -lt 3 ]; then
    return 1
  else
    return 0
  fi
}

@test "dybatpho::retry out of retries" {
  count=0
  run dybatpho::retry 1 _test_retry
  assert_failure
  assert_output --partial "No more retries left to run _test"
}

@test "dybatpho::retry success in max retries" {
  count=0
  run_traced dybatpho::retry 2 _test_retry
  assert_success
  assert_output --partial "Retrying in 4 seconds (2/2)"
}

@test "dybatpho::retry success before max retries" {
  count=0
  run_traced dybatpho::retry 3 _test_retry
  assert_success
  assert_output --partial "Retrying in 4 seconds (2/3)"
  refute_output --partial "Retrying in 8 seconds (3/3)"
}

@test "dybatpho::retry with immediate success" {
  count=0
  _test_retry() {
    return 0
  }
  run_traced dybatpho::retry 3 _test_retry
  assert_success
  refute_output --partial "Retrying"
}

@test "dybatpho::retry sleeps between attempts" {
  local sleep_args_file="${BATS_TEST_TMPDIR}/sleep-args"
  count=0
  stub sleep ": echo \"\$*\" >> ${sleep_args_file}"
  run dybatpho::retry 2 _test_retry retry-target
  unstub sleep
  assert_success
  assert_output --partial "Retrying in 4 seconds (2/2)"
  assert_equal "$(cat "${sleep_args_file}")" '4'
}

@test "dybatpho::retry uses provided description in warning" {
  _always_fail() {
    return 7
  }
  run dybatpho::retry 0 _always_fail custom-description
  assert_failure
  assert_output --partial "No more retries left to run custom-description."
}

@test "dybatpho::retry_until retries with a fixed delay" {
  local sleep_args_file="${BATS_TEST_TMPDIR}/retry-until-sleep-args"
  _retry_until_flaky() {
    count=$((count + 1))
    [[ "${count}" -ge 3 ]]
  }
  count=0
  stub sleep ": echo \"\$*\" >> ${sleep_args_file}"
  run_traced dybatpho::retry_until 3 1 _retry_until_flaky retry-until-target
  unstub sleep
  assert_success
  assert_output --partial "Retrying in 1 seconds (2/3)"
  run_traced cat "${sleep_args_file}"
  assert_success
  assert_output << EOF
1
1
EOF
}

@test "dybatpho::retry_until returns the final failure code" {
  _retry_until_fail() {
    return 9
  }
  stub sleep ":"
  run dybatpho::retry_until 1 1 _retry_until_fail fixed-delay-target
  unstub sleep
  assert_failure 9
  assert_output --partial "No more retries left to run fixed-delay-target."
}

@test "dybatpho::breakpoint wait for output" {
  # Fed directly so the key dispatch runs in this shell; unknown keys loop.
  dybatpho::breakpoint <<< "hoaApq"

  run --separate-stderr dybatpho::breakpoint 2>&1 <<< "hoaApq"
  assert_success
  refute_output
  assert_stderr --partial "Breakpoint hit"
}

@test "dybatpho::is checks empty, true, and false values" {
  local empty_value=""
  dybatpho::is empty "${empty_value}"
  run ! dybatpho::is empty "filled"

  dybatpho::is set "filled"
  run ! dybatpho::is set ""

  dybatpho::is true "yes"
  run ! dybatpho::is true "maybe"
  dybatpho::is false "off"
  run ! dybatpho::is false "maybe"
}

@test "dybatpho::coalesce and dybatpho::coalesce_cmd fail without candidates" {
  run ! dybatpho::coalesce "" ""
  run ! dybatpho::coalesce_cmd "dybatpho-missing-command-a" "dybatpho-missing-command-b"
}

@test "retry helpers give up after the retry budget is exhausted" {
  stub_repeated sleep ": true"

  local status=0
  dybatpho::retry 1 "false" "always failing" || status=$?
  assert_equal "${status}" "1"

  status=0
  dybatpho::retry_until 1 0 "false" "always failing" || status=$?
  assert_equal "${status}" "1"
}
