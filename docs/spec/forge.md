# Feature Specification: Forge API Utilities

**Feature Branch**: `[feature-forge]`
**Status**: Implemented
**Input**: Existing source analysis: `src/forge.sh`, `docs/forge.md`, `test/forge.bats`, and `example/forge_ops.sh`

## Problem Statement *(mandatory)*

`git.sh` reads the repository on disk and `release.sh` builds, checksums and
signs artifacts, then stops. Nothing in the library publishes anything, so every
project that uses it ends up writing the same `curl` against the GitHub or
GitLab API: assembling the base URL, encoding the project path, choosing the
auth header, and remembering which forge calls a field `body` and which calls it
`description`.

Those differences are mechanical but unforgiving. A script written against
GitHub does not run against a company GitLab, and a script that reports a CI
failure by opening an issue opens a new one on every single run.

## Business Value *(mandatory)*

- Close the gap between building a release and publishing it.
- Let one script work against GitHub, GitHub Enterprise, GitLab and self-hosted
  GitLab without branching on the forge.
- Make repeated automated reporting idempotent, so a scheduled job does not
  flood a tracker.
- Keep credentials out of logs by routing tokens through `secret.sh`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover where the repository is hosted (Priority: P1)

As a script author, I want the forge, project and API base derived from the Git
remote so that the same script runs wherever the repository lives.

**Independent Test**: Point a throwaway repository at a `git@`, `ssh://` and
`https://` remote on github.com, gitlab.com, a GitHub Enterprise host and a
self-hosted GitLab, and inspect the four detection functions.

**Acceptance Scenarios**:

1. **Given** a remote in any of the three URL forms, **When** `forge_host` is
   called, **Then** the host is returned without scheme, credential or `.git`
2. **Given** a github.com remote, **When** `forge_api` is called, **Then**
   `https://api.github.com` is returned
3. **Given** any other GitHub host, **When** `forge_api` is called, **Then**
   `https://<host>/api/v3` is returned
4. **Given** a GitLab project nested in subgroups, **When** `forge_repo` is
   called, **Then** every path segment after the host is preserved
5. **Given** a host that matches neither forge, **When** `forge_kind` is called,
   **Then** it fails and names `DYBATPHO_FORGE` as the way to resolve it

### User Story 2 - Report a recurring failure once (Priority: P1)

As the author of a scheduled job, I want to report a failure to the tracker
without opening a duplicate issue on every run.

**Independent Test**: Call `forge_issue_report` twice against a stubbed forge
and confirm the first call creates while the second comments.

**Acceptance Scenarios**:

1. **Given** no open issue carries the title, **When** `forge_issue_report` is
   called, **Then** an issue is created and the result reports `created`
2. **Given** an open issue carries the title, **When** `forge_issue_report` is
   called, **Then** a comment is added and the result reports `commented`
3. **Given** either outcome, **When** the call returns, **Then** stdout is a
   JSON object with `action`, `number` and `url`
4. **Given** an open issue titled `Build failing on macOS`, **When**
   `forge_issue_find "Build failing"` is called, **Then** it does not match

### User Story 3 - Publish a release and its artifacts (Priority: P1)

As a release script, I want to create the release for a tag and attach the
artifacts `release.sh` produced.

**Independent Test**: Create a release against a stubbed forge, then upload a
file to it, on both GitHub and GitLab.

**Acceptance Scenarios**:

1. **Given** a tag, **When** `forge_release_create` is called, **Then** the
   release is created and its identifier is printed
2. **Given** a GitHub release, **When** `forge_release_upload` is called,
   **Then** the asset is sent to the upload host and its download URL is printed
3. **Given** a GitLab release, **When** `forge_release_upload` is called,
   **Then** the file is stored as a generic package and linked to the release
4. **Given** a tag with no release, **When** `forge_release_upload` is called,
   **Then** it fails and says the release must be created first

### Example Workflow

```bash
. dybatpho/init.sh --modules release forge
export GITHUB_TOKEN="ghp_..."

version="$(dybatpho::release_next_version)"
dybatpho::release_package "dist" "v${version}" linux amd64
dybatpho::forge_release_create "v${version}" "v${version}" "$(dybatpho::release_changelog)"
dybatpho::forge_release_upload "v${version}" "dist/app-v${version}-linux-amd64.tar.gz"
```

