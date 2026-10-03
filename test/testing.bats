setup() {
  load test_helper
  export DYBATPHO_TEST_SNAPSHOT_DIR="${BATS_TEST_TMPDIR}/snapshots"
  export DYBATPHO_TEST_UPDATE_SNAPSHOTS=false
  export UPDATE_SNAPSHOTS=""
  export DYBATPHO_TEST_DURATION_RUNS=1
  DYBATPHO_TEST_FAILURES=0
  dybatpho::snapshot_scrub_reset
}

@test "dybatpho::assert_file and assert_dir accept matching paths and reject others" {
  local file="${BATS_TEST_TMPDIR}/report.txt"
  printf 'ok\n' > "${file}"

  dybatpho::assert_file "${file}"
  dybatpho::assert_dir "${BATS_TEST_TMPDIR}"

  run_traced --separate-stderr dybatpho::assert_file "${BATS_TEST_TMPDIR}"
  assert_failure
  assert_stderr --partial "Expected a regular file"

  run_traced --separate-stderr dybatpho::assert_dir "${file}"
  assert_failure
  assert_stderr --partial "Expected a directory"

  run_traced --separate-stderr dybatpho::assert_file "${BATS_TEST_TMPDIR}/missing" "custom diagnostic"
  assert_failure
  assert_stderr --partial "custom diagnostic"
}

@test "dybatpho::assert_symlink checks the link and its target" {
  local target="${BATS_TEST_TMPDIR}/target.txt"
  local link="${BATS_TEST_TMPDIR}/link.txt"
  printf 'data\n' > "${target}"
  ln -s "${target}" "${link}"

  dybatpho::assert_symlink "${link}"
  dybatpho::assert_symlink "${link}" "${target}"

  run_traced --separate-stderr dybatpho::assert_symlink "${link}" "/somewhere/else"
  assert_failure
  assert_stderr --partial "points at the wrong target"

  run_traced --separate-stderr dybatpho::assert_symlink "${target}"
  assert_failure
  assert_stderr --partial "Expected a symbolic link"
}

@test "dybatpho::assert_path_absent only passes when nothing exists" {
  dybatpho::assert_path_absent "${BATS_TEST_TMPDIR}/never-created"

  local broken="${BATS_TEST_TMPDIR}/broken-link"
  ln -s "${BATS_TEST_TMPDIR}/missing-target" "${broken}"
  # A dangling symlink still occupies the path, so the assertion must fail.
  run_traced --separate-stderr dybatpho::assert_path_absent "${broken}"
  assert_failure
  assert_stderr --partial "Expected nothing at"
}

@test "dybatpho::assert_file_contains and assert_file_empty inspect file content" {
  local file="${BATS_TEST_TMPDIR}/log.txt"
  local empty="${BATS_TEST_TMPDIR}/empty.txt"
  printf 'deploy finished\n' > "${file}"
  : > "${empty}"

  dybatpho::assert_file_contains "${file}" "finished"
  dybatpho::assert_file_empty "${empty}"

  run_traced --separate-stderr dybatpho::assert_file_contains "${file}" "rolled back"
  assert_failure
  assert_stderr --partial "does not contain: rolled back"

  run_traced --separate-stderr dybatpho::assert_file_contains "${BATS_TEST_TMPDIR}/missing" "x"
  assert_failure
  assert_stderr --partial "Expected a readable file"

  run_traced --separate-stderr dybatpho::assert_file_empty "${file}"
  assert_failure
  assert_stderr --partial "Expected an empty file"
}

@test "dybatpho::assert_file_mode compares octal permissions" {
  local file="${BATS_TEST_TMPDIR}/secret.txt"
  printf 'token\n' > "${file}"
  chmod 600 "${file}"

  dybatpho::assert_file_mode "${file}" 600
  # Leading zeros describe the same mode.
  dybatpho::assert_file_mode "${file}" 0600

  chmod 644 "${file}"
  run_traced --separate-stderr dybatpho::assert_file_mode "${file}" 600
  assert_failure
  assert_stderr --partial "Wrong permissions"
  assert_stderr --partial "actual:   644"

  run_traced --separate-stderr dybatpho::assert_file_mode "${BATS_TEST_TMPDIR}/missing" 600
  assert_failure
  assert_stderr --partial "Expected an existing path"
}

@test "dybatpho::assert_json_valid and assert_json_query use the JSON backend" {
  local file="${BATS_TEST_TMPDIR}/package.json"
  printf '{"version":"1.4.2"}' > "${file}"

  stub yq ": echo '1.4.2'"
  dybatpho::assert_json_query "${file}" '.version' "1.4.2"
  unstub yq

  stub yq ": echo '1.4.2'"
  run_traced --separate-stderr dybatpho::assert_json_query "${file}" '.version' "9.9.9"
  assert_failure
  assert_stderr --partial "returned an unexpected value"
  unstub yq

  stub yq ": exit 1"
  run_traced --separate-stderr dybatpho::assert_json_valid "${file}"
  assert_failure
  assert_stderr --partial "Expected valid JSON"
  unstub yq
}

