setup() {
  load test_helper

  # Every test drives the module against a throwaway repository, never the real
  # one, so a stray request can never be aimed at this project.
  REPO="$(mktemp -d -p "${BATS_TEST_TMPDIR}" forge-repo-XXXXXXXX)"
  git -C "${REPO}" init -q
  git -C "${REPO}" remote add origin "git@github.com:acme/widget.git"

  DYBATPHO_FORGE=""
  DYBATPHO_FORGE_API=""
  DYBATPHO_FORGE_REPO=""
  DYBATPHO_FORGE_TOKEN="test-token"
  DYBATPHO_FORGE_REMOTE="origin"
  GITHUB_TOKEN=""
  GH_TOKEN=""
  GITLAB_TOKEN=""
  CI_JOB_TOKEN=""

  cd "${REPO}" || return 1
  dybatpho::secret_forget
}

teardown() {
  dybatpho::unmock_all 2> /dev/null || true
}

# @description Point the module at a GitLab remote for the current test.
use_gitlab() {
  git -C "${REPO}" remote set-url origin "git@gitlab.com:acme/group/widget.git"
}

# @description Print the curl argument list of the Nth recorded call.
# @arg $1 number 1-based call index
curl_call() {
  dybatpho::mock_calls curl | sed -n "${1}p"
}

