# shellcheck shell=bash
# @file testing.sh
# @brief Extended assertions, snapshots, mocks, and self-cleaning fixtures for shell tests
# @namespace dybatpho
# @description
#   This module extends the plain `dybatpho::assert` guard from `helpers.sh`
#   with the pieces a shell test suite usually has to hand-roll:
#
#   - assertions for files, directories, symlinks, permissions, JSON, and YAML
#   - snapshot testing for CLI output, including exit code and stderr,
#     regenerated in bulk with `UPDATE_SNAPSHOTS=1`
#   - duration budgets and benchmarks for the code paths a user waits on
#   - mocks for environment variables, external commands, and HTTP responses
#   - fixtures that register themselves for `trap`-based cleanup on exit
#
#   Assertions never terminate the shell. They write a diagnostic to stderr and
#   return `1`, so they compose with `if`, `&&`, and the Bats `run` helper.
#   Only programming mistakes, such as a missing argument, are fatal.
# @usage
#   ### Assert on a generated file
#
#   ```bash
#   dybatpho::assert_file "dist/app.tgz"
#   dybatpho::assert_file_mode "${HOME}/.netrc" 600
#   ```
#
#   ### Snapshot the output of a CLI
#
#   ```bash
#   dybatpho::assert_cli_snapshot deploy-help -- ./mytool deploy --help
#   ```
#
#   ### Refresh every snapshot after an intended change
#
#   ```bash
#   UPDATE_SNAPSHOTS=1 bats test/
#   ```
#
#   ### Keep a hot path inside its budget
#
#   ```bash
#   dybatpho::assert_duration_under 200 -- ./mytool completions bash
#   ```
#
#   ### Mock an external command
#
#   ```bash
#   dybatpho::mock_command kubectl 0 "pod/api-1 Running"
#   ./deploy.sh
#   dybatpho::assert_mock_called kubectl get pods
#   ```
# @see
#   - `example/testing_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_TEST_SNAPSHOT_DIR string Directory holding `.snap` files, default is `test/snapshots` under the current
#   directory
DYBATPHO_TEST_SNAPSHOT_DIR="${DYBATPHO_TEST_SNAPSHOT_DIR:-${PWD}/test/snapshots}"
# @env DYBATPHO_TEST_UPDATE_SNAPSHOTS string Set to `1`, `true`, `yes`, or `on` to rewrite snapshots instead of
#   comparing
#   them
DYBATPHO_TEST_UPDATE_SNAPSHOTS="${DYBATPHO_TEST_UPDATE_SNAPSHOTS:-false}"
# @env UPDATE_SNAPSHOTS string Unprefixed alias for `DYBATPHO_TEST_UPDATE_SNAPSHOTS`, so a whole suite regenerates with
#   `UPDATE_SNAPSHOTS=1 <test runner>`
UPDATE_SNAPSHOTS="${UPDATE_SNAPSHOTS:-}"
# @env DYBATPHO_TEST_DURATION_RUNS number How many times `dybatpho::assert_duration_under` runs a command, keeping the
#   fastest, default is `1`
DYBATPHO_TEST_DURATION_RUNS="${DYBATPHO_TEST_DURATION_RUNS:-1}"
# @env DYBATPHO_TEST_LAST_DURATION_MS number Milliseconds measured by the last duration assertion or benchmark
DYBATPHO_TEST_LAST_DURATION_MS="${DYBATPHO_TEST_LAST_DURATION_MS:-0}"
# @env DYBATPHO_TEST_BENCH_MIN_MS number Fastest run of the last benchmark, in milliseconds
DYBATPHO_TEST_BENCH_MIN_MS="${DYBATPHO_TEST_BENCH_MIN_MS:-0}"
# @env DYBATPHO_TEST_BENCH_MEDIAN_MS number Median run of the last benchmark, in milliseconds
DYBATPHO_TEST_BENCH_MEDIAN_MS="${DYBATPHO_TEST_BENCH_MEDIAN_MS:-0}"
# @env DYBATPHO_TEST_BENCH_MAX_MS number Slowest run of the last benchmark, in milliseconds
DYBATPHO_TEST_BENCH_MAX_MS="${DYBATPHO_TEST_BENCH_MAX_MS:-0}"
# @env DYBATPHO_TEST_FAILURES number Count of assertion failures recorded in this shell
DYBATPHO_TEST_FAILURES="${DYBATPHO_TEST_FAILURES:-0}"

declare -g DYBATPHO_TEST_MOCK_DIR="${DYBATPHO_TEST_MOCK_DIR:-}"
declare -ga DYBATPHO_TEST_SNAPSHOT_SCRUBS=()
declare -gA DYBATPHO_TEST_ENV_BACKUP=()
declare -ga DYBATPHO_TEST_ENV_KEYS=()
declare -gA DYBATPHO_TEST_TTY=()
declare -g DYBATPHO_TEST_TTY_ORIGINAL="${DYBATPHO_TEST_TTY_ORIGINAL:-}"

#######################################
# @description Record an assertion failure and return a failing status.
# @arg $@ string Diagnostic lines describing the failure
# @set DYBATPHO_TEST_FAILURES Incremented by one
# @stderr The formatted diagnostic
# @exitcode 1 Always
# @internal
#######################################
function __dybatpho_test_fail {
  local line
  DYBATPHO_TEST_FAILURES=$((DYBATPHO_TEST_FAILURES + 1))
  for line in "$@"; do
    dybatpho::error "${line}"
  done
  return 1
}

#######################################
# @description Fail the calling assertion unless the `json` module is loaded.
#   Querying a document is the `json` module's work, and only the JSON and YAML
#   assertions do it. Registering it as a dependency would load it into every
#   test suite that only checks files and mocks, so those assertions ask for it
#   instead. Like every assertion here, the check reports and returns rather
#   than ending the test shell, so a suite sees an ordinary failing assertion
#   that names the module to load.
#
#   The guard names an internal helper on purpose: `dybatpho::` functions are
#   exported and a child shell inherits them without the internals they call,
#   so testing the public name would pass in a child that never loaded `json`
#   and then fail on the first internal call.
# @noargs
# @set DYBATPHO_TEST_FAILURES Incremented by one when the module is missing
# @stderr The diagnostic naming the module, when it is missing
# @exitcode 0 The `json` module is loaded
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_test_need_json {
  declare -F __dybatpho_json_cmd_into > /dev/null && return 0
  __dybatpho_test_fail "${FUNCNAME[1]} needs the json module, load it with: dybatpho::load json"
}

#######################################
# @description Resolve an input that is either a file path or `-` for stdin into a readable file.
# @arg $1 string File path, or `-` to buffer stdin into a fixture
# @arg $2 string Variable name that receives the resolved path
# @tip This assigns through a name reference instead of printing, so the cleanup trap
#      registered for a buffered stdin fixture is not discarded with a command substitution.
# @internal
#######################################
function __dybatpho_test_input_file {
  local input path_var
  dybatpho::expect_args input path_var -- "$@"
  local -n resolved="${path_var}"
  if [[ "${input}" != "-" ]]; then
    resolved="${input}"
    return 0
  fi
  dybatpho::create_temp resolved ".input" "assert"
  cat > "${resolved}"
}

#######################################
# @description Create the mock `bin` directory on demand and prepend it to `PATH`.
# @noargs
# @set DYBATPHO_TEST_MOCK_DIR Path of the directory holding mock executables
# @set PATH Prefixed with the mock directory the first time a mock is created
# @tip This must run in the calling shell, never inside `$(...)`, or the `PATH`
#      change is discarded with the subshell.
# @internal
#######################################
function __dybatpho_test_mock_init {
  if [[ -n "${DYBATPHO_TEST_MOCK_DIR}" && -d "${DYBATPHO_TEST_MOCK_DIR}" ]]; then
    return 0
  fi
  dybatpho::create_temp DYBATPHO_TEST_MOCK_DIR "" "mockbin"
  mkdir -p "${DYBATPHO_TEST_MOCK_DIR}/calls"
  PATH="${DYBATPHO_TEST_MOCK_DIR}:${PATH}"
  export PATH DYBATPHO_TEST_MOCK_DIR
}

