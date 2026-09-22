# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`doctor` module — one report of what the environment is missing.**
  `dybatpho::doctor` prints the Bash version, the library version, the host
  platform, and every external command the loaded modules can call, each marked
  found or missing. A module only reaches for `yq`, `curl`, or `tar` when the
  caller reaches the function that needs it, so this turns a sequence of
  mid-script failures into one list to fix before the work starts. Missing
  **required** dependencies fail the report; missing **optional** ones are
  reported and succeed, because they only cost part of a module.

  `--modules "json,git"` checks a set the shell has not loaded yet, `--all`
  covers the registry, `--quiet` answers through the exit code alone for CI, and
  `--json` emits one object — built without `jq`, since a diagnostic that needs a
  tool the user may be missing is of no use.
  `dybatpho::doctor_requirements <module> [required|optional|all]` exposes the
  declarations, and `dybatpho::doctor_bash_supported` answers the version
  question on its own. A dependency written as `a|b` is satisfied by either, so
  `file` reports one row for `sha256sum|shasum|openssl`.

  ```sh
  . dybatpho/init.sh --modules doctor json archive
  dybatpho::doctor || dybatpho::die "Install the tools listed above first"
  ```

- **`dybatpho::version`** — the library now reports which copy is loaded, from
  `init.sh` alone and without loading a module. The version comes from the new
  `VERSION` file beside `init.sh`, with the commit the copy is at appended as
  SemVer build metadata — `2.0.0+af745ff`, and `+af745ff.dirty` when the working
  tree has uncommitted changes — so a report names the code that ran rather than
  the last release before it. Only the library's own checkout is consulted: a
  copy vendored inside another project reports its stamped version alone. A checkout with no `VERSION` file falls back to
  `git describe`, and a copy with neither answers `unknown` rather than empty. It
  drops a leading `v`, caches into `DYBATPHO_VERSION`, and honors that variable
  when it is already set.

- **`scripts/bundle.sh`** — flattens a module selection into a single
  `dybatpho.bundle.sh` to vendor into another repository or bake into a
  container image. The selection is the same `--modules` used everywhere else
  and is resolved by running `init.sh` itself, so the bundled set cannot drift
  from what that selection loads. The generated file carries the bootstrap
  guards and the module sources verbatim, needs no `src/` directory beside it,
  reports the version it was generated from, and lists only what it carries as
  its registry. Inside a bundle, `dybatpho::load` succeeds for a carried module
  and fails for anything else with the command that regenerates the bundle with
  it. The generator refuses to overwrite an existing output without `--force` or
  `DYBATPHO_FORCE`, honors `DRY_RUN`, and verifies that what it wrote parses and
  can be sourced.

  ```sh
  scripts/bundle.sh --modules "logging git semver" --output dist/dybatpho.sh
  ```

- **XDG directories and more filesystem helpers in the `file` module.**
  `dybatpho::xdg_config_dir`, `xdg_cache_dir`, `xdg_data_dir`, and
  `xdg_state_dir` return the directories the XDG Base Directory specification
  defines, optionally scoped to an application name. They honor the matching
  environment variable when it holds an absolute path and fall back to the
  specification's default otherwise — including when the variable holds a
  relative path, which the specification says to ignore. They build a path and
  create nothing, so they pair with `dybatpho::ensure_dir`, which prints the
  directory it made.

  Alongside them: `dybatpho::file_mtime` reports a modification time as a Unix
  timestamp, `dybatpho::dir_size` totals the regular files in a tree (excluding
  symlinks, so a target inside the tree cannot count twice),
  `dybatpho::file_is_binary` looks for a NUL byte in the first block so a text
  rewrite can be skipped rather than mangling the file, and
  `dybatpho::create_temp_dir` asks for a temporary directory by name instead of
  passing `/` as an extension to `dybatpho::create_temp`.

  ```sh
  state="$(dybatpho::ensure_dir "$(dybatpho::xdg_state_dir myapp)" 700)"
  printf '%s\n' "${run_id}" | dybatpho::file_write_atomic "${state}/last-run"
  ```
