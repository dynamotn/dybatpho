setup() {
  load test_helper
  REPO="${BATS_TEST_TMPDIR}/repo"
  # A pre-commit hook runs this suite with `GIT_DIR` and `GIT_INDEX_FILE`
  # pointing at the real repository, and they win over `git -C`: the commits
  # below would land there, as `test/git.bats` already guards against.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
  _require_throwaway_repo
  git init -q "${REPO}"
  git -C "${REPO}" config user.email "test@dybatpho.invalid"
  git -C "${REPO}" config user.name "dybatpho test"
  # Some environments default to annotated or signed tags; a release repository
  # under test must not depend on the caller's Git configuration.
  git -C "${REPO}" config tag.gpgSign false
  git -C "${REPO}" config commit.gpgSign false
  # A throwaway repository must not inherit the developer's hooks: a global
  # `core.hooksPath`, which a pre-commit framework installs, would otherwise run
  # that hook inside these repositories and fail every commit the tests make.
  git -C "${REPO}" config core.hooksPath /dev/null
}

# Every helper here runs `git` against `${REPO}`. An empty or unexpected value
# would make `git -C` fall back to the current directory, which is the real
# dybatpho repository, and `git add -A` there would stage the whole worktree.
# `test/git.bats` guards its repositories the same way, for the same reason.
function _require_throwaway_repo {
  [[ -n "${BATS_TEST_TMPDIR:-}" ]] || {
    printf '%s\n' "BATS_TEST_TMPDIR is not set" >&2
    return 1
  }
  [[ -n "${REPO:-}" ]] || {
    printf '%s\n' "REPO is not set" >&2
    return 1
  }
  [[ "${REPO}" == "${BATS_TEST_TMPDIR}/"* ]] || {
    printf '%s\n' "Refusing to use a repository outside the test tmpdir: ${REPO}" >&2
    return 1
  }
}

commit() {
  local subject="$1"
  shift
  _require_throwaway_repo || return 1
  printf '%s\n' "${subject}" > "${REPO}/file-${RANDOM}"
  git -C "${REPO}" add -A
  git -C "${REPO}" commit -q -m "${subject}" ${@+"$@"}
}

tag() {
  _require_throwaway_repo || return 1
  git -C "${REPO}" tag -m "$1" "$1"
}

@test "dybatpho::release_commit_type classifies conventional subjects" {
  assert_equal "$(dybatpho::release_commit_type 'feat: add thing')" "feat"
  assert_equal "$(dybatpho::release_commit_type 'fix(parser): handle empty')" "fix"
  assert_equal "$(dybatpho::release_commit_type 'perf: faster')" "perf"
  assert_equal "$(dybatpho::release_commit_type 'docs: readme')" "docs"
  assert_equal "$(dybatpho::release_commit_type 'feat!: drop v1')" "breaking"
  assert_equal "$(dybatpho::release_commit_type 'feat(api)!: drop v1')" "breaking"
  assert_equal "$(dybatpho::release_commit_type 'FEAT: upper case')" "feat"
  assert_equal "$(dybatpho::release_commit_type 'no convention here')" "other"
  assert_equal "$(dybatpho::release_commit_type 'Merge branch main')" "other"
}

@test "dybatpho::release_bump_type takes the strongest change in the range" {
  commit "fix: one"
  tag v1.0.0
  commit "fix: two"
  assert_equal "$(dybatpho::release_bump_type "${REPO}" v1.0.0)" "patch"
  commit "feat: three"
  assert_equal "$(dybatpho::release_bump_type "${REPO}" v1.0.0)" "minor"
  commit "fix: four"
  # A later patch must not weaken the minor the range already earned.
  assert_equal "$(dybatpho::release_bump_type "${REPO}" v1.0.0)" "minor"
  commit "refactor!: five"
  assert_equal "$(dybatpho::release_bump_type "${REPO}" v1.0.0)" "major"
}

@test "dybatpho::release_bump_type honors a BREAKING CHANGE footer" {
  commit "feat: one"
  tag v1.0.0
  commit "refactor: internals" -m "BREAKING CHANGE: renamed the config key"
  assert_equal "$(dybatpho::release_bump_type "${REPO}" v1.0.0)" "major"
}

