#!/usr/bin/env bash
# @file git_ops.sh
# @brief Example showing Git utilities
# @description Demonstrates dybatpho::git_root, git_branch, git_default_branch,
#              git_commit_hash/short_hash/subject/author, git_is_clean,
#              git_remote_url, git_has_remote, git_changed_files,
#              git_has_commit, git_commits_between, git_commit_count,
#              and git_tags_containing
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules git

dybatpho::register_common_handlers

# @description Build a throwaway repository with the tags and commits the demo reads.
# @arg $1 string repo path
function _prepare_demo_repo {
  local repo_path
  dybatpho::expect_args repo_path -- "$@"
  (
    unset GIT_DIR GIT_WORK_TREE
    git init -q -b main "${repo_path}"
    git -C "${repo_path}" config user.name "dybatpho"
    git -C "${repo_path}" config user.email "dybatpho@example.com"
    git -C "${repo_path}" config commit.gpgsign false
    git -C "${repo_path}" config tag.gpgsign false
    git -C "${repo_path}" config gc.auto 0
    printf 'hello git\n' > "${repo_path}/README.md"
    git -C "${repo_path}" add README.md
    git -C "${repo_path}" commit -qm 'Initial commit'
    local git_2
    git_2=$(git -C "${repo_path}" rev-parse HEAD)
    git -C "${repo_path}" update-ref refs/tags/v1.0.0 "${git_2}"
    printf 'feature\n' >> "${repo_path}/README.md"
    git -C "${repo_path}" add README.md
    GIT_AUTHOR_NAME="release-bot" \
      GIT_AUTHOR_EMAIL="release@example.com" \
      GIT_COMMITTER_NAME="release-bot" \
      GIT_COMMITTER_EMAIL="release@example.com" \
      git -C "${repo_path}" commit -qm 'Add feature'
    git -C "${repo_path}" remote add origin https://example.com/dybatpho.git
    local git
    git=$(git -C "${repo_path}" rev-parse HEAD)
    git -C "${repo_path}" update-ref refs/remotes/origin/main "${git}"
    git -C "${repo_path}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  )
}

# @description Run the `GIT HELPERS` section of this example.
# @noargs
function _main {
  local workspace repo_path
  dybatpho::create_temp workspace "/"
  repo_path="${workspace}/demo-repo"
  _prepare_demo_repo "${repo_path}"

  dybatpho::header "GIT HELPERS"
  local git_root
  git_root=$(dybatpho::git_root "${repo_path}")
  dybatpho::info "Repo root:         ${git_root}"
  local git_branch
  git_branch=$(dybatpho::git_branch "${repo_path}")
  dybatpho::info "Branch:            ${git_branch}"
  local git_default_branch
  git_default_branch=$(dybatpho::git_default_branch "${repo_path}")
  dybatpho::info "Default branch:    ${git_default_branch}"
  local git_commit_hash
  git_commit_hash=$(dybatpho::git_commit_hash "${repo_path}")
  dybatpho::info "HEAD full SHA:     ${git_commit_hash}"
  local git_commit_short_hash
  git_commit_short_hash=$(dybatpho::git_commit_short_hash "${repo_path}")
  dybatpho::info "HEAD short SHA:    ${git_commit_short_hash}"
  local git_commit_subject_2
  git_commit_subject_2=$(dybatpho::git_commit_subject "${repo_path}")
  dybatpho::info "HEAD subject:      ${git_commit_subject_2}"
  local git_commit_author
  git_commit_author=$(dybatpho::git_commit_author "${repo_path}")
  dybatpho::info "HEAD author:       ${git_commit_author}"
  local git_has_commit_2
  git_has_commit_2=$(dybatpho::git_has_commit "${repo_path}" HEAD && echo yes || echo no)
  dybatpho::info "Has HEAD commit?   ${git_has_commit_2}"
  local git_has_commit
  git_has_commit=$(dybatpho::git_has_commit "${repo_path}" deadbeef && echo yes || echo no)
  dybatpho::info "Has deadbeef?      ${git_has_commit}"
  local git_remote_url
  git_remote_url=$(dybatpho::git_remote_url origin "${repo_path}")
  dybatpho::info "Remote origin:     ${git_remote_url}"
  local git_has_remote
  git_has_remote=$(dybatpho::git_has_remote upstream "${repo_path}" && echo yes || echo no)
  dybatpho::info "Has upstream?      ${git_has_remote}"
  dybatpho::info "Commits since v1.0.0:"
  local git_commits_between_output
  git_commits_between_output=$(dybatpho::git_commits_between "${repo_path}" v1.0.0 HEAD)
  while IFS= read -r sha || [[ -n "${sha}" ]]; do
    local git_commit_subject
    git_commit_subject=$(dybatpho::git_commit_subject "${repo_path}" "${sha}")
    dybatpho::print "  ${sha}  ${git_commit_subject}"
  done < <(printf '%s' "${git_commits_between_output}")
  local git_commit_count
  git_commit_count=$(dybatpho::git_commit_count "${repo_path}" v1.0.0 HEAD)
  dybatpho::info "Commit count since v1.0.0: ${git_commit_count}"
  dybatpho::info "Tags for v1.0.0 commit:"
  local git_tags_containing_output
  git_tags_containing_output=$(dybatpho::git_tags_containing "${repo_path}" v1.0.0)
  while IFS= read -r tag || [[ -n "${tag}" ]]; do
    dybatpho::print "  ${tag}"
  done < <(printf '%s' "${git_tags_containing_output}")
  local git_is_clean_2
  git_is_clean_2=$(dybatpho::git_is_clean "${repo_path}" && echo yes || echo no)
  dybatpho::info "Clean worktree?    ${git_is_clean_2}"
  printf 'dirty\n' >> "${repo_path}/README.md"
  printf 'notes\n' > "${repo_path}/notes.txt"
  dybatpho::info "Changed files:"
  local git_changed_files_output
  git_changed_files_output=$(dybatpho::git_changed_files "${repo_path}")
  while IFS= read -r f || [[ -n "${f}" ]]; do
    dybatpho::print "  ${f}"
  done < <(printf '%s' "${git_changed_files_output}")
  local git_is_clean
  git_is_clean=$(dybatpho::git_is_clean "${repo_path}" && echo yes || echo no)
  dybatpho::info "Clean after edit?  ${git_is_clean}"
  dybatpho::success "Git operations demo complete"
}

_main "$@"
