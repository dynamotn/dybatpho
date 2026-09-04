setup() {
  load test_helper
  dybatpho::secret_forget
  DYBATPHO_SECRET_PLACEHOLDER="***"
  DYBATPHO_SECRET_MIN_LENGTH=4
  DYBATPHO_SECRET_MAX_MODE=600
  DYBATPHO_SECRET_STRICT_PERMS=true
}

teardown() {
  dybatpho::secret_forget
}

@test "secret_from_file reads a private file and masks it in logs" {
  local file="${BATS_TEST_TMPDIR}/token"
  printf 'super-secret-token\n' > "${file}"
  chmod 600 "${file}"

  local TOKEN
  dybatpho::secret_from_file TOKEN "${file}"
  assert_equal "${TOKEN}" "super-secret-token"

  run --separate-stderr dybatpho::error "call failed with ${TOKEN}"
  assert_stderr --partial "call failed with ***"
  refute_stderr --partial "super-secret-token"
}

@test "secret_from_file rejects missing, empty, and non-regular files" {
  run dybatpho::secret_from_file TOKEN "${BATS_TEST_TMPDIR}/absent"
  assert_failure
  assert_output --partial "Secret file not found"

  local empty="${BATS_TEST_TMPDIR}/empty"
  : > "${empty}"
  chmod 600 "${empty}"
  run dybatpho::secret_from_file TOKEN "${empty}"
  assert_failure
  assert_output --partial "Secret file is empty"

  run dybatpho::secret_from_file TOKEN "${BATS_TEST_TMPDIR}"
  assert_failure
  assert_output --partial "isn't a regular file"

  local file="${BATS_TEST_TMPDIR}/valid"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"
  run dybatpho::secret_from_file 1invalid "${file}"
  assert_failure
  assert_output --partial "Invalid variable name"
}

@test "secret_check_permission fails on group or world readable files" {
  local file="${BATS_TEST_TMPDIR}/loose"
  printf 'value-of-secret\n' > "${file}"
  chmod 644 "${file}"

  # A permissive mode only warns when strict checking is disabled.
  DYBATPHO_SECRET_STRICT_PERMS=false
  dybatpho::secret_check_permission "${file}"
  DYBATPHO_SECRET_STRICT_PERMS=true
  dybatpho::secret_check_permission "${file}" 644

  run dybatpho::secret_check_permission "${file}"
  assert_failure
  assert_output --partial "has mode 0644, expected at most 0600"

  DYBATPHO_SECRET_STRICT_PERMS=false
  run --separate-stderr dybatpho::secret_check_permission "${file}"
  assert_success
  assert_stderr --partial "expected at most 0600"
}

@test "secret_check_permission rejects an invalid mode and warns about symlinks" {
  local file="${BATS_TEST_TMPDIR}/link-target"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"

  run dybatpho::secret_check_permission "${file}" 8000
  assert_failure
  assert_output --partial "Invalid octal mode"

  local link="${BATS_TEST_TMPDIR}/link"
  ln -sf "${file}" "${link}"
  run --separate-stderr dybatpho::secret_check_permission "${link}"
  assert_success
  assert_stderr --partial "symbolic link"
}

@test "secret_from_env copies the value and unsets the source variable" {
  export APP_TOKEN="environment-secret"
  local TOKEN
  dybatpho::secret_from_env TOKEN APP_TOKEN
  assert_equal "${TOKEN}" "environment-secret"
  assert_equal "${APP_TOKEN:-gone}" "gone"

  export APP_TOKEN="environment-secret"
  dybatpho::secret_from_env TOKEN APP_TOKEN keep
  assert_equal "${APP_TOKEN}" "environment-secret"
  unset APP_TOKEN
}

@test "secret_from_env validates its arguments" {
  unset APP_TOKEN || true
  run dybatpho::secret_from_env TOKEN APP_TOKEN
  assert_failure
  assert_output --partial "isn't set or is empty"

  export APP_TOKEN="environment-secret"
  run dybatpho::secret_from_env TOKEN APP_TOKEN maybe
  assert_failure
  assert_output --partial "Expected \`keep\` or \`unset\`"

  run dybatpho::secret_from_env TOKEN "bad-name"
  assert_failure
  assert_output --partial "Invalid environment variable name"
  unset APP_TOKEN
}

