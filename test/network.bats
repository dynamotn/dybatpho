setup() {
  load test_helper
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
  stub curl ": echo '200'"
  run dybatpho::curl_do https://this
  unstub curl
  assert_success
}

@test "dybatpho::curl_do with output" {
  local temp_file="$BATS_TEST_TMPDIR/curl_do"
  stub curl ": echo '200'; echo 'hahaa' > $temp_file"
  run dybatpho::curl_do https://this "$temp_file"
  assert_success
  assert_file_not_empty "${BATS_TEST_TMPDIR}/curl_do"
  unstub curl
}

@test "dybatpho::curl_download not have right spec" {
  run dybatpho::curl_download
  assert_failure
  run dybatpho::curl_download https://github.com
  assert_failure
}

@test "dybatpho::curl_download with output" {
  local temp_file=$BATS_TEST_TMPDIR/test/curl_download
  stub curl ": echo '200'; echo 'hahaa' > $temp_file"
  run dybatpho::curl_download https://github.com "$temp_file"
  assert_success
  assert_file_not_empty "${BATS_TEST_TMPDIR}/test/curl_download"
  unstub curl
}
