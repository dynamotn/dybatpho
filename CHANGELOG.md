# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`metrics` module** — measure a script and export the result to Prometheus.
  `dybatpho::metrics_time` wraps a command, records how long it took and whether
  it failed, and returns its exit code unchanged; `metrics_timer_start` and
  `metrics_timer_stop` cover a region rather than one command;
  `metrics_counter_inc`, `metrics_gauge_set`, and `metrics_observe_ms` record
  directly. `metrics_render` produces the Prometheus text exposition format and
  `metrics_write` saves it atomically, which is what the node exporter's textfile
  collector requires.

  Loading the module also turns on instrumentation the library was already in a
  position to record: retries and exhausted retries from `dybatpho::retry`,
  request duration and final status from `dybatpho::curl_do`, and logged messages
  by level. A script that does not load the module is unaffected.

  ```sh
  . dybatpho/init.sh --modules metrics
  dybatpho::metrics_time backup_duration_seconds target=db -- pg_dump -Fc mydb -f /backup/db.dump
  dybatpho::metrics_write /var/lib/node_exporter/textfile_collector/backup.prom
  ```
- **`ai` module.** Call a language model from a script the way you call any
  other command: prompt in, text on stdout, a documented exit code. One API
  covers four backends — the Claude Messages API, any OpenAI-compatible
  `/v1/chat/completions` endpoint, a local Ollama daemon, and an installed
  `claude`, `llm` or `ollama` client — so the choice of provider is
  configuration, not a rewrite.

  ```sh
  . dybatpho/init.sh --modules ai
  dybatpho::ai_ask "Summarize this deploy log in three bullets"
  ```

  Around the call it provides what a script actually needs: conversations kept
  in a file (`ai_conversation_new`, `ai_chat`), answers validated against a
  JSON schema (`ai_json`), token streaming (`ai_stream`), a tool-use loop that
  runs your shell functions (`ai_tool_register`, `ai_run`), response caching,
  and usage accounting. Secrets registered with `dybatpho::secret_register` are
  masked before any request is built, `dybatpho::ai_budget` caps how many calls
  a run may make, and `DRY_RUN` exercises the whole path without sending
  anything. Needs `yq` or `jq`, like the rest of the library.

- **`agent` module.** Make a script safe for an AI agent to drive.
  `agent_result` and `agent_error` print readable text for a person and JSON
  for an agent from the same call site; `agent_confirm` replaces an
  unanswerable prompt with an explicit `DYBATPHO_AGENT_ALLOW` allowlist and
  records every decision through `agent_audit`; `agent_context` tells a model
  what it is working with before it acts.

  ```sh
  . dybatpho/init.sh --modules agent
  dybatpho::agent_tools _spec_root mytool anthropic # Claude tool definitions
  dybatpho::agent_mcp _spec_root mytool             # MCP tools/list payload
  ```

  Tool definitions are generated from the same `cli.sh` option spec that drives
  the parser, in Anthropic, OpenAI, or MCP shape, so a schema cannot describe an
  option the CLI does not have. Needs `yq` or `jq`, like the rest of the library.

- **JSON documents you are still assembling.** `json.sh` gains five helpers for
  documents held in a shell variable rather than a file, so building JSON no
  longer means quoting by hand:

  ```sh
  dybatpho::json_object status ok message 'it "worked"' ports:json '[80,443]'
  # {"status":"ok","message":"it \"worked\"","ports":[80,443]}
  ```

  `json_string` encodes one value, `json_object` builds an object from name and
  value pairs (a name ending in `:json` nests an already-encoded document),
  `json_eval` and `json_get` run a filter against a document in a variable
  returning compact JSON or a bare scalar, and `json_valid` reports whether a
  string parses. All five prefer `yq` and fall back to `jq`, like the rest of
  the module, and the `ai` and `agent` modules are built on them.

- `example/ai_ops.sh` and `example/agent_ops.sh`, both runnable with no API key.

### Fixed

- **File writers now work on macOS.** `chmod` and `sed` were given `--` to mark
  the end of the options, which the BSD versions on macOS read as a file name
  instead: `chmod: --: No such file or directory`. Every writer that carries a
  destination mode over — `file_write_atomic`, `file_replace`,
  `file_ensure_line`, `file_remove_line`, `ensure_dir` — failed there. The
  paths are now guarded by prefixing `./` when a name could be read as an
  option, which both platforms accept.
- CI installs a JSON backend. The `kcov` container had neither `yq` nor `jq`,
  so anything exercising `json.sh` for real died with `Neither yq nor jq is
  installed`; the existing JSON tests passed only because they stub the
  binaries.