@test "secret_from_stdin reads one line without echoing it" {
  local TOKEN
  dybatpho::secret_from_stdin TOKEN < <(printf 'stdin-secret\nignored\n')
  assert_equal "${TOKEN}" "stdin-secret"

  run dybatpho::secret_from_stdin OTHER < /dev/null
  assert_failure
  assert_output --partial "No secret was read from stdin"
}

@test "secret_read dispatches to file, environment, and stdin sources" {
  local file="${BATS_TEST_TMPDIR}/token"
  printf 'file-secret-value\n' > "${file}"
  chmod 600 "${file}"

  local FROM_FILE FROM_ENV FROM_STDIN
  dybatpho::secret_read FROM_FILE "file:${file}"
  assert_equal "${FROM_FILE}" "file-secret-value"

  export APP_TOKEN="env-secret-value"
  dybatpho::secret_read FROM_ENV env:APP_TOKEN
  assert_equal "${FROM_ENV}" "env-secret-value"

  dybatpho::secret_read FROM_STDIN - < <(printf 'stdin-secret-value\n')
  assert_equal "${FROM_STDIN}" "stdin-secret-value"

  run dybatpho::secret_read TOKEN vault:secret/app
  assert_failure
  assert_output --partial "Unsupported secret source"
}

@test "secret_mask masks arguments and stdin, longest match first" {
  dybatpho::secret_register "token-value" "token-value-extended"

  local masked="${BATS_TEST_TMPDIR}/masked"
  dybatpho::secret_mask "authorization: token-value-extended" > "${masked}"
  assert_equal "$(< "${masked}")" "authorization: ***"

  local input="${BATS_TEST_TMPDIR}/input"
  printf 'a=%s\nb=%s\n' "token-value" "other" > "${input}"
  dybatpho::secret_mask < "${input}" > "${masked}"
  assert_equal "$(< "${masked}")" "$(printf 'a=***\nb=other')"
}

@test "secret_mask keeps output unchanged when nothing is registered" {
  local masked="${BATS_TEST_TMPDIR}/masked"
  dybatpho::secret_mask "nothing to hide" > "${masked}"
  assert_equal "$(< "${masked}")" "nothing to hide"
}

@test "secret_register rejects no arguments and skips short values" {
  dybatpho::secret_register "ab"
  assert_equal "${DYBATPHO_SECRET_COUNT}" "0"

  run dybatpho::secret_register
  assert_failure
  assert_output --partial "Expected at least one value"

  run --separate-stderr dybatpho::secret_register "ab"
  assert_success
  assert_stderr --partial "shorter than 4 characters"
}

@test "secret_register masks each line of a multiline secret" {
  dybatpho::secret_register "$(printf 'first-line-secret\nsecond-line-secret')"

  assert_equal "$(dybatpho::secret_mask "leaked second-line-secret here")" "leaked *** here"
}

@test "secret_forget stops masking" {
  dybatpho::secret_register "forgettable-secret"
  dybatpho::secret_forget
  assert_equal "${DYBATPHO_SECRET_COUNT}" "0"
  assert_equal "$(dybatpho::secret_mask "forgettable-secret")" "forgettable-secret"
}

@test "secret_mask_run masks command output and preserves the exit code" {
  dybatpho::secret_register "runtime-secret"

  local masked="${BATS_TEST_TMPDIR}/masked" status=0
  dybatpho::secret_mask_run bash -c \
    'printf "out %s\n" "runtime-secret"; printf "err %s\n" "runtime-secret" >&2; exit 3' \
    > "${masked}" || status=$?
  assert_equal "${status}" "3"
  assert_file_contains "${masked}" "out \\*\\*\\*"
  assert_file_contains "${masked}" "err \\*\\*\\*"
  assert_file_not_contains "${masked}" "runtime-secret"

  dybatpho::secret_mask_run true > "${masked}"

  run dybatpho::secret_mask_run
  assert_failure
  assert_output --partial "Expected a command"
}

@test "secret_hint reveals only the suffix of a secret" {
  local hint="${BATS_TEST_TMPDIR}/hint"
  dybatpho::secret_hint "abcdefghij" > "${hint}"
  assert_equal "$(< "${hint}")" "***ghij"

  dybatpho::secret_hint "abcdefghij" 2 > "${hint}"
  assert_equal "$(< "${hint}")" "***ij"

  dybatpho::secret_hint "short" > "${hint}"
  assert_equal "$(< "${hint}")" "***"

  run dybatpho::secret_hint "abcdefghij" two
  assert_failure
  assert_output --partial "Expected a number"
}

