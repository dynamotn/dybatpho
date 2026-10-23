# dybatpho

![Bash Script](https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)
[![Coverage Status](https://coveralls.io/repos/github/dynamotn/dybatpho/badge.svg?branch=main)](https://coveralls.io/github/dynamotn/dybatpho?branch=main)
[![CI](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml/badge.svg)](https://github.com/dynamotn/dybatpho/actions/workflows/ci.yaml)
[![Latest release](https://img.shields.io/github/release/dynamotn/dybatpho.svg)](https://github.com/dynamotn/dybatpho/releases/latest)

> **dybatpho** – The standard library your Bash scripts never had.
> Logging, CLI parsing, config, secrets, JSON, HTTP, Git and more — in one `source` line.

---

## ✨ From 200 lines of boilerplate to this

```sh
. dybatpho/init.sh --modules release # git, semver and archive come with it
dybatpho::register_common_handlers   # error trap and signal cleanup

dybatpho::git_is_clean "." || dybatpho::die "Commit your changes first"

previous=$(dybatpho::git_latest_tag "." "v*") || previous=""
next=$(dybatpho::release_next_version "." "${previous}") \
  || dybatpho::die "Nothing since ${previous:-the first commit} calls for a release"

dybatpho::info "Preparing release v${next}"
dybatpho::release_changelog "." "${previous}" HEAD "${next}" > release-notes.md

dybatpho::success "Release notes for v${next} are ready"
```

No dependency manager, no runtime, no build step — just Bash ≥ 4.3 and the files in this repo.

## 🚀 Why dybatpho?

- **Batteries included** — modules covering the things every script ends up rewriting: logs, arguments, retries, temp files, traps — and now talking to language models.
- **Load what you need** — the core modules by default, anything else by name, with dependencies resolved for you.
- **Safe by default** — `init.sh` turns on strict mode (`set -euo pipefail`, `inherit_errexit`), and error handlers, signal cleanup and secret masking are one call away. It leaves your globbing alone, exports nothing to child processes unless asked, and never `exit`s the shell that sources it; `--no-strict` keeps your shell options exactly as they were.
- **Portable** — works on GNU/Linux and macOS/BSD, with the flag differences handled for you.
- **Tested** — full unit-test suite with coverage tracking on every commit.
- **Drop-in** — submodule, subtree or plain clone; pin a tag and forget about it.
- **Yours to extend** — plain Bash files, no magic, easy to fork a module and adapt it.

## 📖 What does the name mean?

`dybatpho` is a portmanteau of `đi bát phố` — "to wander and explore", just like this repo helps you discover
and use handy Bash functions freely and flexibly.

## ⚡️ Quick Start

**1. Add `dybatpho` to your project** (pin the version if needed):

- **Submodule:**

  ```sh
  git submodule add --depth 1 https://github.com/dynamotn/dybatpho.git <path>
  git submodule update <path> --remote
  ```

- **Subtree:**

  ```sh
  git subtree add --prefix main --squash < path > https://github.com/dynamotn/dybatpho.git
  git subtree pull --prefix main --squash < path > https://github.com/dynamotn/dybatpho.git
  ```

- **Manual clone** (for CI/CD, etc.):

  ```sh
  git clone https://github.com/dynamotn/dybatpho.git
  ```

**2. Source it before anything else:**

```sh
# Loads the core modules and enables strict mode
. < path-to-dybatpho > /init.sh || exit 1
dybatpho::register_err_handler
dybatpho::info "Greetings from dybatpho!"
```

> Requires **Bash ≥ 4.3**. `init.sh` must be *sourced*, not executed.
> macOS ships Bash 3.2, so install a current one with `brew install bash`.
> See the [example scripts](example/) — one per module — or real-world usage in
> [my dotfiles](https://github.com/dynamotn/dotfiles).

**3. Name the modules you need:**

Sourcing `init.sh` with no argument loads only the core modules — `string`,
`os`, `logging`, `helpers`, `process`, `file`, `secret` and `array`. Everything else is asked
for by name, and dybatpho resolves the dependencies between modules for you:

```sh
. < path > /init.sh --modules git semver          # argument form
DYBATPHO_MODULES="git semver" . < path > /init.sh # environment form
. < path > /init.sh --modules all                 # the whole library
```

Every module set includes the core modules, and can be widened at any point:

```sh
dybatpho::load notification  # brings in its network dependency too
dybatpho::module_loaded json # branch on what is loaded
dybatpho::module_list all    # core + optional module names
dybatpho::module_list stable # modules whose contract holds across minor releases
```

A few modules call another one from only some of their functions —
`dybatpho::csv_to_json` needs `json`, `dybatpho::safe_extract` needs `archive`.
Those *soft dependencies* are loaded on demand the first time such a function
runs, so `--modules csv` is enough; name the other module up front when the call
sits inside `$(...)` on a hot path, since a module loaded in a subshell is gone
with it. `dybatpho::doctor` lists each module's soft dependencies.

Every module has a **stability tier**, shown in the tables below and by
`dybatpho::module_tier`:

- **stable** — the public contract holds across minor releases; a function is
  deprecated for at least one minor release before it is removed.
- **experimental** — may change in any minor release.

The core modules are stable, and a stable module never depends on an
experimental one.

An unknown module name fails the bootstrap instead of failing later with a
missing function: the `.` returns 1, which stops a script under `set -e` and
lets any other caller decide for itself. See [init.sh reference](docs/init.md) and
[example/init_modules.sh](example/init_modules.sh).

**4. Choose what changes in your shell:**

By default `init.sh` turns on `set -euo pipefail`, `extglob` and, on Bash 4.4+,
`inherit_errexit`. It does not turn on `nullglob` or `globstar`, so an
unmatched glob in your script stays literal, as Bash has it. To keep every
`set` and `shopt` option of your own, pass `--no-strict`:

```sh
. < path > /init.sh --no-strict --modules git
```

Child processes inherit nothing from the library by default. A script whose
`bash -c`, `xargs` or `find -exec bash` children call dybatpho opts in, and
each non-interactive Bash child then sources the library with the same modules,
through `BASH_ENV`, without its own options being touched:

```sh
DYBATPHO_EXPORT_FUNCTIONS=true . < path > /init.sh --modules semver
# or, at any point after sourcing:
dybatpho::export_functions
find . -name VERSION -exec bash -c 'dybatpho::semver_valid "$(cat "$1")"' _ {} \;
```

To survive a `dybatpho::die` in one step rather than end the script, run it
through `dybatpho::try out err -- command args...`.

`dybatpho::version` reports which copy of the library is loaded, and the
`doctor` module turns the module set into an environment check:

```sh
. < path > /init.sh --modules doctor json archive
dybatpho::version # 2.0.0+af745ff (release + current commit)
dybatpho::doctor  # every external tool these modules can call
dybatpho::doctor --modules git --quiet || echo "git is missing here"
```

### 🔧 External tools

The core modules need nothing beyond Bash and the POSIX tools every system
ships. An optional module calls an external program only when you reach the
function that needs it, and `dybatpho::doctor` lists them all up front. Two are
worth knowing before you start:

- **`jq`** — every JSON filter in the library runs through it, whatever else is
  installed, so `json`, and the modules built on it (`ai`, `agent`, `forge`,
  `config`, `csv`, `diff`, ...), need it. Filters are written in `jq`'s
  language, YAML included.
- **The Go `yq` v4** ([mikefarah/yq](https://github.com/mikefarah/yq)) — needed
  only to read or write YAML and TOML. The unrelated Python `yq` is refused by
  name rather than misread.

## 📦 Vendoring as one file

`scripts/bundle.sh` flattens the modules a project uses into a single
`dybatpho.bundle.sh`, which is what vendoring into another repository or baking
into a container image needs. The selection is the same `--modules` used
everywhere else, and the bundler resolves it through `init.sh` itself:

```sh
scripts/bundle.sh --modules "logging git semver" --output dist/dybatpho.sh
```

The bundle carries no dependency on a `src/` directory: copy the one file, source
it, and the bundled functions work. Inside it, `dybatpho::load` succeeds for a
bundled module and names the regeneration command for anything else. A bundle
cannot load a soft dependency on demand, so the bundler names the ones it left
out; `--with-soft-deps` carries them too.

## 🚀 Releasing

Maintainers cut a release with `scripts/release.sh`. It stamps `VERSION`,
promotes the `Unreleased` section of `CHANGELOG.md` to the new version,
regenerates `docs/`, commits, tags, builds the all-modules bundle with its
checksum file, pushes, and publishes the GitHub release with the changelog entry
as its notes:

```sh
scripts/release.sh --dry-run # every check, no writes
scripts/release.sh           # version derived from the commits
scripts/release.sh --version 3.0.0 --sign
```

## 🧭 Versioning and stability

dybatpho follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The
public API is every `dybatpho::` function, its arguments, output and exit codes,
every documented `DYBATPHO_*` variable, the `init.sh` options, and the modules a
module loads for you. Anything named `__dybatpho_*` is internal and can change
in any release.

- **Stable and experimental modules.** Each module declares a tier. A
  *stable* module follows the rules below. An *experimental* module is new or
  still finding its shape: it can change in a minor release, and its changelog
  entries say so. A module graduates to stable in a minor release, never the
  other way round.
- **Deprecation before removal.** A stable function, option or variable that is
  going away is marked deprecated first, keeps working, and warns once per run
  naming its replacement. It stays for at least one minor release before the
  next major removes it, and `### Deprecated` in the changelog lists it.
- **Breaking changes are batched.** Changes that break a stable API wait for a
  planned major release rather than leaking out one at a time. Each is marked
  **BREAKING** in the changelog with the old call and the new one, and
  [docs/MIGRATING.md](docs/MIGRATING.md) collects them per major version.
- **Bash floor.** The oldest supported Bash (4.3) is part of the contract:
  raising it is a breaking change, and CI runs the suite on 4.3, 4.4, 5.0 and
  5.1 as well as on the current release.

## 📚 Modules

### 🧱 Core scripting

| Module                            | Tier | What you get                                                       |
| --------------------------------- | --- | ------------------------------------------------------------------ |
| [helpers.sh](docs/helpers.md)      | stable | Argument expectation, dry-run, retries and other everyday patterns  |
| [logging.sh](docs/logging.md)      | stable | Levelled logs, boxed output, structured JSON logging                |
| [process.sh](docs/process.md)      | stable | Process management, traps, timeouts, background jobs, PID files     |
| [cache.sh](docs/cache.md)          | experimental | Command output cache with TTLs, stale-while-revalidate, and pruning |
| [lock.sh](docs/lock.md)            | stable | Portable file locking to serialize concurrent script runs           |
| [parallel.sh](docs/parallel.md)  | experimental | Bounded worker pool: ordered output, per-job exit codes, fail-fast |
| [queue.sh](docs/queue.md)        | experimental | Durable job queue on disk: atomic claim, retries, dead letters      |
| [schedule.sh](docs/schedule.md)  | experimental | Intervals, debounce, once-per-period markers, and a cron predicate  |

### 🔤 Data & text

| Module                        | Tier | What you get                                       |
| ----------------------------- | --- | -------------------------------------------------- |
| [array.sh](docs/array.md)      | stable | Array manipulation                                  |
| [math.sh](docs/math.md)        | stable | Exact decimal arithmetic, rounding, aggregates — no `bc`, no float drift |
| [string.sh](docs/string.md)    | stable | String operations                                   |
| [text.sh](docs/text.md)        | experimental | Multi-line text blocks and formatting               |
| [json.sh](docs/json.md)        | stable | JSON and YAML reading/writing, one `jq` filter language for both |
| [table.sh](docs/table.md)      | experimental | Aligned plain-text and Markdown tables, from CSV or JSON too |
| [markdown.sh](docs/markdown.md) | experimental | Headings, lists, links, badges and code blocks, with every value escaped |
| [csv.sh](docs/csv.md)          | experimental | Real CSV: quoted fields, embedded commas and newlines, filtering, JSON bridge |
| [diff.sh](docs/diff.md)        | experimental | Colored unified diffs, and JSON/YAML compared by key rather than by line |
| [date.sh](docs/date.md)        | stable | Dates, timestamps, day arithmetic — GNU and BSD     |
| [i18n.sh](docs/i18n.md)        | experimental | Translations, plural rules, locale-aware numbers, money, sizes and dates |

### 🖥️ CLI building

| Module               | Tier | What you get                                                                                                 |
| -------------------- | --- | ------------------------------------------------------------------------------------------------------------ |
| [cli.sh](docs/cli.md) | stable | Declarative option parser with "did you mean" suggestions, generated `--no-` switches, counting `-vv` flags, options bound to config keys, prompts for missing values, env fallbacks, automatic `--help`, and generated JSON schema / shell completion / man pages |
| [tui.sh](docs/tui.md) | experimental | Spinners, progress bars, arrow-key single and multi select menus, and confirmations — each one falling back to a numbered prompt or a log line when there is no terminal, so the same script runs unattended |
| [screen.sh](docs/screen.md) | experimental | Full-screen applications: a constraint layout solver, blocks, lists, tables, gauges, tabs, scrollbars, sparklines, bar and Braille line charts, popups, and an event loop with keys, mouse and resize |

### 📁 Files & system

| Module                          | Tier | What you get                                     |
| ------------------------------- | --- | ------------------------------------------------ |
| [file.sh](docs/file.md)          | stable | Paths, XDG dirs, temp files, atomic rewrites, idempotent lines, checksums, upward search |
| [archive.sh](docs/archive.md)    | stable | Create, extract and list archives                 |
| [backup.sh](docs/backup.md)      | experimental | Timestamped snapshots, checksum sidecars, retention pruning |
| [os.sh](docs/os.md)              | stable | Platform/distro and architecture detection        |
| [pkg.sh](docs/pkg.md)            | experimental | Detect the package manager and install dependencies, with confirmation and dry-run |
| [privilege.sh](docs/privilege.md) | experimental | Ask for sudo once, hold it for the whole run, and stop children prompting |

### 🌐 Network & notifications

| Module                                    | Tier | What you get                                                    |
| ----------------------------------------- | --- | ---------------------------------------------------------------- |
| [network.sh](docs/network.md)              | stable | `curl` wrapper with retry, rate limiting, pagination and auth     |
| [notification.sh](docs/notification.md)    | experimental | Slack, Telegram, Teams, Google Chat, Discord, generic webhooks     |

### 🔐 Configuration & secrets

| Module                          | Tier | What you get                                                     |
| ------------------------------- | --- | ----------------------------------------------------------------- |
| [validate.sh](docs/validate.md)  | stable | One validator for email, URL, IP, CIDR, semver, port, dates, paths and your own types |
| [config.sh](docs/config.md)      | stable | Config files + env vars with precedence and schema validation      |
| [secret.sh](docs/secret.md)      | stable | Read secrets safely, mask them in output, shred and wipe them      |
| [safety.sh](docs/safety.md)      | stable | Confirm-or-refuse guards for rm, overwrite, extract, system changes |

### 🤖 AI

| Module                      | Tier | What you get                                                                           |
| --------------------------- | --- | ---------------------------------------------------------------------------------------- |
| [ai.sh](docs/ai.md)          | experimental | Call Claude, OpenAI-compatible APIs, Ollama or a local CLI — conversations, JSON output, streaming, tool use, budgets |
| [agent.sh](docs/agent.md)    | experimental | Make your script agent-safe — JSON results, tool/MCP definitions generated from your CLI spec, an allowlist gate, an audit log |

### 🛠 Dev workflow

| Module                        | Tier | What you get                                            |
| ----------------------------- | --- | -------------------------------------------------------- |
| [git.sh](docs/git.md)          | stable | Repo metadata, branches, tags, commits, remotes, reachability |
| [semver.sh](docs/semver.md)    | stable | Parse, validate, compare, bump, sort and range-match semantic versions |
| [release.sh](docs/release.md)  | experimental | Version from commits, changelog, per-platform artifacts, checksums, signing |
| [forge.sh](docs/forge.md)      | experimental | Publish to GitHub or GitLab: releases, assets, and issues that comment instead of duplicating |
| [testing.sh](docs/testing.md)  | experimental | File/JSON/YAML assertions, CLI snapshots, mocks, fixtures |
| [metrics.sh](docs/metrics.md)  | experimental | Command timing, counters, retry/HTTP/error stats, Prometheus export |
| [doctor.sh](docs/doctor.md)    | experimental | Report the Bash version, the library version and every external tool the loaded modules need |

## 🗂 Directory Structure

```
.
├── docs/           # Module documentation
│   ├── *.md        # Usage guides & reference for each module
│   └── spec/       # Module specifications and design docs
├── example/        # Example scripts for users
├── scripts/        # Helper scripts (test, doc generation, bundling, releasing)
├── src/            # Source code of modules
├── test/           # Unit tests
├── CHANGELOG.md    # User-visible history
├── VERSION         # Version of this copy, reported by `dybatpho::version`
└── init.sh         # Initialization script, **must be sourced first**
```

## 💬 Contribution & Support

- Open an Issue or Pull Request if you'd like to suggest ideas, fix bugs, or contribute new modules!
- All feedback and contributions are welcome.

---

**Get started with dybatpho now to optimize your workflow and save time with your Bash scripts!**

<p align="center">
  <a href="https://github.com/dynamotn/dybatpho/stargazers">
    <img src="https://img.shields.io/github/stars/dynamotn/dybatpho?style=social" alt="Star dybatpho" />
  </a>
</p>
