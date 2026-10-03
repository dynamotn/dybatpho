# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file git.sh
# @brief Utilities for Git repositories
# @namespace dybatpho
# @description
#   Helpers for common Git metadata and history lookups: locating the
#   repository root, reading the current branch, resolving the default branch,
#   inspecting commits, checking whether the worktree is clean, reading remote
#   information, listing changed files, and querying commit/tag relationships.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Run `git` in a repository, ignoring ambient Git environment variables.
# @arg $1 string Repository path
# @arg $@ any Arguments passed to `git`
# @stdout Output of the `git` command
# @tip Git hooks (e.g. `pre-commit`) export `GIT_DIR`/`GIT_INDEX_FILE`, which
#   otherwise override `git -C` and point every call at the hook's repository
# @internal
#######################################
function __dybatpho_git {
  local repo_path
  dybatpho::expect_args repo_path -- "$@"
  shift
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX \
      GIT_CEILING_DIRECTORIES
    git -C "${repo_path}" "$@"
  )
}

#######################################
# @description Stop the script unless a path is inside a Git worktree.
#   It runs in the caller's shell: checked inside `$(...)`, the refusal ended
#   only the subshell, and a predicate such as `dybatpho::git_is_clean` read a
#   path that is not a repository as a plain "no".
# @arg $1 string Repository path
# @exitcode 0 The path is inside a worktree
# @exitcode 1 Stop the script when it is not
# @internal
#######################################
function __dybatpho_git_expect_repo {
  local repo_path
  dybatpho::expect_args repo_path -- "$@"
  dybatpho::require git
  __dybatpho_git "${repo_path}" rev-parse --is-inside-work-tree > /dev/null 2>&1 \
    || dybatpho::die "Not a git repository: ${repo_path}"
}

#######################################
# @description Resolve a commit-ish to a full SHA.
# @arg $1 string Repository path
# @arg $2 string Commit-ish to resolve
# @stdout Full commit SHA
# @internal
#######################################
function __dybatpho_git_resolve_commit {
  local repo_path commitish
  dybatpho::expect_args repo_path commitish -- "$@"
  __dybatpho_git "${repo_path}" rev-parse --verify --quiet "${commitish}^{commit}" 2> /dev/null \
    || dybatpho::die "Unknown git commit: ${commitish}"
}

#######################################
# @description Return the top-level directory of a Git repository.
# @arg $1 string Optional repository path, default is `.`
# @stdout Absolute path to the repository root
#######################################
function dybatpho::git_root {
  local repo_path
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git "${repo_path}" rev-parse --show-toplevel
}

#######################################
# @description Return the current branch name, or a short SHA in detached HEAD state.
# @arg $1 string Optional repository path, default is `.`
# @stdout Current branch name or short SHA
#######################################
function dybatpho::git_branch {
  local repo_path branch_name
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  branch_name="$(__dybatpho_git "${repo_path}" symbolic-ref --quiet --short HEAD 2> /dev/null || true)"
  if [[ -n "${branch_name}" ]]; then
    printf '%s\n' "${branch_name}"
  else
    __dybatpho_git "${repo_path}" rev-parse --short HEAD
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
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  remote_head="$(__dybatpho_git "${repo_path}" symbolic-ref --quiet --short \
    refs/remotes/origin/HEAD 2> /dev/null || true)"
  if [[ -n "${remote_head}" ]]; then
    printf '%s\n' "${remote_head#origin/}"
    return 0
  fi
  if __dybatpho_git "${repo_path}" show-ref --verify --quiet refs/heads/main; then
    printf 'main\n'
    return 0
  fi
  if __dybatpho_git "${repo_path}" show-ref --verify --quiet refs/heads/master; then
    printf 'master\n'
    return 0
  fi
  local configured_default
  configured_default="$(__dybatpho_git "${repo_path}" config --get init.defaultBranch 2> /dev/null || true)"
  if [[ -n "${configured_default}" ]]; then
    printf '%s\n' "${configured_default}"
    return 0
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
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
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
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  __dybatpho_git "${repo_path}" rev-parse --short=7 "${resolved}"
}

#######################################
# @description Return the subject line of a commit message.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Commit subject line
#######################################
function dybatpho::git_commit_subject {
  local repo_path resolved
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  __dybatpho_git "${repo_path}" log -1 --format=%s "${resolved}"
}