@test "JSON and YAML query assertions tolerate quoted string scalars" {
  local file="${BATS_TEST_TMPDIR}/quoted.json"
  printf '{"version":"1.4.2"}' > "${file}"

  # Backends print string scalars as `"1.4.2"`; both forms must be accepted.
  stub yq ": echo '\"1.4.2\"'"
  dybatpho::assert_json_query "${file}" '.version' "1.4.2"
  unstub yq

  stub yq ": echo '\"1.4.2\"'"
  dybatpho::assert_json_query "${file}" '.version' '"1.4.2"'
  unstub yq

  stub yq ": echo '\"1.4.2\"'"
  run_traced --separate-stderr dybatpho::assert_json_query "${file}" '.version' "2.0.0"
  assert_failure
  assert_stderr --partial "returned an unexpected value"
  unstub yq
}

@test "dybatpho::assert_json_has reports a filter that does not match" {
  local file="${BATS_TEST_TMPDIR}/config.json"
  printf '{"a":1}' > "${file}"

  stub yq ": exit 0"
  dybatpho::assert_json_has "${file}" '.a'
  unstub yq

  stub yq ": exit 1"
  run_traced --separate-stderr dybatpho::assert_json_has "${file}" '.missing'
  assert_failure
  assert_stderr --partial "JSON filter did not match"
  unstub yq
}

@test "dybatpho::assert_yaml_* mirror the JSON assertions" {
  local file="${BATS_TEST_TMPDIR}/settings.yaml"
  printf 'mode: dev\n' > "${file}"

  stub yq ": echo 'dev'"
  dybatpho::assert_yaml_query "${file}" '.mode' "dev"
  unstub yq

  stub yq ": echo 'dev'"
  dybatpho::assert_yaml_valid "${file}"
  unstub yq

  stub yq ": exit 0"
  dybatpho::assert_yaml_has "${file}" '.mode'
  unstub yq

  stub yq ": exit 1"
  run_traced --separate-stderr dybatpho::assert_yaml_query "${file}" '.missing' "x"
  assert_failure
  assert_stderr --partial "YAML query failed"
  unstub yq

  stub yq ": exit 1"
  run_traced --separate-stderr dybatpho::assert_yaml_has "${file}" '.missing'
  assert_failure
  assert_stderr --partial "YAML expression did not match"
  unstub yq

  stub yq ": exit 1"
  run_traced --separate-stderr dybatpho::assert_yaml_valid "${file}"
  assert_failure
  assert_stderr --partial "Expected valid YAML"
  unstub yq
}

@test "JSON assertions accept a document on stdin" {
  stub yq ": echo 'dev'"
  printf '{"mode":"dev"}' | dybatpho::assert_json_query - '.mode' "dev"
  unstub yq
}

@test "dybatpho::assert_snapshot records a baseline then compares against it" {
  # The first run has no stored snapshot, so it records one and passes.
  dybatpho::assert_snapshot cli-output "hello world"
  assert_file_exist "${DYBATPHO_TEST_SNAPSHOT_DIR}/cli-output.snap"
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/cli-output.snap")" "hello world"

  # A later run with the same text matches.
  dybatpho::assert_snapshot cli-output "hello world"

  run_traced --separate-stderr dybatpho::assert_snapshot cli-output "hello there"
  assert_failure
  assert_stderr --partial "does not match"
  assert_stderr --partial "-hello world"
  assert_stderr --partial "+hello there"
}

@test "dybatpho::assert_snapshot reads stdin, strips colors, and can be updated" {
  printf '\033[0;31mred text\033[0m\n' | dybatpho::assert_snapshot colored
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/colored.snap")" "red text"

  DYBATPHO_TEST_UPDATE_SNAPSHOTS=true
  dybatpho::assert_snapshot colored "rewritten"
  DYBATPHO_TEST_UPDATE_SNAPSHOTS=false
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/colored.snap")" "rewritten"

  run --separate-stderr dybatpho::assert_snapshot "../escape" "x"
  assert_failure
  assert_stderr --partial "Invalid snapshot name"
}

@test "dybatpho::snapshot_scrub removes volatile values before comparing" {
  dybatpho::snapshot_scrub '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' '<DATE>'
  dybatpho::assert_snapshot scrubbed "built on 2026-09-15"
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/scrubbed.snap")" "built on <DATE>"

  # A different date still matches because it is scrubbed the same way.
  dybatpho::assert_snapshot scrubbed "built on 2027-01-01"

  dybatpho::snapshot_scrub_reset
  run_traced --separate-stderr dybatpho::assert_snapshot scrubbed "built on 2027-01-01"
  assert_failure
}