@test "dybatpho::release_bump_type reports nothing to release" {
  commit "feat: one"
  tag v1.0.0
  commit "docs: tidy"
  commit "chore: bump dep"
  run -1 dybatpho::release_bump_type "${REPO}" v1.0.0
  assert_output ""
}

@test "dybatpho::release_next_version bumps from the latest tag" {
  commit "feat: one"
  tag v1.2.3
  commit "fix: two"
  assert_equal "$(dybatpho::release_next_version "${REPO}")" "1.2.4"
  commit "feat: three"
  assert_equal "$(dybatpho::release_next_version "${REPO}")" "1.3.0"
  commit "feat!: four"
  assert_equal "$(dybatpho::release_next_version "${REPO}")" "2.0.0"
}

@test "dybatpho::release_next_version reads the whole history when nothing is tagged" {
  # The first commit must count: a range that excluded it would miss the only
  # feature in a brand new repository.
  commit "feat: the very first commit"
  assert_equal "$(dybatpho::release_next_version "${REPO}")" "0.1.0"
}

@test "dybatpho::release_next_version accepts an explicit base tag" {
  commit "feat: one"
  tag v1.0.0
  commit "feat: two"
  tag v1.1.0
  commit "fix: three"
  assert_equal "$(dybatpho::release_next_version "${REPO}" v1.0.0)" "1.1.0"
  assert_equal "$(dybatpho::release_next_version "${REPO}" v1.1.0)" "1.1.1"
}

@test "dybatpho::release_next_version reports nothing to release" {
  commit "feat: one"
  tag v1.0.0
  commit "docs: tidy"
  run -1 dybatpho::release_next_version "${REPO}"
  assert_output ""
}

@test "dybatpho::release_next_version rejects a tag that is not a version" {
  commit "feat: one"
  tag release-candidate
  run ! dybatpho::release_next_version "${REPO}" release-candidate
}

@test "dybatpho::release_changelog groups commits by what they changed" {
  commit "feat: one"
  tag v1.0.0
  commit "feat(api): new endpoint"
  commit "fix(parser): handle empty input"
  commit "perf: faster lookup"
  commit "feat!: drop the v1 endpoints"
  commit "docs: tidy readme"
  run -0 dybatpho::release_changelog "${REPO}" v1.0.0 HEAD 2.0.0
  assert_line --index 0 "## [2.0.0]"
  assert_line --partial "### Changed"
  assert_line --partial "- drop the v1 endpoints"
  assert_line --partial "### Added"
  assert_line --partial "- **api**: new endpoint"
  assert_line --partial "### Fixed"
  assert_line --partial "- **parser**: handle empty input"
  assert_line --partial "- faster lookup"
  # A docs commit is history, not release notes.
  refute_output --partial "tidy readme"
}

@test "dybatpho::release_changelog defaults the heading and omits empty sections" {
  commit "feat: one"
  tag v1.0.0
  commit "fix: only a fix"
  run -0 dybatpho::release_changelog "${REPO}" v1.0.0
  assert_line --index 0 "## [Unreleased]"
  assert_line --partial "### Fixed"
  refute_output --partial "### Added"
  refute_output --partial "### Changed"
}

@test "dybatpho::release_artifact_name follows the Go release layout" {
  assert_equal "$(dybatpho::release_artifact_name mytool 1.3.0 linux amd64)" \
    "mytool_1.3.0_linux_amd64.tar.gz"
  assert_equal "$(dybatpho::release_artifact_name mytool 1.3.0 darwin arm64)" \
    "mytool_1.3.0_darwin_arm64.tar.gz"
  # Windows downloads are expected to be zip files.
  assert_equal "$(dybatpho::release_artifact_name mytool 1.3.0 windows amd64)" \
    "mytool_1.3.0_windows_amd64.zip"
  assert_equal "$(dybatpho::release_artifact_name mytool v1.3.0 linux amd64)" \
    "mytool_1.3.0_linux_amd64.tar.gz"
}

@test "dybatpho::release_artifact_name defaults to the running platform" {
  assert_equal "$(dybatpho::release_artifact_name mytool 1.0.0)" \
    "mytool_1.0.0_$(dybatpho::goos)_$(dybatpho::goarch).tar.gz"
}

