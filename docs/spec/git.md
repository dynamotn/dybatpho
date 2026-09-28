# Feature Specification: Git Repository Metadata Utilities

**Feature Branch**: `[reverse-spec-git]`
**Status**: Implemented
**Input**: Existing source analysis: `src/git.sh`, `docs/git.md`, `test/git.bats`, and `example/git_ops.sh`

## Problem Statement *(mandatory)*

Shell automation frequently needs repository roots, branches, commit metadata,
change lists, remotes, and tags. Repeating raw Git commands makes scripts
verbose and produces inconsistent behavior outside or inside worktrees.

## Business Value *(mandatory)*

- Provide stable, readable Git metadata helpers.
- Make release and CI scripts independent of custom Git command plumbing.
- Fail clearly when a path or commit reference is invalid.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Identify repository context (Priority: P1)

As a script author, I want to resolve a repository root, branch, and default
branch so that scripts can locate project files and choose release targets.

**Independent Test**: Use temporary repositories with normal, detached, remote,
and fallback branch configurations.

**Acceptance Scenarios**:

1. **Given** a path inside a worktree, **When** `git_root` runs, **Then** it
   prints the absolute top-level directory
2. **Given** a named branch, **When** `git_branch` runs, **Then** it prints
   that branch
3. **Given** detached HEAD, **When** `git_branch` runs, **Then** it prints a
   short commit SHA
4. **Given** `origin/HEAD`, local `main`/`master`, configured
   `init.defaultBranch`, or only the current branch, **When** default-branch
   lookup runs, **Then** it chooses the first available fallback in that order

### User Story 2 - Inspect commits and ranges (Priority: P1)

As a maintainer, I want commit identifiers and metadata plus range queries so
that changelog and release scripts can be driven by Git history.

**Independent Test**: Create a small history and verify full/short hashes,
subjects, authors, range order, and counts.

**Acceptance Scenarios**:

1. **Given** a valid commit-ish or default `HEAD`, **When** metadata helpers
   run, **Then** they print the requested commit value
2. **Given** a base and head reference, **When** a range helper runs, **Then**
   commits reachable from head but not base are returned oldest first or
   counted
3. **Given** an unknown commit-ish, **When** a resolving helper runs, **Then**
   it fails with a clear diagnostic

### User Story 3 - Check worktree and remote state (Priority: P1)

As an operator, I want clean-state, remote, changed-file, and tag checks so
that automation can gate releases and report repository changes.

**Independent Test**: Modify tracked and untracked files, add remotes and tags,
and verify the corresponding predicates and lists.

**Acceptance Scenarios**:

1. **Given** no tracked or untracked changes, **When** `git_is_clean` runs,
   **Then** it succeeds; otherwise it fails
2. **Given** a configured remote, **When** remote helpers run, **Then** the URL
   is printed or existence succeeds
3. **Given** a base ref and current worktree, **When** changed files are listed,
   **Then** tracked and untracked paths are sorted byte-wise, whatever the
   locale, and deduplicated
4. **Given** a commit contained by one or more tags, **When** tag lookup runs,
   **Then** matching tag names are printed in sorted order

### Example Workflow

```bash
root="$(dybatpho::git_root)"
base="$(dybatpho::git_default_branch "${root}")"

dybatpho::info "branch: $(dybatpho::git_branch "${root}")"
dybatpho::info "commit: $(dybatpho::git_commit_short_hash "${root}") $(dybatpho::git_commit_subject "${root}")"
dybatpho::info "$(dybatpho::git_commit_count "${root}" "${base}") commits ahead of ${base}"

dybatpho::git_is_clean "${root}" || dybatpho::die "Refusing to release a dirty worktree"
dybatpho::git_has_remote origin "${root}" \
  && dybatpho::info "origin: $(dybatpho::git_remote_url origin "${root}")"

dybatpho::git_changed_files "${root}" "${base}"
```

## Edge Cases

- The path is outside any Git worktree.
- Git is not installed.
- HEAD is detached or the repository has no preferred branch fallback.
- A commit-ish, base ref, or head ref is unknown.
- A remote is missing or has no configured URL.
- The worktree contains both tracked and untracked changes.
- A range is empty.

