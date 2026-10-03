# AGENT.md

## Purpose

`dybatpho` is a Bash utility library. Its primary development model is
**spec-driven**: define behavior in source/spec functions, then reuse the same
metadata to generate the parser, help, completions, JSON schema, and man page.

This document describes the repository workflow and conventions to preserve.

## Repository structure

- `src/` — Bash modules, each covering one functional area.
- `init.sh` — required entrypoint; source it before using the library.
- `test/` — Bats tests for each module, such as `test/cli.bats`.
- `example/` — complete, runnable usage examples for every public module.
- `docs/` — API documentation generated from source comments, including
  `docs/init.md` for the bootstrap's own public functions.
- `docs/spec/` — Spec Kit-style feature specifications.
- `CHANGELOG.md` — user-visible history, [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
- `scripts/test.sh` — test runner; `--coverage` adds the kcov report, and
  `--related <changed files>` runs only the tests covering them (the
  pre-commit hook uses it).
- `scripts/bundle.sh` — flatten a module selection into one vendorable file;
  covered by `test/bundle.bats` and specified in `docs/spec/doctor.md`.
- `scripts/release.sh` — cut a release: stamp `VERSION` and `CHANGELOG.md`,
  regenerate `docs/`, commit, tag, and publish the GitHub release. Run it with
  `--dry-run` first.
- `VERSION` — the version this copy reports through `dybatpho::version`;
  `scripts/release.sh` stamps it in the same commit that tags the release.
- `.mise.toml` — standard tasks such as `mise run test` and `mise run doc`.

## Module scope

Every module in `src/` must have a clear responsibility and expose public
functions under the `dybatpho::` namespace. Every public module must have a
corresponding complete example in `example/` (normally
`example/<module>_ops.sh`) **and a specification in `docs/spec/<module>.md`**.
When changing a module, read its source, tests, API documentation, matching
specification, and example before editing.

### Specification requirements

**Every module in `src/` MUST have `docs/spec/<module>.md`. A change that adds a
module or public behavior without its spec is incomplete and must not be
reported as done.** This is not conditional on the size of the change.

Generate or update the spec in the same change that touches the module:

- **New module** — write `docs/spec/<module>.md` before the work is considered
  complete, and register it in both the Spec Files and Source Mapping lists of
  `docs/spec/README.md`.
- **New or changed public function, argument, rule, output, or exit code** —
  add or update the matching user story, functional requirement (`FR-xxx`),
  edge case, and integration test (`IT-xxx`) entries.
- **Removed behavior** — delete the requirements it covered rather than leaving
  them describing code that no longer exists.

Every spec follows the same section order, taken from the existing files:

1. Header (`# Feature Specification: <title>`, `Feature Branch`, `Status`,
   `Input` naming the source, tests, docs, and example it was derived from)
2. `## Problem Statement *(mandatory)*`
3. `## Business Value *(mandatory)*`
4. `## User Scenarios & Testing *(mandatory)*` — numbered, prioritized user
   stories, each with an **Independent Test** and numbered
   **Acceptance Scenarios** in Given/When/Then form, plus an example workflow
5. `## Edge Cases`
6. `## Requirements *(mandatory)*` — `FR-001`-style functional requirements
   written with MUST, and `### Key Entities` when the feature owns data
7. `## Success Criteria *(mandatory)*` — `SC-001`-style measurable outcomes
8. `## Integration Tests *(mandatory)*` — `IT-001`-style entries that map to
   real cases in `test/<module>.bats`
9. `## Acceptance Criteria *(mandatory)*`

Specs describe observable behavior and contracts, not implementation lines.
Requirements must be traceable: every `FR-xxx` should be enforced by code and
every `IT-xxx` should correspond to a test that exists.

Verify no module is missing a spec before finishing:

```bash
scripts/test.sh test/conventions.bats
```

`test/conventions.bats` enforces this rule and the rest of the repository
contract as part of the normal suite, so a missing spec fails the tests rather
than waiting for a reviewer. It checks that every `src/<module>.sh` has its
`docs/`, `docs/spec/`, `test/` and `example/` counterpart, that the module is
registered in `init.sh`, that the spec is listed in `docs/spec/README.md`, that
every public function is named in both its module doc and its test file, and
that no function escapes the `dybatpho::` / `__dybatpho_` namespaces.

Each test reports every violation it finds at once, so the output is the full
list of what the change still owes.

### Complete example requirements

A complete example is a user-facing, executable workflow rather than a list of
isolated function calls. It must:

- source `init.sh` and run successfully with `bash example/<name>.sh`;
- demonstrate the module's primary public APIs, including newly added options
  or behavior;
- show realistic input, expected output, and relevant success/failure paths;
- run non-interactively without credentials, network access, or machine-local
  assumptions; use temporary fixtures, dry-run mode, or command mocks where
  needed;
- clean up temporary files and avoid modifying the repository or user data.

When adding or changing a public API, update the corresponding example in the
same change. If a module has no example, add one before considering the work
complete.

`test/examples.bats` runs every example and fails when one exits non-zero or
changes the working tree, so these rules hold automatically. A new example needs
its own `@test` line there; the first test in that file fails when one is
missing, which is what stops a new example from silently never being run.

An example that needs the network must stub it. `example/network_ops.sh` shows
the pattern: it writes a `curl` executable into a temporary directory and puts
that directory first on `PATH`. A shell function is not enough — the network
module calls `command curl` on purpose, which bypasses functions.

| Module | Primary responsibility | Tests / documentation |
| --- | --- | --- |
| `agent.sh` | Agent detection, structured results and errors, allowlist gate, audit log, and tool/MCP definitions generated from a CLI spec | `test/agent.bats`, `docs/agent.md`, `docs/spec/agent.md` |
| `ai.sh` | Language model calls across Claude, OpenAI-compatible, Ollama, and CLI backends, with conversations, JSON output, streaming, tool use, caching, and budgets | `test/ai.bats`, `docs/ai.md`, `docs/spec/ai.md` |
| `array.sh` | Create, read, join, filter, and manipulate Bash arrays | `test/array.bats`, `docs/array.md`, `docs/spec/array.md` |
| `archive.sh` | Create, extract, and inspect archives | `test/archive.bats`, `docs/archive.md`, `docs/spec/archive.md` |
| `backup.sh` | Timestamped snapshots written atomically, checksum sidecars, newest-first listing, guarded restore, and retention pruning | `test/backup.bats`, `docs/backup.md`, `docs/spec/backup.md` |
| `cli.sh` | Declarative parser, help, subcommands, typo suggestions, config-bound options, completions, and CLI artifacts | `test/cli.bats`, `docs/cli.md`, `docs/spec/cli.md` |
| `config.sh` | Load dotenv, JSON/YAML configuration, precedence, typed schema validation, and configuration docs | `test/config.bats`, `docs/config.md`, `docs/spec/config.md` |
| `date.sh` | Portable date/time parsing, formatting, and calculations | `test/date.bats`, `docs/date.md`, `docs/spec/date.md` |
| `diff.sh` | Colored unified text diffs, structural JSON/YAML comparison by key, and a one-line change summary | `test/diff.bats`, `docs/diff.md`, `docs/spec/diff.md` |
| `doctor.sh` | Environment report: Bash version, library version, and the external commands the loaded modules declare | `test/doctor.bats`, `docs/doctor.md`, `docs/spec/doctor.md` |
| `file.sh` | Path and XDG helpers, upward search, directory creation, temporary files, atomic content rewrites, checksums, and metadata | `test/file.bats`, `docs/file.md`, `docs/spec/file.md` |
| `forge.sh` | GitHub and GitLab detection from the remote, authenticated requests, issues, and releases | `test/forge.bats`, `docs/forge.md`, `docs/spec/forge.md` |
| `git.sh` | Safe repository, branch, commit, reachability, and Git operations | `test/git.bats`, `docs/git.md`, `docs/spec/git.md` |
| `helpers.sh` | Argument validation, command lookup, retry, and common helpers | `test/helpers.bats`, `docs/helpers.md`, `docs/spec/helpers.md` |
| `i18n.sh` | Message catalogs, plural rules, and locale-aware numbers, money, sizes, dates, and text direction | `test/i18n.bats`, `docs/i18n.md`, `docs/spec/i18n.md` |
| `json.sh` | Query, validate, pretty-print, and convert JSON/YAML | `test/json.bats`, `docs/json.md`, `docs/spec/json.md` |
| `lock.sh` | Portable `mkdir`-based process locks, waiting, stale reclaim, and `with_lock` | `test/lock.bats`, `docs/lock.md`, `docs/spec/lock.md` |
| `logging.sh` | Log levels, text/JSON logging, banners, and Bash tracing | `test/logging.bats`, `docs/logging.md`, `docs/spec/logging.md` |
| `csv.sh` | RFC 4180 CSV: parsing quoted fields, reading columns, filtering rows, writing back, and converting to and from JSON | `test/csv.bats`, `docs/csv.md`, `docs/spec/csv.md` |
| `markdown.sh` | Markdown builders for headings, lists, task lists, links, badges, code blocks, tables and collapsible sections, escaping every interpolated value | `test/markdown.bats`, `docs/markdown.md`, `docs/spec/markdown.md` |
| `metrics.sh` | Timing, counters, and Prometheus text export, plus the retry/HTTP/error instrumentation | `test/metrics.bats`, `docs/metrics.md`, `docs/spec/metrics.md` |
| `network.sh` | Curl wrappers, retries, JSON requests, and HTTP metadata | `test/network.bats`, `docs/network.md`, `docs/spec/network.md` |
| `notification.sh` | Webhook notifications and JSON payloads | `test/notification.bats`, `docs/notification.md`, `docs/spec/notification.md` |
| `os.sh` | OS, architecture, distribution, and host facts: name, user, processors, terminal size, root/container/WSL/CI detection | `test/os.bats`, `docs/os.md`, `docs/spec/os.md` |
| `privilege.sh` | Acquiring an escalation once, holding its ticket for the run, shielding children from prompting, and tearing it all down | `test/privilege.bats`, `docs/privilege.md`, `docs/spec/privilege.md` |
| `process.sh` | Traps, cleanup, dry-run, and process lifecycle | `test/process.bats`, `docs/process.md`, `docs/spec/process.md` |
| `parallel.sh` | Bounded worker pool with ordered output and per-job exit codes | `test/parallel.bats`, `docs/parallel.md`, `docs/spec/parallel.md` |
| `pkg.sh` | Package manager detection and guarded dependency installation | `test/pkg.bats`, `docs/pkg.md`, `docs/spec/pkg.md` |
| `queue.sh` | Durable filesystem job queue: locked atomic claim, claimed-not-consumed jobs, retry budgets, and dead letters | `test/queue.bats`, `docs/queue.md`, `docs/spec/queue.md` |
| `release.sh` | Version bumping from commits, changelog generation, per-platform packaging, checksums, and signing | `test/release.bats`, `docs/release.md`, `docs/spec/release.md` |
| `safety.sh` | Guards for destructive operations: removal, overwrite, extraction, and system changes | `test/safety.bats`, `docs/safety.md`, `docs/spec/safety.md` |
| `secret.sh` | Read, mask, and store secrets safely | `test/secret.bats`, `docs/secret.md`, `docs/spec/secret.md` |
| `semver.sh` | Semantic version parsing, comparison, ranges, ordering, and validation | `test/semver.bats`, `docs/semver.md`, `docs/spec/semver.md` |
| `string.sh` | Case conversion, matching, splitting, trimming, and predicates | `test/string.bats`, `docs/string.md`, `docs/spec/string.md` |
| `table.sh` | Plain-text, boxed and Markdown table rendering, from delimited rows, parsed CSV, or JSON records | `test/table.bats`, `docs/table.md`, `docs/spec/table.md` |
| `text.sh` | Multiline text processing, indentation, wrapping, and formatting | `test/text.bats`, `docs/text.md`, `docs/spec/text.md` |
| `tui.sh` | Interactive widgets for a running script: spinners, progress bars, arrow-key single and multi select menus, and confirmations, each with a rendering for when there is no terminal | `test/tui.bats`, `docs/tui.md`, `docs/spec/tui.md` |
| `schedule.sh` | Fixed-cadence loops, burst debounce, once-per-period markers that outlive the process, and a cron due-predicate | `test/schedule.bats`, `docs/schedule.md`, `docs/spec/schedule.md` |
| `screen.sh` | Full-screen applications: alternate screen and raw mode, a constraint layout solver, a widget set, Unicode-correct column measurement, and an event loop over keys, mouse and resize | `test/screen.bats`, `docs/screen.md`, `docs/spec/screen.md` |
| `testing.sh` | Extended assertions, CLI snapshots, env/command/HTTP mocks, and self-cleaning fixtures | `test/testing.bats`, `docs/testing.md`, `docs/spec/testing.md` |
| `validate.sh` | One validator for the library: named value types (`email`, `port`, `ipv4`, `semver`, existing paths), declarative rules, and a registration point for types of your own | `test/validate.bats`, `docs/validate.md`, `docs/spec/validate.md` |

### Module registry

`init.sh` owns the registry and loads modules according to their dependencies.
Sourcing it with no argument loads the core modules only; `--modules` or
`DYBATPHO_MODULES` names anything else, `--modules all` asks for the whole
library, and every module set is widened at run time by `dybatpho::load`.
Because the default is narrow, a script that uses an optional module has to say
so: every `example/*.sh` declares its own module set, and `test/test_helper.bash`
asks for `all` on behalf of the module tests. Do not source a module in isolation when it uses
helpers from another module unless the source header documents the dependency
and isolated tests provide the required setup.

`__dybatpho_source_module` derives a module's file from its name, so
`src/<name>.sh` is the only naming rule: a file whose basename differs from the
registered name cannot be loaded, and `init.sh` needs no per-module entry for it.

A new module in `src/` is not reachable until it is registered in `init.sh`:

1. Add the name to `DYBATPHO_OPTIONAL_MODULES`. `DYBATPHO_CORE_MODULES` is
   reserved for the modules the rest of the library calls unconditionally.
   Registering the name is what makes the module loadable; leaving it out means
   `dybatpho::load <name>` reports it as unknown even though the file exists.
2. Add an entry to `__dybatpho_module_deps` for every **optional** module it
   calls; core modules are implicit. Cycles are allowed because calls resolve at
   run time, but each edge must reflect a real call. A missing edge does not
   fail at load time — it fails later, when a function from the unloaded module
   turns out to be undefined.
3. Extend `test/init.bats` when the module adds a dependency edge worth pinning.
   The suite already fails when a registered module has no file under `src/`,
   and when the registry and `src/` drift apart.
4. Give the module's example an explicit `--modules` line, and add the module to
   any other script that needs it. Nothing loads implicitly any more.

The registry and `src/` must list the same modules. The check is:

```bash
diff <(bash -c '. ./init.sh; dybatpho::module_list all' | sort) \
  <(ls src/*.sh | xargs -n1 basename | sed 's/\.sh$//' | sort)
```

It must print nothing. Any output is a module that exists but cannot be loaded,
or a registered name with no file behind it.

Verify the dependency table against the real call graph rather than by eye.
**Match internal helpers too**: `table.sh` reaches `text.sh` only through
`__dybatpho_text_read_lines`, and an edge found by reading `dybatpho::` calls
alone would miss it.

```bash
declare -A OWNER
for s in src/*.sh; do
  m="$(basename "${s}" .sh)"
  while read -r fn; do OWNER["${fn}"]="${m}"; done < <(
    sed -n 's/^function \([A-Za-z_][A-Za-z_0-9:]*\).*/\1/p' "${s}")
done
CORE=" string os logging helpers process file secret "
for s in src/*.sh; do
  m="$(basename "${s}" .sh)"; opt=""
  for fn in $(grep -oE '\b(dybatpho::[a-z_0-9]+|__[a-z_0-9]+)' "${s}" | sort -u); do
    o="${OWNER[${fn}]-}"
    [[ -n "${o}" && "${o}" != "${m}" && "${CORE}" != *" ${o} "* ]] || continue
    [[ " ${opt} " == *" ${o} "* ]] || opt="${opt} ${o}"
  done
  [[ -n "${opt}" ]] && printf '%-14s -> %s\n' "${m}" "${opt# }"
done
```

Every line it prints must appear in `__dybatpho_module_deps`, **except a call
guarded by `declare -F`**. Such a call is an optional hook, not a dependency: it
does nothing unless the other module happens to be loaded, so recording it as an
edge would drag that module in and, for a core module, create a forbidden
dependency on an optional one. Today this applies to the `metrics` hooks in
`helpers`, `logging`, and `network`, and to the `secret` masking hook in
`logging`, which is why the snippet reports `helpers -> metrics` while
`__dybatpho_module_deps` says nothing about it.

The `i18n` hooks work the same way and are why the snippet also reports
`logging -> i18n`: `logging` routes its diagnostics, its banners, and the help
and parser errors `cli` asks it to render through
`dybatpho::i18n_library_message`, `dybatpho::i18n_library_text`, and
`dybatpho::i18n_library_plural`, all behind a guard on
`__dybatpho_i18n_lookup`. `logging` is a core module, so recording that edge
would make a core module depend on an optional one. `cli` reaches the same hooks
through `__dybatpho_log_text` rather than naming `i18n` itself, which is
deliberate: it keeps a second module out of the scan and leaves one place where
the guard has to be right.

Use the same `declare -F` guard for any future hook of this kind.

**The guard must name an internal `__dybatpho_` helper of the other module, never
a public `dybatpho::` function.** Public functions are exported and a child shell
inherits them without the internal helpers they call, so a guard on a public name
takes the active branch in a child that never loaded the module and then fails on
the first internal call. That is why the metrics hooks test
`declare -F __dybatpho_metrics_key` and the masking hook tests
`declare -F __dybatpho_secret_mask_var`. `test/metrics.bats` pins it with child
shells that log and retry without having loaded `metrics`. Loading each module
on its own is the behavioral version of the same check:

```bash
for m in $(bash -c '. ./init.sh; dybatpho::module_list optional'); do
  bash -c ". ./init.sh --modules ${m}" || echo "BROKEN: ${m}"
done
```

The loaded set is deliberately process-local: only `dybatpho::` functions are
exported, so a child shell that sources `init.sh` again has to source the module
files itself. Never export `DYBATPHO_LOADED_MODULES` or seed it from the
environment.

Editor support depends entirely on two bash-language-server settings, both
recorded in `.vscode/settings.json`. `init.sh` resolves module paths at run time
and carries `# shellcheck source=/dev/null`, so no tool can follow a module from
it; symbol navigation comes from indexing the workspace, not from sourcing:

| Setting | Why |
| --- | --- |
| `bashIde.globPattern` = `**/*@(.sh\|.inc\|.bash\|.command)` | Several clients, including nvim-lspconfig, ship `*@(...)`, which matches the workspace root only, leaving everything under `src/` unindexed. |
| `bashIde.includeAllWorkspaceSymbols` = `true` | Modules do not source one another, and bash-language-server follows neither a computed path nor the `. "${SCRIPTDIR}/../init.sh"` form the examples use. |

With either one at its default, no `dybatpho::` function resolves anywhere in the
repository — including inside `init.sh` itself: go-to-definition fails and
completion offers only the functions defined in the open file.

VS Code reads `.vscode/settings.json` natively. Neovim needs a plugin that feeds
project files into the LSP configuration; this repository is set up for
[codesettings.nvim](https://github.com/mrjones2014/codesettings.nvim), which
reads `.vscode/settings.json`, `codesettings.json`, or `lspsettings.json` and
merges them into the server config. Any other editor has to set the same two
values itself. Nothing in the repository depends on them at run time: they only
affect editor navigation.

### Principles by module group

- **Data primitives** (`array`, `string`, `text`, `table`): keep functions
  predictable and free of unexpected file writes or logging.
- **Validation primitive** (`validate`): the library's checks live here and
  nowhere else, so a module that needs one calls it rather than writing a
  regular expression of its own. It may depend on the core modules only —
  `config` and `cli` load it unconditionally, and a heavier edge would reach
  every script that parses an option. A rule it shares with a richer parser
  elsewhere, such as `network`'s addresses or `semver`'s versions, is pinned
  against that parser by a test rather than trusted to stay in step.
- **System primitives** (`date`, `file`, `os`, `process`, `helpers`): prioritize
  GNU/BSD/BusyBox portability and return clear errors for invalid input. CI
  checks this rather than trusting it: the `portable` job runs the suite on
  macOS and the `busybox` job runs it on Alpine with no `coreutils`. Detect the
  platform by asking for a flag only one of them accepts, not by matching a
  name — `date --version` failing does not make a system BSD, and assuming it
  did left `date` broken end to end on BusyBox.
- **Dependency modules** (`pkg`): detect before acting, resolve package names
  per manager rather than assuming one distribution, and never change system
  state without `--force`/`DYBATPHO_FORCE` or an answered confirmation; honor
  `DRY_RUN`.
- **Security primitives** (`secret`, `safety`): never log or export secret
  values, keep the masking registry process-local, and validate file
  permissions before use. Guarded operations must validate the target path
  first, require `--force` or a confirmation before acting, and honor `DRY_RUN`.
- **Integration modules** (`git`, `network`, `notification`, `archive`, `config`,
  `json`): validate dependencies, quote paths/URLs/payloads, and do not hide
  external command failures.
- **Presentation modules** (`logging`, `cli`): reserve stdout for pipeable or
  capturable data and stderr for diagnostics; preserve text output when adding
  machine-readable output.
- **Localization module** (`i18n`): never derive user-visible text from the
  host's locale data — `date` answers in English when the requested locale was
  never generated, and `printf '%f'` follows `LC_NUMERIC` — so names and
  patterns come from the module's own tables and fractional values are built
  from digit strings. A missing translation degrades to the key rather than
  stopping a script, and the hooks that translate the library's own output stay
  inert unless they are explicitly turned on. Which hook a piece of text takes
  follows from whether it carries a value: a diagnostic that does not, such as
  `curl is not installed`, is its own message id, while text that does — a help
  heading, `Unrecognized option: --colr`, a rejected argument count — is named by
  a stable `cli.*` or `logging.*` key, with the English the call site already
  built kept as the fallback. Text that counts something goes through the plural
  hook, so the target language picks the form rather than the English test for
  one.
- **Observability module** (`metrics`): recording must never change what a
  script does, so a timing helper returns the command's exit code unchanged and
  the hooks in `helpers`, `logging`, and `network` stay inert unless the module
  is loaded. Validate before recording, and never inside a command substitution,
  where a rejection cannot reach the caller.
- **Coordination modules** (`lock`, `parallel`): keep operations atomic and
  portable without `flock`, always report the holder on failure, and never leave
  a lock behind on the failure path. A pool must bound concurrency by what the
  caller asked for, keep each job's output and exit code separate, and leave no
  job running once the shell is interrupted.
- **Testing module** (`testing`): assertions must report and return rather than
  terminate, mocks must restore the prior state, and fixtures must clean
  themselves up; changes here must be checked against the other module tests,
  not only `test/testing.bats`.

## Changelog requirements

**Every change a consumer could notice MUST land in `CHANGELOG.md` under
`## [Unreleased]` in the same change. A change that adds, alters, or removes
public behavior without its changelog entry is incomplete and must not be
reported as done.** This is not conditional on the size of the change, and it is
never deferred to release time.

An entry is required for:

- a new module, public function, option, or CLI attribute;
- a changed contract: renamed or removed function, new required argument,
  different default, different output, different exit code;
- a fixed bug that reached a consumer;
- a new or tightened security guard, or any change to what `safety`, `secret`,
  or a destructive operation refuses.

No entry is required for changes invisible from outside the repository: tests,
examples, specs, generated documentation, refactors that keep every contract,
and fixes to work that is itself still unreleased — those never reached a
consumer, so amend the original `## [Unreleased]` entry instead of adding a
"fixed" one beside it.

Write entries the way the existing ones are written:

- Keep a Changelog sections only — `### Added`, `### Changed`, `### Deprecated`,
  `### Removed`, `### Fixed`, `### Security` — in that order, created on demand.
- Lead with the module or function in bold, then what a consumer can now do,
  in prose rather than a commit subject.
- Name the public functions involved so the entry is searchable.
- Mark a contract change **BREAKING** and show the migration: the old call and
  the new one.
- Do not reference commit hashes, branch names, or internal helpers.

Confirm the entry exists before finishing:

```bash
git diff --stat HEAD -- CHANGELOG.md
```

It must show `CHANGELOG.md` whenever the same diff touches `src/` in a way that
changes public behavior.

## Releasing

`scripts/release.sh` is the only supported way to cut a release, because the
tag, `VERSION`, `CHANGELOG.md`, and `docs/` have to agree and doing that by hand
is where they drift apart. It stamps the version, promotes `## [Unreleased]` to
`## [<version>] - <date>` with a fresh empty `Unreleased` above it, rewrites the
comparison links, regenerates `docs/`, commits `chore(release): v<version>`, tags
it annotated with the changelog entry, builds the all-modules bundle and its
checksum file, pushes, and creates the GitHub release with the same entry as the
release notes.

```bash
scripts/release.sh --dry-run   # every check and computation, no writes
scripts/release.sh             # version derived from the commits
scripts/release.sh --version 3.0.0
```

The version comes from the commits through `dybatpho::release_next_version`,
with one override: an `Unreleased` section that marks a change **BREAKING**
forces a major release even when no commit subject carried `!` or a
`BREAKING CHANGE:` footer. The release notes are always the handwritten
changelog entry, never a generated commit list — which is the other reason the
changelog rule above is not negotiable: an entry missing at release time is an
entry missing from the published notes.

## Bash conventions

- Use Bash 4.3 or newer and always source `init.sh`. That floor is not
  negotiable: modules across the library return values through nameref
  parameters (`local -n`), and the worker pool waits with `wait -n`, both of
  which arrived in 4.3.
- Keep compatibility with strict mode: `set -euo pipefail`.
- Use two-space indentation, LF line endings, and a final newline.
- Put public functions under the `dybatpho::` namespace.
- Name every internal function `__dybatpho_<module>_<action>` (for example
  `__dybatpho_log_write_file`). The `__dybatpho_` prefix is mandatory — a bare
  `__` or `_` prefix risks colliding with helpers defined by the calling script.
  Nested helpers declared inside a function follow the same rule.
- Tag every internal function's comment block with `# @internal`, so the
  generated `docs/` leave it out and document the public API only.
- Use `printf` instead of `echo` when output must be stable or contains user data.
- Quote variables that may contain whitespace or special characters.
- Do not silently swallow errors; return clear failures following repository
  conventions.
- Never validate inside a command substitution. `dybatpho::die` only ends the
  subshell that `$(...)` creates, so the caller carries on with an empty value
  and reports success. A helper that validates must return its result through a
  nameref parameter instead, the way `dybatpho::create_temp` does. This has
  already caught `metrics`, `parallel`, and `semver`; the symptom is a function
  that prints a fatal error and still exits zero.
- Validate and quote every option or variable inserted into generated shell code.

## CLI change workflow

### 1. Update the CLI spec

Define commands in shell functions using the `dybatpho::opts::*` DSL:

```bash
_spec_root() {
  dybatpho::opts::setup "Tool description" ROOT_ARGS action:"_run_root"
  dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
  dybatpho::opts::param "API token" TOKEN --token env:API_TOKEN required:true
  dybatpho::opts::param "Component" COMPONENT --component \
    choices:api,worker,frontend multiple:true prompt:"Choose components"
  dybatpho::opts::cmd deploy _spec_deploy
}
```

Common attributes:

| Attribute | Meaning |
| --- | --- |
| `alias:` / `aliases:` | Alias for an option or command |
| `required:true` | Require the option to be supplied |
| `env:NAME` | Use an environment variable as the initial value |
| `prompt:"..."` | Prompt for a missing value |
| `choices:a,b` | Restrict values to a choice list |
| `multiple:true` | Accumulate values; prompts support `1,3` and `1-3` |
| `persistent:true` | Inherit an option in subcommands |
| `hidden:true` | Hide the item from public help/artifacts |
| `deprecated:"..."` | Warn on use and annotate help |
| `args:<rule>` | Validate positional arguments |

Command-line values must take precedence over `env:NAME`. Prompts run only when
the destination variable is still empty after initialization and parsing.

### 2. Generate all output from the same spec

Use the same function for every artifact:

```bash
dybatpho::generate_from_spec _spec_root "$@"
dybatpho::generate_help _spec_root
dybatpho::generate_completion _spec_root bash mytool
dybatpho::generate_completion _spec_root zsh mytool
dybatpho::generate_completion _spec_root fish mytool
dybatpho::generate_schema _spec_root mytool
dybatpho::generate_man _spec_root mytool
```

Do not maintain separate option or subcommand lists for completions, schema, or
man pages. Metadata must flow through the same DSL to prevent drift between
runtime behavior and documentation.

When checking subcommand artifacts, verify root and child options, aliases,
environment/choice/prompt/multiple/required metadata, hidden/deprecated behavior,
and that a man page contains one `.TH` with appropriate child sections.

### 3. Keep actions and lifecycle explicit

- `setup` contains the description, positional rule, and lifecycle hooks.
- `prerun` runs after validation and before the action.
- `action` contains the main logic.
- `postrun` runs after the action when the action does not exit the process.
- Successful actions should intentionally use `return 0` or `exit 0`.
- Use display options (`disp`) for `--help`, `--version`, `--schema`, `--man`,
  and other actions that do not take a value.

## Test conventions

### Use `run_traced`, not `run`

`run_traced` from `test/test_helper.bash` is the default way to invoke the code
under test. It takes the same flags as `run` — `!`, `-N`, `--separate-stderr` —
so the two are interchangeable at the call site, and the assertions that read
`status`, `output`, `lines`, `stderr` and `stderr_lines` are unchanged.

The reason is coverage, and it is not a small one. kcov instruments Bash through
a `DEBUG` trap, and `run` clears that trap (`trap - ERR DEBUG`) before invoking
the command. Every line a `run` executes is therefore recorded as never having
run. Because the suite reaches for `run` precisely where a command has to fail,
whole error paths were reported as untested while being tested all along. The
same assertion written with `run_traced` records the lines it executes.

`run` stays correct for one case: a command that ends the shell. `dybatpho::die`
calls `exit`, and `run_traced` has no subshell to absorb it, so the test would
end there. Those call sites keep `run`, and the line they exercise carries a
`# kcov(skip)` saying which test covers it — the line is tested, the instrument
simply cannot observe it.

The same blind spot applies to a `case` arm with no command in it (`*) ;;`):
there is nothing for the trap to fire on, so mark those `# kcov(skip)` too.

kcov reads the lines it records from Bash's `xtrace`, and one shape of trace
ends the recording for the rest of the test process: a traced command that
expands a value holding both a line break and a single quote. Bash prints such
a value as `$'...\'...'`, kcov's parser takes the `\'` for the closing quote,
and every later trace line is swallowed as the tail of an unterminated string.
The symptom is a test whose later calls show as never run. Keep such a value
out of a command's arguments and out of an assignment in the code under test
and in the test itself: write it through a here-document or a file instead,
which the trace does not echo. `dybatpho::mock_http` does this for its `curl`
script. `run_traced` itself is not affected, `--separate-stderr` included: its
captures were measured and keep recording.

### Coverage is part of the change

A change is not finished while the lines it adds are unmeasured. Run:

```bash
mise run coverage
```

and confirm, in `coverage/bats/cobertura.xml`:

- every line the change adds or rewrites is covered, or carries a
  `# kcov(skip)` naming the test that exercises it and the reason kcov cannot
  see it;
- the overall figure has not fallen.

A line that is genuinely unreachable does not belong in the library at all;
delete it rather than excluding it. `# kcov(skip)` is for code that a test does
run and the instrument cannot see, never for code no test reaches.

## Tests required for CLI changes

Add behavior-focused tests to `test/cli.bats`. Cover:

- parser, automatic/custom help, and subcommand dispatch;
- prompt input, defaults, and EOF;
- valid and invalid choices;
- `multiple:true` with names, commas, and ranges such as `1-3`;
- environment fallback and CLI precedence;
- the full precedence chain for a bound option: flag > `env:` > `config:` > `init:`;
- suggestions for a mistyped switch and a mistyped command, and silence when nothing is close;
- `negatable:true` generating `--no-`, and `count:true` accumulating `-v`, `-vv`, and `-v -v`;
- positional arguments declared with `dybatpho::opts::arg`, the usage line and `Arguments` section they produce, and the count rule they derive;
- Bash, Zsh, and Fish completions, plus cache reuse and cache bypass;
- valid JSON schema and nested metadata;
- root/child man page output, aliases, and hidden options.

Quick checks:

```bash
test/lib/core/bin/bats --print-output-on-failure test/cli.bats
bash -n src/cli.sh
bash -n example/cli_ux.sh
git diff --check
```

Run the whole suite for broad changes, and the coverage workflow before
touching anything CI reports on:

```bash
mise run test
mise run coverage
```

## Example reference

`example/cli_ux.sh` is the reference example for advanced CLI UX:

```bash
bash example/cli_ux.sh --help
bash example/cli_ux.sh completion --shell bash
bash example/cli_ux.sh schema
bash example/cli_ux.sh man
bash example/cli_ux.sh deploy --help
bash example/cli_ux.sh deploy --component api api
bash example/cli_ux.sh depoy   # suggests 'deploy'
```

When adding CLI behavior, update these together:

1. `src/cli.sh` and embedded API/usage comments;
2. `test/cli.bats`;
3. `example/` when the behavior is useful to demonstrate;
4. `docs/cli.md`;
5. `docs/spec/cli.md` when the contract, acceptance scenario, or requirement changes.

## Workflow for other module changes

1. Identify the module's public API, side effects, dependencies, and portable
   behavior.
2. Find its tests in `test/<module>.bats`; extend tests near the changed behavior.
3. Add API comments for new public functions so `scripts/docs.sh` can generate
   the reference documentation.
4. Create or update `docs/spec/<module>.md`. This step is mandatory for any
   contract or capability change, and for every new module; do not defer it.
5. Add or update the module's complete example in `example/`; do not defer
   examples for public behavior.
6. Run `bash -n` on the source, the module test, and tests for affected
   dependencies.

Keep changes composable: functions should work in command substitution,
pipelines, and conditionals without output outside their documented contract.
Functions with side effects must document them and propagate errors according
to the module convention.

## Checks by change type

| Change | Minimum checks |
| --- | --- |
| String/array/text/table | Empty input, whitespace, special characters, and module tests |
| Path/file/archive | `BATS_TEST_TMPDIR`, paths with spaces, cleanup, and permission errors |
| Date/OS/network | GNU/BSD/BusyBox fallback or the relevant command mock. Run it for real before claiming it: `docker run --rm -v "$PWD:/src:ro" alpine:3.22.1` with `bash git gawk jq` and no `coreutils` is the shape the `busybox` CI job uses |
| Git/process/config | Temporary repository/config, failure paths, traps, and cleanup |
| Logging/CLI | Separate stdout/stderr, filtering, strict mode, and machine-readable output |
| JSON/YAML/notification | Escaping, malformed input, and unavailable dependencies |
| Locking/coordination | Atomic acquire, stale reclaim, release on failure paths, and `DYBATPHO_LOCK_DIR` isolation in tests |
| Destructive guards (`safety`) | Protected paths, `DYBATPHO_SAFE_ROOTS` confinement, declined and forced paths, `DRY_RUN`, short options, and `--` end-of-options |
| Testing helpers | Passing and failing direction of every assertion, mock restore, snapshot create/match/diff, and fixture cleanup |
| New module | `init.sh` registry entry and dependency edges, `docs/spec/<module>.md`, `docs/spec/README.md` entries, `test/<module>.bats`, and `example/<module>_ops.sh` |
| Bootstrap/module loading | `test/init.bats`, a fresh shell per assertion, dependency order, cycle termination, and unknown-module failure. Spawn child shells from a script **file**, never `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which the kcov hook expands on every command and `set -u` then turns into a failure that only appears under `scripts/test.sh` |
| External tool used by a module | A declaration in `DYBATPHO_DOCTOR_REQUIRED` or `DYBATPHO_DOCTOR_OPTIONAL` in `src/doctor.sh`, on the module that runs the command, plus a case in `test/doctor.bats` |
| Bootstrap function or generated artifact | `test/init.bats` or `test/bundle.bats`, and a regenerated bundle check: `scripts/bundle.sh --modules all -o /tmp/bundle.sh` |
| Documentation/spec | Correct links/references, `git diff --check`, and `scripts/lint.sh --stage doc` after regenerating |
| New public function | `test/conventions.bats` — it must appear in `docs/<module>.md` and be named directly in `test/<module>.bats` |
| New or changed example | `test/examples.bats` — it must run non-interactively, offline, and leave the working tree untouched |
| Any shell script | `scripts/lint.sh --stage shell` — `dyshellint` (the style guide rules, ShellCheck and shfmt) and `bash -n` over every tracked script |
| `CHANGELOG.md` | `scripts/lint.sh --stage changelog` — Keep a Changelog headings, dates, and well-formed link reference URLs |
| Any public behavior | `CHANGELOG.md` entry under `## [Unreleased]`, in the same change |
| Any new or rewritten line of a module | `mise run coverage` — the line is covered, or carries a `# kcov(skip)` naming the test that exercises it; the overall figure has not fallen. Invoke the code with `run_traced`, since `run` clears the trap kcov instruments through and hides every line it executes |

## Completion checklist

1. Inspect the worktree first and preserve existing changes.
2. Read related source, tests, documentation, and specification.
3. Make a focused, backward-compatible change unless the contract requires otherwise.
4. Add regression tests for new or fixed behavior, invoking the code with
   `run_traced` so the lines they exercise are counted.
5. Add or update a complete example for every changed public module.
6. Add or update `docs/spec/<module>.md` for every changed public module, and
   confirm the missing-spec check above prints nothing.
7. **Mandatory** — add an entry under `## [Unreleased]` in `CHANGELOG.md` for
   anything a consumer would notice, following the Changelog requirements
   above, and confirm `git diff --stat HEAD -- CHANGELOG.md` shows the file.
   A public-behavior change without its entry is not done.
8. Run targeted tests, `scripts/lint.sh`, and `git diff --check`. `scripts/lint.sh`
   covers `dyshellint`, `bash -n`, the changelog format, documentation drift and
   the bundle; `test/examples.bats` covers the examples.
9. Run `mise run coverage` for a change that touches a module, and confirm the
   lines it added are covered and the overall figure has not fallen.
10. Review the final diff and remove temporary artifacts.
