# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file forge.sh
# @brief Utilities for talking to the forge a repository is hosted on
# @namespace dybatpho
# @description
#   `git.sh` reads the repository on disk and `release.sh` builds, checksums and
#   signs artifacts — and then stops. Nothing in the library publishes anything.
#   This module closes that gap: it turns a Git remote into an authenticated API
#   client for the forge behind it, and exposes the two things a release or CI
#   script actually needs from one — issues and releases.
#
#   **GitHub** (including GitHub Enterprise) and **GitLab** (including
#   self-hosted) are both supported. The forge is detected from the remote URL,
#   so a script that works against `github.com` works against a company GitLab
#   without changing a line. Everything that differs between the two — the API
#   base, the auth header, how a project is addressed in a path, and what the
#   fields are called — is resolved behind the public functions.
#
#   Tokens are read from the environment and registered with `secret.sh`, so a
#   token can never reach a log line even when a request is traced.
#
# @usage
#   ### When to use this module
#
#   Use `forge.sh` when you want to:
#
#   - publish the artifacts `release.sh` produced
#   - report a CI failure without opening the same issue on every run
#   - read release metadata back out of the forge
#
#   ### Common patterns
#
#   #### Publish what `release.sh` built
#
#   ```bash
#   . dybatpho/init.sh --modules release forge
#   export GITHUB_TOKEN="ghp_..."
#
#   version="$(dybatpho::release_next_version)"
#   dybatpho::release_package "dist" "v${version}" linux amd64
#   dybatpho::forge_release_create "v${version}" "v${version}" "$(dybatpho::release_changelog)"
#   dybatpho::forge_release_upload "v${version}" "dist/app-v${version}-linux-amd64.tar.gz"
#   ```
#
#   #### Report a failure once, then keep commenting on it
#
#   ```bash
#   dybatpho::forge_issue_report \
#     "Nightly build is failing" \
#     "Run ${CI_RUN_URL} failed at $(dybatpho::date_now)" \
#     "ci"
#   ```
#
#   The first run opens the issue; every run after that adds a comment to the
#   one that is already open. The JSON it prints says which of the two happened,
#   so a pipeline can branch on it:
#
#   ```bash
#   result="$(dybatpho::forge_issue_report "$title" "$body")"
#   if [[ "$(dybatpho::json_get "${result}" '.action')" == "created" ]]; then
#     dybatpho::notify_slack "New failure: $(dybatpho::json_get "${result}" '.url')"
#   fi
#   ```
#
#   #### Point at a self-hosted forge
#
#   Detection follows the remote, so normally nothing is needed. Override it
#   when the remote is a mirror, or when the host name gives nothing away:
#
#   ```bash
#   export DYBATPHO_FORGE=gitlab
#   export DYBATPHO_FORGE_API="https://git.internal/api/v4"
#   export DYBATPHO_FORGE_TOKEN="glpat-..."
#   ```
#
# @see
#   - `example/forge_ops.sh`
#   - `src/release.sh`
#   - `src/git.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_FORGE string Force the forge kind, `github` or `gitlab`, instead of detecting it
# @env DYBATPHO_FORGE_REMOTE string Git remote the forge is detected from, default `origin`
# @env DYBATPHO_FORGE_API string Override the API base URL, for a forge on a path detection cannot guess
# @env DYBATPHO_FORGE_REPO string Override the detected `owner/repo`
# @env DYBATPHO_FORGE_TOKEN string Token to authenticate with, preferred over the per-forge variables
DYBATPHO_FORGE="${DYBATPHO_FORGE:-}"
DYBATPHO_FORGE_REMOTE="${DYBATPHO_FORGE_REMOTE:-origin}"
DYBATPHO_FORGE_API="${DYBATPHO_FORGE_API:-}"
DYBATPHO_FORGE_REPO="${DYBATPHO_FORGE_REPO:-}"
DYBATPHO_FORGE_TOKEN="${DYBATPHO_FORGE_TOKEN:-}"

#######################################
# @description Normalize a Git remote URL into `host/owner/repo`.
#   Handles the three forms a remote takes — `git@host:owner/repo.git`,
#   `ssh://git@host/owner/repo.git` and `https://host/owner/repo.git` — so the
#   rest of the module never has to care which one a checkout uses.
# @arg $1 string Remote URL
# @stdout `host/owner/repo`
# @internal
#######################################
function __dybatpho_forge_normalize_url {
  local url
  dybatpho::expect_args url -- "$@"

  url="${url%.git}"
  url="${url%/}"
  case "${url}" in
    # The `host:owner/repo` separator becomes a `/` before the scheme is
    # stripped, otherwise the colon of `https:` is the one that matches first.
    git@*) url="${url#git@}" && url="${url/://}" ;;
    ssh://git@*) url="${url#ssh://git@}" ;;
    ssh://*) url="${url#ssh://}" ;;
    https://*) url="${url#https://}" ;;
    http://*) url="${url#http://}" ;;
    *) ;;
  esac
  # A URL may carry `user@host`; the credential is not part of the identity.
  url="${url#*@}"
  printf '%s\n' "${url}"
}