@test "secret_write_file creates a 0600 file that round-trips" {
  local TOKEN="written-secret-value"
  local file="${BATS_TEST_TMPDIR}/written"
  dybatpho::secret_write_file "${file}" TOKEN

  local RELOADED
  dybatpho::secret_from_file RELOADED "${file}"
  assert_equal "${RELOADED}" "written-secret-value"
  assert_equal "$(stat -L -c '%a' "${file}")" "600"
}

@test "secret_write_file validates its destination and source variable" {
  local TOKEN="written-secret-value"
  run dybatpho::secret_write_file "${BATS_TEST_TMPDIR}/absent/dir/file" TOKEN
  assert_failure
  assert_output --partial "Directory of secret file doesn't exist"

  local EMPTY=""
  run dybatpho::secret_write_file "${BATS_TEST_TMPDIR}/file" EMPTY
  assert_failure
  assert_output --partial "is empty"
}

@test "secret_with_file exposes the secret through a file descriptor" {
  local TOKEN="descriptor-secret"
  local consumed="${BATS_TEST_TMPDIR}/consumed" status=0
  dybatpho::secret_with_file TOKEN cat '{}' > "${consumed}"
  assert_equal "$(< "${consumed}")" "descriptor-secret"

  dybatpho::secret_with_file TOKEN bash -c '[[ "$1" == /dev/fd/* ]]' _ '{}'

  dybatpho::secret_with_file TOKEN false || status=$?
  assert_equal "${status}" "1"

  run dybatpho::secret_with_file TOKEN
  assert_failure
  assert_output --partial "Expected a command"
}

@test "secret_wipe clears variables and secret_shred removes files" {
  local TOKEN="wipeable-secret"
  dybatpho::secret_register "${TOKEN}"
  dybatpho::secret_wipe TOKEN MISSING_VARIABLE
  assert_equal "${TOKEN:-unset}" "unset"

  local file="${BATS_TEST_TMPDIR}/shredded"
  printf 'shredded-secret\n' > "${file}"
  dybatpho::secret_shred "${file}" "${BATS_TEST_TMPDIR}/absent"
  assert_file_not_exist "${file}"

  run dybatpho::secret_wipe
  assert_failure
  assert_output --partial "Expected at least one variable name"

  run dybatpho::secret_wipe 1invalid
  assert_failure
  assert_output --partial "Invalid variable name"

  run dybatpho::secret_shred
  assert_failure
  assert_output --partial "Expected at least one file"
}

@test "secret_shred overwrites when shred isn't available" {
  local file="${BATS_TEST_TMPDIR}/no-shred"
  printf 'shredded-secret\n' > "${file}"
  stub shred "* : exit 1"
  dybatpho::secret_shred "${file}"
  assert_file_not_exist "${file}"
  unstub shred
}

@test "secret_no_history disables history persistence" {
  HISTFILE="${BATS_TEST_TMPDIR}/history"
  dybatpho::secret_no_history
  refute [ -v HISTFILE ]
  assert_equal "${HISTSIZE}" "0"
  assert_equal "${DYBATPHO_REPL_HISTORY_FILE}" "/dev/null"
}

@test "json logging masks registered secrets" {
  dybatpho::secret_register "json-secret-value"
  LOG_FORMAT=json run --separate-stderr dybatpho::error "payload json-secret-value"
  assert_stderr --partial '"message":"payload ***"'
  refute_stderr --partial "json-secret-value"
}

@test "secret_register skips a short line of a multiline secret without warning" {
  # The whole value and its long line are registered; the short line is skipped.
  LOG_LEVEL=debug dybatpho::secret_register "$(printf 'long-enough-secret\nab\n')"
  assert_equal "${DYBATPHO_SECRET_COUNT}" "2"
  assert_equal "${DYBATPHO_SECRET_VALUES[1]}" "long-enough-secret"

  LOG_LEVEL=debug run --separate-stderr dybatpho::secret_register "$(printf 'long-enough-secret\nab\n')"
  assert_success
  assert_stderr --partial "Skipped masking a value shorter than 4 characters"
  refute_stderr --partial "isn't registered for masking"
}

@test "secret_register ignores a value that is already registered" {
  dybatpho::secret_register "duplicated-secret"
  dybatpho::secret_register "duplicated-secret"
  assert_equal "${DYBATPHO_SECRET_COUNT}" "1"

  dybatpho::secret_register "shorter-secret"
  assert_equal "${DYBATPHO_SECRET_COUNT}" "2"
  assert_equal "${DYBATPHO_SECRET_VALUES[0]}" "duplicated-secret"
  assert_equal "${DYBATPHO_SECRET_VALUES[1]}" "shorter-secret"
}

