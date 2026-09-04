setup() {
  load test_helper
}

@test "dybatpho::show_file cat content file" {
  # shellcheck disable=2030
  local temp_file="${BATS_TEST_TMPDIR}/file_has_content"
  local content="Toi la ai day la dau"
  echo "${content}" >> "${temp_file}"
  alias bat="cat -n"
  # Called directly first, then through `run` to assert what it printed.
  dybatpho::show_file "${temp_file}"
  # show_file writes to stderr, so the capturing form of `run` is required here.
  run dybatpho::show_file "${temp_file}"
  assert_success
  assert_output --partial "${content}"
}

@test "dybatpho::show_file with non-existent file" {
  run --separate-stderr dybatpho::show_file "/non/existent/file.txt"
  assert_failure
}

@test "dybatpho::path_dirname returns directory component" {
  assert_equal "$(dybatpho::path_dirname "/tmp/demo/file.txt")" "/tmp/demo"
}

@test "dybatpho::path_dirname handles root and relative file" {
  assert_equal "$(dybatpho::path_dirname "/")" "/"

  assert_equal "$(dybatpho::path_dirname "file.txt")" "."
}

@test "dybatpho::path_basename returns basename component" {
  assert_equal "$(dybatpho::path_basename "/tmp/demo/file.txt")" "file.txt"
}

@test "dybatpho::path_basename strips suffix and trailing slash" {
  assert_equal "$(dybatpho::path_basename "/tmp/demo/archive.tar.gz/" ".gz")" "archive.tar"
}

@test "dybatpho::path_extname returns final extension" {
  assert_equal "$(dybatpho::path_extname "/tmp/demo/archive.tar.gz")" ".gz"
}

@test "dybatpho::path_extname handles hidden file and extensionless file" {
  assert_equal "$(dybatpho::path_extname ".bashrc")" ""

  assert_equal "$(dybatpho::path_extname ".config.json")" ".json"

  assert_equal "$(dybatpho::path_extname "README")" ""
}

@test "dybatpho::path_stem strips final extension only" {
  assert_equal "$(dybatpho::path_stem "/tmp/demo/archive.tar.gz")" "archive.tar"
}

@test "dybatpho::path_stem keeps hidden file unchanged" {
  assert_equal "$(dybatpho::path_stem ".bashrc")" ".bashrc"

  assert_equal "$(dybatpho::path_stem ".config.json")" ".config"
}

@test "dybatpho::path_join joins relative and absolute segments cleanly" {
  assert_equal "$(dybatpho::path_join "/tmp/" "/demo/" "archive.tar.gz")" "/tmp/demo/archive.tar.gz"

  assert_equal "$(dybatpho::path_join "var" "log" "dybatpho")" "var/log/dybatpho"
}

@test "dybatpho::path_join ignores empty segments and preserves root" {
  assert_equal "$(dybatpho::path_join "" "/" "" "tmp" "" "cache/")" "/tmp/cache"

  assert_equal "$(dybatpho::path_join "/" "" "")" "/"
}

@test "dybatpho::path_normalize resolves dots and duplicate separators" {
  assert_equal "$(dybatpho::path_normalize "/tmp//demo/./cache/../data.json")" "/tmp/demo/data.json"

  assert_equal "$(dybatpho::path_normalize "var//log/../tmp/./app/")" "var/tmp/app"
}

@test "dybatpho::path_normalize preserves relative parent traversal and clamps root" {
  assert_equal "$(dybatpho::path_normalize "../../foo/../bar")" "../../bar"

  assert_equal "$(dybatpho::path_normalize "/../../tmp")" "/tmp"

  assert_equal "$(dybatpho::path_normalize "")" "."
}

@test "dybatpho::path_is_abs and dybatpho::path_has_ext inspect paths" {
  dybatpho::path_is_abs "/tmp/demo"
  run ! dybatpho::path_is_abs "tmp/demo"
  dybatpho::path_has_ext "archive.tar.gz"
  dybatpho::path_has_ext "archive.tar.gz" ".gz"
  run ! dybatpho::path_has_ext "archive.tar.gz" "zip"
  run ! dybatpho::path_has_ext "plainfile"

  run dybatpho::path_is_abs "tmp/demo"
  assert_failure

  run dybatpho::path_has_ext "archive.tar.gz" "zip"
  assert_failure
}

@test "dybatpho::path_change_ext rewrites and removes final extensions" {
  assert_equal "$(dybatpho::path_change_ext "/tmp/demo/archive.tar.gz" ".zip")" "/tmp/demo/archive.tar.zip"

  assert_equal "$(dybatpho::path_change_ext "README.md" "")" "README"
}

@test "dybatpho::path_relative computes textual relative paths" {
  assert_equal "$(dybatpho::path_relative "/tmp/demo/cache/data.json" "/tmp/demo")" "cache/data.json"

  assert_equal "$(dybatpho::path_relative "/tmp/demo/cache" "/tmp/demo/cache")" "."

  assert_equal "$(dybatpho::path_relative "src/lib/file.sh" "src/test")" "../lib/file.sh"
}

@test "dybatpho::create_temp with empty variable name" {
  run ! dybatpho::create_temp "" ".txt"
  run dybatpho::create_temp "" ".txt"
  assert_failure
  refute_output
}

@test "dybatpho::create_temp with undefined variable name" {
  run_traced dybatpho::create_temp temp_file ".txt"
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
  run_traced _create
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
  run_traced _create "/"
  assert_success
  refute_output

  run_traced _create ""
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
  run_traced _create
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
  run_traced _create
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
  run_traced _create
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
  run_traced _create
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
  run_traced _create
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

@test "path helpers handle trailing slashes, roots, and dotted names" {
  assert_equal "$(dybatpho::path_dirname "/tmp/demo/")" "/tmp"
  assert_equal "$(dybatpho::path_basename "/")" "/"
  assert_equal "$(dybatpho::path_basename "/tmp/demo/")" "demo"
  assert_equal "$(dybatpho::path_extname "archive.")" ""
  assert_equal "$(dybatpho::path_extname "/")" ""
  assert_equal "$(dybatpho::path_extname ".bashrc")" ""
  assert_equal "$(dybatpho::path_extname "plain")" ""
}

@test "dybatpho::path_normalize resolves to the current directory" {
  assert_equal "$(dybatpho::path_normalize "demo/..")" "."
  assert_equal "$(dybatpho::path_normalize "demo/../var/log")" "var/log"
}

@test "dybatpho::path_change_ext accepts an extension without a leading dot" {
  assert_equal "$(dybatpho::path_change_ext "notes.txt" "md")" "notes.md"
}

@test "dybatpho::path_relative handles mixed roots and identical paths" {
  assert_equal "$(dybatpho::path_relative "/var/log" "relative/base")" "/var/log"
  assert_equal "$(dybatpho::path_relative "/var/log" "/var/log")" "."
  assert_equal "$(dybatpho::path_relative "/var/log/app" "/var/cache")" "../log/app"
}