- `scripts/test.sh` takes the worker count from `DYBATPHO_TEST_JOBS`, still one
  per core by default. A kcov-instrumented worker per core no longer fits in a
  CI runner now that the library has grown — the OOM killer was taking the run
  down mid-suite with exit 137 — so CI asks for two.

- **`pkg` module** — detect the machine's package manager and install
  dependencies through it. `dybatpho::pkg_manager` reports one of `apt`, `brew`,
  `apk`, `dnf`, `pacman`, or `emerge`, preferring the distribution manager over
  Homebrew on Linux, and `DYBATPHO_PKG_MANAGER` overrides the detection.
  `dybatpho::pkg_installed` and `dybatpho::pkg_missing` answer what is already
  there, `dybatpho::pkg_name` resolves `<manager>:<package>` overrides so one
  script names a dependency once, and `dybatpho::pkg_install_command` prints the
  exact command a run would execute.

  `dybatpho::pkg_install`, `dybatpho::pkg_update`, `dybatpho::pkg_ensure`, and
  `dybatpho::pkg_require` are the mutating half, and none of them changes the
  system quietly: each asks for confirmation unless `--force` or
  `DYBATPHO_FORCE` approves it, refuses rather than guessing in a
  non-interactive shell, and prints the command instead of running it under
  `--dry-run` or `DRY_RUN`. Elevation follows `DYBATPHO_PKG_SUDO` and is never
  added for Homebrew, and `DYBATPHO_PKG_ASSUME_YES=false` drops the managers'
  non-interactive flags.

  ```sh
  . dybatpho/init.sh --modules pkg
  dybatpho::pkg_install --dry-run ripgrep      # preview the command
  dybatpho::pkg_ensure --force --update curl jq
  dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd
  ```

### Fixed

- `network` and `metrics` called `__log_now_ms`, which the internal-function
  rename had turned into `__dybatpho_log_now_ms`. Every timed `curl` call and
  every timer in the `metrics` module failed with `command not found` instead of
  recording a duration.

## [2.0.0] - 2026-09-17

### Added

- **Module loading on demand.** `init.sh` accepts a module set, either as a
  leading `--modules` argument or through the `DYBATPHO_MODULES` environment
  variable, and resolves the dependencies between modules for you. Use
  `--modules all` for the whole library.

  ```sh
  . dybatpho/init.sh --modules git semver
  DYBATPHO_MODULES="git semver" . dybatpho/init.sh
  ```

- `dybatpho::load` widens the module set after bootstrap, `dybatpho::module_loaded`
  answers whether a module is available, and `dybatpho::module_list` prints the
  `loaded`, `all`, `core`, or `optional` module names.
- **`lock` module** — serialize concurrent runs of a script without `flock`, which
  macOS does not ship. `dybatpho::with_lock` runs a command under a lock and
  releases it on every exit path; `lock_acquire`, `lock_release`, `lock_is_held`,
  `lock_info`, `lock_field`, `lock_path`, `lock_hostname`, `lock_is_alive`, and
  `lock_reclaim_stale` cover the rest. A lock records its holder, so a failed
  acquisition reports who owns it, and a lock left behind by a dead process is
  reclaimed rather than blocking forever. `DYBATPHO_LOCK_DIR` and
  `DYBATPHO_LOCK_POLL_INTERVAL` tune where locks live and how often waiting
  retries.
- **`safety` module** — guards for destructive operations, so a script asks
  before it removes or replaces something: `dybatpho::confirm`,
  `assert_safe_path`, `safe_rm`, `safe_overwrite`, `safe_copy`, `safe_move`,
  `safe_extract`, `safe_system`, and `is_interactive`. Every guarded operation
  validates the target path first, requires `--force` or a confirmation, refuses
  to touch a protected path such as `/` or `${HOME}`, and honors `DRY_RUN`.
  `is_interactive` lets a script tell an operator's terminal from CI, where a
  prompt would hang.
- **`testing` module** — 31 helpers for testing shell code: assertions for files,
  modes, symlinks, JSON, and YAML; snapshots, including CLI snapshots with
  scrubbing for values that change per run; mocks for commands, environment
  variables, and HTTP requests, each restoring the previous state; and fixtures
  that clean themselves up. Assertions report and return rather than terminate,
  so a test run reports every failure instead of stopping at the first.
