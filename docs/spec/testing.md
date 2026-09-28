# Feature Specification: Extended Assertions, Snapshots, Mocks, and Fixtures

**Feature Branch**: `[feature-testing]`
**Status**: Implemented
**Input**: Existing source analysis: `src/testing.sh`, `docs/testing.md`, `test/testing.bats`, and `example/testing_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts that touch the filesystem, call external commands, or make HTTP
requests are hard to test. `helpers.sh` offers a single `dybatpho::assert`
guard, which is enough for preconditions but not for verifying an outcome: there
is no way to state that a file has the right permissions, that a JSON document
holds the right value, that a CLI still prints what it printed yesterday, or
that a script called `kubectl` with the right arguments. Test suites therefore
re-implement the same helpers, and the ones that shell out for real are slow,
network-dependent, and leave temporary files behind when they fail.

## Business Value *(mandatory)*

- Let a test state an expectation once instead of hand-writing `[[ ]]` chains.
- Make failures diagnosable: every assertion names the path, key, or call that
  did not match, and shows expected versus actual.
- Remove the network and the developer's environment from the test path.
- Detect unintended CLI output changes without maintaining golden files by hand.
- Guarantee that fixtures are removed even when a test fails part-way.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Assert on files, directories, and symlinks (Priority: P1)

As a script author, I want to state what a script should have produced on disk,
including permissions, so that a wrong layout fails with a clear message.

**Independent Test**: Create files, directories, and links, then verify each
assertion passes for a match and fails with a diagnostic otherwise.

**Acceptance Scenarios**:

1. **Given** a regular file or directory, **When** the matching assertion runs,
   **Then** it succeeds, and the mismatched assertion fails naming the path
2. **Given** a symbolic link, **When** an expected target is supplied, **Then**
   the assertion fails unless the link points at that target
3. **Given** a file with mode `600`, **When** `assert_file_mode` runs with `600`
   or `0600`, **Then** it succeeds, and any other mode fails showing both values
4. **Given** a dangling symlink, **When** `assert_path_absent` runs, **Then** it
   fails because the path is occupied

### User Story 2 - Assert on JSON and YAML documents (Priority: P1)

As a script author, I want to assert on a parsed value rather than on raw text
so that formatting changes do not break my tests.

**Independent Test**: Assert validity, a queried value, and a matching filter on
JSON and YAML documents supplied both as files and on stdin.

**Acceptance Scenarios**:

1. **Given** a document, **When** the validity assertion runs, **Then** it fails
   only when the backend cannot parse the document
2. **Given** a query and an expected value, **When** the assertion runs, **Then**
   it reports the expected and actual values on mismatch
3. **Given** a backend that prints a string scalar as `"value"`, **When** the
   expected value is written as `value`, **Then** the assertion still matches
4. **Given** a document on stdin, **When** `-` is passed as the input, **Then**
   the content is buffered into a self-cleaning fixture and asserted on

### User Story 3 - Snapshot CLI output (Priority: P1)

As a CLI maintainer, I want to record the stdout, stderr, and exit code of a
command and be told when they change, so that output regressions are caught.

**Independent Test**: Snapshot a command twice and verify the first run records
a baseline, the second run matches, and a changed output or exit code fails.

**Acceptance Scenarios**:

1. **Given** no stored snapshot, **When** the assertion runs, **Then** the
   snapshot is written and the assertion passes
2. **Given** a stored snapshot and different text, **When** the assertion runs,
   **Then** it fails and prints a unified diff
3. **Given** output containing ANSI colors or volatile values, **When** the
   snapshot is taken, **Then** colors are stripped and registered scrubs are
   applied first
4. **Given** a command that exits non-zero, **When** it is snapshotted, **Then**
   the exit code is recorded in the snapshot instead of failing the assertion

### User Story 4 - Mock the environment, commands, and HTTP (Priority: P1)

As a script author, I want to replace environment variables, external commands,
and HTTP responses so that a test is fast, offline, and repeatable.

**Independent Test**: Mock a variable, a command, and an HTTP route; run code
that uses all three; then verify the recorded calls and the restored state.

**Acceptance Scenarios**:

1. **Given** mocked environment variables, **When** the mock is undone, **Then**
   previously-set variables regain their value and previously-unset variables
   are unset again
2. **Given** a mocked command, **When** it is invoked, **Then** the call is
   recorded and the mock returns the configured output and exit code
3. **Given** recorded calls, **When** `assert_mock_called` runs with arguments,
   **Then** it succeeds only when one recorded call contains them, and otherwise
   lists the calls that were recorded
4. **Given** a mocked HTTP route, **When** a network helper requests a matching
   URL, **Then** the canned status, headers, and body are served without network
   access, and an unrouted URL falls through to `404`

### User Story 5 - Use fixtures that clean themselves up (Priority: P1)

As a script author, I want temporary files and directories removed automatically
so that a failing test does not leave artifacts behind.

**Independent Test**: Create fixtures inside a subshell and verify they are gone
once that shell exits.

**Acceptance Scenarios**:

1. **Given** a fixture directory or file, **When** it is created, **Then** its
   path is assigned to a caller-named variable and registered for cleanup
2. **Given** the shell that created a fixture exits, **When** the exit trap
   runs, **Then** the fixture is removed, including on failure or interruption
3. **Given** fixture content on stdin, **When** `-` is passed as the content,
   **Then** the content is read from the redirected input

### User Story 6 - Regenerate snapshots in bulk after an intended change (Priority: P2)

As a CLI maintainer, I want one switch that rewrites every stored snapshot, so
that an intended output change does not mean deleting `.snap` files by hand.

**Independent Test**: Record a snapshot, run the suite again with the switch set
and different text, and verify the stored baseline was replaced.

**Acceptance Scenarios**:

1. **Given** stored snapshots and `UPDATE_SNAPSHOTS=1`, **When** the suite runs,
   **Then** every snapshot it touches is rewritten and no comparison fails
2. **Given** `UPDATE_SNAPSHOTS=0`, an empty value, or no value at all, **When**
   the suite runs, **Then** snapshots are compared as usual and the stored
   baselines are left untouched

### User Story 7 - Keep a hot path inside a time budget (Priority: P2)

As a CLI maintainer, I want to assert that a command finishes in under a stated
number of milliseconds, so that a performance regression fails the suite instead
of being reported by a user.

**Independent Test**: Assert a trivial command against a generous budget and
against a zero budget, and verify the pass and the reported overrun.

**Acceptance Scenarios**:

1. **Given** a command that finishes inside the budget, **When** the assertion
   runs, **Then** it passes and publishes the measured milliseconds
2. **Given** a command that takes at least the budget, **When** the assertion
   runs, **Then** it fails naming both the budget and the measured time
3. **Given** a command that exits non-zero, **When** it is timed, **Then** the
   assertion fails with the command's exit code and output rather than treating
   a crash as a fast run
4. **Given** several runs are configured, **When** the command is timed, **Then**
   the fastest run decides, so one descheduled run does not fail the suite
5. **Given** a benchmark over several runs, **When** it finishes, **Then** it
   reports the fastest, median, and slowest run and asserts nothing

### Example Workflow

```bash
# Fixtures, mocks, and the environment are all scoped to this run.
dybatpho::fixture_dir workdir
dybatpho::mock_env RELEASE_VERSION=1.5.0
dybatpho::mock_command git 0 ""
dybatpho::mock_http "api.example.test/releases" 200 '{"artifact":"app.tgz"}'

