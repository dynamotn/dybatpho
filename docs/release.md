# release.sh

Utilities for cutting a release from a Git repository

> 🧭 Source: [src/release.sh](../src/release.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module turns the commits since the last tag into a release: it decides
how far the version moves, writes the changelog entry, packages build output
per platform, and produces the checksums and signature a consumer needs to
verify what they downloaded.

Version decisions follow [Conventional Commits](https://www.conventionalcommits.org):
a commit marked breaking moves the major, `feat` moves the minor, `fix` and
`perf` move the patch, and anything else does not move the version at all.

Nothing here talks to a forge. The module produces files; pushing a tag or
creating a GitHub release stays with the caller, who owns those credentials.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RELEASE_TAG_PATTERN`** | string | Glob that release tags match, default is `v*` |
| **`DYBATPHO_RELEASE_CHECKSUM_ALGORITHM`** | string | Checksum algorithm for the sums file, default is `sha256` |
| **`DYBATPHO_RELEASE_SIGN_CMD`** | string | Command that signs a file, receiving the signature path and the file path. Default signs with `gpg` |
| **`DYBATPHO_RELEASE_GPG_KEY`** | string | Key `gpg` signs with, default is its configured default key |

### 🚀 Highlights

- [`dybatpho::release_commit_parse`](#dybatphorelease_commit_parse) — Break a commit message into the parts Conventional Commits defines. `dybatpho::release_commit_type` answers only "what kind of change is this", and reports a breaking change as its own kind, which loses the type. This reports every part separately, so a caller can group by type and still know that the change was breaking.
- [`dybatpho::release_commit_type`](#dybatphorelease_commit_type) — Classify one commit subject as Conventional Commits does.
- [`dybatpho::release_bump_type`](#dybatphorelease_bump_type) — Decide how far the version should move, from the commits in a range. A commit is breaking when its subject carries `!` or its body carries a `BREAKING CHANGE:` footer, which is the other spelling the convention allows.
- [`dybatpho::release_next_version`](#dybatphorelease_next_version) — Print the version a release from these commits should carry.
- [`dybatpho::release_changelog`](#dybatphorelease_changelog) — Render the changelog entry for a range of commits. Commits are grouped the way Conventional Commits names them, so the entry reads as a summary of what changed rather than a list of subjects.
- [`dybatpho::release_artifact_name`](#dybatphorelease_artifact_name) — Print the name a release artifact should carry for one platform. The layout is the one Go release tooling established, so a consumer who has seen any Go project's downloads recognizes it.
- [`dybatpho::release_package`](#dybatphorelease_package) — Package build output into a release artifact for one platform.
- [`dybatpho::release_checksums`](#dybatphorelease_checksums) — Write one checksum file covering every artifact in a directory. The layout is the one `sha256sum -c` reads, so a consumer verifies a download with a tool they already have.
- [`dybatpho::release_sign`](#dybatphorelease_sign) — Sign a file and print the signature's path. Signing uses `gpg` unless `DYBATPHO_RELEASE_SIGN_CMD` names another command, which lets a project sign with `minisign`, `cosign`, or anything else without this module knowing about it.

<a id="see-also"></a>
## 🔗 See also

- [example/release_ops.sh](../example/release_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::release_commit_parse`

- A subject that follows no convention reports the type `other` and keeps the whole subject as its description

### `dybatpho::release_next_version`

- With no tag in the repository yet, the range starts at the first commit and the result is the first version the commits call for

### `dybatpho::release_changelog`

- Commits of a type that does not move the version, such as `docs` or `chore`, are left out: they are part of the history, not of the release notes

### `dybatpho::release_package`

- The artifact is written by the `archive` module, which `release` does not load; load it alongside: `--modules release archive`

### `dybatpho::release_checksums`

- The file names are recorded without a directory component, so the file verifies from inside the directory it describes

### `dybatpho::release_sign`

- Sign the checksum file rather than every artifact: one signature then covers them all, because the checksums bind their contents

<a id="reference"></a>
## 📚 Reference

### `dybatpho::release_commit_parse`

Break a commit message into the parts Conventional Commits defines.
`dybatpho::release_commit_type` answers only "what kind of change is this",
and reports a breaking change as its own kind, which loses the type. This
reports every part separately, so a caller can group by type and still know
that the change was breaking.

**🧪 Examples**

```bash
read -r type scope breaking description < <(
  dybatpho::release_commit_parse "feat(api)!: drop the v1 endpoints" | paste -sd' ' -
)

```

```bash
dybatpho::release_commit_parse "fix: handle empty input"
# fix
# false
# handle empty input

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Commit subject line |
| `$2` | string | Optional commit body, searched for a `BREAKING CHANGE:` footer |

**📤 Output on stdout**

- Four lines: type, scope (empty if none), `true` or `false` for
  breaking, and the description with the type prefix removed


---

### `dybatpho::release_commit_type`

Classify one commit subject as Conventional Commits does.

**🧪 Example**

```bash
dybatpho::release_commit_type "feat(api)!: drop v1 endpoints"  # breaking
dybatpho::release_commit_type "fix: handle empty input"        # fix

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Commit subject line |

**📤 Output on stdout**

- One of `breaking`, `feat`, `fix`, `perf`, the declared type, or `other`


---

### `dybatpho::release_bump_type`

Decide how far the version should move, from the commits in a range.
A commit is breaking when its subject carries `!` or its body carries a
`BREAKING CHANGE:` footer, which is the other spelling the convention allows.

**🧪 Example**

```bash
bump="$(dybatpho::release_bump_type "." "v1.2.3")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | Base ref, excluded from the range, or empty to read the whole history |
| `$3` | string | Optional head ref, default is `HEAD` |

**📤 Output on stdout**

- One of `major`, `minor`, or `patch`

**🚦 Exit codes**

- `1`: No commit in the range calls for a release


---

### `dybatpho::release_next_version`

Print the version a release from these commits should carry.

**🧪 Example**

```bash
if next="$(dybatpho::release_next_version ".")"; then
  dybatpho::info "Next release is v${next}"
else
  dybatpho::info "Nothing to release"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional repository path, default is `.` |
| `$2` | string | Optional base tag, default is the highest matching tag |
| `$3` | string | Optional head ref, default is `HEAD` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RELEASE_TAG_PATTERN`** | string | Glob that release tags match |

**📤 Output on stdout**

- Next version, without a leading `v`

**🚦 Exit codes**

- `1`: No commit since the base tag calls for a release


---

### `dybatpho::release_changelog`

Render the changelog entry for a range of commits.
Commits are grouped the way Conventional Commits names them, so the entry
reads as a summary of what changed rather than a list of subjects.

**🧪 Example**

```bash
dybatpho::release_changelog "." "v1.2.3" "HEAD" "1.3.0" >> CHANGELOG.md

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Repository path |
| `$2` | string | Base ref, excluded from the range, or empty to read the whole history |
| `$3` | string | Optional head ref, default is `HEAD` |
| `$4` | string | Optional version for the heading, default is `Unreleased` |

**📤 Output on stdout**

- Markdown section for the release


---

### `dybatpho::release_artifact_name`

Print the name a release artifact should carry for one platform.
The layout is the one Go release tooling established, so a consumer who has
seen any Go project's downloads recognizes it.

**🧪 Example**

```bash
dybatpho::release_artifact_name mytool 1.3.0 linux amd64   # mytool_1.3.0_linux_amd64.tar.gz
dybatpho::release_artifact_name mytool 1.3.0 windows amd64 # mytool_1.3.0_windows_amd64.zip

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Project name |
| `$2` | string | Version, without a leading `v` |
| `$3` | string | Optional operating system, default is the current one |
| `$4` | string | Optional architecture, default is the current one |

**📤 Output on stdout**

- Artifact file name, including the extension for that platform


---

### `dybatpho::release_package`

Package build output into a release artifact for one platform.

**🧪 Example**

```bash
dybatpho::release_package ./dist/linux_amd64 ./release mytool 1.3.0 linux amd64

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Directory or file to package |
| `$2` | string | Directory the artifact is written to, created when missing |
| `$3` | string | Project name |
| `$4` | string | Version |
| `$5` | string | Optional operating system, default is the current one |
| `$6` | string | Optional architecture, default is the current one |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, print the path without packaging anything |

**📤 Output on stdout**

- Path of the artifact that was created

**🚦 Exit codes**

- `1`: The source is missing or the archive cannot be created
- `1`: Stop the script when the `archive` module is not loaded


---

### `dybatpho::release_checksums`

Write one checksum file covering every artifact in a directory.
The layout is the one `sha256sum -c` reads, so a consumer verifies a
download with a tool they already have.

**🧪 Example**

```bash
sums="$(dybatpho::release_checksums ./release)"
( cd ./release && sha256sum -c "$(basename "${sums}")" )

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Directory holding the artifacts |
| `$2` | string | Optional output file, default is `<dir>/SHA256SUMS` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RELEASE_CHECKSUM_ALGORITHM`** | string | Algorithm passed to the hash helper |
| **`DRY_RUN`** | string | When true-like, print the path without writing anything |

**📤 Output on stdout**

- Path of the checksum file

**🚦 Exit codes**

- `1`: The directory is missing or holds no file to checksum


---

### `dybatpho::release_sign`

Sign a file and print the signature's path.
Signing uses `gpg` unless `DYBATPHO_RELEASE_SIGN_CMD` names another command,
which lets a project sign with `minisign`, `cosign`, or anything else
without this module knowing about it.

**🧪 Examples**

```bash
dybatpho::release_sign ./release/SHA256SUMS

```

```bash
DYBATPHO_RELEASE_SIGN_CMD="minisign -S -m" dybatpho::release_sign ./release/SHA256SUMS

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File to sign |
| `$2` | string | Optional signature path, default is `<file>.asc` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_RELEASE_SIGN_CMD`** | string | Command receiving the signature path and the file path, one argument each |
| **`DYBATPHO_RELEASE_GPG_KEY`** | string | Key `gpg` signs with |
| **`DRY_RUN`** | string | When true-like, print the path without signing |

**📤 Output on stdout**

- Path of the signature

**🚦 Exit codes**

- `1`: The file is missing, no signing tool is available, or signing fails
