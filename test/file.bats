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

@test "dybatpho::file_write_atomic writes stdin and keeps the destination mode" {
  local target="${BATS_TEST_TMPDIR}/atomic.conf"
  printf 'old\n' > "${target}"
  chmod 640 "${target}"
  printf 'new line\nsecond\n' | dybatpho::file_write_atomic "${target}"
  assert_equal "$(cat "${target}")" "$(printf 'new line\nsecond')"
  assert_equal "$(stat -c %a "${target}" 2> /dev/null || stat -f %Lp "${target}")" "640"
}

@test "dybatpho::file_write_atomic replaces the file by rename, not by truncation" {
  local target="${BATS_TEST_TMPDIR}/rename.conf"
  printf 'old\n' > "${target}"
  local before after
  before="$(stat -c %i "${target}" 2> /dev/null || stat -f %i "${target}")"
  printf 'new\n' | dybatpho::file_write_atomic "${target}"
  after="$(stat -c %i "${target}" 2> /dev/null || stat -f %i "${target}")"
  refute [ "${before}" = "${after}" ]
  run find "${BATS_TEST_TMPDIR}" -name '.dybatpho_staging_*'
  assert_output ""
}

@test "dybatpho::file_write_atomic creates a new file and rejects a missing directory" {
  local target="${BATS_TEST_TMPDIR}/created.txt"
  printf 'fresh\n' | dybatpho::file_write_atomic "${target}"
  assert_equal "$(cat "${target}")" "fresh"
  run ! dybatpho::file_write_atomic "${BATS_TEST_TMPDIR}/missing/dir/file"
}

@test "dybatpho::file_replace substitutes every match in place" {
  local target="${BATS_TEST_TMPDIR}/replace.conf"
  printf 'debug = true\nport = 8080\ndebug = true\n' > "${target}"
  dybatpho::file_replace "${target}" '^debug = true$' 'debug = false'
  assert_equal "$(grep -c 'debug = false' "${target}")" "2"
  refute grep -q 'debug = true' "${target}"
}

@test "dybatpho::file_replace picks a delimiter that the arguments do not contain" {
  local target="${BATS_TEST_TMPDIR}/paths.conf"
  printf 'prefix=/usr/local\n' > "${target}"
  dybatpho::file_replace "${target}" '/usr/local' '/opt/tools'
  assert_equal "$(cat "${target}")" "prefix=/opt/tools"
}

@test "dybatpho::file_replace supports back references" {
  local target="${BATS_TEST_TMPDIR}/backref.conf"
  printf 'version 1.2\n' > "${target}"
  dybatpho::file_replace "${target}" 'version \([0-9.]*\)' 'v\1'
  assert_equal "$(cat "${target}")" "v1.2"
}

@test "dybatpho::file_replace leaves the file untouched when sed fails" {
  local target="${BATS_TEST_TMPDIR}/broken.conf"
  printf 'original\n' > "${target}"
  run ! dybatpho::file_replace "${target}" '[unclosed' 'x'
  assert_equal "$(cat "${target}")" "original"
  run find "${BATS_TEST_TMPDIR}" -name '.dybatpho_staging_*'
  assert_output ""
}

@test "dybatpho::file_replace rejects a missing file" {
  run ! dybatpho::file_replace "${BATS_TEST_TMPDIR}/absent" 'a' 'b'
}

@test "dybatpho::file_ensure_line appends once and stays idempotent" {
  local target="${BATS_TEST_TMPDIR}/rc"
  printf 'first\n' > "${target}"
  dybatpho::file_ensure_line "${target}" 'export EDITOR=nvim'
  dybatpho::file_ensure_line "${target}" 'export EDITOR=nvim'
  assert_equal "$(grep -cxF 'export EDITOR=nvim' "${target}")" "1"
  assert_equal "$(head -1 "${target}")" "first"
}

@test "dybatpho::file_ensure_line matches whole lines only" {
  local target="${BATS_TEST_TMPDIR}/whole"
  printf 'export EDITOR=nvim --extra\n' > "${target}"
  dybatpho::file_ensure_line "${target}" 'export EDITOR=nvim'
  assert_equal "$(wc -l < "${target}" | tr -d ' ')" "2"
}

@test "dybatpho::file_ensure_line keeps a missing final newline from joining lines" {
  local target="${BATS_TEST_TMPDIR}/nonewline"
  printf 'no trailing newline' > "${target}"
  dybatpho::file_ensure_line "${target}" 'appended'
  assert_equal "$(sed -n '1p' "${target}")" "no trailing newline"
  assert_equal "$(sed -n '2p' "${target}")" "appended"
}

