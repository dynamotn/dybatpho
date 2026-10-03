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
  run_traced dybatpho::still_has_args "${opts[@]}"
  assert_failure
  refute_output
}

@test "dybatpho::still_has_args with single arg" {
  run_traced dybatpho::still_has_args "single"
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

@test "dybatpho::require checks a command given as a path" {
  # `hash` accepts any name holding a `/` without looking, so a path has to be
  # checked for an executable file.
  local dir="${BATS_TEST_TMPDIR}/require_path"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\n' > "${dir}/tool"
  chmod +x "${dir}/tool"
  printf 'data\n' > "${dir}/plain"

  run_traced -0 dybatpho::require "${dir}/tool"

  run --separate-stderr -127 dybatpho::require "${dir}/absent"
  assert_stderr --partial "${dir}/absent isn't installed"
  run --separate-stderr -127 dybatpho::require "${dir}/plain"
  assert_stderr --partial "${dir}/plain isn't installed"
  run --separate-stderr -5 dybatpho::require "${dir}" 5
  assert_stderr --partial "${dir} isn't installed"
}

@test "dybatpho::require with custom exit code" {
  run --separate-stderr -99 dybatpho::require "nonexistent_command_xyz" 99
  assert_failure
  assert_stderr --partial "nonexistent_command_xyz isn't installed"
}

# A command on PATH that answers `--version` with whatever the test decided.
require_fake_tool() {
  local dir="${BATS_TEST_TMPDIR}/require_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$2" > "${dir}/$1"
  chmod +x "${dir}/$1"
  PATH="${dir}:${PATH}"
  # `hash` remembers where a command was, and an earlier lookup of the same
  # name would otherwise win over the one just installed.
  hash -r
}

@test "dybatpho::require accepts a command that satisfies the range" {
  require_fake_tool faketool "faketool 1.7.1"
  dybatpho::require faketool '>=1.6'
  dybatpho::require faketool '^1.2'
  dybatpho::require faketool '>=1.0 <2'
}

@test "dybatpho::require rejects a command that is older than the range" {
  require_fake_tool faketool "faketool 1.5.0"
  run --separate-stderr -127 dybatpho::require faketool '>=1.6'
  assert_stderr --partial "faketool >=1.6 is required, found 1.5.0"
}

@test "dybatpho::require reports a range failure with a custom exit code" {
  require_fake_tool faketool "faketool 1.5.0"
  run --separate-stderr -3 dybatpho::require faketool '>=1.6' 3
  assert_stderr --partial "faketool >=1.6 is required, found 1.5.0"
}

@test "dybatpho::require normalizes a version that is not full semver" {
  # `tar` says `1.35`, which is not a semver at all until it is coerced.
  require_fake_tool faketool "tar (GNU tar) 1.35"
  dybatpho::require faketool '>=1.30'
  run --separate-stderr -127 dybatpho::require faketool '>=1.40'
  assert_stderr --partial "found 1.35"
}

@test "dybatpho::require treats a distribution's build marker as the release" {
  # Read as a pre-release, `3.12-modified` would rank below `3.12` and be
  # rejected by a range that the very same grep satisfies.
  require_fake_tool faketool "grep (GNU grep) 3.12-modified"
  dybatpho::require faketool '>=3.12'
}

@test "dybatpho::require fails when the version cannot be read" {
  local dir="${BATS_TEST_TMPDIR}/require_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${dir}/faketool"
  chmod +x "${dir}/faketool"
  PATH="${dir}:${PATH}"
  hash -r
  run --separate-stderr -127 dybatpho::require faketool '>=1.0'
  assert_stderr --partial "version can't be determined"
}

@test "dybatpho::require still reads a bare second argument as an exit code" {
  # Ranges arrived after this argument already meant an exit code, so only an
  # operator makes it a range. `4` stays an exit code even though it would be a
  # valid range anywhere else.
  run --separate-stderr -4 dybatpho::require "nonexistent_command_xyz" 4
  assert_stderr --partial "isn't installed"
  require_fake_tool faketool "faketool 1.0.0"
  dybatpho::require faketool 4
}

@test "dybatpho::require checks the command exists before it checks the version" {
  run --separate-stderr -127 dybatpho::require "nonexistent_command_xyz" '>=1.0'
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
  run_traced dybatpho::is "command" "dyfoooo"
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
  run_traced dybatpho::is "function" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is file" {
  run_traced dybatpho::is "file" "${BASH_SOURCE[0]}"
  assert_success
  refute_output
  run_traced dybatpho::is "file" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is dir" {
  run_traced dybatpho::is "dir" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  refute_output
  run_traced dybatpho::is "dir" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is link" {
  local temp="${BATS_TEST_TMPDIR}/link"
  ln -sf "${BASH_SOURCE[0]}" "${temp}"
  run_traced dybatpho::is "link" "${temp}"
  assert_success
  refute_output
  run_traced dybatpho::is "link" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is exist" {
  run_traced dybatpho::is "exist" "$(dirname "${BASH_SOURCE[0]}")"
  assert_success
  refute_output
  run_traced dybatpho::is "exist" "dyfoooo"
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
  run_traced dybatpho::is "readable" "${temp}"
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
  run_traced dybatpho::is "writeable" "${temp}"
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
  run_traced dybatpho::is "executable" "${temp}"
  assert_failure
  refute_output
}

@test "dybatpho::is set" {
  local dyfoooo=""
  run_traced dybatpho::is "set" "${dyfoooo}"
  assert_failure
  refute_output
  dyfoooo="v"
  run_traced dybatpho::is "set" "${dyfoooo}"
  assert_success
  refute_output
}

@test "dybatpho::is with unset variable" {
  local unset_var
  run_traced dybatpho::is "set" "${unset_var:-}"
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
  run_traced dybatpho::is "number" "1a"
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
  run_traced dybatpho::is "int" "1.11"
  assert_failure
  refute_output
  run_traced dybatpho::is "int" "1a"
  assert_failure
  refute_output
}

@test "dybatpho::is int with negative int" {
  run_traced dybatpho::is "int" "-456"
  assert_success
  refute_output
}

@test "dybatpho::is int and number refuse what printf would coerce" {
  # These used to go through `printf '%d'` and `printf '%f'`, which take a
  # leading quote as a character code, read `0x` as hexadecimal, skip leading
  # blanks, and follow `LC_NUMERIC`.
  local value
  for value in "'a" '"a' 0x1F " 12" "12 " 1,5 inf nan ""; do
    run_traced -1 dybatpho::is int "${value}"
    run_traced -1 dybatpho::is number "${value}"
  done
  # A leading zero is octal to Bash arithmetic, so `010` would count as 8 and
  # `08` stop a script; an int is a value arithmetic reads as written.
  run_traced -1 dybatpho::is int 010
  run_traced -1 dybatpho::is int 08
  run_traced -0 dybatpho::is int 0
  run_traced -0 dybatpho::is int +7
  run_traced -0 dybatpho::is number 1e3
  run_traced -0 dybatpho::is number .5
  run_traced -0 dybatpho::is number 010
}

@test "dybatpho::is int and number never accept what validate_is rejects" {
  # The two checks share one meaning of a number; `is int` is only stricter
  # about leading zeros, which arithmetic reads as octal.
  local value status expected
  for value in 0 7 -7 +7 010 08 1.5 .5 5. -1e3 1E+3 1e 'x' "'a" 0x1F 1,5 "" " 1" inf; do
    if dybatpho::is int "${value}"; then
      dybatpho::validate_is int "${value}" || fail "is int accepts '${value}', validate_is does not"
    fi
    dybatpho::is number "${value}" && status=0 || status=1
    dybatpho::validate_is number "${value}" && expected=0 || expected=1
    assert_equal "${status}" "${expected}"
  done
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
  run_traced dybatpho::is "true" ""
  assert_failure
  refute_output
  run_traced dybatpho::is "true" "dyfoooo"
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
  run_traced dybatpho::is "false" ""
  assert_failure
  refute_output
  run_traced dybatpho::is "false" "dyfoooo"
  assert_failure
  refute_output
}

@test "dybatpho::is something undefined" {
  run_traced dybatpho::is "fool" "I'm in love"
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

  run_traced dybatpho::command_exists_all bash definitely_missing_command_xyz
  assert_failure
}

@test "dybatpho::coalesce_cmd prints first available command" {
  assert_equal "$(dybatpho::coalesce_cmd definitely_missing_command_xyz bash cat)" "bash"

  run_traced dybatpho::coalesce_cmd definitely_missing_command_xyz another_missing_command_xyz
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
  run_traced dybatpho::retry 2 _test_retry retry-target
  unstub sleep
  assert_success
  assert_output --partial "Retrying in 4 seconds (2/2)"
  assert_equal "$(cat "${sleep_args_file}")" '4'
}

@test "__dybatpho_helpers_backoff grows exponentially and stops at the cap" {
  DYBATPHO_RETRY_BASE_DELAY=2
  DYBATPHO_RETRY_MAX_DELAY=30
  DYBATPHO_RETRY_JITTER=false

  # 2, 4, 8, 16, then the cap rather than 32.
  assert_equal "$(__dybatpho_helpers_backoff 1)" "2"
  assert_equal "$(__dybatpho_helpers_backoff 2)" "4"
  assert_equal "$(__dybatpho_helpers_backoff 3)" "8"
  assert_equal "$(__dybatpho_helpers_backoff 4)" "16"
  assert_equal "$(__dybatpho_helpers_backoff 5)" "30"
  assert_equal "$(__dybatpho_helpers_backoff 20)" "30"
}

@test "__dybatpho_helpers_backoff honours a different base and cap" {
  DYBATPHO_RETRY_BASE_DELAY=1
  DYBATPHO_RETRY_MAX_DELAY=5
  DYBATPHO_RETRY_JITTER=false

  assert_equal "$(__dybatpho_helpers_backoff 1)" "1"
  assert_equal "$(__dybatpho_helpers_backoff 3)" "4"
  assert_equal "$(__dybatpho_helpers_backoff 4)" "5"
}

@test "__dybatpho_helpers_backoff adds jitter without exceeding the cap" {
  DYBATPHO_RETRY_BASE_DELAY=2
  DYBATPHO_RETRY_MAX_DELAY=30
  DYBATPHO_RETRY_JITTER=true

  # Jitter is random, so the contract is a range: at least the undisturbed
  # delay, at most one base delay more, and never past the cap.
  local i delay varied=false first
  first="$(__dybatpho_helpers_backoff 3)"
  for i in $(seq 1 25); do
    delay="$(__dybatpho_helpers_backoff 3)"
    [ "${delay}" -ge 8 ] || fail "jitter reduced the delay below the base: ${delay}"
    [ "${delay}" -le 10 ] || fail "jitter exceeded one base delay: ${delay}"
    [ "${delay}" = "${first}" ] || varied=true
  done
  # 25 draws from three values collide only about one run in 2.8 million.
  [ "${varied}" = true ] || fail "jitter never changed the delay in 25 draws"

  DYBATPHO_RETRY_MAX_DELAY=8
  for i in $(seq 1 10); do
    assert_equal "$(__dybatpho_helpers_backoff 3)" "8"
  done
}

@test "dybatpho::retry waits longer each time and never past the cap" {
  local sleep_args_file="${BATS_TEST_TMPDIR}/sleep-args"
  DYBATPHO_RETRY_BASE_DELAY=2
  DYBATPHO_RETRY_MAX_DELAY=5
  DYBATPHO_RETRY_JITTER=false

  _never_succeeds() {
    return 1
  }
  stub_repeated sleep ": echo \"\$*\" >> ${sleep_args_file}"
  run_traced dybatpho::retry 4 _never_succeeds capped-target
  unstub sleep
  assert_failure

  # 2, 4, then the cap twice instead of 8 and 16.
  assert_equal "$(tr '\n' ' ' < "${sleep_args_file}")" "2 4 5 5 "
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

  run_traced --separate-stderr dybatpho::breakpoint 2>&1 <<< "hoaApq"
  assert_success
  refute_output
  assert_stderr --partial "Breakpoint hit"
}

@test "dybatpho::is checks empty, true, and false values" {
  local empty_value=""
  dybatpho::is empty "${empty_value}"
  run_traced ! dybatpho::is empty "filled"

  dybatpho::is set "filled"
  run_traced ! dybatpho::is set ""

  dybatpho::is true "yes"
  run_traced ! dybatpho::is true "maybe"
  dybatpho::is false "off"
  run_traced ! dybatpho::is false "maybe"
}

@test "dybatpho::coalesce and dybatpho::coalesce_cmd fail without candidates" {
  run_traced ! dybatpho::coalesce "" ""
  run_traced ! dybatpho::coalesce_cmd "dybatpho-missing-command-a" "dybatpho-missing-command-b"
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

@test "dybatpho::provides names the module a function came from" {
  assert_equal "$(dybatpho::provides semver_valid)" "semver"
  # The prefix is what you have already typed when you stop to ask, so it is
  # accepted either way.
  assert_equal "$(dybatpho::provides dybatpho::semver_valid)" "semver"
  assert_equal "$(dybatpho::provides trim)" "string"
  assert_equal "$(dybatpho::provides provides)" "helpers"
  # The bootstrap defines functions of its own.
  assert_equal "$(dybatpho::provides version)" "init"
  run_traced ! dybatpho::provides no_such_function_at_all
}

@test "dybatpho::provides --path points at the line that defines the function" {
  local location file line
  location="$(dybatpho::provides --path semver_valid)"
  file="${location%:*}"
  line="${location##*:}"
  assert_equal "${file}" "${DYBATPHO_DIR}/src/semver.sh"
  # The claim is only worth something if the line really holds the definition.
  assert_equal "$(sed -n "${line}p" "${file}")" "function dybatpho::semver_valid {"
}

@test "dybatpho::provides leaves extdebug as it found it" {
  # The lookup needs `extdebug`, which also changes how DEBUG and RETURN traps
  # behave, so a caller must not be able to tell it was ever on.
  shopt -u extdebug
  dybatpho::provides semver_valid > /dev/null
  run_traced ! shopt -p extdebug
  shopt -s extdebug
  dybatpho::provides semver_valid > /dev/null
  run_traced -0 shopt -p extdebug
  shopt -u extdebug
}

@test "dybatpho::describe prints the comment the source carries" {
  run_traced -0 dybatpho::describe semver_valid
  assert_line --index 0 --partial "dybatpho::semver_valid  (semver,"
  assert_output --partial "Return success when the string is a valid semver"
  assert_output --partial '@arg $1 string Version string to validate'
  assert_output --partial "@exitcode 0 Valid semver"
  # The marker introducing the prose is noise once the prose is on screen.
  refute_output --partial "@description"
  # The comment markers themselves are not documentation either.
  refute_line --regexp '^#'
}

@test "dybatpho::describe steps over a shellcheck directive above the function" {
  # `dybatpho::trim` carries one between its comment and its definition, and it
  # is addressed to a linter rather than to a reader.
  run_traced -0 dybatpho::describe trim
  refute_output --partial "shellcheck"
  assert_output --partial "Trim leading and trailing whitespace"
}

@test "dybatpho::describe refuses a function this shell does not have" {
  run_traced ! dybatpho::describe no_such_function_at_all
}

@test "dybatpho::function_list lists the loaded public API in order" {
  run_traced -0 dybatpho::function_list
  assert_line "dybatpho::semver_valid"
  assert_line "dybatpho::trim"
  # Internals are not the API, and `declare -F` is right there for them.
  refute_line --regexp '^__dybatpho_'
  local listed sorted
  listed="${output}"
  sorted="$(printf '%s\n' "${listed}" | LC_ALL=C sort)"
  assert_equal "${listed}" "${sorted}"
}

@test "dybatpho::function_list limits itself to one module" {
  run_traced -0 dybatpho::function_list semver
  assert_line "dybatpho::semver_valid"
  refute_line "dybatpho::trim"
  # Everything it listed really does belong to that module.
  local name
  while read -r name; do
    assert_equal "$(dybatpho::provides "${name}")" "semver"
  done <<< "${output}"
}

@test "dybatpho::function_list rejects a module that is not loaded" {
  run --separate-stderr ! dybatpho::function_list not_a_loaded_module
  assert_stderr --partial "is not loaded"
}

@test "dybatpho::expect_ref accepts a caller's own variable name" {
  dybatpho::expect_ref my_array
  dybatpho::expect_ref _private
  dybatpho::expect_ref name2
}

@test "dybatpho::expect_ref rejects the library's reserved prefix" {
  # Binding a nameref to one of the library's own locals makes every write land
  # somewhere the caller never looks, and Bash does not always say so.
  run --separate-stderr dybatpho::expect_ref __dybatpho_array_sort_values
  assert_failure
  assert_stderr --partial "is reserved"
  assert_stderr --partial "Rename the variable in the caller"

  run --separate-stderr dybatpho::expect_ref __dybatpho
  assert_failure
  assert_stderr --partial "is reserved"
}

@test "dybatpho::expect_ref rejects a name that is not an identifier" {
  run --separate-stderr dybatpho::expect_ref "not a name"
  assert_failure
  assert_stderr --partial "Invalid variable name"

  run --separate-stderr dybatpho::expect_ref "2leading"
  assert_failure
  assert_stderr --partial "Invalid variable name"

  run --separate-stderr dybatpho::expect_ref ""
  assert_failure
  assert_stderr --partial "Invalid variable name"
}

@test "a reserved name is refused by the helpers that bind it" {
  # The guard exists because this used to succeed and sort nothing.
  __dybatpho_array_sort_values=(c a b)
  run --separate-stderr dybatpho::array_sort __dybatpho_array_sort_values
  assert_failure
  assert_stderr --partial "is reserved"

  # An ordinary name still works.
  local -a mine=(c a b)
  dybatpho::array_sort mine
  assert_equal "${mine[*]}" "a b c"
}
