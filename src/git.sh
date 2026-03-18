#!/usr/bin/env bash
# @file git.sh
# @brief Utilities for Git repositories
# @description
#   Helpers for common Git metadata and history lookups: locating the
#   repository root, reading the current branch, resolving the default branch,
#   inspecting commits, checking whether the worktree is clean, reading remote
#   information, listing changed files, and querying commit/tag relationships.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Ensure a path is inside a Git worktree.
# @arg $1 string Optional repository path, default is `.`
# @stdout The validated repository path
#######################################
function __dybatpho_git_repo_path {
  local repo_path="${1:-.}"
  dybatpho::require git
  git -C "${repo_path}" rev-parse --is-inside-work-tree > /dev/null 2>&1 \
    || dybatpho::die "Not a git repository: ${repo_path}"
  printf '%s\n' "${repo_path}"
}

#######################################
# @description Resolve a commit-ish to a full SHA.
# @arg $1 string Repository path
# @arg $2 string Commit-ish to resolve
# @stdout Full commit SHA
#######################################
function __dybatpho_git_resolve_commit {
  local repo_path commitish
  dybatpho::expect_args repo_path commitish -- "$@"
  git -C "${repo_path}" rev-parse --verify --quiet "${commitish}^{commit}" 2> /dev/null \
    || dybatpho::die "Unknown git commit: ${commitish}"
}

#######################################
# @description Return the top-level directory of a Git repository.
# @arg $1 string Optional repository path, default is `.`
# @stdout Absolute path to the repository root
#######################################
function dybatpho::git_root {
  local repo_path
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  git -C "${repo_path}" rev-parse --show-toplevel
}

#######################################
# @description Return the current branch name, or a short SHA in detached HEAD state.
# @arg $1 string Optional repository path, default is `.`
# @stdout Current branch name or short SHA
#######################################
function dybatpho::git_branch {
  local repo_path branch_name
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  branch_name="$(git -C "${repo_path}" symbolic-ref --quiet --short HEAD 2> /dev/null || true)"
  if [[ -n "${branch_name}" ]]; then
    printf '%s\n' "${branch_name}"
  else
    git -C "${repo_path}" rev-parse --short HEAD
  fi
}

#######################################
# @description Return the default branch of a Git repository.
# @arg $1 string Optional repository path, default is `.`
# @stdout Default branch name
# @tip Prefers `origin/HEAD`, then local `main`/`master`, then current branch
#######################################
function dybatpho::git_default_branch {
  local repo_path remote_head
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  remote_head="$(git -C "${repo_path}" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null || true)"
  if [[ -n "${remote_head}" ]]; then
    printf '%s\n' "${remote_head#origin/}"
    return 0
  fi
  if git -C "${repo_path}" show-ref --verify --quiet refs/heads/main; then
    printf 'main\n'; return 0
  fi
  if git -C "${repo_path}" show-ref --verify --quiet refs/heads/master; then
    printf 'master\n'; return 0
  fi
  local configured_default
  configured_default="$(git -C "${repo_path}" config --get init.defaultBranch 2> /dev/null || true)"
  if [[ -n "${configured_default}" ]]; then
    printf '%s\n' "${configured_default}"; return 0
  fi
  dybatpho::git_branch "${repo_path}"
}

#######################################
# @description Return the full SHA of a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Full commit SHA
#######################################
function dybatpho::git_commit_hash {
  local repo_path
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  __dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}"
}

#######################################
# @description Return the short SHA of a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Short commit SHA (7 chars)
#######################################
function dybatpho::git_commit_short_hash {
  local repo_path resolved
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  git -C "${repo_path}" rev-parse --short=7 "${resolved}"
}

#######################################
# @description Return the subject line of a commit message.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Commit subject line
#######################################
function dybatpho::git_commit_subject {
  local repo_path resolved
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  git -C "${repo_path}" log -1 --format=%s "${resolved}"
}

#######################################
# @description Return the author name of a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Commit author name
#######################################
function dybatpho::git_commit_author {
  local repo_path resolved
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  git -C "${repo_path}" log -1 --format=%aN "${resolved}"
}

