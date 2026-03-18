setup() {
  load test_helper
}

# ---------------------------------------------------------------------------
# Safety guards – prevent tests from touching the real dybatpho repository
# ---------------------------------------------------------------------------

function _safe_git_test_root {
  [[ -n "${BATS_TEST_TMPDIR:-}" ]] || { printf '%s\n' "BATS_TEST_TMPDIR is not set" >&2; return 1; }
  [[ -d "${BATS_TEST_TMPDIR}" ]] || { printf '%s\n' "BATS_TEST_TMPDIR does not exist: ${BATS_TEST_TMPDIR}" >&2; return 1; }
  printf '%s\n' "${BATS_TEST_TMPDIR}"
}

function _new_git_repo_path {
  local test_root
  test_root="$(_safe_git_test_root)" || return $?
  mktemp -d -p "${test_root}" git-repo-XXXXXXXX
}

function _require_safe_git_test_path {
  local repo_path test_root
  dybatpho::expect_args repo_path -- "$@"
  test_root="$(_safe_git_test_root)" || return $?
  [[ -n "${repo_path}" ]] || { printf '%s\n' "Refusing to use an empty repository path" >&2; return 1; }
  [[ "${repo_path}" == "${test_root}"/* ]] || { printf '%s\n' "Refusing to touch non-test path: ${repo_path}" >&2; return 1; }
  [[ "${repo_path}" != "${DYBATPHO_DIR}" ]] || { printf '%s\n' "Refusing to touch the real dybatpho repository" >&2; return 1; }
  [[ "${repo_path}" != "${DYBATPHO_DIR}"/* ]] || { printf '%s\n' "Refusing to touch paths inside the real dybatpho repository" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Helpers that build isolated test repos
# Unset git env vars injected by the pre-commit hook so that `git -C`
# operates on the test repo's own .git, not on $DYBATPHO_DIR.
# ---------------------------------------------------------------------------

function _create_git_repo {
  local repo_path default_branch
  dybatpho::expect_args repo_path default_branch -- "$@"
  _require_safe_git_test_path "${repo_path}" || return $?
  mkdir -p "${repo_path}"
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
    git init -q -b "${default_branch}" "${repo_path}"
    git -C "${repo_path}" config user.name "dybatpho"
    git -C "${repo_path}" config user.email "dybatpho@example.com"
    git -C "${repo_path}" config commit.gpgsign false
    git -C "${repo_path}" config tag.gpgsign false
    git -C "${repo_path}" config gc.auto 0
    printf 'hello\n' > "${repo_path}/README.md"
    git -C "${repo_path}" add README.md
    git -C "${repo_path}" commit -qm 'Initial commit'
  )
}

function _append_git_commit {
  local repo_path message
  dybatpho::expect_args repo_path message -- "$@"
  _require_safe_git_test_path "${repo_path}" || return $?
  local author_name="${3:-dybatpho}"
  local author_email="${4:-dybatpho@example.com}"
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
    printf '%s\n' "${message}" >> "${repo_path}/README.md"
    git -C "${repo_path}" add README.md
    GIT_AUTHOR_NAME="${author_name}" \
      GIT_AUTHOR_EMAIL="${author_email}" \
      GIT_COMMITTER_NAME="${author_name}" \
      GIT_COMMITTER_EMAIL="${author_email}" \
      git -C "${repo_path}" commit -qm "${message}"
  )
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "dybatpho::git_root returns the top-level repository directory" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  mkdir -p "${repo_path}/nested/path"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_root "${repo_path}/nested/path"
  assert_success
  assert_output "${repo_path}"
}

@test "dybatpho::git_branch returns the current branch name" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" checkout -qb feature/test)

  run dybatpho::git_branch "${repo_path}"
  assert_success
  assert_output 'feature/test'
}

@test "dybatpho::git_branch falls back to a short SHA in detached HEAD state" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  local short_sha
  short_sha="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse --short HEAD)"
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" checkout -q --detach)

  run dybatpho::git_branch "${repo_path}"
  assert_success
  assert_output "${short_sha}"
}

@test "dybatpho::git_default_branch prefers origin HEAD when available" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" remote add origin https://example.com/repo.git
    git -C "${repo_path}" update-ref refs/remotes/origin/main "$(git -C "${repo_path}" rev-parse HEAD)"
    git -C "${repo_path}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  )

  run dybatpho::git_default_branch "${repo_path}"
  assert_success
  assert_output 'main'
}

@test "dybatpho::git_default_branch falls back to local master when origin HEAD is absent" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" master

  run dybatpho::git_default_branch "${repo_path}"
  assert_success
  assert_output 'master'
}

@test "dybatpho::git_commit_hash and dybatpho::git_commit_short_hash resolve commit SHAs" {
  local repo_path commit_sha short_sha
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  commit_sha="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse HEAD)"
  short_sha="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse --short=7 HEAD)"

  run dybatpho::git_commit_hash "${repo_path}"
  assert_success
  assert_output "${commit_sha}"

  run dybatpho::git_commit_short_hash "${repo_path}"
  assert_success
  assert_output "${short_sha}"
}

@test "dybatpho::git_commit_subject and dybatpho::git_commit_author inspect commit metadata" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _append_git_commit "${repo_path}" "Add feature" "release-bot" "release@example.com"

  run dybatpho::git_commit_subject "${repo_path}"
  assert_success
  assert_output 'Add feature'

  run dybatpho::git_commit_author "${repo_path}"
  assert_success
  assert_output 'release-bot'
}

@test "dybatpho::git_has_commit checks whether a commit exists" {
  local repo_path commit_sha
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  commit_sha="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse HEAD)"

  run dybatpho::git_has_commit "${repo_path}" "${commit_sha}"
  assert_success

  run dybatpho::git_has_commit "${repo_path}" deadbeef
  assert_failure
}

@test "dybatpho::git_commits_between and dybatpho::git_commit_count inspect commit ranges" {
  local repo_path second_commit third_commit
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" update-ref refs/tags/v1.0.0 "$(git -C "${repo_path}" rev-parse HEAD)")
  _append_git_commit "${repo_path}" "Add feature"
  second_commit="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse HEAD)"
  _append_git_commit "${repo_path}" "Ship release"
  third_commit="$(unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" rev-parse HEAD)"

  run dybatpho::git_commits_between "${repo_path}" v1.0.0 HEAD
  assert_success
  assert_output "${second_commit}"$'\n'"${third_commit}"

  run dybatpho::git_commit_count "${repo_path}" v1.0.0 HEAD
  assert_success
  assert_output '2'
}

@test "dybatpho::git_is_clean reflects repository changes" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_is_clean "${repo_path}"
  assert_success

  printf 'dirty\n' >> "${repo_path}/README.md"
  run dybatpho::git_is_clean "${repo_path}"
  assert_failure
}

@test "dybatpho::git_remote_url returns the configured remote URL" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" remote add origin https://example.com/repo.git)

  run dybatpho::git_remote_url origin "${repo_path}"
  assert_success
  assert_output 'https://example.com/repo.git'
}

@test "dybatpho::git_has_remote checks whether a remote exists" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" remote add origin https://example.com/repo.git)

  run dybatpho::git_has_remote origin "${repo_path}"
  assert_success

  run dybatpho::git_has_remote upstream "${repo_path}"
  assert_failure
}

@test "dybatpho::git_changed_files lists tracked and untracked changes" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  printf 'dirty\n' >> "${repo_path}/README.md"
  printf 'new\n' > "${repo_path}/notes.txt"

  run dybatpho::git_changed_files "${repo_path}"
  assert_success
  assert_output $'README.md\nnotes.txt'
}

@test "dybatpho::git_tags_containing lists tags containing a commit" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (unset GIT_DIR GIT_WORK_TREE; git -C "${repo_path}" update-ref refs/tags/v1.0.0 "$(git -C "${repo_path}" rev-parse HEAD)")

  run dybatpho::git_tags_containing "${repo_path}"
  assert_success
  assert_output 'v1.0.0'
}

@test "Commit-resolving Git helpers fail clearly for an unknown commit" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_commit_subject "${repo_path}" deadbeef
  assert_failure
  assert_output --partial 'Unknown git commit: deadbeef'
}

@test "Git helpers fail clearly outside a repository" {
  local outside_path
  outside_path="$(_safe_git_test_root)/outside"
  mkdir -p "${outside_path}"

  run dybatpho::git_root "${outside_path}"
  assert_failure
  assert_output --partial 'Not a git repository'
}

@test "_create_git_repo refuses paths outside the BATS tempdir" {
  run _create_git_repo "${DYBATPHO_DIR}/unsafe-repo" main
  assert_failure
  assert_output --partial 'Refusing to touch'
}