#######################################
# @description Print the host of the configured remote.
# @arg $1 string Optional remote name, default `DYBATPHO_FORGE_REMOTE`
# @arg $2 string Optional repository path, default `.`
# @stdout Host name
# @exitcode 1 The remote has no URL
#######################################
function dybatpho::forge_host {
  local remote="${1:-${DYBATPHO_FORGE_REMOTE}}" repo_path="${2:-.}"
  local url
  url="$(dybatpho::git_remote_url "${remote}" "${repo_path}")" \
    || dybatpho::die "No URL for remote '${remote}'"
  url="$(__dybatpho_forge_normalize_url "${url}")"
  printf '%s\n' "${url%%/*}"
}

#######################################
# @description Print which forge the repository is hosted on.
#   `DYBATPHO_FORGE` wins when set, so a mirror or an unrecognizable host name
#   never has to be guessed at.
# @example
#   case "$(dybatpho::forge_kind)" in
#     github) ... ;;
#     gitlab) ... ;;
#   esac
#
# @arg $1 string Optional remote name, default `DYBATPHO_FORGE_REMOTE`
# @arg $2 string Optional repository path, default `.`
# @env DYBATPHO_FORGE string Forced forge kind
# @stdout `github` or `gitlab`
# @exitcode 1 The host matches neither forge and `DYBATPHO_FORGE` is unset
#######################################
function dybatpho::forge_kind {
  if [[ -n "${DYBATPHO_FORGE}" ]]; then
    case "${DYBATPHO_FORGE}" in
      github | gitlab)
        printf '%s\n' "${DYBATPHO_FORGE}"
        return 0
        ;;
      *) dybatpho::die "DYBATPHO_FORGE must be 'github' or 'gitlab', got '${DYBATPHO_FORGE}'" ;;
    esac
  fi

  local host
  host="$(dybatpho::forge_host "$@")"
  case "${host}" in
    github.com | github.*) printf 'github\n' ;;
    gitlab.com | gitlab.*) printf 'gitlab\n' ;;
    *)
      dybatpho::die "Cannot tell which forge '${host}' is; set DYBATPHO_FORGE to 'github' or 'gitlab'"
      ;;
  esac
}

#######################################
# @description Print the `owner/repo` the remote points at.
#   A GitLab project may be nested in subgroups, so everything after the host is
#   kept rather than only the last two segments.
# @arg $1 string Optional remote name, default `DYBATPHO_FORGE_REMOTE`
# @arg $2 string Optional repository path, default `.`
# @env DYBATPHO_FORGE_REPO string Override the detected value
# @stdout `owner/repo`, or `group/subgroup/repo` on GitLab
# @exitcode 1 The remote URL carries no path
#######################################
function dybatpho::forge_repo {
  if [[ -n "${DYBATPHO_FORGE_REPO}" ]]; then
    printf '%s\n' "${DYBATPHO_FORGE_REPO}"
    return 0
  fi

  local remote="${1:-${DYBATPHO_FORGE_REMOTE}}" repo_path="${2:-.}"
  local url
  url="$(dybatpho::git_remote_url "${remote}" "${repo_path}")" \
    || dybatpho::die "No URL for remote '${remote}'"
  url="$(__dybatpho_forge_normalize_url "${url}")"

  local project="${url#*/}"
  [[ "${project}" != "${url}" && -n "${project}" ]] \
    || dybatpho::die "Remote '${remote}' has no owner/repo path: ${url}"
  printf '%s\n' "${project}"
}

#######################################
# @description Print the API base URL for the repository's forge.
#   `github.com` answers on a separate API host; every other GitHub is an
#   Enterprise install serving `/api/v3` from the same host. GitLab always
#   serves `/api/v4` from its own host.
# @arg $1 string Optional remote name, default `DYBATPHO_FORGE_REMOTE`
# @arg $2 string Optional repository path, default `.`
# @env DYBATPHO_FORGE_API string Override the computed value
# @stdout API base URL, without a trailing slash
#######################################
# shellcheck disable=SC2120 # the remote and path are optional; callers inside
#   this module have no remote of their own to pass and rely on the defaults
function dybatpho::forge_api {
  if [[ -n "${DYBATPHO_FORGE_API}" ]]; then
    printf '%s\n' "${DYBATPHO_FORGE_API%/}"
    return 0
  fi

  local kind host api
  kind="$(dybatpho::forge_kind "$@")"
  host="$(dybatpho::forge_host "$@")"
  __dybatpho_forge_api_for_into api "${kind}" "${host}"
  printf '%s\n' "${api}"
}

