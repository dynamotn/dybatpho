# Changelog: 3.x releases

Releases 3.x of dybatpho, archived from [CHANGELOG.md](../../CHANGELOG.md) by
`scripts/changelog_archive.sh`. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-09-22

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

- **`scripts/release.sh`** — cuts a release in one command. It refuses to start
  on a dirty tree or an existing tag, resolves the version from the commits
  through `dybatpho::release_next_version` (or from `--version` / `--bump`),
  stamps `VERSION`, promotes `## [Unreleased]` in `CHANGELOG.md` to
  `## [<version>] - <date>` with a fresh empty `Unreleased` above it, rewrites
  the comparison links, regenerates `doc/`, commits `chore(release): v<version>`
  and tags it annotated with the changelog entry, builds the all-modules bundle
  with a `SHA256SUMS` file beside it, pushes, and creates the GitHub release
  with that same entry as its notes. The notes are always the handwritten
  changelog, never a generated commit list, and an `Unreleased` section that
  marks a change **BREAKING** forces a major release even when no commit subject
  carried `!`. `--dry-run` performs every check and prints every command without
  writing anything, and `--no-push` / `--no-github` / `--no-bundle` / `--sign`
  cover the rest of the release policy.

  ```sh
  scripts/release.sh --dry-run
  scripts/release.sh --version 3.0.0 --sign
  ```

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
- **Version ranges, ordering, and the last links of the release chain.**
  `dybatpho::semver_satisfies` answers whether a version fits a range written
  the way npm and Cargo write them: `^1.2` for anything compatible, `~1.2.3` for
  patch updates, plain comparisons such as `>=18`, partial versions and
  wildcards such as `1.2.x`, several comparators meaning all of them, and `||`
  meaning either. A pre-release only satisfies a range that names a pre-release
  of the same release, so `^1.0.0` does not quietly accept `2.0.0-alpha`.

  `dybatpho::semver_sort` and `dybatpho::semver_max` order versions by the
  specification rather than as strings, reading the list from arguments or
  standard input and preserving a leading `v`, so a list of tags stays usable.

  `dybatpho::git_is_ancestor` reports whether one commit is reachable from
  another, which is how a release script tells an already-released tag from one
  that is not on this branch.

  `dybatpho::release_commit_parse` breaks a commit into its type, scope,
  breaking flag, and description. `release_commit_type` reports a breaking
  change as its own kind, which loses the type; the parser reports both, and the
  bump and changelog helpers now derive their answers from it instead of each
  restating the convention.

  ```sh
  dybatpho::semver_satisfies "$(node --version | tr -d v)" ">=18" \
    || dybatpho::die "Node 18 or newer is required"
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

- **The repository contract is enforced by the test suite instead of a
  checklist.** `test/conventions.bats` fails the suite when a module ships
  without its `doc/`, `doc/spec/`, `test/` or `example/` counterpart, when it
  isn't registered in `init.sh`, when its spec is missing from
  `doc/spec/README.md`, when a public function is absent from its module
  documentation or never named in its test file, or when a function escapes the
  `dybatpho::` / `__dybatpho_` namespaces. The rules were already in `AGENT.md`;
  they were prose a contributor had to remember, and drift had already happened.
  Each check reports every violation at once rather than stopping at the first.

- **Private functions in `ai` and `agent` now carry the mandatory `__dybatpho_`
  prefix.** `src/ai.sh` and `src/agent.sh` defined 38 helpers as `__ai_*` and
  `__agent_*` — names bare enough to collide with a helper defined by the
  calling script, which is the reason the prefix is mandatory. They are private
  and were never exported, so no consumer can be affected.

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

- **Six public functions had no direct test.** `dybatpho::ai_stream`,
  `dybatpho::opts::validate_choice`, `dybatpho::lock_field`,
  `dybatpho::lock_is_alive`, `dybatpho::lock_reclaim_stale` and
  `dybatpho::mock_calls` were only ever reached indirectly, so nothing pinned
  their contracts. Each now has a test naming it directly.

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

[3.0.0]: https://github.com/dynamotn/dybatpho/compare/v2.0.0...v3.0.0
