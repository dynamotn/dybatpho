# Migrating between major versions

Each section lists what a script written for the previous major version has to
change, and how. It covers only what can break a working script; everything else
is in [CHANGELOG.md](../CHANGELOG.md) (older releases are archived under
[docs/changelog/](changelog/) once `scripts/changelog_archive.sh` has run).

Every entry here has a **BREAKING** counterpart in the changelog that shows the
old call and the new one. The policy behind these releases is in the
*Versioning and stability* section of the [README](../README.md#versioning-and-stability).

Before upgrading, `dybatpho::doctor --modules "<the modules the script loads>"`
lists the modules that set pulls in and every external command they can call,
which is the inventory the sections below are checked against.

## 6.x to 7.0

7.0 batches the API clean-up planned since 6.0. Upgrade in this order, running
the script's own tests after each step.

### Module tiers

<!-- 7.0: tiers -->

### Exported functions

<!-- 7.0: export -->

### Strict mode

<!-- 7.0: strict -->

### JSON and YAML

<!-- 7.0: json -->

### Environment variables

<!-- 7.0: env -->

### Evaluated arguments

<!-- 7.0: eval -->

## 5.x to 6.0

6.0 narrowed the module dependency graph: a module now loads only the modules it
calls on every path. A function that needs another module only on one path
stops with a message naming the module to load, instead of loading it for
every caller.

| Loading this | No longer brings | Needed only by | Fix |
| --- | --- | --- | --- |
| `network` (and `notification`, `forge`, `ai`, `testing` through it) | `json` | `dybatpho::curl_graphql` | add `json` to `--modules` |
| `diff` or `backup` | `json` | `dybatpho::diff_yaml` | add `json` |
| `csv` | `json` | `dybatpho::csv_to_json` | add `json` |
| `testing` | `json`, `diff`, `network` | the JSON and YAML assertions (`json`), drawn snapshot mismatches (`diff`) | add the module the assertion uses |
| `text` | `table` | `dybatpho::text_columns` | add `table` |
| `markdown` | `table` | `dybatpho::md_table` | add `table` |
| `safety` (and `tui`, `agent`, `pkg` through it) | `archive` | `dybatpho::safe_extract` | add `archive` |
| `archive` | `safety` | nothing in `archive` | add `safety` if the script calls it |
| `cli` (and `safety`, `tui`, `agent`, `pkg` through it) | `config` | `dybatpho::config_load` and the other `config_*` functions | add `config` |
| `release` | `archive` | `dybatpho::release_package` | add `archive` |
| `schedule` | `lock` | `dybatpho::schedule_debounce` | add `lock` |
| `i18n` | `date` | `dybatpho::i18n_date`, `i18n_time`, `i18n_datetime`, `i18n_date_pattern`, and `i18n_relative` reading the clock | add `date` |

A function whose module is missing stops with `<function> needs the <module>
module, load it with: dybatpho::load <module>`, so the fix is always the module
that message names. Any other `dybatpho::<module>_*` call that relied on the old
edge needs the same addition.

```bash
# 5.x
. dybatpho/init.sh --modules network
dybatpho::curl_graphql "${url}" "${query}"

# 6.0
. dybatpho/init.sh --modules "network json"
dybatpho::curl_graphql "${url}" "${query}"
```

A script that loads `--modules all` is not affected.

## 4.x to 5.0

5.0 has no change to a function's arguments or output, but three things outside
the function signatures moved:

- **Documentation paths.** The generated reference moved from `doc/` to
  `docs/` (`doc/logging.md` is now `docs/logging.md`), and the specifications
  to `docs/spec/`. Update any link into the repository.
- **Lock layout.** A lock is a symbolic link, not a directory, with the command
  that took it in a file beside it. `dybatpho::lock_info`,
  `dybatpho::lock_is_held` and `dybatpho::lock_field` are unchanged; code that
  inspected the lock directory by hand has to use them instead.
- **Snapshot switches.** `DYBATPHO_TEST_UPDATE_SNAPSHOTS=0` now means off.
  Only `1`, `true`, `yes` and `on` turn a snapshot switch on.

## 3.x to 4.0

The rest variable named by `dybatpho::opts::setup` is a Bash array, not a
string joined with spaces. Read it as an array:

```bash
# 3.x
dybatpho::opts::setup "Copy files" FILES action:"_run"
_run() { for f in ${FILES}; do ...; done; }

# 4.0
dybatpho::opts::setup "Copy files" FILES action:"_run"
_run() { for f in "${FILES[@]}"; do ...; done; }
```

`dybatpho::opts::arg` now binds its variable, in declaration order, so a
command that declared arguments and then split the rest variable by hand can
read the named variables instead.

## 2.x to 3.0

The minimum Bash is 4.3, raised from 4.0. `init.sh` refuses to load on anything
older. On macOS, install a current Bash (`brew install bash`) and run scripts
with it; the system `/bin/bash` is 3.2.

## 1.x to 2.0

Sourcing `init.sh` with no argument loads only the core modules (`string`,
`logging`, `helpers`, `process`, `file`, `secret`). Name everything else:

```bash
# 1.x: every module
. dybatpho/init.sh

# 2.0
. dybatpho/init.sh --modules "git semver"
# or
DYBATPHO_MODULES="git semver" . dybatpho/init.sh
# or, after loading
dybatpho::load git semver
```

`--modules all` restores the 1.x behaviour.
