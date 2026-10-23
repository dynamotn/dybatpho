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

Nothing breaks. Every module now reports a tier: `stable` modules keep their
public contract across minor releases, `experimental` ones may change in any
minor release. Check what a script depends on with
`dybatpho::module_list experimental` or `dybatpho::doctor`, and pin the library
version more tightly if it leans on experimental modules.

Functions that used to stop with `… needs the X module, load it with:
dybatpho::load X` now load `X` on demand and succeed. A test that matched the
old message must change. A module loaded on demand inside `$(...)` is gone with
that subshell, so name it in `--modules` when such a call sits on a hot path. A
bundle that does not carry the module still stops; regenerate it with
`scripts/bundle.sh --with-soft-deps`.

### Exported functions

Child processes no longer see dybatpho functions. A script whose `bash -c`,
`xargs bash -c`, `find -exec bash -c` or `timeout bash -c` children call the
library opts in, before or after sourcing:

```sh
DYBATPHO_EXPORT_FUNCTIONS=true . lib/dybatpho/init.sh --modules semver
# or, after sourcing:
dybatpho::export_functions
```

Each non-interactive Bash child then sources the whole library, internal
helpers included, so calls that used to fail or answer wrongly in a child now
work. A `BASH_ENV` the script already set is still sourced first.

### Strict mode

| 6.x | 7.0 | Fix |
| --- | --- | --- |
| `nullglob` and `globstar` on after sourcing | both left as the caller had them | add `shopt -s nullglob globstar` after sourcing, or guard glob loops with `[[ -e "${f}" ]] \|\| continue` |
| a failed bootstrap ran `exit 1` | it returns 1 | under `set -e` nothing changes; otherwise write `. init.sh --modules … \|\| exit 1` |
| no way to keep your own options | `--no-strict` leaves every `set` and `shopt` option alone | `. init.sh --no-strict --modules …` (the option goes first, like `--modules`) |

Bundles behave the same way.

### JSON and YAML

Every filter passed to `json_query`, `json_has`, `json_eval`, `json_get`,
`yaml_query`, `yaml_has` and the `testing` JSON/YAML assertions is now a `jq`
filter, run by `jq` even when `yq` is installed. `jq` is required for every
JSON helper but `dybatpho::json_string`; the Go `yq` v4 only for YAML, and the
Python `yq` is refused by name.

| yq syntax | jq |
| --- | --- |
| `strenv(X)`, `env(X)` | `$ENV.X`, or `--arg x "${X}"` and `$x` (extra arguments go to `jq`) |
| `downcase`, `upcase` | `ascii_downcase`, `ascii_upcase` |
| `.[] as $x ireduce (init; f)` | `reduce .[] as $x (init; f)` |
| `tag == "!!map"` (`!!seq`, `!!str`, `!!int`, `!!null`) | `type == "object"` (`array`, `string`, `number`, `null`) |
| `to_json`, `from_json` | `tojson`, `fromjson` |
| `with(path; f)` | `path \|= f` |
| `keys` in document order | `keys_unsorted` (`keys` is sorted now) |
| `eval`, `-o=json`, `-P`, `-I=0` passed as extra arguments | drop them; use `dybatpho::json_to_yaml` for YAML output |

`json_get` prints objects and arrays as JSON, `json_has`/`yaml_has` return 1 for
`false`, `null` or no output, and `csv_from_json`, `table_from_json` and the
YAML/TOML paths of `config_load` need `jq` too (YAML hexadecimal integers load
as their decimal value).

### Environment variables

| 6.x name | 7.0 name | Notes |
| --- | --- | --- |
| `LOG_LEVEL`, `LOG_FORMAT`, `LOG_FILE`, `LOG_FILE_LEVEL`, `LOG_FILE_MAX_BYTES`, `LOG_FILE_MAX_BACKUPS`, `LOG_REQUEST_ID` | `DYBATPHO_LOG_*` | the bare name is still read when the prefixed one is unset or empty |
| `DRY_RUN` | `DYBATPHO_DRY_RUN` | `DYBATPHO_DRY_RUN=false` overrides an inherited `DRY_RUN=true` |
| `UPDATE_SNAPSHOTS` | `DYBATPHO_TEST_UPDATE_SNAPSHOTS` | the prefixed switch wins |

The library no longer assigns or exports any of these, nor `NO_COLOR`, nor its
own defaults and state (`DYBATPHO_SPINNER*`, `DYBATPHO_TUI_*`, …). Children no
longer inherit the log level, the request ID or the results of
`dybatpho::log_to_file` and `dybatpho::cli_apply_verbosity`: export the
`DYBATPHO_` names yourself where a child should share them, and read
`$DYBATPHO_LOG_LEVEL` / `$DYBATPHO_LOG_FILE` after those helpers instead of the
bare names. With no file level set, the file threshold follows the current log
level.

### Evaluated arguments

The single shell-string forms still work in 7.0 but are deprecated and go in
the next major. Each one runs its string through `eval`, so data interpolated
into it is code:

| Deprecated | Use |
| --- | --- |
| `dybatpho::retry 3 "curl -fsSL '${url}'" desc` | `dybatpho::retry 3 desc -- curl -fsSL "${url}"` |
| `dybatpho::retry_until 5 2 "test -S ${s}"` | `dybatpho::retry_until 5 2 -- test -S "${s}"` |
| `dybatpho::assert '[[ -f $f ]]' msg` | `dybatpho::assert msg -- test -f "${f}"` |
| `dybatpho::circuit_breaker k "cmd"` | `dybatpho::circuit_breaker k -- cmd` |
| `dybatpho::debug_command m "cmd"` | `dybatpho::debug_command m -- cmd` |
| `dybatpho::parallel_run 3 "a b" "c"` | `local -a j1=(a b) j2=(c); dybatpho::parallel_run --argv 3 j1 j2` |
| `dybatpho::dry_run "rm -rf ${p}"` | `dybatpho::dry_run -- rm -rf -- "${p}"` |

### Plural categories

`dybatpho::i18n_plural_form` follows CLDR for more languages, so a catalog that
was written against the old answers picks a different form:

| Language | Count | 6.x | 7.0 |
| --- | --- | --- | --- |
| Serbian, Croatian, Bosnian (`sr`, `hr`, `bs`, `sh`) | 0, 5-20, 25-30, ... | `many` | `other` |
| Maltese (`mt`) | 2 | `few` | `two` |
| Maltese (`mt`) | 102, 202, ... | `few` | `other` |
| Zulu, Kannada, Gujarati, Punjabi, Sinhala, Armenian, Northern Sotho | 0 | `other` | `one` |

A catalog that already follows CLDR needs nothing. One that supplied `many` for
Serbian-family languages renames it to `other`; a Maltese catalog adds `two`.

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
