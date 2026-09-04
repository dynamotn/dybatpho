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
. dybatpho/init.sh
dybatpho::register_common_handlers   # strict mode, error trap, signal cleanup

dybatpho::git_is_clean "." || dybatpho::die "Commit your changes first"

next=$(dybatpho::semver_bump "$(git describe --tags --abbrev=0)" minor)
dybatpho::info "Preparing release v${next}"

dybatpho::git_commits_between "." "v1.0.0" HEAD | while read -r sha; do
  dybatpho::print "- $(dybatpho::git_commit_subject "." "${sha}")"
done

dybatpho::success "Release notes ready"
```

No dependency manager, no runtime, no build step — just Bash ≥ 4 and the files in this repo.

## 🚀 Why dybatpho?

- **Batteries included** — 19 modules covering the things every script ends up rewriting: logs, arguments, retries, temp files, traps.
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
# Loads every module and enables strict mode
. < path-to-dybatpho > /init.sh
dybatpho::register_err_handler
dybatpho::info "Greetings from dybatpho!"
```

> Requires **Bash ≥ 4**. `init.sh` must be *sourced*, not executed.
> See the [example scripts](example/) — one per module — or real-world usage in
> [my dotfiles](https://github.com/dynamotn/dotfiles).

## 📚 Modules

### 🧱 Core scripting

| Module                            | What you get                                                       |
| --------------------------------- | ------------------------------------------------------------------ |
| [helpers.sh](doc/helpers.md)      | Argument expectation, dry-run, retries and other everyday patterns  |
| [logging.sh](doc/logging.md)      | Levelled logs, boxed output, structured JSON logging                |
| [process.sh](doc/process.md)      | Process management, traps, signal-safe cleanup                      |

### 🔤 Data & text

| Module                        | What you get                                       |
| ----------------------------- | -------------------------------------------------- |
| [array.sh](doc/array.md)      | Array manipulation                                  |
| [string.sh](doc/string.md)    | String operations                                   |
| [text.sh](doc/text.md)        | Multi-line text blocks and formatting               |
| [json.sh](doc/json.md)        | JSON and YAML reading/writing                       |
| [table.sh](doc/table.md)      | Aligned plain-text and Markdown tables              |
| [date.sh](doc/date.md)        | Dates, timestamps, day arithmetic — GNU and BSD     |

### 🖥️ CLI building

| Module               | What you get                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------ |
| [cli.sh](doc/cli.md) | Declarative option parser, prompts for missing values, env fallbacks, automatic `--help`, and generated JSON schema / shell completion / man pages |

### 📁 Files & system

| Module                          | What you get                                     |
| ------------------------------- | ------------------------------------------------ |
| [file.sh](doc/file.md)          | File handling, temp files, safe writes            |
| [archive.sh](doc/archive.md)    | Create, extract and list archives                 |
| [os.sh](doc/os.md)              | Platform/distro detection, package managers       |

### 🌐 Network & notifications

| Module                                    | What you get                                                    |
| ----------------------------------------- | ---------------------------------------------------------------- |
| [network.sh](doc/network.md)              | `curl` wrapper with retry, dry-run and header handling            |
| [notification.sh](doc/notification.md)    | Slack, Telegram, Teams, Google Chat, Discord, generic webhooks     |

### 🔐 Configuration & secrets

| Module                          | What you get                                                     |
| ------------------------------- | ----------------------------------------------------------------- |
| [config.sh](doc/config.md)      | Config files + env vars with precedence and schema validation      |
| [secret.sh](doc/secret.md)      | Read secrets safely, mask them in output, shred and wipe them      |

### 🛠 Dev workflow

| Module                        | What you get                                            |
| ----------------------------- | -------------------------------------------------------- |
| [git.sh](doc/git.md)          | Repo metadata, branches, tags, commits, remotes           |
| [semver.sh](doc/semver.md)    | Parse, validate, compare and bump semantic versions       |

## 🗂 Directory Structure

```
.
├── doc/            # Module documentation
│   ├── *.md        # Usage guides & reference for each module
│   └── spec/       # Module specifications and design docs
├── example/        # Example scripts for users
├── scripts/        # Helper scripts (test, doc generation, etc.)
├── src/            # Source code of modules
├── test/           # Unit tests
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
