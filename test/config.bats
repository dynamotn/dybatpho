setup() {
  load test_helper
}

@test "config_load loads dotenv files and later files override earlier values" {
  local base="${BATS_TEST_TMPDIR}/base.env"
  local local_config="${BATS_TEST_TMPDIR}/local.env"
  printf 'HOST=example.test\nPORT=80\n' > "${base}"
  printf 'PORT=443\nMESSAGE="hello world"\n' > "${local_config}"

  dybatpho::config_load "${base}" "${local_config}"
  assert_equal "$(dybatpho::config_get HOST)" "example.test"
  assert_equal "$(dybatpho::config_get PORT)" "443"
  assert_equal "$(dybatpho::config_get MESSAGE)" "hello world"
}

@test "config_env applies prefixed environment variables" {
  export APP_HOST="env.test"
  dybatpho::config_env APP_
  assert_equal "$(dybatpho::config_get HOST)" "env.test"
  unset APP_HOST
}

@test "config_get supports defaults and config_export exports values" {
  assert_equal "$(dybatpho::config_get MISSING fallback)" "fallback"

  __dybatpho_config_set EXPORTED "value"
  dybatpho::config_export
  assert_equal "${EXPORTED}" "value"
}

@test "config_load rejects unsupported files and missing files" {
  run dybatpho::config_load "${BATS_TEST_TMPDIR}/missing.conf"
  assert_failure
  assert_output --partial "Configuration file not found"

  local config="${BATS_TEST_TMPDIR}/config.txt"
  : > "${config}"
  run dybatpho::config_load "${config}"
  assert_failure
  assert_output --partial "Unsupported configuration format"
}

@test "config_load parses dotenv comments, quoting, and escaped values" {
  local config="${BATS_TEST_TMPDIR}/quoted.dotenv"
  printf '%s\n' \
    '# comment' \
    'PLAIN=value # inline comment' \
    'DOUBLE="line\nvalue"' \
    "SINGLE='literal # value'" \
    'SPACED = trimmed' > "${config}"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${config}"
  assert_equal "$(dybatpho::config_get PLAIN)" "value"
  assert_equal "$(dybatpho::config_get DOUBLE)" $'line\nvalue'
  assert_equal "$(dybatpho::config_get SINGLE)" 'literal # value'
  assert_equal "$(dybatpho::config_get SPACED)" "trimmed"
}

@test "config_load supports JSON and YAML files with precedence" {
  local json_file="${BATS_TEST_TMPDIR}/settings.json"
  local yaml_file="${BATS_TEST_TMPDIR}/settings.yaml"
  printf '{}' > "${json_file}"
  printf '{}' > "${yaml_file}"
  stub jq ": printf 'PORT\\t8080\\nSHARED\\tfrom-json\\n'"
  stub yq ": printf 'SHARED\\tfrom-yaml\\nHOST\\tlocalhost\\n'"

  DYBATPHO_CONFIG=()
  dybatpho::config_load "${json_file}" "${yaml_file}"
  assert_equal "$(dybatpho::config_get PORT)" "8080"
  assert_equal "$(dybatpho::config_get SHARED)" "from-yaml"
  assert_equal "$(dybatpho::config_get HOST)" "localhost"
  unstub jq
  unstub yq
}

@test "config_load reports invalid dotenv and structured configuration" {
  local dotenv="${BATS_TEST_TMPDIR}/invalid.env"
  local json_file="${BATS_TEST_TMPDIR}/invalid.json"
  local yaml_file="${BATS_TEST_TMPDIR}/invalid.yaml"
  printf 'not an assignment\n' > "${dotenv}"
  run dybatpho::config_load "${dotenv}"
  assert_failure
  assert_output --partial "Invalid dotenv entry"

  printf '{}' > "${json_file}"
  stub jq ": exit 1"
  run dybatpho::config_load "${json_file}"
  assert_failure
  assert_output --partial "Invalid JSON configuration"
  unstub jq

  printf '{}' > "${yaml_file}"
  stub yq ": exit 1"
  run dybatpho::config_load "${yaml_file}"
  assert_failure
  assert_output --partial "Invalid YAML configuration"
  unstub yq
}