@test "dybatpho::file_ensure_line creates the file and rejects a missing directory" {
  local target="${BATS_TEST_TMPDIR}/made.rc"
  dybatpho::file_ensure_line "${target}" 'only line'
  assert_equal "$(cat "${target}")" "only line"
  run ! dybatpho::file_ensure_line "${BATS_TEST_TMPDIR}/missing/dir/rc" 'x'
}

@test "dybatpho::file_remove_line removes every occurrence and stays idempotent" {
  local target="${BATS_TEST_TMPDIR}/remove"
  printf 'keep\ndrop\nkeep2\ndrop\n' > "${target}"
  dybatpho::file_remove_line "${target}" 'drop'
  dybatpho::file_remove_line "${target}" 'drop'
  assert_equal "$(cat "${target}")" "$(printf 'keep\nkeep2')"
}

@test "dybatpho::file_remove_line accepts emptying the file and a missing file" {
  local target="${BATS_TEST_TMPDIR}/only"
  printf 'only\n' > "${target}"
  dybatpho::file_remove_line "${target}" 'only'
  assert_equal "$(dybatpho::file_size "${target}")" "0"
  dybatpho::file_remove_line "${BATS_TEST_TMPDIR}/never-existed" 'x'
}

@test "dybatpho::file_hash matches the reference checksum for each algorithm" {
  local target="${BATS_TEST_TMPDIR}/payload"
  printf 'hello\n' > "${target}"
  # Checksums of "hello\n", so the assertion does not merely re-run the code.
  assert_equal "$(dybatpho::file_hash "${target}")" \
    "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
  assert_equal "$(dybatpho::file_hash "${target}" md5)" "b1946ac92492d2347c6235b4d2611184"
  assert_equal "$(dybatpho::file_hash "${target}" sha1)" \
    "f572d396fae9206628714fb2ce00f72e94f2258f"
  local sha512
  sha512="$(dybatpho::file_hash "${target}" sha512)"
  assert_equal "${#sha512}" "128"
}

@test "dybatpho::file_hash accepts an uppercase algorithm and rejects an unknown one" {
  local target="${BATS_TEST_TMPDIR}/payload2"
  printf 'hello\n' > "${target}"
  assert_equal "$(dybatpho::file_hash "${target}" MD5)" "b1946ac92492d2347c6235b4d2611184"
  run ! dybatpho::file_hash "${target}" crc32
  run ! dybatpho::file_hash "${BATS_TEST_TMPDIR}/absent"
}

@test "dybatpho::file_size reports the byte count" {
  local target="${BATS_TEST_TMPDIR}/sized"
  printf '12345' > "${target}"
  assert_equal "$(dybatpho::file_size "${target}")" "5"
  : > "${target}"
  assert_equal "$(dybatpho::file_size "${target}")" "0"
  run ! dybatpho::file_size "${BATS_TEST_TMPDIR}/absent"
}

@test "dybatpho::file_age_seconds grows with the modification time" {
  local target="${BATS_TEST_TMPDIR}/aged"
  printf 'x' > "${target}"
  # A freshly written file is new, but asserting exactly 0 makes the test flaky:
  # under a parallel run the clock can tick between the write and the read.
  assert [ "$(dybatpho::file_age_seconds "${target}")" -lt 5 ]
  touch -t 200001010000 "${target}"
  assert [ "$(dybatpho::file_age_seconds "${target}")" -gt 100000 ]
  run ! dybatpho::file_age_seconds "${BATS_TEST_TMPDIR}/absent"
}

@test "dybatpho::file_age_seconds reports zero for a file modified in the future" {
  local target="${BATS_TEST_TMPDIR}/future"
  printf 'x' > "${target}"
  touch -d '+1 hour' "${target}" 2> /dev/null || touch -A 010000 "${target}"
  assert_equal "$(dybatpho::file_age_seconds "${target}")" "0"
}

@test "dybatpho::file_backup copies the file and prints the copy path" {
  local target="${BATS_TEST_TMPDIR}/backed"
  printf 'content\n' > "${target}"
  chmod 640 "${target}"
  local backup
  backup="$(dybatpho::file_backup "${target}")"
  assert [ -f "${backup}" ]
  assert_equal "$(cat "${backup}")" "content"
  assert_equal "$(stat -c %a "${backup}" 2> /dev/null || stat -f %Lp "${backup}")" "640"
  run ! dybatpho::file_backup "${BATS_TEST_TMPDIR}/absent"
}

