#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# keeps its declarations with the functions they describe.
# dyshellint disable=BSG050,BSG033
# @file testing_ops.sh
# @brief Example showing the extended assertion, snapshot, mock, and fixture helpers
# @description Verifies a small "release" script end to end without touching the
#              network, the real filesystem layout, or the developer's environment.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules testing network text

dybatpho::register_common_handlers

# Keep snapshots beside this example instead of the repository's test tree.
dybatpho::fixture_dir EXAMPLE_ROOT
# shellcheck disable=SC2154 # set by the option spec of this script
export DYBATPHO_TEST_SNAPSHOT_DIR="${EXAMPLE_ROOT}/snapshots"

# --- the script under test ---------------------------------------------------

# A miniature release script: it reads configuration, calls an HTTP API, writes
# a manifest, and reports what it did.
# @description The script under test: it reads configuration, calls an API and writes a manifest.
# @arg $1 path Directory to write the release into
function _release_tool {
  local version="${RELEASE_VERSION:?RELEASE_VERSION must be set}"
  local out_dir="$1"

  mkdir -p "${out_dir}"
  dybatpho::curl_do "https://api.example.test/releases/${version}" "${out_dir}/release.json" \
    || return 1

  # shellcheck disable=SC2154 # set by the option spec of this script
  printf '{"version":"%s","channel":"%s"}\n' "${version}" "${RELEASE_CHANNEL}" \
    > "${out_dir}/manifest.json"
  ln -sfn "manifest.json" "${out_dir}/current.json"
  chmod 600 "${out_dir}/manifest.json"

  git tag "v${version}"
  printf 'Released %s on %s\n' "${version}" "${RELEASE_CHANNEL}"
}

# --- fixtures ----------------------------------------------------------------

dybatpho::header "FIXTURES"
# Both fixtures register an exit trap, so nothing is left behind afterwards.
# Declare the targets first: the helpers assign through a name reference.
declare workdir expected_manifest settings
dybatpho::fixture_dir workdir
dybatpho::fixture_file expected_manifest '{"version":"1.5.0","channel":"stable"}' ".json"
dybatpho::info "workdir:  ${workdir}"
dybatpho::info "fixture:  ${expected_manifest}"

# --- mocks -------------------------------------------------------------------

dybatpho::header "MOCKS"
# Environment: set inputs without leaking them into the surrounding shell.
dybatpho::mock_env RELEASE_VERSION=1.5.0 RELEASE_CHANNEL=stable DYBATPHO_CURL_MAX_RETRIES=0

# Command: `git tag` must not touch the real repository.
dybatpho::mock_command git 0 ""

# HTTP: serve a canned response instead of calling the network.
dybatpho::mock_http "api.example.test/releases" 200 '{"artifact":"app-1.5.0.tgz"}' \
  "Content-Type: application/json"

dybatpho::success "Environment, git, and curl are mocked"

# --- run the script under test ----------------------------------------------

dybatpho::header "RUN"
_release_tool "${workdir}/dist"

# --- assertions --------------------------------------------------------------

dybatpho::header "FILE, DIRECTORY, AND SYMLINK ASSERTIONS"
dybatpho::assert_dir "${workdir}/dist"
dybatpho::assert_file "${workdir}/dist/manifest.json"
dybatpho::assert_symlink "${workdir}/dist/current.json" "manifest.json"
dybatpho::assert_file_mode "${workdir}/dist/manifest.json" 600
dybatpho::assert_path_absent "${workdir}/dist/rollback.json"
dybatpho::success "Layout on disk is correct"

dybatpho::header "JSON ASSERTIONS"
dybatpho::assert_json_valid "${workdir}/dist/manifest.json"
dybatpho::assert_json_query "${workdir}/dist/manifest.json" '.version' "1.5.0"
dybatpho::assert_json_has "${workdir}/dist/release.json" '.artifact'
dybatpho::assert_json_query "${expected_manifest}" '.channel' "stable"
dybatpho::success "Manifest and API response have the expected shape"

dybatpho::header "YAML ASSERTIONS"
dybatpho::fixture_file settings 'mode: production' ".yaml"
dybatpho::assert_yaml_valid "${settings}"
dybatpho::assert_yaml_query "${settings}" '.mode' "production"
dybatpho::assert_yaml_has "${settings}" '.mode'
dybatpho::success "YAML settings validated"

dybatpho::header "MOCK ASSERTIONS"
dybatpho::assert_http_called "api.example.test/releases/1.5.0"
dybatpho::assert_mock_called git tag v1.5.0
mock_call_count_2=$(dybatpho::mock_call_count git)
mock_call_count=${mock_call_count_2}
mock_call_count_3=$(dybatpho::mock_call_count curl)
dybatpho::info "curl calls: ${mock_call_count_3}, git calls: ${mock_call_count}"
dybatpho::success "The script called the API and tagged the release"