@test "dybatpho::release_package builds one artifact per platform" {
  local source="${BATS_TEST_TMPDIR}/build"
  mkdir -p "${source}"
  printf 'binary\n' > "${source}/mytool"
  local out="${BATS_TEST_TMPDIR}/dist"

  local artifact
  artifact="$(dybatpho::release_package "${source}" "${out}" mytool 1.3.0 linux amd64)"
  assert_equal "${artifact}" "${out}/mytool_1.3.0_linux_amd64.tar.gz"
  assert [ -f "${artifact}" ]
  run dybatpho::archive_list "${artifact}"
  assert_output --partial "mytool"

  dybatpho::release_package "${source}" "${out}" mytool 1.3.0 darwin arm64 > /dev/null
  assert [ -f "${out}/mytool_1.3.0_darwin_arm64.tar.gz" ]
}

@test "dybatpho::release_package creates the output directory and rejects a missing source" {
  local source="${BATS_TEST_TMPDIR}/build2"
  mkdir -p "${source}"
  printf 'binary\n' > "${source}/mytool"
  dybatpho::release_package "${source}" "${BATS_TEST_TMPDIR}/made/up/dist" mytool 1.0.0 linux amd64 > /dev/null
  assert [ -d "${BATS_TEST_TMPDIR}/made/up/dist" ]
  run ! dybatpho::release_package "${BATS_TEST_TMPDIR}/absent" "${BATS_TEST_TMPDIR}/dist" mytool 1.0.0
}

@test "dybatpho::release_checksums writes a file sha256sum can verify" {
  local out="${BATS_TEST_TMPDIR}/dist3"
  mkdir -p "${out}"
  printf 'one\n' > "${out}/mytool_1.0.0_linux_amd64.tar.gz"
  printf 'two\n' > "${out}/mytool_1.0.0_darwin_arm64.tar.gz"

  local sums
  sums="$(dybatpho::release_checksums "${out}")"
  assert_equal "${sums}" "${out}/SHA256SUMS"
  assert_equal "$(wc -l < "${sums}" | tr -d ' ')" "2"
  # Names are recorded bare, so the file verifies from inside its own directory.
  refute grep -q '/' "${sums}"
  if dybatpho::is command sha256sum; then
    run -0 bash -c "cd '${out}' && sha256sum -c SHA256SUMS"
  fi
}

@test "dybatpho::release_checksums leaves signatures and itself out" {
  local out="${BATS_TEST_TMPDIR}/dist4"
  mkdir -p "${out}"
  printf 'one\n' > "${out}/mytool_1.0.0_linux_amd64.tar.gz"
  printf 'sig\n' > "${out}/mytool_1.0.0_linux_amd64.tar.gz.asc"
  printf 'sig\n' > "${out}/other.sig"
  local sums
  sums="$(dybatpho::release_checksums "${out}")"
  assert_equal "$(wc -l < "${sums}" | tr -d ' ')" "1"
  refute grep -q 'asc' "${sums}"
  # Running again must not fold the previous checksum file into the new one.
  dybatpho::release_checksums "${out}" > /dev/null
  assert_equal "$(wc -l < "${sums}" | tr -d ' ')" "1"
}

@test "dybatpho::release_checksums rejects an empty or missing directory" {
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  run ! dybatpho::release_checksums "${BATS_TEST_TMPDIR}/empty"
  run ! dybatpho::release_checksums "${BATS_TEST_TMPDIR}/absent-dir"
}

@test "dybatpho::release_sign runs the configured signing command" {
  local target="${BATS_TEST_TMPDIR}/SHA256SUMS"
  printf 'sums\n' > "${target}"
  local signature
  # shellcheck disable=2030
  DYBATPHO_RELEASE_SIGN_CMD="${BATS_TEST_TMPDIR}/signer"
  cat > "${BATS_TEST_TMPDIR}/signer" << 'SIGNER'
#!/usr/bin/env bash
printf 'signature of %s\n' "$2" > "$1"
SIGNER
  chmod +x "${BATS_TEST_TMPDIR}/signer"
  signature="$(dybatpho::release_sign "${target}")"
  DYBATPHO_RELEASE_SIGN_CMD=""
  assert_equal "${signature}" "${target}.asc"
  assert_equal "$(cat "${signature}")" "signature of ${target}"
}

