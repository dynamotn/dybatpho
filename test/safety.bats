setup() {
  load test_helper
  export DYBATPHO_INTERACTIVE=false
  export DYBATPHO_FORCE=false
  export DYBATPHO_SAFE_ROOTS=""
  export DYBATPHO_PROTECTED_PATHS=""
  export DRY_RUN=""
}

# ---------------------------------------------------------------------------
# Interactivity and confirmation
# ---------------------------------------------------------------------------

@test "dybatpho::is_interactive honors the DYBATPHO_INTERACTIVE override" {
  DYBATPHO_INTERACTIVE=true dybatpho::is_interactive
  run_traced -1 dybatpho::is_interactive
  # `auto` falls back to terminal detection, and tests never own a terminal.
  DYBATPHO_INTERACTIVE=auto run -1 dybatpho::is_interactive
}

@test "dybatpho::confirm accepts yes, no, and the default answer" {
  DYBATPHO_INTERACTIVE=true dybatpho::confirm "Continue?" <<< "y"
  DYBATPHO_INTERACTIVE=true dybatpho::confirm "Continue?" <<< "YES"

  run_traced -1 dybatpho::confirm "Continue?" <<< "n"
  run_traced -1 dybatpho::confirm "Continue?" <<< ""
  DYBATPHO_INTERACTIVE=true dybatpho::confirm "Continue?" yes <<< ""
}

@test "dybatpho::confirm refuses in a non-interactive shell and obeys DYBATPHO_FORCE" {
  run dybatpho::confirm "Continue?"
  assert_failure
  assert_output --partial "Refusing without --force in a non-interactive shell"

  DYBATPHO_FORCE=true dybatpho::confirm "Continue?"
}

# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------

@test "dybatpho::assert_safe_path normalizes relative paths" {
  cd "${BATS_TEST_TMPDIR}"
  mkdir -p nested
  assert_equal "$(dybatpho::assert_safe_path "nested/../nested/file.txt")" "${BATS_TEST_TMPDIR}/nested/file.txt"
}

@test "dybatpho::assert_safe_path rejects empty and protected paths" {
  run dybatpho::assert_safe_path "   "
  assert_failure
  assert_output --partial "Refusing to use an empty path"

  run dybatpho::assert_safe_path "/"
  assert_failure
  assert_output --partial "Refusing to touch protected path: /"

  run dybatpho::assert_safe_path "/usr" "destination"
  assert_failure
  assert_output --partial "Refusing to touch protected destination: /usr"

  run dybatpho::assert_safe_path "${HOME}"
  assert_failure
  assert_output --partial "Refusing to touch protected path"
}

@test "dybatpho::assert_safe_path honors DYBATPHO_PROTECTED_PATHS and DYBATPHO_SAFE_ROOTS" {
  local guarded="${BATS_TEST_TMPDIR}/keep"
  mkdir -p "${guarded}"

  DYBATPHO_PROTECTED_PATHS="${guarded}" run dybatpho::assert_safe_path "${guarded}"
  assert_failure
  assert_output --partial "Refusing to touch protected path: ${guarded}"

  DYBATPHO_SAFE_ROOTS="${BATS_TEST_TMPDIR}" run dybatpho::assert_safe_path "${BATS_TEST_TMPDIR}/inside.txt"
  assert_success

  DYBATPHO_SAFE_ROOTS="${guarded}" run dybatpho::assert_safe_path "${guarded}/../escape.txt"
  assert_failure
  assert_output --partial "outside DYBATPHO_SAFE_ROOTS"
}

# ---------------------------------------------------------------------------
# safe_rm
# ---------------------------------------------------------------------------

@test "dybatpho::safe_rm removes an approved file and keeps a declined one" {
  local target="${BATS_TEST_TMPDIR}/file.txt"
  printf 'data\n' > "${target}"

  run dybatpho::safe_rm "${target}"
  assert_failure
  assert_output --partial "Aborted removal of 1 path(s)"
  [ -f "${target}" ]

  DYBATPHO_INTERACTIVE=true dybatpho::safe_rm "${target}" <<< "y"
  [ ! -e "${target}" ]
}

@test "dybatpho::safe_rm requires --recursive for directories" {
  local target="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${target}/nested"

  run dybatpho::safe_rm --force "${target}"
  assert_failure
  assert_output --partial "Refusing to remove a directory without --recursive"
  [ -d "${target}" ]

  dybatpho::safe_rm --force --recursive "${target}"
  [ ! -d "${target}" ]
}

