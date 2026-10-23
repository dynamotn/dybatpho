setup() {
  load test_helper
  ARCHIVE_SH="${DYBATPHO_DIR}/scripts/changelog_archive.sh"
  # A repository of its own, so `scripts/lint.sh` can be pointed at the result:
  # it checks the changelog next to the `init.sh` it was started from.
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}/scripts"
  cp -R "${DYBATPHO_DIR}/src" "${REPO}/src"
  cp "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/VERSION" "${REPO}/"
  cp "${ARCHIVE_SH}" "${DYBATPHO_DIR}/scripts/lint.sh" "${REPO}/scripts/"
  write_fixture > "${REPO}/CHANGELOG.md"
}

# @description Print a small changelog with two majors before the current one.
write_fixture() {
  cat << 'EOF'
# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- **`foo`** — something new.

## [3.0.0] - 2026-03-01

### Changed

- **BREAKING** `dybatpho::three` replaces `dybatpho::two`.

## [2.1.0] - 2026-02-01

### Added

- **`two`** — a minor release.

## [2.0.0] - 2026-01-15

### Removed

- **BREAKING** `dybatpho::one` is gone.

## [1.0.0] - 2026-01-01

### Added

- **`one`** — the first release.

[Unreleased]: https://example.test/dyb/compare/v3.0.0...HEAD
[3.0.0]: https://example.test/dyb/compare/v2.1.0...v3.0.0
[2.1.0]: https://example.test/dyb/compare/v2.0.0...v2.1.0
[2.0.0]: https://example.test/dyb/compare/v1.0.0...v2.0.0
[1.0.0]: https://example.test/dyb/releases/tag/v1.0.0
EOF
}

# Run a script of the copied repository the way a user would.
repo_script() {
  local script="$1"
  shift
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES -u DRY_RUN \
    bash "${REPO}/scripts/${script}" "$@"
}

@test "changelog_archive.sh --dry-run names what would move and writes nothing" {
  local before
  before="$(cat "${REPO}/CHANGELOG.md")"
  run --separate-stderr repo_script changelog_archive.sh --before 3.0.0 --dry-run
  assert_success
  assert_stderr --partial "Archiving 3 release(s) older than 3.0.0: 2.1.0 2.0.0 1.0.0"
  assert_equal "$(cat "${REPO}/CHANGELOG.md")" "${before}"
  assert_not_exists "${REPO}/docs/changelog"
}

@test "changelog_archive.sh moves old sections and their links into one file per major" {
  run --separate-stderr repo_script changelog_archive.sh --before 3.0.0
  assert_success

  local main="${REPO}/CHANGELOG.md" two="${REPO}/docs/changelog/CHANGELOG-2.x.md"
  local one="${REPO}/docs/changelog/CHANGELOG-1.x.md"
  assert_file_exists "${two}"
  assert_file_exists "${one}"

  # The current major and Unreleased stay, with their links.
  run grep -c '^## \[' "${main}"
  assert_output "2"
  run grep -E '^\[(2\.1\.0|2\.0\.0|1\.0\.0)\]:' "${main}"
  assert_failure
  run grep -F '[3.0.0]: https://example.test/dyb/compare/v2.1.0...v3.0.0' "${main}"
  assert_success
  # The index sits in the preamble, newest major first, before Unreleased.
  run grep -n -F 'Older releases are archived by major version: [2.x](docs/changelog/CHANGELOG-2.x.md), [1.x](docs/changelog/CHANGELOG-1.x.md).' "${main}"
  assert_success
  assert_output --regexp '^[0-9]+:'
  [[ "${output%%:*}" -lt "$(grep -n '^## \[Unreleased\]' "${main}" | cut -d: -f1)" ]]

  # Each archive holds its own versions, newest first, with their links and a
  # way back to the main file.
  run grep -E '^## \[' "${two}"
  assert_output "$(printf '%s\n' '## [2.1.0] - 2026-02-01' '## [2.0.0] - 2026-01-15')"
  run grep -F -- '- **BREAKING** `dybatpho::one` is gone.' "${two}"
  assert_success
  run grep -F '[2.0.0]: https://example.test/dyb/compare/v1.0.0...v2.0.0' "${two}"
  assert_success
  run grep -F '[CHANGELOG.md](../../CHANGELOG.md)' "${two}"
  assert_success
  run grep -F '[1.0.0]: https://example.test/dyb/releases/tag/v1.0.0' "${one}"
  assert_success

  # The result is what `scripts/lint.sh` accepts.
  run --separate-stderr repo_script lint.sh --stage changelog
  assert_success
}