@test "dybatpho::assert_cli_snapshot captures stdout, stderr, and the exit code" {
  dybatpho::assert_cli_snapshot cli-run -- bash -c 'printf "out\n"; printf "err\n" >&2; exit 3'

  local snapshot
  snapshot="$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/cli-run.snap")"
  assert_equal "$(printf '%s' "${snapshot}" | grep -c '^--- exit: 3$')" "1"
  dybatpho::assert_file_contains "${DYBATPHO_TEST_SNAPSHOT_DIR}/cli-run.snap" "out"
  dybatpho::assert_file_contains "${DYBATPHO_TEST_SNAPSHOT_DIR}/cli-run.snap" "err"

  # A changed exit code is a snapshot mismatch, not a passing run.
  run_traced --separate-stderr dybatpho::assert_cli_snapshot cli-run -- bash -c 'printf "out\n"; printf "err\n" >&2; exit 0'
  assert_failure
  assert_stderr --partial "does not match"
}

@test "dybatpho::assert_cli_snapshot rejects a missing separator or command" {
  run --separate-stderr dybatpho::assert_cli_snapshot name bash -c true
  assert_failure
  assert_stderr --partial "Expected: name -- command"

  run --separate-stderr dybatpho::assert_cli_snapshot name --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"
}

@test "UPDATE_SNAPSHOTS=1 rewrites snapshots and an off value leaves them alone" {
  dybatpho::assert_snapshot golden "recorded"

  # The unprefixed alias is what a contributor types in front of the runner.
  UPDATE_SNAPSHOTS=1
  dybatpho::assert_snapshot golden "regenerated"
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/golden.snap")" "regenerated"

  # `0` is off here, however `dybatpho::is true` reads it: an environment
  # variable set to zero must not quietly rewrite the baseline.
  UPDATE_SNAPSHOTS=0
  run_traced --separate-stderr dybatpho::assert_snapshot golden "drifted"
  assert_failure
  assert_stderr --partial "does not match"
  assert_equal "$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/golden.snap")" "regenerated"
}

@test "dybatpho::assert_duration_under passes under its budget and reports an overrun" {
  dybatpho::assert_duration_under 10000 -- true
  assert [ "${DYBATPHO_TEST_LAST_DURATION_MS}" -ge 0 ]

  run_traced --separate-stderr dybatpho::assert_duration_under 0 -- true
  assert_failure
  assert_stderr --partial "Expected to finish in under 0ms"

  # A command that fails is a failure, not a fast run.
  run_traced --separate-stderr dybatpho::assert_duration_under 10000 -- bash -c 'printf "boom\n" >&2; exit 4'
  assert_failure
  assert_stderr --partial "exited 4"
  assert_stderr --partial "boom"
}

@test "dybatpho::assert_duration_under keeps the fastest of several runs" {
  DYBATPHO_TEST_DURATION_RUNS=3
  dybatpho::assert_duration_under 10000 -- true
  DYBATPHO_TEST_DURATION_RUNS=1

  run --separate-stderr dybatpho::assert_duration_under 100 -- true extra
  assert_success

  run --separate-stderr dybatpho::assert_duration_under later -- true
  assert_failure
  assert_stderr --partial "Expected a budget in milliseconds"

  run --separate-stderr dybatpho::assert_duration_under 100 true
  assert_failure
  assert_stderr --partial "Expected: milliseconds -- command"

  run --separate-stderr dybatpho::assert_duration_under 100 --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"
}

@test "dybatpho::benchmark reports the fastest, median, and slowest run" {
  run dybatpho::benchmark startup 3 -- true
  assert_success
  assert_output --partial "startup runs=3"
  assert_output --partial "median="

  dybatpho::benchmark startup 3 -- true > /dev/null
  assert [ "${DYBATPHO_TEST_BENCH_MIN_MS}" -le "${DYBATPHO_TEST_BENCH_MEDIAN_MS}" ]
  assert [ "${DYBATPHO_TEST_BENCH_MEDIAN_MS}" -le "${DYBATPHO_TEST_BENCH_MAX_MS}" ]
  assert_equal "${DYBATPHO_TEST_LAST_DURATION_MS}" "${DYBATPHO_TEST_BENCH_MEDIAN_MS}"

  run --separate-stderr dybatpho::benchmark startup 0 -- true
  assert_failure
  assert_stderr --partial "Expected a positive number of runs"

  run --separate-stderr dybatpho::benchmark startup 2 true
  assert_failure
  assert_stderr --partial "Expected: label runs -- command"

  run --separate-stderr dybatpho::benchmark startup 2 --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"

  run --separate-stderr dybatpho::benchmark startup 2 -- bash -c 'exit 5'
  assert_failure
  assert_stderr --partial "exited 5 on run 1 of 2"
}

