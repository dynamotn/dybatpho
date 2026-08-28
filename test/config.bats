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
  run bash -c 'source "'"${DYBATPHO_DIR}"'/init.sh"; printf "%s" "${EXPORTED-unset}"'
  assert_success
  assert_output "unset"
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