- **`cli` typo suggestions** — an unrecognized option or invalid command now
  names the closest thing the command accepts, compared by Levenshtein distance
  with leading dashes ignored, so `--colr` answers with
  `Did you mean '--color'?` and `depoy` with `Did you mean 'deploy'?`. Typing a
  prefix of a longer switch counts as an abbreviation and outranks every
  edit-distance match. `dybatpho::cli_levenshtein` and `dybatpho::cli_suggest`
  are exposed for CLIs that want to do their own matching.

  Making that work required the parser to notice a mistyped option at all:
  a command that declares at least one switch now rejects an unmatched `-x` or
  `--xy` instead of quietly collecting it as a positional argument. `--` is
  still how dashed values are passed through, and a command that declares no
  switches is a passthrough wrapper and keeps collecting them unchanged.

- **`cli` generated negation switches** — `negatable:true` on
  `dybatpho::opts::flag` generates a `--no-<name>` for every long switch and
  alias, instead of spelling the pair out as `--{no-}name`. Without an explicit
  `off:`, a negatable flag turns off to `false` rather than to the empty string,
  so `--no-color` lands on a value worth testing.

- **`cli` counting flags** — `count:true` records how often a flag appeared
  rather than a value, starting at `0`, so `-v`, `-vv`, and `-v -v` yield `1`,
  `2`, and `2`. `dybatpho::cli_verbosity_level` maps that count onto a log level
  and `dybatpho::cli_apply_verbosity` applies it to `LOG_LEVEL`, which is the
  `-vv`-raises-verbosity idiom in two lines of spec.

- **`cli` options bound to configuration keys** — `config:<key>` binds an option
  to a key loaded by `src/config.sh`, giving one precedence chain across the
  whole CLI: **flag > `env:` > `config:` > `init:`**. `cli` and `config` no
  longer have to be wired together by hand at every option; `cli` now depends on
  `config` so the binding works wherever `cli` is loaded. Configuration has to
  be loaded before `dybatpho::generate_from_spec`, because that is when an
  option's initial value is resolved; a missing key, or a CLI that never loaded
  configuration, falls through to `init:`.

- **`cli` documented positional arguments** — `dybatpho::opts::arg` declares a
  positional argument's name, description, and whether it is required or
  variadic. The values still land in the rest variable, but the usage line now
  shows real placeholders (`<SOURCE> [TARGET]...`), help gains an `Arguments`
  section, and the schema and man page describe them too. Declaring arguments
  also derives the `args:<rule>` count check, so the two cannot disagree; an
  explicit `args:` still wins.

- **`cli` completion cache** — `dybatpho::generate_completion` caches its output
  under `DYBATPHO_CLI_CACHE_DIR` (default
  `${XDG_CACHE_HOME:-$HOME/.cache}/dybatpho/cli`), so a shell startup that
  sources a generated completion does not walk the spec tree again. The key
  hashes the script declaring the spec, so editing it invalidates the entry on
  its own and there is nothing to clear by hand. `DYBATPHO_CLI_CACHE=false`
  regenerates every time.

- **`parallel` module** — run independent work a few jobs at a time.
  `dybatpho::parallel_map` runs one command over a list, passing each item as a
  single value so an item with spaces or shell syntax is not re-parsed;
  `dybatpho::parallel_run` runs different shell commands at once. Each job's
  output is captured while it runs and replayed afterwards in submission order,
  so a concurrent run reads like a serial one, and each job's exit code is kept
  separately and readable through `parallel_status`, `parallel_count`, and
  `parallel_failed`.

  `DYBATPHO_PARALLEL_JOBS` sets the default width, `0` means one job per
  processor, and `DYBATPHO_PARALLEL_FAILFAST` stops further jobs once one fails,
  reporting the ones that never started as skipped rather than failed. The pool
  gives each job its own process group, so an interrupted run ends the jobs
  together with anything they started.

  ```sh
  . dybatpho/init.sh --modules parallel
  dybatpho::parallel_map 8 check_host "${hosts[@]}" || true
  for ((i = 0; i < $(dybatpho::parallel_count); i++)); do
    [[ "$(dybatpho::parallel_status "${i}")" == 0 ]] || dybatpho::warn "${hosts[i]} is down"
  done
  ```