@test "dybatpho::file_backup never overwrites an existing backup" {
  local target="${BATS_TEST_TMPDIR}/twice"
  printf 'content\n' > "${target}"
  local first second
  first="$(dybatpho::file_backup "${target}")"
  second="$(dybatpho::file_backup "${target}")"
  refute [ "${first}" = "${second}" ]
  assert [ -f "${first}" ]
  assert [ -f "${second}" ]
}

@test "the file writers report their work without touching anything under DRY_RUN" {
  local target="${BATS_TEST_TMPDIR}/dry.conf"
  printf 'keep = 1\n' > "${target}"
  local backup
  # shellcheck disable=2030
  export DRY_RUN=true
  printf 'clobbered\n' | dybatpho::file_write_atomic "${target}"
  dybatpho::file_replace "${target}" 'keep' 'gone'
  dybatpho::file_ensure_line "${target}" 'added'
  dybatpho::file_remove_line "${target}" 'keep = 1'
  backup="$(dybatpho::file_backup "${target}" | tail -1)"
  unset DRY_RUN
  assert_equal "$(cat "${target}")" "keep = 1"
  refute [ -e "${backup}" ]
  run find "${BATS_TEST_TMPDIR}" -name '.dybatpho_staging_*'
  assert_output ""
}

@test "the file writers write through a symlink instead of replacing it" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${repo}"
  printf 'tracked\n' > "${repo}/bashrc"
  local link="${BATS_TEST_TMPDIR}/.bashrc"
  ln -s "${repo}/bashrc" "${link}"

  printf 'rewritten\n' | dybatpho::file_write_atomic "${link}"
  assert [ -L "${link}" ]
  assert_equal "$(cat "${repo}/bashrc")" "rewritten"

  dybatpho::file_ensure_line "${link}" 'added'
  dybatpho::file_replace "${link}" 'rewritten' 'edited'
  dybatpho::file_remove_line "${link}" 'added'
  assert [ -L "${link}" ]
  assert_equal "$(cat "${repo}/bashrc")" "edited"
}

@test "the file writers follow a chain of symlinks" {
  local target="${BATS_TEST_TMPDIR}/target"
  printf 'first\n' > "${target}"
  ln -s "${target}" "${BATS_TEST_TMPDIR}/middle"
  ln -s "${BATS_TEST_TMPDIR}/middle" "${BATS_TEST_TMPDIR}/outer"
  printf 'second\n' | dybatpho::file_write_atomic "${BATS_TEST_TMPDIR}/outer"
  assert [ -L "${BATS_TEST_TMPDIR}/outer" ]
  assert_equal "$(cat "${target}")" "second"
}

@test "the file writers follow a relative symlink" {
  mkdir -p "${BATS_TEST_TMPDIR}/nested"
  printf 'original\n' > "${BATS_TEST_TMPDIR}/nested/real"
  ln -s "nested/real" "${BATS_TEST_TMPDIR}/relative"
  printf 'through\n' | dybatpho::file_write_atomic "${BATS_TEST_TMPDIR}/relative"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/nested/real")" "through"
}

@test "DYBATPHO_FILE_FOLLOW_SYMLINKS=false replaces the symlink instead" {
  local repo="${BATS_TEST_TMPDIR}/repo2"
  mkdir -p "${repo}"
  printf 'tracked\n' > "${repo}/rc"
  local link="${BATS_TEST_TMPDIR}/rc-link"
  ln -s "${repo}/rc" "${link}"
  # shellcheck disable=2030
  DYBATPHO_FILE_FOLLOW_SYMLINKS=false
  printf 'detached\n' | dybatpho::file_write_atomic "${link}"
  DYBATPHO_FILE_FOLLOW_SYMLINKS=true
  refute [ -L "${link}" ]
  assert_equal "$(cat "${link}")" "detached"
  assert_equal "$(cat "${repo}/rc")" "tracked"
}

@test "a symlink loop is reported instead of hanging" {
  ln -s "${BATS_TEST_TMPDIR}/loop_b" "${BATS_TEST_TMPDIR}/loop_a"
  ln -s "${BATS_TEST_TMPDIR}/loop_a" "${BATS_TEST_TMPDIR}/loop_b"
  run ! dybatpho::file_ensure_line "${BATS_TEST_TMPDIR}/loop_a" 'x'
  assert_output --partial "Too many levels of symbolic links"
}

@test "file metadata describes the target of a symlink, not the link" {
  local target="${BATS_TEST_TMPDIR}/sized_target"
  printf '0123456789\n' > "${target}"
  local link="${BATS_TEST_TMPDIR}/sized_link"
  ln -s "${target}" "${link}"
  assert_equal "$(dybatpho::file_size "${link}")" "$(dybatpho::file_size "${target}")"
  assert_equal "$(dybatpho::file_size "${link}")" "11"
  touch -t 200001010000 "${target}"
  assert [ "$(dybatpho::file_age_seconds "${link}")" -gt 100000 ]
}