#######################################
# @description Print the token used to authenticate against the forge.
#   The token is registered with `secret.sh` before it is returned, so a later
#   log line containing it is masked instead.
#
#   That registration only reaches the shell this function runs in. Capturing
#   the token with `token="$(dybatpho::forge_token)"` runs it in a subshell,
#   which takes the registration with it when it exits — a Bash property no
#   function can work around. A script that holds the token itself should
#   register it once, in its own shell:
#
#   ```bash
#   token="$(dybatpho::forge_token)"
#   dybatpho::secret_register "${token}"
#   ```
#
#   The module never logs the token, so this matters for what the calling
#   script does with it rather than for the requests made here.
# @arg $1 string Optional forge kind, detected when omitted
# @env DYBATPHO_FORGE_TOKEN string Checked first, whatever the forge
# @env GITHUB_TOKEN string GitHub token, with `GH_TOKEN` as a fallback
# @env GITLAB_TOKEN string GitLab token, with `CI_JOB_TOKEN` as a fallback
# @stdout The token
# @exitcode 1 No token is set for this forge
#######################################
function dybatpho::forge_token {
  local kind="${1:-}"
  if [[ -z "${kind}" ]]; then
    local -A context=()
    __dybatpho_forge_context_into context
    kind="${context[kind]}"
  fi
  local token
  __dybatpho_forge_token_into token "${kind}"
  printf '%s\n' "${token}"
}

#######################################
# @description Resolve the forge token into a variable, registered with
#   `secret.sh` in the caller's own shell.
#   Resolving it here rather than through `dybatpho::forge_token` is what keeps
#   the registration: a command substitution takes it away when it exits, which
#   left every request this module made with its token unmasked afterwards.
# @arg $1 string Name of the variable receiving the token
# @arg $2 string Forge kind
# @set The named variable
# @exitcode 1 Stop the script when no token is set for this forge
# @internal
#######################################
function __dybatpho_forge_token_into {
  local -n __dybatpho_forge_token_out="$1"
  local __dybatpho_forge_token_kind="$2"
  local __dybatpho_forge_token_value="${DYBATPHO_FORGE_TOKEN}"
  if [[ -z "${__dybatpho_forge_token_value}" ]]; then
    case "${__dybatpho_forge_token_kind}" in
      github) __dybatpho_forge_token_value="${GITHUB_TOKEN:-${GH_TOKEN:-}}" ;;
      gitlab) __dybatpho_forge_token_value="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}" ;;
      *) ;;
    esac
  fi

  if [[ -z "${__dybatpho_forge_token_value}" ]]; then
    local __dybatpho_forge_token_vars
    __dybatpho_forge_token_vars=$(__dybatpho_forge_token_vars "${__dybatpho_forge_token_kind}")
    dybatpho::die "No ${__dybatpho_forge_token_kind} token. Set DYBATPHO_FORGE_TOKEN, or ${__dybatpho_forge_token_vars}"
  fi

  dybatpho::secret_register "${__dybatpho_forge_token_value}"
  __dybatpho_forge_token_out="${__dybatpho_forge_token_value}"
}

#######################################
# @description Resolve what a forge call needs in one pass, in the caller's shell.
#   Asking `forge_kind`, `forge_repo`, `forge_api` and `forge_host` separately
#   read the remote four times per request, each through command substitutions
#   that also swallowed their own fatal errors. Here the remote is read at most
#   once, and not at all when every value it would answer is overridden.
#   `kind` is always resolved; the other fields only when asked for.
# @arg $1 string Name of the associative array receiving the fields
# @arg $@ string Fields wanted besides `kind`: `host`, `repo`, `api`, `token`
# @set The named array: `kind`, and `host`, `repo`, `api`, `token` as asked
# @exitcode 1 Stop the script when the remote, the forge or the token can't be resolved
# @internal
#######################################
function __dybatpho_forge_context_into {
  local -n __dybatpho_forge_ctx="$1"
  shift
  local __dybatpho_forge_ctx_want=" $* "
  local __dybatpho_forge_ctx_remote="${DYBATPHO_FORGE_REMOTE}"

  case "${DYBATPHO_FORGE}" in
    "" | github | gitlab) ;;
    *) dybatpho::die "DYBATPHO_FORGE must be 'github' or 'gitlab', got '${DYBATPHO_FORGE}'" ;;
  esac

  # The remote is read only when something it answers is not overridden.
  local __dybatpho_forge_ctx_url=""
  if [[ -z "${DYBATPHO_FORGE}" || "${__dybatpho_forge_ctx_want}" == *" host "* ]] \
    || [[ "${__dybatpho_forge_ctx_want}" == *" repo "* && -z "${DYBATPHO_FORGE_REPO}" ]] \
    || [[ "${__dybatpho_forge_ctx_want}" == *" api "* && -z "${DYBATPHO_FORGE_API}" ]]; then
    __dybatpho_forge_ctx_url="$(dybatpho::git_remote_url "${__dybatpho_forge_ctx_remote}" .)" \
      || dybatpho::die "No URL for remote '${__dybatpho_forge_ctx_remote}'"
    __dybatpho_forge_ctx_url="$(__dybatpho_forge_normalize_url "${__dybatpho_forge_ctx_url}")"
    __dybatpho_forge_ctx[host]="${__dybatpho_forge_ctx_url%%/*}"
  fi

  if [[ -n "${DYBATPHO_FORGE}" ]]; then
    __dybatpho_forge_ctx[kind]="${DYBATPHO_FORGE}"
  else
    case "${__dybatpho_forge_ctx[host]}" in
      github.com | github.*) __dybatpho_forge_ctx[kind]=github ;;
      gitlab.com | gitlab.*) __dybatpho_forge_ctx[kind]=gitlab ;;
      *)
        local __dybatpho_forge_ctx_hint="set DYBATPHO_FORGE to 'github' or 'gitlab'"
        dybatpho::die "Cannot tell which forge '${__dybatpho_forge_ctx[host]}' is; ${__dybatpho_forge_ctx_hint}"
        ;;
    esac
  fi

  if [[ "${__dybatpho_forge_ctx_want}" == *" repo "* ]]; then
    if [[ -n "${DYBATPHO_FORGE_REPO}" ]]; then
      __dybatpho_forge_ctx[repo]="${DYBATPHO_FORGE_REPO}"
    else
      local __dybatpho_forge_ctx_project="${__dybatpho_forge_ctx_url#*/}"
      [[ "${__dybatpho_forge_ctx_project}" != "${__dybatpho_forge_ctx_url}" &&
        -n "${__dybatpho_forge_ctx_project}" ]] \
        || dybatpho::die "Remote '${__dybatpho_forge_ctx_remote}' has no owner/repo path: ${__dybatpho_forge_ctx_url}"
      __dybatpho_forge_ctx[repo]="${__dybatpho_forge_ctx_project}"
    fi
  fi

  if [[ "${__dybatpho_forge_ctx_want}" == *" api "* ]]; then
    if [[ -n "${DYBATPHO_FORGE_API}" ]]; then
      __dybatpho_forge_ctx[api]="${DYBATPHO_FORGE_API%/}"
    else
      local __dybatpho_forge_ctx_api
      __dybatpho_forge_api_for_into __dybatpho_forge_ctx_api \
        "${__dybatpho_forge_ctx[kind]}" "${__dybatpho_forge_ctx[host]}"
      __dybatpho_forge_ctx[api]="${__dybatpho_forge_ctx_api}"
    fi
  fi

  if [[ "${__dybatpho_forge_ctx_want}" == *" token "* ]]; then
    local __dybatpho_forge_ctx_token
    __dybatpho_forge_token_into __dybatpho_forge_ctx_token "${__dybatpho_forge_ctx[kind]}"
    __dybatpho_forge_ctx[token]="${__dybatpho_forge_ctx_token}"
  fi
}

