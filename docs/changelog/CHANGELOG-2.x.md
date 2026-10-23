# Changelog: 2.x releases

Releases 2.x of dybatpho, archived from [CHANGELOG.md](../../CHANGELOG.md) by
`scripts/changelog_archive.sh`. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[2.0.0]: https://github.com/dynamotn/dybatpho/releases/tag/v2.0.0
