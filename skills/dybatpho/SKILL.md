---
name: dybatpho
description: Use when writing or changing a Bash script that sources the dybatpho library (dybatpho/init.sh, functions named dybatpho::*), or a Bash script longer than a few lines in a project that vendors it - loading modules, declaring a CLI with dybatpho::opts::*, error handling, logging, cleanup, and finding the existing dybatpho:: function before writing a helper by hand.
---

# Writing Bash with dybatpho

[dybatpho](https://github.com/dynamotn/dybatpho) is a Bash 4.3+ library of
`dybatpho::*` functions, split into modules a script loads on demand. The one
rule that matters most: **before writing a helper, look for the
`dybatpho::` function that already does it** — argument parsing, retries,
logging, temporary files, locks, JSON, HTTP and prompts are all covered.

Where to look, shortest first:

- [references/modules.md](references/modules.md) — every module, how to load
  it, and whether it is stable.
- `llms-full.txt` at the library root — every public function's signature and
  one-line description, grouped by module. Search it by keyword before writing
  code. Online:
  <https://raw.githubusercontent.com/dynamotn/dybatpho/main/llms-full.txt>.
- `docs/<module>.md` — the full reference of one module: arguments, exit
  codes, environment, examples. Read it before calling a function for the
  first time.
- `example/<module>_*.sh` — a runnable script per module.

## Load the library

Source `init.sh` once, at the top, naming every module the script uses.
Without `--modules`, only the core modules load: `string os logging helpers
process file secret array`.

```bash
#!/usr/bin/env bash
# @file sync.sh
# @brief Sync a directory to a server
# @description Copies a directory with rsync, retrying on failure.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dybatpho/init.sh
. "${SCRIPT_DIR}/lib/dybatpho/init.sh" --modules cli network json
dybatpho::register_common_handlers
```

- Sourcing turns on strict mode (`set -euo pipefail`, `extglob`,
  `inherit_errexit`). Do not add your own `set -e` or error trap; pass
  `--no-strict` only when the caller must keep its own shell options.
- `dybatpho::load <module>...` adds a module later; `--modules all` loads
  everything (slower; prefer naming them).
- A function that is "command not found" at run time almost always belongs to
  a module that was not named in `--modules`.
- A project that cannot carry the whole tree vendors one file built by
  `scripts/bundle.sh --modules "<names>" --output <file>`, and sources that.

## Declare the command line

Never hand-roll `getopts` or a `case "$1"` loop. Declare a spec function and
let `dybatpho::generate_from_spec` build the parser. It adds `--help` on its
own; declaring it, as below, keeps dyshellint's `BSG052` quiet:

```bash
# @description Spec of the command line.
# @noargs
function _spec {
  dybatpho::opts::setup "Sync a directory to a server" ARGS action:"_main"
  dybatpho::opts::arg "Directory to sync" SOURCE
  dybatpho::opts::param "Server to sync to" HOST --host -H required:true
  dybatpho::opts::param "Retries before giving up" RETRIES --retries init:="3" \
    validate:"dybatpho::is int \$OPTARG"
  dybatpho::opts::flag "Show what would run" DRY_RUN --dry-run -n on:true off:false init:="false"
  dybatpho::opts::disp "Show help" --help -h action:"dybatpho::generate_help _spec"
}

# @description Run the sync with the parsed options.
# @noargs
function _main {
  dybatpho::is dir "${SOURCE}" || dybatpho::die "Not a directory: ${SOURCE}"
  dybatpho::info "Syncing ${SOURCE} to ${HOST}"
  dybatpho::retry "${RETRIES}" -- dybatpho::dry_run -- rsync -a "${SOURCE}/" "${HOST}:"
}

dybatpho::generate_from_spec _spec "$@"
```

- `dybatpho::opts::setup` comes first; its second argument names the array
  that receives positional arguments (`-` discards them).
- `DRY_RUN=true` from `--dry-run` is enough: `dybatpho::dry_run` reads
  `DYBATPHO_DRY_RUN` and falls back to `DRY_RUN`.
- `dybatpho::opts::cmd <name> <spec-function>` adds a subcommand with a spec
  of its own; `dybatpho::opts::disp` adds a display-only option such as
  `--version`.
- The option keys (`init:`, `on:`, `validate:`, `required:`, `export:`, …) are
  listed at the top of `docs/cli.md`; `example/cli_basic.sh` and
  `example/cli_advanced.sh` are complete scripts.

Inside a function, bind arguments with `dybatpho::expect_args` instead of
reading `$1`, `$2` by hand:

```bash
function deploy {
  local env version
  dybatpho::expect_args env version -- "$@"
  ...
}
```

## Errors, logging and cleanup

| Need | Use |
|---|---|
| Stop the script with a message | `dybatpho::die "message" [code]` |
| Report and carry on | `dybatpho::error`, `dybatpho::warn` |
| Progress and detail | `dybatpho::info`, `dybatpho::debug`, `dybatpho::success` |
| Choose verbosity | `DYBATPHO_LOG_LEVEL` (`trace`, `debug`, `info`, `warn`, `error`, `fatal`) |
| Error and signal handlers | `dybatpho::register_common_handlers`, once after sourcing |
| Add to a trap without replacing it | `dybatpho::trap "command" EXIT INT TERM` |
| Temporary file or directory, removed on exit | `dybatpho::create_temp var ".txt"`, `dybatpho::create_temp_dir var` |
| Remove something on exit | `dybatpho::cleanup_file_on_exit "${path}"` |
| Check a tool is installed | `dybatpho::require jq` |
| Test a value | `dybatpho::is file\|dir\|command\|int\|number\|true\|set\|… "${value}"` |
| Validate against rules | `dybatpho::validate_or_die` (module `validate`) |
| Retry, time out, catch a failure | `dybatpho::retry`, `dybatpho::run_with_timeout`, `dybatpho::try` |
| Honour dry run | `dybatpho::dry_run -- cmd args…` (reads `DYBATPHO_DRY_RUN`) |

- Messages go to stderr through the logging functions; never `echo` a
  diagnostic to stdout, which is the script's data channel.
- `dybatpho::die` inside `$(...)` only ends the subshell. Check the status of
  the assignment: `value=$(lookup "${key}") || dybatpho::die "No ${key}"`.
- Destructive work goes through the `safety` module (`dybatpho::safe_rm`,
  `dybatpho::safe_overwrite`), secrets through `secret`
  (`dybatpho::secret_from_env`, `dybatpho::secret_mask`); never log a secret's
  value.

## Which module

| Need | Module |
|---|---|
| Options, subcommands, help, completion | `cli` |
| HTTP requests, downloads, retries over the network | `network` |
| JSON and YAML queries | `json` |
| Validating values and config | `validate`, `config` |
| Paths, atomic writes, temp files | `file` (core) |
| Strings, arrays | `string`, `array` (core) |
| Dates, exact decimal math, semver | `date`, `math`, `semver` |
| Locks, running jobs in parallel, queues | `lock`, `parallel`, `queue` |
| Guarded `rm`/overwrite/extract | `safety` |
| Git, releases, the forge (GitHub/GitLab) | `git`, `release`, `forge` |
| Spinners, menus, confirmations; full-screen apps | `tui`; `screen` |
| Tables, Markdown, CSV | `table`, `markdown`, `csv` |
| Package install, `sudo` once per run, services | `pkg`, `privilege`, `service` |
| Testing scripts (asserts, mocks, snapshots) | `testing` |
| Calling an LLM; being driven by an agent | `ai`; `agent` |

The complete list, with stability, is in
[references/modules.md](references/modules.md). An experimental module may
change in any minor release; prefer a stable one when either would do.

## Before reporting done

- Lint every script you wrote or changed with
  [dyshellint](https://github.com/dynamotn/dyshellint), which runs ShellCheck
  and shfmt on top of the Bash style rules, and fix what it reports:

  ```bash
  dyshellint -warnings-as-errors path/to/script.sh
  ```

  Silence a rule only on purpose, with
  `# dyshellint disable=<CODE> <reason>` on the line above.
- Run the script's tests, or at least `--help` and one real invocation.
- Document functions with shdoc comments (`# @description`, `# @arg`,
  `# @noargs`, `# @stdout`, `# @exitcode`), as the library does.
