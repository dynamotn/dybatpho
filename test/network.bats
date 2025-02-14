setup() {
  load test_helper
  TEST_TEMP_DIR=$(temp_make)
}

teardown() {
  temp_del "$TEST_TEMP_DIR"
}

@test "__get_http_code no arg" {
  run __get_http_code
  assert_failure
}

@test "__get_http_code output" {
  run __get_http_code 403
  assert_success
  assert_output "403 (forbidden)"
}

@test "dybatpho::curl_do no arg" {
  run dybatpho::curl_do
  assert_failure
}

@test "dybatpho::curl_do only url" {
  run dybatpho::curl_do https://github.com
  assert_success
}

@test "dybatpho::curl_do with output" {
  local temp_file="$TEST_TEMP_DIR/curl_do"
  run dybatpho::curl_do https://github.com "$temp_file"
  assert_success
  assert_file_not_empty "${TEST_TEMP_DIR}/curl_do"
}