## Edge Cases

- A remote URL carrying `user@host` must not leak the credential into the host.
- A remote URL with a trailing slash or `.git` suffix must normalize identically.
- A GitLab project path must be URL-encoded when it appears in an API path, and
  must not be encoded when it appears in a browser URL.
- `DYBATPHO_FORGE` set to anything other than `github` or `gitlab` is an error
  rather than a silent fallback.
- An issue title that is a prefix of another open issue's title must not match.
- A token registered inside a command substitution does not survive it; this is
  a property of Bash subshells and is documented rather than worked around.
- Every request honors `DRY_RUN`, so a publishing script can be rehearsed.
- A GitLab asset uploads but linking it to the release is refused.
- A request made by the module resolves its own token: that registration must
  stay in the calling shell, so the script's later log lines mask the token.
- Every value the remote would answer is overridden, so no checkout is needed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST detect the forge from the configured Git remote,
  and MUST let `DYBATPHO_FORGE` override detection.
- **FR-002**: The module MUST normalize `git@host:path`, `ssh://git@host/path`
  and `https://host/path` remotes to the same `host/owner/repo`.
- **FR-003**: `dybatpho::forge_api` MUST return `https://api.github.com` for
  github.com, `https://<host>/api/v3` for any other GitHub, and
  `https://<host>/api/v4` for GitLab, and MUST honor `DYBATPHO_FORGE_API`.
- **FR-004**: `dybatpho::forge_repo` MUST preserve nested GitLab group paths and
  MUST honor `DYBATPHO_FORGE_REPO`.
- **FR-005**: `dybatpho::forge_token` MUST prefer `DYBATPHO_FORGE_TOKEN`, then
  `GITHUB_TOKEN`/`GH_TOKEN` or `GITLAB_TOKEN`/`CI_JOB_TOKEN` by forge, MUST
  register the token with `secret.sh`, and MUST name the variables to set when
  none is.
- **FR-006**: `dybatpho::forge_request` MUST resolve a project-relative path to
  a full API URL, MUST pass an absolute URL through unchanged, MUST send the
  auth header the forge expects, and MUST send a JSON content type only when a
  body is supplied.
- **FR-007**: The module MUST address a GitLab project by its URL-encoded path
  and a GitHub repository as `repos/owner/name`.
- **FR-008**: `dybatpho::forge_issue_find` MUST match a title exactly and MUST
  read `number` on GitHub and `iid` on GitLab.
- **FR-009**: `dybatpho::forge_issue_create` MUST send `body` on GitHub and
  `description` on GitLab, and MUST send labels as a JSON array on GitHub and as
  a comma-separated string on GitLab.
- **FR-010**: `dybatpho::forge_issue_report` MUST create when no open issue
  carries the title, MUST comment otherwise, and MUST print a JSON object with
  `action`, `number` and `url`.
- **FR-011a**: `dybatpho::forge_release_create` MUST accept a draft flag, MUST
  set `draft` on GitHub when it is given, MUST omit the field otherwise, and
  MUST fail on GitLab rather than publish a release that was asked to be a
  draft, because GitLab has no draft release.
- **FR-011**: `dybatpho::forge_release_find` MUST print the identifier the
  forge's own upload step needs: the numeric id on GitHub, the tag on GitLab.
- **FR-012**: `dybatpho::forge_release_upload` MUST refuse a missing file and a
  tag with no release, MUST send GitHub assets to the upload host, and MUST
  store GitLab assets as a generic package and then link them to the release.
- **FR-013**: Every failing request MUST fail the calling function with a
  message naming the operation and the HTTP status.
- **FR-014**: A failed request MUST report what the forge said about it, not
  only the HTTP status, so a bad field, an expired token and a rate limit are
  told apart. The status MUST still be included, because a body is not
  guaranteed to be present or to be JSON.
- **FR-015**: When a GitLab asset uploads but linking it to the release fails,
  the error MUST carry the link request's own message, never the upload's.
