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

@test "dybatpho::path_dirname returns directory component" {
  run dybatpho::path_dirname "/tmp/demo/file.txt"
  assert_success
  assert_output "/tmp/demo"
}

@test "dybatpho::path_dirname handles root and relative file" {
  run dybatpho::path_dirname "/"
  assert_success
  assert_output "/"

  run dybatpho::path_dirname "file.txt"
  assert_success
  assert_output "."
}

@test "dybatpho::path_basename returns basename component" {
  run dybatpho::path_basename "/tmp/demo/file.txt"
  assert_success
  assert_output "file.txt"
}

@test "dybatpho::path_basename strips suffix and trailing slash" {
  run dybatpho::path_basename "/tmp/demo/archive.tar.gz/" ".gz"
  assert_success
  assert_output "archive.tar"
}

@test "dybatpho::path_extname returns final extension" {
  run dybatpho::path_extname "/tmp/demo/archive.tar.gz"
  assert_success
  assert_output ".gz"
}

@test "dybatpho::path_extname handles hidden file and extensionless file" {
  run dybatpho::path_extname ".bashrc"
  assert_success
  assert_output ""

  run dybatpho::path_extname ".config.json"
  assert_success
  assert_output ".json"

  run dybatpho::path_extname "README"
  assert_success
  assert_output ""
}

@test "dybatpho::path_stem strips final extension only" {
  run dybatpho::path_stem "/tmp/demo/archive.tar.gz"
  assert_success
  assert_output "archive.tar"
}

@test "dybatpho::path_stem keeps hidden file unchanged" {
  run dybatpho::path_stem ".bashrc"
  assert_success
  assert_output ".bashrc"

  run dybatpho::path_stem ".config.json"
  assert_success
  assert_output ".config"
}

@test "dybatpho::path_join joins relative and absolute segments cleanly" {
  run dybatpho::path_join "/tmp/" "/demo/" "archive.tar.gz"
  assert_success
  assert_output "/tmp/demo/archive.tar.gz"

  run dybatpho::path_join "var" "log" "dybatpho"
  assert_success
  assert_output "var/log/dybatpho"
}

@test "dybatpho::path_join ignores empty segments and preserves root" {
  run dybatpho::path_join "" "/" "" "tmp" "" "cache/"
  assert_success
  assert_output "/tmp/cache"

  run dybatpho::path_join "/" "" ""
  assert_success
  assert_output "/"
}

@test "dybatpho::path_normalize resolves dots and duplicate separators" {
  run dybatpho::path_normalize "/tmp//demo/./cache/../data.json"
  assert_success
  assert_output "/tmp/demo/data.json"

  run dybatpho::path_normalize "var//log/../tmp/./app/"
  assert_success
  assert_output "var/tmp/app"
}

@test "dybatpho::path_normalize preserves relative parent traversal and clamps root" {
  run dybatpho::path_normalize "../../foo/../bar"
  assert_success
  assert_output "../../bar"

  run dybatpho::path_normalize "/../../tmp"
  assert_success
  assert_output "/tmp"

  run dybatpho::path_normalize ""
  assert_success
  assert_output "."
}

@test "dybatpho::path_is_abs and dybatpho::path_has_ext inspect paths" {
  run dybatpho::path_is_abs "/tmp/demo"
  assert_success

  run dybatpho::path_is_abs "tmp/demo"
  assert_failure

  run dybatpho::path_has_ext "archive.tar.gz"
  assert_success

  run dybatpho::path_has_ext "archive.tar.gz" ".gz"
  assert_success

  run dybatpho::path_has_ext "archive.tar.gz" "zip"
  assert_failure
}

@test "dybatpho::path_change_ext rewrites and removes final extensions" {
  run dybatpho::path_change_ext "/tmp/demo/archive.tar.gz" ".zip"
  assert_success
  assert_output "/tmp/demo/archive.tar.zip"

  run dybatpho::path_change_ext "README.md" ""
  assert_success
  assert_output "README"
}

@test "dybatpho::path_relative computes textual relative paths" {
  run dybatpho::path_relative "/tmp/demo/cache/data.json" "/tmp/demo"
  assert_success
  assert_output "cache/data.json"

  run dybatpho::path_relative "/tmp/demo/cache" "/tmp/demo/cache"
  assert_success
  assert_output "."

  run dybatpho::path_relative "src/lib/file.sh" "src/test"
  assert_success
  assert_output "../lib/file.sh"
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

@test "dybatpho::create_temp uses TMPDIR by default" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    export TMPDIR="${BATS_TEST_TMPDIR}"
    dybatpho::create_temp temp_file ".txt"
    [[ -f ${temp_file} ]] && [[ ${temp_file} == "${BATS_TEST_TMPDIR}"/* ]]
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

@test "dybatpho::create_temp sanitizes extension suffix" {
  # shellcheck disable=2329
  _create() {
    local temp_file
    dybatpho::create_temp temp_file ".txt/../../ignored"
    [[ -f ${temp_file} ]] && [[ ${temp_file} =~ \.txt$ ]] && [[ ${temp_file} != *ignored* ]]
  }
  run _create
  assert_success
  refute_output
}

@test "dybatpho::create_temp cleans up temp files and folders on shell exit" {
  local cleanup_script="${BATS_TEST_TMPDIR}/cleanup-check.sh"
  local temp_path_file="${BATS_TEST_TMPDIR}/created-path.txt"
  cat > "${cleanup_script}" << EOF
#!/usr/bin/env bash
set -euo pipefail
. "${BATS_TEST_DIRNAME}/../init.sh"
dybatpho::register_common_handlers
temp_file=""
temp_dir=""
dybatpho::create_temp temp_file ".txt"
  dybatpho::create_temp temp_dir "/"
  printf '%s\n%s\n' "\${temp_file}" "\${temp_dir}" > "${temp_path_file}"
EOF
  chmod +x "${cleanup_script}"
  env -i PATH="${PATH}" HOME="${HOME}" TMPDIR="${BATS_TEST_TMPDIR}" bash "${cleanup_script}"
  local created_file created_dir
  mapfile -t created_paths < "${temp_path_file}"
  created_file="${created_paths[0]}"
  created_dir="${created_paths[1]}"
  [[ ! -e "${created_file}" ]]
  [[ ! -e "${created_dir}" ]]
}
