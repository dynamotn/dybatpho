# forge.sh

Utilities for talking to the forge a repository is hosted on

> 🧭 Source: [src/forge.sh](../src/forge.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`git.sh` reads the repository on disk and `release.sh` builds, checksums and
signs artifacts — and then stops. Nothing in the library publishes anything.
This module closes that gap: it turns a Git remote into an authenticated API
client for the forge behind it, and exposes the two things a release or CI
script actually needs from one — issues and releases.

**GitHub** (including GitHub Enterprise) and **GitLab** (including
self-hosted) are both supported. The forge is detected from the remote URL,
so a script that works against `github.com` works against a company GitLab
without changing a line. Everything that differs between the two — the API
base, the auth header, how a project is addressed in a path, and what the
fields are called — is resolved behind the public functions.

Tokens are read from the environment and registered with `secret.sh`, so a
token can never reach a log line even when a request is traced.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORGE`** | string | Force the forge kind, `github` or `gitlab`, instead of detecting it |
| **`DYBATPHO_FORGE_REMOTE`** | string | Git remote the forge is detected from, default `origin` |
| **`DYBATPHO_FORGE_API`** | string | Override the API base URL, for a forge on a path detection cannot guess |
| **`DYBATPHO_FORGE_REPO`** | string | Override the detected `owner/repo` |
| **`DYBATPHO_FORGE_TOKEN`** | string | Token to authenticate with, preferred over the per-forge variables |

### 🚀 Highlights

- [`dybatpho::forge_host`](#dybatphoforge_host) — Print the host of the configured remote.
- [`dybatpho::forge_kind`](#dybatphoforge_kind) — Print which forge the repository is hosted on. `DYBATPHO_FORGE` wins when set, so a mirror or an unrecognizable host name never has to be guessed at.
- [`dybatpho::forge_repo`](#dybatphoforge_repo) — Print the `owner/repo` the remote points at. A GitLab project may be nested in subgroups, so everything after the host is kept rather than only the last two segments.
- [`dybatpho::forge_api`](#dybatphoforge_api) — Print the API base URL for the repository's forge. `github.com` answers on a separate API host; every other GitHub is an Enterprise install serving `/api/v3` from the same host. GitLab always serves `/api/v4` from its own host.
- [`dybatpho::forge_token`](#dybatphoforge_token) — Print the token used to authenticate against the forge. The token is registered with `secret.sh` before it is returned, so a later log line containing it is masked instead. That registration only reaches the shell this function runs in. Capturing the token with `token="$(dybatpho::forge_token)"` runs it in a subshell, which takes the registration with it when it exits — a Bash property no function can work around. A script that holds the token itself should register it once, in its own shell: ```bash token="$(dybatpho::forge_token)" dybatpho::secret_register "${token}" ``` The module never logs the token, so this matters for what the calling script does with it rather than for the requests made here.
- [`dybatpho::forge_request`](#dybatphoforge_request) — Make an authenticated request against the forge API. The path is relative to the project, so callers write `issues` rather than repeating the API base and the project identifier on every call.
- [`dybatpho::forge_error`](#dybatphoforge_error) — Print what the forge said about the last failed request. A forge refuses a request for a reason, and puts the reason in the response body: which field was missing, that the token cannot see this repository, that a release already exists for the tag. Reporting only `HTTP 422` throws that away and leaves a bad field, an expired token and a rate limit looking identical. The status is always included, because the body is not guaranteed to be JSON, or to be there at all.
- [`dybatpho::forge_issue_find`](#dybatphoforge_issue_find) — Print the number of an open issue whose title matches exactly. GitLab can filter server-side; GitHub cannot search titles on the issues endpoint, so the open issues are compared here. Both are exact matches, so "Build failing" never collides with "Build failing on macOS".
- [`dybatpho::forge_issue_create`](#dybatphoforge_issue_create) — Open an issue and print its number.
- [`dybatpho::forge_issue_comment`](#dybatphoforge_issue_comment) — Add a comment to an existing issue.
- [`dybatpho::forge_issue_report`](#dybatphoforge_issue_report) — Report something once, then keep reporting to the same issue. A script that runs on a schedule should not open a new issue on every failure. This opens one the first time and comments on it afterwards, and says in its output which of the two it did so a pipeline can react.
- [`dybatpho::forge_issue_url`](#dybatphoforge_issue_url) — Print the browser URL of an issue.
- [`dybatpho::forge_release_find`](#dybatphoforge_release_find) — Print the identifier of the release for a tag. GitHub assets are attached by numeric release id; GitLab addresses a release by its tag. Each forge returns the identifier its own upload step needs.
- [`dybatpho::forge_release_create`](#dybatphoforge_release_create) — Create a release for a tag and print its identifier. The tag must already exist on the forge; this publishes the release that points at it rather than creating the tag.
- [`dybatpho::forge_release_upload`](#dybatphoforge_release_upload) — Attach a file to an existing release and print its URL. The two forges do genuinely different things here. GitHub stores the asset itself, on a separate upload host. GitLab stores nothing on a release: the file goes to the project's generic package registry and the release gains a link pointing at it. Both end with the file reachable from the release page.

<a id="usage"></a>
## 🚀 Usage

### When to use this module

Use `forge.sh` when you want to:

- publish the artifacts `release.sh` produced
- report a CI failure without opening the same issue on every run
- read release metadata back out of the forge

### Common patterns

#### Publish what `release.sh` built

```bash
. dybatpho/init.sh --modules release forge
export GITHUB_TOKEN="ghp_..."

version="$(dybatpho::release_next_version)"
dybatpho::release_package "dist" "v${version}" linux amd64
dybatpho::forge_release_create "v${version}" "v${version}" "$(dybatpho::release_changelog)"
dybatpho::forge_release_upload "v${version}" "dist/app-v${version}-linux-amd64.tar.gz"
```

#### Report a failure once, then keep commenting on it

```bash
dybatpho::forge_issue_report \
  "Nightly build is failing" \
  "Run ${CI_RUN_URL} failed at $(dybatpho::date_now)" \
  "ci"
```

The first run opens the issue; every run after that adds a comment to the
one that is already open. The JSON it prints says which of the two happened,
so a pipeline can branch on it:

```bash
result="$(dybatpho::forge_issue_report "$title" "$body")"
if [[ "$(dybatpho::json_get "${result}" '.action')" == "created" ]]; then
  dybatpho::notify_slack "New failure: $(dybatpho::json_get "${result}" '.url')"
fi
```

#### Point at a self-hosted forge

Detection follows the remote, so normally nothing is needed. Override it
when the remote is a mirror, or when the host name gives nothing away:

```bash
export DYBATPHO_FORGE=gitlab
export DYBATPHO_FORGE_API="https://git.internal/api/v4"
export DYBATPHO_FORGE_TOKEN="glpat-..."
```

<a id="see-also"></a>
## 🔗 See also

- [example/forge_ops.sh](../example/forge_ops.sh)
- [src/release.sh](../src/release.sh)
- [src/git.sh](../src/git.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::forge_request`

- Honors `DRY_RUN`, so a publishing script can be rehearsed safely

<a id="reference"></a>
## 📚 Reference

### `dybatpho::forge_host`

Print the host of the configured remote.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default `DYBATPHO_FORGE_REMOTE` |
| `$2` | string | Optional repository path, default `.` |

**📤 Output on stdout**

- Host name

**🚦 Exit codes**

- `1`: The remote has no URL


---

### `dybatpho::forge_kind`

Print which forge the repository is hosted on.
`DYBATPHO_FORGE` wins when set, so a mirror or an unrecognizable host name
never has to be guessed at.

**🧪 Example**

```bash
case "$(dybatpho::forge_kind)" in
  github) ... ;;
  gitlab) ... ;;
esac

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default `DYBATPHO_FORGE_REMOTE` |
| `$2` | string | Optional repository path, default `.` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORGE`** | string | Forced forge kind |

**📤 Output on stdout**

- `github` or `gitlab`

**🚦 Exit codes**

- `1`: The host matches neither forge and `DYBATPHO_FORGE` is unset


---

### `dybatpho::forge_repo`

Print the `owner/repo` the remote points at.
A GitLab project may be nested in subgroups, so everything after the host is
kept rather than only the last two segments.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default `DYBATPHO_FORGE_REMOTE` |
| `$2` | string | Optional repository path, default `.` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORGE_REPO`** | string | Override the detected value |

**📤 Output on stdout**

- `owner/repo`, or `group/subgroup/repo` on GitLab

**🚦 Exit codes**

- `1`: The remote URL carries no path


---

### `dybatpho::forge_api`

Print the API base URL for the repository's forge.
`github.com` answers on a separate API host; every other GitHub is an
Enterprise install serving `/api/v3` from the same host. GitLab always
serves `/api/v4` from its own host.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional remote name, default `DYBATPHO_FORGE_REMOTE` |
| `$2` | string | Optional repository path, default `.` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORGE_API`** | string | Override the computed value |

**📤 Output on stdout**

- API base URL, without a trailing slash
  this module have no remote of their own to pass and rely on the defaults


---

### `dybatpho::forge_token`

Print the token used to authenticate against the forge.
The token is registered with `secret.sh` before it is returned, so a later
log line containing it is masked instead.

That registration only reaches the shell this function runs in. Capturing
the token with `token="$(dybatpho::forge_token)"` runs it in a subshell,
which takes the registration with it when it exits — a Bash property no
function can work around. A script that holds the token itself should
register it once, in its own shell:

```bash
token="$(dybatpho::forge_token)"
dybatpho::secret_register "${token}"
```

The module never logs the token, so this matters for what the calling
script does with it rather than for the requests made here.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional forge kind, detected when omitted |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_FORGE_TOKEN`** | string | Checked first, whatever the forge |
| **`GITHUB_TOKEN`** | string | GitHub token, with `GH_TOKEN` as a fallback |
| **`GITLAB_TOKEN`** | string | GitLab token, with `CI_JOB_TOKEN` as a fallback |

**📤 Output on stdout**

- The token

**🚦 Exit codes**

- `1`: No token is set for this forge


---

### `dybatpho::forge_request`

Make an authenticated request against the forge API.
The path is relative to the project, so callers write `issues` rather than
repeating the API base and the project identifier on every call.

**🧪 Example**

```bash
local body
dybatpho::create_temp body ".json"
dybatpho::forge_request GET "issues?state=open" "" "${body}"
dybatpho::json_get "$(< "${body}")" '.[0].title'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | HTTP method |
| `$2` | string | Path relative to the project, or an absolute URL |
| `$3` | string | Optional JSON request body |
| `$4` | string | Optional file the response body is written to, default `/dev/null` |
| `$@` | string | Additional curl options |

**🧩 Variable sets**

- **`DYBATPHO_HTTP_STATUS`** (The): response status code

**🚦 Exit codes**

- `0`: The forge answered with a 2xx status
- `4`: The forge answered with a 4xx status
- `5`: The forge answered with a 5xx status


---

### `dybatpho::forge_error`

Print what the forge said about the last failed request.

A forge refuses a request for a reason, and puts the reason in the response
body: which field was missing, that the token cannot see this repository,
that a release already exists for the tag. Reporting only `HTTP 422` throws
that away and leaves a bad field, an expired token and a rate limit looking
identical.

The status is always included, because the body is not guaranteed to be
JSON, or to be there at all.

**🧪 Example**

```bash
dybatpho::forge_request POST "issues" "${payload}" "${response}" \
  || dybatpho::die "Could not create issue: $(dybatpho::forge_error "${response}")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Response body file, defaulting to the last one parsed |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_HTTP_STATUS`** | string | Status of the last request |
| **`DYBATPHO_HTTP_BODY_FILE`** | string | Body file of the last request |

**📤 Output on stdout**

- The forge's own message when there is one, prefixed with the status

**🚦 Exit codes**

- `0`: Always


---

### `dybatpho::forge_issue_find`

Print the number of an open issue whose title matches exactly.
GitLab can filter server-side; GitHub cannot search titles on the issues
endpoint, so the open issues are compared here. Both are exact matches, so
"Build failing" never collides with "Build failing on macOS".

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Issue title |

**📤 Output on stdout**

- Issue number, or nothing when no open issue has that title

**🚦 Exit codes**

- `0`: A matching issue exists
- `1`: No open issue has that title


---

### `dybatpho::forge_issue_create`

Open an issue and print its number.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Issue title |
| `$2` | string | Issue body |
| `$3` | string | Optional comma-separated labels |

**📤 Output on stdout**

- Number of the created issue

**🚦 Exit codes**

- `1`: The forge rejected the request


---

### `dybatpho::forge_issue_comment`

Add a comment to an existing issue.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Issue number |
| `$2` | string | Comment body |

**🚦 Exit codes**

- `1`: The forge rejected the request


---

### `dybatpho::forge_issue_report`

Report something once, then keep reporting to the same issue.
A script that runs on a schedule should not open a new issue on every
failure. This opens one the first time and comments on it afterwards, and
says in its output which of the two it did so a pipeline can react.

**🧪 Example**

```bash
result="$(dybatpho::forge_issue_report "Nightly build failing" "${log_url}" ci)"
dybatpho::json_get "${result}" '.action'   # created | commented

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Issue title, also the identity used to find an existing issue |
| `$2` | string | Body of the issue or of the comment |
| `$3` | string | Optional comma-separated labels, applied only when creating |

**📤 Output on stdout**

- JSON object with `action`, `number` and `url`

**🚦 Exit codes**

- `1`: The forge rejected the request


---

### `dybatpho::forge_issue_url`

Print the browser URL of an issue.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Issue number |

**📤 Output on stdout**

- Issue URL


---

### `dybatpho::forge_release_find`

Print the identifier of the release for a tag.
GitHub assets are attached by numeric release id; GitLab addresses a release
by its tag. Each forge returns the identifier its own upload step needs.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tag name |

**📤 Output on stdout**

- Release id on GitHub, tag name on GitLab

**🚦 Exit codes**

- `0`: A release exists for the tag
- `1`: No release exists for the tag


---

### `dybatpho::forge_release_create`

Create a release for a tag and print its identifier.
The tag must already exist on the forge; this publishes the release that
points at it rather than creating the tag.

**🧪 Example**

```bash
dybatpho::forge_release_create "v1.2.0" "v1.2.0" "$(dybatpho::release_changelog)"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tag name |
| `$2` | string | Optional release title, default is the tag |
| `$3` | string | Optional release notes |
| `$4` | string | Optional `true` to create the release as a draft |

**📝 Notes**

- GitLab has no draft release, so asking for one there is an error rather than a release published by surprise

**📤 Output on stdout**

- Release id on GitHub, tag name on GitLab

**🚦 Exit codes**

- `1`: The forge rejected the request, or a draft was asked of GitLab


---

### `dybatpho::forge_release_upload`

Attach a file to an existing release and print its URL.
The two forges do genuinely different things here. GitHub stores the asset
itself, on a separate upload host. GitLab stores nothing on a release: the
file goes to the project's generic package registry and the release gains a
link pointing at it. Both end with the file reachable from the release page.

**🧪 Example**

```bash
dybatpho::forge_release_upload "v1.2.0" "dist/app-v1.2.0-linux-amd64.tar.gz"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tag name of an existing release |
| `$2` | string | File to attach |

**📤 Output on stdout**

- URL the asset is reachable at

**🚦 Exit codes**

- `1`: The release does not exist, the file does not exist, or the upload failed