#######################################
# @description Work out the API base URL of a forge from its kind and host.
#   `github.com` answers on a separate API host; every other GitHub is an
#   Enterprise install serving `/api/v3` from the same host. GitLab always
#   serves `/api/v4` from its own host.
# @arg $1 string Name of the variable receiving the URL
# @arg $2 string Forge kind
# @arg $3 string Host
# @set The named variable
# @internal
#######################################
function __dybatpho_forge_api_for_into {
  local -n __dybatpho_forge_api_out="$1"
  case "$2" in
    github)
      if [[ "$3" == "github.com" ]]; then
        __dybatpho_forge_api_out="https://api.github.com"
      else
        __dybatpho_forge_api_out="https://$3/api/v3"
      fi
      ;;
    gitlab) __dybatpho_forge_api_out="https://$3/api/v4" ;;
    *) ;;
  esac
}

#######################################
# @description Name the environment variables a forge reads its token from.
# @arg $1 string Forge kind
# @stdout Human-readable list for an error message
# @internal
#######################################
function __dybatpho_forge_token_vars {
  local kind
  dybatpho::expect_args kind -- "$@"
  case "${kind}" in
    github) printf 'GITHUB_TOKEN or GH_TOKEN\n' ;;
    gitlab) printf 'GITLAB_TOKEN or CI_JOB_TOKEN\n' ;;
    *) ;;
  esac
}

#######################################
# @description Print the path segment that identifies the project on this forge.
#   GitHub addresses a repository as `repos/owner/name`. GitLab addresses a
#   project by its URL-encoded path, so the separating slashes become `%2F`.
# @arg $1 string Forge kind
# @arg $2 string `owner/repo`
# @stdout Path segment, with no leading or trailing slash
# @internal
#######################################
function __dybatpho_forge_project_path {
  local kind repo
  dybatpho::expect_args kind repo -- "$@"
  case "${kind}" in
    github) printf 'repos/%s\n' "${repo}" ;;
    gitlab)
      local encoded
      encoded=$(dybatpho::url_encode "${repo}")
      printf 'projects/%s\n' "${encoded}"
      ;;
    *) ;;
  esac
}

#######################################
# @description Turn a comma-separated label list into a JSON array.
#   GitHub wants `["a","b"]`; GitLab takes the comma-separated string as-is, so
#   only GitHub needs this.
# @arg $1 string Comma-separated labels
# @stdout JSON array of strings
# @internal
#######################################
function __dybatpho_forge_labels_json {
  local labels
  dybatpho::expect_args labels -- "$@"

  local label separator="" array="["
  local split_output
  split_output=$(dybatpho::split "${labels}" ",")
  while IFS= read -r label || [[ -n "${label}" ]]; do
    label="$(dybatpho::trim "${label}")"
    [[ -n "${label}" ]] || continue
    array+="${separator}$(dybatpho::json_string "${label}")"
    separator=","
  done < <(printf '%s' "${split_output}")
  printf '%s]\n' "${array}"
}