#######################################
# @description Return the author name of a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout Commit author name
#######################################
function dybatpho::git_commit_author {
  local repo_path resolved
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  __dybatpho_git "${repo_path}" log -1 --format=%aN "${resolved}"
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
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git "${repo_path}" rev-parse --verify --quiet "${2:-HEAD}^{commit}" > /dev/null 2>&1
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
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git_resolve_commit "${repo_path}" "${base_ref}" > /dev/null
  __dybatpho_git_resolve_commit "${repo_path}" "${head_ref}" > /dev/null
  __dybatpho_git "${repo_path}" rev-list --reverse "${base_ref}..${head_ref}"
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
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git_resolve_commit "${repo_path}" "${base_ref}" > /dev/null
  __dybatpho_git_resolve_commit "${repo_path}" "${head_ref}" > /dev/null
  __dybatpho_git "${repo_path}" rev-list --count "${base_ref}..${head_ref}"
}

#######################################
# @description Return success when the worktree has no tracked or untracked changes.
# @arg $1 string Optional repository path, default is `.`
# @exitcode 0 Worktree is clean
# @exitcode 1 Worktree has changes
#######################################
function dybatpho::git_is_clean {
  local repo_path status_output
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  status_output="$(__dybatpho_git "${repo_path}" status --porcelain --untracked-files=normal)"
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
  repo_path="${2:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git "${repo_path}" remote get-url "${remote_name}"
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
  repo_path="${2:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  __dybatpho_git "${repo_path}" remote get-url "${remote_name}" > /dev/null 2>&1
}

#######################################
# @description List changed files relative to a base ref, including untracked.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional base ref, default is `HEAD`
# @stdout One changed file path per line, sorted byte-wise and deduplicated,
#   so the order does not depend on the caller's locale
#######################################
function dybatpho::git_changed_files {
  local repo_path base_ref
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  base_ref="${2:-HEAD}"
  {
    __dybatpho_git "${repo_path}" diff --name-only "${base_ref}" --
    __dybatpho_git "${repo_path}" ls-files --others --exclude-standard
  } | awk 'NF' | LC_ALL=C sort -u
}

#######################################
# @description Print the highest version tag in a repository.
#   Tags are ordered the way versions compare, not the way strings do, so `v10`
#   sorts above `v9` and the newest release is the first line.
# @example
#   if previous="$(dybatpho::git_latest_tag "." "v*")"; then
#     dybatpho::info "Releasing on top of ${previous}"
#   fi
#
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional tag glob to match, default is every tag
# @stdout The highest matching tag
# @exitcode 0 A matching tag exists
# @exitcode 1 The repository has no matching tag
#######################################
function dybatpho::git_latest_tag {
  local repo_path pattern tag
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  pattern="${2:-*}"
  local git
  local git_2
  local git_3
  local git_4
  local git_5
  local git_6
  local git_7
  local git_8
  local git_9
  local git_tags
  git_tags=$(__dybatpho_git "${repo_path}" tag --list "${pattern}" --sort=-v:refname)
  git_9=$(printf '%s\n' "${git_tags}" | head -n 1)
  git_8=${git_9}
  git_7=${git_8}
  git_6=${git_7}
  git_5=${git_6}
  git_4=${git_5}
  git_3=${git_4}
  git_2=${git_3}
  git=${git_2}
  tag="${git}"
  [[ -n "${tag}" ]] || return 1
  printf '%s\n' "${tag}"
}

#######################################
# @description List tags that contain a commit.
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional commit-ish, default is `HEAD`
# @stdout One tag per line, sorted
#######################################
function dybatpho::git_tags_containing {
  local repo_path resolved
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  resolved="$(__dybatpho_git_resolve_commit "${repo_path}" "${2:-HEAD}")" || return $?
  __dybatpho_git "${repo_path}" tag --contains "${resolved}" | sort
}