@test "dybatpho::mock_env sets values and unmock_env restores the previous state" {
  export DYBATPHO_TEST_PRESET="original"
  unset DYBATPHO_TEST_ABSENT || true

  dybatpho::mock_env DYBATPHO_TEST_PRESET=mocked DYBATPHO_TEST_ABSENT=added
  assert_equal "${DYBATPHO_TEST_PRESET}" "mocked"
  assert_equal "${DYBATPHO_TEST_ABSENT}" "added"

  dybatpho::unmock_env
  assert_equal "${DYBATPHO_TEST_PRESET}" "original"
  # A variable that was unset before mocking is unset again, not left empty.
  refute [ -v DYBATPHO_TEST_ABSENT ]

  unset DYBATPHO_TEST_PRESET
}

@test "dybatpho::mock_env rejects malformed assignments" {
  run --separate-stderr dybatpho::mock_env
  assert_failure
  assert_stderr --partial "Expected at least one NAME=value"

  run --separate-stderr dybatpho::mock_env "not-an-assignment"
  assert_failure
  assert_stderr --partial "Invalid assignment"
}

@test "dybatpho::mock_command records calls and assert_mock_called matches arguments" {
  dybatpho::mock_command kubectl 0 "pod/api Running"

  assert_equal "$(kubectl get pods)" "pod/api Running"
  kubectl delete pod api

  assert_equal "$(dybatpho::mock_call_count kubectl)" "2"
  dybatpho::assert_mock_called kubectl
  dybatpho::assert_mock_called kubectl get pods
  dybatpho::assert_mock_called kubectl delete pod api

  run_traced --separate-stderr dybatpho::assert_mock_called kubectl apply -f manifest.yaml
  assert_failure
  assert_stderr --partial "was never called with"
}

@test "dybatpho::mock_command honors the requested exit code" {
  dybatpho::mock_command failing-tool 7
  run_traced failing-tool --now
  assert_failure 7
  assert_equal "$(dybatpho::mock_call_count failing-tool)" "1"
}

@test "dybatpho::mock_command_script runs a custom body" {
  dybatpho::mock_command_script greeter 'printf "hello %s\n" "$1"; exit 0'
  assert_equal "$(greeter world)" "hello world"
  dybatpho::assert_mock_called greeter world
}

@test "mock bookkeeping reports uncalled and unmocked commands" {
  assert_equal "$(dybatpho::mock_call_count never-mocked)" "0"

  run_traced --separate-stderr dybatpho::assert_mock_called never-mocked
  assert_failure
  assert_stderr --partial "Command was never mocked"

  dybatpho::mock_command idle-tool 0
  assert_equal "$(dybatpho::mock_call_count idle-tool)" "0"
  run_traced --separate-stderr dybatpho::assert_mock_called idle-tool
  assert_failure
  assert_stderr --partial "was never called"
}

@test "dybatpho::unmock_command removes one mock and unmock_all clears everything" {
  dybatpho::mock_command first-tool 0 "one"
  dybatpho::mock_command second-tool 0 "two"
  assert_equal "$(first-tool)" "one"

  dybatpho::unmock_command first-tool
  run_traced --separate-stderr dybatpho::assert_mock_called first-tool
  assert_failure
  assert_equal "$(second-tool)" "two"

  dybatpho::unmock_all
  run_traced --separate-stderr dybatpho::assert_mock_called second-tool
  assert_failure
}

@test "dybatpho::mock_command rejects invalid names and exit codes" {
  run --separate-stderr dybatpho::mock_command_script "bad name" 'exit 0'
  assert_failure
  assert_stderr --partial "Invalid command name"

  run --separate-stderr dybatpho::mock_command tool "not-a-number"
  assert_failure
  assert_stderr --partial "Exit code must be a non-negative integer"
}

@test "dybatpho::mock_http serves a canned response to the network module" {
  export DYBATPHO_CURL_MAX_RETRIES=0
  local body_file="${BATS_TEST_TMPDIR}/body.json"
  dybatpho::mock_http "api.example.test/status" 200 '{"ok":true}' "Content-Type: application/json"

  dybatpho::curl_do "https://api.example.test/status" "${body_file}"
  dybatpho::assert_file_contains "${body_file}" '{"ok":true}'
  dybatpho::assert_http_called "api.example.test/status"
}

@test "dybatpho::mock_http maps status codes onto network module exit codes" {
  export DYBATPHO_CURL_MAX_RETRIES=0
  dybatpho::mock_http "api.example.test/missing" 404

  run_traced -4 dybatpho::curl_do "https://api.example.test/missing" "${BATS_TEST_TMPDIR}/out"
  # An unrouted URL falls through to the mock's default 404.
  run_traced -4 dybatpho::curl_do "https://api.example.test/unknown" "${BATS_TEST_TMPDIR}/out"
}

