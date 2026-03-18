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

- [`__dybatpho_git_repo_path`](#__dybatpho_git_repo_path) — Ensure a path is inside a Git worktree.
- [`__dybatpho_git_resolve_commit`](#__dybatpho_git_resolve_commit) — Resolve a commit-ish to a full SHA.
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
- [`dybatpho::git_tags_containing`](#dybatphogit_tags_containing) — List tags that contain a commit.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::git_default_branch`

- Prefers `origin/HEAD`, then local `main`/`master`, then current branch

<a id="reference"></a>
## 📚 Reference

### `__dybatpho_git_repo_path`

Ensure a path is inside a Git worktree.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |

**📤 Output on stdout**

- The validated repository path


---

### `__dybatpho_git_resolve_commit`

Resolve a commit-ish to a full SHA.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | Commit-ish to resolve |

**📤 Output on stdout**

- Full commit SHA


---

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

- One changed file path per line, sorted and deduplicated


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