#######################################
# @description Return success when one commit is reachable from another.
#   A release script asks this before acting: whether a tag is on the branch it
#   is about to release, or whether a fix has already landed on the branch a
#   backport is aimed at.
# @example
#   if dybatpho::git_is_ancestor "." "v1.2.0" "HEAD"; then
#     dybatpho::info "v1.2.0 is already on this branch"
#   fi
#
# @arg $1 string Repository path
# @arg $2 string The commit-ish that may be the ancestor
# @arg $3 string The commit-ish that may descend from it
# @exitcode 0 The first commit is an ancestor of the second, or they are the same commit
# @exitcode 1 It is not, or either commit-ish cannot be resolved
# @tip A commit counts as its own ancestor, which is what `git merge-base` reports
#   and what makes "has this landed yet" answer yes for the commit itself
#######################################
function dybatpho::git_is_ancestor {
  local repo_path ancestor descendant resolved_ancestor resolved_descendant
  dybatpho::expect_args repo_path ancestor descendant -- "$@"
  __dybatpho_git_expect_repo "${repo_path}"
  resolved_ancestor="$(__dybatpho_git_resolve_commit "${repo_path}" "${ancestor}")" || return $?
  resolved_descendant="$(__dybatpho_git_resolve_commit "${repo_path}" "${descendant}")" || return $?
  __dybatpho_git "${repo_path}" merge-base --is-ancestor \
    "${resolved_ancestor}" "${resolved_descendant}"
}

#######################################
# @description Print the upstream a branch tracks.
#   A script asks this before it compares with, pulls from, or pushes to the
#   remote branch, and the answer is the short name Git shows, such as
#   `origin/main`.
# @example
#   if upstream="$(dybatpho::git_upstream "." main)"; then
#     dybatpho::info "main tracks ${upstream}"
#   fi
#
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional branch name, default is the current branch
# @stdout Short name of the upstream ref
# @exitcode 0 The branch has an upstream
# @exitcode 1 It has none, the branch does not exist, or HEAD is detached
#######################################
function dybatpho::git_upstream {
  local repo_path branch_name
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  branch_name="${2-}"
  __dybatpho_git "${repo_path}" rev-parse --abbrev-ref --symbolic-full-name \
    "${branch_name}@{upstream}" 2> /dev/null || return 1
}

#######################################
# @description Count the commits a ref is ahead of and behind another.
#   With no base the branch is compared with its upstream, which is the
#   "2 ahead, 1 behind" a prompt or a pre-push check wants.
# @example
#   local counts ahead behind
#   counts="$(dybatpho::git_ahead_behind ".")"
#   read -r ahead behind <<< "${counts}"
#
# @arg $1 string Optional repository path, default is `.`
# @arg $2 string Optional base ref, default is the upstream of the head ref
# @arg $3 string Optional head ref, default is `HEAD`
# @stdout `<ahead> <behind>` on one line: commits only on the head ref, then
#   commits only on the base ref
# @exitcode 0 Both refs resolved
# @exitcode 1 There is no base ref and the head has no upstream, or a ref is unknown
#######################################
function dybatpho::git_ahead_behind {
  local repo_path base_ref head_ref counts
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  base_ref="${2-}"
  head_ref="${3:-HEAD}"
  if [[ -z "${base_ref}" ]]; then
    local head_branch=""
    [[ "${head_ref}" == "HEAD" ]] || head_branch="${head_ref}"
    base_ref="$(dybatpho::git_upstream "${repo_path}" "${head_branch}")" \
      || dybatpho::die "No upstream configured for ${head_ref}"
  fi
  __dybatpho_git_resolve_commit "${repo_path}" "${base_ref}" > /dev/null
  __dybatpho_git_resolve_commit "${repo_path}" "${head_ref}" > /dev/null
  counts="$(__dybatpho_git "${repo_path}" rev-list --left-right --count \
    "${head_ref}...${base_ref}")"
  printf '%s %s\n' "${counts%%[[:space:]]*}" "${counts##*[[:space:]]}"
}

