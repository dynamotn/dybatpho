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

- A base ref that names no commit, and a repository with no commit yet.
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

### User Story - Know where the branch stands before acting (Priority: P2)

As a script that is about to commit, pull, push, or rebase, I want to know the
branch's upstream, how far it has drifted from it, whether an operation is
half finished, whether the clone is shallow, how much is stashed, and which
worktrees exist, so that I refuse to act on a repository in a state the action
would make worse.

**Why this priority**: Committing into a half-finished merge or reading tags
from a shallow clone gives a wrong result without any error.

**Independent Test**: Build temporary repositories with a bare remote, diverged
branches, conflicted merge/cherry-pick/revert/rebase/am runs, a bisect, a
shallow clone, stash entries, and linked worktrees whose paths contain spaces.

**Acceptance Scenarios**:

1. **Given** a branch that tracks a remote branch, **When** `git_upstream`
   runs, **Then** it prints the upstream's short name; **Given** no upstream,
   an unknown branch, or detached HEAD, **Then** it prints nothing and exits 1
2. **Given** two refs, **When** `git_ahead_behind` runs, **Then** it prints the
   commits only on the head ref and the commits only on the base ref, in that
   order; with no base it compares with the upstream and fails clearly when
   there is none
3. **Given** a conflicted merge, cherry-pick, revert, rebase, `git am`, or a
   bisect, **When** `git_state` runs, **Then** it names that operation, and
   prints `none` otherwise, including from a subdirectory and for each linked
   worktree separately
4. **Given** a shallow clone, **When** `git_is_shallow` runs, **Then** it
   succeeds, and fails for a full clone
5. **Given** stash entries, **When** `git_stash_count` runs, **Then** it prints
   their number, `0` when there is no stash
6. **Given** linked worktrees, **When** `git_worktree_list` runs, **Then** it
   prints one tab-separated path and branch per worktree, the main one first,
   with `(detached)` and `(bare)` for those cases

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-A01**: The module MUST report whether one commit is reachable from another, treating a commit as its own ancestor, accepting tags and branch names as well as hashes, and failing when either reference cannot be resolved.

- **FR-B01**: `git_upstream` MUST print the short name of the upstream of the
  current or named branch, and MUST exit 1 with no output when there is none,
  the branch is unknown, or HEAD is detached.
- **FR-B02**: `git_ahead_behind` MUST print `<ahead> <behind>` for a head ref
  (default `HEAD`) against a base ref (default the head's upstream), MUST fail
  with a diagnostic when no base is given and the head has no upstream, and
  MUST reject unknown refs.
- **FR-B03**: `git_state` MUST print `rebase`, `am`, `merge`, `cherry-pick`,
  `revert`, `bisect`, or `none`, checking in that order, and MUST locate the
  markers through the worktree's own Git paths so linked worktrees and
  subdirectories answer for themselves.
- **FR-B04**: `git_is_shallow` MUST succeed for a shallow repository and fail
  otherwise.
- **FR-B05**: `git_stash_count` MUST print the number of stash entries, `0`
  when there is no stash.
- **FR-B06**: `git_worktree_list` MUST print one `<path>\t<branch>` line per
  worktree, the main worktree first, with `(detached)` for a detached HEAD and
  `(bare)` for a bare repository, keeping paths with spaces whole.

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
- **FR-013**: `git_changed_files` MUST stop when the base names no commit or a Git command fails, and before the first commit MUST list staged files together with untracked ones.

### Key Entities *(include if feature involves data)*

- **Repository Path**: A path validated as inside a Git worktree.
- **Branch Reference**: A local, remote, or current branch name used for
  default-branch selection.
- **Commit-ish**: A Git reference resolved to a commit object.
- **Commit Range**: The commits in `base..head`, listed oldest first when
  requested.
- **Worktree State**: Clean or dirty status including untracked files.
- **Remote**: A named Git remote and its configured URL.
- **Upstream**: The remote-tracking branch a local branch is configured to
  follow.
- **Repository State**: The operation in progress in a worktree, or `none`.
- **Worktree Entry**: A worktree path paired with its checked-out branch.

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

- **IT-B01**: Read the upstream of the current and a named branch, and fail
  without one, for an unknown branch, and on detached HEAD.
- **IT-B02**: Count ahead/behind against the upstream and between diverged
  branches in both directions, and fail without an upstream or with an unknown
  ref.
- **IT-B03**: Report each in-progress operation, `none` once it is aborted, a
  linked worktree's bisect without leaking it into the main worktree, and the
  state from a subdirectory with a space in its name.
- **IT-B04**: Tell a shallow clone from a full repository, count stash entries,
  and list worktrees with spaces, detached HEAD, and a bare main repository.
- **IT-B05**: Verify every new helper fails clearly outside a worktree.

- **IT-001**: Resolve root, branch, detached HEAD, and default branch fallbacks.
- **IT-002**: Read commit hash, short hash, subject, and author.
- **IT-003**: List and count commits between valid refs and reject unknown refs.
- **IT-004**: Check clean and dirty worktrees with tracked and untracked files.
- **IT-005**: Read an existing remote URL and test missing remote behavior.
- **IT-006**: List sorted changed files and tags containing a commit.
- **IT-007**: Verify all repository helpers fail clearly outside a worktree.
- **IT-008**: Verify helpers work when run with `GIT_DIR`/`GIT_INDEX_FILE` set,
  as happens inside a `pre-commit` hook.
- **IT-009**: Refuse a base that names no commit, and list staged and untracked files in a repository with no commit.

## Acceptance Criteria *(mandatory)*

1. Git helpers are composable in command substitutions and shell conditionals.
2. Defaults and failure behavior match the current source and generated docs.
3. Repository inspection does not mutate the target repository.
