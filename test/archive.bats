setup() {
  load test_helper
}

@test "dybatpho::archive_create creates a tar.gz archive from a directory" {
  local source_dir="${BATS_TEST_TMPDIR}/bundle"
  local archive_path="${BATS_TEST_TMPDIR}/bundle.tar.gz"
  local args_file="${BATS_TEST_TMPDIR}/tar-create-args"
  mkdir -p "${source_dir}"

  stub tar ": echo \"\$*\" > ${args_file}"
  run dybatpho::archive_create "${source_dir}" "${archive_path}"
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "-C ${BATS_TEST_TMPDIR} -czf ${archive_path} bundle"
  unstub tar
}

@test "dybatpho::archive_create supports tar.xz and tar.zst archives" {
  local source_dir="${BATS_TEST_TMPDIR}/bundle"
  mkdir -p "${source_dir}"
  local args_file="${BATS_TEST_TMPDIR}/tar-archive-args"

  stub tar \
    ": echo \"\$*\" > ${args_file}" \
    ": echo \"\$*\" > ${args_file}"

  run dybatpho::archive_create "${source_dir}" "${BATS_TEST_TMPDIR}/bundle.tar.xz"
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "-C ${BATS_TEST_TMPDIR} -cJf ${BATS_TEST_TMPDIR}/bundle.tar.xz bundle"

  run dybatpho::archive_create "${source_dir}" "${BATS_TEST_TMPDIR}/bundle.tar.zst"
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "--zstd -C ${BATS_TEST_TMPDIR} -cf ${BATS_TEST_TMPDIR}/bundle.tar.zst bundle"
  unstub tar
}

@test "dybatpho::archive_create supports xz gz bz2 and zst for single files" {
  local source_file="${BATS_TEST_TMPDIR}/bundle.txt"
  printf 'hello\n' > "${source_file}"
  local xz_args="${BATS_TEST_TMPDIR}/xz-args"
  local gz_args="${BATS_TEST_TMPDIR}/gz-args"
  local bz2_args="${BATS_TEST_TMPDIR}/bz2-args"
  local zst_args="${BATS_TEST_TMPDIR}/zst-args"

  stub xz ": echo \"\$*\" > ${xz_args}; printf 'xz-data'"
  run dybatpho::archive_create "${source_file}" "${BATS_TEST_TMPDIR}/bundle.txt.xz"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/bundle.txt.xz"
  assert_success
  assert_output "xz-data"
  run cat "${xz_args}"
  assert_success
  assert_output "-c ${source_file}"
  unstub xz

  stub gzip ": echo \"\$*\" > ${gz_args}; printf 'gz-data'"
  run dybatpho::archive_create "${source_file}" "${BATS_TEST_TMPDIR}/bundle.txt.gz"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/bundle.txt.gz"
  assert_success
  assert_output "gz-data"
  run cat "${gz_args}"
  assert_success
  assert_output "-c ${source_file}"
  unstub gzip

  stub bzip2 ": echo \"\$*\" > ${bz2_args}; printf 'bz2-data'"
  run dybatpho::archive_create "${source_file}" "${BATS_TEST_TMPDIR}/bundle.txt.bz2"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/bundle.txt.bz2"
  assert_success
  assert_output "bz2-data"
  run cat "${bz2_args}"
  assert_success
  assert_output "-c ${source_file}"
  unstub bzip2

  stub zstd ": echo \"\$*\" > ${zst_args}; printf 'zst-data'"
  run dybatpho::archive_create "${source_file}" "${BATS_TEST_TMPDIR}/bundle.txt.zst"
  assert_success
  run cat "${BATS_TEST_TMPDIR}/bundle.txt.zst"
  assert_success
  assert_output "zst-data"
  run cat "${zst_args}"
  assert_success
  assert_output "-q -c ${source_file}"
  unstub zstd
}

@test "dybatpho::archive_create creates a zip archive from a directory" {
  local source_dir="${BATS_TEST_TMPDIR}/bundle"
  local archive_path="${BATS_TEST_TMPDIR}/bundle.zip"
  local args_file="${BATS_TEST_TMPDIR}/zip-create-args"
  local pwd_file="${BATS_TEST_TMPDIR}/zip-create-pwd"
  mkdir -p "${source_dir}"

  stub zip ": pwd > ${pwd_file}; echo \"\$*\" > ${args_file}"
  run dybatpho::archive_create "${source_dir}" "${archive_path}"
  assert_success
  run cat "${pwd_file}"
  assert_success
  assert_output "${BATS_TEST_TMPDIR}"
  run cat "${args_file}"
  assert_success
  assert_output "-rq ${archive_path} bundle"
  unstub zip
}

@test "dybatpho::archive_extract extracts tar.gz archives into the destination" {
  local archive_path="${BATS_TEST_TMPDIR}/bundle.tar.gz"
  local destination="${BATS_TEST_TMPDIR}/out"
  local args_file="${BATS_TEST_TMPDIR}/tar-extract-args"
  : > "${archive_path}"

  stub tar ": echo \"\$*\" > ${args_file}"
  run dybatpho::archive_extract "${archive_path}" "${destination}"
  assert_success
  [ -d "${destination}" ]
  run cat "${args_file}"
  assert_success
  assert_output "-xzf ${archive_path} -C ${destination}"
  unstub tar
}

@test "dybatpho::archive_extract supports strip-components for tar archives" {
  local archive_path="${BATS_TEST_TMPDIR}/bundle.tar.xz"
  local destination="${BATS_TEST_TMPDIR}/out"
  local args_file="${BATS_TEST_TMPDIR}/tar-strip-args"
  : > "${archive_path}"

  stub tar ": echo \"\$*\" > ${args_file}"
  run dybatpho::archive_extract "${archive_path}" "${destination}" 1
  assert_success
  run cat "${args_file}"
  assert_success
  assert_output "-xJf ${archive_path} -C ${destination} --strip-components 1"
  unstub tar
}

