# testing.sh

Extended assertions, snapshots, mocks, and self-cleaning fixtures for shell tests

> 🧭 Source: [src/testing.sh](../src/testing.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module extends the plain `dybatpho::assert` guard from `helpers.sh`
with the pieces a shell test suite usually has to hand-roll:

- assertions for files, directories, symlinks, permissions, JSON, and YAML
- snapshot testing for CLI output, including exit code and stderr,
  regenerated in bulk with `UPDATE_SNAPSHOTS=1`
- duration budgets and benchmarks for the code paths a user waits on
- mocks for environment variables, external commands, and HTTP responses
- fixtures that register themselves for `trap`-based cleanup on exit

Assertions never terminate the shell. They write a diagnostic to stderr and
return `1`, so they compose with `if`, `&&`, and the Bats `run` helper.
Only programming mistakes, such as a missing argument, are fatal.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEST_SNAPSHOT_DIR`** | string | Directory holding `.snap` files, default is `test/snapshots` under the current directory |
| **`DYBATPHO_TEST_UPDATE_SNAPSHOTS`** | string | Set to `1`, `true`, `yes`, or `on` to rewrite snapshots instead of comparing them |
| **`UPDATE_SNAPSHOTS`** | string | Unprefixed alias for `DYBATPHO_TEST_UPDATE_SNAPSHOTS`, so a whole suite regenerates with `UPDATE_SNAPSHOTS=1 <test runner>` |
| **`DYBATPHO_TEST_DURATION_RUNS`** | number | How many times `dybatpho::assert_duration_under` runs a command, keeping the fastest, default is `1` |
| **`DYBATPHO_TEST_LAST_DURATION_MS`** | number | Milliseconds measured by the last duration assertion or benchmark |
| **`DYBATPHO_TEST_BENCH_MIN_MS`** | number | Fastest run of the last benchmark, in milliseconds |
| **`DYBATPHO_TEST_BENCH_MEDIAN_MS`** | number | Median run of the last benchmark, in milliseconds |
| **`DYBATPHO_TEST_BENCH_MAX_MS`** | number | Slowest run of the last benchmark, in milliseconds |
| **`DYBATPHO_TEST_FAILURES`** | number | Count of assertion failures recorded in this shell |

### 🚀 Highlights

- [`dybatpho::assert_file`](#dybatphoassert_file) — Assert that a path exists and is a regular file.
- [`dybatpho::assert_dir`](#dybatphoassert_dir) — Assert that a path exists and is a directory.
- [`dybatpho::assert_symlink`](#dybatphoassert_symlink) — Assert that a path is a symbolic link, optionally pointing at an expected target.
- [`dybatpho::assert_path_absent`](#dybatphoassert_path_absent) — Assert that nothing exists at a path.
- [`dybatpho::assert_file_contains`](#dybatphoassert_file_contains) — Assert that a file contains an exact substring.
- [`dybatpho::assert_file_empty`](#dybatphoassert_file_empty) — Assert that a file exists and holds no content.
- [`dybatpho::assert_file_mode`](#dybatphoassert_file_mode) — Assert that a file or directory carries exact octal permissions.
- [`dybatpho::assert_json_valid`](#dybatphoassert_json_valid) — Assert that a document is parsable JSON.
- [`dybatpho::assert_json_query`](#dybatphoassert_json_query) — Assert that a JSON query prints an expected value.
- [`dybatpho::assert_json_has`](#dybatphoassert_json_has) — Assert that a JSON filter matches something in the document.
- [`dybatpho::assert_yaml_valid`](#dybatphoassert_yaml_valid) — Assert that a document is parsable YAML.
- [`dybatpho::assert_yaml_query`](#dybatphoassert_yaml_query) — Assert that a YAML expression prints an expected value.
- [`dybatpho::assert_yaml_has`](#dybatphoassert_yaml_has) — Assert that a YAML expression matches something in the document.
- [`dybatpho::snapshot_scrub`](#dybatphosnapshot_scrub) — Register a substitution applied to text before it is snapshotted.
- [`dybatpho::snapshot_scrub_reset`](#dybatphosnapshot_scrub_reset) — Forget every registered snapshot substitution.
- [`dybatpho::assert_snapshot`](#dybatphoassert_snapshot) — Compare text against a stored snapshot, creating it when missing.
- [`dybatpho::assert_cli_snapshot`](#dybatphoassert_cli_snapshot) — Snapshot the stdout, stderr, and exit code of a command.
- [`dybatpho::assert_duration_under`](#dybatphoassert_duration_under) — Assert that a command finishes in under a budget of milliseconds.
- [`dybatpho::benchmark`](#dybatphobenchmark) — Time a command over several runs and report its fastest, median, and slowest.
- [`dybatpho::mock_env`](#dybatphomock_env) — Set environment variables for the duration of a test, remembering their previous state.
- [`dybatpho::unmock_env`](#dybatphounmock_env) — Restore every environment variable changed through `dybatpho::mock_env`.
- [`dybatpho::mock_command_script`](#dybatphomock_command_script) — Replace a command with a script that records every invocation.
- [`dybatpho::mock_command`](#dybatphomock_command) — Replace a command with a mock that prints fixed output and exits with a fixed code.
- [`dybatpho::mock_calls`](#dybatphomock_calls) — Print one line per recorded invocation of a mocked command.
- [`dybatpho::mock_call_count`](#dybatphomock_call_count) — Print how many times a mocked command was called.
- [`dybatpho::assert_mock_called`](#dybatphoassert_mock_called) — Assert that a mocked command was called, optionally with specific arguments.
- [`dybatpho::unmock_command`](#dybatphounmock_command) — Remove one mocked command so the real command is used again.
- [`dybatpho::mock_http`](#dybatphomock_http) — Register a canned HTTP response for URLs matching a pattern.
- [`dybatpho::mock_http_calls`](#dybatphomock_http_calls) — Print every URL requested through the HTTP mock, oldest first.
- [`dybatpho::mock_http_payloads`](#dybatphomock_http_payloads) — Print the request material of every mocked HTTP call that did not travel in the argument vector, newest last, one request per line. Credentials and request bodies are deliberately kept off `curl`'s command line, because arguments are readable by every account on the host through `/proc/<pid>/cmdline`. They go into a `--config` file and onto standard input instead. That is the right thing for a running script and an awkward thing for a test, which still has to be able to say "the token was sent" and "the body carried this field" -- so the mock records them here.
- [`dybatpho::assert_http_called`](#dybatphoassert_http_called) — Assert that a URL matching a pattern was requested through the HTTP mock.
- [`dybatpho::fixture_dir`](#dybatphofixture_dir) — Create a temporary fixture directory that is removed when the shell exits.
- [`dybatpho::fixture_file`](#dybatphofixture_file) — Create a temporary fixture file holding the given content.
- [`dybatpho::unmock_all`](#dybatphounmock_all) — Remove every mock created in this shell and restore the environment.

<a id="usage"></a>
## 🚀 Usage

### Assert on a generated file

```bash
dybatpho::assert_file "dist/app.tgz"
dybatpho::assert_file_mode "${HOME}/.netrc" 600
```

### Snapshot the output of a CLI

```bash
dybatpho::assert_cli_snapshot deploy-help -- ./mytool deploy --help
```

### Refresh every snapshot after an intended change

```bash
UPDATE_SNAPSHOTS=1 bats test/
```

### Keep a hot path inside its budget

```bash
dybatpho::assert_duration_under 200 -- ./mytool completions bash
```

### Mock an external command

```bash
dybatpho::mock_command kubectl 0 "pod/api-1 Running"
./deploy.sh
dybatpho::assert_mock_called kubectl get pods
```

<a id="see-also"></a>
## 🔗 See also

- [example/testing_ops.sh](../example/testing_ops.sh)

<a id="tips"></a>
## 💡 Tips

### `dybatpho::assert_file_mode`

- Useful for verifying that secret files are not group- or world-readable

### `dybatpho::assert_json_query`

- String scalars are compared without their JSON quoting, so an expected value of `1.4.2` matches a backend result of `"1.4.2"`.

### `dybatpho::assert_yaml_query`

- String scalars are compared without their JSON quoting, so an expected value of `1.4.2` matches a backend result of `"1.4.2"`.

### `dybatpho::snapshot_scrub`

- Use this to remove timestamps, temporary paths, and process ids that would otherwise make a snapshot fail on every run.

### `dybatpho::assert_snapshot`

- A missing snapshot is written and passes, so the first run records the baseline.
- Trailing blank lines are not preserved, because the text passes through a command substitution; a snapshot cannot assert on them.

### `dybatpho::assert_cli_snapshot`

- The command's own exit code is recorded inside the snapshot rather than propagated, so a CLI that exits non-zero can still be snapshotted.

### `dybatpho::assert_duration_under`

- A machine under load makes a tight budget flaky. Set `DYBATPHO_TEST_DURATION_RUNS` above `1` so a single descheduled run does not fail the suite: the fastest run is the one that measures the code rather than the machine.
- Budget for the shape of the cost, not the current number. A regression worth catching is a loop that became quadratic, not a run that drifted by five milliseconds.

### `dybatpho::benchmark`

- This measures and reports; it asserts nothing. Compare the median against a budget with `dybatpho::assert_duration_under`, or record the line in a log to watch the number move between releases.
- The median, not the mean, because one descheduled run drags a mean and leaves a median where it was.

### `dybatpho::mock_env`

- Variables that were unset before the mock are unset again on restore, rather than being left behind as empty strings.

### `dybatpho::mock_command_script`

- The mock is a real executable on `PATH`, so it also intercepts `command <name>`, which is how the network module invokes `curl`.

### `dybatpho::assert_mock_called`

- Arguments are matched on whole-argument boundaries, so a fragment of an argument never counts as a match.

### `dybatpho::mock_http`

- The mock replaces `curl` itself, so it also covers `command curl` calls made by `dybatpho::curl_do` and every helper built on it.
- Following the repository's curl-stubbing convention, the mock always exits `0` and reports the status through `-w '%{http_code}'`, which is what the network module reads to decide success, retry, and its own exit code.

### `dybatpho::fixture_dir`

- Cleanup is registered through `dybatpho::cleanup_file_on_exit`, so the fixture is removed by an `EXIT`/`HUP`/`INT`/`TERM` trap even when the script fails.

### `dybatpho::fixture_file`

- When reading content from stdin, redirect into the call (`< file` or `<<<`) instead of piping into it. A pipeline runs the helper in a subshell, so the assigned variable would not survive in the caller.

### `dybatpho::unmock_all`

- Fixtures and mocks are already removed by their exit traps; call this to reset state between test cases that share one shell.

<a id="reference"></a>
## 📚 Reference

### `dybatpho::assert_file`

Assert that a path exists and is a regular file.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to check |
| `$2` | string | Optional message replacing the default diagnostic |

**🚦 Exit codes**

- `0`: The path is a regular file
- `1`: The path is missing or is not a regular file


---

### `dybatpho::assert_dir`

Assert that a path exists and is a directory.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to check |
| `$2` | string | Optional message replacing the default diagnostic |

**🚦 Exit codes**

- `0`: The path is a directory
- `1`: The path is missing or is not a directory


---

### `dybatpho::assert_symlink`

Assert that a path is a symbolic link, optionally pointing at an expected target.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to check |
| `$2` | string | Optional expected link target, compared literally |

**🚦 Exit codes**

- `0`: The path is a symlink and matches the expected target when one is given
- `1`: The path is not a symlink, or points somewhere else


---

### `dybatpho::assert_path_absent`

Assert that nothing exists at a path.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path that must not exist |

**🚦 Exit codes**

- `0`: Nothing exists at the path
- `1`: A file, directory, or link exists at the path


---

### `dybatpho::assert_file_contains`

Assert that a file contains an exact substring.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |
| `$2` | string | Substring that must appear in the file |

**🚦 Exit codes**

- `0`: The substring was found
- `1`: The file is unreadable or the substring is absent


---

### `dybatpho::assert_file_empty`

Assert that a file exists and holds no content.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File path |

**🚦 Exit codes**

- `0`: The file exists and is empty
- `1`: The file is missing or has content


---

### `dybatpho::assert_file_mode`

Assert that a file or directory carries exact octal permissions.

**🧪 Example**

```bash
dybatpho::assert_file_mode "${HOME}/.netrc" 600

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to check |
| `$2` | string | Expected octal mode, such as `600` or `0700` |

**🚦 Exit codes**

- `0`: The permissions match
- `1`: The path is missing or its permissions differ


---

### `dybatpho::assert_json_valid`

Assert that a document is parsable JSON.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path, or `-` for stdin |

**🚦 Exit codes**

- `0`: The document parses as JSON
- `1`: The document is missing or malformed


---

### `dybatpho::assert_json_query`

Assert that a JSON query prints an expected value.

**🧪 Example**

```bash
dybatpho::assert_json_query package.json '.version' "1.4.2"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path, or `-` for stdin |
| `$2` | string | Query filter understood by the JSON backend |
| `$3` | string | Expected query result |

**🚦 Exit codes**

- `0`: The query result matches
- `1`: The query failed or returned a different value


---

### `dybatpho::assert_json_has`

Assert that a JSON filter matches something in the document.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | JSON file path, or `-` for stdin |
| `$2` | string | Query filter that must succeed |

**🚦 Exit codes**

- `0`: The filter matched
- `1`: The filter did not match


---

### `dybatpho::assert_yaml_valid`

Assert that a document is parsable YAML.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path, or `-` for stdin |

**🚦 Exit codes**

- `0`: The document parses as YAML
- `1`: The document is missing or malformed


---

### `dybatpho::assert_yaml_query`

Assert that a YAML expression prints an expected value.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path, or `-` for stdin |
| `$2` | string | `yq` expression |
| `$3` | string | Expected result |

**🚦 Exit codes**

- `0`: The expression result matches
- `1`: The expression failed or returned a different value


---

### `dybatpho::assert_yaml_has`

Assert that a YAML expression matches something in the document.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | YAML file path, or `-` for stdin |
| `$2` | string | `yq` expression that must succeed |

**🚦 Exit codes**

- `0`: The expression matched
- `1`: The expression did not match


---

### `dybatpho::snapshot_scrub`

Register a substitution applied to text before it is snapshotted.

**🧪 Example**

```bash
dybatpho::snapshot_scrub '/tmp/[A-Za-z0-9_]*' '<TMPDIR>'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Basic regular expression understood by `sed` |
| `$2` | string | Replacement text |

**🧩 Variable sets**

- **`DYBATPHO_TEST_SNAPSHOT_SCRUBS`** (Appends): the substitution


---

### `dybatpho::snapshot_scrub_reset`

Forget every registered snapshot substitution.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_TEST_SNAPSHOT_SCRUBS`**: Emptied


---

### `dybatpho::assert_snapshot`

Compare text against a stored snapshot, creating it when missing.

**🧪 Example**

```bash
dybatpho::assert_snapshot version-output "$(./mytool --version)"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Snapshot name, stored as `<name>.snap` inside the snapshot directory |
| `$2` | string | Text to compare; omit to read the text from stdin |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEST_SNAPSHOT_DIR`** | string | Directory holding the `.snap` files |
| **`DYBATPHO_TEST_UPDATE_SNAPSHOTS`** | string | Set to `1`, `true`, `yes`, or `on` to rewrite the snapshot |
| **`UPDATE_SNAPSHOTS`** | string | Unprefixed alias for the same switch |

**📤 Output on stderr**

- A unified diff when the text and the snapshot differ

**🚦 Exit codes**

- `0`: The text matches, or the snapshot was created or updated
- `1`: The text differs from the stored snapshot


---

### `dybatpho::assert_cli_snapshot`

Snapshot the stdout, stderr, and exit code of a command.

**🧪 Example**

```bash
dybatpho::assert_cli_snapshot deploy-help -- ./mytool deploy --help

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Snapshot name |
| `$2` | string | Literal `--` separating the name from the command |
| `$@` | string | Command and arguments to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEST_SNAPSHOT_DIR`** | string | Directory holding the `.snap` files |

**📤 Output on stderr**

- A unified diff when the captured output differs from the snapshot

**🚦 Exit codes**

- `0`: The captured output matches the snapshot
- `1`: The captured output differs


---

### `dybatpho::assert_duration_under`

Assert that a command finishes in under a budget of milliseconds.

**🧪 Example**

```bash
dybatpho::assert_duration_under 200 -- ./mytool completions bash

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Budget in whole milliseconds; the command must finish in less than this |
| `$2` | string | Literal `--` separating the budget from the command |
| `$@` | string | Command and arguments to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEST_DURATION_RUNS`** | number | How many times to run the command, keeping the fastest |

**🧩 Variable sets**

- **`DYBATPHO_TEST_LAST_DURATION_MS`** (number): Fastest run measured, in milliseconds
- **`DYBATPHO_TEST_FAILURES`** (Incremented): when the command fails or overruns the budget

**📤 Output on stderr**

- A diagnostic naming the budget and the measured time, followed by the
        command's own output when it failed

**🚦 Exit codes**

- `0`: The command succeeded and stayed under the budget
- `1`: The command failed, or took at least the budget


---

### `dybatpho::benchmark`

Time a command over several runs and report its fastest, median, and slowest.

**🧪 Example**

```bash
dybatpho::benchmark parse-config 20 -- ./mytool config show

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Label printed with the measurements |
| `$2` | number | How many times to run the command |
| `$3` | string | Literal `--` separating the arguments from the command |
| `$@` | string | Command and arguments to run |

**🧩 Variable sets**

- **`DYBATPHO_TEST_BENCH_MIN_MS`** (number): Fastest run, in milliseconds
- **`DYBATPHO_TEST_BENCH_MEDIAN_MS`** (number): Median run, in milliseconds
- **`DYBATPHO_TEST_BENCH_MAX_MS`** (number): Slowest run, in milliseconds
- **`DYBATPHO_TEST_LAST_DURATION_MS`** (number): Median run, in milliseconds

**📤 Output on stdout**

- One line: `<label> runs=<n> min=<ms>ms median=<ms>ms max=<ms>ms`

**🚦 Exit codes**

- `0`: Every run succeeded
- `1`: A run failed, with its output on stderr


---

### `dybatpho::mock_env`

Set environment variables for the duration of a test, remembering their previous state.

**🧪 Example**

```bash
dybatpho::mock_env DEPLOY_ENV=prod LOG_LEVEL=debug

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Assignments in `NAME=value` form |

**🧩 Variable sets**

- **`DYBATPHO_TEST_ENV_BACKUP`** (Previous): values, used by `dybatpho::unmock_env`

**🚦 Exit codes**

- `1`: An argument is not a valid `NAME=value` assignment


---

### `dybatpho::unmock_env`

Restore every environment variable changed through `dybatpho::mock_env`.

_Function has no arguments._

**🧩 Variable sets**

- **`DYBATPHO_TEST_ENV_BACKUP`**: Emptied


---

### `dybatpho::mock_command_script`

Replace a command with a script that records every invocation.

**🧪 Example**

```bash
dybatpho::mock_command_script kubectl 'printf "pod/api Running\n"; exit 0'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command name to mock |
| `$2` | string | Shell body executed by the mock, with `$@` holding the call arguments |

**🧩 Variable sets**

- **`PATH`** (Prefixed): with the mock directory on first use

**🚦 Exit codes**

- `1`: The command name is not a valid executable name


---

### `dybatpho::mock_command`

Replace a command with a mock that prints fixed output and exits with a fixed code.

**🧪 Example**

```bash
dybatpho::mock_command git 0 "main"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command name to mock |
| `$2` | number | Exit code the mock returns, default is `0` |
| `$3` | string | Text the mock prints on stdout, default is empty |

**🔗 See also**

- [dybatpho::mock_command_script](#dybatphomock_command_script)


---

### `dybatpho::mock_calls`

Print one line per recorded invocation of a mocked command.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mocked command name |

**📤 Output on stdout**

- The arguments of each call, oldest first

**🚦 Exit codes**

- `1`: The command was never mocked


---

### `dybatpho::mock_call_count`

Print how many times a mocked command was called.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mocked command name |

**📤 Output on stdout**

- Call count, `0` when the mock was never invoked


---

### `dybatpho::assert_mock_called`

Assert that a mocked command was called, optionally with specific arguments.

**🧪 Example**

```bash
dybatpho::assert_mock_called kubectl get pods

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mocked command name |
| `$@` | string | Optional arguments that must appear together in one recorded call |

**🚦 Exit codes**

- `0`: A matching call was recorded
- `1`: The command was never called, or never with those arguments


---

### `dybatpho::unmock_command`

Remove one mocked command so the real command is used again.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mocked command name |


---

### `dybatpho::mock_http`

Register a canned HTTP response for URLs matching a pattern.

**🧪 Example**

```bash
dybatpho::mock_http 'api.example.test/status' 200 '{"ok":true}'

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Substring matched against the requested URL |
| `$2` | number | HTTP status code the mock reports |
| `$3` | string | Optional response body written to the caller's output file |
| `$@` | string | Optional extra response headers in `Name: value` form |

**🧩 Variable sets**

- **`PATH`** (Prefixed): with the mock directory on first use

**🚦 Exit codes**

- `1`: The status code is not a three-digit number


---

### `dybatpho::mock_http_calls`

Print every URL requested through the HTTP mock, oldest first.

_Function has no arguments._

**📤 Output on stdout**

- One requested URL per line

**🚦 Exit codes**

- `1`: No HTTP request was made through the mock


---

### `dybatpho::mock_http_payloads`

Print the request material of every mocked HTTP call that did not
travel in the argument vector, newest last, one request per line.

Credentials and request bodies are deliberately kept off `curl`'s command
line, because arguments are readable by every account on the host through
`/proc/<pid>/cmdline`. They go into a `--config` file and onto standard
input instead. That is the right thing for a running script and an awkward
thing for a test, which still has to be able to say "the token was sent" and
"the body carried this field" -- so the mock records them here.

**🧪 Example**

```bash
dybatpho::mock_http "api.github.com" 201 '{"number":12}'
dybatpho::forge_issue_create "Nightly failing" "It broke"
dybatpho::mock_http_payloads   # header = "Authorization: Bearer ..." {"title":...}

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEST_MOCK_DIR`** | string | Directory the mocks live in |

**📤 Output on stdout**

- One line per recorded request

**🚦 Exit codes**

- `0`: Requests were recorded
- `1`: No mocked request has been made yet

**🔗 See also**

- [- `dybatpho::mock_http` - `dybatpho::mock_http_calls](#dybatphomock_http-dybatphomock_http_calls)


---

### `dybatpho::assert_http_called`

Assert that a URL matching a pattern was requested through the HTTP mock.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Substring matched against the requested URLs |

**🚦 Exit codes**

- `0`: A matching request was recorded
- `1`: No matching request was recorded


---

### `dybatpho::fixture_dir`

Create a temporary fixture directory that is removed when the shell exits.

**🧪 Example**

```bash
dybatpho::fixture_dir workdir
printf 'data\n' > "${workdir}/input.txt"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the directory path |

**🔗 See also**

- [dybatpho::create_temp](#dybatphocreate_temp)


---

### `dybatpho::fixture_file`

Create a temporary fixture file holding the given content.

**🧪 Example**

```bash
dybatpho::fixture_file settings '{"mode":"dev"}' ".json"
dybatpho::assert_json_query "${settings}" '.mode' dev

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the file path |
| `$2` | string | File content, or `-` to read the content from stdin |
| `$3` | string | Optional file extension, default is `.txt` |

**🔗 See also**

- [dybatpho::create_temp](#dybatphocreate_temp)


---

### `dybatpho::unmock_all`

Remove every mock created in this shell and restore the environment.

_Function has no arguments._
