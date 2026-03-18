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
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

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
    git -C "${repo_path}" update-ref refs/tags/v1.0.0 "$(git -C "${repo_path}" rev-parse HEAD)"
    printf 'feature\n' >> "${repo_path}/README.md"
    git -C "${repo_path}" add README.md
    GIT_AUTHOR_NAME="release-bot" \
      GIT_AUTHOR_EMAIL="release@example.com" \
      GIT_COMMITTER_NAME="release-bot" \
      GIT_COMMITTER_EMAIL="release@example.com" \
      git -C "${repo_path}" commit -qm 'Add feature'
    git -C "${repo_path}" remote add origin https://example.com/dybatpho.git
    git -C "${repo_path}" update-ref refs/remotes/origin/main "$(git -C "${repo_path}" rev-parse HEAD)"
    git -C "${repo_path}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  )
}

function _main {
  local workspace repo_path
  dybatpho::create_temp workspace "/"
  repo_path="${workspace}/demo-repo"
  _prepare_demo_repo "${repo_path}"

  dybatpho::header "GIT HELPERS"
  dybatpho::info "Repo root:         $(dybatpho::git_root "${repo_path}")"
  dybatpho::info "Branch:            $(dybatpho::git_branch "${repo_path}")"
  dybatpho::info "Default branch:    $(dybatpho::git_default_branch "${repo_path}")"
  dybatpho::info "HEAD full SHA:     $(dybatpho::git_commit_hash "${repo_path}")"
  dybatpho::info "HEAD short SHA:    $(dybatpho::git_commit_short_hash "${repo_path}")"
  dybatpho::info "HEAD subject:      $(dybatpho::git_commit_subject "${repo_path}")"
  dybatpho::info "HEAD author:       $(dybatpho::git_commit_author "${repo_path}")"
  dybatpho::info "Has HEAD commit?   $(dybatpho::git_has_commit "${repo_path}" HEAD && echo yes || echo no)"
  dybatpho::info "Has deadbeef?      $(dybatpho::git_has_commit "${repo_path}" deadbeef && echo yes || echo no)"
  dybatpho::info "Remote origin:     $(dybatpho::git_remote_url origin "${repo_path}")"
  dybatpho::info "Has upstream?      $(dybatpho::git_has_remote upstream "${repo_path}" && echo yes || echo no)"
  dybatpho::info "Commits since v1.0.0:"
  dybatpho::git_commits_between "${repo_path}" v1.0.0 HEAD | while IFS= read -r sha; do
    dybatpho::print "  ${sha}  $(dybatpho::git_commit_subject "${repo_path}" "${sha}")"
  done
  dybatpho::info "Commit count since v1.0.0: $(dybatpho::git_commit_count "${repo_path}" v1.0.0 HEAD)"
  dybatpho::info "Tags for v1.0.0 commit:"
  dybatpho::git_tags_containing "${repo_path}" v1.0.0 | while IFS= read -r tag; do
    dybatpho::print "  ${tag}"
  done
  dybatpho::info "Clean worktree?    $(dybatpho::git_is_clean "${repo_path}" && echo yes || echo no)"
  printf 'dirty\n' >> "${repo_path}/README.md"
  printf 'notes\n' > "${repo_path}/notes.txt"
  dybatpho::info "Changed files:"
  dybatpho::git_changed_files "${repo_path}" | while IFS= read -r f; do
    dybatpho::print "  ${f}"
  done
  dybatpho::info "Clean after edit?  $(dybatpho::git_is_clean "${repo_path}" && echo yes || echo no)"
  dybatpho::success "Git operations demo complete"
}

_main "$@"