@test "dybatpho::archive_extract extracts zip archives into the destination" {
  local archive_path="${BATS_TEST_TMPDIR}/bundle.zip"
  local destination="${BATS_TEST_TMPDIR}/out"
  local args_file="${BATS_TEST_TMPDIR}/unzip-extract-args"
  : > "${archive_path}"

  stub unzip ": echo \"\$*\" > ${args_file}"
  run dybatpho::archive_extract "${archive_path}" "${destination}"
  assert_success
  [ -d "${destination}" ]
  run cat "${args_file}"
  assert_success
  assert_output "-q ${archive_path} -d ${destination}"
  unstub unzip
}

@test "dybatpho::archive_extract supports strip-components for zip archives" {
  local archive_path="${BATS_TEST_TMPDIR}/bundle.zip"
  local destination="${BATS_TEST_TMPDIR}/out"
  : > "${archive_path}"

  stub unzip ": mkdir -p \"\$4/bundle/nested\"; printf 'hello\n' > \"\$4/bundle/nested/file.txt\""
  run dybatpho::archive_extract "${archive_path}" "${destination}" 1
  assert_success
  [ -f "${destination}/nested/file.txt" ]
  run cat "${destination}/nested/file.txt"
  assert_success
  assert_output "hello"
  unstub unzip
}

@test "dybatpho::archive_extract supports xz gz and bz2 single-file archives" {
  local xz_archive="${BATS_TEST_TMPDIR}/bundle.txt.xz"
  local gz_archive="${BATS_TEST_TMPDIR}/bundle.txt.gz"
  local bz2_archive="${BATS_TEST_TMPDIR}/bundle.txt.bz2"
  local destination="${BATS_TEST_TMPDIR}/out"
  : > "${xz_archive}"
  : > "${gz_archive}"
  : > "${bz2_archive}"

  stub xz ": printf 'hello-xz\n'"
  run dybatpho::archive_extract "${xz_archive}" "${destination}"
  assert_success
  run cat "${destination}/bundle.txt"
  assert_success
  assert_output "hello-xz"
  unstub xz

  stub gzip ": printf 'hello-gz\n'"
  run dybatpho::archive_extract "${gz_archive}" "${destination}"
  assert_success
  run cat "${destination}/bundle.txt"
  assert_success
  assert_output "hello-gz"
  unstub gzip

  stub bzip2 ": printf 'hello-bz2\n'"
  run dybatpho::archive_extract "${bz2_archive}" "${destination}"
  assert_success
  run cat "${destination}/bundle.txt"
  assert_success
  assert_output "hello-bz2"
  unstub bzip2
}

@test "dybatpho::archive_list lists tar, zip, and single-file compressed archives" {
  local tar_archive="${BATS_TEST_TMPDIR}/bundle.tar"
  local tar_zst_archive="${BATS_TEST_TMPDIR}/bundle.tar.zst"
  local zip_archive="${BATS_TEST_TMPDIR}/bundle.zip"
  local tar_args_file="${BATS_TEST_TMPDIR}/tar-list-args"
  local unzip_args_file="${BATS_TEST_TMPDIR}/unzip-list-args"
  : > "${tar_archive}"
  : > "${tar_zst_archive}"
  : > "${zip_archive}"

  stub tar \
    ": echo \"\$*\" > ${tar_args_file}; printf 'bundle/file.txt\n'" \
    ": echo \"\$*\" > ${tar_args_file}; printf 'bundle/file.txt\n'"
  run dybatpho::archive_list "${tar_archive}"
  assert_success
  assert_output "bundle/file.txt"
  run cat "${tar_args_file}"
  assert_success
  assert_output "-tf ${tar_archive}"

  run dybatpho::archive_list "${tar_zst_archive}"
  assert_success
  assert_output "bundle/file.txt"
  run cat "${tar_args_file}"
  assert_success
  assert_output "--zstd -tf ${tar_zst_archive}"
  unstub tar

  stub unzip ": echo \"\$*\" > ${unzip_args_file}; printf 'bundle/file.txt\n'"
  run dybatpho::archive_list "${zip_archive}"
  assert_success
  assert_output "bundle/file.txt"
  run cat "${unzip_args_file}"
  assert_success
  assert_output "-Z1 ${zip_archive}"
  unstub unzip

  run dybatpho::archive_list "${BATS_TEST_TMPDIR}/bundle.txt.xz"
  assert_success
  assert_output "bundle.txt"

  run dybatpho::archive_list "${BATS_TEST_TMPDIR}/bundle.txt.gz"
  assert_success
  assert_output "bundle.txt"
}

@test "dybatpho::archive_extract rejects strip-components for single-file archives" {
  local archive_path="${BATS_TEST_TMPDIR}/bundle.txt.xz"
  : > "${archive_path}"

  run dybatpho::archive_extract "${archive_path}" "${BATS_TEST_TMPDIR}/out" 1
  assert_failure
  assert_output --partial "strip-components is only supported for multi-entry archives"
}

@test "dybatpho::archive_create rejects unsupported formats" {
  local source_dir="${BATS_TEST_TMPDIR}/bundle"
  mkdir -p "${source_dir}"

  run dybatpho::archive_create "${source_dir}" "${BATS_TEST_TMPDIR}/bundle.rar"
  assert_failure
  assert_output --partial "Unsupported archive format"
}
