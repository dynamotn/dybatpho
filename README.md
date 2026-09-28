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
dybatpho::register_common_handlers   # strict mode, error trap, signal cleanup

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
- **Safe by default** — strict mode, error handlers, signal cleanup and secret masking are wired in from `init.sh`.
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
. < path-to-dybatpho > /init.sh
dybatpho::register_err_handler
dybatpho::info "Greetings from dybatpho!"
```

> Requires **Bash ≥ 4.3**. `init.sh` must be *sourced*, not executed.
> macOS ships Bash 3.2, so install a current one with `brew install bash`.
> See the [example scripts](example/) — one per module — or real-world usage in
> [my dotfiles](https://github.com/dynamotn/dotfiles).

**3. Name the modules you need:**

Sourcing `init.sh` with no argument loads only the core modules — `string`,
`os`, `logging`, `helpers`, `process`, `file` and `secret`. Everything else is asked
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
```

An unknown module name stops the script at bootstrap instead of failing later
with a missing function. See [init.sh reference](doc/init.md) and
[example/init_modules.sh](example/init_modules.sh).

`dybatpho::version` reports which copy of the library is loaded, and the
`doctor` module turns the module set into an environment check:

```sh
. < path > /init.sh --modules doctor json archive
dybatpho::version                  # 2.0.0+af745ff (release + current commit)
dybatpho::doctor                   # every external tool these modules can call
dybatpho::doctor --modules git --quiet || echo "git is missing here"
```

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
bundled module and names the regeneration command for anything else.

## 🚀 Releasing

Maintainers cut a release with `scripts/release.sh`. It stamps `VERSION`,
promotes the `Unreleased` section of `CHANGELOG.md` to the new version,
regenerates `doc/`, commits, tags, builds the all-modules bundle with its
checksum file, pushes, and publishes the GitHub release with the changelog entry
as its notes:

```sh
scripts/release.sh --dry-run     # every check, no writes
scripts/release.sh               # version derived from the commits
scripts/release.sh --version 3.0.0 --sign
```

## 📚 Modules

### 🧱 Core scripting

| Module                            | What you get                                                       |
| --------------------------------- | ------------------------------------------------------------------ |
| [helpers.sh](doc/helpers.md)      | Argument expectation, dry-run, retries and other everyday patterns  |
| [logging.sh](doc/logging.md)      | Levelled logs, boxed output, structured JSON logging                |
| [process.sh](doc/process.md)      | Process management, traps, timeouts, background jobs, PID files     |
| [lock.sh](doc/lock.md)            | Portable file locking to serialize concurrent script runs           |
| [parallel.sh](doc/parallel.md)  | Bounded worker pool: ordered output, per-job exit codes, fail-fast |

### 🔤 Data & text

| Module                        | What you get                                       |
| ----------------------------- | -------------------------------------------------- |
| [array.sh](doc/array.md)      | Array manipulation                                  |
| [math.sh](doc/math.md)        | Exact decimal arithmetic, rounding, aggregates — no `bc`, no float drift |
| [string.sh](doc/string.md)    | String operations                                   |
| [text.sh](doc/text.md)        | Multi-line text blocks and formatting               |
| [json.sh](doc/json.md)        | JSON and YAML reading/writing                       |
| [table.sh](doc/table.md)      | Aligned plain-text and Markdown tables              |
| [date.sh](doc/date.md)        | Dates, timestamps, day arithmetic — GNU and BSD     |
| [i18n.sh](doc/i18n.md)        | Translations, plural rules, locale-aware numbers, money, sizes and dates |

### 🖥️ CLI building

| Module               | What you get                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------ |
| [cli.sh](doc/cli.md) | Declarative option parser with "did you mean" suggestions, generated `--no-` switches, counting `-vv` flags, options bound to config keys, prompts for missing values, env fallbacks, automatic `--help`, and generated JSON schema / shell completion / man pages |

### 📁 Files & system

| Module                          | What you get                                     |
| ------------------------------- | ------------------------------------------------ |
| [file.sh](doc/file.md)          | Paths, XDG dirs, temp files, atomic rewrites, idempotent lines, checksums, upward search |
| [archive.sh](doc/archive.md)    | Create, extract and list archives                 |
| [os.sh](doc/os.md)              | Platform/distro and architecture detection        |
| [pkg.sh](doc/pkg.md)            | Detect the package manager and install dependencies, with confirmation and dry-run |

### 🌐 Network & notifications

| Module                                    | What you get                                                    |
| ----------------------------------------- | ---------------------------------------------------------------- |
| [network.sh](doc/network.md)              | `curl` wrapper with retry, rate limiting, pagination and auth     |
| [notification.sh](doc/notification.md)    | Slack, Telegram, Teams, Google Chat, Discord, generic webhooks     |

### 🔐 Configuration & secrets

| Module                          | What you get                                                     |
| ------------------------------- | ----------------------------------------------------------------- |
| [validate.sh](doc/validate.md)  | One validator for email, URL, IP, CIDR, semver, port, dates, paths and your own types |
| [config.sh](doc/config.md)      | Config files + env vars with precedence and schema validation      |
| [secret.sh](doc/secret.md)      | Read secrets safely, mask them in output, shred and wipe them      |
| [safety.sh](doc/safety.md)      | Confirm-or-refuse guards for rm, overwrite, extract, system changes |

### 🤖 AI

| Module                      | What you get                                                                           |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| [ai.sh](doc/ai.md)          | Call Claude, OpenAI-compatible APIs, Ollama or a local CLI — conversations, JSON output, streaming, tool use, budgets |
| [agent.sh](doc/agent.md)    | Make your script agent-safe — JSON results, tool/MCP definitions generated from your CLI spec, an allowlist gate, an audit log |

### 🛠 Dev workflow

| Module                        | What you get                                            |
| ----------------------------- | -------------------------------------------------------- |
| [git.sh](doc/git.md)          | Repo metadata, branches, tags, commits, remotes, reachability |
| [semver.sh](doc/semver.md)    | Parse, validate, compare, bump, sort and range-match semantic versions |
| [release.sh](doc/release.md)  | Version from commits, changelog, per-platform artifacts, checksums, signing |
| [forge.sh](doc/forge.md)      | Publish to GitHub or GitLab: releases, assets, and issues that comment instead of duplicating |
| [testing.sh](doc/testing.md)  | File/JSON/YAML assertions, CLI snapshots, mocks, fixtures |
| [metrics.sh](doc/metrics.md)  | Command timing, counters, retry/HTTP/error stats, Prometheus export |
| [doctor.sh](doc/doctor.md)    | Report the Bash version, the library version and every external tool the loaded modules need |

## 🗂 Directory Structure

```
.
├── doc/            # Module documentation
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
