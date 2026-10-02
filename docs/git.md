# git.sh

Utilities for Git repositories

> 🧭 Source: [src/git.sh](../src/git.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

Helpers for common Git metadata and history lookups: locating the
repository root, reading the current branch, resolving the default branch,
inspecting commits, checking whether the worktree is clean, reading remote
information, listing changed files, and querying commit/tag relationships.

### 🚀 Highlights

- [`dybatpho::git_root`](#dybatphogit_root) — Return the top-level directory of a Git repository.
- [`dybatpho::git_branch`](#dybatphogit_branch) — Return the current branch name, or a short SHA in detached HEAD state.
- [`dybatpho::git_default_branch`](#dybatphogit_default_branch) — Return the default branch of a Git repository.
- [`dybatpho::git_commit_hash`](#dybatphogit_commit_hash) — Return the full SHA of a commit.
- [`dybatpho::git_commit_short_hash`](#dybatphogit_commit_short_hash) — Return the short SHA of a commit.
- [`dybatpho::git_commit_subject`](#dybatphogit_commit_subject) — Return the subject line of a commit message.
- [`dybatpho::git_commit_author`](#dybatphogit_commit_author) — Return the author name of a commit.
- [`dybatpho::git_has_commit`](#dybatphogit_has_commit) — Return success when a commit exists.
- [`dybatpho::git_commits_between`](#dybatphogit_commits_between) — List commits reachable from a head ref but not from a base ref.
- [`dybatpho::git_commit_count`](#dybatphogit_commit_count) — Count commits in a range.
- [`dybatpho::git_is_clean`](#dybatphogit_is_clean) — Return success when the worktree has no tracked or untracked changes.
- [`dybatpho::git_remote_url`](#dybatphogit_remote_url) — Return the URL for a Git remote.
- [`dybatpho::git_has_remote`](#dybatphogit_has_remote) — Return success when a named remote exists.
- [`dybatpho::git_changed_files`](#dybatphogit_changed_files) — List changed files relative to a base ref, including untracked.
- [`dybatpho::git_latest_tag`](#dybatphogit_latest_tag) — Print the highest version tag in a repository. Tags are ordered the way versions compare, not the way strings do, so `v10` sorts above `v9` and the newest release is the first line.
- [`dybatpho::git_tags_containing`](#dybatphogit_tags_containing) — List tags that contain a commit.
- [`dybatpho::git_is_ancestor`](#dybatphogit_is_ancestor) — Return success when one commit is reachable from another. A release script asks this before acting: whether a tag is on the branch it is about to release, or whether a fix has already landed on the branch a backport is aimed at.
- [`dybatpho::git_upstream`](#dybatphogit_upstream) — Print the upstream a branch tracks. A script asks this before it compares with, pulls from, or pushes to the remote branch, and the answer is the short name Git shows, such as `origin/main`.
- [`dybatpho::git_ahead_behind`](#dybatphogit_ahead_behind) — Count the commits a ref is ahead of and behind another. With no base the branch is compared with its upstream, which is the "2 ahead, 1 behind" a prompt or a pre-push check wants.
- [`dybatpho::git_state`](#dybatphogit_state) — Name the operation a repository is in the middle of. A script that is about to commit, switch branch, or rebase checks this first, so it does not act on a tree that is half way through a merge. The markers are found through `git rev-parse --git-path`, so the answer is right inside a linked worktree, whose state lives apart from the main one.
- [`dybatpho::git_is_shallow`](#dybatphogit_is_shallow) — Return success when a repository is a shallow clone. History questions such as a commit count or the latest tag give a truncated answer in a shallow clone, which is what CI checkouts usually are.
- [`dybatpho::git_stash_count`](#dybatphogit_stash_count) — Count the entries on the stash.
- [`dybatpho::git_worktree_list`](#dybatphogit_worktree_list) — List the worktrees of a repository with the branch each has checked out. The main worktree comes first, then every linked one, in the order `git worktree list` reports them.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::git_default_branch`

- Prefers `origin/HEAD`, then local `main`/`master`, then current branch

### `dybatpho::git_is_ancestor`

- A commit counts as its own ancestor, which is what `git merge-base` reports and what makes "has this landed yet" answer yes for the commit itself

### `dybatpho::git_state`

- A rebase is reported ahead of the cherry-pick it performs underneath, because the rebase is what has to be continued or aborted

### `dybatpho::git_worktree_list`

- The fields are separated by a tab so that a path with spaces reads back whole with `IFS=$'\t' read -r`

<a id="reference"></a>
## 📚 Reference

### `dybatpho::git_root`

Return the top-level directory of a Git repository.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- Absolute path to the repository root


---

### `dybatpho::git_branch`

Return the current branch name, or a short SHA in detached HEAD state.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- Current branch name or short SHA


---

### `dybatpho::git_default_branch`

Return the default branch of a Git repository.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- Default branch name


---

### `dybatpho::git_commit_hash`

Return the full SHA of a commit.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional commit-ish, default is `HEAD` |

**📤 Output on stdout**

- Full commit SHA


---

### `dybatpho::git_commit_short_hash`

Return the short SHA of a commit.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional commit-ish, default is `HEAD` |

**📤 Output on stdout**

- Short commit SHA (7 chars)


---

### `dybatpho::git_commit_subject`

Return the subject line of a commit message.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional commit-ish, default is `HEAD` |

**📤 Output on stdout**

- Commit subject line


---

### `dybatpho::git_commit_author`

Return the author name of a commit.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional commit-ish, default is `HEAD` |

**📤 Output on stdout**

- Commit author name


---

### `dybatpho::git_has_commit`

Return success when a commit exists.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Commit-ish to verify, default is `HEAD` |

**🚦 Exit codes**

- `0`: Commit exists
- `1`: Commit does not exist


---

### `dybatpho::git_commits_between`

List commits reachable from a head ref but not from a base ref.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | Base ref (excluded) |
| `$3` | string | Optional head ref, default is `HEAD` |

**📤 Output on stdout**

- One full SHA per line, oldest first


---

### `dybatpho::git_commit_count`

Count commits in a range.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | Base ref (excluded) |
| `$3` | string | Optional head ref, default is `HEAD` |

**📤 Output on stdout**

- Number of commits


---

### `dybatpho::git_is_clean`

Return success when the worktree has no tracked or untracked changes.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**🚦 Exit codes**

- `0`: Worktree is clean
- `1`: Worktree has changes


---

### `dybatpho::git_remote_url`

Return the URL for a Git remote.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default is `origin` |
| `$2` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- Remote URL


---

### `dybatpho::git_has_remote`

Return success when a named remote exists.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default is `origin` |
| `$2` | string | Optional repository path, default is `.` |

**🚦 Exit codes**

- `0`: Remote exists
- `1`: Remote does not exist


---

### `dybatpho::git_changed_files`

List changed files relative to a base ref, including untracked.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional base ref, default is `HEAD` |

**📤 Output on stdout**

- One changed file path per line, sorted byte-wise and deduplicated,
  so the order does not depend on the caller's locale


---

### `dybatpho::git_latest_tag`

Print the highest version tag in a repository.
Tags are ordered the way versions compare, not the way strings do, so `v10`
sorts above `v9` and the newest release is the first line.

**🧪 Example**

```bash
if previous="$(dybatpho::git_latest_tag "." "v*")"; then
  dybatpho::info "Releasing on top of ${previous}"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional tag glob to match, default is every tag |

**📤 Output on stdout**

- The highest matching tag

**🚦 Exit codes**

- `0`: A matching tag exists
- `1`: The repository has no matching tag


---

### `dybatpho::git_tags_containing`

List tags that contain a commit.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional commit-ish, default is `HEAD` |

**📤 Output on stdout**

- One tag per line, sorted


---

### `dybatpho::git_is_ancestor`

Return success when one commit is reachable from another.
A release script asks this before acting: whether a tag is on the branch it
is about to release, or whether a fix has already landed on the branch a
backport is aimed at.

**🧪 Example**

```bash
if dybatpho::git_is_ancestor "." "v1.2.0" "HEAD"; then
  dybatpho::info "v1.2.0 is already on this branch"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | The commit-ish that may be the ancestor |
| `$3` | string | The commit-ish that may descend from it |

**🚦 Exit codes**

- `0`: The first commit is an ancestor of the second, or they are the same commit
- `1`: It is not, or either commit-ish cannot be resolved


---

### `dybatpho::git_upstream`

Print the upstream a branch tracks.
A script asks this before it compares with, pulls from, or pushes to the
remote branch, and the answer is the short name Git shows, such as
`origin/main`.

**🧪 Example**

```bash
if upstream="$(dybatpho::git_upstream "." main)"; then
  dybatpho::info "main tracks ${upstream}"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional branch name, default is the current branch |

**📤 Output on stdout**

- Short name of the upstream ref

**🚦 Exit codes**

- `0`: The branch has an upstream
- `1`: It has none, the branch does not exist, or HEAD is detached


---

### `dybatpho::git_ahead_behind`

Count the commits a ref is ahead of and behind another.
With no base the branch is compared with its upstream, which is the
"2 ahead, 1 behind" a prompt or a pre-push check wants.

**🧪 Example**

```bash
local counts ahead behind
counts="$(dybatpho::git_ahead_behind ".")"
read -r ahead behind <<< "${counts}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional base ref, default is the upstream of the head ref |
| `$3` | string | Optional head ref, default is `HEAD` |

**📤 Output on stdout**

- `<ahead> <behind>` on one line: commits only on the head ref, then
  commits only on the base ref

**🚦 Exit codes**

- `0`: Both refs resolved
- `1`: There is no base ref and the head has no upstream, or a ref is unknown


---

### `dybatpho::git_state`

Name the operation a repository is in the middle of.
A script that is about to commit, switch branch, or rebase checks this
first, so it does not act on a tree that is half way through a merge.
The markers are found through `git rev-parse --git-path`, so the answer is
right inside a linked worktree, whose state lives apart from the main one.

**🧪 Example**

```bash
local state
state="$(dybatpho::git_state ".")"
[[ "${state}" == "none" ]] || dybatpho::die "Finish the ${state} first"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- One of `rebase`, `am`, `merge`, `cherry-pick`, `revert`, `bisect`, or `none`


---

### `dybatpho::git_is_shallow`

Return success when a repository is a shallow clone.
History questions such as a commit count or the latest tag give a
truncated answer in a shallow clone, which is what CI checkouts usually are.

**🧪 Example**

```bash
if dybatpho::git_is_shallow "."; then
  git fetch --unshallow
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**🚦 Exit codes**

- `0`: The repository is shallow
- `1`: It has its full history


---

### `dybatpho::git_stash_count`

Count the entries on the stash.

**🧪 Example**

```bash
local stashed
stashed="$(dybatpho::git_stash_count ".")"
((stashed == 0)) || dybatpho::warn "${stashed} stash entries left behind"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- Number of stash entries, `0` when there is no stash


---

### `dybatpho::git_worktree_list`

List the worktrees of a repository with the branch each has checked out.
The main worktree comes first, then every linked one, in the order
`git worktree list` reports them.

**🧪 Example**

```bash
local path branch
while IFS=$'\t' read -r path branch; do
  dybatpho::print "${branch} -> ${path}"
done <<< "$(dybatpho::git_worktree_list ".")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- One `<path>\t<branch>` line per worktree. The branch is its short
  name, `(detached)` when HEAD is detached, or `(bare)` for a bare repository