@test "changelog_archive.sh is idempotent and merges a later cut-off into the archive" {
  repo_script changelog_archive.sh --before 3.0.0 2> /dev/null
  local main two
  main="$(cat "${REPO}/CHANGELOG.md")"
  two="$(cat "${REPO}/docs/changelog/CHANGELOG-2.x.md")"

  run --separate-stderr repo_script changelog_archive.sh --before 3.0.0
  assert_success
  assert_stderr --partial "No release"
  assert_equal "$(cat "${REPO}/CHANGELOG.md")" "${main}"
  assert_equal "$(cat "${REPO}/docs/changelog/CHANGELOG-2.x.md")" "${two}"

  # A later run reaches the next major and lists it in the index too.
  run --separate-stderr repo_script changelog_archive.sh --before 4.0.0
  assert_success
  assert_file_exists "${REPO}/docs/changelog/CHANGELOG-3.x.md"
  run grep -c '^## \[' "${REPO}/CHANGELOG.md"
  assert_output "1"
  run grep -F '[3.x](docs/changelog/CHANGELOG-3.x.md), [2.x]' "${REPO}/CHANGELOG.md"
  assert_success
  assert_equal "$(cat "${REPO}/docs/changelog/CHANGELOG-2.x.md")" "${two}"
  run --separate-stderr repo_script lint.sh --stage changelog
  assert_success
}

@test "changelog_archive.sh merges into an archive in version order, preferring CHANGELOG.md" {
  # An archive already holding 2.0.0 (stale wording) receives 2.1.0 and a
  # corrected 2.0.0 from the main file.
  mkdir -p "${REPO}/docs/changelog"
  cat > "${REPO}/docs/changelog/CHANGELOG-2.x.md" << 'EOF'
# Changelog: 2.x releases

## [2.0.0] - 2026-01-15

### Removed

- stale wording.

[2.0.0]: https://example.test/dyb/compare/v1.0.0...v2.0.0
EOF
  run --separate-stderr repo_script changelog_archive.sh --before 3.0.0
  assert_success
  local two="${REPO}/docs/changelog/CHANGELOG-2.x.md"
  run grep -E '^## \[' "${two}"
  assert_output "$(printf '%s\n' '## [2.1.0] - 2026-02-01' '## [2.0.0] - 2026-01-15')"
  run grep -F 'stale wording' "${two}"
  assert_failure
  run grep -c '^\[2\.[01]\.0\]: ' "${two}"
  assert_output "2"
}

@test "changelog_archive.sh refuses a bad cut-off and a changelog without Unreleased" {
  run --separate-stderr repo_script changelog_archive.sh --before v3
  assert_failure

  run --separate-stderr repo_script changelog_archive.sh
  assert_failure

  sed -i.bak '/^## \[Unreleased\]/d' "${REPO}/CHANGELOG.md"
  run --separate-stderr repo_script changelog_archive.sh --before 3.0.0
  assert_failure
  assert_stderr --partial "has no '## [Unreleased]' section"
}

@test "scripts/lint.sh rejects an archived release that is still in CHANGELOG.md or a dead index link" {
  repo_script changelog_archive.sh --before 3.0.0 2> /dev/null
  # Put 2.1.0 back into the main file: it is now described twice.
  printf '%s\n' '## [2.1.0] - 2026-02-01' '' '### Added' '' '- again.' '' \
    '[2.1.0]: https://example.test/dyb/compare/v2.0.0...v2.1.0' >> "${REPO}/CHANGELOG.md"
  rm "${REPO}/docs/changelog/CHANGELOG-1.x.md"

  run --separate-stderr repo_script lint.sh --stage changelog
  assert_failure
  assert_stderr --partial "[2.1.0] is described in more than one changelog file"
  assert_stderr --partial "links to a missing docs/changelog/CHANGELOG-1.x.md"
}

@test "changelog_archive.sh splits the real changelog without losing a line" {
  # The real changelog is archived already, so the run starts from it and its
  # archives and moves the next release out as well.
  cp "${DYBATPHO_DIR}/CHANGELOG.md" "${REPO}/CHANGELOG.md"
  mkdir -p "${REPO}/docs/changelog"
  cp "${DYBATPHO_DIR}"/docs/changelog/CHANGELOG-*.md "${REPO}/docs/changelog/"
  local cut="6.0.1"
  # Every non-blank line of the inputs is in exactly one of the outputs; the
  # boilerplate each archive file and the index carry is set aside.
  content_lines() {
    grep -hv '^[[:space:]]*$' "$@" \
      | grep -v -e '^<!-- ' -e '^Older releases are archived' -e '^# Changelog: ' \
        -e '^Releases [0-9]*\.x of dybatpho' -e '^`scripts/changelog_archive.sh`' \
        -e '^\[Keep a Changelog\](https://keepachangelog.com/en/1.1.0/), and this project$' \
        -e '^adheres to \[Semantic Versioning\]' \
      | sort
  }
  local original moved
  original="$(content_lines "${REPO}/CHANGELOG.md" "${REPO}"/docs/changelog/CHANGELOG-*.md)"
  run --separate-stderr repo_script changelog_archive.sh --before "${cut}"
  assert_success
  assert_file_exist "${REPO}/docs/changelog/CHANGELOG-6.x.md"
  moved="$(content_lines "${REPO}/CHANGELOG.md" "${REPO}"/docs/changelog/CHANGELOG-*.md)"
  assert_equal "${moved}" "${original}"
  run --separate-stderr repo_script lint.sh --stage changelog
  assert_success
}