#######################################
# @description Print the authentication header this forge expects.
# @arg $1 string Forge kind
# @arg $2 string Token
# @stdout Header in `Name: value` form
# @internal
#######################################
function __dybatpho_forge_auth_header {
  local kind token
  dybatpho::expect_args kind token -- "$@"
  case "${kind}" in
    github) printf 'Authorization: Bearer %s\n' "${token}" ;;
    gitlab) printf 'PRIVATE-TOKEN: %s\n' "${token}" ;;
    *) ;;
  esac
}

#######################################
# @description Make an authenticated request against the forge API.
#   The path is relative to the project, so callers write `issues` rather than
#   repeating the API base and the project identifier on every call.
# @example
#   local body
#   dybatpho::create_temp body ".json"
#   dybatpho::forge_request GET "issues?state=open" "" "${body}"
#   dybatpho::json_get "$(< "${body}")" '.[0].title'
#
# @arg $1 string HTTP method
# @arg $2 string Path relative to the project, or an absolute URL
# @arg $3 string Optional JSON request body
# @arg $4 string Optional file the response body is written to, default `/dev/null`
# @arg $@ string Additional curl options
# @set DYBATPHO_HTTP_STATUS The response status code
# @exitcode 0 The forge answered with a 2xx status
# @exitcode 4 The forge answered with a 4xx status
# @exitcode 5 The forge answered with a 5xx status
# @tip Honors `DRY_RUN`, so a publishing script can be rehearsed safely
#######################################
function dybatpho::forge_request {
  local method path
  dybatpho::expect_args method path -- "$@"
  local body="${3-}" output="${4:-/dev/null}"
  if (($# > 4)); then
    shift 4
  else
    shift $#
  fi

  # The forge, its token and -- for a relative path -- the project are
  # resolved here, in the caller's shell, so the token stays registered for
  # masking and a remote that can't be read stops the script.
  local -A context=()
  local url
  case "${path}" in
    http://* | https://*)
      __dybatpho_forge_context_into context token
      url="${path}"
      ;;
    *)
      __dybatpho_forge_context_into context token repo api
      url="${context[api]}/$(__dybatpho_forge_project_path "${context[kind]}" "${context[repo]}")/${path#/}"
      ;;
  esac
  local kind="${context[kind]}" token="${context[token]}"

  local -a args=(
    --request "${method}"
    --header "Accept: application/json"
  )

  # The token goes to curl out of band rather than as `--header`, which would
  # publish it in `/proc/<pid>/cmdline` for the life of the request. `local`
  # scoping means it is visible to `dybatpho::curl_do` and gone on return.
  local -a DYBATPHO_CURL_SECRET_HEADERS=(
    "$(__dybatpho_forge_auth_header "${kind}" "${token}")"
  )
  local DYBATPHO_CURL_SECRET_DATA=""
  if [[ -n "${body}" ]]; then
    args+=(--header "Content-Type: application/json")
    # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
    DYBATPHO_CURL_SECRET_DATA="${body}"
  fi

  dybatpho::debug "forge: ${method} ${url}"
  dybatpho::curl_request "${url}" "${output}" "${args[@]}" "$@"
}

#######################################
# @description Print what the forge said about the last failed request.
#
#   A forge refuses a request for a reason, and puts the reason in the response
#   body: which field was missing, that the token cannot see this repository,
#   that a release already exists for the tag. Reporting only `HTTP 422` throws
#   that away and leaves a bad field, an expired token and a rate limit looking
#   identical.
#
#   The status is always included, because the body is not guaranteed to be
#   JSON, or to be there at all.
# @example
#   dybatpho::forge_request POST "issues" "${payload}" "${response}" \
#     || dybatpho::die "Could not create issue: $(dybatpho::forge_error "${response}")"
#
# @arg $1 string Response body file, defaulting to the last one parsed
# @env DYBATPHO_HTTP_STATUS string Status of the last request
# @env DYBATPHO_HTTP_BODY_FILE string Body file of the last request
# @stdout The forge's own message when there is one, prefixed with the status
# @exitcode 0 Always
#######################################
function dybatpho::forge_error {
  local body_file="${1:-${DYBATPHO_HTTP_BODY_FILE:-}}"
  local status_text="HTTP ${DYBATPHO_HTTP_STATUS:-unknown}"

  if [[ -z "${body_file}" ]] || ! dybatpho::is file "${body_file}"; then
    printf '%s\n' "${status_text}"
    return 0
  fi

  local body
  body="$(< "${body_file}")"
  [[ -n "${body// /}" ]] || {
    printf '%s\n' "${status_text}"
    return 0
  }

  local message="" detail=""
  if dybatpho::json_valid "${body}"; then
    # GitHub uses `message`, GitLab uses `message` or `error`.
    message="$(dybatpho::json_get "${body}" \
      '[.message?, .error?, .error_description?] | map(select(. != null and . != "")) | .[0] // ""')"
    # GitHub says which field it did not like in a separate array.
    detail="$(dybatpho::json_get "${body}" \
      '[.errors[]? | [.field?, .code?] | map(select(. != null)) | join(" ")] | join(", ")' 2> /dev/null || true)"
  fi

  if [[ -z "${message}" && -z "${detail}" ]]; then
    # Not JSON, or JSON naming no error: an HTML error page or a proxy's plain
    # text. A little of it is more use than none of it, and all of it is not
    # worth a log line.
    local excerpt
    excerpt=$(dybatpho::string_truncate "${body//$'\n'/ }" 200)
    printf '%s: %s\n' "${status_text}" "${excerpt}"
    return 0
  fi

  printf '%s: %s%s\n' "${status_text}" "${message}" "${detail:+ (${detail})}"
}

#######################################
# @description Run a forge request and stop the script with the forge's own
#   reason when it fails.
#   The same four lines followed every request that must not fail; the reason is
#   read from the response once the request has failed, never before.
# @arg $1 string What failed, the start of the error message
# @arg $2 string Response body file the request writes to
# @arg $@ string The request command and its arguments
# @exitcode 0 The request succeeded
# @exitcode 1 Stop the script, naming the status and the forge's message
# @internal
#######################################
function __dybatpho_forge_or_die {
  local what="$1" response="$2"
  shift 2
  "$@" && return 0
  local detail
  detail=$(dybatpho::forge_error "${response}")
  dybatpho::die "${what}: ${detail}"
}

#######################################
# @description Print the number of an open issue whose title matches exactly.
#   GitLab can filter server-side; GitHub cannot search titles on the issues
#   endpoint, so the open issues are compared here. Both are exact matches, so
#   "Build failing" never collides with "Build failing on macOS".
# @arg $1 string Issue title
# @stdout Issue number, or nothing when no open issue has that title
# @exitcode 0 A matching issue exists
# @exitcode 1 No open issue has that title
#######################################
function dybatpho::forge_issue_find {
  local title
  dybatpho::expect_args title -- "$@"

  local kind body number
  local -A context=()
  __dybatpho_forge_context_into context
  kind="${context[kind]}"
  dybatpho::create_temp body ".json"

  case "${kind}" in
    github)
      dybatpho::forge_request GET "issues?state=open&per_page=100" "" "${body}" || return 1
      local title_json
      title_json=$(dybatpho::json_string "${title}")
      number="$(dybatpho::json_get "$(< "${body}")" \
        ".[] | select(.title == ${title_json}) | .number" | head -n 1)"
      ;;
    gitlab)
      local url_encode
      url_encode=$(dybatpho::url_encode "${title}")
      dybatpho::forge_request GET \
        "issues?state=opened&search=${url_encode}&in=title" "" "${body}" || return 1
      local json_string
      json_string=$(dybatpho::json_string "${title}")
      number="$(dybatpho::json_get "$(< "${body}")" \
        ".[] | select(.title == ${json_string}) | .iid" | head -n 1)"
      ;;
    *) ;;
  esac

  [[ -n "${number}" && "${number}" != "null" ]] || return 1
  printf '%s\n' "${number}"
}