@test "dybatpho::find_up finds an entry in the starting directory and above it" {
  mkdir -p "${BATS_TEST_TMPDIR}/proj/a/b"
  : > "${BATS_TEST_TMPDIR}/proj/.marker"
  assert_equal "$(dybatpho::find_up ".marker" "${BATS_TEST_TMPDIR}/proj/a/b")" \
    "${BATS_TEST_TMPDIR}/proj/.marker"
  assert_equal "$(dybatpho::find_up ".marker" "${BATS_TEST_TMPDIR}/proj")" \
    "${BATS_TEST_TMPDIR}/proj/.marker"
}

@test "dybatpho::find_up matches a directory as well as a file" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo3/.git" "${BATS_TEST_TMPDIR}/repo3/src"
  assert_equal "$(dybatpho::find_up ".git" "${BATS_TEST_TMPDIR}/repo3/src")" \
    "${BATS_TEST_TMPDIR}/repo3/.git"
}

@test "dybatpho::find_up defaults to the current directory" {
  mkdir -p "${BATS_TEST_TMPDIR}/cwd_proj/sub"
  : > "${BATS_TEST_TMPDIR}/cwd_proj/.here"
  cd "${BATS_TEST_TMPDIR}/cwd_proj/sub"
  assert_equal "$(dybatpho::find_up ".here")" "${BATS_TEST_TMPDIR}/cwd_proj/.here"
}

@test "dybatpho::find_up reports failure without output when nothing matches" {
  run -1 dybatpho::find_up "dybatpho-no-such-marker-xyz" "${BATS_TEST_TMPDIR}"
  assert_output ""
}

@test "dybatpho::find_up rejects a start directory that does not exist" {
  run ! dybatpho::find_up ".marker" "${BATS_TEST_TMPDIR}/missing"
}

@test "dybatpho::ensure_dir creates nested directories and prints the path" {
  local target="${BATS_TEST_TMPDIR}/deep/nested/dir"
  assert_equal "$(dybatpho::ensure_dir "${target}")" "${target}"
  assert [ -d "${target}" ]
}

@test "dybatpho::ensure_dir is idempotent and applies the requested mode" {
  local target="${BATS_TEST_TMPDIR}/moded"
  dybatpho::ensure_dir "${target}" 700 > /dev/null
  assert_equal "$(stat -c %a "${target}" 2> /dev/null || stat -f %Lp "${target}")" "700"
  # An existing directory is brought to the requested mode as well, so the
  # result does not depend on whether the script ran before.
  dybatpho::ensure_dir "${target}" 755 > /dev/null
  assert [ -d "${target}" ]
  assert_equal "$(stat -c %a "${target}" 2> /dev/null || stat -f %Lp "${target}")" "755"
}

@test "dybatpho::ensure_dir rejects a path that exists as a file" {
  local target="${BATS_TEST_TMPDIR}/not_a_dir"
  printf 'x' > "${target}"
  run ! dybatpho::ensure_dir "${target}"
}

@test "dybatpho::ensure_dir creates nothing under DRY_RUN but still prints the path" {
  local target="${BATS_TEST_TMPDIR}/dry_dir"
  # shellcheck disable=2030
  export DRY_RUN=true
  local printed
  printed="$(dybatpho::ensure_dir "${target}" 700 | tail -1)"
  unset DRY_RUN
  assert_equal "${printed}" "${target}"
  refute [ -d "${target}" ]
}

@test "the file helpers reject an empty path instead of writing into the current directory" {
  cd "${BATS_TEST_TMPDIR}"
  run ! dybatpho::file_write_atomic ""
  run ! dybatpho::file_replace "" 'a' 'b'
  run ! dybatpho::file_ensure_line "" 'x'
  run ! dybatpho::file_remove_line "" 'x'
  run ! dybatpho::ensure_dir ""
  run find "${BATS_TEST_TMPDIR}" -name '.dybatpho_staging_*'
  assert_output ""
}

@test "a rewrite that cannot be committed leaves no staging file behind" {
  local dir="${BATS_TEST_TMPDIR}/readonly"
  mkdir -p "${dir}"
  printf 'original\n' > "${dir}/f"
  chmod 500 "${dir}"
  run ! dybatpho::file_write_atomic "${dir}/f"
  chmod 700 "${dir}"
  assert_equal "$(cat "${dir}/f")" "original"
  run find "${dir}" -name '.dybatpho_staging_*'
  assert_output ""
}