@test "dybatpho::mock_http records requested URLs and parses response headers" {
  export DYBATPHO_CURL_MAX_RETRIES=0
  local header_file="${BATS_TEST_TMPDIR}/headers.txt"
  dybatpho::mock_http "example.test/data" 201 'created' "X-Request-Id: abc123"

  dybatpho::curl_do "https://example.test/data" "${BATS_TEST_TMPDIR}/out" -D "${header_file}"
  dybatpho::curl_parse_response "${header_file}"
  assert_equal "${DYBATPHO_HTTP_STATUS}" "201"
  assert_equal "$(dybatpho::curl_response_header x-request-id)" "abc123"

  run_traced dybatpho::mock_http_calls
  assert_success
  assert_output --partial "https://example.test/data"
}

@test "dybatpho::mock_http_payloads records what never reached the argument vector" {
  export DYBATPHO_CURL_MAX_RETRIES=0
  dybatpho::mock_http "example.test/secure" 200 'ok'

  # Nothing sent out of band yet.
  run_traced dybatpho::mock_http_payloads
  assert_failure

  local -a DYBATPHO_CURL_SECRET_HEADERS=("Authorization: Bearer shhh-token")
  local DYBATPHO_CURL_SECRET_DATA='{"field":"value"}'
  dybatpho::curl_do "https://example.test/secure" "${BATS_TEST_TMPDIR}/out"

  # The credential and the body were both sent, and neither was an argument.
  run_traced dybatpho::mock_http_payloads
  assert_success
  assert_output --partial 'Authorization: Bearer shhh-token'
  assert_output --partial '{"field":"value"}'

  run_traced dybatpho::mock_calls curl
  assert_success
  refute_output --partial "shhh-token"
  refute_output --partial '"field":"value"'
}

@test "dybatpho::assert_http_called reports unmatched and absent requests" {
  run_traced --separate-stderr dybatpho::assert_http_called "never.example.test"
  assert_failure
  assert_stderr --partial "No HTTP request was made through the mock"

  export DYBATPHO_CURL_MAX_RETRIES=0
  dybatpho::mock_http "example.test/one" 200 "body"
  dybatpho::curl_do "https://example.test/one" "${BATS_TEST_TMPDIR}/out"

  run_traced --separate-stderr dybatpho::assert_http_called "example.test/two"
  assert_failure
  assert_stderr --partial "No HTTP request matched"
}

@test "dybatpho::mock_http keeps routes apart when patterns sanitize alike" {
  export DYBATPHO_CURL_MAX_RETRIES=0
  # `api.test/v1` and `api-test/v1` reduce to the same sanitized name, so each
  # route needs its own storage or the second registration wins both URLs.
  dybatpho::mock_http "api.test/v1" 200 "V1"
  dybatpho::mock_http "api-test/v1" 201 "OTHER"

  dybatpho::curl_do "https://api.test/v1" "${BATS_TEST_TMPDIR}/dot"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/dot")" "V1"

  dybatpho::curl_do "https://api-test/v1" "${BATS_TEST_TMPDIR}/dash"
  assert_equal "$(cat "${BATS_TEST_TMPDIR}/dash")" "OTHER"
}

@test "dybatpho::mock_http keeps its script out of the execution trace" {
  # kcov reads coverage from `xtrace`, and a traced value holding both a line
  # break and a single quote is printed in a form kcov misreads, after which it
  # records nothing more in the process. The mock script is exactly such a
  # value, so it must reach its file without ever being expanded in a command.
  local trace="${BATS_TEST_TMPDIR}/trace"
  exec {trace_fd}> "${trace}"
  BASH_XTRACEFD="${trace_fd}"
  set -x
  dybatpho::mock_http "api.test" 200 "ok"
  set +x
  unset BASH_XTRACEFD
  exec {trace_fd}>&-

  run_traced grep -c 'body_on_stdin=0' "${trace}"
  assert_output "0"
  run_traced grep -c 'body_on_stdin=0' "${DYBATPHO_TEST_MOCK_DIR}/curl"
  assert_output "1"
}

@test "dybatpho::assert_mock_called matches whole arguments, not fragments" {
  dybatpho::mock_command tool 0
  tool deploy production --wait

  dybatpho::assert_mock_called tool deploy production
  # A leading subset of the recorded arguments still matches.
  dybatpho::assert_mock_called tool deploy
  dybatpho::assert_mock_called tool --wait

  # A fragment that spans an argument boundary must not count as a call.
  run_traced --separate-stderr dybatpho::assert_mock_called tool "loy produc"
  assert_failure
  assert_stderr --partial "was never called with"

  run_traced --separate-stderr dybatpho::assert_mock_called tool "deploy staging"
  assert_failure
}

@test "dybatpho::mock_http rejects a status code that is not three digits" {
  run --separate-stderr dybatpho::mock_http "example.test" 20
  assert_failure
  assert_stderr --partial "HTTP status must be three digits"
}