#######################################
# @description Open an issue and print its number.
# @arg $1 string Issue title
# @arg $2 string Issue body
# @arg $3 string Optional comma-separated labels
# @stdout Number of the created issue
# @exitcode 1 The forge rejected the request
#######################################
function dybatpho::forge_issue_create {
  local title body
  dybatpho::expect_args title body -- "$@"
  local labels="${3-}"

  local kind payload response number
  local -A context=()
  __dybatpho_forge_context_into context
  kind="${context[kind]}"
  dybatpho::create_temp response ".json"

  case "${kind}" in
    github)
      payload="$(dybatpho::json_object title "${title}" body "${body}")"
      local forge_labels_json
      forge_labels_json=$(__dybatpho_forge_labels_json "${labels}")
      [[ -n "${labels}" ]] \
        && payload="$(dybatpho::json_eval "${payload}" \
          ".labels = ${forge_labels_json}")"
      __dybatpho_forge_or_die "Could not create issue '${title}'" "${response}" \
        dybatpho::forge_request POST "issues" "${payload}" "${response}"
      number="$(dybatpho::json_get "$(< "${response}")" '.number')"
      ;;
    gitlab)
      payload="$(dybatpho::json_object title "${title}" description "${body}")"
      [[ -n "${labels}" ]] \
        && payload="$(dybatpho::json_eval "${payload}" ".labels = $(dybatpho::json_string "${labels}")")"
      __dybatpho_forge_or_die "Could not create issue '${title}'" "${response}" \
        dybatpho::forge_request POST "issues" "${payload}" "${response}"
      number="$(dybatpho::json_get "$(< "${response}")" '.iid')"
      ;;
    *) ;;
  esac

  printf '%s\n' "${number}"
}

