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

@test "__get_http_code with unknown code" {
  run __get_http_code 999
  assert_success
  assert_output "999 (unknown)"
}

@test "dybatpho::curl_do no arg" {
  run dybatpho::curl_do
  assert_failure
}

@test "dybatpho::curl_do with empty url" {
  run --separate-stderr dybatpho::curl_do ""
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

@test "dybatpho::curl_do header with space in value is passed as single argument" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do_header"
  # Write each curl argument on its own line so we can verify quoting
  stub curl ": printf '%s\n' \"\$@\" > ${temp_file}; echo '200'"
  run dybatpho::curl_do https://this "${temp_file}" -H "Authorization: Bearer mytoken"
  assert_success
  # The full header value must appear on one line, not split
  grep "^Authorization: Bearer mytoken$" "${temp_file}"
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

@test "dybatpho::curl_do without stub" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  echo -e "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n" | nc -l 8080 &
  sleep 1
  run dybatpho::curl_do http://localhost:8080 "${temp_file}"
  assert_success
  refute_output
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
  export DYBATPHO_CURL_MAX_RETRIES=1
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

@test "dybatpho::curl_do with curl command failure" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_do"
  export DYBATPHO_CURL_MAX_RETRIES=0
  stub curl ": return 1"
  run --separate-stderr -1 dybatpho::curl_do https://this "${temp_file}"
  unstub curl
  assert_failure
  assert_stderr --partial "Error when access https://this"
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

@test "dybatpho::curl_download adds progress flags" {
  local temp_file="${BATS_TEST_TMPDIR}/test/curl_download_flags"
  stub curl ": echo \"\$*\" > ${temp_file}; echo '200'"
  run dybatpho::curl_download https://this "${temp_file}"
  assert_success
  grep -- "-#" "${temp_file}"
  grep -- "--no-silent" "${temp_file}"
  unstub curl
}

@test "dybatpho::curl_download to readonly directory" {
  run --separate-stderr -6 dybatpho::curl_download https://example.com /root/readonly/file.txt
  assert_failure
}

@test "dybatpho::curl_json adds JSON headers" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_json"
  stub curl ": echo \"\$*\" > ${temp_file}; echo '200'"
  run dybatpho::curl_json https://this "${temp_file}" --request POST
  assert_success
  grep -- '--header Accept: application/json' "${temp_file}"
  grep -- '--header Content-Type: application/json' "${temp_file}"
  grep -- '--request POST' "${temp_file}"
  unstub curl
}

@test "dybatpho::curl_head adds HEAD mode" {
  local temp_file="${BATS_TEST_TMPDIR}/curl_head"
  stub curl ": echo \"\$*\" > ${temp_file}; echo '200'"
  run dybatpho::curl_head https://this "${temp_file}" --header "X-Test: 1"
  assert_success
  grep -- '-I' "${temp_file}"
  grep -- '--header X-Test: 1' "${temp_file}"
  unstub curl
}
