setup() {
  load test_helper
}

@test "dybatpho::show_file cat content file" {
  # shellcheck disable=2030
  local temp_file="${BATS_TEST_TMPDIR}/file_has_content"
  local content="Toi la ai day la dau"
  echo "${content}" >> "${temp_file}"
  alias bat="cat -n"
  run dybatpho::show_file "${temp_file}"
  assert_success
  assert_output --partial "${content}"
}

@test "dybatpho::show_file with non-existent file" {
  run --separate-stderr dybatpho::show_file "/non/existent/file.txt"
  assert_failure
}

@test "dybatpho::create_temp with empty variable name" {
  run dybatpho::create_temp "" ".txt"
  assert_failure
  refute_output
}

@test "dybatpho::create_temp with undefined variable name" {
  run dybatpho::create_temp temp_file ".txt"
  assert_success
  refute_output
}

@test "dybatpho::create_temp create temp file" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    dybatpho::create_temp temp_file ".txt"
    # shellcheck disable=2031
    [[ -f ${temp_file} ]] && [[ -n "${temp_file}" ]]
  }
  run _create
  assert_success
  refute_output
}

@test "dybatpho::create_temp create temp folder" {
  # shellcheck disable=2329
  _create() {
    local temp_folder
    dybatpho::create_temp temp_folder "${1:-}"
    # shellcheck disable=2031
    [[ -d ${temp_folder} ]] && [[ -n "${temp_folder}" ]]
  }
  run _create "/"
  assert_success
  refute_output

  run _create ""
  assert_success
  refute_output
}

@test "dybatpho::create_temp create file with prefix" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    dybatpho::create_temp temp_file ".sh" "prefix1"
    # shellcheck disable=2031
    [[ -f ${temp_file} ]] && [[ -n "${temp_file}" ]] && [[ ${temp_file} =~ .*prefix1.* ]]
  }
  run _create
  assert_success
  refute_output
}

@test "dybatpho::create_temp create temp file in not existed folder" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    dybatpho::create_temp temp_file ".txt" "" "/not-existed-folder"
    # shellcheck disable=2031
    [[ -f ${temp_file} ]] && [[ -n "${temp_file}" ]]
  }
  run --separate-stderr _create
  assert_failure
  refute_output
  assert_stderr --partial "is not existed"
}

@test "dybatpho::create_temp create temp file in existed folder, different with TMPDIR" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    dybatpho::create_temp temp_file ".txt" "" "${BATS_TEST_TMPDIR}"
    # shellcheck disable=2031
    [[ -f ${temp_file} ]] && [[ -n "${temp_file}" ]]
  }
  run _create
  assert_success
  refute_output
}

@test "dybatpho::create_temp with different extensions" {
  _create() {
    local temp_file1 temp_file2
    dybatpho::create_temp temp_file1 ".json"
    dybatpho::create_temp temp_file2 ".yaml"
    [[ -f ${temp_file1} ]] && [[ ${temp_file1} =~ .*\.json$ ]] \
      && [[ -f ${temp_file2} ]] && [[ ${temp_file2} =~ .*\.yaml$ ]]
  }
  run _create
  assert_success
  refute_output
}
