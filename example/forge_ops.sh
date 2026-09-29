#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file forge_ops.sh
# @brief Example showing how to talk to the forge a repository is hosted on
# @description Demonstrates dybatpho::forge_host, forge_kind, forge_repo,
#   forge_api, forge_token, forge_request, forge_issue_find, forge_issue_create,
#   forge_issue_comment, forge_issue_report, forge_issue_url,
#   forge_release_find, forge_release_create, and forge_release_upload
#
#   The example runs against a throwaway repository and a stubbed forge, so it
#   needs no network, no credentials, and never touches this project. What the
#   module builds — URLs, auth headers, payload shapes — is real; only the
#   server answering is not.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules forge

dybatpho::register_common_handlers

# @description Install a `curl` stub on PATH that answers like a forge API.
#   `dybatpho::curl_do` runs `command curl`, which deliberately bypasses shell
#   functions, so the stub has to be a real executable earlier on PATH.
#
#   The stub answers by URL, and the issue search deliberately returns an empty
#   list the first time and a match afterwards, so the comment-or-create demo
#   below shows both of its branches.
# @noargs
function _install_forge_stub {
  local stub_dir
  dybatpho::create_temp_dir stub_dir "forge-stub"

  cat > "${stub_dir}/curl" << 'STUB'
#!/usr/bin/env bash
output=""
header_file=""
prev=""
url="${!#}"
for arg in "$@"; do
  case "${prev}" in
    -o) output="${arg}" ;;
    -D) header_file="${arg}" ;;
  esac
  prev="${arg}"
done

state="${FORGE_STUB_STATE:-/tmp/forge-stub-state}"
status=200
body='{}'
case "${url}" in
  *"issues?state=open"* | *"issues?state=opened"*)
    if [[ -f "${state}" ]]; then
      body='[{"number":42,"iid":42,"title":"Nightly build is failing"}]'
    else
      body='[]'
      : > "${state}"
    fi
    ;;
  *"/issues/42/comments"* | *"/issues/42/notes"*) status=201 ;;
  *"releases/tags/v1.4.0"* | *"releases/v1.4.0"*)
    body='{"id":9001,"tag_name":"v1.4.0"}'
    ;;
  *"assets?name="*)
    status=201
    body='{"browser_download_url":"https://github.com/acme/widget/releases/download'
    body+='/v1.4.0/widget-v1.4.0-linux-amd64.tar.gz"}'
    ;;
  *"packages/generic"* | *"assets/links"*) status=201 ;;
  *releases*)
    status=201
    body='{"id":9001,"tag_name":"v1.4.0"}'
    ;;
  *issues*)
    status=201
    body='{"number":42,"iid":42}'
    ;;
esac

if [[ -n "${header_file}" ]]; then
  printf 'HTTP/2 %s\r\ncontent-type: application/json\r\n\r\n' "${status}" > "${header_file}"
fi
if [[ -n "${output}" && "${output}" != "/dev/null" ]]; then
  printf '%s' "${body}" > "${output}"
fi
printf '%s' "${status}"
STUB

  chmod +x "${stub_dir}/curl"
  export PATH="${stub_dir}:${PATH}"
}

# @description Create a throwaway repository with the given remote and work in it.
# @arg $1 string Remote URL the forge is detected from
function _use_remote {
  local remote_url="$1"
  # shellcheck disable=SC2154 # set by the option spec of this script
  git -C "${WORKDIR}" remote remove origin > /dev/null 2>&1 || true
  git -C "${WORKDIR}" remote add origin "${remote_url}"
  cd "${WORKDIR}" || exit 1
}

# @description Run the `WHERE IS THIS REPOSITORY HOSTED` section of this example.
# @noargs
function _demo_detection {
  dybatpho::header "WHERE IS THIS REPOSITORY HOSTED"

  _use_remote "git@github.com:acme/widget.git"
  dybatpho::info "remote git@github.com:acme/widget.git"
  local forge_host_2
  forge_host_2=$(dybatpho::forge_host)
  dybatpho::print "  host: ${forge_host_2}"
  local forge_kind_2
  forge_kind_2=$(dybatpho::forge_kind)
  dybatpho::print "  kind: ${forge_kind_2}"
  local forge_repo_2
  forge_repo_2=$(dybatpho::forge_repo)
  dybatpho::print "  repo: ${forge_repo_2}"
  local forge_api_2
  forge_api_2=$(dybatpho::forge_api)
  dybatpho::print "  api : ${forge_api_2}"

  # The same four calls, against a self-hosted GitLab with nested groups.
  _use_remote "ssh://git@gitlab.acme.dev/platform/tools/widget.git"
  dybatpho::info "remote ssh://git@gitlab.acme.dev/platform/tools/widget.git"
  local forge_host
  forge_host=$(dybatpho::forge_host)
  dybatpho::print "  host: ${forge_host}"
  local forge_kind
  forge_kind=$(dybatpho::forge_kind)
  dybatpho::print "  kind: ${forge_kind}"
  local forge_repo
  forge_repo=$(dybatpho::forge_repo)
  dybatpho::print "  repo: ${forge_repo}"
  local forge_api
  forge_api=$(dybatpho::forge_api)
  dybatpho::print "  api : ${forge_api}"

  _use_remote "git@github.com:acme/widget.git"
}

