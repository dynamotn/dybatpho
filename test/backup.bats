setup() {
  load test_helper
  SOURCE="${BATS_TEST_TMPDIR}/source"
  DEST="${BATS_TEST_TMPDIR}/backups"
  mkdir -p "${SOURCE}"
  printf 'first\n' > "${SOURCE}/a.txt"
  printf 'second\n' > "${SOURCE}/b.txt"
}

# @description Create a backup file of a given name without running an archiver,
#   for the tests that only care about the retention arithmetic.
# @arg $1 string Backup file name
# @arg $2 string Optional `touch -t` stamp to age the file with
plant() {
  mkdir -p "${DEST}"
  printf 'content of %s\n' "$1" > "${DEST}/$1"
  printf 'deadbeef  %s\n' "$1" > "${DEST}/$1.sha256"
  if [ -n "${2-}" ]; then
    touch -t "$2" "${DEST}/$1" "${DEST}/$1.sha256"
  fi
}

@test "dybatpho::backup_create writes a timestamped archive and its sidecar" {
  run_traced dybatpho::backup_create "${SOURCE}" "${DEST}" snap
  assert_success
  assert_output --regexp "${DEST}/snap-[0-9]{8}T[0-9]{6}Z\.tar\.gz$"

  local archive="${output}"
  assert_file_exist "${archive}"
  assert_file_exist "${archive}.sha256"
}

@test "dybatpho::backup_create names the backup after the source when none is given" {
  run_traced dybatpho::backup_create "${SOURCE}" "${DEST}"
  assert_success
  assert_output --partial "/source-"
}

@test "dybatpho::backup_create creates the destination directory" {
  run_traced dybatpho::backup_create "${SOURCE}" "${BATS_TEST_TMPDIR}/made/up" snap
  assert_success
  assert_dir_exist "${BATS_TEST_TMPDIR}/made/up"
}

@test "dybatpho::backup_create refuses a source that is not there" {
  run --separate-stderr dybatpho::backup_create "${BATS_TEST_TMPDIR}/absent" "${DEST}" snap
  assert_failure
  assert_stderr --partial "Nothing to back up at"
}

@test "dybatpho::backup_create leaves nothing behind when the archiver fails" {
  # A killed or failing run must not leave a file that a later listing counts
  # as a backup. An extension no archiver knows is the cheapest way to fail.
  DYBATPHO_BACKUP_EXTENSION="nosuchformat" \
    run --separate-stderr dybatpho::backup_create "${SOURCE}" "${DEST}" snap
  assert_failure

  run_traced find "${DEST}" -type f
  assert_output ""
}

@test "dybatpho::backup_create does not overwrite a backup taken in the same second" {
  # The timestamp has one-second resolution, so two runs in a row would
  # otherwise collide and the first backup would silently disappear.
  # A frozen clock makes the collision happen every run, rather than only when
  # the two calls land either side of a second boundary.
  dybatpho::date_now() { printf '20260101T000000Z\n'; }

  local first second
  first="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  second="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  assert_equal "${first}" "${DEST}/snap-20260101T000000Z.tar.gz"
  assert_equal "${second}" "${DEST}/snap-20260101T000000Z-1.tar.gz"
  [ "${first}" != "${second}" ]
  assert_file_exist "${first}"
  assert_file_exist "${second}"
}

@test "dybatpho::backup_verify accepts an intact backup and reports a corrupted one" {
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  run_traced dybatpho::backup_verify "${archive}"
  assert_success

  printf 'junk' >> "${archive}"
  run_traced --separate-stderr dybatpho::backup_verify "${archive}"
  assert_failure
  assert_stderr --partial "does not match its sidecar"
}

@test "dybatpho::backup_verify refuses to pass a backup it cannot check" {
  # "No sidecar" is not the same answer as "matches", and treating it as one
  # would report a corrupted restore as a good one.
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  rm -f "${archive}.sha256"

  run --separate-stderr dybatpho::backup_verify "${archive}"
  assert_failure
  assert_stderr --partial "No checksum sidecar"

  run --separate-stderr dybatpho::backup_verify "${DEST}/absent.tar.gz"
  assert_failure
  assert_stderr --partial "No such backup"
}

@test "dybatpho::backup_list prints the backups newest first" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"
  plant "snap-20260201T000000Z.tar.gz"

  run_traced dybatpho::backup_list "${DEST}" snap
  assert_success
  assert_line --index 0 "${DEST}/snap-20260301T000000Z.tar.gz"
  assert_line --index 1 "${DEST}/snap-20260201T000000Z.tar.gz"
  assert_line --index 2 "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_list matches one name and says nothing for an empty directory" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "other-20260301T000000Z.tar.gz"

  run_traced dybatpho::backup_list "${DEST}" snap
  assert_success
  assert_output "${DEST}/snap-20260101T000000Z.tar.gz"

  run_traced dybatpho::backup_list "${DEST}"
  assert_success
  [ "${#lines[@]}" -eq 2 ]

  run_traced dybatpho::backup_list "${BATS_TEST_TMPDIR}/nowhere"
  assert_success
  assert_output ""
}

@test "dybatpho::backup_list leaves a half-written archive out" {
  plant "snap-20260101T000000Z.tar.gz"
  printf 'half' > "${DEST}/.snap-20260301T000000Z.999.partial.tar.gz"

  run_traced dybatpho::backup_list "${DEST}"
  assert_success
  assert_output "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_latest resolves the newest backup and reports an empty directory" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  run_traced dybatpho::backup_latest "${DEST}" snap
  assert_success
  assert_output "${DEST}/snap-20260301T000000Z.tar.gz"

  run_traced -1 dybatpho::backup_latest "${BATS_TEST_TMPDIR}/nowhere"
  assert_output ""
}