#######################################
# @description Return success when a commit exists.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Commit-ish to verify, default is `HEAD`
# @exitcode 0 Commit exists
# @exitcode 1 Commit does not exist
#######################################
function dybatpho::git_has_commit {
  local repo_path
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  git -C "${repo_path}" rev-parse --verify --quiet "${2:-HEAD}^{commit}" > /dev/null 2>&1
}

#######################################
# @description List commits reachable from a head ref but not from a base ref.
# @arg $1 string Repository path
# @arg $2 string Base ref (excluded)
# @arg $3 string Optional head ref, default is `HEAD`
# @stdout One full SHA per line, oldest first
#######################################
function dybatpho::git_commits_between {
  local repo_path base_ref
  dybatpho::expect_args repo_path base_ref -- "$@"
  local head_ref="${3:-HEAD}"
  repo_path="$(__dybatpho_git_repo_path "${repo_path}")" || return $?
  __dybatpho_git_resolve_commit "${repo_path}" "${base_ref}" > /dev/null
  __dybatpho_git_resolve_commit "${repo_path}" "${head_ref}" > /dev/null
  git -C "${repo_path}" rev-list --reverse "${base_ref}..${head_ref}"
}

#######################################
# @description Count commits in a range.
# @arg $1 string Repository path
# @arg $2 string Base ref (excluded)
# @arg $3 string Optional head ref, default is `HEAD`
# @stdout Number of commits
#######################################
function dybatpho::git_commit_count {
  local repo_path base_ref
  dybatpho::expect_args repo_path base_ref -- "$@"
  local head_ref="${3:-HEAD}"
  repo_path="$(__dybatpho_git_repo_path "${repo_path}")" || return $?
  __dybatpho_git_resolve_commit "${repo_path}" "${base_ref}" > /dev/null
  __dybatpho_git_resolve_commit "${repo_path}" "${head_ref}" > /dev/null
  git -C "${repo_path}" rev-list --count "${base_ref}..${head_ref}"
}

#######################################
# @description Return success when the worktree has no tracked or untracked changes.
# @arg $1 string Optional repository path, default is `.`
# @exitcode 0 Worktree is clean
# @exitcode 1 Worktree has changes
#######################################
function dybatpho::git_is_clean {
  local repo_path status_output
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  status_output="$(git -C "${repo_path}" status --porcelain --untracked-files=normal)"
  [[ -z "${status_output}" ]]
}

#######################################
# @description Return the URL for a Git remote.
# @arg $1 string Optional remote name, default is `origin`
# @arg $2 string Optional repository path, default is `.`
# @stdout Remote URL
#######################################
function dybatpho::git_remote_url {
  local remote_name="${1:-origin}"
  local repo_path
  repo_path="$(__dybatpho_git_repo_path "${2:-.}")" || return $?
  git -C "${repo_path}" remote get-url "${remote_name}"
}

#######################################
# @description Return success when a named remote exists.
# @arg $1 string Optional remote name, default is `origin`
# @arg $2 string Optional repository path, default is `.`
# @exitcode 0 Remote exists
# @exitcode 1 Remote does not exist
#######################################
function dybatpho::git_has_remote {
  local remote_name="${1:-origin}"
  local repo_path
  repo_path="$(__dybatpho_git_repo_path "${2:-.}")" || return $?
  git -C "${repo_path}" remote get-url "${remote_name}" > /dev/null 2>&1
}

#######################################
# @description List changed files relative to a base ref, including untracked.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional base ref, default is `HEAD`
# @stdout One changed file path per line, sorted and deduplicated
#######################################
function dybatpho::git_changed_files {
  local repo_path base_ref
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  base_ref="${2:-HEAD}"
  {
    git -C "${repo_path}" diff --name-only "${base_ref}" --
    git -C "${repo_path}" ls-files --others --exclude-standard
  } | awk 'NF' | sort -u
}

#######################################
# @description List tags that contain a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout One tag per line, sorted
#######################################
function dybatpho::git_tags_containing {
  local repo_path resolved
  repo_path="$(__dybatpho_git_repo_path "${1:-.}")" || return $?
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  git -C "${repo_path}" tag --contains "${resolved}" | sort
}