# @description Print the credentials and body of the Nth recorded call. These
#   are deliberately kept out of the argument vector, so they are not in
#   `curl_call`; see `dybatpho::mock_http_payloads`.
# @arg $1 number 1-based call index
curl_payload() {
  dybatpho::mock_http_payloads | sed -n "${1}p"
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

@test "dybatpho::forge_host reads the host out of every remote URL form" {
  assert_equal "$(dybatpho::forge_host)" "github.com"

  git -C "${REPO}" remote set-url origin "ssh://git@gitlab.example.org/a/b.git"
  assert_equal "$(dybatpho::forge_host)" "gitlab.example.org"

  git -C "${REPO}" remote set-url origin "https://user@git.example.net/a/b"
  assert_equal "$(dybatpho::forge_host)" "git.example.net"
}

@test "dybatpho::forge_host fails when the remote does not exist" {
  run dybatpho::forge_host "nope"
  assert_failure
}

@test "dybatpho::forge_kind detects both forges and honors the override" {
  assert_equal "$(dybatpho::forge_kind)" "github"

  use_gitlab
  assert_equal "$(dybatpho::forge_kind)" "gitlab"

  # A host that gives nothing away is exactly what the override is for.
  git -C "${REPO}" remote set-url origin "git@code.internal:a/b.git"
  run dybatpho::forge_kind
  assert_failure
  assert_output --partial "set DYBATPHO_FORGE"

  DYBATPHO_FORGE=gitlab
  assert_equal "$(dybatpho::forge_kind)" "gitlab"
}

@test "dybatpho::forge_kind rejects an override that names no forge" {
  DYBATPHO_FORGE=bitbucket
  run dybatpho::forge_kind
  assert_failure
  assert_output --partial "must be 'github' or 'gitlab'"
}

@test "dybatpho::forge_repo keeps nested GitLab groups and honors the override" {
  assert_equal "$(dybatpho::forge_repo)" "acme/widget"

  use_gitlab
  assert_equal "$(dybatpho::forge_repo)" "acme/group/widget"

  DYBATPHO_FORGE_REPO="other/thing"
  assert_equal "$(dybatpho::forge_repo)" "other/thing"
}

@test "dybatpho::forge_api points at the right base for each forge" {
  assert_equal "$(dybatpho::forge_api)" "https://api.github.com"

  # Any GitHub that is not github.com is an Enterprise install.
  git -C "${REPO}" remote set-url origin "https://github.acme.dev/a/b.git"
  assert_equal "$(dybatpho::forge_api)" "https://github.acme.dev/api/v3"

  use_gitlab
  assert_equal "$(dybatpho::forge_api)" "https://gitlab.com/api/v4"

  DYBATPHO_FORGE_API="https://git.internal/api/v4/"
  assert_equal "$(dybatpho::forge_api)" "https://git.internal/api/v4"
}

# ---------------------------------------------------------------------------
# Token
# ---------------------------------------------------------------------------

@test "dybatpho::forge_token prefers DYBATPHO_FORGE_TOKEN over the forge variables" {
  GITHUB_TOKEN="from-github-var"
  assert_equal "$(dybatpho::forge_token)" "test-token"
}

@test "dybatpho::forge_token falls back to the variables each forge uses" {
  DYBATPHO_FORGE_TOKEN=""
  GITHUB_TOKEN="gh-primary"
  assert_equal "$(dybatpho::forge_token github)" "gh-primary"

  GITHUB_TOKEN=""
  GH_TOKEN="gh-fallback"
  assert_equal "$(dybatpho::forge_token github)" "gh-fallback"

  GITLAB_TOKEN="gl-primary"
  assert_equal "$(dybatpho::forge_token gitlab)" "gl-primary"

  GITLAB_TOKEN=""
  CI_JOB_TOKEN="gl-ci"
  assert_equal "$(dybatpho::forge_token gitlab)" "gl-ci"
}

@test "dybatpho::forge_token names the variables to set when none is set" {
  DYBATPHO_FORGE_TOKEN=""
  run dybatpho::forge_token github
  assert_failure
  assert_output --partial "GITHUB_TOKEN or GH_TOKEN"

  run dybatpho::forge_token gitlab
  assert_failure
  assert_output --partial "GITLAB_TOKEN or CI_JOB_TOKEN"
}

@test "dybatpho::forge_token registers the token in the shell it runs in" {
  DYBATPHO_FORGE_TOKEN="super-secret-value"
  dybatpho::forge_token github > /dev/null
  run_traced dybatpho::secret_mask "token is super-secret-value"
  refute_output --partial "super-secret-value"
}

@test "dybatpho::forge_token cannot register through a command substitution" {
  # Pinning the limitation the documentation states, so nobody reads the
  # registration above as a guarantee that survives `token="$(...)"`. A
  # subshell takes its registrations with it when it exits; that is Bash, not
  # something this module can fix.
  DYBATPHO_FORGE_TOKEN="another-secret-value"
  local captured
  captured="$(dybatpho::forge_token github)"
  assert_equal "${captured}" "another-secret-value"
  assert_equal "$(dybatpho::secret_mask "token is another-secret-value")" \
    "token is another-secret-value"

  # Registering it in this shell is what makes masking work from here on.
  dybatpho::secret_register "${captured}"
  run_traced dybatpho::secret_mask "token is another-secret-value"
  refute_output --partial "another-secret-value"
}

# ---------------------------------------------------------------------------
# Request
# ---------------------------------------------------------------------------

@test "dybatpho::forge_request builds a GitHub URL and sends a bearer token" {
  dybatpho::mock_http "api.github.com" 200 '{"ok":true}'

  run_traced dybatpho::forge_request GET "issues"
  assert_success
  dybatpho::assert_http_called "https://api.github.com/repos/acme/widget/issues"
  assert_regex "$(curl_payload 1)" "Authorization: Bearer test-token"
}

@test "dybatpho::forge_request URL-encodes the project path on GitLab" {
  use_gitlab
  dybatpho::mock_http "gitlab.com" 200 '{"ok":true}'

  run_traced dybatpho::forge_request GET "issues"
  assert_success
  dybatpho::assert_http_called "https://gitlab.com/api/v4/projects/acme%2Fgroup%2Fwidget/issues"
  assert_regex "$(curl_payload 1)" "PRIVATE-TOKEN: test-token"
}

@test "dybatpho::forge_request sends a JSON body only when one is given" {
  dybatpho::mock_http "api.github.com" 201 '{}'

  dybatpho::forge_request POST "issues" '{"title":"x"}'
  assert_regex "$(curl_call 1)" "Content-Type: application/json"
  assert_regex "$(curl_payload 1)" '\{"title":"x"\}'

  dybatpho::forge_request GET "issues"
  refute_regex "$(curl_call 2)" "Content-Type: application/json"
}

@test "dybatpho::forge_request passes an absolute URL through untouched" {
  dybatpho::mock_http "uploads.example" 200 '{}'

  run_traced dybatpho::forge_request GET "https://uploads.example/direct"
  assert_success
  dybatpho::assert_http_called "https://uploads.example/direct"
}

@test "dybatpho::forge_request reports a failing status to the caller" {
  dybatpho::mock_http "api.github.com" 404 '{"message":"Not Found"}'

  run_traced dybatpho::forge_request GET "issues/9999"
  assert_failure
}

# ---------------------------------------------------------------------------
# Issues
# ---------------------------------------------------------------------------

@test "dybatpho::forge_issue_find matches a title exactly, not by prefix" {
  dybatpho::mock_http "api.github.com" 200 \
    '[{"number":7,"title":"Build failing on macOS"},{"number":4,"title":"Build failing"}]'

  assert_equal "$(dybatpho::forge_issue_find "Build failing")" "4"

  run_traced dybatpho::forge_issue_find "Nothing like this"
  assert_failure
}

@test "dybatpho::forge_issue_find reads the iid on GitLab and searches by title" {
  use_gitlab
  dybatpho::mock_http "gitlab.com" 200 '[{"iid":11,"title":"Nightly failing"}]'

  assert_equal "$(dybatpho::forge_issue_find "Nightly failing")" "11"
  dybatpho::assert_http_called "in=title"
}

@test "dybatpho::forge_issue_create posts the GitHub field names" {
  dybatpho::mock_http "api.github.com" 201 '{"number":12}'

  assert_equal "$(dybatpho::forge_issue_create "Title" "Body text")" "12"
  assert_regex "$(curl_payload 1)" '"title":"Title"'
  assert_regex "$(curl_payload 1)" '"body":"Body text"'
}

@test "dybatpho::forge_issue_create sends GitHub labels as a JSON array" {
  dybatpho::mock_http "api.github.com" 201 '{"number":13}'

  dybatpho::forge_issue_create "Title" "Body" "ci, bug"
  assert_regex "$(curl_payload 1)" '"labels":\["ci","bug"\]'
}

@test "dybatpho::forge_issue_create uses description and a label string on GitLab" {
  use_gitlab
  dybatpho::mock_http "gitlab.com" 201 '{"iid":21}'

  assert_equal "$(dybatpho::forge_issue_create "Title" "Body" "ci,bug")" "21"
  assert_regex "$(curl_payload 1)" '"description":"Body"'
  assert_regex "$(curl_payload 1)" '"labels":"ci,bug"'
}

@test "dybatpho::forge_issue_create fails loudly when the forge rejects it" {
  dybatpho::mock_http "api.github.com" 422 '{"message":"Validation Failed"}'

  run dybatpho::forge_issue_create "Title" "Body"
  assert_failure
  assert_output --partial "Could not create issue"
}

@test "dybatpho::forge_issue_comment posts to the endpoint each forge uses" {
  dybatpho::mock_http "api.github.com" 201 '{}'
  dybatpho::forge_issue_comment 4 "a note"
  dybatpho::assert_http_called "/repos/acme/widget/issues/4/comments"
  assert_regex "$(curl_payload 1)" '"body":"a note"'

  dybatpho::unmock_all
  use_gitlab
  dybatpho::mock_http "gitlab.com" 201 '{}'
  dybatpho::forge_issue_comment 11 "a note"
  dybatpho::assert_http_called "/issues/11/notes"
}

@test "dybatpho::forge_issue_comment fails loudly when the forge rejects it" {
  dybatpho::mock_http "api.github.com" 403 '{}'

  run dybatpho::forge_issue_comment 4 "a note"
  assert_failure
  assert_output --partial "Could not comment on issue 4"
}

@test "dybatpho::forge_issue_report opens an issue when none is open yet" {
  # The search returns nothing, so the create route answers the POST.
  dybatpho::mock_http "issues?state=open" 200 '[]'
  dybatpho::mock_http "/repos/acme/widget/issues" 201 '{"number":30}'

  # Two layers of care here. `run` keeps a rejected request inside this test,
  # because the module reports one with `dybatpho::die`. And the result is
  # matched as text rather than parsed: feeding an error message to
  # `dybatpho::json_get` would itself die, at the top level of the test, which
  # aborts the whole file instead of failing this one case.
  run_traced dybatpho::forge_issue_report "Nightly failing" "log url" "ci"
  assert_success
  assert_regex "${output}" '"action":"created"'
  assert_regex "${output}" '"number":"30"'
  assert_regex "${output}" '"url":"https://github.com/acme/widget/issues/30"'
}

@test "dybatpho::forge_issue_report comments on the issue that is already open" {
  dybatpho::mock_http "issues?state=open" 200 '[{"number":30,"title":"Nightly failing"}]'
  dybatpho::mock_http "/issues/30/comments" 201 '{}'

  run_traced dybatpho::forge_issue_report "Nightly failing" "another failure"
  assert_success
  assert_regex "${output}" '"action":"commented"'
  assert_regex "${output}" '"number":"30"'
  dybatpho::assert_http_called "/issues/30/comments"
}

@test "dybatpho::forge_issue_url points at the browser path of each forge" {
  assert_equal "$(dybatpho::forge_issue_url 5)" "https://github.com/acme/widget/issues/5"

  use_gitlab
  assert_equal "$(dybatpho::forge_issue_url 5)" "https://gitlab.com/acme/group/widget/-/issues/5"
}

# ---------------------------------------------------------------------------
# Releases
# ---------------------------------------------------------------------------

@test "dybatpho::forge_release_find returns the id GitHub needs for uploads" {
  dybatpho::mock_http "releases/tags/v1.2.0" 200 '{"id":9001,"tag_name":"v1.2.0"}'

  assert_equal "$(dybatpho::forge_release_find "v1.2.0")" "9001"
}

@test "dybatpho::forge_release_find returns the tag GitLab addresses releases by" {
  use_gitlab
  dybatpho::mock_http "releases/v1.2.0" 200 '{"tag_name":"v1.2.0"}'

  assert_equal "$(dybatpho::forge_release_find "v1.2.0")" "v1.2.0"
}

@test "dybatpho::forge_release_find fails when the tag has no release" {
  dybatpho::mock_http "api.github.com" 404 '{"message":"Not Found"}'

  run_traced dybatpho::forge_release_find "v9.9.9"
  assert_failure
}

@test "dybatpho::forge_release_create posts the GitHub field names" {
  dybatpho::mock_http "api.github.com" 201 '{"id":9002}'

  assert_equal "$(dybatpho::forge_release_create "v1.3.0" "v1.3.0" "notes here")" "9002"
  assert_regex "$(curl_payload 1)" '"tag_name":"v1.3.0"'
  assert_regex "$(curl_payload 1)" '"body":"notes here"'
}

@test "dybatpho::forge_release_create uses description on GitLab and defaults the name" {
  use_gitlab
  dybatpho::mock_http "gitlab.com" 201 '{"tag_name":"v1.3.0"}'

  assert_equal "$(dybatpho::forge_release_create "v1.3.0")" "v1.3.0"
  assert_regex "$(curl_payload 1)" '"name":"v1.3.0"'
  assert_regex "$(curl_payload 1)" '"description":""'
}

@test "dybatpho::forge_release_create marks a GitHub release as a draft when asked" {
  dybatpho::mock_http "api.github.com" 201 '{"id":9003}'

  assert_equal "$(dybatpho::forge_release_create "v1.3.0" "v1.3.0" "notes" true)" "9003"
  assert_regex "$(curl_payload 1)" '"draft":true'
}

@test "dybatpho::forge_release_create publishes rather than drafting by default" {
  dybatpho::mock_http "api.github.com" 201 '{"id":9004}'

  dybatpho::forge_release_create "v1.3.0"
  refute_regex "$(curl_payload 1)" '"draft"'
}

@test "dybatpho::forge_release_create refuses a draft on GitLab rather than publishing one" {
  # GitLab has no draft release. Silently publishing would be the worst answer.
  use_gitlab
  dybatpho::mock_http "gitlab.com" 201 '{"tag_name":"v1.3.0"}'

  run dybatpho::forge_release_create "v1.3.0" "v1.3.0" "notes" true
  assert_failure
  assert_output --partial "no draft release"
}

@test "dybatpho::forge_release_create fails loudly when the forge rejects it" {
  dybatpho::mock_http "api.github.com" 422 '{}'

  run dybatpho::forge_release_create "v1.3.0"
  assert_failure
  assert_output --partial "Could not create release"
}

@test "dybatpho::forge_release_upload sends the asset to the GitHub upload host" {
  local artifact="${BATS_TEST_TMPDIR}/app-v1.2.0.tar.gz"
  printf 'payload' > "${artifact}"

  dybatpho::mock_http "releases/tags/v1.2.0" 200 '{"id":9001}'
  dybatpho::mock_http "uploads.github.com" 201 \
    '{"browser_download_url":"https://github.com/acme/widget/releases/download/v1.2.0/app-v1.2.0.tar.gz"}'

  assert_equal "$(dybatpho::forge_release_upload "v1.2.0" "${artifact}")" \
    "https://github.com/acme/widget/releases/download/v1.2.0/app-v1.2.0.tar.gz"
  dybatpho::assert_http_called "uploads.github.com/repos/acme/widget/releases/9001/assets?name=app-v1.2.0.tar.gz"
}

@test "dybatpho::forge_release_upload puts the file in the GitLab package registry and links it" {
  use_gitlab
  local artifact="${BATS_TEST_TMPDIR}/app-v1.2.0.tar.gz"
  printf 'payload' > "${artifact}"

  dybatpho::mock_http "releases/v1.2.0" 200 '{"tag_name":"v1.2.0"}'
  dybatpho::mock_http "packages/generic" 201 '{}'
  dybatpho::mock_http "assets/links" 201 '{}'

  run_traced dybatpho::forge_release_upload "v1.2.0" "${artifact}"
  assert_success
  assert_output --partial "packages/generic/widget/v1.2.0/app-v1.2.0.tar.gz"
  # A generic package is invisible from the release page until it is linked.
  dybatpho::assert_http_called "releases/v1.2.0/assets/links"
}

@test "dybatpho::forge_release_upload reports why GitLab refused the link" {
  # The message used to be read from the upload's own, successful response
  # before the link request ran, so a refused link reported a stale message.
  use_gitlab
  local artifact="${BATS_TEST_TMPDIR}/app-v1.2.0.tar.gz"
  printf 'payload' > "${artifact}"

  dybatpho::mock_http "releases/v1.2.0" 200 '{"tag_name":"v1.2.0"}'
  dybatpho::mock_http "packages/generic" 201 '{"message":"201 Created"}'
  dybatpho::mock_http "assets/links" 403 '{"message":"403 Forbidden - link refused"}'

  run dybatpho::forge_release_upload "v1.2.0" "${artifact}"
  assert_failure
  assert_output --partial "could not link it to release 'v1.2.0': HTTP 403: 403 Forbidden - link refused"
  refute_output --partial "201 Created"
}

@test "dybatpho::forge_release_upload refuses a missing file or a missing release" {
  run dybatpho::forge_release_upload "v1.2.0" "${BATS_TEST_TMPDIR}/absent.tar.gz"
  assert_failure
  assert_output --partial "No such file to upload"

  local artifact="${BATS_TEST_TMPDIR}/app.tar.gz"
  printf 'payload' > "${artifact}"
  dybatpho::mock_http "api.github.com" 404 '{}'
  run dybatpho::forge_release_upload "v9.9.9" "${artifact}"
  assert_failure
  assert_output --partial "No release for tag"
}

# ---------------------------------------------------------------------------
# Internals worth pinning on their own
# ---------------------------------------------------------------------------

@test "__dybatpho_forge_normalize_url handles every remote form" {
  assert_equal "$(__dybatpho_forge_normalize_url "git@github.com:o/r.git")" "github.com/o/r"
  assert_equal "$(__dybatpho_forge_normalize_url "ssh://git@gitlab.com/g/s/r.git")" "gitlab.com/g/s/r"
  assert_equal "$(__dybatpho_forge_normalize_url "https://github.com/o/r")" "github.com/o/r"
  assert_equal "$(__dybatpho_forge_normalize_url "https://user@host/o/r.git")" "host/o/r"
  assert_equal "$(__dybatpho_forge_normalize_url "https://github.com/o/r/")" "github.com/o/r"
}

@test "__dybatpho_forge_labels_json drops blanks and quotes each label" {
  assert_equal "$(__dybatpho_forge_labels_json "ci, bug ,")" '["ci","bug"]'
  assert_equal "$(__dybatpho_forge_labels_json "")" '[]'
}

@test "__dybatpho_forge_project_path addresses the project the way each forge does" {
  assert_equal "$(__dybatpho_forge_project_path github "o/r")" "repos/o/r"
  assert_equal "$(__dybatpho_forge_project_path gitlab "g/s/r")" "projects/g%2Fs%2Fr"
}

@test "__dybatpho_forge_auth_header uses the scheme each forge expects" {
  assert_equal "$(__dybatpho_forge_auth_header github "t")" "Authorization: Bearer t"
  assert_equal "$(__dybatpho_forge_auth_header gitlab "t")" "PRIVATE-TOKEN: t"
}

@test "__dybatpho_forge_token_vars names the variables for each forge" {
  assert_equal "$(__dybatpho_forge_token_vars github)" "GITHUB_TOKEN or GH_TOKEN"
  assert_equal "$(__dybatpho_forge_token_vars gitlab)" "GITLAB_TOKEN or CI_JOB_TOKEN"
}

@test "dybatpho::forge_error quotes what the forge actually said" {
  local body="${BATS_TEST_TMPDIR}/forge-error"
  DYBATPHO_HTTP_STATUS=422

  printf '%s' '{"message":"Validation Failed","errors":[{"field":"title","code":"missing"}]}' > "${body}"
  run_traced dybatpho::forge_error "${body}"
  assert_success
  assert_output --partial "HTTP 422"
  assert_output --partial "Validation Failed"
  assert_output --partial "title missing"

  # GitLab words it differently.
  printf '%s' '{"error":"insufficient_scope"}' > "${body}"
  run_traced dybatpho::forge_error "${body}"
  assert_output --partial "insufficient_scope"
}

@test "dybatpho::forge_error copes with a body that is not JSON, or missing" {
  local body="${BATS_TEST_TMPDIR}/not-json"
  DYBATPHO_HTTP_STATUS=502

  printf '%s' '<html><body>Bad Gateway</body></html>' > "${body}"
  run_traced dybatpho::forge_error "${body}"
  assert_success
  assert_output --partial "HTTP 502"
  assert_output --partial "Bad Gateway"

  : > "${body}"
  run_traced dybatpho::forge_error "${body}"
  assert_success
  assert_output "HTTP 502"

  run_traced dybatpho::forge_error "${BATS_TEST_TMPDIR}/does-not-exist"
  assert_success
  assert_output "HTTP 502"
}

@test "a failed forge call reports the forge's reason, not just the status" {
  dybatpho::mock_http "api.github.com" 422 \
    '{"message":"Validation Failed","errors":[{"field":"title","code":"missing"}]}'

  run --separate-stderr dybatpho::forge_issue_create "" "body text"
  assert_failure
  assert_stderr --partial "Validation Failed"
}