./release.sh "${workdir}/dist"

dybatpho::assert_dir "${workdir}/dist"
dybatpho::assert_file_mode "${workdir}/dist/manifest.json" 600
dybatpho::assert_symlink "${workdir}/dist/current.json" "manifest.json"
dybatpho::assert_json_query "${workdir}/dist/manifest.json" '.version' "1.5.0"
dybatpho::assert_http_called "api.example.test/releases"
dybatpho::assert_mock_called git tag v1.5.0

dybatpho::snapshot_scrub "${workdir}" '<WORKDIR>'
dybatpho::assert_cli_snapshot release-help -- ./release.sh --help

dybatpho::unmock_all
```

## Edge Cases

- The asserted path is missing, is the wrong type, or is a dangling symlink.
- A mode is written with and without a leading zero.
- `stat` uses GNU syntax on Linux and BSD syntax on macOS.
- The JSON or YAML backend is unavailable, or the document is malformed.
- A backend prints a string scalar with its surrounding JSON quotes.
- A document is supplied on stdin rather than as a file path.
- A snapshot does not exist yet, or must be deliberately rewritten.
- Snapshotted output contains colors, timestamps, temporary paths, or pids.
- A snapshot name contains path separators or traversal segments.
- A mocked variable was previously unset rather than set to another value.
- A command is asserted on although it was never mocked, or was mocked but
  never called.
- An HTTP request is made to a URL that no route matches.
- Two HTTP route patterns differ only in punctuation and would otherwise
  share one sanitized storage name.
- An expected argument is a fragment of a recorded argument rather than a
  whole argument.
- Snapshotted text ends in blank lines, which command substitution strips.
- A helper that assigns through a variable name is invoked in a pipeline, which
  would run it in a subshell and discard the assignment.
- A fixture outlives its creating shell, or the shell fails before cleanup.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Assertions MUST report failures on stderr and return `1` rather
  than terminating the shell, so they compose with `if`, `&&`, and Bats `run`.
- **FR-002**: Invalid arguments, such as a missing parameter, a malformed
  assignment, or an unusable name, MUST fail through the library's fatal path.
- **FR-003**: Every assertion failure MUST be counted in
  `DYBATPHO_TEST_FAILURES`.
- **FR-004**: The module MUST assert that a path is a regular file, a directory,
  a symbolic link with an optional expected target, or absent.
- **FR-005**: The module MUST assert that a file contains a substring
  (`assert_file_contains`), that a file is empty (`assert_file_empty`), and that
  a path carries exact octal permissions (`assert_file_mode`).
- **FR-006**: Permission comparison MUST be numeric so `600` and `0600` match,
  and MUST work with both GNU and BSD `stat`.
- **FR-007**: The module MUST assert JSON and YAML validity
  (`assert_json_valid`, `assert_yaml_valid`), a queried value
  (`assert_json_query`, `assert_yaml_query`), and a matching filter
  (`assert_json_has`, `assert_yaml_has`), reusing the JSON module's backends.
- **FR-008**: Query assertions MUST accept an expected scalar with or without
  the backend's surrounding JSON quotes.
- **FR-009**: Document assertions MUST accept a file path or `-` for stdin, and
  MUST buffer stdin into a fixture registered for cleanup.
- **FR-010**: `assert_snapshot` MUST write and pass when no snapshot exists,
  compare against the stored snapshot otherwise, and print a unified diff on
  mismatch.
- **FR-011**: Snapshots MUST be rewritten when `DYBATPHO_TEST_UPDATE_SNAPSHOTS`
  is truthy, and MUST live under `DYBATPHO_TEST_SNAPSHOT_DIR`.
- **FR-012**: Snapshot names MUST be restricted so they cannot escape the
  snapshot directory.
- **FR-013**: Snapshotted text MUST have ANSI escapes stripped and every
  substitution registered through `snapshot_scrub` applied before comparison;
  `snapshot_scrub_reset` MUST forget them again.
- **FR-014**: `assert_cli_snapshot` MUST capture stdout, stderr, and the exit
  code of a command into one snapshot document, and MUST NOT propagate the
  command's exit code.
- **FR-015**: `mock_env` MUST record whether each variable was previously set,
  and `unmock_env` MUST restore set values and unset previously-unset ones.
- **FR-016**: Command mocks MUST be real executables placed on `PATH`, so they
  also intercept `command <name>` invocations. `mock_command` MUST cover the
  fixed-output case and `mock_command_script` MUST allow an arbitrary body.
- **FR-017**: Command mocks MUST record every invocation, exposed through
  `mock_calls`, `mock_call_count`, and `assert_mock_called`.
- **FR-018**: `assert_mock_called` MUST distinguish "never mocked" from "mocked
  but never called", and MUST list recorded calls when arguments do not match.
  It MUST match on whole-argument boundaries, so a fragment of a recorded
  argument never counts as a matching call.
- **FR-019**: `mock_http` MUST register routes matched against the requested
  URL, serve the configured status, headers, and body, record every requested
  URL for `mock_http_calls` and `assert_http_called`, and answer unmatched URLs
  with `404`.
  Each route MUST keep its own response storage even when two patterns reduce
  to the same sanitized name.
- **FR-020**: The HTTP mock MUST follow the repository's curl-stubbing
  convention by exiting `0` and reporting the status through `-w '%{http_code}'`,
  so the network module's status mapping and retry logic still apply.
- **FR-021**: `fixture_dir` and `fixture_file` MUST assign their path to a
  caller-named variable and register removal through
  `dybatpho::cleanup_file_on_exit`; `fixture_file` MUST accept content inline or
  from redirected stdin.
- **FR-022**: `unmock_all` MUST remove every command and HTTP mock, restore the
  environment, and clear registered snapshot substitutions.
- **FR-023**: Snapshot rewriting MUST also be switchable through the unprefixed
  `UPDATE_SNAPSHOTS` variable, so a whole suite regenerates with
  `UPDATE_SNAPSHOTS=1 <test runner>`.
- **FR-024**: Both snapshot switches MUST read `1`, `true`, `yes`, and `on` as
  on, and every other value, including `0` and an empty value, as off, so a
  baseline is never rewritten by accident.
- **FR-025**: `assert_duration_under` MUST run a command, fail when it exits
  non-zero, fail when it takes at least the stated budget in milliseconds, and
  publish the measured time in `DYBATPHO_TEST_LAST_DURATION_MS`.
- **FR-026**: `assert_duration_under` MUST repeat the command
  `DYBATPHO_TEST_DURATION_RUNS` times and judge the fastest run.
- **FR-027**: `benchmark` MUST time a command over a given number of runs and
  report the fastest, median, and slowest in milliseconds, on stdout and in
  `DYBATPHO_TEST_BENCH_MIN_MS`, `DYBATPHO_TEST_BENCH_MEDIAN_MS`, and
  `DYBATPHO_TEST_BENCH_MAX_MS`, without asserting anything.
- **FR-028**: The HTTP mock MUST record the request material that does not
  travel in the argument vector -- the headers of a `--config` file and a body
  read from standard input -- and `mock_http_payloads` MUST print one such
  record per request, so that a test can assert a credential or a body was sent
  even though neither is visible in `mock_calls curl`.
- **FR-029**: `mock_http_payloads` MUST fail when no mocked request has been
  made yet, matching `mock_http_calls`.

### Key Entities *(include if feature involves data)*

- **Assertion**: A check that reports on stderr and returns `0` or `1` without
  terminating the shell.
- **Snapshot**: A `.snap` file under `DYBATPHO_TEST_SNAPSHOT_DIR` holding the
  normalized text recorded for a named case.
- **Snapshot Scrub**: A `sed` substitution applied before comparison to remove
  volatile values.
- **Mock Directory**: The temporary directory prepended to `PATH` that holds
  mock executables, their call logs, and HTTP route data.
- **Call Log**: One line per recorded invocation of a mocked command.
- **HTTP Route**: A URL pattern mapped to a status, headers, and body.
- **Fixture**: A temporary file or directory registered for `trap`-based
  cleanup.
- **Duration Budget**: A ceiling in milliseconds that a timed command must stay
  under.
- **Benchmark Sample**: One timed run of a command, in milliseconds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A test can verify a script's filesystem, JSON, and HTTP effects
  without writing custom shell checks.
- **SC-002**: A failing assertion names the path, key, or call and shows both
  the expected and the actual value.
- **SC-003**: A suite using these mocks makes no network requests and does not
  depend on the developer's environment.
- **SC-004**: CLI output regressions, including exit-code changes, are caught by
  a stored snapshot.
- **SC-005**: No fixture survives the shell that created it, including when the
  script fails or is interrupted.
- **SC-006**: An intended output change is absorbed by one run of the suite with
  `UPDATE_SNAPSHOTS=1`, with no `.snap` file edited or deleted by hand.
- **SC-007**: A command that grows slower than its stated budget fails the suite
  with both numbers in the diagnostic.

## Integration Tests *(mandatory)*

- **IT-001**: Assert file, directory, symlink, target, absence, content,
  emptiness, and permissions, covering both the passing and failing directions.
- **IT-002**: Assert JSON and YAML validity, queries, and filters against a
  stubbed backend, including a quoted string scalar and a stdin document.
- **IT-003**: Record a snapshot, match it, and verify a mismatch prints a diff.
- **IT-004**: Verify color stripping, scrub substitutions, snapshot updating,
  and rejection of an unsafe snapshot name.
- **IT-005**: Snapshot a command's stdout, stderr, and non-zero exit code, and
  verify a changed exit code fails.
- **IT-006**: Mock previously-set and previously-unset variables and verify both
  are restored correctly.
- **IT-007**: Mock commands with fixed output, custom bodies, and exit codes,
  then verify call recording, counting, and argument matching.
- **IT-008**: Verify "never mocked" and "never called" are reported differently,
  and that `unmock_command` and `unmock_all` take effect.
- **IT-009**: Serve mocked HTTP responses to `dybatpho::curl_do`, verify body,
  headers, status-to-exit-code mapping, recorded URLs, and the unrouted default.
- **IT-010**: Create fixtures and verify they are removed when their shell exits.
- **IT-011**: Register two HTTP routes whose patterns sanitize alike and verify
  each URL still receives its own response.
- **IT-012**: Verify `assert_mock_called` accepts a whole-argument subset and
  rejects a fragment that spans an argument boundary.
- **IT-013**: Verify `DYBATPHO_TEST_FAILURES` counts failures and ignores passes.
- **IT-014**: Record a snapshot, rewrite it with `UPDATE_SNAPSHOTS=1`, and verify
  that `UPDATE_SNAPSHOTS=0` compares instead of rewriting.
- **IT-015**: Verify `assert_duration_under` passes under a generous budget,
  reports an overrun against a zero budget, fails on a command that exits
  non-zero, and rejects a malformed budget, separator, or empty command.
- **IT-016**: Verify `benchmark` reports ordered min, median, and max values and
  fails on a run that exits non-zero.
- **IT-017**: Verify `mock_http_payloads` fails before any request, then, after
  a request carrying `DYBATPHO_CURL_SECRET_HEADERS` and
  `DYBATPHO_CURL_SECRET_DATA`, reports both while `mock_calls curl` shows
  neither.

## Acceptance Criteria *(mandatory)*

1. Assertions never terminate the calling shell, so a test can inspect or
   aggregate failures itself.
2. Mocks are removed and the environment restored without manual bookkeeping.
3. Tests written with this module run offline, and leave no files behind.