@test "dybatpho::release_sign accepts an explicit signature path and rejects a missing file" {
  local target="${BATS_TEST_TMPDIR}/artifact"
  printf 'x\n' > "${target}"
  # shellcheck disable=2030,2031
  DYBATPHO_RELEASE_SIGN_CMD="${BATS_TEST_TMPDIR}/signer2"
  printf '#!/usr/bin/env bash\nprintf sig > "$1"\n' > "${BATS_TEST_TMPDIR}/signer2"
  chmod +x "${BATS_TEST_TMPDIR}/signer2"
  assert_equal "$(dybatpho::release_sign "${target}" "${target}.minisig")" "${target}.minisig"
  assert [ -f "${target}.minisig" ]
  DYBATPHO_RELEASE_SIGN_CMD=""
  run ! dybatpho::release_sign "${BATS_TEST_TMPDIR}/absent-file"
}

@test "the release writers touch nothing under DRY_RUN" {
  local source="${BATS_TEST_TMPDIR}/build5"
  mkdir -p "${source}"
  printf 'binary\n' > "${source}/mytool"
  local out="${BATS_TEST_TMPDIR}/dist5"
  mkdir -p "${out}"
  printf 'one\n' > "${out}/mytool_1.0.0_linux_amd64.tar.gz"

  # shellcheck disable=2030,2031
  export DRY_RUN=true
  local artifact sums signature
  artifact="$(dybatpho::release_package "${source}" "${BATS_TEST_TMPDIR}/dist6" mytool 1.0.0 linux amd64 | tail -1)"
  sums="$(dybatpho::release_checksums "${out}" | tail -1)"
  signature="$(dybatpho::release_sign "${out}/mytool_1.0.0_linux_amd64.tar.gz" | tail -1)"
  unset DRY_RUN

  refute [ -e "${artifact}" ]
  refute [ -e "${sums}" ]
  refute [ -e "${signature}" ]
  refute [ -d "${BATS_TEST_TMPDIR}/dist6" ]
}

@test "dybatpho::release_commit_parse separates type, scope, breaking and description" {
  run -0 dybatpho::release_commit_parse "feat(api)!: drop the v1 endpoints"
  assert_line --index 0 "feat"
  assert_line --index 1 "api"
  assert_line --index 2 "true"
  assert_line --index 3 "drop the v1 endpoints"
}

@test "dybatpho::release_commit_parse reports an absent scope and marker" {
  # Compared whole: an absent scope is an empty line, and Bats drops empty
  # lines from the array that `assert_line` indexes into.
  run -0 dybatpho::release_commit_parse "fix: handle empty input"
  assert_output "$(printf 'fix\n\nfalse\nhandle empty input')"
}

@test "dybatpho::release_commit_parse reads a BREAKING CHANGE footer from the body" {
  run -0 dybatpho::release_commit_parse "refactor: rework the loader" \
    "$(printf 'Some detail.\n\nBREAKING CHANGE: the config key was renamed\n')"
  # The description still comes from the subject, not from the footer.
  assert_output "$(printf 'refactor\n\ntrue\nrework the loader')"
}

@test "dybatpho::release_commit_parse keeps an unconventional subject whole" {
  run -0 dybatpho::release_commit_parse "Merge branch 'main' into topic"
  assert_output "$(printf "other\n\nfalse\nMerge branch 'main' into topic")"
}

@test "dybatpho::release_commit_parse lowercases the type" {
  run -0 dybatpho::release_commit_parse "FEAT(API): shout"
  assert_line --index 0 "feat"
  # The scope is left as written, because it names something in the project.
  assert_line --index 1 "API"
}

@test "dybatpho::release_commit_type keeps reporting a breaking change as its own kind" {
  # The older helper conflates the two on purpose; the parser is what a caller
  # reaches for when it needs both the type and the breaking flag.
  assert_equal "$(dybatpho::release_commit_type 'feat(api)!: x')" "breaking"
  assert_equal "$(dybatpho::release_commit_type 'fix: y')" "fix"
  assert_equal "$(dybatpho::release_commit_type 'nope')" "other"
}