@test "dybatpho::fixture_dir and fixture_file create usable temporary fixtures" {
  local workdir settings notes
  dybatpho::fixture_dir workdir
  dybatpho::assert_dir "${workdir}"

  dybatpho::fixture_file settings '{"mode":"dev"}' ".json"
  dybatpho::assert_file "${settings}"
  dybatpho::assert_file_contains "${settings}" '"mode":"dev"'
  assert_equal "$(dybatpho::path_extname "${settings}")" ".json"

  # A here-string keeps the call in the current shell; a pipeline would run
  # `fixture_file` in a subshell and lose the assigned variable.
  dybatpho::fixture_file notes - <<< "from stdin"
  dybatpho::assert_file_contains "${notes}" "from stdin"
}

@test "dybatpho::fixture_file fills a caller variable named like its locals" {
  local content=""
  dybatpho::fixture_file content "payload"
  dybatpho::assert_file_contains "${content}" "payload"
}

@test "dybatpho::fixture_dir fills a caller variable named like a create_temp local" {
  local path_var=""
  dybatpho::fixture_dir path_var
  dybatpho::assert_dir "${path_var}"
}

@test "fixtures are removed by the exit trap when their shell ends" {
  local marker="${BATS_TEST_TMPDIR}/fixture-path"
  # The fixture is created in a subshell, so its exit trap must clean it up.
  (
    local fixture
    dybatpho::fixture_file fixture "temporary"
    printf '%s' "${fixture}" > "${marker}"
    dybatpho::assert_file "${fixture}"
  )
  dybatpho::assert_path_absent "$(cat "${marker}")"
}

@test "assertion failures are counted in DYBATPHO_TEST_FAILURES" {
  DYBATPHO_TEST_FAILURES=0
  dybatpho::assert_file "${BATS_TEST_TMPDIR}" 2> /dev/null || true
  dybatpho::assert_dir "${BATS_TEST_TMPDIR}/missing" 2> /dev/null || true
  assert_equal "${DYBATPHO_TEST_FAILURES}" "2"

  dybatpho::assert_dir "${BATS_TEST_TMPDIR}"
  assert_equal "${DYBATPHO_TEST_FAILURES}" "2"
}

@test "dybatpho::mock_calls prints one line per call and fails for an unmocked command" {
  dybatpho::mock_command deploy-tool 0

  deploy-tool push --env staging
  deploy-tool status

  run_traced dybatpho::mock_calls deploy-tool
  assert_success
  assert_line --index 0 "push --env staging"
  assert_line --index 1 "status"

  run_traced dybatpho::mock_calls never-mocked-tool
  assert_failure
}

@test "dybatpho::assert_exit_code passes on the expected status and reports any other" {
  dybatpho::assert_exit_code 0 -- true
  dybatpho::assert_exit_code 3 -- bash -c 'exit 3'

  run_traced --separate-stderr dybatpho::assert_exit_code 0 -- bash -c 'printf "boom\n"; exit 2'
  assert_failure
  assert_stderr --partial "Expected exit 0, got 2"
  assert_stderr --partial "boom"
  # Output is captured, never printed on stdout.
  assert_output ""

  run_traced --separate-stderr dybatpho::assert_exit_code 1 -- true
  assert_failure
  assert_stderr --partial "Expected exit 1, got 0"
}

@test "dybatpho::assert_exit_code runs in the current shell and counts failures" {
  DYBATPHO_TEST_FAILURES=0
  dybatpho::mock_command flaky-tool 4
  dybatpho::assert_exit_code 4 -- flaky-tool --once
  dybatpho::assert_mock_called flaky-tool --once

  dybatpho::assert_exit_code 0 -- flaky-tool 2> /dev/null || true
  assert_equal "${DYBATPHO_TEST_FAILURES}" "1"
}

@test "dybatpho::assert_exit_code rejects a bad status, separator, or missing command" {
  run --separate-stderr dybatpho::assert_exit_code 256 -- true
  assert_failure
  assert_stderr --partial "Expected an exit status from 0 to 255"

  run --separate-stderr dybatpho::assert_exit_code abc -- true
  assert_failure
  assert_stderr --partial "Expected an exit status from 0 to 255"

  run --separate-stderr dybatpho::assert_exit_code 0 true
  assert_failure
  assert_stderr --partial "Expected: status -- command"

  run --separate-stderr dybatpho::assert_exit_code 0 --
  assert_failure
  assert_stderr --partial "Expected a command to run after --"
}

@test "dybatpho::mock_time freezes now for date and the date module" {
  # A date that already ran is remembered by the shell; the mock must still win.
  date +%s > /dev/null
  dybatpho::mock_time 1767225600

  assert_equal "$(date -u +%s)" "1767225600"
  assert_equal "$(TZ=UTC dybatpho::date_now '%F %T')" "2026-01-01 00:00:00"
  # A child process sees the same moment.
  assert_equal "$(bash -c 'date -u +%F')" "2026-01-01"

  # A call that names its own moment is passed through.
  assert_equal "$(TZ=UTC dybatpho::date_format 0 %F)" "1970-01-01"
  assert_equal "$(DYBATPHO_DATE_TIMEZONE=UTC dybatpho::date_parse '2024-02-29 12:34:56')" "1709210096"
  dybatpho::assert_mock_called date
}