#######################################
# @description Assert that a path exists and is a regular file.
# @arg $1 string Path to check
# @arg $2 string Optional message replacing the default diagnostic
# @exitcode 0 The path is a regular file
# @exitcode 1 The path is missing or is not a regular file
#######################################
function dybatpho::assert_file {
  local path
  dybatpho::expect_args path -- "$@"
  if ! dybatpho::is file "${path}"; then
    __dybatpho_test_fail "${2:-Expected a regular file: ${path}}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a path exists and is a directory.
# @arg $1 string Path to check
# @arg $2 string Optional message replacing the default diagnostic
# @exitcode 0 The path is a directory
# @exitcode 1 The path is missing or is not a directory
#######################################
function dybatpho::assert_dir {
  local path
  dybatpho::expect_args path -- "$@"
  if ! dybatpho::is dir "${path}"; then
    __dybatpho_test_fail "${2:-Expected a directory: ${path}}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a path is a symbolic link, optionally pointing at an expected target.
# @arg $1 string Path to check
# @arg $2 string Optional expected link target, compared literally
# @exitcode 0 The path is a symlink and matches the expected target when one is given
# @exitcode 1 The path is not a symlink, or points somewhere else
#######################################
function dybatpho::assert_symlink {
  local path
  dybatpho::expect_args path -- "$@"
  if ! dybatpho::is link "${path}"; then
    __dybatpho_test_fail "Expected a symbolic link: ${path}"
    return 1
  fi
  (($# > 1)) || return 0

  local target
  target="$(readlink "${path}")"
  if [[ "${target}" != "$2" ]]; then
    __dybatpho_test_fail \
      "Symbolic link ${path} points at the wrong target" \
      "  expected: $2" \
      "  actual:   ${target}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that nothing exists at a path.
# @arg $1 string Path that must not exist
# @exitcode 0 Nothing exists at the path
# @exitcode 1 A file, directory, or link exists at the path
#######################################
function dybatpho::assert_path_absent {
  local path
  dybatpho::expect_args path -- "$@"
  if dybatpho::is exist "${path}" || dybatpho::is link "${path}"; then
    __dybatpho_test_fail "Expected nothing at: ${path}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a file contains an exact substring.
# @arg $1 string File path
# @arg $2 string Substring that must appear in the file
# @exitcode 0 The substring was found
# @exitcode 1 The file is unreadable or the substring is absent
#######################################
function dybatpho::assert_file_contains {
  local path needle
  dybatpho::expect_args path needle -- "$@"
  if ! dybatpho::is readable "${path}"; then
    __dybatpho_test_fail "Expected a readable file: ${path}"
    return 1
  fi

  local content
  content="$(< "${path}")"
  if ! dybatpho::string_contains "${content}" "${needle}"; then
    __dybatpho_test_fail "File ${path} does not contain: ${needle}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a file exists and holds no content.
# @arg $1 string File path
# @exitcode 0 The file exists and is empty
# @exitcode 1 The file is missing or has content
#######################################
function dybatpho::assert_file_empty {
  local path
  dybatpho::expect_args path -- "$@"
  dybatpho::assert_file "${path}" || return 1
  if [[ -s "${path}" ]]; then
    __dybatpho_test_fail "Expected an empty file: ${path}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a file or directory carries exact octal permissions.
# @example
#   dybatpho::assert_file_mode "${HOME}/.netrc" 600
#
# @arg $1 string Path to check
# @arg $2 string Expected octal mode, such as `600` or `0700`
# @exitcode 0 The permissions match
# @exitcode 1 The path is missing or its permissions differ
# @tip Useful for verifying that secret files are not group- or world-readable
#######################################
function dybatpho::assert_file_mode {
  local path expected
  dybatpho::expect_args path expected -- "$@"
  if ! dybatpho::is exist "${path}"; then
    __dybatpho_test_fail "Expected an existing path: ${path}"
    return 1
  fi

  local actual
  if ! actual="$(stat -c '%a' "${path}" 2> /dev/null)"; then
    # kcov(disabled) - the BSD stat fallback doesn't run on the Linux CI image
    if ! actual="$(stat -f '%Lp' "${path}" 2> /dev/null)"; then
      __dybatpho_test_fail "Unable to read permissions of: ${path}"
      return 1
    fi
    # kcov(enabled)
  fi
  # Compare numerically so `600` and `0600` describe the same mode.
  if ((10#${actual} != 10#${expected})); then
    __dybatpho_test_fail \
      "Wrong permissions on ${path}" \
      "  expected: ${expected}" \
      "  actual:   ${actual}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a document is parsable JSON.
# @arg $1 string JSON file path, or `-` for stdin
# @exitcode 0 The document parses as JSON
# @exitcode 1 The document is missing or malformed
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_json_valid {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_test_need_json || return 1
  local file
  __dybatpho_test_input_file "${input}" file
  if ! dybatpho::json_query "${file}" '.' > /dev/null 2>&1; then
    __dybatpho_test_fail "Expected valid JSON: ${input}"
    return 1
  fi
  return 0
}

#######################################
# @description Compare a query result with an expected scalar, tolerating JSON quoting.
# @arg $1 string Value printed by the JSON/YAML backend
# @arg $2 string Expected value
# @exitcode 0 The values match, either literally or after unquoting the result
# @exitcode 1 The values differ
# @tip Backends print string scalars as `"value"`, so both `value` and `"value"`
#      are accepted as the expected form.
# @internal
#######################################
function __dybatpho_test_scalar_matches {
  local actual expected
  dybatpho::expect_args actual expected -- "$@"
  if [[ "${actual}" == "${expected}" ]]; then
    return 0
  fi
  if [[ "${actual}" == '"'*'"' ]]; then
    if [[ "${actual:1:${#actual}-2}" == "${expected}" ]]; then
      return 0
    fi
  fi
  return 1
}

#######################################
# @description Assert that a JSON query prints an expected value.
# @example
#   dybatpho::assert_json_query package.json '.version' "1.4.2"
#
# @arg $1 string JSON file path, or `-` for stdin
# @arg $2 string Query filter understood by the JSON backend
# @arg $3 string Expected query result
# @exitcode 0 The query result matches
# @exitcode 1 The query failed or returned a different value
# @tip String scalars are compared without their JSON quoting, so an expected
#      value of `1.4.2` matches a backend result of `"1.4.2"`.
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_json_query {
  local input filter expected
  dybatpho::expect_args input filter expected -- "$@"
  __dybatpho_test_need_json || return 1
  local file actual
  __dybatpho_test_input_file "${input}" file
  if ! actual="$(dybatpho::json_query "${file}" "${filter}" 2> /dev/null)"; then
    __dybatpho_test_fail "JSON query failed on ${input}: ${filter}"
    return 1
  fi
  if ! __dybatpho_test_scalar_matches "${actual}" "${expected}"; then
    __dybatpho_test_fail \
      "JSON query ${filter} returned an unexpected value" \
      "  expected: ${expected}" \
      "  actual:   ${actual}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a JSON filter matches something in the document.
# @arg $1 string JSON file path, or `-` for stdin
# @arg $2 string Query filter that must succeed
# @exitcode 0 The filter matched
# @exitcode 1 The filter did not match
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_json_has {
  local input filter
  dybatpho::expect_args input filter -- "$@"
  __dybatpho_test_need_json || return 1
  local file
  __dybatpho_test_input_file "${input}" file
  if ! dybatpho::json_has "${file}" "${filter}"; then
    __dybatpho_test_fail "JSON filter did not match in ${input}: ${filter}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a document is parsable YAML.
# @arg $1 string YAML file path, or `-` for stdin
# @exitcode 0 The document parses as YAML
# @exitcode 1 The document is missing or malformed
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_yaml_valid {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_test_need_json || return 1
  local file
  __dybatpho_test_input_file "${input}" file
  if ! dybatpho::yaml_query "${file}" '.' > /dev/null 2>&1; then
    __dybatpho_test_fail "Expected valid YAML: ${input}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a YAML expression prints an expected value.
# @arg $1 string YAML file path, or `-` for stdin
# @arg $2 string `yq` expression
# @arg $3 string Expected result
# @exitcode 0 The expression result matches
# @exitcode 1 The expression failed or returned a different value
# @tip String scalars are compared without their JSON quoting, so an expected
#      value of `1.4.2` matches a backend result of `"1.4.2"`.
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_yaml_query {
  local input expression expected
  dybatpho::expect_args input expression expected -- "$@"
  __dybatpho_test_need_json || return 1
  local file actual
  __dybatpho_test_input_file "${input}" file
  if ! actual="$(dybatpho::yaml_query "${file}" "${expression}" 2> /dev/null)"; then
    __dybatpho_test_fail "YAML query failed on ${input}: ${expression}"
    return 1
  fi
  if ! __dybatpho_test_scalar_matches "${actual}" "${expected}"; then
    __dybatpho_test_fail \
      "YAML query ${expression} returned an unexpected value" \
      "  expected: ${expected}" \
      "  actual:   ${actual}"
    return 1
  fi
  return 0
}

#######################################
# @description Assert that a YAML expression matches something in the document.
# @arg $1 string YAML file path, or `-` for stdin
# @arg $2 string `yq` expression that must succeed
# @exitcode 0 The expression matched
# @exitcode 1 The expression did not match
# @note Needs the `json` module: `dybatpho::load json`, or `--modules testing json`
#######################################
function dybatpho::assert_yaml_has {
  local input expression
  dybatpho::expect_args input expression -- "$@"
  __dybatpho_test_need_json || return 1
  local file
  __dybatpho_test_input_file "${input}" file
  if ! dybatpho::yaml_has "${file}" "${expression}"; then
    __dybatpho_test_fail "YAML expression did not match in ${input}: ${expression}"
    return 1
  fi
  return 0
}

#######################################
# @description Register a substitution applied to text before it is snapshotted.
# @example
#   dybatpho::snapshot_scrub '/tmp/[A-Za-z0-9_]*' '<TMPDIR>'
#
# @arg $1 string Basic regular expression understood by `sed`
# @arg $2 string Replacement text
# @set DYBATPHO_TEST_SNAPSHOT_SCRUBS Appends the substitution
# @tip Use this to remove timestamps, temporary paths, and process ids that would
#      otherwise make a snapshot fail on every run.
#######################################
function dybatpho::snapshot_scrub {
  local pattern replacement
  dybatpho::expect_args pattern replacement -- "$@"
  DYBATPHO_TEST_SNAPSHOT_SCRUBS+=("s|${pattern}|${replacement}|g")
}

#######################################
# @description Forget every registered snapshot substitution.
# @noargs
# @set DYBATPHO_TEST_SNAPSHOT_SCRUBS Emptied
#######################################
function dybatpho::snapshot_scrub_reset {
  DYBATPHO_TEST_SNAPSHOT_SCRUBS=()
}

#######################################
# @description Normalize text for snapshotting by stripping colors and applying scrubs.
# @arg $1 string Text to normalize
# @stdout Normalized text
# @internal
#######################################
function __dybatpho_test_normalize {
  local text
  dybatpho::expect_args text -- "$@"
  text="$(dybatpho::text_strip_ansi "${text}")"
  local script
  for script in ${DYBATPHO_TEST_SNAPSHOT_SCRUBS[@]+"${DYBATPHO_TEST_SNAPSHOT_SCRUBS[@]}"}; do
    text="$(printf '%s\n' "${text}" | sed -e "${script}")"
  done
  printf '%s' "${text}"
}

#######################################
# @description Answer whether snapshots are being regenerated rather than compared.
# @noargs
# @env DYBATPHO_TEST_UPDATE_SNAPSHOTS string Prefixed switch
# @env UPDATE_SNAPSHOTS string Unprefixed alias, consulted when the prefixed switch is not truthy
# @exitcode 0 Snapshots are to be rewritten
# @exitcode 1 Snapshots are to be compared
# @tip `dybatpho::is true` reads `0` as true, because it speaks in exit codes.
#      An environment variable does not: `UPDATE_SNAPSHOTS=0` means off, and a
#      suite regenerated by accident is a suite that asserts nothing.
# @internal
#######################################
function __dybatpho_test_updating_snapshots {
  local setting
  for setting in "${DYBATPHO_TEST_UPDATE_SNAPSHOTS:-}" "${UPDATE_SNAPSHOTS:-}"; do
    case "${setting}" in
      1 | [tT][rR][uU][eE] | [yY][eE][sS] | [oO][nN]) return 0 ;;
      *) ;;
    esac
  done
  return 1
}

#######################################
# @description Compare text against a stored snapshot, creating it when missing.
# @example
#   dybatpho::assert_snapshot version-output "$(./mytool --version)"
#
# @arg $1 string Snapshot name, stored as `<name>.snap` inside the snapshot directory
# @arg $2 string Text to compare; omit to read the text from stdin
# @env DYBATPHO_TEST_SNAPSHOT_DIR string Directory holding the `.snap` files
# @env DYBATPHO_TEST_UPDATE_SNAPSHOTS string Set to `1`, `true`, `yes`, or `on` to rewrite the snapshot
# @env UPDATE_SNAPSHOTS string Unprefixed alias for the same switch
# @stderr A unified diff when the text and the snapshot differ
# @exitcode 0 The text matches, or the snapshot was created or updated
# @exitcode 1 The text differs from the stored snapshot
# @tip A missing snapshot is written and passes, so the first run records the baseline.
# @tip Trailing blank lines are not preserved, because the text passes through a
#      command substitution; a snapshot cannot assert on them.
# @note Showing the difference on a mismatch needs the `diff` module: `dybatpho::load diff`
#######################################
function dybatpho::assert_snapshot {
  local name actual
  dybatpho::expect_args name -- "$@"
  [[ "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid snapshot name: ${name}"
  if (($# > 1)); then
    actual="$2"
  else
    actual="$(cat)"
  fi
  actual="$(__dybatpho_test_normalize "${actual}")"

  local snapshot_file="${DYBATPHO_TEST_SNAPSHOT_DIR%/}/${name}.snap"
  if [[ ! -f "${snapshot_file}" ]] || __dybatpho_test_updating_snapshots; then
    mkdir -p "${DYBATPHO_TEST_SNAPSHOT_DIR%/}"
    printf '%s\n' "${actual}" > "${snapshot_file}"
    dybatpho::info "Wrote snapshot ${snapshot_file}"
    return 0
  fi

  local expected
  expected="$(< "${snapshot_file}")"
  if [[ "${actual}" == "${expected}" ]]; then
    return 0
  fi
  __dybatpho_test_fail "Snapshot ${name} does not match ${snapshot_file}"
  # The difference is drawn by `diff`, which `testing` does not load: the
  # mismatch is reported either way, and only its rendering needs the module.
  if ! declare -F __dybatpho_diff_paint > /dev/null; then
    dybatpho::error "${FUNCNAME[0]} needs the diff module to show the difference, load it with: dybatpho::load diff"
    return 1
  fi
  # Through `diff.sh` rather than a raw `diff -u`, so a snapshot failure reads
  # the same as every other comparison the library prints, colored included.
  # The captured text goes to a file first: `dybatpho::diff_text` reads a side
  # that names an existing file as that file, and a CLI whose output is a path
  # would otherwise have that file's contents diffed instead of its own output.
  local actual_file
  dybatpho::create_temp actual_file ".snap" "snapshot-actual"
  printf '%s\n' "${actual}" > "${actual_file}"
  dybatpho::diff_text "${snapshot_file}" "${actual_file}" snapshot actual >&2 || true
  return 1
}

#######################################
# @description Snapshot the stdout, stderr, and exit code of a command.
# @example
#   dybatpho::assert_cli_snapshot deploy-help -- ./mytool deploy --help
#
# @arg $1 string Snapshot name
# @arg $2 string Literal `--` separating the name from the command
# @arg $@ string Command and arguments to run
# @env DYBATPHO_TEST_SNAPSHOT_DIR string Directory holding the `.snap` files
# @stderr A unified diff when the captured output differs from the snapshot
# @exitcode 0 The captured output matches the snapshot
# @exitcode 1 The captured output differs
# @tip The command's own exit code is recorded inside the snapshot rather than
#      propagated, so a CLI that exits non-zero can still be snapshotted.
#######################################
function dybatpho::assert_cli_snapshot {
  local name separator
  dybatpho::expect_args name separator -- "$@"
  shift 2
  [[ "${separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: name -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local stdout_file stderr_file exit_code=0
  dybatpho::create_temp stdout_file ".out" "snapshot"
  dybatpho::create_temp stderr_file ".err" "snapshot"
  "$@" > "${stdout_file}" 2> "${stderr_file}" || exit_code=$?

  local document
  printf -v document '$ %s\n--- exit: %s\n--- stdout:\n%s\n--- stderr:\n%s' \
    "$*" "${exit_code}" "$(< "${stdout_file}")" "$(< "${stderr_file}")"
  dybatpho::assert_snapshot "${name}" "${document}"
}

#######################################
# @description Assert that a command exits with an expected status.
#
#   The command runs in the current shell, so the mocks and variables a test has
#   set up apply to it, and its stdout and stderr are captured rather than
#   printed. They are only shown when the status is not the one expected, which
#   is the moment they explain something.
# @example
#   dybatpho::assert_exit_code 2 -- ./mytool --unknown-flag
#   dybatpho::assert_exit_code 0 -- dybatpho::semver_valid 1.2.3
#
# @arg $1 number Expected exit status, from `0` to `255`
# @arg $2 string Literal `--` separating the status from the command
# @arg $@ string Command and arguments to run
# @set DYBATPHO_TEST_FAILURES Incremented when the status differs
# @stderr A diagnostic naming the expected and actual status, followed by the
#         command's own output
# @exitcode 0 The command exited with the expected status
# @exitcode 1 The command exited with any other status
# @tip A command that calls `exit` ends the shell running it. Wrap a script's
#      function in `bash -c` or call the script itself when it exits rather than
#      returns.
#######################################
function dybatpho::assert_exit_code {
  local expected separator
  dybatpho::expect_args expected separator -- "$@"
  shift 2
  if [[ ! "${expected}" =~ ^[0-9]+$ ]] || ((10#${expected} > 255)); then
    dybatpho::die "${FUNCNAME[0]}: Expected an exit status from 0 to 255: ${expected}"
  fi
  [[ "${separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: status -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local output_file status=0
  dybatpho::create_temp output_file ".log" "exitcode"
  "$@" > "${output_file}" 2>&1 || status=$?

  ((status == 10#${expected})) && return 0
  __dybatpho_test_fail \
    "Expected exit ${expected}, got ${status}: $*" \
    "$(< "${output_file}")"
}

#######################################
# @description Run a command once and report how long it took.
# @arg $1 string Path of a file collecting the command's stdout and stderr
# @arg $2 string Variable name that receives the elapsed milliseconds
# @arg $@ string Command and arguments to run
# @exitcode * The command's own exit code
# @internal
#######################################
function __dybatpho_test_time_command {
  local output_file elapsed_var
  dybatpho::expect_args output_file elapsed_var -- "$@"
  shift 2
  local -n __elapsed="${elapsed_var}"
  local started status=0
  started="$(__dybatpho_log_now_ms)"
  "$@" >> "${output_file}" 2>&1 || status=$?
  __elapsed=$(($(__dybatpho_log_now_ms) - started))
  ((__elapsed < 0)) && __elapsed=0
  return "${status}"
}

#######################################
# @description Assert that a command finishes in under a budget of milliseconds.
# @example
#   dybatpho::assert_duration_under 200 -- ./mytool completions bash
#
# @arg $1 number Budget in whole milliseconds; the command must finish in less than this
# @arg $2 string Literal `--` separating the budget from the command
# @arg $@ string Command and arguments to run
# @env DYBATPHO_TEST_DURATION_RUNS number How many times to run the command, keeping the fastest
# @set DYBATPHO_TEST_LAST_DURATION_MS number Fastest run measured, in milliseconds
# @set DYBATPHO_TEST_FAILURES Incremented when the command fails or overruns the budget
# @stderr A diagnostic naming the budget and the measured time, followed by the
#         command's own output when it failed
# @exitcode 0 The command succeeded and stayed under the budget
# @exitcode 1 The command failed, or took at least the budget
# @tip A machine under load makes a tight budget flaky. Set
#      `DYBATPHO_TEST_DURATION_RUNS` above `1` so a single descheduled run does
#      not fail the suite: the fastest run is the one that measures the code
#      rather than the machine.
# @tip Budget for the shape of the cost, not the current number. A regression
#      worth catching is a loop that became quadratic, not a run that drifted by
#      five milliseconds.
#######################################
function dybatpho::assert_duration_under {
  local budget separator
  dybatpho::expect_args budget separator -- "$@"
  shift 2
  [[ "${budget}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected a budget in milliseconds: ${budget}"
  [[ "${separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: milliseconds -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local runs="${DYBATPHO_TEST_DURATION_RUNS}"
  [[ "${runs}" =~ ^[1-9][0-9]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: DYBATPHO_TEST_DURATION_RUNS must be a positive number: ${runs}"

  local output_file
  dybatpho::create_temp output_file ".log" "duration"

  local run elapsed status=0 fastest=""
  for ((run = 0; run < runs; run++)); do
    __dybatpho_test_time_command "${output_file}" elapsed "$@" || status=$?
    if ((status != 0)); then
      __dybatpho_test_fail \
        "Command exited ${status} while timing it: $*" \
        "$(< "${output_file}")"
      return 1
    fi
    if [[ -z "${fastest}" ]] || ((elapsed < fastest)); then
      fastest="${elapsed}"
    fi
  done

  DYBATPHO_TEST_LAST_DURATION_MS="${fastest}"
  if ((fastest < budget)); then
    return 0
  fi
  __dybatpho_test_fail \
    "Expected to finish in under ${budget}ms, took ${fastest}ms over ${runs} run(s): $*"
  return 1
}

#######################################
# @description Time a command over several runs and report its fastest, median, and slowest.
# @example
#   dybatpho::benchmark parse-config 20 -- ./mytool config show
#
# @arg $1 string Label printed with the measurements
# @arg $2 number How many times to run the command
# @arg $3 string Literal `--` separating the arguments from the command
# @arg $@ string Command and arguments to run
# @set DYBATPHO_TEST_BENCH_MIN_MS number Fastest run, in milliseconds
# @set DYBATPHO_TEST_BENCH_MEDIAN_MS number Median run, in milliseconds
# @set DYBATPHO_TEST_BENCH_MAX_MS number Slowest run, in milliseconds
# @set DYBATPHO_TEST_LAST_DURATION_MS number Median run, in milliseconds
# @stdout One line: `<label> runs=<n> min=<ms>ms median=<ms>ms max=<ms>ms`
# @exitcode 0 Every run succeeded
# @exitcode 1 A run failed, with its output on stderr
# @tip This measures and reports; it asserts nothing. Compare the median against
#      a budget with `dybatpho::assert_duration_under`, or record the line in a
#      log to watch the number move between releases.
# @tip The median, not the mean, because one descheduled run drags a mean and
#      leaves a median where it was.
#######################################
function dybatpho::benchmark {
  local label runs separator
  dybatpho::expect_args label runs separator -- "$@"
  shift 3
  [[ "${runs}" =~ ^[1-9][0-9]*$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected a positive number of runs: ${runs}"
  [[ "${separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: label runs -- command [args...]"
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected a command to run after --"

  local output_file
  dybatpho::create_temp output_file ".log" "benchmark"

  local run elapsed status=0
  local -a samples=()
  for ((run = 0; run < runs; run++)); do
    __dybatpho_test_time_command "${output_file}" elapsed "$@" || status=$?
    if ((status != 0)); then
      __dybatpho_test_fail \
        "Command exited ${status} on run $((run + 1)) of ${runs}: $*" \
        "$(< "${output_file}")"
      return 1
    fi
    samples+=("${elapsed}")
  done

  local -a sorted=()
  mapfile -t sorted < <(printf '%s\n' "${samples[@]}" | sort -n)
  DYBATPHO_TEST_BENCH_MIN_MS="${sorted[0]}"
  DYBATPHO_TEST_BENCH_MAX_MS="${sorted[-1]}"
  DYBATPHO_TEST_BENCH_MEDIAN_MS="${sorted[$((${#sorted[@]} / 2))]}"
  DYBATPHO_TEST_LAST_DURATION_MS="${DYBATPHO_TEST_BENCH_MEDIAN_MS}"
  printf '%s runs=%s min=%sms median=%sms max=%sms\n' \
    "${label}" "${runs}" "${DYBATPHO_TEST_BENCH_MIN_MS}" \
    "${DYBATPHO_TEST_BENCH_MEDIAN_MS}" "${DYBATPHO_TEST_BENCH_MAX_MS}"
}

#######################################
# @description Set environment variables for the duration of a test, remembering their previous state.
# @example
#   dybatpho::mock_env DEPLOY_ENV=prod LOG_LEVEL=debug
#
# @arg $@ string Assignments in `NAME=value` form
# @set DYBATPHO_TEST_ENV_BACKUP Previous values, used by `dybatpho::unmock_env`
# @exitcode 1 An argument is not a valid `NAME=value` assignment
# @tip Variables that were unset before the mock are unset again on restore, rather
#      than being left behind as empty strings.
#######################################
function dybatpho::mock_env {
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one NAME=value assignment"
  local assignment name value
  for assignment in "$@"; do
    [[ "${assignment}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]] \
      || dybatpho::die "${FUNCNAME[0]}: Invalid assignment: ${assignment}"
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ ! -v "DYBATPHO_TEST_ENV_BACKUP[${name}]" ]]; then
      if [[ -v "${name}" ]]; then
        DYBATPHO_TEST_ENV_BACKUP["${name}"]="set:${!name}"
      else
        DYBATPHO_TEST_ENV_BACKUP["${name}"]="unset:"
      fi
      DYBATPHO_TEST_ENV_KEYS+=("${name}")
    fi
    export "${name}=${value}"
  done
}

#######################################
# @description Restore every environment variable changed through `dybatpho::mock_env`.
# @noargs
# @set DYBATPHO_TEST_ENV_BACKUP Emptied
#######################################
function dybatpho::unmock_env {
  local name record
  for name in ${DYBATPHO_TEST_ENV_KEYS[@]+"${DYBATPHO_TEST_ENV_KEYS[@]}"}; do
    record="${DYBATPHO_TEST_ENV_BACKUP[${name}]-}"
    if [[ "${record}" == set:* ]]; then
      export "${name}=${record#set:}"
    else
      unset "${name}"
    fi
  done
  DYBATPHO_TEST_ENV_BACKUP=()
  DYBATPHO_TEST_ENV_KEYS=()
}

#######################################
# @description Replace a command with a script that records every invocation.
# @example
#   dybatpho::mock_command_script kubectl 'printf "pod/api Running\n"; exit 0'
#
# @arg $1 string Command name to mock
# @arg $2 string Shell body executed by the mock, with `$@` holding the call arguments
# @set PATH Prefixed with the mock directory on first use
# @exitcode 1 The command name is not a valid executable name
# @tip The mock is a real executable on `PATH`, so it also intercepts `command <name>`,
#      which is how the network module invokes `curl`.
#######################################
function dybatpho::mock_command_script {
  local name body
  dybatpho::expect_args name body -- "$@"
  [[ "${name}" =~ ^[a-zA-Z0-9_.-]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Invalid command name: ${name}"
  __dybatpho_test_mock_script_write "${name}" <<< "${body}"
}

#######################################
# @description Install a mock command whose body is read from standard input.
#   The body never passes through an argument or a variable, which is what
#   keeps a long body visible to coverage: kcov reads Bash's `xtrace`, and a
#   traced command that expands a value holding both a line break and a single
#   quote is printed as `$'...\'...'`, which kcov's trace parser misreads as an
#   unterminated quote, recording nothing more for the rest of the process.
#   A here-document is not part of the trace.
# @arg $1 string Command name to mock, already validated
# @stdin Shell body executed by the mock
# @set PATH Prefixed with the mock directory on first use
# @internal
#######################################
function __dybatpho_test_mock_script_write {
  local name
  dybatpho::expect_args name -- "$@"
  __dybatpho_test_mock_init
  local mock_dir="${DYBATPHO_TEST_MOCK_DIR}"

  local script="${mock_dir}/${name}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "${mock_dir}/calls/${name}"
    cat
  } > "${script}"
  chmod +x "${script}"
  : > "${mock_dir}/calls/${name}"
  # Bash remembers where it last found a command, so a command that already ran
  # in this shell would keep going to the real executable past the mock.
  hash -d "${name}" 2> /dev/null || true
}

#######################################
# @description Replace a command with a mock that prints fixed output and exits with a fixed code.
# @example
#   dybatpho::mock_command git 0 "main"
#
# @arg $1 string Command name to mock
# @arg $2 number Exit code the mock returns, default is `0`
# @arg $3 string Text the mock prints on stdout, default is empty
# @see dybatpho::mock_command_script
#######################################
function dybatpho::mock_command {
  local name
  dybatpho::expect_args name -- "$@"
  local status="${2:-0}" output="${3-}"
  [[ "${status}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Exit code must be a non-negative integer: ${status}"

  local body
  if [[ -n "${output}" ]]; then
    printf -v body 'printf "%%s\\n" %q\nexit %s' "${output}" "${status}"
  else
    printf -v body 'exit %s' "${status}"
  fi
  dybatpho::mock_command_script "${name}" "${body}"
}

#######################################
# @description Print one line per recorded invocation of a mocked command.
# @arg $1 string Mocked command name
# @stdout The arguments of each call, oldest first
# @exitcode 1 The command was never mocked
#######################################
function dybatpho::mock_calls {
  local name
  dybatpho::expect_args name -- "$@"
  local calls="${DYBATPHO_TEST_MOCK_DIR}/calls/${name}"
  dybatpho::is file "${calls}" || return 1
  cat "${calls}"
}

#######################################
# @description Print how many times a mocked command was called.
# @arg $1 string Mocked command name
# @stdout Call count, `0` when the mock was never invoked
#######################################
function dybatpho::mock_call_count {
  local name output
  dybatpho::expect_args name -- "$@"
  if ! output="$(dybatpho::mock_calls "${name}" 2> /dev/null)"; then
    printf '0'
    return 0
  fi
  if [[ -z "${output}" ]]; then
    printf '0'
    return 0
  fi
  local printf
  local printf_2
  local printf_3
  local printf_4
  local printf_5
  local printf_6
  local printf_7
  local printf_8
  local printf_9
  local line_count
  line_count=$(printf '%s\n' "${output}" | wc -l)
  printf_9=$(printf '%s' "${line_count}" | tr -d ' ')
  printf_8=${printf_9}
  printf_7=${printf_8}
  printf_6=${printf_7}
  printf_5=${printf_6}
  printf_4=${printf_5}
  printf_3=${printf_4}
  printf_2=${printf_3}
  printf=${printf_2}
  printf '%s' "${printf}"
}

#######################################
# @description Assert that a mocked command was called, optionally with specific arguments.
# @example
#   dybatpho::assert_mock_called kubectl get pods
#
# @arg $1 string Mocked command name
# @arg $@ string Optional arguments that must appear together in one recorded call
# @exitcode 0 A matching call was recorded
# @tip Arguments are matched on whole-argument boundaries, so a fragment of an
#      argument never counts as a match.
# @exitcode 1 The command was never called, or never with those arguments
#######################################
function dybatpho::assert_mock_called {
  local name
  dybatpho::expect_args name -- "$@"
  shift

  local calls
  if ! calls="$(dybatpho::mock_calls "${name}" 2> /dev/null)"; then
    __dybatpho_test_fail "Command was never mocked: ${name}"
    return 1
  fi
  if [[ -z "${calls}" ]]; then
    __dybatpho_test_fail "Mocked command was never called: ${name}"
    return 1
  fi
  (($# > 0)) || return 0

  # Pad both sides so the comparison lands on argument boundaries: a call
  # recorded as `deploy production` must not match a `loy produc` fragment.
  local expected="$*" line
  while IFS= read -r line; do
    if dybatpho::string_contains " ${line} " " ${expected} "; then
      return 0
    fi
  done <<< "${calls}"
  local text_indent
  text_indent=$(dybatpho::text_indent "${calls}" '    ')
  __dybatpho_test_fail \
    "Mocked command ${name} was never called with: ${expected}" \
    "  recorded calls:" \
    "${text_indent}"
  return 1
}

#######################################
# @description Remove one mocked command so the real command is used again.
# @arg $1 string Mocked command name
#######################################
function dybatpho::unmock_command {
  local name
  dybatpho::expect_args name -- "$@"
  [[ -n "${DYBATPHO_TEST_MOCK_DIR}" ]] || return 0
  rm -f "${DYBATPHO_TEST_MOCK_DIR}/${name}" "${DYBATPHO_TEST_MOCK_DIR}/calls/${name}"
  hash -d "${name}" 2> /dev/null || true
}

#######################################
# @description Register a canned HTTP response for URLs matching a pattern.
# @example
#   dybatpho::mock_http 'api.example.test/status' 200 '{"ok":true}'
#
# @arg $1 string Substring matched against the requested URL
# @arg $2 number HTTP status code the mock reports
# @arg $3 string Optional response body written to the caller's output file
# @arg $@ string Optional extra response headers in `Name: value` form
# @set PATH Prefixed with the mock directory on first use
# @exitcode 1 The status code is not a three-digit number
# @tip The mock replaces `curl` itself, so it also covers `command curl` calls made by
#      `dybatpho::curl_do` and every helper built on it.
# @tip Following the repository's curl-stubbing convention, the mock always exits `0`
#      and reports the status through `-w '%{http_code}'`, which is what the network
#      module reads to decide success, retry, and its own exit code.
#######################################
function dybatpho::mock_http {
  local pattern status body
  dybatpho::expect_args pattern status -- "$@"
  body="${3-}"
  if (($# > 3)); then
    shift 3
  else
    shift $#
  fi
  [[ "${status}" =~ ^[0-9]{3}$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: HTTP status must be three digits: ${status}"
  __dybatpho_test_mock_init
  local mock_dir="${DYBATPHO_TEST_MOCK_DIR}"

  local routes="${mock_dir}/http-routes"
  local route_dir="${mock_dir}/http"
  mkdir -p "${route_dir}"
  # Sanitizing the pattern alone is not unique: `api.test/v1` and `api-test/v1`
  # both reduce to the same name, so an index keeps every route's files apart.
  local route_id route_index=0
  if [[ -f "${routes}" ]]; then
    local wc
    wc=$(wc -l < "${routes}" | tr -d ' ')
    route_index="${wc}"
  fi
  route_id="$(printf '%s' "${pattern}" | tr -c 'a-zA-Z0-9' '_')_${route_index}"
  printf '%s' "${body}" > "${route_dir}/${route_id}.body"
  {
    printf 'HTTP/1.1 %s\r\n' "${status}"
    local header
    for header in "$@"; do
      printf '%s\r\n' "${header}"
    done
    printf '\r\n'
  } > "${route_dir}/${route_id}.headers"
  printf '%s\t%s\t%s\n' "${pattern}" "${status}" "${route_id}" >> "${routes}"

  local routes_q route_dir_q calls_q payloads_q
  printf -v routes_q '%q' "${routes}"
  printf -v route_dir_q '%q' "${route_dir}"
  printf -v calls_q '%q' "${mock_dir}/http-calls"
  printf -v payloads_q '%q' "${mock_dir}/http-payloads"

  # Through standard input rather than `mock_command_script`'s argument: this
  # body holds both line breaks and single quotes, and as an argument it would
  # end coverage for the rest of every test that mocks HTTP.
  __dybatpho_test_mock_script_write curl << MOCK_CURL
routes=${routes_q}
route_dir=${route_dir_q}
calls=${calls_q}
payloads=${payloads_q}

output="/dev/null"
header_file=""
url=""
config_file=""
body=""
body_on_stdin=0
while ((\$#)); do
  case "\$1" in
    -o)
      output="\$2"
      shift 2
      ;;
    -D)
      header_file="\$2"
      shift 2
      ;;
    --config)
      config_file="\$2"
      shift 2
      ;;
    --data-binary)
      if [[ "\$2" == "@-" ]]; then
        body_on_stdin=1
      else
        body="\$2"
      fi
      shift 2
      ;;
    -w | --connect-timeout | --max-time | -H | --header | -F | --form | -X | --request | -d | --data)
      shift 2
      ;;
    -*) shift ;;
    *)
      url="\$1"
      shift
      ;;
  esac
done
printf '%s\n' "\${url}" >> "\${calls}"

# Record the request material that does not travel in the argument vector, so a
# test can still assert what was actually sent. Newlines are flattened so that
# one request stays one line.
payload=""
if [[ -n "\${config_file}" && -r "\${config_file}" ]]; then
  payload+="\$(tr '\n' ' ' < "\${config_file}")"
fi
if ((body_on_stdin)); then
  body="\$(cat)"
fi
if [[ -n "\${body}" ]]; then
  payload+=" \${body}"
fi
printf '%s\n' "\${payload//\$'\n'/ }" >> "\${payloads}"

status="404"
route_id=""
while IFS=\$'\t' read -r pattern route_status route; do
  [[ -z "\${pattern}" ]] && continue
  if [[ "\${url}" == *"\${pattern}"* ]]; then
    status="\${route_status}"
    route_id="\${route}"
  fi
done < "\${routes}"

if [[ -n "\${header_file}" ]]; then
  if [[ -n "\${route_id}" ]]; then
    cat "\${route_dir}/\${route_id}.headers" > "\${header_file}"
  else
    printf 'HTTP/1.1 404\r\n\r\n' > "\${header_file}"
  fi
fi
if [[ -n "\${route_id}" && "\${output}" != "/dev/null" ]]; then
  cat "\${route_dir}/\${route_id}.body" > "\${output}"
fi
printf '%s' "\${status}"
exit 0
MOCK_CURL
}

#######################################
# @description Print every URL requested through the HTTP mock, oldest first.
# @noargs
# @stdout One requested URL per line
# @exitcode 1 No HTTP request was made through the mock
#######################################
function dybatpho::mock_http_calls {
  local calls="${DYBATPHO_TEST_MOCK_DIR}/http-calls"
  dybatpho::is file "${calls}" || return 1
  cat "${calls}"
}

#######################################
# @description Print the request material of every mocked HTTP call that did not
#   travel in the argument vector, newest last, one request per line.
#
#   Credentials and request bodies are deliberately kept off `curl`'s command
#   line, because arguments are readable by every account on the host through
#   `/proc/<pid>/cmdline`. They go into a `--config` file and onto standard
#   input instead. That is the right thing for a running script and an awkward
#   thing for a test, which still has to be able to say "the token was sent" and
#   "the body carried this field" -- so the mock records them here.
# @noargs
# @example
#   dybatpho::mock_http "api.github.com" 201 '{"number":12}'
#   dybatpho::forge_issue_create "Nightly failing" "It broke"
#   dybatpho::mock_http_payloads   # header = "Authorization: Bearer ..." {"title":...}
#
# @env DYBATPHO_TEST_MOCK_DIR string Directory the mocks live in
# @stdout One line per recorded request
# @exitcode 0 Requests were recorded
# @exitcode 1 No mocked request has been made yet
# @see
#   - `dybatpho::mock_http`
#   - `dybatpho::mock_http_calls`
#######################################
function dybatpho::mock_http_payloads {
  local payloads="${DYBATPHO_TEST_MOCK_DIR}/http-payloads"
  dybatpho::is file "${payloads}" || return 1
  cat "${payloads}"
}

#######################################
# @description Assert that a URL matching a pattern was requested through the HTTP mock.
# @arg $1 string Substring matched against the requested URLs
# @exitcode 0 A matching request was recorded
# @exitcode 1 No matching request was recorded
#######################################
function dybatpho::assert_http_called {
  local pattern
  dybatpho::expect_args pattern -- "$@"
  local calls line
  if ! calls="$(dybatpho::mock_http_calls 2> /dev/null)"; then
    __dybatpho_test_fail "No HTTP request was made through the mock"
    return 1
  fi

  while IFS= read -r line; do
    if dybatpho::string_contains "${line}" "${pattern}"; then
      return 0
    fi
  done <<< "${calls}"
  local text_indent
  text_indent=$(dybatpho::text_indent "${calls}" '    ')
  __dybatpho_test_fail \
    "No HTTP request matched: ${pattern}" \
    "  requested URLs:" \
    "${text_indent}"
  return 1
}

#######################################
# @description Find the real `date` executable on `PATH`, skipping the mock directory.
# @arg $1 string Variable name that receives the absolute path
# @exitcode 0 A `date` executable was found
# @exitcode 1 No `date` executable outside the mock directory is on `PATH`
# @internal
#######################################
function __dybatpho_test_real_date {
  local path_var
  dybatpho::expect_args path_var -- "$@"
  local -n __dybatpho_test_date_path="${path_var}"
  local entry
  local -a entries=()
  IFS=: read -r -a entries <<< "${PATH}"
  for entry in "${entries[@]}"; do
    [[ -n "${entry}" && "${entry}" != "${DYBATPHO_TEST_MOCK_DIR}" ]] || continue
    if [[ -x "${entry}/date" && ! -d "${entry}/date" ]]; then
      __dybatpho_test_date_path="${entry}/date"
      return 0
    fi
  done
  # Reached under `run` by "dybatpho::mock_time fails when no date can format
  # a timestamp", which kcov cannot see.
  return 1 # kcov(skip)
}

#######################################
# @description Freeze the clock that `date` reports, for the code under test.
#
#   The library reads the time by running `date`: `dybatpho::date_now` and
#   `dybatpho::date_today`, and through them the `schedule`, `queue`, `backup`
#   and `i18n` modules, as well as the ages `dybatpho::file_age_seconds` and the
#   `cache` module compute, the rate-limit windows in `network`, and the
#   timestamps `lock` records. This puts a `date` on `PATH` that answers every
#   question about *now* from the frozen moment, so all of them agree on one
#   instant, in this shell and in every command it starts.
#
#   A `date` call that names its own moment -- `-d`/`--date`, `-r`, `-f`, `-j`,
#   BusyBox's `-D` -- is passed through untouched, so parsing and formatting an
#   explicit timestamp keep working. A relative date such as `-d tomorrow` is
#   therefore measured from the real clock, not the frozen one.
#
#   The frozen moment is not seen by `$EPOCHSECONDS`, `$EPOCHREALTIME`,
#   `printf '%(...)T'`, `sleep`, or anything that calls `busybox date`
#   directly. That leaves the millisecond timers -- `dybatpho::timer_start`,
#   `dybatpho::metrics_time`, `dybatpho::assert_duration_under` -- measuring
#   real elapsed time, which is what they are for.
# @example
#   dybatpho::mock_time 1767225600            # 2026-01-01T00:00:00Z
#   dybatpho::date_now %F                     # 2026-01-01 (in UTC)
#   dybatpho::mock_time_advance 86400
#   dybatpho::date_now %F                     # 2026-01-02
#   dybatpho::unmock_time
#
# @arg $1 number Unix timestamp to freeze the clock at
# @set PATH Prefixed with the mock directory on first use
# @exitcode 0 The clock is frozen
# @exitcode 1 The timestamp is not a whole number, or no usable `date` is on `PATH`
# @tip The clock stays still until it is moved, so code that waits for time to
#      pass -- `dybatpho::lock_acquire` with a timeout above `0` on a held lock --
#      waits forever. Move the clock with `dybatpho::mock_time_advance`, or
#      unfreeze it around such a call.
# @see
#   - `dybatpho::mock_time_advance`
#   - `dybatpho::unmock_time`
#######################################
function dybatpho::mock_time {
  local epoch
  dybatpho::expect_args epoch -- "$@"
  [[ "${epoch}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected a Unix timestamp in whole seconds: ${epoch}"
  __dybatpho_test_mock_init

  local real_date
  __dybatpho_test_real_date real_date \
    || dybatpho::die "${FUNCNAME[0]}: No date command found on PATH"

  # GNU and BusyBox take the moment as `-d @<seconds>`, BSD as `-r <seconds>`.
  # Asking which one works is the portable test; the name of the system is not.
  local flag="" prefix="" probe
  probe="$("${real_date}" -d @0 +%s 2> /dev/null)" || probe=""
  if [[ "${probe}" == "0" ]]; then
    flag="-d" prefix="@"
  else
    probe="$("${real_date}" -r 0 +%s 2> /dev/null)" || probe=""
    [[ "${probe}" == "0" ]] && flag="-r"
  fi
  [[ -n "${flag}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: ${real_date} cannot format a given timestamp"

  local state="${DYBATPHO_TEST_MOCK_DIR}/time-epoch"
  printf '%s\n' "${epoch}" > "${state}"

  local state_q real_q
  printf -v state_q '%q' "${state}"
  printf -v real_q '%q' "${real_date}"
  local body
  IFS= read -r -d '' body << MOCK_DATE || true
epoch="\$(< ${state_q})"
for arg in "\$@"; do
  case "\${arg}" in
    -d* | --date* | -r* | --reference* | -f* | --file* | -j* | -D* | -s* | --set* | --help | --version)
      exec ${real_q} "\$@"
      ;;
  esac
done
exec ${real_q} ${flag} "${prefix}\${epoch}" "\$@"
MOCK_DATE
  dybatpho::mock_command_script date "${body}"
}

#######################################
# @description Move the frozen clock forward, or back, by a number of seconds.
# @example
#   dybatpho::mock_time 1767225600
#   dybatpho::mock_time_advance 3600   # one hour later
#   dybatpho::mock_time_advance -60    # one minute back
#
# @arg $1 number Seconds to move the clock by; negative moves it back
# @exitcode 0 The clock moved
# @exitcode 1 The amount is not a whole number, or the clock is not frozen
# @tip The new moment is seen by every process at once, including one already
#      running in the background, because the mock reads it on every call.
#######################################
function dybatpho::mock_time_advance {
  local seconds
  dybatpho::expect_args seconds -- "$@"
  [[ "${seconds}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected a whole number of seconds: ${seconds}"
  local state="${DYBATPHO_TEST_MOCK_DIR}/time-epoch"
  [[ -n "${DYBATPHO_TEST_MOCK_DIR}" && -f "${state}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: The clock is not frozen; call dybatpho::mock_time first"
  local epoch
  epoch="$(< "${state}")"
  epoch=$((epoch + seconds))
  ((epoch >= 0)) \
    || dybatpho::die "${FUNCNAME[0]}: Cannot move the clock before the Unix epoch"
  printf '%s\n' "${epoch}" > "${state}"
}

#######################################
# @description Unfreeze the clock, so `date` reports the real time again.
# @noargs
# @exitcode 0 Always, including when the clock was not frozen
#######################################
function dybatpho::unmock_time {
  [[ -n "${DYBATPHO_TEST_MOCK_DIR}" ]] || return 0
  dybatpho::unmock_command date
  rm -f "${DYBATPHO_TEST_MOCK_DIR}/time-epoch"
}

#######################################
# @description Answer `dybatpho::is_tty` from the mocked streams, and from the
#   real file descriptors for the streams that are not mocked.
# @arg $1 string Stream name, default is `stdout`
# @exitcode 0 The stream is, or is mocked as, a terminal
# @exitcode 1 The stream is not, or is mocked as not, a terminal
# @internal
#######################################
# The stream is optional and defaults to stdout, exactly as in the function this
# stands in for, so there is no fixed argument list to name.
# dyshellint disable=BSG050
function __dybatpho_test_tty_answer {
  local stream="${1:-stdout}"
  __dybatpho_os_assert_stream "${stream}"
  local name fd
  case "${stream}" in
    stdin | 0) name=stdin fd=0 ;;
    stdout | 1) name=stdout fd=1 ;;
    *) name=stderr fd=2 ;;
  esac
  case "${DYBATPHO_TEST_TTY[${name}]-}" in
    on) return 0 ;;
    off) return 1 ;;
    *)
      # Run by "dybatpho::mock_tty answers is_tty for the streams it names",
      # which asserts its answer; kcov records no hit for this test.
      [[ -t "${fd}" ]] # kcov(skip)
      ;;
  esac
}

#######################################
# @description Make the library see a terminal, or none, on the standard streams.
#
#   This replaces `dybatpho::is_tty` until `dybatpho::unmock_tty`, so everything
#   that asks it follows: `dybatpho::color_supported`, `dybatpho::is_interactive`
#   and the confirmations built on it, and the privilege prompt guard. A stream
#   that is not named keeps its real answer, and a later call changes only the
#   streams it names.
#
#   The environment still has the last word, exactly as it does on a real
#   terminal: `NO_COLOR` and `FORCE_COLOR` decide colour, and
#   `DYBATPHO_INTERACTIVE` set to anything but `auto` decides interactivity.
#   Code that tests a file descriptor itself with `[[ -t ]]` is not affected --
#   `dybatpho::tui_supported` is one, and is steered with `DYBATPHO_TUI`
#   instead -- and neither is a script started in a new shell, which sources the
#   library afresh.
# @example
#   dybatpho::mock_tty on stdout stderr
#   dybatpho::color_supported stderr && printf 'colour\n'
#   dybatpho::mock_tty off stdin
#   dybatpho::confirm "Delete?" || printf 'refused without a terminal\n'
#   dybatpho::unmock_tty
#
# @arg $1 string `on` to report a terminal, `off` to report none
# @arg $@ string Streams to mock: `stdin`, `stdout`, `stderr`, or `0`-`2`; default is all three
# @set DYBATPHO_TEST_TTY Mocked answer for each stream
# @exitcode 0 The streams are mocked
# @exitcode 1 The state is not `on` or `off`, or a stream name is unknown
# @see dybatpho::unmock_tty
#######################################
function dybatpho::mock_tty {
  local state
  dybatpho::expect_args state -- "$@"
  shift
  [[ "${state}" == "on" || "${state}" == "off" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected on or off: ${state}"
  (($# > 0)) || set -- stdin stdout stderr

  local stream
  local -a names=()
  for stream in "$@"; do
    case "${stream}" in
      stdin | 0) names+=(stdin) ;;
      stdout | 1) names+=(stdout) ;;
      stderr | 2) names+=(stderr) ;;
      # Ends the shell, so "dybatpho::mock_tty rejects a bad state or stream"
      # runs it under `run`, which kcov cannot see.
      *) dybatpho::die "${FUNCNAME[0]}: Stream must be stdin, stdout, or stderr, got '${stream}'" ;; # kcov(skip)
    esac
  done

  if [[ -z "${DYBATPHO_TEST_TTY_ORIGINAL}" ]]; then
    DYBATPHO_TEST_TTY_ORIGINAL="$(declare -f dybatpho::is_tty)"
    # Replacing a function of another module by name is what the mock is; a
    # literal definition is the only way to write one without documenting a
    # second, public `dybatpho::is_tty` here.
    # dyshellint disable=BSG040
    eval "function dybatpho::is_tty { __dybatpho_test_tty_answer \"\$@\"; }"
  fi
  for stream in "${names[@]}"; do
    DYBATPHO_TEST_TTY["${stream}"]="${state}"
  done
}

#######################################
# @description Give `dybatpho::is_tty` back its real answers.
# @noargs
# @set DYBATPHO_TEST_TTY Emptied
# @exitcode 0 Always, including when no stream was mocked
#######################################
function dybatpho::unmock_tty {
  DYBATPHO_TEST_TTY=()
  [[ -n "${DYBATPHO_TEST_TTY_ORIGINAL}" ]] || return 0
  # `declare -f` prints a definition that recreates the function, so running it
  # is how the original comes back; there is no other form to restore it from.
  # dyshellint disable=BSG040
  eval "${DYBATPHO_TEST_TTY_ORIGINAL}"
  DYBATPHO_TEST_TTY_ORIGINAL=""
}

#######################################
# @description Create a temporary fixture directory that is removed when the shell exits.
# @example
#   dybatpho::fixture_dir workdir
#   printf 'data\n' > "${workdir}/input.txt"
#
# @arg $1 string Variable name that receives the directory path
# @see dybatpho::create_temp
# @tip Cleanup is registered through `dybatpho::cleanup_file_on_exit`, so the fixture
#      is removed by an `EXIT`/`HUP`/`INT`/`TERM` trap even when the script fails.
#######################################
function dybatpho::fixture_dir {
  local __dybatpho_test_fixture_var
  dybatpho::expect_args __dybatpho_test_fixture_var -- "$@"
  dybatpho::expect_ref "${__dybatpho_test_fixture_var}"
  dybatpho::create_temp "${__dybatpho_test_fixture_var}" "" "fixture"
}

#######################################
# @description Create a temporary fixture file holding the given content.
# @example
#   dybatpho::fixture_file settings '{"mode":"dev"}' ".json"
#   dybatpho::assert_json_query "${settings}" '.mode' dev
#
# @arg $1 string Variable name that receives the file path
# @arg $2 string File content, or `-` to read the content from stdin
# @arg $3 string Optional file extension, default is `.txt`
# @see dybatpho::create_temp
# @tip When reading content from stdin, redirect into the call (`< file` or `<<<`)
#      instead of piping into it. A pipeline runs the helper in a subshell, so the
#      assigned variable would not survive in the caller.
#######################################
function dybatpho::fixture_file {
  # Every local carries the library's prefix: `create_temp` and the nameref
  # below bind to the name the caller chose, and one matching a plain local
  # here would resolve to that local instead of the caller's variable.
  local __dybatpho_test_fixture_var __dybatpho_test_fixture_content
  dybatpho::expect_args __dybatpho_test_fixture_var __dybatpho_test_fixture_content -- "$@"
  dybatpho::expect_ref "${__dybatpho_test_fixture_var}"
  local __dybatpho_test_fixture_extension="${3:-.txt}"
  dybatpho::create_temp "${__dybatpho_test_fixture_var}" "${__dybatpho_test_fixture_extension}" "fixture"
  local -n __dybatpho_test_fixture_ref="${__dybatpho_test_fixture_var}"
  if [[ "${__dybatpho_test_fixture_content}" == "-" ]]; then
    cat > "${__dybatpho_test_fixture_ref}"
  else
    printf '%s\n' "${__dybatpho_test_fixture_content}" > "${__dybatpho_test_fixture_ref}"
  fi
}

#######################################
# @description Remove every mock created in this shell and restore the environment,
#   the clock, and the terminal detection.
# @noargs
# @tip Fixtures and mocks are already removed by their exit traps; call this to reset
#      state between test cases that share one shell.
#######################################
function dybatpho::unmock_all {
  dybatpho::unmock_env
  dybatpho::unmock_tty
  dybatpho::unmock_time
  dybatpho::snapshot_scrub_reset
  if [[ -n "${DYBATPHO_TEST_MOCK_DIR}" && -d "${DYBATPHO_TEST_MOCK_DIR}" ]]; then
    rm -rf "${DYBATPHO_TEST_MOCK_DIR:?}"/*
    mkdir -p "${DYBATPHO_TEST_MOCK_DIR}/calls"
  fi
  hash -r
  return 0
}