#######################################
# @description Add a comment to an existing issue.
# @arg $1 string Issue number
# @arg $2 string Comment body
# @exitcode 1 The forge rejected the request
#######################################
function dybatpho::forge_issue_comment {
  local number body
  dybatpho::expect_args number body -- "$@"

  local kind payload path
  local -A context=()
  __dybatpho_forge_context_into context
  kind="${context[kind]}"
  payload="$(dybatpho::json_object body "${body}")"
  case "${kind}" in
    github) path="issues/${number}/comments" ;;
    gitlab) path="issues/${number}/notes" ;;
    *) ;;
  esac

  local response
  dybatpho::create_temp response ".json"
  __dybatpho_forge_or_die "Could not comment on issue ${number}" "${response}" \
    dybatpho::forge_request POST "${path}" "${payload}" "${response}"
}

#######################################
# @description Report something once, then keep reporting to the same issue.
#   A script that runs on a schedule should not open a new issue on every
#   failure. This opens one the first time and comments on it afterwards, and
#   says in its output which of the two it did so a pipeline can react.
# @example
#   result="$(dybatpho::forge_issue_report "Nightly build failing" "${log_url}" ci)"
#   dybatpho::json_get "${result}" '.action'   # created | commented
#
# @arg $1 string Issue title, also the identity used to find an existing issue
# @arg $2 string Body of the issue or of the comment
# @arg $3 string Optional comma-separated labels, applied only when creating
# @stdout JSON object with `action`, `number` and `url`
# @exitcode 1 The forge rejected the request
#######################################
function dybatpho::forge_issue_report {
  local title body
  dybatpho::expect_args title body -- "$@"
  local labels="${3-}"

  local number action
  if number="$(dybatpho::forge_issue_find "${title}")"; then
    dybatpho::forge_issue_comment "${number}" "${body}"
    action="commented"
  else
    number="$(dybatpho::forge_issue_create "${title}" "${body}" "${labels}")"
    action="created"
  fi

  local forge_issue_url
  forge_issue_url=$(dybatpho::forge_issue_url "${number}")
  dybatpho::json_object \
    action "${action}" \
    number "${number}" \
    url "${forge_issue_url}"
}

#######################################
# @description Print the browser URL of an issue.
# @arg $1 string Issue number
# @stdout Issue URL
#######################################
function dybatpho::forge_issue_url {
  local number
  dybatpho::expect_args number -- "$@"

  local -A context=()
  __dybatpho_forge_context_into context host repo
  local kind="${context[kind]}" host="${context[host]}" repo="${context[repo]}"
  case "${kind}" in
    github) printf 'https://%s/%s/issues/%s\n' "${host}" "${repo}" "${number}" ;;
    gitlab) printf 'https://%s/%s/-/issues/%s\n' "${host}" "${repo}" "${number}" ;;
    *) ;;
  esac
}

#######################################
# @description Print the identifier of the release for a tag.
#   GitHub assets are attached by numeric release id; GitLab addresses a release
#   by its tag. Each forge returns the identifier its own upload step needs.
# @arg $1 string Tag name
# @stdout Release id on GitHub, tag name on GitLab
# @exitcode 0 A release exists for the tag
# @exitcode 1 No release exists for the tag
#######################################
function dybatpho::forge_release_find {
  local tag
  dybatpho::expect_args tag -- "$@"

  local kind body value
  local -A context=()
  __dybatpho_forge_context_into context
  kind="${context[kind]}"
  dybatpho::create_temp body ".json"

  case "${kind}" in
    github)
      dybatpho::forge_request GET "releases/tags/${tag}" "" "${body}" || return 1
      value="$(dybatpho::json_get "$(< "${body}")" '.id')"
      ;;
    gitlab)
      local url_encode
      url_encode=$(dybatpho::url_encode "${tag}")
      dybatpho::forge_request GET "releases/${url_encode}" "" "${body}" || return 1
      value="$(dybatpho::json_get "$(< "${body}")" '.tag_name')"
      ;;
    *) ;;
  esac

  [[ -n "${value}" && "${value}" != "null" ]] || return 1
  printf '%s\n' "${value}"
}