@test "dybatpho::mock_time drives ages computed from the clock" {
  local file="${BATS_TEST_TMPDIR}/aged"
  : > "${file}"

  dybatpho::mock_time "$(dybatpho::file_mtime "${file}")"
  assert_equal "$(dybatpho::file_age_seconds "${file}")" "0"
  dybatpho::mock_time_advance 90
  assert_equal "$(dybatpho::file_age_seconds "${file}")" "90"
}

@test "dybatpho::mock_time_advance moves the clock both ways" {
  dybatpho::mock_time 1000
  dybatpho::mock_time_advance 86400
  assert_equal "$(date -u +%s)" "87400"
  dybatpho::mock_time_advance -400
  assert_equal "$(date -u +%s)" "87000"

  # Freezing again replaces the moment instead of stacking on it.
  dybatpho::mock_time 5
  assert_equal "$(date -u +%s)" "5"
}

@test "dybatpho::mock_time_advance rejects bad amounts and an unfrozen clock" {
  run --separate-stderr dybatpho::mock_time_advance 10
  assert_failure
  assert_stderr --partial "The clock is not frozen"

  dybatpho::mock_time 10
  run --separate-stderr dybatpho::mock_time_advance soon
  assert_failure
  assert_stderr --partial "Expected a whole number of seconds"

  run --separate-stderr dybatpho::mock_time_advance -11
  assert_failure
  assert_stderr --partial "before the Unix epoch"
}

@test "dybatpho::mock_time rejects a timestamp that is not whole seconds" {
  run --separate-stderr dybatpho::mock_time "2026-01-01"
  assert_failure
  assert_stderr --partial "Expected a Unix timestamp in whole seconds"

  run --separate-stderr dybatpho::mock_time -5
  assert_failure
  assert_stderr --partial "Expected a Unix timestamp in whole seconds"
}

@test "dybatpho::mock_time drives a BSD date through -r" {
  local bin="${BATS_TEST_TMPDIR}/bsd-bin" real moment='-r "$2"'
  real="$(command -v date)"
  # On GNU and BusyBox, the fake turns `-r <seconds>` into the real `-d @...`.
  if "${real}" -d @0 +%s > /dev/null 2>&1; then
    moment='-d "@$2"'
  fi
  mkdir -p "${bin}"
  # A date that refuses `-d`, as BSD's does for a bare `@<seconds>`.
  cat > "${bin}/date" << BSD
#!/usr/bin/env bash
args=()
while ((\$#)); do
  case "\$1" in
    -d*) exit 1 ;;
    -r) args+=(${moment}); shift 2 ;;
    *) args+=("\$1"); shift ;;
  esac
done
exec ${real} "\${args[@]}"
BSD
  chmod +x "${bin}/date"
  PATH="${bin}:${PATH}"

  dybatpho::mock_time 1767225600
  assert_equal "$(date -u +%F)" "2026-01-01"
  dybatpho::assert_file_contains "${DYBATPHO_TEST_MOCK_DIR}/date" '-r "${epoch}"'
}

@test "dybatpho::mock_time fails when no date can format a timestamp" {
  local bin="${BATS_TEST_TMPDIR}/broken-bin"
  mkdir -p "${bin}"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${bin}/date"
  chmod +x "${bin}/date"
  PATH="${bin}:${PATH}"

  run --separate-stderr dybatpho::mock_time 10
  assert_failure
  assert_stderr --partial "cannot format a given timestamp"

  # Only the lookup runs without a PATH; the mock directory is made beforehand.
  dybatpho::mock_command placeholder 0
  mock_time_without_path() {
    local PATH="${BATS_TEST_TMPDIR}/nowhere"
    dybatpho::mock_time 10
  }
  run --separate-stderr mock_time_without_path
  assert_failure
  assert_stderr --partial "No date command found on PATH"
}

@test "dybatpho::unmock_time and unmock_all bring the real clock back" {
  local real
  real="$(date +%Y)"

  dybatpho::unmock_time
  dybatpho::mock_time 0
  assert_equal "$(date -u +%Y)" "1970"
  dybatpho::unmock_time
  assert_equal "$(date +%Y)" "${real}"
  dybatpho::unmock_time

  dybatpho::mock_time 0
  dybatpho::unmock_all
  assert_equal "$(date +%Y)" "${real}"
  refute [ -e "${DYBATPHO_TEST_MOCK_DIR}/time-epoch" ]
}