@test "dybatpho::backup_restore puts the files back" {
  local archive target="${BATS_TEST_TMPDIR}/restored"
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  run_traced dybatpho::backup_restore --force "${archive}" "${target}"
  assert_success
  assert_file_exist "${target}/source/a.txt"
  assert_equal "$(cat "${target}/source/a.txt")" "first"
}

@test "dybatpho::backup_restore checks the archive before extracting it" {
  local archive target="${BATS_TEST_TMPDIR}/restored"
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  printf 'junk' >> "${archive}"

  run_traced --separate-stderr dybatpho::backup_restore --force "${archive}" "${target}"
  assert_failure
  assert_stderr --partial "does not match its sidecar"
  assert_file_not_exist "${target}/source/a.txt"
}

@test "dybatpho::backup_restore confirms an overwrite when not forced" {
  local archive target="${BATS_TEST_TMPDIR}/restored"
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  DYBATPHO_FORCE=true run_traced dybatpho::backup_restore "${archive}" "${target}"
  assert_success
  assert_file_exist "${target}/source/a.txt"
}

@test "dybatpho::backup_prune keeps the newest --keep-count backups" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260201T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  run_traced dybatpho::backup_prune --keep-count 2 --name snap --force "${DEST}"
  assert_success

  run_traced dybatpho::backup_list "${DEST}" snap
  assert_line --index 0 "${DEST}/snap-20260301T000000Z.tar.gz"
  assert_line --index 1 "${DEST}/snap-20260201T000000Z.tar.gz"
  [ "${#lines[@]}" -eq 2 ]
}

@test "dybatpho::backup_prune removes a pruned backup's sidecar with it" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  dybatpho::backup_prune --keep-count 1 --name snap --force "${DEST}"
  assert_file_not_exist "${DEST}/snap-20260101T000000Z.tar.gz"
  assert_file_not_exist "${DEST}/snap-20260101T000000Z.tar.gz.sha256"
}

@test "dybatpho::backup_prune keeps the backups younger than --keep-days" {
  plant "snap-20260301T000000Z.tar.gz" "202601010000"
  plant "snap-20260302T000000Z.tar.gz"

  run_traced dybatpho::backup_prune --keep-days 1 --name snap --force "${DEST}"
  assert_success
  assert_file_not_exist "${DEST}/snap-20260301T000000Z.tar.gz"
  assert_file_exist "${DEST}/snap-20260302T000000Z.tar.gz"
}

@test "dybatpho::backup_prune keeps a backup any policy keeps" {
  # Both policies together keep more, not less: deleting more than the
  # operator asked for is the expensive direction to be wrong in. The old file
  # survives because --keep-count still counts it among the newest two.
  plant "snap-20260101T000000Z.tar.gz" "202601010000"
  plant "snap-20260302T000000Z.tar.gz"
  plant "snap-20260303T000000Z.tar.gz"

  run_traced dybatpho::backup_prune --keep-count 3 --keep-days 1 --name snap --force "${DEST}"
  assert_success
  assert_file_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_prune reports what it would remove under DRY_RUN" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  DRY_RUN=true run_traced dybatpho::backup_prune --keep-count 1 --name snap --force "${DEST}"
  assert_success
  assert_output --partial "snap-20260101T000000Z.tar.gz"
  assert_file_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_prune refuses to run without a retention policy" {
  # Nothing to keep would mean deleting every backup there is.
  plant "snap-20260101T000000Z.tar.gz"

  run --separate-stderr dybatpho::backup_prune --name snap --force "${DEST}"
  assert_failure
  assert_stderr --partial "refusing to prune without a policy"
  assert_file_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_prune rejects a malformed option" {
  run --separate-stderr dybatpho::backup_prune --keep-count two --force "${DEST}"
  assert_failure
  assert_stderr --partial "--keep-count expects a number"

  run --separate-stderr dybatpho::backup_prune --keep-days later --force "${DEST}"
  assert_failure
  assert_stderr --partial "--keep-days expects a number"

  run --separate-stderr dybatpho::backup_prune --keep-count 1 --nonsense "${DEST}"
  assert_failure
  assert_stderr --partial "Unrecognized option: --nonsense"

  run --separate-stderr dybatpho::backup_prune --keep-count 1
  assert_failure
  assert_stderr --partial "Expected a directory to prune"
}

@test "dybatpho::backup_prune takes the directory after an end-of-options marker" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  run_traced dybatpho::backup_prune --keep-count 1 --name snap --force -- "${DEST}"
  assert_success
  assert_file_not_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_prune does nothing when there is nothing to prune" {
  run_traced dybatpho::backup_prune --keep-count 1 "${BATS_TEST_TMPDIR}/nowhere"
  assert_success
  assert_output ""

  plant "snap-20260101T000000Z.tar.gz"
  run_traced dybatpho::backup_prune --keep-count 5 --name snap "${DEST}"
  assert_success
  assert_file_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "dybatpho::backup_prune asks before deleting when it is not forced" {
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260301T000000Z.tar.gz"

  DYBATPHO_FORCE=true run_traced dybatpho::backup_prune --keep-count 1 --name snap "${DEST}"
  assert_success
  assert_file_not_exist "${DEST}/snap-20260101T000000Z.tar.gz"
}

@test "DYBATPHO_BACKUP_EXTENSION and the checksum algorithm are configurable" {
  DYBATPHO_BACKUP_EXTENSION="tar.bz2" DYBATPHO_BACKUP_CHECKSUM_ALGORITHM="sha512" \
    run_traced dybatpho::backup_create "${SOURCE}" "${DEST}" snap
  assert_success
  assert_output --partial ".tar.bz2"
  assert_file_exist "${output}.sha512"
}
