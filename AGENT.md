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
- `doc/` — API documentation generated from source comments, including
  `doc/init.md` for the bootstrap's own public functions.
- `doc/spec/` — Spec Kit-style feature specifications.
- `CHANGELOG.md` — user-visible history, [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
- `scripts/test.sh` — test runner; `--coverage` adds the kcov report.
- `.mise.toml` — standard tasks such as `mise run test` and `mise run doc`.

## Module scope

Every module in `src/` must have a clear responsibility and expose public
functions under the `dybatpho::` namespace. Every public module must have a
corresponding complete example in `example/` (normally
`example/<module>_ops.sh`) **and a specification in `doc/spec/<module>.md`**.
When changing a module, read its source, tests, API documentation, matching
specification, and example before editing.

### Specification requirements

**Every module in `src/` MUST have `doc/spec/<module>.md`. A change that adds a
module or public behavior without its spec is incomplete and must not be
reported as done.** This is not conditional on the size of the change.

Generate or update the spec in the same change that touches the module:

- **New module** — write `doc/spec/<module>.md` before the work is considered
  complete, and register it in both the Spec Files and Source Mapping lists of
  `doc/spec/README.md`.
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
comm -23 \
  <(ls src/*.sh | xargs -n1 basename | sed 's/\.sh$/.md/' | sort) \
  <(ls doc/spec/*.md | xargs -n1 basename | sort)
```

The command must print nothing. Any output is a missing spec that must be
written before the change is complete.

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
complete. Validate every example with `bash -n example/*.sh` and execute new or
changed examples.

| Module | Primary responsibility | Tests / documentation |
| --- | --- | --- |
| `agent.sh` | Agent detection, structured results and errors, allowlist gate, audit log, and tool/MCP definitions generated from a CLI spec | `test/agent.bats`, `doc/agent.md`, `doc/spec/agent.md` |
| `ai.sh` | Language model calls across Claude, OpenAI-compatible, Ollama, and CLI backends, with conversations, JSON output, streaming, tool use, caching, and budgets | `test/ai.bats`, `doc/ai.md`, `doc/spec/ai.md` |
| `array.sh` | Create, read, join, filter, and manipulate Bash arrays | `test/array.bats`, `doc/array.md`, `doc/spec/array.md` |
| `archive.sh` | Create, extract, and inspect archives | `test/archive.bats`, `doc/archive.md`, `doc/spec/archive.md` |
| `cli.sh` | Declarative parser, help, subcommands, completions, and CLI artifacts | `test/cli.bats`, `doc/cli.md`, `doc/spec/cli.md` |
| `config.sh` | Load dotenv, JSON/YAML configuration, precedence, typed schema validation, and configuration docs | `test/config.bats`, `doc/config.md`, `doc/spec/config.md` |
| `date.sh` | Portable date/time parsing, formatting, and calculations | `test/date.bats`, `doc/date.md`, `doc/spec/date.md` |
| `file.sh` | Path helpers, upward search, directory creation, temporary files, and atomic content rewrites, checksums, and metadata | `test/file.bats`, `doc/file.md`, `doc/spec/file.md` |
| `git.sh` | Safe repository, branch, commit, and Git operations | `test/git.bats`, `doc/git.md`, `doc/spec/git.md` |
| `helpers.sh` | Argument validation, command lookup, retry, and common helpers | `test/helpers.bats`, `doc/helpers.md`, `doc/spec/helpers.md` |
| `json.sh` | Query, validate, pretty-print, and convert JSON/YAML | `test/json.bats`, `doc/json.md`, `doc/spec/json.md` |
| `lock.sh` | Portable `mkdir`-based process locks, waiting, stale reclaim, and `with_lock` | `test/lock.bats`, `doc/lock.md`, `doc/spec/lock.md` |
| `logging.sh` | Log levels, text/JSON logging, banners, and Bash tracing | `test/logging.bats`, `doc/logging.md`, `doc/spec/logging.md` |
| `metrics.sh` | Timing, counters, and Prometheus text export, plus the retry/HTTP/error instrumentation | `test/metrics.bats`, `doc/metrics.md`, `doc/spec/metrics.md` |
| `network.sh` | Curl wrappers, retries, JSON requests, and HTTP metadata | `test/network.bats`, `doc/network.md`, `doc/spec/network.md` |
| `notification.sh` | Webhook notifications and JSON payloads | `test/notification.bats`, `doc/notification.md`, `doc/spec/notification.md` |
| `os.sh` | OS, architecture, and environment detection | `test/os.bats`, `doc/os.md`, `doc/spec/os.md` |
| `process.sh` | Traps, cleanup, dry-run, and process lifecycle | `test/process.bats`, `doc/process.md`, `doc/spec/process.md` |
| `safety.sh` | Guards for destructive operations: removal, overwrite, extraction, and system changes | `test/safety.bats`, `doc/safety.md`, `doc/spec/safety.md` |
| `secret.sh` | Read, mask, and store secrets safely | `test/secret.bats`, `doc/secret.md`, `doc/spec/secret.md` |
| `semver.sh` | Semantic version parsing, comparison, and validation | `test/semver.bats`, `doc/semver.md`, `doc/spec/semver.md` |
| `string.sh` | Case conversion, matching, splitting, trimming, and predicates | `test/string.bats`, `doc/string.md`, `doc/spec/string.md` |
| `table.sh` | Plain-text and Markdown table rendering | `test/table.bats`, `doc/table.md`, `doc/spec/table.md` |
| `text.sh` | Multiline text processing, indentation, wrapping, and formatting | `test/text.bats`, `doc/text.md`, `doc/spec/text.md` |
| `testing.sh` | Extended assertions, CLI snapshots, env/command/HTTP mocks, and self-cleaning fixtures | `test/testing.bats`, `doc/testing.md`, `doc/spec/testing.md` |

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
CORE=" string logging helpers process file secret "
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
`helpers`, `logging`, and `network`, which is why the snippet reports
`helpers -> metrics` while `__dybatpho_module_deps` says nothing about it. Use
the same `declare -F` guard for any future hook of this kind. Loading each module
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
- **System primitives** (`date`, `file`, `os`, `process`, `helpers`): prioritize
  GNU/BSD/BusyBox portability and return clear errors for invalid input.
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
- **Observability module** (`metrics`): recording must never change what a
  script does, so a timing helper returns the command's exit code unchanged and
  the hooks in `helpers`, `logging`, and `network` stay inert unless the module
  is loaded. Validate before recording, and never inside a command substitution,
  where a rejection cannot reach the caller.
- **Coordination modules** (`lock`): keep operations atomic and portable
  without `flock`, always report the holder on failure, and never leave a lock
  behind on the failure path.
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

## Bash conventions

- Use Bash 4 or newer and always source `init.sh`.
- Keep compatibility with strict mode: `set -euo pipefail`.
- Use two-space indentation, LF line endings, and a final newline.
- Put public functions under the `dybatpho::` namespace.
- Name every internal function `__dybatpho_<module>_<action>` (for example
  `__dybatpho_log_write_file`). The `__dybatpho_` prefix is mandatory — a bare
  `__` or `_` prefix risks colliding with helpers defined by the calling script.
  Nested helpers declared inside a function follow the same rule.
- Use `printf` instead of `echo` when output must be stable or contains user data.
- Quote variables that may contain whitespace or special characters.
- Do not silently swallow errors; return clear failures following repository
  conventions.
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

## Tests required for CLI changes

Add behavior-focused tests to `test/cli.bats`. Cover:

- parser, automatic/custom help, and subcommand dispatch;
- prompt input, defaults, and EOF;
- valid and invalid choices;
- `multiple:true` with names, commas, and ranges such as `1-3`;
- environment fallback and CLI precedence;
- Bash, Zsh, and Fish completions;
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
bash example/cli_ux.sh --completion bash
bash example/cli_ux.sh --schema
bash example/cli_ux.sh --man
bash example/cli_ux.sh deploy
```

When adding CLI behavior, update these together:

1. `src/cli.sh` and embedded API/usage comments;
2. `test/cli.bats`;
3. `example/` when the behavior is useful to demonstrate;
4. `doc/cli.md`;
5. `doc/spec/cli.md` when the contract, acceptance scenario, or requirement changes.

## Workflow for other module changes

1. Identify the module's public API, side effects, dependencies, and portable
   behavior.
2. Find its tests in `test/<module>.bats`; extend tests near the changed behavior.
3. Add API comments for new public functions so `scripts/doc.sh` can generate
   the reference documentation.
4. Create or update `doc/spec/<module>.md`. This step is mandatory for any
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
| Date/OS/network | GNU/BSD/BusyBox fallback or the relevant command mock |
| Git/process/config | Temporary repository/config, failure paths, traps, and cleanup |
| Logging/CLI | Separate stdout/stderr, filtering, strict mode, and machine-readable output |
| JSON/YAML/notification | Escaping, malformed input, and unavailable dependencies |
| Locking/coordination | Atomic acquire, stale reclaim, release on failure paths, and `DYBATPHO_LOCK_DIR` isolation in tests |
| Destructive guards (`safety`) | Protected paths, `DYBATPHO_SAFE_ROOTS` confinement, declined and forced paths, `DRY_RUN`, short options, and `--` end-of-options |
| Testing helpers | Passing and failing direction of every assertion, mock restore, snapshot create/match/diff, and fixture cleanup |
| New module | `init.sh` registry entry and dependency edges, `doc/spec/<module>.md`, `doc/spec/README.md` entries, `test/<module>.bats`, and `example/<module>_ops.sh` |
| Bootstrap/module loading | `test/init.bats`, a fresh shell per assertion, dependency order, cycle termination, and unknown-module failure. Spawn child shells from a script **file**, never `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which the kcov hook expands on every command and `set -u` then turns into a failure that only appears under `scripts/test.sh` |
| Documentation/spec | Correct links/references and `git diff --check` |
| Any public behavior | `CHANGELOG.md` entry under `## [Unreleased]`, in the same change |

## Completion checklist

1. Inspect the worktree first and preserve existing changes.
2. Read related source, tests, documentation, and specification.
3. Make a focused, backward-compatible change unless the contract requires otherwise.
4. Add regression tests for new or fixed behavior.
5. Add or update a complete example for every changed public module.
6. Add or update `doc/spec/<module>.md` for every changed public module, and
   confirm the missing-spec check above prints nothing.
7. **Mandatory** — add an entry under `## [Unreleased]` in `CHANGELOG.md` for
   anything a consumer would notice, following the Changelog requirements
   above, and confirm `git diff --stat HEAD -- CHANGELOG.md` shows the file.
   A public-behavior change without its entry is not done.
8. Run targeted tests, `bash -n example/*.sh`, changed examples, and
   `git diff --check`.
9. Review the final diff and remove temporary artifacts.