- **`release` module** — cut a release from the commits since the last tag.
  `dybatpho::release_next_version` derives the version from
  [Conventional Commits](https://www.conventionalcommits.org) (a breaking change
  moves the major, `feat` the minor, `fix` and `perf` the patch, anything else
  moves nothing and is reported as nothing to release);
  `release_changelog` writes the matching entry, grouped by what changed;
  `release_artifact_name` and `release_package` produce one artifact per platform
  under the `name_version_os_arch` layout Go release tooling established, a zip
  for Windows and a tarball elsewhere; `release_checksums` writes a `SHA256SUMS`
  file that `sha256sum -c` verifies; and `release_sign` signs it with `gpg`, or
  with any other tool through `DYBATPHO_RELEASE_SIGN_CMD`.

  The module produces files and never contacts a forge, so credentials for
  pushing a tag or creating a release stay with the caller.

  ```sh
  . dybatpho/init.sh --modules release
  version="$(dybatpho::release_next_version .)" || exit 0
  dybatpho::release_changelog . "$(dybatpho::git_latest_tag . 'v*')" HEAD "${version}"
  dybatpho::release_package ./dist/linux_amd64 ./release mytool "${version}" linux amd64
  dybatpho::release_sign "$(dybatpho::release_checksums ./release)"
  ```

- `dybatpho::git_latest_tag` returns the highest version tag in a repository,
  ordering tags as versions rather than as strings, so `v10.0.0` outranks
  `v9.0.0`.

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

- **`pkg` module** — detect the machine's package manager and install
  dependencies through it. `dybatpho::pkg_manager` reports one of `apt`, `brew`,
  `apk`, `dnf`, `pacman`, or `emerge`, preferring the distribution manager over
  Homebrew on Linux, and `DYBATPHO_PKG_MANAGER` overrides the detection.
  `dybatpho::pkg_installed` and `dybatpho::pkg_missing` answer what is already
  there — on Homebrew they ask the formula scope and the cask scope, so an
  installed cask is not reinstalled on every run — `dybatpho::pkg_name` resolves `<manager>:<package>` overrides so one
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

  A flag the module does not model — `--cask` on Homebrew, `--no-cache` on
  Alpine, `--no-install-recommends` on Debian — goes through with `--arg`, once
  per flag, and lands after the manager's own flags and before the package
  names. `dybatpho::pkg_install`, `dybatpho::pkg_update`,
  `dybatpho::pkg_install_command`, `dybatpho::pkg_ensure`, and
  `dybatpho::pkg_require` all take it; the index refresh that `--update` runs
  never receives the install's extra arguments.

  ```sh
  . dybatpho/init.sh --modules pkg
  dybatpho::pkg_install --dry-run ripgrep # preview the command
  dybatpho::pkg_ensure --force --update curl jq
  dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd
  dybatpho::pkg_install --force --arg --cask -- firefox
  dybatpho::pkg_ensure --force --arg --no-cache -- curl
  ```

### Changed

- **`cli` help output now reads like a conventional command-line tool.** The
  usage line describes what the command actually accepts — `[OPTIONS]`, a
  `COMMAND` only when there are subcommands, and the declared positional
  arguments — instead of a fixed `[options...] [arguments...]`. Help gains an
  `Arguments` section, a `Commands` section ahead of `Options`, and a closing
  `Run '<prog> COMMAND --help' ...` line. Rows across all three sections align
  to one column computed from the longest label rather than a fixed width, and
  the `-h, --help` every command already accepted is finally listed.

  Each option now carries its details underneath it — `[env: NAME]`,
  `[config: key]`, `[choices: a, b]`, `[default: value]`, `[repeatable]`,
  `[repeat to increase]` — so where a value comes from is visible without
  reading the spec. A default built from a command substitution is left out,
  since printing the expression would mislead more than it helps.

- **BREAKING:** the minimum supported Bash is now 4.3, raised from 4.0.
  `init.sh` refuses to load on anything older instead of failing later with a
  confusing error.

  The library already depended on 4.3 without saying so: modules across it
  return values through nameref parameters (`local -n`, 43 uses at the time of
  the change), and the worker pool waits with `wait -n`. Both arrived in Bash
  4.3, so on 4.0 through 4.2 the library did not work — it just failed at the
  first call rather than at load time.

  Bash 4.3 was released in 2014 and every current distribution ships something
  newer. macOS still ships 3.2, which was already too old; `brew install bash`
  provides a current one.