@test "dybatpho::safe_rm skips missing paths and removes dangling symlinks" {
  local link="${BATS_TEST_TMPDIR}/dangling"
  ln -s "${BATS_TEST_TMPDIR}/nowhere" "${link}"

  dybatpho::safe_rm --force "${BATS_TEST_TMPDIR}/missing.txt"

  dybatpho::safe_rm --force "${link}"
  [ ! -L "${link}" ]
}

@test "dybatpho::safe_rm validates options and arguments" {
  run dybatpho::safe_rm
  assert_failure
  assert_output --partial "expected at least one path"

  run dybatpho::safe_rm --unknown "${BATS_TEST_TMPDIR}/file"
  assert_failure
  assert_output --partial "unknown option: --unknown"

  local dashed="${BATS_TEST_TMPDIR}/--dashed"
  printf 'data\n' > "${dashed}"
  dybatpho::safe_rm --force -- "${dashed}"
  [ ! -e "${dashed}" ]
}

@test "dybatpho::safe_rm prints the command instead of removing it under DRY_RUN" {
  local target="${BATS_TEST_TMPDIR}/file.txt"
  printf 'data\n' > "${target}"

  DRY_RUN=true run dybatpho::safe_rm --force "${target}"
  assert_success
  assert_output --partial "DRY RUN: rm -f -- ${target}"
  [ -f "${target}" ]
}

# ---------------------------------------------------------------------------
# safe_overwrite, safe_copy, safe_move
# ---------------------------------------------------------------------------

@test "dybatpho::safe_overwrite allows a missing destination and guards an existing one" {
  local target="${BATS_TEST_TMPDIR}/config"

  dybatpho::safe_overwrite "${target}"

  printf 'old\n' > "${target}"
  run dybatpho::safe_overwrite "${target}"
  assert_failure
  assert_output --partial "Aborted overwrite of ${target}"

  dybatpho::safe_overwrite --force --backup "${target}"
  printf 'new\n' > "${target}"
  assert_equal "$(cat "${target}")" "new"
  assert_equal "$(cat "${target}.bak")" "old"
}

@test "dybatpho::safe_overwrite refuses directories and invalid arguments" {
  mkdir -p "${BATS_TEST_TMPDIR}/dir"

  run dybatpho::safe_overwrite --force "${BATS_TEST_TMPDIR}/dir"
  assert_failure
  assert_output --partial "Refusing to overwrite a directory"

  run dybatpho::safe_overwrite
  assert_failure
  assert_output --partial "expected exactly one destination"

  run dybatpho::safe_overwrite --unknown "${BATS_TEST_TMPDIR}/file"
  assert_failure
  assert_output --partial "unknown option: --unknown"
}

@test "dybatpho::safe_copy copies into a directory and guards the overwrite" {
  local source="${BATS_TEST_TMPDIR}/source.txt"
  local destination="${BATS_TEST_TMPDIR}/dest"
  printf 'v1\n' > "${source}"
  mkdir -p "${destination}"

  dybatpho::safe_copy "${source}" "${destination}"
  assert_equal "$(cat "${destination}/source.txt")" "v1"

  printf 'v2\n' > "${source}"
  run_traced dybatpho::safe_copy "${source}" "${destination}"
  assert_failure
  assert_equal "$(cat "${destination}/source.txt")" "v1"

  dybatpho::safe_copy --force "${source}" "${destination}"
  assert_equal "$(cat "${destination}/source.txt")" "v2"
}

@test "dybatpho::safe_move creates missing parents and reports a missing source" {
  local source="${BATS_TEST_TMPDIR}/source.txt"
  printf 'v1\n' > "${source}"

  dybatpho::safe_move "${source}" "${BATS_TEST_TMPDIR}/new/dir/moved.txt"
  [ ! -e "${source}" ]
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/new/dir/moved.txt")" "v1"

  run dybatpho::safe_move "${source}" "${BATS_TEST_TMPDIR}/other.txt"
  assert_failure
  assert_output --partial "Source doesn't exist"

  run dybatpho::safe_copy "${BATS_TEST_TMPDIR}/new/dir/moved.txt"
  assert_failure
  assert_output --partial "expected a source and a destination"
}

@test "safe_rm and safe_overwrite accept the short option forms" {
  local target="${BATS_TEST_TMPDIR}/short.txt"
  local tree="${BATS_TEST_TMPDIR}/tree"
  printf 'v1\n' > "${target}"
  mkdir -p "${tree}/nested"

  # -b is the short form of --backup, -f of --force.
  dybatpho::safe_overwrite -f -b "${target}"
  assert_file_exist "${target}.bak"
  assert_equal "$(cat "${target}.bak")" "v1"

  # -r is the short form of --recursive.
  dybatpho::safe_rm -r -f "${tree}"
  [ ! -e "${tree}" ]
}

