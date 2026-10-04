setup() {
  load test_helper
  SOURCE="${BATS_TEST_TMPDIR}/source"
  # Physical, as an incremental backup reports it: the macOS temporary
  # directory sits behind the `/var` -> `/private/var` symlink.
  DEST="$(cd -- "${BATS_TEST_TMPDIR}" && pwd -P)/backups"
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

@test "dybatpho::backup_create never shows a backup without its complete sidecar" {
  # The backup used to be moved into place first and its sidecar written after,
  # with a plain redirection. When that write failed -- here because something
  # already holds the sidecar's name -- the backup stayed listed with no
  # sidecar, and every later verify, restore and comparison refused it.
  dybatpho::date_now() { printf '20260101T000000Z\n'; }
  mkdir -p "${DEST}/snap-20260101T000000Z.tar.gz.sha256"

  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  assert_equal "${archive}" "${DEST}/snap-20260101T000000Z-1.tar.gz"

  local -a listed=()
  mapfile -t listed < <(dybatpho::backup_list "${DEST}" snap)
  assert_equal "${#listed[@]}" "1"
  run_traced dybatpho::backup_verify "${listed[0]}"
  assert_success
  # The sidecar was written whole under a hidden name and renamed into place.
  run_traced find "${DEST}" -name '.*partial*'
  assert_output ""
}

@test "dybatpho::backup_create takes another name when its own is taken before the move" {
  # The free name was chosen first and the backup moved there afterwards. A
  # directory that appeared at that name in between swallowed the archive,
  # which `mv` moved inside it, and the path printed was the directory.
  dybatpho::date_now() { printf '20260101T000000Z\n'; }
  eval "__test_file_hash() $(declare -f dybatpho::file_hash | tail -n +2)"
  # shellcheck disable=SC2329 # invoked by backup_create
  dybatpho::file_hash() {
    mkdir -p "${DEST}/snap-20260101T000000Z.tar.gz"
    __test_file_hash "$@"
  }

  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  assert_equal "${archive}" "${DEST}/snap-20260101T000000Z-1.tar.gz"
  [[ -f "${archive}" ]]
  run_traced find "${DEST}/snap-20260101T000000Z.tar.gz" -mindepth 1
  assert_output ""
}

@test "dybatpho::backup_create --incremental takes another name when its own is taken" {
  # A directory move onto a name that turned into a directory lands inside it,
  # so a snapshot published there would have been nested a level too deep.
  dybatpho::date_now() { printf '20260101T000000Z\n'; }
  eval "__test_tree_hash_into() $(declare -f __dybatpho_backup_tree_hash_into | tail -n +2)"
  # shellcheck disable=SC2329 # invoked by backup_create
  __dybatpho_backup_tree_hash_into() {
    mkdir -p "${DEST}/snap-20260101T000000Z.snapshot"
    __test_tree_hash_into "$@"
  }

  local snapshot
  snapshot="$(dybatpho::backup_create --incremental "${SOURCE}" "${DEST}" snap)"
  assert_equal "${snapshot}" "${DEST}/snap-20260101T000000Z-1.snapshot"
  assert_file_exist "${snapshot}/source/a.txt"
  run_traced find "${DEST}/snap-20260101T000000Z.snapshot" -mindepth 1
  assert_output ""
  eval "__dybatpho_backup_tree_hash_into() $(declare -f __test_tree_hash_into | tail -n +2)"
  run_traced dybatpho::backup_verify "${snapshot}"
  assert_success
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

@test "dybatpho::backup_list orders backups from the same second by their suffix" {
  # The suffix is the only thing telling these apart, and a name comparison
  # gets it wrong: under C collation `-1.` sorts before `.`, and everywhere
  # `-10` sorts before `-2`.
  plant "snap-20260101T000000Z.tar.gz"
  plant "snap-20260101T000000Z-1.tar.gz"
  plant "snap-20260101T000000Z-2.tar.gz"
  plant "snap-20260101T000000Z-10.tar.gz"
  plant "snap-20251231T235959Z-3.tar.gz"
  mkdir -p "${DEST}/snap-20260101T000000Z-11.snapshot"

  local locale
  for locale in C "${LANG:-C}"; do
    LC_ALL="${locale}" run_traced dybatpho::backup_list "${DEST}" snap
    assert_success
    assert_line --index 0 "${DEST}/snap-20260101T000000Z-11.snapshot"
    assert_line --index 1 "${DEST}/snap-20260101T000000Z-10.tar.gz"
    assert_line --index 2 "${DEST}/snap-20260101T000000Z-2.tar.gz"
    assert_line --index 3 "${DEST}/snap-20260101T000000Z-1.tar.gz"
    assert_line --index 4 "${DEST}/snap-20260101T000000Z.tar.gz"
    assert_line --index 5 "${DEST}/snap-20251231T235959Z-3.tar.gz"
  done
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

@test "dybatpho::backup_diff shows what changed between two backups" {
  local older newer
  older="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  printf 'rewritten\n' > "${SOURCE}/a.txt"
  rm "${SOURCE}/b.txt"
  mkdir "${SOURCE}/new dir"
  printf 'added\n' > "${SOURCE}/new dir/c.txt"
  newer="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  DYBATPHO_DIFF_COLOR=false run_traced -1 dybatpho::backup_diff "${older}" "${newer}"
  assert_output - << EOF
~ a.txt
- b.txt
+ new dir/
+ new dir/c.txt
EOF

  run_traced -1 dybatpho::backup_diff --summary "${older}" "${newer}"
  assert_output "+2 -1 ~1"
}

@test "dybatpho::backup_diff compares a backup with the live source" {
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  run_traced -0 dybatpho::backup_diff "${archive}" "${SOURCE}"
  assert_output ""

  printf 'third\n' > "${SOURCE}/c.txt"
  DYBATPHO_DIFF_COLOR=false run_traced -1 dybatpho::backup_diff "${archive}" "${SOURCE}"
  assert_output "+ c.txt"

  # The source's own name is not compared, so a copy restored elsewhere lines
  # up with the backup just as well.
  cp -R "${SOURCE}" "${BATS_TEST_TMPDIR}/elsewhere"
  DYBATPHO_DIFF_COLOR=false run_traced -1 dybatpho::backup_diff -- "${archive}" "${BATS_TEST_TMPDIR}/elsewhere"
  assert_output "+ c.txt"
}

@test "dybatpho::backup_diff compares a single-file backup with the live file" {
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}/a.txt" "${DEST}" config)"

  run_traced -0 dybatpho::backup_diff "${archive}" "${SOURCE}/a.txt"
  printf 'changed\n' > "${SOURCE}/a.txt"
  DYBATPHO_DIFF_COLOR=false run_traced -1 dybatpho::backup_diff "${archive}" "${SOURCE}/a.txt"
  assert_output "~ a.txt"
}

@test "dybatpho::backup_diff passes --null through to the tree comparison" {
  local archive record
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  printf 'x\n' > "${SOURCE}/two"$'\n'"lines"

  record="$(dybatpho::backup_diff --null "${archive}" "${SOURCE}" | tr '\0' '|' || true)"
  assert_equal "${record}" "+ two"$'\n'"lines|"
}

@test "dybatpho::backup_diff refuses a backup it cannot trust" {
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"

  # `dybatpho::die` ends the shell, so these use `run`.
  printf 'junk' >> "${archive}"
  run -2 dybatpho::backup_diff "${archive}" "${SOURCE}"
  assert_output --partial "fails its checksum"

  rm "${archive}.sha256"
  run -2 dybatpho::backup_diff "${archive}" "${SOURCE}"
  assert_output --partial "No checksum sidecar beside: ${archive}"

  run -2 dybatpho::backup_diff "${SOURCE}" "${BATS_TEST_TMPDIR}/missing"
  assert_output --partial "Nothing to compare at: ${BATS_TEST_TMPDIR}/missing"
}

@test "dybatpho::backup_diff refuses a backup holding an entry that escapes" {
  local evil="${DEST}/evil-20260101T000000Z.tar.gz"
  mkdir -p "${DEST}" "${BATS_TEST_TMPDIR}/evil/bundle"
  printf 'owned\n' > "${BATS_TEST_TMPDIR}/evil/victim.txt"
  (
    cd "${BATS_TEST_TMPDIR}/evil/bundle"
    tar -czf "${evil}" -P ../victim.txt 2> /dev/null
  )
  printf '%s  %s\n' "$(dybatpho::file_hash "${evil}" sha256)" "$(basename "${evil}")" > "${evil}.sha256"

  run -2 dybatpho::backup_diff "${evil}" "${SOURCE}"
  assert_output --partial "outside the scratch directory"
}

# @description Take an incremental snapshot, the way every snapshot test does.
# @arg $@ string Arguments after `--incremental`
# @stdout The snapshot path
snapshot() {
  dybatpho::backup_create --incremental "$@"
}

@test "dybatpho::backup_create --incremental writes a snapshot directory and its sidecar" {
  run_traced dybatpho::backup_create --incremental "${SOURCE}" "${DEST}" site
  assert_success
  assert_output --regexp "${DEST}/site-[0-9]{8}T[0-9]{6}Z\.snapshot$"

  local snap="${output}"
  assert_dir_exist "${snap}"
  assert_file_exist "${snap}.sha256"
  assert_equal "$(cat "${snap}/source/a.txt")" "first"
  # Nothing half-written is left behind.
  run_traced -0 find "${DEST}" -name '.*partial*'
  assert_output ""
}

@test "dybatpho::backup_create --incremental hard-links what did not change" {
  local older newer
  older="$(snapshot "${SOURCE}" "${DEST}" site)"
  printf 'rewritten\n' > "${SOURCE}/b.txt"
  newer="$(dybatpho::backup_create -i "${SOURCE}/" "${DEST}" site)"

  assert [ "${older}/source/a.txt" -ef "${newer}/source/a.txt" ]
  refute [ "${older}/source/b.txt" -ef "${newer}/source/b.txt" ]
  assert_equal "$(cat "${older}/source/b.txt")" "second"
  assert_equal "$(cat "${newer}/source/b.txt")" "rewritten"
}

@test "dybatpho::backup_create --incremental without rsync refuses an unreadable part" {
  # The copy walked what `find` could list and passed over the rest, so a
  # directory it could not enter was snapshotted as an empty one and the
  # backup reported success.
  [[ "$(id -u)" != 0 ]] || skip "root reads every directory"
  mkdir -p "${SOURCE}/sealed"
  printf 'inside\n' > "${SOURCE}/sealed/e.txt"
  chmod 000 "${SOURCE}/sealed"

  PATH="$(path_without rsync)" run --separate-stderr dybatpho::backup_create -i "${SOURCE}" "${DEST}" site
  chmod 700 "${SOURCE}/sealed"
  assert_failure
  assert_stderr --partial "Cannot read every entry under"
  run_traced find "${DEST}" -name '*.snapshot'
  assert_output ""
}

@test "dybatpho::backup_create --incremental links without rsync too" {
  local older newer
  mkdir -p "${SOURCE}/sub dir" "${SOURCE}/locked"
  printf 'deep\n' > "${SOURCE}/sub dir/c.txt"
  printf 'secret\n' > "${SOURCE}/locked/d.txt"
  chmod 0555 "${SOURCE}/locked"
  printf 'mode\n' > "${SOURCE}/m.sh"
  ln -s a.txt "${SOURCE}/link"
  mkfifo "${SOURCE}/pipe"

  PATH="$(path_without rsync)" run_traced dybatpho::backup_create -i "${SOURCE}" "${DEST}" site
  assert_success
  older="${output}"
  printf 'rewritten\n' > "${SOURCE}/b.txt"
  chmod 0755 "${SOURCE}/m.sh"
  PATH="$(path_without rsync)" run_traced dybatpho::backup_create -i "${SOURCE}" "${DEST}" site
  assert_success
  newer="${output}"
  chmod 0755 "${SOURCE}/locked" "${older}/source/locked" "${newer}/source/locked"

  assert [ "${older}/source/a.txt" -ef "${newer}/source/a.txt" ]
  assert [ "${older}/source/sub dir/c.txt" -ef "${newer}/source/sub dir/c.txt" ]
  refute [ "${older}/source/b.txt" -ef "${newer}/source/b.txt" ]
  # Same content under a new mode is a new file, or the older snapshot's copy
  # would change mode with it.
  refute [ "${older}/source/m.sh" -ef "${newer}/source/m.sh" ]
  assert_equal "$(readlink "${newer}/source/link")" "a.txt"
  assert_file_not_exist "${newer}/source/pipe"
  assert_equal "$(cat "${newer}/source/locked/d.txt")" "secret"
  run_traced -0 dybatpho::backup_verify "${newer}"
}

@test "dybatpho::backup_create --incremental keeps the directory modes of the source" {
  mkdir -p "${SOURCE}/locked"
  printf 'secret\n' > "${SOURCE}/locked/d.txt"
  chmod 0555 "${SOURCE}/locked"

  local snap
  snap="$(PATH="$(path_without rsync)" snapshot "${SOURCE}" "${DEST}" site)"
  local mode
  mode="$(__dybatpho_file_stat mode "${snap}/source/locked")"
  # Unlocked again before asserting, so bats can clean the directory up.
  chmod 0755 "${SOURCE}/locked" "${snap}/source/locked"
  assert_equal "${mode}" "555"
}

@test "dybatpho::backup_create --incremental snapshots a single file" {
  local older newer
  older="$(snapshot "${SOURCE}/a.txt" "${DEST}" config)"
  newer="$(PATH="$(path_without rsync)" snapshot "${SOURCE}/a.txt" "${DEST}" config)"
  assert_file_exist "${older}/a.txt"
  assert [ "${older}/a.txt" -ef "${newer}/a.txt" ]
}

@test "dybatpho::backup_create --incremental leaves nothing behind when a file cannot be read" {
  [[ "${EUID}" -ne 0 ]] || skip "root reads every file"
  chmod 000 "${SOURCE}/b.txt"

  PATH="$(path_without rsync)" run --separate-stderr dybatpho::backup_create -i "${SOURCE}" "${DEST}" site
  chmod 644 "${SOURCE}/b.txt"
  assert_failure
  assert_stderr --partial "Could not snapshot: "
  run_traced -0 dybatpho::backup_list "${DEST}"
  assert_output ""
  run_traced -0 find "${DEST}" -mindepth 1
  assert_output ""
}

@test "dybatpho::backup_verify checks a snapshot's whole tree" {
  local snap
  snap="$(snapshot "${SOURCE}" "${DEST}" site)"
  run_traced -0 dybatpho::backup_verify "${snap}"

  printf 'intruder\n' > "${snap}/source/new.txt"
  run_traced --separate-stderr -1 dybatpho::backup_verify "${snap}"
  assert_stderr --partial "does not match its sidecar"
  rm "${snap}/source/new.txt"

  rm "${snap}/source/a.txt"
  printf 'tampered\n' > "${snap}/source/a.txt"
  run_traced -1 dybatpho::backup_verify "${snap}"

  rm "${snap}.sha256"
  run --separate-stderr dybatpho::backup_verify "${snap}"
  assert_failure
  assert_stderr --partial "No checksum sidecar beside"
}

@test "dybatpho::backup_list merges archives and snapshots in the order they were taken" {
  plant "site-20260101T000000Z.tar.gz"
  mkdir -p "${DEST}/site-20260201T000000Z.snapshot" "${DEST}/site-20260401T000000Z.snapshot"
  plant "site-20260301T000000Z.tar.gz"
  # A file with the suffix is not a snapshot, and neither is a link to one.
  printf 'x\n' > "${DEST}/site-20260501T000000Z.snapshot"
  ln -s "${DEST}/site-20260401T000000Z.snapshot" "${DEST}/site-20260601T000000Z.snapshot"

  run_traced -0 dybatpho::backup_list "${DEST}" site
  assert_output - << EOF
${DEST}/site-20260401T000000Z.snapshot
${DEST}/site-20260301T000000Z.tar.gz
${DEST}/site-20260201T000000Z.snapshot
${DEST}/site-20260101T000000Z.tar.gz
EOF

  run_traced -0 dybatpho::backup_latest "${DEST}"
  assert_output "${DEST}/site-20260401T000000Z.snapshot"
}

@test "dybatpho::backup_restore copies a snapshot back as plain files" {
  local snap target="${BATS_TEST_TMPDIR}/restored"
  snap="$(snapshot "${SOURCE}" "${DEST}" site)"

  run_traced -0 dybatpho::backup_restore --force "${snap}" "${target}"
  assert_equal "$(cat "${target}/source/a.txt")" "first"
  refute [ "${target}/source/a.txt" -ef "${snap}/source/a.txt" ]

  # Restoring over it again asks first, and refuses without a terminal.
  printf 'local edit\n' > "${target}/source/a.txt"
  run_traced --separate-stderr -1 dybatpho::backup_restore "${snap}" "${target}"
  assert_stderr --partial "Aborted restore"
  assert_equal "$(cat "${target}/source/a.txt")" "local edit"

  DYBATPHO_FORCE=true run_traced -0 dybatpho::backup_restore "${snap}" "${target}"
  assert_equal "$(cat "${target}/source/a.txt")" "first"
}

@test "dybatpho::backup_restore restores a single-file snapshot, and reports under DRY_RUN" {
  local snap target="${BATS_TEST_TMPDIR}/restored"
  snap="$(snapshot "${SOURCE}/a.txt" "${DEST}" config)"

  DRY_RUN=true run_traced -0 dybatpho::backup_restore --force "${snap}" "${target}"
  assert_file_not_exist "${target}/a.txt"

  run_traced -0 dybatpho::backup_restore --force "${snap}" "${target}"
  assert_equal "$(cat "${target}/a.txt")" "first"
}

@test "dybatpho::backup_restore refuses a tampered snapshot and an ambiguous one" {
  local snap target="${BATS_TEST_TMPDIR}/restored"
  snap="$(snapshot "${SOURCE}" "${DEST}" site)"
  printf 'extra\n' > "${snap}/stray"

  run_traced --separate-stderr -1 dybatpho::backup_restore --force "${snap}" "${target}"
  assert_file_not_exist "${target}/source/a.txt"

  # A sidecar that agrees with a snapshot holding two entries still leaves no
  # single entry to restore.
  local checksum
  __dybatpho_backup_tree_hash_into checksum "${snap}"
  printf '%s  %s\n' "${checksum}" "$(basename "${snap}")" > "${snap}.sha256"
  run --separate-stderr dybatpho::backup_restore --force "${snap}" "${target}"
  assert_failure
  assert_stderr --partial "Expected one entry in snapshot"
}

@test "dybatpho::backup_prune removes a snapshot without breaking the ones it shares files with" {
  local older newer
  older="$(snapshot "${SOURCE}" "${DEST}" site)"
  printf 'rewritten\n' > "${SOURCE}/b.txt"
  newer="$(snapshot "${SOURCE}" "${DEST}" site)"

  run_traced -0 dybatpho::backup_prune --keep-count 1 --force "${DEST}"
  assert_dir_not_exist "${older}"
  assert_file_not_exist "${older}.sha256"
  assert_equal "$(cat "${newer}/source/a.txt")" "first"
  run_traced -0 dybatpho::backup_verify "${newer}"
}

@test "dybatpho::backup_diff compares snapshots with each other and with the live source" {
  local older newer
  older="$(snapshot "${SOURCE}" "${DEST}" site)"
  printf 'rewritten\n' > "${SOURCE}/b.txt"
  newer="$(snapshot "${SOURCE}" "${DEST}" site)"

  DYBATPHO_DIFF_COLOR=false run_traced -1 dybatpho::backup_diff "${older}" "${newer}"
  assert_output "~ b.txt"
  run_traced -0 dybatpho::backup_diff "${newer}" "${SOURCE}"

  # A snapshot lines up with an archive of the same source too.
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" site)"
  run_traced -0 dybatpho::backup_diff "${newer}" "${archive}"

  printf 'tampered\n' >> "${newer}/source/b.txt"
  run -2 dybatpho::backup_diff "${older}" "${newer}"
  assert_output --partial "fails its checksum"
  rm "${newer}.sha256"
  run -2 dybatpho::backup_diff "${older}" "${newer}"
  assert_output --partial "No checksum sidecar beside: ${newer}"
}

@test "dybatpho::backup_create --incremental does not overwrite a snapshot taken in the same second" {
  dybatpho::date_now() { printf '20260101T000000Z\n'; }

  local first second
  first="$(snapshot "${SOURCE}" "${DEST}" site)"
  second="$(snapshot "${SOURCE}" "${DEST}" site)"
  assert_equal "${first}" "${DEST}/site-20260101T000000Z.snapshot"
  assert_equal "${second}" "${DEST}/site-20260101T000000Z-1.snapshot"
  assert [ "${first}/source/a.txt" -ef "${second}/source/a.txt" ]
}

@test "dybatpho::backup_diff asks for the diff module when it is not loaded" {
  # `backup` does not load `diff`, so a script that only takes and restores
  # backups does not pay for it. A child shell started from a file, without
  # the functions this process exports, shows what such a script sees.
  local archive
  archive="$(dybatpho::backup_create "${SOURCE}" "${DEST}" snap)"
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules backup\n' "${DYBATPHO_DIR}/init.sh"
    printf 'dybatpho::backup_verify %q && printf "verified\\n"\n' "${archive}"
    printf 'dybatpho::backup_diff --summary %q %q\n' "${archive}" "${SOURCE}"
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_line --index 0 "verified"
  assert_output --partial "dybatpho::backup_diff needs the diff module, load it with: dybatpho::load diff"

  # Once the script loads it, the same comparison runs and finds nothing.
  sed_in_place 's/--modules backup$/--modules backup diff/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_line "+0 -0 ~0"
}
