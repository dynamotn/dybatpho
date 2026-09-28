# cli.sh

Utilities for building CLI parsers from shell specs.

> 🧭 Source: [src/cli.sh](../src/cli.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)
>
> Reference sections: [Internal functions](#internal-functions) · [Spec functions](#spec-functions) · [Parse functions](#parse-functions)

<a id="overview"></a>
## ✨ Overview

`src/cli.sh` lets you describe a command with shell functions, then generate:

- option parsing
- subcommand dispatch
- help output
- validation and error handling
- automatic `--help` / `-h` for commands that do not define their own help option

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CLI_DEBUG`** | bool | Set to `true` to dump generated parser details while developing specs |
| **`DYBATPHO_CLI_CACHE`** | bool | Set to `false` to regenerate completion output instead of reusing the cached copy. Default is `true` |
| **`DYBATPHO_CLI_CACHE_DIR`** | string | Directory holding cached completion output. Default is `${XDG_CACHE_HOME:-$HOME/.cache}/dybatpho/cli` |

### 🚀 Highlights

- [`dybatpho::prompt`](#dybatphoprompt) — Read a line from the terminal (or stdin) with an optional default.
- [`dybatpho::select`](#dybatphoselect) — Prompt for one or more values from a comma-separated list or numeric range.
- [`dybatpho::opts::validate_choice`](#dybatphooptsvalidate_choice) — Check that a value belongs to a comma-separated choice list.
- [`dybatpho::cli_levenshtein`](#dybatphocli_levenshtein) — Compute the Levenshtein edit distance between two strings.
- [`dybatpho::cli_suggest`](#dybatphocli_suggest) — Print the candidates closest to a mistyped switch or command name. Leading dashes are ignored while comparing, so `--colr` still matches `--color`, and a candidate that shares a prefix with the input always wins over a pure edit-distance match.
- [`dybatpho::cli_verbosity_level`](#dybatphocli_verbosity_level) — Raise a log level by the number of times a counting `-v` flag was repeated.
- [`dybatpho::cli_apply_verbosity`](#dybatphocli_apply_verbosity) — Apply a repeat count from a counting `-v` flag to `LOG_LEVEL`.
- [`__dybatpho_cli_config_get`](#__dybatpho_cli_config_get) — Functions are triggered by `dybatpho::generate_from_spec` Read a key bound with `config:<key>` out of the configuration loaded by `src/config.sh`. Missing keys and an unloaded config module both report failure so the generated parser falls through to the option's declared default.
- [`__dybatpho_cli_parse_opt`](#__dybatpho_cli_parse_opt) — Parse options with a spec from `dybatpho::opts::flag`, `dybatpho::opts::param`
- [`__dybatpho_cli_print_indent`](#__dybatpho_cli_print_indent) — Write script with indentation to stdout
- [`__dybatpho_cli_require_shell_name`](#__dybatpho_cli_require_shell_name) — Validate a shell variable name used by generated parser code.
- [`__dybatpho_cli_collect_long_switches`](#__dybatpho_cli_collect_long_switches) — Collect every long switch a spec accepts, for abbreviation matching. The metadata walk is reused because it already expands `--{no-}x`, aliases, and negatable forms.
- [`__dybatpho_cli_expand_abbr`](#__dybatpho_cli_expand_abbr) — Resolve an abbreviated long option against the switches a command accepts, the way `--vers` stands for `--version`. An exact match wins outright, so a switch that is also the prefix of a longer one stays reachable.
- [`__dybatpho_cli_require_case_pattern`](#__dybatpho_cli_require_case_pattern) — Validate a `case` glob supplied by `pattern:<glob>`. Unlike every other spec value, a pattern cannot be quoted on its way into the generated script — quoting it would make `case` compare it literally and defeat the point. This restricts it to characters that cannot end the `case` branch or start a substitution, so a spec still cannot inject code into the parser it generates.
- [`__dybatpho_cli_canonical_type`](#__dybatpho_cli_canonical_type) — Resolve the name given by `type:<name>` to the canonical type the generated parser will call. Kept separate from `__dybatpho_validate_canonical` only so the `cli` module has one place to name the validator it depends on.
- [`__dybatpho_cli_assign_quoted`](#__dybatpho_cli_assign_quoted) — Assign the quoted string to a variable
- [`__dybatpho_cli_prepend_export`](#__dybatpho_cli_prepend_export) — Prepend export of before string of command, based on `export:<bool>` switch
- [`__dybatpho_cli_define_var`](#__dybatpho_cli_define_var) — Define variable from spec from `dybatpho::opts::flag`, `dybatpho::opts::param`
- [`__dybatpho_cli_parse_key_value`](#__dybatpho_cli_parse_key_value) — Extract key value from spec with format `x:y`, to get settings of option
- [`__dybatpho_cli_generate_logic`](#__dybatpho_cli_generate_logic) — Generate logic from spec of script/function to get options
- [`__dybatpho_cli_print_get_arg`](#__dybatpho_cli_print_get_arg) — Emit generated code that rebuilds positional parameters from a serialized argument list.
- [`__dybatpho_cli_print_rest`](#__dybatpho_cli_print_rest) — Emit generated code that appends the remaining positional arguments to the configured rest variable and stops option parsing.
- [`__dybatpho_cli_generate_help`](#__dybatpho_cli_generate_help) — Get help description for options from spec. Sets __help_mode=true so dybatpho::opts::* collect help data via dynamic scoping into dybatpho::generate_help's locals, then prints the buffered sections in the correct order.
- [`__dybatpho_cli_help_usage`](#__dybatpho_cli_help_usage) — Build the usage line from what the command actually accepts, so it names a COMMAND only when there are subcommands and shows the declared positional arguments when there are any.
- [`dybatpho::generate_schema`](#dybatphogenerate_schema) — Generate a JSON CLI schema from the same option spec used by parsing.
- [`__dybatpho_cli_generate_schema_command`](#__dybatpho_cli_generate_schema_command) — 
- [`dybatpho::generate_man`](#dybatphogenerate_man) — Generate a roff man page from a CLI option spec.
- [`__dybatpho_cli_generate_man_command`](#__dybatpho_cli_generate_man_command) — 
- [`dybatpho::generate_completion`](#dybatphogenerate_completion) — Generate Bash, Zsh, or Fish completion from a CLI option spec.
- [`__dybatpho_cli_cache_file`](#__dybatpho_cli_cache_file) — Resolve the cache file for a generated artifact, creating the cache directory when needed. The key hashes the script that declares the spec, so a spec change produces a new key instead of a stale hit; a spec declared from an unreadable source (a `bash -c` one-liner, for example) is simply not cached.
- [`__dybatpho_cli_completion_words`](#__dybatpho_cli_completion_words) — 
- [`__dybatpho_cli_generate_completion_command`](#__dybatpho_cli_generate_completion_command) — 
- [`__dybatpho_cli_help_pad`](#__dybatpho_cli_help_pad) — Pad string $2 to at least length $3 and store result in variable $1
- [`__dybatpho_cli_help_sw`](#__dybatpho_cli_help_sw) — Append a formatted switch to caller-local variable `sw`. Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so that short+long pairs align as "-s, --long".
- [`__dybatpho_cli_help_row`](#__dybatpho_cli_help_row) — Build one help row and print it as a record for later rendering. Rendering is deferred because the column width is only known once every row of every section has been collected.
- [`__dybatpho_cli_help_add_switch`](#__dybatpho_cli_help_add_switch) — Sort one declared switch into the caller-local `_short_forms` and `_long_forms` buffers, expanding bracketed and `negatable:true` forms on the way.
- [`__dybatpho_cli_help_annotate`](#__dybatpho_cli_help_annotate) — Append a `[name: value]` annotation to a caller variable, or do nothing when the value is empty.
- [`__dybatpho_cli_help_default`](#__dybatpho_cli_help_default) — Render the literal default of an `init:` form, or nothing when the default is empty, dynamic, or an `init:@...` directive that has no value to show.
- [`__dybatpho_cli_help_render_rows`](#__dybatpho_cli_help_render_rows) — Print every collected help row, aligned to a shared column.
- [`__dybatpho_cli_help_dedupe`](#__dybatpho_cli_help_dedupe) — Drop rows whose label was already collected, keeping the first.
- [`__dybatpho_cli_help_width_for`](#__dybatpho_cli_help_width_for) — Choose the description column width that fits every row, so the Arguments, Commands, and Options sections line up with each other.
- [`__dybatpho_cli_add_switch`](#__dybatpho_cli_add_switch) — Add to switches list if flag/param has multiple switches
- [`__dybatpho_cli_suggest_suffix`](#__dybatpho_cli_suggest_suffix) — Build the `Did you mean ...` suffix appended to an unrecognized option or command error. Called from generated parser code.
- [`__dybatpho_cli_add_plain_switch`](#__dybatpho_cli_add_plain_switch) — Add a literal switch to the switches list, pairing a long switch with its `--no-` form when the option is declared `negatable:true`. Short switches and switches that already carry a negative prefix are added unchanged.
- [`__dybatpho_cli_expand_switch`](#__dybatpho_cli_expand_switch) — Expand one declared switch into the concrete switches a user can type, honouring `--{no-}name`, `--with{out}-name`, and `negatable:true`. Results are appended to a caller-provided array.
- [`__dybatpho_cli_print_validate`](#__dybatpho_cli_print_validate) — Emit generated code that validates the current `OPTARG` and assigns it to the destination variable.
- [`__dybatpho_cli_parse_alias_list`](#__dybatpho_cli_parse_alias_list) — Split a comma-separated alias list into a caller-provided array.
- [`__dybatpho_cli_record_persistent_def`](#__dybatpho_cli_record_persistent_def) — Serialize an option definition so it can be replayed for persistent descendant commands.
- [`__dybatpho_cli_replay_persistent_defs`](#__dybatpho_cli_replay_persistent_defs) — Replay inherited persistent option definitions inside the current parser/help generation context.
- [`__dybatpho_cli_print_persistent_help_defs`](#__dybatpho_cli_print_persistent_help_defs) — Emit generated code that seeds persistent option definitions for nested help output.
- [`__dybatpho_cli_print_known_candidates`](#__dybatpho_cli_print_known_candidates) — Emit generated code declaring the switches and command names the current command accepts, used to suggest a close match when the user mistypes one.
- [`__dybatpho_cli_print_deprecated_warning`](#__dybatpho_cli_print_deprecated_warning) — Emit generated code that warns when a deprecated CLI item is used.
- [`__dybatpho_cli_generate_child_logic`](#__dybatpho_cli_generate_child_logic) — Generate parser logic for a child command with inherited persistent option definitions.
- [`__dybatpho_cli_print_arg_bindings`](#__dybatpho_cli_print_arg_bindings) — Emit generated code that copies the collected positional arguments into the variables declared with `dybatpho::opts::arg`, in declaration order. A `variadic:true` argument is the last one and receives every remaining value as an array, so the values it holds keep their boundaries.
- [`__dybatpho_cli_print_args_check`](#__dybatpho_cli_print_args_check) — Emit generated code that validates the positional argument count configured by `args:<rule>` in `dybatpho::opts::setup`.
- [`__dybatpho_cli_collect_switches`](#__dybatpho_cli_collect_switches) — Expand option switches and aliases into a caller-provided array.
- [`__dybatpho_cli_json_quote`](#__dybatpho_cli_json_quote) — Escape a value for JSON and store it in a caller variable.
- [`__dybatpho_cli_collect_spec_metadata`](#__dybatpho_cli_collect_spec_metadata) — Collect option and command metadata from a CLI spec.
- [`dybatpho::opts::setup`](#dybatphooptssetup) — Functions work in spec of script or function via `dybatpho::generate_from_spec`. Setup global settings for getting options (mandatory) in spec of script or function
- [`dybatpho::opts::flag`](#dybatphooptsflag) — Define an option that take no argument
- [`dybatpho::opts::param`](#dybatphooptsparam) — Define an option that take an argument
- [`dybatpho::opts::disp`](#dybatphooptsdisp) — Define an option that display only
- [`dybatpho::opts::msg`](#dybatphooptsmsg) — Place a line of free text in the generated help, so a long option list can be broken into labelled groups. It declares no switch and affects nothing but help output.
- [`dybatpho::opts::cmd`](#dybatphooptscmd) — Define a sub-command in spec
- [`dybatpho::opts::arg`](#dybatphooptsarg) — Declare a positional argument. Its value is assigned to the named variable once parsing succeeds, and it also gives the usage line a real placeholder and the generated help, schema, and man page an `Arguments` section. Every value still lands in the rest array named by `dybatpho::opts::setup` as well.
- [`__dybatpho_cli_arg_placeholder`](#__dybatpho_cli_arg_placeholder) — Render a positional argument the way usage lines conventionally do: angle brackets when it is required, square brackets when it is optional, and a trailing ellipsis when it is variadic.
- [`__dybatpho_cli_derive_args_rule`](#__dybatpho_cli_derive_args_rule) — Derive the `args:<rule>` a command would need to accept exactly the positional arguments it declared with `dybatpho::opts::arg`.
- [`dybatpho::generate_from_spec`](#dybatphogenerate_from_spec) — Functions to parse spec and put value of options to variable with corresponding name Define spec of parent function or script, spec contains below commands
- [`dybatpho::generate_help`](#dybatphogenerate_help) — Show help description of root command/sub-command. Declares help state as locals so dybatpho::opts::* in the call chain can read/write them via bash dynamic scoping.

<a id="usage"></a>
## 🚀 Usage

### Basic workflow

1. Write a spec function.
2. Call `dybatpho::opts::setup` once inside that spec.
3. Define flags, params, display options, and subcommands.
4. Call `dybatpho::generate_from_spec <spec> "$@"`.
5. Optionally expose `--help` with `dybatpho::generate_help <spec>`.

#### Minimal example

```bash
function _run {
  dybatpho::print "Hello, ${NAME}!"
  exit 0
}

function _spec {
  dybatpho::opts::setup "A minimal greeter CLI" ARGS action:"_run"
  dybatpho::opts::param "Your name" NAME -n --name required:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

dybatpho::generate_from_spec _spec "$@"
```

### Spec argument types

Functions in this module accept two kinds of extra arguments:

| Type | Description |
| ---- | ----------- |
| `switch` | Option switch such as `-f`, `--flag`, `--{no-}flag`, `--with{out}-feature` |
| `key:value` | Attribute in `name:value` form |

### Supported switch forms

| Form | Meaning |
| ---- | ------- |
| `-x` | short option |
| `--name` | long option |
| `--{no-}name` | expands to `--name` and `--no-name` |
| `--with{out}-name` | expands to `--with-name` and `--without-name` |

### Shared attributes

These attributes are parsed by `dybatpho::opts::flag` and/or `dybatpho::opts::param`.

| Attribute | Applies to | Description |
| --------- | ---------- | ----------- |
| `action:<code>` | `setup`, `disp` | Code to run when parsing finishes or a display option is used |
| `prerun:<code>` | `setup` | Code to run after validation and before `action:<code>` |
| `postrun:<code>` | `setup` | Code to run after `action:<code>` |
| `args:<rule>` | `setup` | Positional argument rule: `none`, `exact:N`, `min:N`, `max:N`, or `range:M:N` |
| `abbr:<bool>` | `setup` | Accept an unambiguous prefix of a long switch, such as `--vers` for `--version` |
| `alias:<name>` | `flag`, `param`, `disp`, `cmd` | Add one alias switch or command name |
| `aliases:<a,b>` | `flag`, `param`, `disp`, `cmd` | Add multiple aliases separated by commas |
| `init:<value>` | `flag`, `param` | Initial variable value |
| `on:<string>` | `flag`, `param` | Positive value when the option is enabled |
| `off:<string>` | `flag`, `param` | Negative value when the option is disabled or absent |
| `persistent:<bool>` | `flag`, `param`, `disp` | Make the option available in descendant subcommands |
| `export:<bool>` | `flag`, `param` | Export the variable |
| `env:<NAME>` | `flag`, `param` | Use environment variable `NAME` as the option's initial value |
| `config:<key>` | `flag`, `param` | Use configuration key `key` as the option's initial value, below `env:` and above `init:` |
| `negatable:<bool>` | `flag` | Also accept a generated `--no-<name>` for every long switch |
| `count:<bool>` | `flag` | Count repeats instead of storing a value, so `-vv` yields `2` |
| `optional:<bool>` | `param` | Whether the option value is optional when the switch appears |
| `required:<bool>` | `param` | Whether the option itself must appear |
| `prompt:<text>` | `param` | Prompt for a missing value with the supplied text |
| `choices:<a,b>` | `param` | Restrict values to a comma-separated list of choices |
| `multiple:<bool>` | `param` | Append repeated or multi-selected values instead of replacing the value; interactive selection accepts comma-separated values and ranges such as `1-3` |
| `pattern:<glob>` | `flag`, `param` | Restrict values to a `case` glob such as `fast|slow` |
| `type:<name>` | `flag`, `param` | Restrict values to a `validate` type such as `email`, `port`, or `file` |
| `validate:<code>` | `flag`, `param` | Validation logic using `\$OPTARG` |
| `deprecated:<text>` | `flag`, `param`, `disp`, `cmd` | Warn when the item is used and annotate it in help |
| `error:<code>` | `flag`, `param`, `setup` | Custom error handler |
| `hidden:<bool>` | help output | Hide the row from generated help |
| `label:<string>` | help output | Override the label shown in generated help |

### `init:` forms

| Form | Description |
| ---- | ----------- |
| `init:@empty` | Initialize with empty string |
| `init:@on` | Initialize with the current `on:` value |
| `init:@off` | Initialize with the current `off:` value |
| `init:@unset` | Unset the variable |
| `init:@keep` | Keep the current variable value |
| `init:action:<code>` | Run code without assignment |
| `init:=<code>` | Assign the raw shell expression |

### Positional argument rules

Use `args:<rule>` in `dybatpho::opts::setup` to validate positional arguments
the same way Cobra-style commands often do.

| Rule | Meaning |
| ---- | ------- |
| `args:none` | Reject all positional arguments |
| `args:exact:2` | Require exactly 2 positional arguments |
| `args:min:1` | Require at least 1 positional argument |
| `args:max:3` | Allow at most 3 positional arguments |
| `args:range:1:2` | Require between 1 and 2 positional arguments |

### Parsing and dispatch

`dybatpho::generate_from_spec` generates and runs parser logic from a spec. It:

- initializes variables from the spec
- parses switches and arguments
- counts positional arguments for `args:` rules
- validates input
- dispatches subcommands
- runs the `action:` from `dybatpho::opts::setup`

### Positional arguments

The second argument to `dybatpho::opts::setup` names a **Bash array** that
collects everything which is not a switch:

```bash
function _spec {
  dybatpho::opts::setup "Copy files" FILES action:"_run"
}

function _run {
  dybatpho::print "Got ${#FILES[@]} file(s)"
  for file in "${FILES[@]}"; do dybatpho::print "- ${file}"; done
}
```

An array is what keeps `tool "my report.pdf" notes.txt` two arguments rather
than three, and keeps quotes, glob characters, and newlines inside a value
untouched. Read it with `"${FILES[@]}"`; `"${#FILES[@]}"` is the count.

Bash cannot export an array, so `export:` has nothing to say about the rest
variable. Note that under `set -u` a scalar read such as `${FILES}` fails on
an empty array rather than expanding to the empty string.

### Help generation

`dybatpho::generate_help` renders the layout a conventional command-line
tool uses:

```text
Usage: deploy-tool deploy [OPTIONS] <SERVICE> [TARGETS]...

Deploy selected components

Arguments:
  <SERVICE>                       Service to deploy
  [TARGETS]...                    Extra targets

Commands:
  rollback                        Undo the last deploy

Options:
  -e, --environment <DEPLOY_ENV>  Target environment (required)
                                  [env: DEPLOY_ENV]
                                  [config: deploy.environment]
                                  [choices: staging, production]
                                  [default: staging]
  -h, --help                      Show this help

Run 'deploy-tool COMMAND --help' for more information on a command.
```

It automatically handles:

- a usage line that names `COMMAND` only when there are subcommands, and
  shows the arguments declared with `dybatpho::opts::arg`
- description from `dybatpho::opts::setup`
- argument, command, and option rows aligned to one shared column
- the `-h, --help` row every command gets for free
- current subcommand path
- automatic `(required)` suffix for `required:true` params
- `[env: ...]`, `[config: ...]`, `[choices: ...]`, `[pattern: ...]`, `[type: ...]`, `[default: ...]`,
  `[repeatable]`, and `[repeat to increase]` annotations, each on its own
  line under the description

A `[default: ...]` annotation is only shown for a literal `init:` value. A
default built from a command substitution or a variable is resolved at run
time, so printing the expression would mislead more than it helps.

By default:

- `flag` rows show switches only
- `param` rows show switches plus `<VARNAME>`
- `disp` rows show switches only
- `cmd` rows show the command name

You can override the rendered label with `label:<string>`.

Commands automatically accept `--help` and `-h` unless the spec defines a
help display option itself. Define a custom display option when the command
needs a different help action or aliases.

### Common patterns

#### Required positional-like option

```bash
function _run {
  dybatpho::print "Hello, ${NAME}"
  exit 0
}

function _spec {
  dybatpho::opts::setup "Greeter" -
  dybatpho::opts::param "Your name" NAME --name required:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}
```

#### Exact positional args

```bash
function _spec_sum {
  dybatpho::opts::setup "Add two numbers" SUM_ARGS args:exact:2 action:"_run_sum"
}
```

#### Aliases

```bash
dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
dybatpho::opts::cmd config _spec_config alias:cfg aliases:conf,settings
```

#### Persistent parent options

```bash
function _spec_root {
  dybatpho::opts::setup "Root command" -
  dybatpho::opts::flag "Verbose output" VERBOSE --verbose persistent:true
  dybatpho::opts::cmd deploy _spec_deploy
}
```

#### Hidden and deprecated items

```bash
dybatpho::opts::flag "Legacy flag" LEGACY --legacy hidden:true
dybatpho::opts::cmd old-run _spec_old deprecated:"Use 'run' instead"
```

#### PreRun / PostRun hooks

```bash
function _spec_run {
  dybatpho::opts::setup "Run command" - prerun:"echo pre" action:"echo main" postrun:"echo post"
}
```

#### Boolean toggle

```bash
dybatpho::opts::flag "Color output" COLOR --{no-}color on:true off:false init:="true"
```

`negatable:true` generates the negative switch instead of spelling both out.
Without an explicit `off:`, a negatable flag turns off to `false` rather
than to the empty string, so `--no-color` lands on a value worth testing:

```bash
dybatpho::opts::flag "Color output" COLOR --color negatable:true init:="true"
# accepts --color and --no-color; aliases get their own --no- form too
```

#### Counting verbosity

A `count:true` flag records how often it appeared instead of storing a
value, so `-v`, `-vv`, and `-v -v` yield `1`, `2`, and `2`. It starts at `0`
unless `init:` says otherwise.

```bash
dybatpho::opts::flag "Increase verbosity" VERBOSITY -v alias:--verbose count:true

function _run {
  dybatpho::cli_apply_verbosity "${VERBOSITY}" # info -> debug -> trace
}
```

#### Binding an option to a configuration key

`config:<key>` reads the key from the configuration `src/config.sh` loaded,
giving one precedence chain across the whole CLI:

**flag > `env:` > `config:` > `init:`**

```bash
dybatpho::config_load ./app.yaml          # before generate_from_spec

function _spec {
  dybatpho::opts::setup "Serve" ARGS action:"_run"
  dybatpho::opts::param "Port to listen on" PORT --port \
    env:APP_PORT config:server.port init:="8080"
}
```

The configuration has to be loaded before `dybatpho::generate_from_spec`,
because that is when the parser resolves an option's initial value. A key
that is absent, or a CLI that never loaded any configuration at all, simply
falls through to `init:`.

#### Named positional arguments

```bash
function _spec {
  dybatpho::opts::setup "Copy a file" ARGS action:"_run"
  dybatpho::opts::arg "File to read" SOURCE
  dybatpho::opts::arg "Where to write it" TARGET required:false
  dybatpho::opts::arg "Anything else" EXTRA required:false variadic:true
}
# Usage: tool [OPTIONS] <SOURCE> [TARGET] [EXTRA]...

function _run {
  dybatpho::print "${SOURCE} -> ${TARGET}"
  dybatpho::print "plus ${#EXTRA[@]} more"
}
```

Each argument is assigned to its variable in declaration order once the
count check passes, so an action reads `${SOURCE}` rather than picking the
value out of the rest array by index. A `variadic:true` argument comes last
and is an array of everything remaining; an omitted optional argument is the
empty string. Use `-` as the variable name to document an argument without
binding it.

Declaring arguments also derives the `args:<rule>` count check, so the two
never disagree. State `args:` explicitly to override the derived rule.

#### Abbreviating long options

`abbr:true` on `dybatpho::opts::setup` lets a long switch be typed as any
prefix that identifies it uniquely. It is off by default, because turning it
on means every new option can make a previously working abbreviation
ambiguous.

```bash
dybatpho::opts::setup "Tool" ARGS abbr:true action:"_run"
dybatpho::opts::flag "Colorize output" COLOR --color
dybatpho::opts::param "Configuration file" CONFIG --config
# --colo works, --config works, --co is ambiguous
```

An exact match always wins, so declaring both `--log` and `--log-level`
keeps `--log` usable. A prefix matching more than one switch fails with
`Ambiguous option: --co (matches --color, --config)`, translated under the
key `cli.ambiguous_option`; the `error:` handler sees the error name
`ambiguous` with the candidates in `$OPTARG`. A prefix matching nothing is
reported as an unrecognized option, suggestion included.

#### Restricting values to a pattern

`type:` names a check the `validate` module already owns — `email`,
`port`, `ipv4`, `semver`, `file`, or anything registered with
`dybatpho::validate_register` — so the common cases need neither a glob nor
a validator function, and a rejected value is described the same way it
would be in a configuration file. A spec naming a type that does not exist
fails when the parser is generated rather than when a user first types a
value.

`pattern:` takes a `case` glob, which covers the common checks without a
helper function. `choices:` is still the better fit for a fixed list, since
it also feeds completion and the `[choices: ...]` help annotation.

```bash
dybatpho::opts::param "Mode" MODE --mode pattern:'fast|slow'
dybatpho::opts::param "Port" PORT --port pattern:'[0-9]*'
dybatpho::opts::param "Port" PORT --port type:port
dybatpho::opts::param "Contact" EMAIL --email type:email
```

A value that does not match fails with
`Does not match the pattern (fast|slow): medium`, translated under the key
`cli.pattern_mismatch`, and the `error:` handler sees the error name
`pattern:<glob>`.

A pattern reaches the generated parser unquoted, because quoting it would
make `case` compare it literally. It is therefore restricted to characters
that cannot end a `case` branch or start a substitution, and a pattern
outside that set is rejected when the parser is generated.

#### Grouping options in help

`dybatpho::opts::msg` puts a line of free text in the help output, which is
what a long option list needs to stay readable. It declares no switch, and
completion, schema, and man output ignore it.

```bash
dybatpho::opts::msg "Connection options:"
dybatpho::opts::param "Host to reach" HOST --host
dybatpho::opts::msg ""
dybatpho::opts::msg "Output options:"
dybatpho::opts::flag "Colorize output" COLOR --color
```

#### Validation

```bash
_validate_port() {
  [[ "${1}" =~ ^[0-9]+$ ]] && [ "${1}" -ge 1 ] && [ "${1}" -le 65535 ]
}

dybatpho::opts::param "Port" PORT --port validate:"_validate_port \$OPTARG"
```

#### Subcommand tree

```bash
function _spec_root {
  dybatpho::opts::setup "Tool root" ROOT_ARGS action:"dybatpho::generate_help _spec_root"
  dybatpho::opts::cmd user _spec_user
  dybatpho::opts::cmd config _spec_config
}

function _spec_user {
  dybatpho::opts::setup "User commands" USER_ARGS action:"dybatpho::generate_help _spec_user"
  dybatpho::opts::cmd add _spec_user_add
}
```

### Error messages

The parser reports these standard errors:

- `Unrecognized option: ...`
- `Does not allow an argument: ...`
- `Requires an argument: ...`
- `Missing required option: ...`
- `Expected ... arguments, got ...`
- `Invalid command: ...`
- `Validation error (...): ...`

`Unrecognized option` and `Invalid command` carry a suggestion when the
input is close to something the command accepts, compared by Levenshtein
distance with leading dashes ignored:

```text
Unrecognized option: --colr. Did you mean '--color'?
Invalid command: depoy. Did you mean 'deploy'?
```

A command that declares at least one switch rejects any unmatched `-x` or
`--xy` rather than collecting it as a positional argument. Use `--` to pass
dashed values through. A command that declares no switches at all is a
passthrough wrapper and keeps collecting them.

### Debugging

Set `DYBATPHO_CLI_DEBUG=true` to print the generated parser script.

```bash
DYBATPHO_CLI_DEBUG=true bash example/cli_basic.sh --help
```

This is useful when debugging:

- dispatch flow
- generated actions
- switch matching
- help generation

### Advanced UX example

`example/cli_ux.sh` is a complete spec-driven CLI example:

- `_spec_root` declares the root command, a persistent `count:true` verbosity flag, plus `deploy`, `completion`, `schema`, and `man` subcommands.
- `_spec_deploy` demonstrates `arg`, `env:`, `config:`, `choices:`, `prompt:`, `multiple:`, `negatable:`, and boolean toggles.
- `_spec_completion`, `_spec_schema`, and `_spec_man` define the artifact subcommands.
- `_run_root`, `_run_completion`, `_run_schema`, and `_run_man` implement their actions.
- `_run_deploy` consumes the parsed values and performs the deploy action.

Run it with:

```bash
bash example/cli_ux.sh deploy --component api api
bash example/cli_ux.sh deploy -vv --no-color --component api api
bash example/cli_ux.sh depoy                      # suggests 'deploy'
bash example/cli_ux.sh completion --shell bash
bash example/cli_ux.sh schema
bash example/cli_ux.sh man
```

### Completion cache

`dybatpho::generate_completion` caches its output under
`DYBATPHO_CLI_CACHE_DIR`, so a shell startup that sources a generated
completion does not walk the whole spec tree again. The cache key hashes the
script that declares the spec, so editing that script invalidates the entry
by itself and there is nothing to clear by hand. Set
`DYBATPHO_CLI_CACHE=false` to regenerate every time, and note that a spec
declared somewhere with no readable source file is never cached.

<a id="see-also"></a>
## 🔗 See also

- [example/cli_basic.sh](../example/cli_basic.sh)
- [example/cli_advanced.sh](../example/cli_advanced.sh)
- [example/cli_ux.sh](../example/cli_ux.sh)

<a id="tips"></a>
## 💡 Tips

- Set `DYBATPHO_CLI_DEBUG=true` while developing a spec to inspect the generated parser and help logic.

### `dybatpho::prompt`

- The prompt is written to stderr so the returned value remains clean on stdout.

### `dybatpho::select`

- Pass `true` for the third argument to accept comma-separated values and numeric ranges such as `1-3`.
- Invalid or out-of-range selections are rejected and prompt again.

### `dybatpho::generate_schema`

- Use the schema to drive external validation, form generation, tooling, or documentation from the same source of truth.

### `dybatpho::generate_man`

- Generate the page from the root spec to include the complete nested command tree.

### `dybatpho::generate_completion`

- Keep completion generation in a display option declared inside the spec when the CLI should complete itself.
- Generate completion from the root spec so subcommand options and aliases are included.

### `dybatpho::opts::setup`

- Call `setup` before declaring any flags, params, display options, or subcommands.
- Keep the action focused on command behavior; validation and lifecycle hooks are applied by the generated parser.

### `dybatpho::opts::flag`

- Use `on:` and `off:` with a paired `--{no-}name` switch to model boolean toggles.
- Use `persistent:true` for options that must be accepted by every descendant command.

### `dybatpho::opts::param`

- Use `required:true` when the option itself must be present
- Use `optional:true` when the option may appear without an explicit value
- `optional:true` controls whether a value is required after the switch appears, while `required:true` controls whether the switch itself must appear at all
- Keep conditional requirements such as "required unless `--list` is set" in your action or validation logic
- Use `env:NAME` for an environment fallback; an explicit command-line value always takes precedence.
- Combine `prompt:` with `choices:` to interactively request a missing value from a constrained set.

### `dybatpho::opts::disp`

- Use a display option for help, schema, man-page, completion, or other actions that should exit after running.
- Define a custom help display option only when the default `--help` / `-h` behavior is not sufficient.

### `dybatpho::opts::msg`

- Pass an empty string for a blank separator line.

### `dybatpho::opts::cmd`

- Declare each subcommand with its own spec function so help, completion, schema, and man output stay consistent.
- Aliases are accepted during dispatch and are included in generated help and schema metadata.

### `dybatpho::opts::arg`

- Declare arguments in the order they are typed; a variadic argument must come last.

### `dybatpho::generate_from_spec`

- Generate the parser once at the end of the script after defining the complete spec tree.
- The generated parser preserves the original command-line arguments while dispatching nested subcommands.

### `dybatpho::generate_help`

- The current subcommand path is tracked automatically during parser dispatch
- A command receives automatic `--help` and `-h` unless the spec declares its own help display option.

<a id="reference"></a>
## 📚 Reference

### `dybatpho::prompt`

Read a line from the terminal (or stdin) with an optional default.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt text |
| `$2` | string | Optional default value |

**📤 Output on stdout**

- Entered value

**🚦 Exit codes**

- 0


---

### `dybatpho::select`

Prompt for one or more values from a comma-separated list or numeric range.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt text |
| `$2` | string | Comma-separated choices |
| `$3` | bool | Allow multiple selections |

**📤 Output on stdout**

- Selected value(s), separated by spaces

**🚦 Exit codes**

- 0


---

### `dybatpho::opts::validate_choice`

Check that a value belongs to a comma-separated choice list.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Value |
| `$2` | string | Comma-separated choices |

**🚦 Exit codes**

- `0`: Value is allowed


---

### `dybatpho::cli_levenshtein`

Compute the Levenshtein edit distance between two strings.

**🧪 Example**

```bash
distance="$(dybatpho::cli_levenshtein color colour)"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | First string |
| `$2` | string | Second string |

**📤 Output on stdout**

- Edit distance as a decimal number

**🚦 Exit codes**

- 0


---

### `dybatpho::cli_suggest`

Print the candidates closest to a mistyped switch or command name.
Leading dashes are ignored while comparing, so `--colr` still
matches `--color`, and a candidate that shares a prefix with the
input always wins over a pure edit-distance match.

**🧪 Example**

```bash
dybatpho::cli_suggest --colr --color --cold --verbose

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mistyped input |
| `$@` | string | Known candidates |

**📤 Output on stdout**

- Up to three closest candidates, one per line

**🚦 Exit codes**

- `0`: At least one close candidate was found
- `1`: Nothing was close enough to suggest


---

### `dybatpho::cli_verbosity_level`

Raise a log level by the number of times a counting `-v` flag was repeated.

**🧪 Example**

```bash
LOG_LEVEL="$(dybatpho::cli_verbosity_level 2)" # info -> trace

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Repeat count, default `0` |
| `$2` | string | Base level, default `LOG_LEVEL` |

**📤 Output on stdout**

- Resulting log level, capped at `trace`

**🚦 Exit codes**

- 0


---

### `dybatpho::cli_apply_verbosity`

Apply a repeat count from a counting `-v` flag to `LOG_LEVEL`.

**🧪 Example**

```bash
dybatpho::opts::flag "Increase verbosity" VERBOSITY -v alias:--verbose count:true
# then, from the command action or a prerun hook:
dybatpho::cli_apply_verbosity "${VERBOSITY}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Repeat count, default `0` |
| `$2` | string | Base level, default `LOG_LEVEL` |

**🧩 Variable sets**

- **`LOG_LEVEL`** (string): Raised log level

**🚦 Exit codes**

- 0


<a id="internal-functions"></a>
### 🧩 Internal functions

#### `__dybatpho_cli_config_get`

Functions are triggered by `dybatpho::generate_from_spec`
Read a key bound with `config:<key>` out of the configuration
             loaded by `src/config.sh`. Missing keys and an unloaded config
             module both report failure so the generated parser falls through
             to the option's declared default.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Configuration key |

**📤 Output on stdout**

- Configuration value

**🚦 Exit codes**

- `0`: The key is present
- `1`: The key is absent, or no configuration has been loaded


---

### `__dybatpho_cli_parse_opt`

Parse options with a spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | bool | Flag that defined option that take argument in spec |
| `$2` | number | Count of non-option metadata args to skip after the mode flags |
| `$@` | string | Passed arguments from `dybatpho::opts::(flag\|param\|disp)` |

**🚦 Exit codes**

- 0


---

### `__dybatpho_cli_print_indent`

Write script with indentation to stdout

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Number of indentation level |
| `$@` | string | Line of code to generate |

**📤 Output on stdout**

- Generated code

**🚦 Exit codes**

- 0


---

### `__dybatpho_cli_require_shell_name`

Validate a shell variable name used by generated parser code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name, or `-` to intentionally skip assignment |

**🚦 Exit codes**

- `0`: The name is valid, or the sentinel `-` was used


---

### `__dybatpho_cli_collect_long_switches`

Collect every long switch a spec accepts, for abbreviation
matching. The metadata walk is reused because it already expands
`--{no-}x`, aliases, and negatable forms.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array variable receiving the switches |
| `$2` | string | Name of the spec function |

**🚦 Exit codes**

- `0`: The array is left empty when the spec declares no long switch


---

### `__dybatpho_cli_expand_abbr`

Resolve an abbreviated long option against the switches a command
accepts, the way `--vers` stands for `--version`. An exact match
wins outright, so a switch that is also the prefix of a longer one
stays reachable.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Switch as typed |
| `$@` | string | Long switches the command accepts |

**📤 Output on stdout**

- The resolved switch, or the candidate list when the input is ambiguous

**🚦 Exit codes**

- `0`: Resolved to exactly one switch
- `1`: Matched nothing, so the caller reports it as unrecognized
- `2`: Matched more than one switch; the candidates are on stdout


---

### `__dybatpho_cli_require_case_pattern`

Validate a `case` glob supplied by `pattern:<glob>`. Unlike every
other spec value, a pattern cannot be quoted on its way into the
generated script — quoting it would make `case` compare it
literally and defeat the point. This restricts it to characters
that cannot end the `case` branch or start a substitution, so a
spec still cannot inject code into the parser it generates.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Pattern to validate |

**🚦 Exit codes**

- `0`: The pattern is safe to interpolate


---

### `__dybatpho_cli_canonical_type`

Resolve the name given by `type:<name>` to the canonical type
the generated parser will call. Kept separate from
`__dybatpho_validate_canonical` only so the `cli` module has one
place to name the validator it depends on.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Declared type name or alias |

**📤 Output on stdout**

- Canonical type name

**🚦 Exit codes**

- `1`: The type is not registered


---

### `__dybatpho_cli_assign_quoted`

Assign the quoted string to a variable

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name to be assigned |
| `$2` | string | Input string to be quoted |

**🚦 Exit codes**

- 0


---

### `__dybatpho_cli_prepend_export`

Prepend export of before string of command,
based on `export:<bool>` switch

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String of command |


---

### `__dybatpho_cli_define_var`

Define variable from spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of variable to be defined |


---

### `__dybatpho_cli_parse_key_value`

Extract key value from spec with format `x:y`,
to get settings of option

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | key:value | Key-value string to extract |
| `$2` | string | Prefix of key to assign as variable |


---

### `__dybatpho_cli_generate_logic`

Generate logic from spec of script/function to get options

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of function that has spec of parent function or script |
| `$2` | string | Command of spec (`-` for root command trigger from CLI, otherwise is sub-command) |

**📤 Output on stdout**

- Generated logic


---

### `__dybatpho_cli_print_get_arg`

Emit generated code that rebuilds positional parameters from a serialized argument list.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Shell expression that expands to serialized arguments |

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_print_rest`

Emit generated code that appends the remaining positional arguments to the configured rest variable and stops option parsing.

_Function has no arguments._

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_generate_help`

Get help description for options from spec.
Sets __help_mode=true so dybatpho::opts::* collect help data
via dynamic scoping into dybatpho::generate_help's locals,
then prints the buffered sections in the correct order.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of function that has spec of parent function or script |

**📤 Output on stdout**

- Help description

**🚦 Exit codes**

- `0`: exit code


---

### `__dybatpho_cli_help_usage`

Build the usage line from what the command actually accepts, so
it names a COMMAND only when there are subcommands and shows the
declared positional arguments when there are any.

_Function has no arguments._

**📤 Output on stdout**

- Usage line


---

### `dybatpho::generate_schema`

Generate a JSON CLI schema from the same option spec used by parsing.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Spec function |
| `$2` | string | Optional command name |

**📤 Output on stdout**

- JSON schema


---

### `__dybatpho_cli_generate_schema_command`



---

### `dybatpho::generate_man`

Generate a roff man page from a CLI option spec.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Spec function |
| `$2` | string | Optional command name |

**📤 Output on stdout**

- Man page


---

### `__dybatpho_cli_generate_man_command`



---

### `dybatpho::generate_completion`

Generate Bash, Zsh, or Fish completion from a CLI option spec.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Spec function |
| `$2` | string | Shell (`bash`, `zsh`, or `fish`) |
| `$3` | string | Optional command name |

**📝 Notes**

- Output is cached under `DYBATPHO_CLI_CACHE_DIR`, keyed by the hash of the script that declares the spec, so editing the script invalidates the entry on its own. Set `DYBATPHO_CLI_CACHE=false` to bypass the cache.

**📤 Output on stdout**

- Completion script


---

### `__dybatpho_cli_cache_file`

Resolve the cache file for a generated artifact, creating the
cache directory when needed. The key hashes the script that
declares the spec, so a spec change produces a new key instead of
a stale hit; a spec declared from an unreadable source (a `bash -c`
one-liner, for example) is simply not cached.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the cache file path |
| `$@` | string | Key parts, such as the artifact kind, spec, shell, and command name |

**🚦 Exit codes**

- `0`: A cache file path was resolved
- `1`: Caching is disabled or unavailable for this invocation


---

### `__dybatpho_cli_completion_words`



---

### `__dybatpho_cli_generate_completion_command`



---

### `__dybatpho_cli_help_pad`

Pad string $2 to at least length $3 and store result in variable $1

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name to store result |
| `$2` | string | String to pad |
| `$3` | number | Minimum length |


---

### `__dybatpho_cli_help_sw`

Append a formatted switch to caller-local variable `sw`.
Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so
that short+long pairs align as "-s, --long".

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Minimum pad width before appending $2 |
| `$2` | string | Switch string to append |


---

### `__dybatpho_cli_help_row`

Build one help row and print it as a record for later rendering.
Rendering is deferred because the column width is only known once
every row of every section has been collected.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type: flag \| param \| disp \| cmd |
| `$2` | string | Variable name (or command name for cmd type) |
| `$3` | string | Description |
| `$@` | switch\|key:value | Switches and settings of this option |

**📤 Output on stdout**

- Record of `label<TAB>description<TAB>annotations`, where annotations
        are separated by a unit separator. Nothing for a hidden row.


---

### `__dybatpho_cli_help_add_switch`

Sort one declared switch into the caller-local `_short_forms` and
`_long_forms` buffers, expanding bracketed and `negatable:true`
forms on the way.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | switch | Declared switch |
| `$2` | bool | Whether the owning option is negatable |


---

### `__dybatpho_cli_help_annotate`

Append a `[name: value]` annotation to a caller variable, or do
nothing when the value is empty.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable holding the annotation list |
| `$2` | string | Annotation name |
| `$3` | string | Annotation value |


---

### `__dybatpho_cli_help_default`

Render the literal default of an `init:` form, or nothing when
the default is empty, dynamic, or an `init:@...` directive that
has no value to show.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Raw `init:` value |

**📤 Output on stdout**

- Literal default value


---

### `__dybatpho_cli_help_render_rows`

Print every collected help row, aligned to a shared column.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Description column width |
| `$@` | string | Row records from `__dybatpho_cli_help_row` |

**📤 Output on stdout**

- Rendered rows


---

### `__dybatpho_cli_help_dedupe`

Drop rows whose label was already collected, keeping the first.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the array of row records to rewrite in place |


---

### `__dybatpho_cli_help_width_for`

Choose the description column width that fits every row, so the
Arguments, Commands, and Options sections line up with each other.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the width |
| `$@` | string | Row records from `__dybatpho_cli_help_row` |


---

### `__dybatpho_cli_add_switch`

Add to switches list if flag/param has multiple switches

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | switch | Switch |


---

### `__dybatpho_cli_suggest_suffix`

Build the `Did you mean ...` suffix appended to an unrecognized
option or command error. Called from generated parser code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Mistyped input |
| `$@` | string | Known candidates |

**📤 Output on stdout**

- Suggestion suffix, or nothing when no candidate is close enough

**🚦 Exit codes**

- 0


---

### `__dybatpho_cli_add_plain_switch`

Add a literal switch to the switches list, pairing a long switch
with its `--no-` form when the option is declared `negatable:true`.
Short switches and switches that already carry a negative prefix
are added unchanged.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | switch | Switch such as `-c` or `--color` |


---

### `__dybatpho_cli_expand_switch`

Expand one declared switch into the concrete switches a user can
type, honouring `--{no-}name`, `--with{out}-name`, and
`negatable:true`. Results are appended to a caller-provided array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of destination array variable |
| `$2` | switch | Declared switch |
| `$3` | bool | Whether the owning option is `negatable:true`, default `false` |


---

### `__dybatpho_cli_print_validate`

Emit generated code that validates the current `OPTARG` and assigns it to the destination variable.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Destination variable name, or `-` to skip assignment |

**📝 Notes**

- Uses caller-local `__validate` when a custom validator was configured for the current option

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_parse_alias_list`

Split a comma-separated alias list into a caller-provided array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of destination array variable |
| `$2` | string | Comma-separated aliases |

**🚦 Exit codes**

- `0`: Aliases appended to destination array


---

### `__dybatpho_cli_record_persistent_def`

Serialize an option definition so it can be replayed for persistent descendant commands.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option type (`flag`, `param`, or `disp`) |
| `$@` | string | Original arguments passed to the option helper |

**🚦 Exit codes**

- `0`: Definition stored for later replay


---

### `__dybatpho_cli_replay_persistent_defs`

Replay inherited persistent option definitions inside the current parser/help generation context.

_Function has no arguments._

**🚦 Exit codes**

- `0`: All inherited persistent definitions were replayed


---

### `__dybatpho_cli_print_persistent_help_defs`

Emit generated code that seeds persistent option definitions for nested help output.

_Function has no arguments._

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_print_known_candidates`

Emit generated code declaring the switches and command names the
current command accepts, used to suggest a close match when the
user mistypes one.

_Function has no arguments._

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_print_deprecated_warning`

Emit generated code that warns when a deprecated CLI item is used.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Item type label (`option` or `command`) |
| `$2` | string | Item label shown in the warning |
| `$3` | string | Deprecation message |

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_generate_child_logic`

Generate parser logic for a child command with inherited persistent option definitions.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Child spec function |
| `$2` | string | Child command name |
| `$@` | string | Original CLI arguments |

**📤 Output on stdout**

- Generated parser code


---

### `__dybatpho_cli_print_arg_bindings`

Emit generated code that copies the collected positional
arguments into the variables declared with `dybatpho::opts::arg`,
in declaration order. A `variadic:true` argument is the last one
and receives every remaining value as an array, so the values it
holds keep their boundaries.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the rest array holding the collected arguments |
| `$@` | string | Declared argument records of `required<TAB>variadic<TAB>varname` |

**📤 Output on stdout**

- Generated parser code

**🚦 Exit codes**

- `0`: Nothing is emitted when no argument was declared


---

### `__dybatpho_cli_print_args_check`

Emit generated code that validates the positional argument count configured by `args:<rule>` in `dybatpho::opts::setup`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Argument count rule (`none`, `exact:N`, `min:N`, `max:N`, `range:M:N`, `any`) |

**📤 Output on stdout**

- Generated parser code

**🚦 Exit codes**

- `0`: Rule accepted and code emitted


---

### `__dybatpho_cli_collect_switches`

Expand option switches and aliases into a caller-provided array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of destination array |
| `$@` | switch\|key:value | Option metadata |


---

### `__dybatpho_cli_json_quote`

Escape a value for JSON and store it in a caller variable.


---

### `__dybatpho_cli_collect_spec_metadata`

Collect option and command metadata from a CLI spec.


<a id="spec-functions"></a>
### 🧩 Spec functions

#### `dybatpho::opts::setup`

Functions work in spec of script or function via `dybatpho::generate_from_spec`.
Setup global settings for getting options (mandatory) in spec
of script or function

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Description of sub-command/root command |
| `$2` | string | Name of the array variable receiving positional arguments, or `-` to discard them |
| `$@` | key:value | Settings `key:value` for sub-command/root command such as `action:<code>`, `prerun:<code>`, `postrun:<code>`, and `args:<rule>` |

**📝 Notes**

- The rest variable is a Bash array. Read it as `"${REST[@]}"` to iterate and `"${#REST[@]}"` to count. An argument containing spaces, quotes, or newlines therefore survives parsing as one element.
- `args:<rule>` supports raw rules plus Cobra-like names such as `NoArgs`, `ExactArgs:N`, and `RangeArgs:M:N`
- `prerun:<code>` runs before `action:<code>`, and `postrun:<code>` runs after it

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::opts::flag`

Define an option that take no argument

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Description of option to display |
| `$2` | string | Variable name for getting option. `-` if want to omit |
| `$@` | switch\|key:value | Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>` |

**📝 Notes**

- Use `persistent:true` to make the flag available to descendant subcommands

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::opts::param`

Define an option that take an argument

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Description of option to display |
| `$2` | string | Variable name for getting option. `-` if want to omit |
| `$@` | switch\|key:value | Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>` |

**📝 Notes**

- Use `persistent:true` to make the param available to descendant subcommands

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::opts::disp`

Define an option that display only

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Description of option to display |
| `$@` | switch\|key:value | Other switches and settings `key:value` of this option, including `alias:<switch>` / `aliases:<a,b>` |

**📝 Notes**

- Use `persistent:true` to make the display option available to descendant subcommands

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::opts::msg`

Place a line of free text in the generated help, so a long option
list can be broken into labelled groups. It declares no switch and
affects nothing but help output.

**🧪 Example**

```bash
dybatpho::opts::msg "Connection options:"
dybatpho::opts::param "Host to reach" HOST --host
dybatpho::opts::msg ""
dybatpho::opts::msg "Output options:"
dybatpho::opts::flag "Colorize output" COLOR --color
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Message text, and optionally `hidden:<bool>` |

**📝 Notes**

- Completion, schema, and man output ignore messages, because none of them has a place for text that describes no option.

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::opts::cmd`

Define a sub-command in spec

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command name |
| `$2` | string | Name of function that has spec of sub-command |
| `$@` | key:value | Optional metadata such as `alias:<name>` or `aliases:<a,b>` |


---

### `dybatpho::opts::arg`

Declare a positional argument. Its value is assigned to the named
variable once parsing succeeds, and it also gives the usage line a
real placeholder and the generated help, schema, and man page an
`Arguments` section. Every value still lands in the rest array
named by `dybatpho::opts::setup` as well.

**🧪 Example**

```bash
dybatpho::opts::arg "File to read" SOURCE
dybatpho::opts::arg "Where to write it" TARGET required:false
dybatpho::opts::arg "Extra files" EXTRA required:false variadic:true

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Description of the argument |
| `$2` | string | Placeholder name, shown uppercase in usage and help |
| `$@` | key:value | Settings: `required:<bool>` (default `true`) and `variadic:<bool>` (default `false`) |

**📝 Notes**

- Arguments bind in declaration order. A `variadic:true` argument is an array holding every remaining value; the others are strings, and an omitted optional argument is the empty string. Pass `-` as the variable name to document an argument without binding it.
- When `dybatpho::opts::setup` declares no `args:<rule>`, the rule is derived from the declared arguments, so the count is validated without stating it twice.

**🚦 Exit codes**

- `0`: exit code


---

### `__dybatpho_cli_arg_placeholder`

Render a positional argument the way usage lines conventionally
do: angle brackets when it is required, square brackets when it
is optional, and a trailing ellipsis when it is variadic.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Placeholder name |
| `$2` | bool | Whether the argument is required |
| `$3` | bool | Whether the argument is variadic |

**📤 Output on stdout**

- Rendered placeholder


---

### `__dybatpho_cli_derive_args_rule`

Derive the `args:<rule>` a command would need to accept exactly
the positional arguments it declared with `dybatpho::opts::arg`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of the variable receiving the rule |
| `$@` | string | Declared argument records of `required<TAB>variadic` |

**🚦 Exit codes**

- `0`: The variable is left untouched when nothing was declared


<a id="parse-functions"></a>
### 🧩 Parse functions

#### `dybatpho::generate_from_spec`

Functions to parse spec and put value of options to variable with corresponding name
Define spec of parent function or script, spec contains below commands

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of function that has spec of parent function or script |

**🚦 Exit codes**

- `0`: exit code


---

### `dybatpho::generate_help`

Show help description of root command/sub-command.
Declares help state as locals so dybatpho::opts::* in the call
chain can read/write them via bash dynamic scoping.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of function that has spec of parent function or script |

**📤 Output on stdout**

- Help description