@test "safe_copy and safe_move keep a backup with --backup" {
  local source="${BATS_TEST_TMPDIR}/source.txt"
  local copied="${BATS_TEST_TMPDIR}/copied.txt"
  local moved="${BATS_TEST_TMPDIR}/moved.txt"
  printf 'new\n' > "${source}"
  printf 'old-copy\n' > "${copied}"
  printf 'old-move\n' > "${moved}"

  # The backup flag is forwarded to the overwrite guard.
  dybatpho::safe_copy --force --backup "${source}" "${copied}"
  assert_equal "$(cat "${copied}")" "new"
  assert_equal "$(cat "${copied}.bak")" "old-copy"

  dybatpho::safe_move -f -b "${source}" "${moved}"
  assert_equal "$(cat "${moved}")" "new"
  assert_equal "$(cat "${moved}.bak")" "old-move"
  [ ! -e "${source}" ]
}

@test "safe_copy and safe_move reject unknown options" {
  run dybatpho::safe_copy --unknown "${BATS_TEST_TMPDIR}/a" "${BATS_TEST_TMPDIR}/b"
  assert_failure
  assert_output --partial "dybatpho::safe_copy: unknown option: --unknown"

  run dybatpho::safe_move --unknown "${BATS_TEST_TMPDIR}/a" "${BATS_TEST_TMPDIR}/b"
  assert_failure
  assert_output --partial "dybatpho::safe_move: unknown option: --unknown"
}

@test "safe_copy treats everything after -- as a path" {
  # A source whose name starts with a dash must not be parsed as an option.
  local source="${BATS_TEST_TMPDIR}/-f"
  local destination="${BATS_TEST_TMPDIR}/dashed-copy.txt"
  printf 'dashed\n' > "${source}"

  dybatpho::safe_copy --force -- "${source}" "${destination}"
  assert_equal "$(cat "${destination}")" "dashed"
}

# ---------------------------------------------------------------------------
# safe_extract
# ---------------------------------------------------------------------------

function _create_test_archive {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local source_dir="${BATS_TEST_TMPDIR}/payload"
  mkdir -p "${source_dir}/bundle/nested"
  printf 'hello\n' > "${source_dir}/bundle/nested/file.txt"
  tar -czf "${archive_path}" -C "${source_dir}" bundle
}

function _create_traversal_archive {
  local archive_path
  dybatpho::expect_args archive_path -- "$@"
  local source_dir="${BATS_TEST_TMPDIR}/evil"
  mkdir -p "${source_dir}/bundle"
  printf 'owned\n' > "${source_dir}/victim.txt"
  (
    cd "${source_dir}/bundle"
    tar -czf "${archive_path}" -P ../victim.txt 2> /dev/null
  )
}

@test "dybatpho::safe_extract extracts a safe archive and supports strip-components" {
  local archive_path="${BATS_TEST_TMPDIR}/safe.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  _create_test_archive "${archive_path}"

  dybatpho::safe_extract "${archive_path}" "${destination}"
  assert_equal "$(cat "${destination}/bundle/nested/file.txt")" "hello"

  dybatpho::safe_extract "${archive_path}" "${destination}/stripped" 1
  assert_equal "$(cat "${destination}/stripped/nested/file.txt")" "hello"
}

@test "dybatpho::safe_extract asks for the archive module when it is not loaded" {
  # `safety` does not load `archive`, so a script that only confirms or removes
  # does not pay for it. A child shell started from a file, without the
  # functions this process exports, shows what such a script sees: the guard
  # fires before the archive path is even looked at.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules safety\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'dybatpho::is_interactive || echo "not interactive"'
    printf '%s\n' 'dybatpho::safe_extract --force "${1}" "${2}"'
  } > "${script}"

  local archive_path="${BATS_TEST_TMPDIR}/safe.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  _create_test_archive "${archive_path}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${BATS_TEST_TMPDIR}/absent.tar.gz" "${destination}"
  assert_failure
  assert_line --index 0 "not interactive"
  assert_output --partial "dybatpho::safe_extract needs the archive module, load it with: dybatpho::load archive"
  refute_output --partial "Archive doesn't exist"

  # Once the script loads it, the same call extracts.
  sed_in_place 's/--modules safety/--modules safety archive/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}" "${archive_path}" "${destination}"
  assert_success
  assert_equal "$(cat "${destination}/bundle/nested/file.txt")" "hello"
}

