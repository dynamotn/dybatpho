setup() {
  load test_helper
  DYBATPHO_TEMP_FILE=$(mktemp)
  trap "rm -f $DYBATPHO_TEMP_FILE" EXIT
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
  run dybatpho::curl_do https://github.com "$DYBATPHO_TEMP_FILE"
  assert_success
  ! dybatpho::is empty "$(cat "$DYBATPHO_TEMP_FILE")"
}