#######################################
# @description Create a release for a tag and print its identifier.
#   The tag must already exist on the forge; this publishes the release that
#   points at it rather than creating the tag.
# @example
#   dybatpho::forge_release_create "v1.2.0" "v1.2.0" "$(dybatpho::release_changelog)"
#
# @arg $1 string Tag name
# @arg $2 string Optional release title, default is the tag
# @arg $3 string Optional release notes
# @arg $4 string Optional `true` to create the release as a draft
# @stdout Release id on GitHub, tag name on GitLab
# @exitcode 1 The forge rejected the request, or a draft was asked of GitLab
# @note GitLab has no draft release, so asking for one there is an error rather
#   than a release published by surprise
#######################################
function dybatpho::forge_release_create {
  local tag
  dybatpho::expect_args tag -- "$@"
  local name="${2:-${tag}}" notes="${3-}" draft="${4:-false}"

  local kind payload response value
  local -A context=()
  __dybatpho_forge_context_into context
  kind="${context[kind]}"
  dybatpho::create_temp response ".json"

  case "${kind}" in
    github)
      payload="$(dybatpho::json_object tag_name "${tag}" name "${name}" body "${notes}")"
      dybatpho::is true "${draft}" \
        && payload="$(dybatpho::json_eval "${payload}" '.draft = true')"
      __dybatpho_forge_or_die "Could not create release '${tag}'" "${response}" \
        dybatpho::forge_request POST "releases" "${payload}" "${response}"
      value="$(dybatpho::json_get "$(< "${response}")" '.id')"
      ;;
    gitlab)
      dybatpho::is true "${draft}" \
        && dybatpho::die "GitLab has no draft release; hold the tag back instead"
      payload="$(dybatpho::json_object tag_name "${tag}" name "${name}" description "${notes}")"
      __dybatpho_forge_or_die "Could not create release '${tag}'" "${response}" \
        dybatpho::forge_request POST "releases" "${payload}" "${response}"
      value="$(dybatpho::json_get "$(< "${response}")" '.tag_name')"
      ;;
    *) ;;
  esac

  printf '%s\n' "${value}"
}

#######################################
# @description Attach a file to an existing release and print its URL.
#   The two forges do genuinely different things here. GitHub stores the asset
#   itself, on a separate upload host. GitLab stores nothing on a release: the
#   file goes to the project's generic package registry and the release gains a
#   link pointing at it. Both end with the file reachable from the release page.
# @example
#   dybatpho::forge_release_upload "v1.2.0" "dist/app-v1.2.0-linux-amd64.tar.gz"
#
# @arg $1 string Tag name of an existing release
# @arg $2 string File to attach
# @stdout URL the asset is reachable at
# @exitcode 1 The release does not exist, the file does not exist, or the upload failed
#######################################
function dybatpho::forge_release_upload {
  local tag file
  dybatpho::expect_args tag file -- "$@"
  dybatpho::is file "${file}" || dybatpho::die "No such file to upload: ${file}"

  local -A context=()
  __dybatpho_forge_context_into context token repo
  local kind="${context[kind]}" token="${context[token]}" repo="${context[repo]}"
  local release name response
  release="$(dybatpho::forge_release_find "${tag}")" \
    || dybatpho::die "No release for tag '${tag}'; create it before uploading assets"
  name="$(dybatpho::path_basename "${file}")"
  dybatpho::create_temp response ".json"

  case "${kind}" in
    github)
      # Assets go to a different host than the rest of the API, so this is the
      # one request that cannot go through `dybatpho::forge_request`.
      local host upload_url
      __dybatpho_forge_context_into context host
      host="${context[host]}"
      if [[ "${host}" == "github.com" ]]; then
        upload_url="https://uploads.github.com"
      else
        upload_url="https://${host}/api/uploads"
      fi
      upload_url="${upload_url}/repos/${repo}/releases/${release}/assets?name=$(dybatpho::url_encode "${name}")"

      # The token is handed over out of band; see DYBATPHO_CURL_SECRET_HEADERS.
      local -a DYBATPHO_CURL_SECRET_HEADERS=(
        "$(__dybatpho_forge_auth_header github "${token}")"
      )
      __dybatpho_forge_or_die "Could not upload ${name}" "${response}" \
        dybatpho::curl_request "${upload_url}" "${response}" \
        --request POST \
        --header "Content-Type: application/octet-stream" \
        --data-binary "@${file}"
      dybatpho::json_get "$(< "${response}")" '.browser_download_url'
      ;;
    gitlab)
      local package_url
      __dybatpho_forge_context_into context api
      package_url="${context[api]}/$(__dybatpho_forge_project_path gitlab "${repo}")"
      local path_basename
      path_basename=$(dybatpho::path_basename "${repo}")
      package_url="${package_url}/packages/generic/$(dybatpho::url_encode "${path_basename}")"
      local url_encode
      url_encode=$(dybatpho::url_encode "${tag}")
      package_url="${package_url}/${url_encode}/$(dybatpho::url_encode "${name}")"

      # The token is handed over out of band; see DYBATPHO_CURL_SECRET_HEADERS.
      # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
      local -a DYBATPHO_CURL_SECRET_HEADERS=(
        "$(__dybatpho_forge_auth_header gitlab "${token}")"
      )
      __dybatpho_forge_or_die "Could not upload ${name}" "${response}" \
        dybatpho::curl_request "${package_url}" "${response}" \
        --request PUT \
        --upload-file "${file}"

      # A generic package is not visible from the release until it is linked.
      local link_payload
      link_payload="$(dybatpho::json_object name "${name}" url "${package_url}")"
      # The reason is read from the link request's own response, once it has
      # failed: read earlier, it was the upload's answer, which had succeeded.
      __dybatpho_forge_or_die "Uploaded ${name} but could not link it to release '${tag}'" "${response}" \
        dybatpho::forge_request POST \
        "releases/${url_encode}/assets/links" "${link_payload}" "${response}"
      printf '%s\n' "${package_url}"
      ;;
    *) ;;
  esac
}