- **FR-016**: A request MUST resolve the forge, its project and its token in the
  calling shell: the token MUST stay registered with `secret.sh` afterwards, the
  remote MUST be read at most once per request and not at all when
  `DYBATPHO_FORGE`, `DYBATPHO_FORGE_REPO` and `DYBATPHO_FORGE_API` answer it, and
  a remote, forge or token that can't be resolved MUST stop the script.
- **FR-017**: `forge_issue_report` MUST fail when the forge refuses to open the issue, instead of reporting an issue with no number.

### Key Entities *(include if feature involves data)*

- **Forge kind**: `github` or `gitlab`; selects every path, field name and
  header that differs between the two.
- **Project identifier**: `owner/repo`, possibly with nested groups; encoded
  differently for API paths and browser URLs.
- **Issue report result**: JSON object with `action` (`created` or
  `commented`), `number` and `url`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script that publishes a release runs unchanged against GitHub,
  GitHub Enterprise, GitLab and self-hosted GitLab.
- **SC-002**: A scheduled job reporting the same failure repeatedly produces
  exactly one issue.
- **SC-003**: Detection produces the same `host/owner/repo` for all three remote
  URL forms of the same repository.
- **SC-004**: No function in the module writes a token to stdout, stderr or a
  log file.

## Integration Tests *(mandatory)*

- **IT-001**: `dybatpho::forge_host` reads the host out of every remote URL form.
- **IT-002**: `dybatpho::forge_kind` detects both forges and honors the override.
- **IT-003**: `dybatpho::forge_kind` rejects an override that names no forge.
- **IT-004**: `dybatpho::forge_repo` keeps nested GitLab groups and honors the override.
- **IT-005**: `dybatpho::forge_api` points at the right base for each forge.
- **IT-006**: `dybatpho::forge_token` prefers `DYBATPHO_FORGE_TOKEN` and falls back per forge.
- **IT-007**: `dybatpho::forge_token` names the variables to set when none is set.
- **IT-008**: `dybatpho::forge_token` registers in its own shell but not through a command substitution.
- **IT-009**: `dybatpho::forge_request` builds a GitHub URL and sends a bearer token.
- **IT-010**: `dybatpho::forge_request` URL-encodes the project path on GitLab.
- **IT-011**: `dybatpho::forge_request` sends a JSON body only when one is given.
- **IT-012**: `dybatpho::forge_request` passes an absolute URL through untouched.
- **IT-013**: `dybatpho::forge_issue_find` matches a title exactly, not by prefix.
- **IT-014**: `dybatpho::forge_issue_create` posts the field names and label shape of each forge.
- **IT-015**: `dybatpho::forge_issue_comment` posts to the endpoint each forge uses.
- **IT-016**: `dybatpho::forge_issue_report` creates when nothing is open and comments otherwise.
- **IT-017**: `dybatpho::forge_issue_url` points at the browser path of each forge.
- **IT-018**: `dybatpho::forge_release_find` returns the identifier each forge needs.
- **IT-019**: `dybatpho::forge_release_create` posts the field names of each forge.
- **IT-019a**: `dybatpho::forge_release_create` drafts on GitHub when asked, does not by default, and refuses on GitLab.
- **IT-020**: `dybatpho::forge_release_upload` sends the asset to the GitHub upload host.
- **IT-021**: `dybatpho::forge_release_upload` stores and links a GitLab generic package.
- **IT-022**: `dybatpho::forge_release_upload` refuses a missing file or a missing release.
- **IT-023**: Verify the forge's message and field-level detail are reported
  for a 422, for both forges' wordings, and that a missing or non-JSON body
  falls back to the status.
- **IT-024**: Verify a GitLab upload whose link request is refused with a 403
  reports the link's message and not the successful upload's.
- **IT-025**: Verify a request leaves its token masked in the calling shell, reads
  the remote no more than one read takes, reads it not at all when every value
  is overridden, and stops on a remote, a host or an override it can't use.
- **IT-026**: Report an issue whose creation the forge refuses with HTTP 403, and fail without printing a created report.

## Acceptance Criteria *(mandatory)*

- All functional requirements are implemented in `src/forge.sh`.
- Every integration test above corresponds to a case in `test/forge.bats`.
- `example/forge_ops.sh` runs offline, against a stubbed forge and a throwaway
  repository, and demonstrates every public function.
- `docs/forge.md` is generated from the source and documents every public
  function and environment variable.
