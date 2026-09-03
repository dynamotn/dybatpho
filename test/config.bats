setup() {
  load test_helper
}

@test "config_load loads dotenv files and later files override earlier values" {
  local base="${BATS_TEST_TMPDIR}/base.env"
  local local_config="${BATS_TEST_TMPDIR}/local.env"
  printf 'HOST=example.test\nPORT=80\n' > "${base}"
  printf 'PORT=443\nMESSAGE="hello world"\n' > "${local_config}"

  dybatpho::config_load "${base}" "${local_config}"
  run dybatpho::config_get HOST
  assert_output "example.test"
  run dybatpho::config_get PORT
  assert_output "443"
  run dybatpho::config_get MESSAGE
  assert_output "hello world"
}

@test "config_env applies prefixed environment variables" {
  export APP_HOST="env.test"
  dybatpho::config_env APP_
  run dybatpho::config_get HOST
  assert_output "env.test"
  unset APP_HOST
}

@test "config_get supports defaults and config_export exports values" {
  run dybatpho::config_get MISSING fallback
  assert_success
  assert_output "fallback"

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
  run dybatpho::config_get PLAIN
  assert_output "value"
  run dybatpho::config_get DOUBLE
  assert_output $'line\nvalue'
  run dybatpho::config_get SINGLE
  assert_output 'literal # value'
  run dybatpho::config_get SPACED
  assert_output "trimmed"
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
  run dybatpho::config_get PORT
  assert_output "8080"
  run dybatpho::config_get SHARED
  assert_output "from-yaml"
  run dybatpho::config_get HOST
  assert_output "localhost"
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
  run dybatpho::config_get MISSING
  assert_failure

  run --separate-stderr dybatpho::config_get "bad key"
  assert_failure
  assert_stderr --partial "Invalid configuration key"

  run dybatpho::config_require
  assert_failure
  run --separate-stderr dybatpho::config_require MISSING
  assert_failure
  assert_stderr --partial "Required configuration is missing"

  __dybatpho_config_set PRESENT "yes"
  run dybatpho::config_require PRESENT
  assert_success
}

@test "config_env applies only matching prefixed variables" {
  export DYBATPHO_CONFIG_ENV_TEST="loaded"
  export UNRELATED_CONFIG_ENV_TEST="ignored"
  DYBATPHO_CONFIG=()
  dybatpho::config_env DYBATPHO_CONFIG_
  run dybatpho::config_get ENV_TEST
  assert_success
  assert_output "loaded"
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
  run dybatpho::config_get DYBATPHO_CONFIG_UNPREFIXED
  assert_success
  assert_output "loaded"
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