- **Circuit breaker and more `curl` helpers in `network`** —
  `dybatpho::circuit_breaker` stops hammering an endpoint that keeps failing and
  lets a trial request through after a cooldown, with `circuit_state` and
  `circuit_reset` to inspect and clear it; `DYBATPHO_CIRCUIT_THRESHOLD` and
  `DYBATPHO_CIRCUIT_COOLDOWN` tune it. Added alongside: `curl_request`,
  `curl_parse_response`, `curl_response_header`, `curl_resume_download`,
  `curl_upload`, `curl_timeout`, and `verify_checksum`.
- **Structured logging to a file, with rotation** — `LOG_FILE` appends JSON log
  events independently of the console format, `LOG_FILE_LEVEL` sets its own
  threshold, and `LOG_FILE_MAX_BYTES` with `LOG_FILE_MAX_BACKUPS` rotate it.
  Every structured event carries `LOG_REQUEST_ID`, generated when unset, so the
  lines of one run can be correlated.
- **Configuration schema and documentation** — `dybatpho::config_doc` renders the
  declared schema as documentation, and `dybatpho::config_schema_reset` clears it
  between runs.
- **File content helpers in the `file` module** — the paths-and-temp-files module
  now also rewrites what a file holds. Every writer stages its output next to the
  destination and renames it into place, so a reader never sees a half-written
  file and an interrupted run leaves the original intact; the destination's mode
  is carried over, and its owner too when the process may set it. All of them
  honor `DRY_RUN`.

  | Function | Purpose |
  | --- | --- |
  | `dybatpho::file_write_atomic` | Write standard input over a file |
  | `dybatpho::file_replace` | Substitute a pattern in place, without the `sed -i` argument that differs on GNU and BSD |
  | `dybatpho::file_ensure_line` | Append a line unless the exact line is already there |
  | `dybatpho::file_remove_line` | Remove every occurrence of an exact line |
  | `dybatpho::file_hash` | Checksum a file as `md5`, `sha1`, `sha256`, or `sha512` |
  | `dybatpho::file_size` | Size in bytes |
  | `dybatpho::file_age_seconds` | Seconds since the last modification |
  | `dybatpho::file_backup` | Copy a file under a timestamped name and print the copy's path |
  | `dybatpho::find_up` | Search a directory and its ancestors for an entry, such as `.git` |
  | `dybatpho::ensure_dir` | Create a directory tree, apply a mode, and print the path |

  `file_ensure_line` and `file_remove_line` are idempotent, so a dotfiles script
  that runs twice leaves the same result as running it once. `file` is a core
  module, so these are available from a bare `. dybatpho/init.sh`.

  A destination that is a symlink is followed, so editing a dotfile symlinked
  into a repository rewrites the file in the repository and leaves the link in
  place. Set `DYBATPHO_FILE_FOLLOW_SYMLINKS=false` to replace the link instead.
  `file_size` and `file_age_seconds` likewise describe the file a symlink points
  at, not the link.

- `example/init_modules.sh`, showing how to request a module set and widen it at
  run time.
- `doc/init.md`, generated from `init.sh` like every module reference.

### Changed

- **BREAKING:** sourcing `init.sh` with no argument now loads only the core
  modules — `string`, `logging`, `helpers`, `process`, `file` and `secret`.
  Previously it loaded every module. A script that uses anything else has to ask
  for it:

  ```sh
  . dybatpho/init.sh               # before: everything; now: core only
  . dybatpho/init.sh --modules all # the previous behavior
  . dybatpho/init.sh --modules git # or name what the script actually uses
  ```

  Without the change, the script fails on the first call into an unloaded
  module. `dybatpho::module_list loaded` shows what a shell currently has.
- Project editor settings moved from `.neoconf.json` to `.vscode/settings.json`,
  which VS Code reads natively and
  [codesettings.nvim](https://github.com/mrjones2014/codesettings.nvim) feeds
  into Neovim's LSP configuration. The file pins the two bash-language-server
  settings without which no `dybatpho::` function resolves in an editor.

### Fixed

- Git helpers no longer inherit ambient Git environment variables such as
  `GIT_DIR` and `GIT_WORK_TREE`, which made them read whichever repository the
  caller's environment happened to point at rather than the one they were given.

### Security

- `dybatpho::archive_is_safe` and `dybatpho::archive_unsafe_entries` report
  archive entries that would escape the extraction directory, and
  `dybatpho::safe_extract` validates an archive before extracting it. This blocks
  path-traversal entries such as `../../etc/passwd` in an untrusted archive.

[Unreleased]: https://github.com/dynamotn/dybatpho/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/dynamotn/dybatpho/releases/tag/v2.0.0