# @description Run the `A RAW API CALL` section of this example.
# @noargs
function _demo_raw_request {
  dybatpho::header "A RAW API CALL"

  # `forge_token` registers the token for masking, but capturing it with `$( )`
  # runs that in a subshell, which takes the registration with it. A script that
  # holds the token registers it once, in its own shell.
  local token
  token="$(dybatpho::forge_token)"
  dybatpho::secret_register "${token}"
  local secret_mask
  secret_mask=$(dybatpho::secret_mask "${token}")
  dybatpho::info "token in use: ${secret_mask}"

  local body
  dybatpho::create_temp body ".json"
  # The path is relative to the project: no API base, no owner/repo, no auth.
  if dybatpho::forge_request GET "issues?state=open&per_page=100" "" "${body}"; then
    # shellcheck disable=SC2154 # set by the option spec of this script
    dybatpho::info "HTTP ${DYBATPHO_HTTP_STATUS}, body: $(< "${body}")"
  else
    dybatpho::warn "Request failed with status ${DYBATPHO_HTTP_STATUS}"
  fi
}

# @description Run the `REPORT A FAILURE WITHOUT SPAMMING ISSUES` section of this example.
# @noargs
function _demo_issue_report {
  dybatpho::header "REPORT A FAILURE WITHOUT SPAMMING ISSUES"

  local title="Nightly build is failing"
  local first second

  # The raw call above already searched, and the stub answers the first search
  # with an empty list. Reset it so both branches below are visible.
  rm -f "${FORGE_STUB_STATE}"

  # First run: nothing is open, so an issue is created.
  first="$(dybatpho::forge_issue_report "${title}" "Run 101 failed." "ci")"
  local json_get_3
  json_get_3=$(dybatpho::json_get "${first}" '.number')
  local json_get_5
  json_get_5=$(dybatpho::json_get "${first}" '.action')
  dybatpho::info "first run  -> action=${json_get_5}\
 number=${json_get_3}"

  # Second run: the issue is open, so this adds a comment instead.
  second="$(dybatpho::forge_issue_report "${title}" "Run 102 failed too.")"
  local json_get_2
  json_get_2=$(dybatpho::json_get "${second}" '.number')
  local json_get_4
  json_get_4=$(dybatpho::json_get "${second}" '.action')
  dybatpho::info "second run -> action=${json_get_4}\
 number=${json_get_2}"

  local json_get
  json_get=$(dybatpho::json_get "${second}" '.url')
  dybatpho::print "  issue URL: ${json_get}"

  # The pieces the report is built from are public too, when a script needs
  # finer control than comment-or-create gives it.
  local number
  if number="$(dybatpho::forge_issue_find "${title}")"; then
    local forge_issue_url
    forge_issue_url=$(dybatpho::forge_issue_url "${number}")
    dybatpho::info "forge_issue_find found issue ${number} at ${forge_issue_url}"
    dybatpho::forge_issue_comment "${number}" "One more note."
    dybatpho::info "forge_issue_comment added a note to issue ${number}"
  fi
}

# @description Run the `PUBLISH A RELEASE` section of this example.
# @noargs
function _demo_release {
  dybatpho::header "PUBLISH A RELEASE"

  local tag="v1.4.0" dist artifact
  dybatpho::create_temp_dir dist "forge-dist"
  artifact="${dist}/widget-${tag}-linux-amd64.tar.gz"
  printf 'pretend this is a build artifact\n' > "${artifact}"

  # In a real script the notes come from `dybatpho::release_changelog`.
  local release
  release="$(dybatpho::forge_release_create "${tag}" "${tag}" "Fixes and improvements.")"
  dybatpho::info "forge_release_create -> ${release}"

  if dybatpho::forge_release_find "${tag}" > /dev/null; then
    dybatpho::info "forge_release_find confirms ${tag} exists"
  fi

  local forge_release_upload_2
  forge_release_upload_2=$(dybatpho::forge_release_upload "${tag}" "${artifact}")
  dybatpho::info "asset URL: ${forge_release_upload_2}"

  # GitLab stores release assets in the package registry instead, and the
  # module handles the difference; the call a script makes is the same.
  _use_remote "git@gitlab.com:acme/widget.git"
  local forge_release_upload
  forge_release_upload=$(dybatpho::forge_release_upload "${tag}" "${artifact}")
  dybatpho::info "on GitLab: ${forge_release_upload}"
  _use_remote "git@github.com:acme/widget.git"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _install_forge_stub

  dybatpho::create_temp_dir WORKDIR "forge-demo"
  git -C "${WORKDIR}" init -q

  export FORGE_STUB_STATE="${WORKDIR}/searched-once"
  export DYBATPHO_FORGE_TOKEN="demo-token-value"

  _demo_detection
  _demo_raw_request
  _demo_issue_report
  _demo_release

  dybatpho::success "Forge operations demo complete"
}

_main "$@"