dybatpho::header "SNAPSHOT TESTING"
# Volatile values would otherwise change the snapshot on every run.
dybatpho::snapshot_scrub "${workdir}" '<WORKDIR>'
dybatpho::assert_cli_snapshot release-run -- _release_tool "${workdir}/dist2"
dybatpho::info "Recorded snapshot:"
cat_2=$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/release-run.snap")
dybatpho::text_indent "${cat_2}" "  "
# Running again compares against the snapshot recorded a moment ago.
dybatpho::assert_cli_snapshot release-run -- _release_tool "${workdir}/dist2"
dybatpho::success "CLI output is stable across runs"

dybatpho::header "GOLDEN UPDATE"
# After an intended change to the output, regenerate every snapshot in one run
# instead of deleting `.snap` files by hand:
#
#   UPDATE_SNAPSHOTS=1 bats test/
#
# The switch is read on every comparison, so it rewrites whatever the suite
# touches. `0`, `false` and an empty value all leave the baselines alone.
export UPDATE_SNAPSHOTS=1
dybatpho::assert_cli_snapshot release-run -- _release_tool "${workdir}/dist3"
export UPDATE_SNAPSHOTS=0
dybatpho::info "Snapshot after the bulk update:"
cat=$(cat "${DYBATPHO_TEST_SNAPSHOT_DIR}/release-run.snap")
dybatpho::text_indent "${cat}" "  "
dybatpho::success "Baseline regenerated, then comparison resumed"

dybatpho::header "DURATION BUDGETS"
# A budget guards the shape of the cost, not the exact millisecond count.
# Several runs keep the fastest, so one descheduled run does not fail a suite.
export DYBATPHO_TEST_DURATION_RUNS=3
dybatpho::assert_duration_under 5000 -- _release_tool "${workdir}/dist4"
# shellcheck disable=SC2154 # set by the option spec of this script
dybatpho::info "Fastest run: ${DYBATPHO_TEST_LAST_DURATION_MS}ms"

# A benchmark only measures and reports; assert on the median when you want it
# enforced.
dybatpho::benchmark release-tool 3 -- _release_tool "${workdir}/dist5"
dybatpho::success "Release path stayed inside its budget"

# An overrun is reported, not fatal, like every other assertion here.
if dybatpho::assert_duration_under 1 -- sleep 0.05; then
  dybatpho::error "Expected the overrun to be reported"
else
  dybatpho::warn "Overrun reported as expected"
fi

dybatpho::header "EXIT CODES"
# An error path is one line: the status it must return, then the command.
dybatpho::mock_env RELEASE_VERSION=""
dybatpho::assert_exit_code 1 -- bash -c 'echo "RELEASE_VERSION must be set" >&2; exit 1'
dybatpho::mock_command git 128 "fatal: tag already exists"
dybatpho::assert_exit_code 128 -- git tag v1.5.0
dybatpho::success "Both failures returned the status they promise"

# --- clock and terminal ------------------------------------------------------

dybatpho::header "FROZEN CLOCK"
# Every `date` asking for "now" -- here and in child processes -- answers from
# the frozen moment, so an age or a timestamp is an exact value.
declare stamp
dybatpho::fixture_file stamp "written at the frozen moment"
dybatpho::mock_time 1767225600
now_text=$(date -u '+%F %T')
dybatpho::info "now: ${now_text} UTC"
# Freeze at the moment the fixture was written, then let 90 seconds pass.
written=$(dybatpho::file_mtime "${stamp}")
dybatpho::mock_time "${written}"
dybatpho::mock_time_advance 90
age=$(dybatpho::file_age_seconds "${stamp}")
dybatpho::info "stamp age after advancing 90s: ${age}s"
dybatpho::unmock_time
dybatpho::success "Clock frozen, moved, and released"

dybatpho::header "TERMINAL DETECTION"
# The example runs without a terminal; pretend stderr has one to test the
# coloured path, then pretend it has none.
dybatpho::mock_tty on stderr
if (unset NO_COLOR && dybatpho::color_supported stderr); then
  dybatpho::info "stderr is treated as a colour terminal"
fi
dybatpho::mock_tty off stderr
dybatpho::color_supported stderr || dybatpho::info "stderr is treated as a pipe"
dybatpho::unmock_tty
dybatpho::success "Terminal detection followed the mock"

# --- failure reporting -------------------------------------------------------

dybatpho::header "FAILURE REPORTING"
# Assertions return 1 instead of exiting, so a failure can be handled inline.
if dybatpho::assert_json_query "${workdir}/dist/manifest.json" '.version' "9.9.9"; then
  dybatpho::error "Expected the mismatched version to be reported"
else
  dybatpho::warn "Mismatch reported as expected"
fi
# shellcheck disable=SC2154 # set by the option spec of this script
dybatpho::info "Recorded assertion failures: ${DYBATPHO_TEST_FAILURES}"

# --- teardown ----------------------------------------------------------------

dybatpho::header "TEARDOWN"
dybatpho::unmock_all
dybatpho::info "RELEASE_VERSION after unmock: ${RELEASE_VERSION:-<unset>}"
dybatpho::success "Testing helpers demo complete; fixtures are removed on exit"