#######################################
# @description Name the operation a repository is in the middle of.
#   A script that is about to commit, switch branch, or rebase checks this
#   first, so it does not act on a tree that is half way through a merge.
#   The markers are found through `git rev-parse --git-path`, so the answer is
#   right inside a linked worktree, whose state lives apart from the main one.
# @example
#   local state
#   state="$(dybatpho::git_state ".")"
#   [[ "${state}" == "none" ]] || dybatpho::die "Finish the ${state} first"
#
# @arg $1 string Optional repository path, default is `.`
# @stdout One of `rebase`, `am`, `merge`, `cherry-pick`, `revert`, `bisect`, or `none`
# @tip A rebase is reported ahead of the cherry-pick it performs underneath,
#   because the rebase is what has to be continued or aborted
#######################################
function dybatpho::git_state {
  local repo_path
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  local -a names=(rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG)
  local -a git_args=(rev-parse)
  local name
  for name in "${names[@]}"; do
    git_args+=(--git-path "${name}")
  done
  # Keyed by the marker's name, with `-` spelled `_` so the subscript does
  # not read as arithmetic.
  local -A marker=()
  local index=0 marker_path marker_paths
  marker_paths="$(__dybatpho_git "${repo_path}" "${git_args[@]}")"
  while IFS= read -r marker_path; do
    # `--git-path` answers relative to the directory Git ran in.
    [[ "${marker_path}" == /* ]] || marker_path="${repo_path}/${marker_path}"
    marker["${names[index]//-/_}"]="${marker_path}"
    index=$((index + 1))
  done <<< "${marker_paths}"

  if [[ -d "${marker[rebase_merge]}" ]]; then
    printf 'rebase\n'
  elif [[ -d "${marker[rebase_apply]}" ]]; then
    if [[ -e "${marker[rebase_apply]}/applying" ]]; then
      printf 'am\n'
    else
      printf 'rebase\n'
    fi
  elif [[ -e "${marker[MERGE_HEAD]}" ]]; then
    printf 'merge\n'
  elif [[ -e "${marker[CHERRY_PICK_HEAD]}" ]]; then
    printf 'cherry-pick\n'
  elif [[ -e "${marker[REVERT_HEAD]}" ]]; then
    printf 'revert\n'
  elif [[ -e "${marker[BISECT_LOG]}" ]]; then
    printf 'bisect\n'
  else
    printf 'none\n'
  fi
}

#######################################
# @description Return success when a repository is a shallow clone.
#   History questions such as a commit count or the latest tag give a
#   truncated answer in a shallow clone, which is what CI checkouts usually are.
# @example
#   if dybatpho::git_is_shallow "."; then
#     git fetch --unshallow
#   fi
#
# @arg $1 string Optional repository path, default is `.`
# @exitcode 0 The repository is shallow
# @exitcode 1 It has its full history
#######################################
function dybatpho::git_is_shallow {
  local repo_path answer
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  answer="$(__dybatpho_git "${repo_path}" rev-parse --is-shallow-repository)"
  [[ "${answer}" == "true" ]]
}

#######################################
# @description Count the entries on the stash.
# @example
#   local stashed
#   stashed="$(dybatpho::git_stash_count ".")"
#   ((stashed == 0)) || dybatpho::warn "${stashed} stash entries left behind"
#
# @arg $1 string Optional repository path, default is `.`
# @stdout Number of stash entries, `0` when there is no stash
#######################################
function dybatpho::git_stash_count {
  local repo_path
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  if ! __dybatpho_git "${repo_path}" rev-parse --verify --quiet refs/stash > /dev/null 2>&1; then
    printf '0\n'
    return 0
  fi
  __dybatpho_git "${repo_path}" rev-list --walk-reflogs --count refs/stash
}

#######################################
# @description List the worktrees of a repository with the branch each has checked out.
#   The main worktree comes first, then every linked one, in the order
#   `git worktree list` reports them.
# @example
#   local path branch
#   while IFS=$'\t' read -r path branch; do
#     dybatpho::print "${branch} -> ${path}"
#   done <<< "$(dybatpho::git_worktree_list ".")"
#
# @arg $1 string Optional repository path, default is `.`
# @stdout One `<path>\t<branch>` line per worktree. The branch is its short
#   name, `(detached)` when HEAD is detached, or `(bare)` for a bare repository
# @tip The fields are separated by a tab so that a path with spaces reads back
#   whole with `IFS=$'\t' read -r`
#######################################
function dybatpho::git_worktree_list {
  local repo_path
  repo_path="${1:-.}"
  __dybatpho_git_expect_repo "${repo_path}"
  local listing
  listing="$(__dybatpho_git "${repo_path}" worktree list --porcelain)"
  local line worktree_path="" worktree_branch=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      "worktree "*)
        worktree_path="${line#worktree }"
        worktree_branch=""
        ;;
      "branch "*) worktree_branch="${line#branch refs/heads/}" ;;
      detached) worktree_branch="(detached)" ;;
      bare) worktree_branch="(bare)" ;;
      "")
        [[ -z "${worktree_path}" ]] \
          || printf '%s\t%s\n' "${worktree_path}" "${worktree_branch}"
        worktree_path=""
        ;;
      *) ;; # kcov(skip) the HEAD, locked and prunable lines carry nothing listed here
    esac
  done <<< "${listing}"
  [[ -z "${worktree_path}" ]] \
    || printf '%s\t%s\n' "${worktree_path}" "${worktree_branch}"
}
