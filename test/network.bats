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

@test "dybatpho::curl_do with more than 2 parameters" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  stub curl ": echo \"\$*\" > ${temp_file}; echo '200'"
  run dybatpho::curl_do https://this "${temp_file}" --header "X-Test: 1"
  assert_success
  grep "header X-Test: 1" "${temp_file}"
  unstub curl
}

@test "dybatpho::curl_do with status code 200" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  stub curl ": echo '200'; echo 'hahaa' > ${temp_file}"
  run dybatpho::curl_do https://this "${temp_file}"
  assert_success
  assert_file_not_empty "${BATS_TEST_TMPDIR}/curl_do"
  unstub curl
}

@test "dybatpho::curl_do with status code 404" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  stub curl ": echo '404'"
  run -4 dybatpho::curl_do https://this "${temp_file}"
  assert_failure
  unstub curl
}

@test "dybatpho::curl_do with retries success" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  stub curl \
    ": echo '300'" \
    ": echo '500'" \
    ": echo '200'; echo 'hahaa' > ${temp_file}"
  run dybatpho::curl_do https://this "${temp_file}"
  assert_success
  assert_file_not_empty "${BATS_TEST_TMPDIR}/curl_do"
  unstub curl
}

@test "dybatpho::curl_do with retries failed" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  DYBATPHO_CURL_MAX_RETRIES=1
  stub curl \
    ": echo '300'" \
    ": echo '300'" \
    ": echo '500'" \
    ": echo '500'" \
    ": echo '101'" \
    ": echo '101'"
  run -3 dybatpho::curl_do https://this "${temp_file}"
  assert_failure
  run -5 dybatpho::curl_do https://this "${temp_file}"
  assert_failure
  run -1 dybatpho::curl_do https://this "${temp_file}"
  assert_failure
  unstub curl
}

@test "dybatpho::curl_download not have right spec" {
  run dybatpho::curl_download
  assert_failure
  run dybatpho::curl_download https://github.com
  assert_failure
}

@test "dybatpho::curl_download with output" {
  local temp_file=${BATS_TEST_TMPDIR}/test/curl_download
  stub curl ": echo '200'; echo 'hahaa' > ${temp_file}"
  run dybatpho::curl_download https://github.com "${temp_file}"
  assert_success
  assert_file_not_empty "${BATS_TEST_TMPDIR}/test/curl_download"
  unstub curl
}

@test "dybatpho::curl_download with more than 2 parameters" {
  local temp_file="${BATS_TEST_TMPDIR}/test/curl_download"
  stub curl ": echo \"\$*\" > ${temp_file}; echo '200'"
  run dybatpho::curl_download https://this "${temp_file}" --header "X-Test: 1"
  assert_success
  grep "header X-Test: 1" "${temp_file}"
  unstub curl
}