@test "config_get and config_require validate keys and missing values" {
  DYBATPHO_CONFIG=()
  run ! dybatpho::config_get MISSING
  __dybatpho_config_set PRESENT "yes"
  dybatpho::config_require PRESENT

  run --separate-stderr dybatpho::config_get "bad key"
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  run dybatpho::config_require
  assert_failure

  run --separate-stderr dybatpho::config_require MISSING
  assert_failure
  assert_stderr --partial "Required configuration is missing"
}

@test "config_env applies only matching prefixed variables" {
  export DYBATPHO_CONFIG_ENV_TEST="loaded"
  export UNRELATED_CONFIG_ENV_TEST="ignored"
  DYBATPHO_CONFIG=()
  dybatpho::config_env DYBATPHO_CONFIG_
  assert_equal "$(dybatpho::config_get ENV_TEST)" "loaded"
  run dybatpho::config_get UNRELATED_CONFIG_ENV_TEST
  assert_failure
  unset DYBATPHO_CONFIG_ENV_TEST UNRELATED_CONFIG_ENV_TEST
}

@test "config_env also loads variables without a prefix" {
  export DYBATPHO_CONFIG_UNPREFIXED="loaded"
  DYBATPHO_CONFIG=()
  set +u
  dybatpho::config_env
  set -u
  assert_equal "$(dybatpho::config_get DYBATPHO_CONFIG_UNPREFIXED)" "loaded"
  unset DYBATPHO_CONFIG_UNPREFIXED
}

@test "config_load rejects invalid keys returned by structured backends" {
  local json_file="${BATS_TEST_TMPDIR}/bad-key.json"
  printf '{}' > "${json_file}"
  stub jq ": printf '1BAD\\tvalue\\n'"
  run dybatpho::config_load "${json_file}"
  assert_failure
  assert_output --partial "Invalid configuration key"
  unstub jq
}

@test "config_export rejects invalid prefixes and non-shell keys" {
  DYBATPHO_CONFIG=()
  run --separate-stderr dybatpho::config_export "bad-prefix-"
  assert_failure
  assert_stderr --partial "Invalid configuration variable prefix"

  __dybatpho_config_set "with.dot" "value"
  run --separate-stderr dybatpho::config_export
  assert_failure
  assert_stderr --partial "Cannot export configuration key as variable"
}

@test "config_validate applies defaults and validates types, ranges, URLs, and enums" {
  DYBATPHO_CONFIG=()
  DYBATPHO_CONFIG_SCHEMA=()
  dybatpho::config_schema HOST url required:true
  dybatpho::config_schema PORT int default:8080 min:1 max:65535
  dybatpho::config_schema MODE enum choices:dev,prod
  dybatpho::config_schema DEBUG bool
  __dybatpho_config_set HOST "https://example.test"
  __dybatpho_config_set MODE prod
  __dybatpho_config_set DEBUG true
  # An optional key without a default is skipped instead of failing.
  dybatpho::config_schema REGION string
  dybatpho::config_validate
  assert_equal "$(dybatpho::config_get PORT)" "8080"
  run ! dybatpho::config_get REGION
}

@test "config_validate rejects missing required and invalid values" {
  DYBATPHO_CONFIG=()
  DYBATPHO_CONFIG_SCHEMA=()
  dybatpho::config_schema REQUIRED string required:true
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "required value is missing"

  DYBATPHO_CONFIG=()
  DYBATPHO_CONFIG_SCHEMA=()
  dybatpho::config_schema PORT int min:1 max:10
  __dybatpho_config_set PORT 99
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "must be at most 10"

  DYBATPHO_CONFIG=()
  DYBATPHO_CONFIG_SCHEMA=()
  dybatpho::config_schema MODE enum choices:dev,prod
  __dybatpho_config_set MODE test
  run --separate-stderr dybatpho::config_validate
  assert_failure
  assert_stderr --partial "expected one of"
}

@test "config_schema rejects invalid types and rules" {
  run --separate-stderr dybatpho::config_schema VALUE float
  assert_failure
  assert_stderr --partial "Unsupported configuration type"
  run --separate-stderr dybatpho::config_schema VALUE string unknown:value
  assert_failure
  assert_stderr --partial "Unsupported configuration schema rule"
}