@test "dybatpho::safe_extract refuses archives that escape the destination" {
  local archive_path="${BATS_TEST_TMPDIR}/evil.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  _create_traversal_archive "${archive_path}"

  run dybatpho::safe_extract --force "${archive_path}" "${destination}"
  assert_failure
  assert_output --partial "Refusing to extract entry outside ${destination}: ../victim.txt"
  [ ! -e "${BATS_TEST_TMPDIR}/victim.txt" ]
}

@test "dybatpho::safe_extract refuses an archive it cannot list" {
  # The entries are checked before anything is written, so an archive whose
  # entries cannot be read must stop there rather than be extracted unchecked.
  local archive_path="${BATS_TEST_TMPDIR}/corrupt.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  printf 'not an archive\n' > "${archive_path}"

  run dybatpho::safe_extract --force "${archive_path}" "${destination}"
  assert_failure
  assert_output --partial "Can't list archive ${archive_path}"
}

@test "dybatpho::safe_extract confirms before overwriting existing files" {
  local archive_path="${BATS_TEST_TMPDIR}/safe.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  _create_test_archive "${archive_path}"
  mkdir -p "${destination}/bundle/nested"
  printf 'local\n' > "${destination}/bundle/nested/file.txt"

  run dybatpho::safe_extract "${archive_path}" "${destination}"
  assert_failure
  assert_output --partial "Aborted extraction of ${archive_path}"
  assert_equal "$(cat "${destination}/bundle/nested/file.txt")" "local"

  dybatpho::safe_extract --force "${archive_path}" "${destination}"
  assert_equal "$(cat "${destination}/bundle/nested/file.txt")" "hello"
}

@test "dybatpho::safe_extract validates its arguments" {
  run dybatpho::safe_extract
  assert_failure
  assert_output --partial "expected an archive path"

  run dybatpho::safe_extract "${BATS_TEST_TMPDIR}/missing.tar.gz"
  assert_failure
  assert_output --partial "Archive doesn't exist"

  local archive_path="${BATS_TEST_TMPDIR}/safe.tar.gz"
  _create_test_archive "${archive_path}"
  run dybatpho::safe_extract "${archive_path}" "${BATS_TEST_TMPDIR}/out" abc
  assert_failure
  assert_output --partial "strip-components must be a non-negative integer"

  run dybatpho::safe_extract --unknown "${archive_path}"
  assert_failure
  assert_output --partial "unknown option: --unknown"
}

# ---------------------------------------------------------------------------
# safe_system
# ---------------------------------------------------------------------------

@test "dybatpho::safe_system runs an approved command and skips a declined one" {
  local marker="${BATS_TEST_TMPDIR}/applied"

  run dybatpho::safe_system "Restart the service" -- touch "${marker}"
  assert_failure
  assert_output --partial "Skipped system change: Restart the service"
  [ ! -e "${marker}" ]

  dybatpho::safe_system --force "Restart the service" -- touch "${marker}"
  [ -f "${marker}" ]
}

@test "dybatpho::safe_system honors DRY_RUN and validates its arguments" {
  local marker="${BATS_TEST_TMPDIR}/applied"

  DRY_RUN=true run dybatpho::safe_system --force "Restart the service" -- touch "${marker}"
  assert_success
  assert_output --partial "DRY RUN: touch ${marker}"
  [ ! -e "${marker}" ]

  run dybatpho::safe_system --force -- true
  assert_failure
  assert_output --partial "expected a description"

  run dybatpho::safe_system --force "Restart the service"
  assert_failure
  assert_output --partial "expected a command after --"

  run dybatpho::safe_system --force "Restart" "Twice" -- true
  assert_failure
  assert_output --partial "expected a single description before --"

  run dybatpho::safe_system --unknown "Restart" -- true
  assert_failure
  assert_output --partial "unknown option: --unknown"
}

@test "a command run by safe_system sees the caller's variables, not the guard's" {
  # The command runs in the guard's scope, where its locals hid the caller's
  # variables of the same names.
  local force="caller" description="caller" arguments="caller" command_args="caller"
  local seen="${BATS_TEST_TMPDIR}/seen"
  look() { printf '%s %s %s %s\n' "${force}" "${description}" "${arguments}" "${command_args}" > "${seen}"; }
  dybatpho::safe_system --force "scoped change" -- look 2> /dev/null
  assert_equal "$(cat "${seen}")" "caller caller caller caller"
}