### User Story - Ask whether a commit has landed (Priority: P2)

As a release script, I want to know whether one commit is reachable from another so that I can tell an already-released tag from one that is not on this branch, before acting on it.

**Why this priority**: Acting on the wrong answer ships a release from the wrong history, which is expensive to undo.

**Independent Test**: Build a repository with a branch that diverges, and verify reachability in both directions.

**Acceptance Scenarios**:

1. **Given** an earlier commit and a later one on the same branch, **When** reachability is asked, **Then** the earlier one is reported as an ancestor and the later one is not
2. **Given** one commit, **When** it is compared with itself, **Then** it counts as its own ancestor, which is what "has this landed" should answer
3. **Given** two branches that have diverged, **When** either tip is compared with the other, **Then** neither reaches the other
4. **Given** a reference that cannot be resolved, **When** reachability is asked, **Then** the call fails rather than guessing

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-A01**: The module MUST report whether one commit is reachable from another, treating a commit as its own ancestor, accepting tags and branch names as well as hashes, and failing when either reference cannot be resolved.

- **FR-001**: All repository helpers MUST accept an optional repository path,
  defaulting to `.` where applicable.
- **FR-002**: Helpers MUST reject paths that are not inside a Git worktree.
- **FR-003**: `git_root` MUST print the absolute repository top-level path.
- **FR-004**: `git_branch` MUST print the current short branch name or a short
  HEAD SHA when detached.
- **FR-005**: `git_default_branch` MUST prefer `origin/HEAD`, then local
  `main`, local `master`, configured `init.defaultBranch`, and finally the
  current branch.
- **FR-006**: Commit helpers MUST support full hash, 7-character short hash,
  subject, author, existence, range listing, and range count.
- **FR-007**: Commit-resolving helpers MUST reject unknown commit-ish values.
- **FR-008**: `git_is_clean` MUST treat tracked and untracked worktree changes
  as dirty.
- **FR-009**: Remote helpers MUST read a named remote URL and test remote
  existence, defaulting to `origin`.
- **FR-010**: `git_changed_files` MUST combine tracked diff paths with
  non-ignored untracked paths, then sort and deduplicate them.
- **FR-011**: `git_tags_containing` MUST resolve the commit and print containing
  tags in sorted order.
- **FR-012**: All helpers MUST target the requested repository path even when
  Git environment variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, and
  related) are exported by a surrounding Git hook.

### Key Entities *(include if feature involves data)*

- **Repository Path**: A path validated as inside a Git worktree.
- **Branch Reference**: A local, remote, or current branch name used for
  default-branch selection.
- **Commit-ish**: A Git reference resolved to a commit object.
- **Commit Range**: The commits in `base..head`, listed oldest first when
  requested.
- **Worktree State**: Clean or dirty status including untracked files.
- **Remote**: A named Git remote and its configured URL.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: CI and release scripts can obtain common Git metadata without
  open-coded `git -C` pipelines.
- **SC-002**: Invalid repository paths and references fail before misleading
  output is produced.
- **SC-003**: Change and range reports are stable, sorted, and suitable for
  automation.

## Integration Tests *(mandatory)*

- **IT-A01**: Verify reachability along a branch, for a commit against itself, across two diverged branches, with a tag, and for an unresolvable reference.

- **IT-001**: Resolve root, branch, detached HEAD, and default branch fallbacks.
- **IT-002**: Read commit hash, short hash, subject, and author.
- **IT-003**: List and count commits between valid refs and reject unknown refs.
- **IT-004**: Check clean and dirty worktrees with tracked and untracked files.
- **IT-005**: Read an existing remote URL and test missing remote behavior.
- **IT-006**: List sorted changed files and tags containing a commit.
- **IT-007**: Verify all repository helpers fail clearly outside a worktree.
- **IT-008**: Verify helpers work when run with `GIT_DIR`/`GIT_INDEX_FILE` set,
  as happens inside a `pre-commit` hook.

## Acceptance Criteria *(mandatory)*

1. Git helpers are composable in command substitutions and shell conditionals.
2. Defaults and failure behavior match the current source and generated docs.
3. Repository inspection does not mutate the target repository.
