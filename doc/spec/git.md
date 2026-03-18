# Feature Specification: Git Utilities

**Status**: Implemented
**Source**: `src/git.sh`

## Problem Statement

Shell scripts repeatedly need lightweight Git metadata — repository root, current branch, default branch, commit hashes/subjects/authors, remote URLs, changed files, tags — but embedding raw `git` commands makes automation noisy and error-prone.

## Functional Requirements

- **FR-001** Helper that returns the Git repository root for a path.
- **FR-002** Helper that returns the current branch, or a short SHA in detached HEAD state.
- **FR-003** Helper that returns the default branch (prefers `origin/HEAD`, then `main`/`master`, then current).
- **FR-004** Helper that returns success only when the worktree is clean.
- **FR-005** Helper that returns a configured remote URL.
- **FR-006** Helper that returns success only when a named remote exists.
- **FR-007** Helper that lists tracked and untracked changed file paths (sorted, deduplicated).
- **FR-008** Helper that lists tags containing a commit-ish.
- **FR-009** Helpers for commit hash, short hash, subject, author, range listing, and range count.
- **FR-010** Helper that returns success only when a commit exists.
- **FR-011** All public helpers MUST fail clearly when the target path is not inside a Git repository.
- **FR-012** Commit-resolving helpers MUST fail clearly when the commit-ish does not exist.

## Public API

| Function | Args | Returns |
|---|---|---|
| `dybatpho::git_root` | `[path]` | Absolute repo root path |
| `dybatpho::git_branch` | `[path]` | Current branch or short SHA |
| `dybatpho::git_default_branch` | `[path]` | Default branch name |
| `dybatpho::git_commit_hash` | `[path] [commit-ish]` | Full SHA |
| `dybatpho::git_commit_short_hash` | `[path] [commit-ish]` | 7-char SHA |
| `dybatpho::git_commit_subject` | `[path] [commit-ish]` | Commit subject line |
| `dybatpho::git_commit_author` | `[path] [commit-ish]` | Author name |
| `dybatpho::git_has_commit` | `[path] [commit-ish]` | Exit 0 if exists |
| `dybatpho::git_commits_between` | `path base [head]` | SHAs oldest→newest |
| `dybatpho::git_commit_count` | `path base [head]` | Integer count |
| `dybatpho::git_is_clean` | `[path]` | Exit 0 if clean |
| `dybatpho::git_remote_url` | `[remote] [path]` | Remote fetch URL |
| `dybatpho::git_has_remote` | `[remote] [path]` | Exit 0 if exists |
| `dybatpho::git_changed_files` | `[path] [base]` | Changed file paths |
| `dybatpho::git_tags_containing` | `[path] [commit-ish]` | Tag names |