@test "dybatpho::mock_tty answers is_tty for the streams it names" {
  dybatpho::mock_tty on stdout
  run_traced dybatpho::is_tty stdout
  assert_success
  run_traced dybatpho::is_tty 1
  assert_success
  # stdin is not mocked, and in the suite it is not a terminal.
  run_traced dybatpho::is_tty stdin
  assert_failure

  dybatpho::mock_tty on 0 2
  run_traced dybatpho::is_tty stdin
  assert_success
  run_traced dybatpho::is_tty stderr
  assert_success

  # A later call changes only the streams it names.
  dybatpho::mock_tty off stderr
  run_traced dybatpho::is_tty stderr
  assert_failure
  run_traced dybatpho::is_tty stdout
  assert_success

  # No stream named means all three.
  dybatpho::mock_tty off
  run_traced dybatpho::is_tty stdout
  assert_failure
  run_traced dybatpho::is_tty stdin
  assert_failure
}

@test "dybatpho::mock_tty steers colour and interactivity" {
  local NO_COLOR="" FORCE_COLOR="" TERM=xterm
  local DYBATPHO_INTERACTIVE=auto DYBATPHO_FORCE=false

  dybatpho::mock_tty on stderr
  run_traced dybatpho::color_supported stderr
  assert_success
  dybatpho::mock_tty off stderr
  run_traced dybatpho::color_supported stderr
  assert_failure

  dybatpho::mock_tty on stdin
  run_traced dybatpho::is_interactive
  assert_success
  dybatpho::mock_tty off stdin
  run_traced dybatpho::is_interactive
  assert_failure

  # The environment still has the last word, as it does on a real terminal.
  dybatpho::mock_tty on
  NO_COLOR=1
  run_traced dybatpho::color_supported stdout
  assert_failure
  DYBATPHO_INTERACTIVE=false
  run_traced dybatpho::is_interactive
  assert_failure
}

@test "dybatpho::mock_tty rejects a bad state or stream, and keeps stream checks" {
  run --separate-stderr dybatpho::mock_tty maybe
  assert_failure
  assert_stderr --partial "Expected on or off"

  run --separate-stderr dybatpho::mock_tty on stdlog
  assert_failure
  assert_stderr --partial "Stream must be stdin, stdout, or stderr"

  dybatpho::mock_tty on
  run --separate-stderr dybatpho::is_tty stdlog
  assert_failure
  assert_stderr --partial "Stream must be stdin, stdout, or stderr"
}

@test "dybatpho::unmock_tty and unmock_all restore the real is_tty" {
  local original
  original="$(declare -f dybatpho::is_tty)"
  dybatpho::unmock_tty

  dybatpho::mock_tty on
  dybatpho::mock_tty on stdout
  dybatpho::unmock_tty
  assert_equal "$(declare -f dybatpho::is_tty)" "${original}"
  run_traced dybatpho::is_tty stdout
  assert_failure

  dybatpho::mock_tty on
  dybatpho::unmock_all
  assert_equal "$(declare -f dybatpho::is_tty)" "${original}"
  assert_equal "${#DYBATPHO_TEST_TTY[@]}" "0"
}

@test "dybatpho::unmock_command makes a hashed command resolve to the real one" {
  dybatpho::mock_command printenv 0 "mocked"
  assert_equal "$(printenv)" "mocked"
  printenv > /dev/null
  dybatpho::unmock_command printenv
  run_traced printenv DYBATPHO_DIR
  assert_success
  assert_output "${DYBATPHO_DIR}"
}

@test "the json assertions and a snapshot diff ask for their modules when they are not loaded" {
  # `testing` does not load `json` or `diff`, so a suite that only checks files
  # and mocks does not pay for them. The assertions that need one report it as
  # an ordinary failure and return, rather than ending the test shell. A child
  # shell started from a file, without the functions this process exports,
  # shows what such a suite sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh" json="${BATS_TEST_TMPDIR}/doc.json"
  printf '{"a":1}\n' > "${json}"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules testing\n' "${DYBATPHO_DIR}/init.sh"
    printf 'export DYBATPHO_TEST_SNAPSHOT_DIR=%q\n' "${BATS_TEST_TMPDIR}/snaps"
    printf 'rc=0; dybatpho::assert_json_valid %q || rc=$?; echo "json rc=${rc}"\n' "${json}"
    printf '%s\n' 'dybatpho::assert_snapshot pinned old > /dev/null 2>&1'
    printf '%s\n' 'rc=0; dybatpho::assert_snapshot pinned new || rc=$?; echo "snapshot rc=${rc}"'
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_output --partial "dybatpho::assert_json_valid needs the json module, load it with: dybatpho::load json"
  assert_output --partial "json rc=1"
  assert_output --partial "Snapshot pinned does not match"
  assert_output --partial "dybatpho::assert_snapshot needs the diff module to show the difference, load it with: dybatpho::load diff"
  assert_output --partial "snapshot rc=1"

  # Once the suite loads them, the JSON assertion passes and the mismatch is drawn.
  rm -rf "${BATS_TEST_TMPDIR}/snaps"
  sed -i 's/--modules testing/--modules testing json diff/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_output --partial "json rc=0"
  assert_output --partial "+new"
  assert_output --partial "snapshot rc=1"
  refute_output --partial "needs the"
}