@test "secret_check_permission reports a file owned by another user" {
  local file="${BATS_TEST_TMPDIR}/foreign"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"

  # The mode is queried first, then the owner, then the parent directory.
  DYBATPHO_SECRET_STRICT_PERMS=false
  stub stat "* : echo 600" "* : echo 999999" "* : echo 700"
  dybatpho::secret_check_permission "${file}"

  DYBATPHO_SECRET_STRICT_PERMS=true
  stub stat "* : echo 600" "* : echo 999999"
  run dybatpho::secret_check_permission "${file}"
  assert_failure
  assert_output --partial "isn't owned by the current user"
}

@test "secret_check_permission fails when the mode can't be read" {
  local file="${BATS_TEST_TMPDIR}/no-mode"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"
  stub_repeated stat "* : exit 1"

  run dybatpho::secret_check_permission "${file}"
  assert_failure
  assert_output --partial "Cannot read permissions of secret file"
}

@test "secret_check_permission fails when the owner can't be read" {
  local file="${BATS_TEST_TMPDIR}/no-owner"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"
  # Mode lookup succeeds, then both owner lookups fail.
  stub stat "* : echo 600" "* : exit 1" "* : exit 1"

  run dybatpho::secret_check_permission "${file}"
  assert_failure
  assert_output --partial "Cannot read owner of secret file"
}

@test "secret_check_permission warns about a world writable parent directory" {
  local directory="${BATS_TEST_TMPDIR}/open-dir"
  mkdir -p "${directory}"
  chmod 777 "${directory}"
  local file="${directory}/token"
  printf 'value-of-secret\n' > "${file}"
  chmod 600 "${file}"

  dybatpho::secret_check_permission "${file}"

  run --separate-stderr dybatpho::secret_check_permission "${file}"
  assert_success
  assert_stderr --partial "writable by group or others"
  chmod 700 "${directory}"
}

@test "secret_check_permission fails on an unreadable file" {
  if ((EUID == 0)); then
    skip "root bypasses file permission bits"
  fi
  local file="${BATS_TEST_TMPDIR}/unreadable"
  printf 'value-of-secret\n' > "${file}"
  chmod 000 "${file}"

  run dybatpho::secret_check_permission "${file}"
  assert_failure
  assert_output --partial "isn't readable"
  chmod 600 "${file}"
}

@test "secret_read accepts the stdin keyword" {
  local FROM_STDIN
  dybatpho::secret_read FROM_STDIN stdin < <(printf 'keyword-secret-value\n')
  assert_equal "${FROM_STDIN}" "keyword-secret-value"
}

@test "secret_write_file rejects an invalid variable name" {
  run dybatpho::secret_write_file "${BATS_TEST_TMPDIR}/file" 1invalid
  assert_failure
  assert_output --partial "Invalid variable name"
}

@test "secret_write_file fails when the staging file can't be created" {
  if ((EUID == 0)); then
    skip "root bypasses directory permission bits"
  fi
  local directory="${BATS_TEST_TMPDIR}/read-only"
  mkdir -p "${directory}"
  chmod 500 "${directory}"

  local TOKEN="written-secret-value"
  run dybatpho::secret_write_file "${directory}/token" TOKEN
  assert_failure
  assert_output --partial "Cannot create secret file"
  chmod 700 "${directory}"
}

@test "secret_write_file fails when the staged file can't be moved into place" {
  local TOKEN="written-secret-value"
  local file="${BATS_TEST_TMPDIR}/unmovable"
  stub_repeated mv "* : exit 1"

  run dybatpho::secret_write_file "${file}" TOKEN
  assert_failure
  assert_output --partial "Cannot write secret file"
}

@test "secret_with_file rejects an invalid variable name and an empty secret" {
  run dybatpho::secret_with_file 1invalid cat '{}'
  assert_failure
  assert_output --partial "Invalid variable name"

  local EMPTY=""
  run dybatpho::secret_with_file EMPTY cat '{}'
  assert_failure
  assert_output --partial "is empty"
}

@test "secret_shred removes an empty file without overwriting it" {
  local file="${BATS_TEST_TMPDIR}/empty-shred"
  : > "${file}"
  stub_repeated shred "* : exit 1"

  dybatpho::secret_shred "${file}"
  assert_file_not_exist "${file}"
}