- **The test runner is roughly three times faster and reports one summary
  instead of a TAP transcript.** `test/test_helper.bash` parks Bats' `DEBUG`
  trap while it sources the bats libraries and every dybatpho module: that trap
  fires once per executed command, and the setup a test does not care about was
  costing ~800ms per test instead of ~150ms. `scripts/test.sh` now lets Bats
  schedule at the test level so one heavy file no longer pins a single core, and
  prints a per-file table plus one set of totals, with the failure detail
  replayed once at the end. A full run went from ~6m to ~2m.
- **`scripts/test.sh` follows the library's own CLI conventions.** Options are
  declared through `dybatpho::opts::*` and parsed by
  `dybatpho::generate_from_spec`, so `--help` is generated, values are
  validated, and `--jobs`/`--chunk` read `DYBATPHO_TEST_JOBS`/
  `DYBATPHO_TEST_CHUNK` as their initial values.
- **Coverage is opt-in and chunked.** `scripts/test.sh` runs without kcov by
  default, which is what makes it usable in an edit/test loop; `--coverage`
  runs one kcov invocation per `--chunk` files and merges the parts into
  `coverage/bats`. kcov never releases the trace state it accumulates, so a
  single invocation over the whole suite grew until the OOM killer took the run
  down.

### Fixed

- **A dybatpho script run from a dybatpho shell no longer dies on its first log
  line.** The optional `metrics` hooks in `helpers`, `logging`, and `network`
  asked `declare -F dybatpho::metrics_counter_inc` whether to record. That name
  is exported, so a child shell inherited it without the internal helpers it
  calls, took the recording branch, and aborted with
  `__dybatpho_metrics_key: command not found` — which hit any script whose
  parent shell had loaded `metrics`, on its first `dybatpho::info` or first
  retry. The hooks now test an internal helper of the module, which cannot cross
  a process boundary, so they stay inert exactly when recording is impossible
  and still record in a child that loads `metrics` itself.
- **Temporary files no longer pile up in `/tmp` during a test run.** Bats
  re-arms its own `EXIT` trap after each test body, which discarded the cleanup
  trap `dybatpho::create_temp` had just registered, so virtually every temporary
  file a test created survived the run — the suite left roughly a thousand
  `/tmp/dybatpho_*` entries behind each time. With no explicit parent directory,
  temporary paths are now created under the Bats temporary directory when
  running as a test, which Bats removes itself and which is the right lifetime
  for a file a test created. A full suite run now leaves nothing behind.

- **`dybatpho::cleanup_file_on_exit` no longer grows the trap with every path.**
  Each registration used to append its own `rm` command, so a script creating
  many temporary files built a trap string that grew with each one. Paths are
  now collected in `DYBATPHO_CLEANUP_PATHS` and removed by a single trap
  installed on first use. A path registered by one shell is still never removed
  by another, so a subshell exiting leaves its parent's temporary files intact.

- **`dybatpho::create_temp` honours the requested parent directory when
  `mktemp` is missing.** The fallback path hardcoded `/tmp`, ignoring both the
  explicit fourth argument and `TMPDIR`.

- **`parallel`**: a job that called `exit` ended the worker before its exit code
  was written, so the pool reported the job as never having run and the run as
  successful even though the job had failed. Both `dybatpho::parallel_map` and
  `dybatpho::parallel_run` now evaluate the job one subshell deeper, so `exit`
  ends only the job.
- **`cli`**: a persistent option declared on a command was listed twice in that
  command's own help, once replayed as an inherited definition and once from
  its own spec.
- **`cli`**: the `@none` sentinel recorded for an alias-less command leaked into
  generated completion word lists and into the `aliases` array of the generated
  JSON schema.

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
- **Two tests were silently not running.** `test/logging.bats` unset
  `EPOCHREALTIME` in the test body; it is a bash dynamic variable, so the unset
  is permanent, and Bats reads it for `--timing` right after the body returns —
  which dropped the test from the run with nothing but a warning line to say so.
  `test/metrics.bats` spawned a child shell with `bash -c`, whose empty
  `BASH_SOURCE` the kcov hook expands on every command until `set -u` fails the
  test, so it failed under coverage only. `scripts/test.sh` now fails a run when
  a file executes fewer tests than it declares, so a disappearing test cannot
  pass unnoticed again.

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
