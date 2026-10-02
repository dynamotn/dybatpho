setup() {
  load test_helper
}

# ---------------------------------------------------------------------------
# Safety guards – prevent tests from touching the real dybatpho repository
# ---------------------------------------------------------------------------

function _safe_git_test_root {
  [[ -n "${BATS_TEST_TMPDIR:-}" ]] || {
    printf '%s\n' "BATS_TEST_TMPDIR is not set" >&2
    return 1
  }
  [[ -d "${BATS_TEST_TMPDIR}" ]] || {
    printf '%s\n' "BATS_TEST_TMPDIR does not exist: ${BATS_TEST_TMPDIR}" >&2
    return 1
  }
  # Git reports the physical path, and on macOS the temporary directory sits
  # behind the `/var` -> `/private/var` link, so hand out the resolved form.
  (cd "${BATS_TEST_TMPDIR}" && pwd -P)
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
  [[ -n "${repo_path}" ]] || {
    printf '%s\n' "Refusing to use an empty repository path" >&2
    return 1
  }
  [[ "${repo_path}" == "${test_root}"/* ]] || {
    printf '%s\n' "Refusing to touch non-test path: ${repo_path}" >&2
    return 1
  }
  [[ "${repo_path}" != "${DYBATPHO_DIR}" ]] || {
    printf '%s\n' "Refusing to touch the real dybatpho repository" >&2
    return 1
  }
  [[ "${repo_path}" != "${DYBATPHO_DIR}"/* ]] || {
    printf '%s\n' "Refusing to touch paths inside the real dybatpho repository" >&2
    return 1
  }
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
    # Same reason as in test/release.bats: a globally configured hooks path
    # must not reach the repositories these tests create.
    git -C "${repo_path}" config core.hooksPath /dev/null
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

  assert_equal "$(dybatpho::git_root "${repo_path}/nested/path")" "${repo_path}"
}

@test "dybatpho::git_branch returns the current branch name" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" checkout -qb feature/test
  )

  assert_equal "$(dybatpho::git_branch "${repo_path}")" 'feature/test'
}

@test "dybatpho::git_branch falls back to a short SHA in detached HEAD state" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  local short_sha
  short_sha="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse --short HEAD
  )"
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" checkout -q --detach
  )

  assert_equal "$(dybatpho::git_branch "${repo_path}")" "${short_sha}"
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

  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'main'
}

@test "dybatpho::git_default_branch falls back to local master when origin HEAD is absent" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" master

  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'master'
}

@test "dybatpho::git_commit_hash and dybatpho::git_commit_short_hash resolve commit SHAs" {
  local repo_path commit_sha short_sha
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  commit_sha="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse HEAD
  )"
  short_sha="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse --short=7 HEAD
  )"

  assert_equal "$(dybatpho::git_commit_hash "${repo_path}")" "${commit_sha}"

  assert_equal "$(dybatpho::git_commit_short_hash "${repo_path}")" "${short_sha}"
}

@test "dybatpho::git_commit_subject and dybatpho::git_commit_author inspect commit metadata" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _append_git_commit "${repo_path}" "Add feature" "release-bot" "release@example.com"

  assert_equal "$(dybatpho::git_commit_subject "${repo_path}")" 'Add feature'

  assert_equal "$(dybatpho::git_commit_author "${repo_path}")" 'release-bot'
}

@test "dybatpho::git_has_commit checks whether a commit exists" {
  local repo_path commit_sha
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  commit_sha="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse HEAD
  )"

  dybatpho::git_has_commit "${repo_path}" "${commit_sha}"

  run_traced dybatpho::git_has_commit "${repo_path}" deadbeef
  assert_failure
}

@test "dybatpho::git_commits_between and dybatpho::git_commit_count inspect commit ranges" {
  local repo_path second_commit third_commit
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" update-ref refs/tags/v1.0.0 "$(git -C "${repo_path}" rev-parse HEAD)"
  )
  _append_git_commit "${repo_path}" "Add feature"
  second_commit="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse HEAD
  )"
  _append_git_commit "${repo_path}" "Ship release"
  third_commit="$(
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" rev-parse HEAD
  )"

  assert_equal "$(dybatpho::git_commits_between "${repo_path}" v1.0.0 HEAD)" "${second_commit}"$'\n'"${third_commit}"

  assert_equal "$(dybatpho::git_commit_count "${repo_path}" v1.0.0 HEAD)" '2'
}

@test "dybatpho::git_is_clean reflects repository changes" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  dybatpho::git_is_clean "${repo_path}"

  printf 'dirty\n' >> "${repo_path}/README.md"
  run_traced dybatpho::git_is_clean "${repo_path}"
  assert_failure
}

@test "dybatpho::git_remote_url returns the configured remote URL" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" remote add origin https://example.com/repo.git
  )

  assert_equal "$(dybatpho::git_remote_url origin "${repo_path}")" 'https://example.com/repo.git'
}

@test "dybatpho::git_has_remote checks whether a remote exists" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" remote add origin https://example.com/repo.git
  )

  dybatpho::git_has_remote origin "${repo_path}"

  run_traced dybatpho::git_has_remote upstream "${repo_path}"
  assert_failure
}

@test "dybatpho::git_changed_files lists tracked and untracked changes" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  printf 'dirty\n' >> "${repo_path}/README.md"
  printf 'new\n' > "${repo_path}/notes.txt"

  assert_equal "$(dybatpho::git_changed_files "${repo_path}")" $'README.md\nnotes.txt'
}

@test "dybatpho::git_tags_containing lists tags containing a commit" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" update-ref refs/tags/v1.0.0 "$(git -C "${repo_path}" rev-parse HEAD)"
  )

  assert_equal "$(dybatpho::git_tags_containing "${repo_path}")" 'v1.0.0'
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

@test "dybatpho::git_default_branch uses local main before configured defaults" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" config init.defaultBranch configured
  )

  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'main'
}

@test "dybatpho::git_default_branch uses configured and current branch fallbacks" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" develop
  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" config init.defaultBranch configured
  )

  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'configured'

  (
    unset GIT_DIR GIT_WORK_TREE
    git -C "${repo_path}" config --local init.defaultBranch ""
  )
  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'develop'
}

@test "Git range helpers reject unknown base and head commits" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_commits_between "${repo_path}" missing-base
  assert_failure
  assert_output --partial "Unknown git commit: missing-base"

  run dybatpho::git_commit_count "${repo_path}" HEAD missing-head
  assert_failure
  assert_output --partial "Unknown git commit: missing-head"
}

@test "dybatpho::git_remote_url and git_tags_containing report missing refs" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_remote_url upstream "${repo_path}"
  assert_failure

  run dybatpho::git_tags_containing "${repo_path}" missing-commit
  assert_failure
  assert_output --partial "Unknown git commit: missing-commit"
}

@test "Git helpers ignore Git env vars injected by hooks" {
  local repo_path hook_repo
  repo_path="$(_new_git_repo_path)"
  hook_repo="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _create_git_repo "${hook_repo}" master
  _append_git_commit "${repo_path}" 'Second commit'

  # Mimic the environment a `pre-commit` hook runs in: git exports GIT_DIR and
  # GIT_INDEX_FILE, which would otherwise win over `git -C <repo_path>`.
  export GIT_DIR="${hook_repo}/.git"
  export GIT_INDEX_FILE="${hook_repo}/.git/index"
  export GIT_WORK_TREE="${hook_repo}"

  assert_equal "$(dybatpho::git_root "${repo_path}")" "${repo_path}"
  assert_equal "$(dybatpho::git_branch "${repo_path}")" 'main'
  assert_equal "$(dybatpho::git_default_branch "${repo_path}")" 'main'
  assert_equal "$(dybatpho::git_commit_subject "${repo_path}")" 'Second commit'
  assert_equal "$(dybatpho::git_commit_count "${repo_path}" 'HEAD~1')" '1'
  dybatpho::git_is_clean "${repo_path}"

  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
}

@test "dybatpho::git_latest_tag orders tags by version, not as strings" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  for version in v1.0.0 v2.0.0 v9.0.0 v10.0.0; do
    _append_git_commit "${repo_path}" "towards ${version}"
    git -C "${repo_path}" tag "${version}"
  done
  # A string sort would put v9.0.0 on top; a version sort puts v10.0.0 there.
  assert_equal "$(dybatpho::git_latest_tag "${repo_path}")" "v10.0.0"
}

@test "dybatpho::git_latest_tag honors a tag pattern" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" tag v1.0.0
  _append_git_commit "${repo_path}" "nightly"
  git -C "${repo_path}" tag nightly-2026-01-01
  assert_equal "$(dybatpho::git_latest_tag "${repo_path}" 'v*')" "v1.0.0"
  assert_equal "$(dybatpho::git_latest_tag "${repo_path}" 'nightly-*')" "nightly-2026-01-01"
}

@test "dybatpho::git_latest_tag reports failure when no tag matches" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  run_traced -1 dybatpho::git_latest_tag "${repo_path}"
  assert_output ""
  git -C "${repo_path}" tag v1.0.0
  run_traced -1 dybatpho::git_latest_tag "${repo_path}" 'release-*'
  assert_output ""
}

@test "dybatpho::git_is_ancestor answers whether a commit has landed" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  local first
  first="$(dybatpho::git_commit_hash "${repo_path}")"
  _append_git_commit "${repo_path}" "second"
  local second
  second="$(dybatpho::git_commit_hash "${repo_path}")"

  dybatpho::git_is_ancestor "${repo_path}" "${first}" "${second}"
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" "${second}" "${first}"
}

@test "dybatpho::git_is_ancestor counts a commit as its own ancestor" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  # This is what makes "has this landed yet" answer yes for the commit itself.
  dybatpho::git_is_ancestor "${repo_path}" HEAD HEAD
}

@test "dybatpho::git_is_ancestor works with tags and branch names" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" tag v1.0.0
  _append_git_commit "${repo_path}" "after the tag"
  dybatpho::git_is_ancestor "${repo_path}" v1.0.0 HEAD
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" HEAD v1.0.0
}

@test "dybatpho::git_is_ancestor separates unrelated branches" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" checkout -q -b side
  _append_git_commit "${repo_path}" "only on side"
  local side
  side="$(dybatpho::git_commit_hash "${repo_path}")"
  git -C "${repo_path}" checkout -q main
  _append_git_commit "${repo_path}" "only on main"

  # Neither branch tip reaches the other once they have diverged.
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" "${side}" HEAD
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" HEAD "${side}"
}

@test "dybatpho::git_is_ancestor reports an unresolvable commit" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" "no-such-ref" HEAD
  run_traced ! dybatpho::git_is_ancestor "${repo_path}" HEAD "no-such-ref"
}

# Give a test repository a bare remote it tracks, so upstream questions have
# an answer that never touches the network.
function _track_git_remote {
  local repo_path
  dybatpho::expect_args repo_path -- "$@"
  _require_safe_git_test_path "${repo_path}" || return $?
  local remote_path="${repo_path}.remote.git"
  _require_safe_git_test_path "${remote_path}" || return $?
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
    git init -q --bare "${remote_path}"
    git -C "${repo_path}" remote add origin "${remote_path}"
    git -C "${repo_path}" push -q -u origin main
  )
}

@test "dybatpho::git_upstream names the tracked branch" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _track_git_remote "${repo_path}"

  run_traced dybatpho::git_upstream "${repo_path}"
  assert_success
  assert_output "origin/main"
  run_traced dybatpho::git_upstream "${repo_path}" main
  assert_output "origin/main"
}

@test "dybatpho::git_upstream fails without an upstream or a branch" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run_traced -1 dybatpho::git_upstream "${repo_path}"
  assert_output ""
  run_traced -1 dybatpho::git_upstream "${repo_path}" no-such-branch
  git -C "${repo_path}" checkout -q --detach
  run_traced -1 dybatpho::git_upstream "${repo_path}"
}

@test "dybatpho::git_ahead_behind compares with the upstream by default" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _track_git_remote "${repo_path}"

  run_traced dybatpho::git_ahead_behind "${repo_path}"
  assert_output "0 0"
  _append_git_commit "${repo_path}" "local one"
  _append_git_commit "${repo_path}" "local two"
  run_traced dybatpho::git_ahead_behind "${repo_path}"
  assert_output "2 0"
  run_traced dybatpho::git_ahead_behind "${repo_path}" "" main
  assert_output "2 0"
}

@test "dybatpho::git_ahead_behind counts both sides of diverged refs" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" checkout -q -b side
  _append_git_commit "${repo_path}" "only on side"
  git -C "${repo_path}" checkout -q main
  _append_git_commit "${repo_path}" "main one"
  _append_git_commit "${repo_path}" "main two"

  run_traced dybatpho::git_ahead_behind "${repo_path}" side
  assert_output "2 1"
  run_traced dybatpho::git_ahead_behind "${repo_path}" main side
  assert_output "1 2"
}

@test "dybatpho::git_ahead_behind reports a missing upstream or ref" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run dybatpho::git_ahead_behind "${repo_path}"
  assert_failure
  assert_output --partial "No upstream configured for HEAD"
  run dybatpho::git_ahead_behind "${repo_path}" no-such-ref
  assert_failure
  assert_output --partial "Unknown git commit: no-such-ref"
}

@test "dybatpho::git_state reports none for a quiet repository" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "none"
}

@test "dybatpho::git_state reports a conflicted merge, cherry-pick and revert" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" checkout -q -b side
  _append_git_commit "${repo_path}" "side change"
  git -C "${repo_path}" checkout -q main
  _append_git_commit "${repo_path}" "main change"

  run_traced -1 git -C "${repo_path}" merge -q side
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "merge"
  git -C "${repo_path}" merge --abort

  run_traced -1 git -C "${repo_path}" cherry-pick side
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "cherry-pick"
  git -C "${repo_path}" cherry-pick --abort

  run_traced -1 git -C "${repo_path}" revert --no-edit HEAD~1
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "revert"
  git -C "${repo_path}" revert --abort
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "none"
}

@test "dybatpho::git_state reports rebase, am and bisect" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" checkout -q -b side
  _append_git_commit "${repo_path}" "side change"
  git -C "${repo_path}" checkout -q main
  _append_git_commit "${repo_path}" "main change"

  git -C "${repo_path}" checkout -q side
  run_traced -1 git -C "${repo_path}" rebase -q main
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "rebase"
  git -C "${repo_path}" rebase --abort

  git -C "${repo_path}" format-patch -q -1 -o "${repo_path}.patches" side
  git -C "${repo_path}" checkout -q main
  run_traced ! git -C "${repo_path}" am -q "${repo_path}.patches"/*.patch
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "am"
  git -C "${repo_path}" am --abort

  # A rebase stopped by the apply backend keeps `rebase-apply` without `applying`.
  mkdir "$(git -C "${repo_path}" rev-parse --absolute-git-dir)/rebase-apply"
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "rebase"
  rmdir "$(git -C "${repo_path}" rev-parse --absolute-git-dir)/rebase-apply"

  git -C "${repo_path}" bisect start > /dev/null
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "bisect"
  git -C "${repo_path}" bisect reset > /dev/null
}

@test "dybatpho::git_state reads a linked worktree's own markers" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  local worktree_path="${repo_path}.linked tree"
  git -C "${repo_path}" worktree add -q "${worktree_path}" -b linked

  git -C "${worktree_path}" bisect start > /dev/null
  run_traced dybatpho::git_state "${worktree_path}"
  assert_output "bisect"
  run_traced dybatpho::git_state "${repo_path}"
  assert_output "none"
}

@test "dybatpho::git_state answers from a subdirectory" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  mkdir -p "${repo_path}/sub dir"
  git -C "${repo_path}" bisect start > /dev/null
  run_traced dybatpho::git_state "${repo_path}/sub dir"
  assert_output "bisect"
}

@test "dybatpho::git_is_shallow tells a shallow clone from a full one" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  _append_git_commit "${repo_path}" "second"
  run_traced ! dybatpho::git_is_shallow "${repo_path}"

  local clone_path="${repo_path}.shallow"
  git clone -q --depth 1 "file://${repo_path}" "${clone_path}"
  run_traced dybatpho::git_is_shallow "${clone_path}"
}

@test "dybatpho::git_stash_count counts stash entries" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main

  run_traced dybatpho::git_stash_count "${repo_path}"
  assert_output "0"
  printf 'one\n' >> "${repo_path}/README.md"
  git -C "${repo_path}" stash -q
  printf 'two\n' >> "${repo_path}/README.md"
  git -C "${repo_path}" stash -q
  run_traced dybatpho::git_stash_count "${repo_path}"
  assert_output "2"
}

@test "dybatpho::git_worktree_list lists every worktree with its branch" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  git -C "${repo_path}" worktree add -q "${repo_path}.with space" -b feature
  git -C "${repo_path}" worktree add -q --detach "${repo_path}.detached"

  run_traced dybatpho::git_worktree_list "${repo_path}"
  assert_success
  assert_line --index 0 "${repo_path}"$'\t'"main"
  assert_line "${repo_path}.with space"$'\t'"feature"
  assert_line "${repo_path}.detached"$'\t'"(detached)"
  assert_equal "${#lines[@]}" 3
}

@test "dybatpho::git_worktree_list marks a bare repository" {
  local repo_path
  repo_path="$(_new_git_repo_path)"
  _create_git_repo "${repo_path}" main
  local bare_path="${repo_path}.bare.git"
  git clone -q --bare "${repo_path}" "${bare_path}"
  git -C "${bare_path}" worktree add -q "${repo_path}.from-bare" main

  run_traced dybatpho::git_worktree_list "${repo_path}.from-bare"
  assert_line --index 0 "${bare_path}"$'\t'"(bare)"
  assert_line --index 1 "${repo_path}.from-bare"$'\t'"main"
}

@test "New Git state helpers fail clearly outside a repository" {
  local outside_path
  outside_path="$(_safe_git_test_root)/outside"
  mkdir -p "${outside_path}"
  local helper
  for helper in git_upstream git_ahead_behind git_state git_is_shallow \
    git_stash_count git_worktree_list; do
    run "dybatpho::${helper}" "${outside_path}"
    assert_failure
    assert_output --partial 'Not a git repository'
  done
}
