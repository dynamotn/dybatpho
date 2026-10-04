# shellcheck shell=bash
# This file sourced by `init.sh` and never run, so it carries no executable bit
# and installs no handlers of its own. It is also the parser itself: its
# helpers read the spec positionally, the state that builds one spec is shared
# across the calls that declare it, and `eval` is how a declared spec becomes a
# parser — so the rules that ask for `dybatpho::expect_args`, `local` and a
# `_spec_*` function describe its callers rather than this file. The public
# `dybatpho::opts::*` names carry a second namespace level that the
# function-name rule does not allow and that callers depend on. What is left
# over the line limit here is the parser it emits: a generated line is written
# as one string so that the code it produces reads the way it runs, and the
# error paths carry a `# kcov(skip)` marker that has to stay on the line it
# marks.
# dyshellint disable=BSG050,BSG011,BSG040,BSG051,BSG003,BSG070
# @file cli.sh
# @brief Utilities for building CLI parsers from shell specs.
# @namespace dybatpho
# @description
#   `src/cli.sh` lets you describe a command with shell functions, then generate:
#
#   - option parsing
#   - subcommand dispatch
#   - help output
#   - validation and error handling
#   - automatic `--help` / `-h` for commands that do not define their own help option
# @usage
#   ### Basic workflow
#
#   1. Write a spec function.
#   2. Call `dybatpho::opts::setup` once inside that spec.
#   3. Define flags, params, display options, and subcommands.
#   4. Call `dybatpho::generate_from_spec <spec> "$@"`.
#   5. Optionally expose `--help` with `dybatpho::generate_help <spec>`.
#
#   #### Minimal example
#
#   ```bash
#   function _run {
#     dybatpho::print "Hello, ${NAME}!"
#     exit 0
#   }
#
#   function _spec {
#     dybatpho::opts::setup "A minimal greeter CLI" ARGS action:"_run"
#     dybatpho::opts::param "Your name" NAME -n --name required:true
#     dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
#   }
#
#   dybatpho::generate_from_spec _spec "$@"
#   ```
#
#   ### Spec argument types
#
#   Functions in this module accept two kinds of extra arguments:
#
#   | Type | Description |
#   | ---- | ----------- |
#   | `switch` | Option switch such as `-f`, `--flag`, `--{no-}flag`, `--with{out}-feature` |
#   | `key:value` | Attribute in `name:value` form |
#
#   ### Supported switch forms
#
#   | Form | Meaning |
#   | ---- | ------- |
#   | `-x` | short option |
#   | `--name` | long option |
#   | `--{no-}name` | expands to `--name` and `--no-name` |
#   | `--with{out}-name` | expands to `--with-name` and `--without-name` |
#
#   ### Shared attributes
#
#   These attributes are parsed by `dybatpho::opts::flag` and/or `dybatpho::opts::param`.
#
#   | Attribute | Applies to | Description |
#   | --------- | ---------- | ----------- |
#   | `action:<code>` | `setup`, `disp` | Code to run when parsing finishes or a display option is used |
#   | `prerun:<code>` | `setup` | Code to run after validation and before `action:<code>` |
#   | `postrun:<code>` | `setup` | Code to run after `action:<code>` |
#   | `args:<rule>` | `setup` | Positional argument rule: `none`, `exact:N`, `min:N`, `max:N`, or `range:M:N` |
#   | `abbr:<bool>` | `setup` | Accept an unambiguous prefix of a long switch, such as `--vers` for `--version` |
#   | `alias:<name>` | `flag`, `param`, `disp`, `cmd` | Add one alias switch or command name |
#   | `aliases:<a,b>` | `flag`, `param`, `disp`, `cmd` | Add multiple aliases separated by commas |
#   | `init:<value>` | `flag`, `param` | Initial variable value |
#   | `on:<string>` | `flag`, `param` | Positive value when the option is enabled |
#   | `off:<string>` | `flag`, `param` | Negative value when the option is disabled or absent |
#   | `persistent:<bool>` | `flag`, `param`, `disp` | Make the option available in descendant subcommands |
#   | `export:<bool>` | `flag`, `param` | Export the variable |
#   | `env:<NAME>` | `flag`, `param` | Use environment variable `NAME` as the option's initial value |
#   | `config:<key>` | `flag`, `param` | Initial value from configuration key `key`, under `env:`, over `init:` |
#   | `negatable:<bool>` | `flag` | Also accept a generated `--no-<name>` for every long switch |
#   | `count:<bool>` | `flag` | Count repeats instead of storing a value, so `-vv` yields `2` |
#   | `optional:<bool>` | `param` | Whether the option value is optional when the switch appears |
#   | `required:<bool>` | `param` | Whether the option itself must appear |
#   | `prompt:<text>` | `param` | Prompt for a missing value with the supplied text |
#   | `choices:<a,b>` | `param` | Restrict values to a comma-separated list of choices |
#   | `multiple:<bool>` | `param` | Append repeats instead of replacing; selection takes lists and ranges (`1-3`) |
#   | `pattern:<glob>` | `flag`, `param` | Restrict values to a `case` glob such as `fast|slow` |
#   | `type:<name>` | `flag`, `param` | Restrict values to a `validate` type such as `email`, `port`, or `file` |
#   | `validate:<code>` | `flag`, `param` | Validation logic using `\$OPTARG` |
#   | `deprecated:<text>` | `flag`, `param`, `disp`, `cmd` | Warn when the item is used and annotate it in help |
#   | `error:<code>` | `flag`, `param`, `setup` | Custom error handler |
#   | `hidden:<bool>` | help output | Hide the row from generated help |
#   | `label:<string>` | help output | Override the label shown in generated help |
#
#   ### `init:` forms
#
#   | Form | Description |
#   | ---- | ----------- |
#   | `init:@empty` | Initialize with empty string |
#   | `init:@on` | Initialize with the current `on:` value |
#   | `init:@off` | Initialize with the current `off:` value |
#   | `init:@unset` | Unset the variable |
#   | `init:@keep` | Keep the current variable value |
#   | `init:action:<code>` | Run code without assignment |
#   | `init:=<code>` | Assign the raw shell expression |
#
#   ### Positional argument rules
#
#   Use `args:<rule>` in `dybatpho::opts::setup` to validate positional arguments
#   the same way Cobra-style commands often do.
#
#   | Rule | Meaning |
#   | ---- | ------- |
#   | `args:none` | Reject all positional arguments |
#   | `args:exact:2` | Require exactly 2 positional arguments |
#   | `args:min:1` | Require at least 1 positional argument |
#   | `args:max:3` | Allow at most 3 positional arguments |
#   | `args:range:1:2` | Require between 1 and 2 positional arguments |
#
#   ### Parsing and dispatch
#
#   `dybatpho::generate_from_spec` generates and runs parser logic from a spec. It:
#
#   - initializes variables from the spec
#   - parses switches and arguments
#   - counts positional arguments for `args:` rules
#   - validates input
#   - dispatches subcommands
#   - runs the `action:` from `dybatpho::opts::setup`
#
#   ### Positional arguments
#
#   The second argument to `dybatpho::opts::setup` names a **Bash array** that
#   collects everything which is not a switch:
#
#   ```bash
#   function _spec {
#     dybatpho::opts::setup "Copy files" FILES action:"_run"
#   }
#
#   function _run {
#     dybatpho::print "Got ${#FILES[@]} file(s)"
#     for file in "${FILES[@]}"; do dybatpho::print "- ${file}"; done
#   }
#   ```
#
#   An array is what keeps `tool "my report.pdf" notes.txt` two arguments rather
#   than three, and keeps quotes, glob characters, and newlines inside a value
#   untouched. Read it with `"${FILES[@]}"`; `"${#FILES[@]}"` is the count.
#
#   Bash cannot export an array, so `export:` has nothing to say about the rest
#   variable. Note that under `set -u` a scalar read such as `${FILES}` fails on
#   an empty array rather than expanding to the empty string.
#
#   ### Help generation
#
#   `dybatpho::generate_help` renders the layout a conventional command-line
#   tool uses:
#
#   ```text
#   Usage: deploy-tool deploy [OPTIONS] <SERVICE> [TARGETS]...
#
#   Deploy selected components
#
#   Arguments:
#     <SERVICE>                       Service to deploy
#     [TARGETS]...                    Extra targets
#
#   Commands:
#     rollback                        Undo the last deploy
#
#   Options:
#     -e, --environment <DEPLOY_ENV>  Target environment (required)
#                                     [env: DEPLOY_ENV]
#                                     [config: deploy.environment]
#                                     [choices: staging, production]
#                                     [default: staging]
#     -h, --help                      Show this help
#
#   Run 'deploy-tool COMMAND --help' for more information on a command.
#   ```
#
#   It automatically handles:
#
#   - a usage line that names `COMMAND` only when there are subcommands, and
#     shows the arguments declared with `dybatpho::opts::arg`
#   - description from `dybatpho::opts::setup`
#   - argument, command, and option rows aligned to one shared column
#   - the `-h, --help` row every command gets for free
#   - current subcommand path
#   - automatic `(required)` suffix for `required:true` params
#   - `[env: ...]`, `[config: ...]`, `[choices: ...]`, `[pattern: ...]`, `[type: ...]`, `[default: ...]`,
#     `[repeatable]`, and `[repeat to increase]` annotations, each on its own
#     line under the description
#
#   A `[default: ...]` annotation is only shown for a literal `init:` value. A
#   default built from a command substitution or a variable is resolved at run
#   time, so printing the expression would mislead more than it helps.
#
#   By default:
#
#   - `flag` rows show switches only
#   - `param` rows show switches plus `<VARNAME>`
#   - `disp` rows show switches only
#   - `cmd` rows show the command name
#
#   You can override the rendered label with `label:<string>`.
#
#   Commands automatically accept `--help` and `-h` unless the spec defines a
#   help display option itself. Define a custom display option when the command
#   needs a different help action or aliases.
#
#   ### Common patterns
#
#   #### Required positional-like option
#
#   ```bash
#   function _run {
#     dybatpho::print "Hello, ${NAME}"
#     exit 0
#   }
#
#   function _spec {
#     dybatpho::opts::setup "Greeter" -
#     dybatpho::opts::param "Your name" NAME --name required:true
#     dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
#   }
#   ```
#
#   #### Exact positional args
#
#   ```bash
#   function _spec_sum {
#     dybatpho::opts::setup "Add two numbers" SUM_ARGS args:exact:2 action:"_run_sum"
#   }
#   ```
#
#   #### Aliases
#
#   ```bash
#   dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
#   dybatpho::opts::cmd config _spec_config alias:cfg aliases:conf,settings
#   ```
#
#   #### Persistent parent options
#
#   ```bash
#   function _spec_root {
#     dybatpho::opts::setup "Root command" -
#     dybatpho::opts::flag "Verbose output" VERBOSE --verbose persistent:true
#     dybatpho::opts::cmd deploy _spec_deploy
#   }
#   ```
#
#   #### Hidden and deprecated items
#
#   ```bash
#   dybatpho::opts::flag "Legacy flag" LEGACY --legacy hidden:true
#   dybatpho::opts::cmd old-run _spec_old deprecated:"Use 'run' instead"
#   ```
#
#   #### PreRun / PostRun hooks
#
#   ```bash
#   function _spec_run {
#     dybatpho::opts::setup "Run command" - prerun:"echo pre" action:"echo main" postrun:"echo post"
#   }
#   ```
#
#   #### Boolean toggle
#
#   ```bash
#   dybatpho::opts::flag "Color output" COLOR --{no-}color on:true off:false init:="true"
#   ```
#
#   `negatable:true` generates the negative switch instead of spelling both out.
#   Without an explicit `off:`, a negatable flag turns off to `false` rather
#   than to the empty string, so `--no-color` lands on a value worth testing:
#
#   ```bash
#   dybatpho::opts::flag "Color output" COLOR --color negatable:true init:="true"
#   # accepts --color and --no-color; aliases get their own --no- form too
#   ```
#
#   #### Counting verbosity
#
#   A `count:true` flag records how often it appeared instead of storing a
#   value, so `-v`, `-vv`, and `-v -v` yield `1`, `2`, and `2`. It starts at `0`
#   unless `init:` says otherwise.
#
#   ```bash
#   dybatpho::opts::flag "Increase verbosity" VERBOSITY -v alias:--verbose count:true
#
#   function _run {
#     dybatpho::cli_apply_verbosity "${VERBOSITY}" # info -> debug -> trace
#   }
#   ```
#
#   #### Binding an option to a configuration key
#
#   `config:<key>` reads the key from the configuration `src/config.sh` loaded,
#   giving one precedence chain across the whole CLI:
#
#   **flag > `env:` > `config:` > `init:`**
#
#   ```bash
#   . dybatpho/init.sh --modules cli config
#   dybatpho::config_load ./app.yaml          # before generate_from_spec
#
#   function _spec {
#     dybatpho::opts::setup "Serve" ARGS action:"_run"
#     dybatpho::opts::param "Port to listen on" PORT --port \
#       env:APP_PORT config:server.port init:="8080"
#   }
#   ```
#
#   The configuration has to be loaded before `dybatpho::generate_from_spec`,
#   because that is when the parser resolves an option's initial value. A key
#   that is absent, or a CLI that never loaded any configuration at all, simply
#   falls through to `init:`. `cli` does not load the `config` module itself,
#   so a script that binds options this way asks for it:
#   `--modules cli config`.
#
#   #### Named positional arguments
#
#   ```bash
#   function _spec {
#     dybatpho::opts::setup "Copy a file" ARGS action:"_run"
#     dybatpho::opts::arg "File to read" SOURCE
#     dybatpho::opts::arg "Where to write it" TARGET required:false
#     dybatpho::opts::arg "Anything else" EXTRA required:false variadic:true
#   }
#   # Usage: tool [OPTIONS] <SOURCE> [TARGET] [EXTRA]...
#
#   function _run {
#     dybatpho::print "${SOURCE} -> ${TARGET}"
#     dybatpho::print "plus ${#EXTRA[@]} more"
#   }
#   ```
#
#   Each argument is assigned to its variable in declaration order once the
#   count check passes, so an action reads `${SOURCE}` rather than picking the
#   value out of the rest array by index. A `variadic:true` argument comes last
#   and is an array of everything remaining; an omitted optional argument is the
#   empty string. Use `-` as the variable name to document an argument without
#   binding it.
#
#   Declaring arguments also derives the `args:<rule>` count check, so the two
#   never disagree. State `args:` explicitly to override the derived rule.
#
#   #### Abbreviating long options
#
#   `abbr:true` on `dybatpho::opts::setup` lets a long switch be typed as any
#   prefix that identifies it uniquely. It is off by default, because turning it
#   on means every new option can make a previously working abbreviation
#   ambiguous.
#
#   ```bash
#   dybatpho::opts::setup "Tool" ARGS abbr:true action:"_run"
#   dybatpho::opts::flag "Colorize output" COLOR --color
#   dybatpho::opts::param "Configuration file" CONFIG --config
#   # --colo works, --config works, --co is ambiguous
#   ```
#
#   An exact match always wins, so declaring both `--log` and `--log-level`
#   keeps `--log` usable. A prefix matching more than one switch fails with
#   `Ambiguous option: --co (matches --color, --config)`, translated under the
#   key `cli.ambiguous_option`; the `error:` handler sees the error name
#   `ambiguous` with the candidates in `$OPTARG`. A prefix matching nothing is
#   reported as an unrecognized option, suggestion included.
#
#   #### Restricting values to a pattern
#
#   `type:` names a check the `validate` module already owns — `email`,
#   `port`, `ipv4`, `semver`, `file`, or anything registered with
#   `dybatpho::validate_register` — so the common cases need neither a glob nor
#   a validator function, and a rejected value is described the same way it
#   would be in a configuration file. A spec naming a type that does not exist
#   fails when the parser is generated rather than when a user first types a
#   value.
#
#   `pattern:` takes a `case` glob, which covers the common checks without a
#   helper function. `choices:` is still the better fit for a fixed list, since
#   it also feeds completion and the `[choices: ...]` help annotation.
#
#   ```bash
#   dybatpho::opts::param "Mode" MODE --mode pattern:'fast|slow'
#   dybatpho::opts::param "Port" PORT --port pattern:'[0-9]*'
#   dybatpho::opts::param "Port" PORT --port type:port
#   dybatpho::opts::param "Contact" EMAIL --email type:email
#   ```
#
#   A value that does not match fails with
#   `Does not match the pattern (fast|slow): medium`, translated under the key
#   `cli.pattern_mismatch`, and the `error:` handler sees the error name
#   `pattern:<glob>`.
#
#   A pattern reaches the generated parser unquoted, because quoting it would
#   make `case` compare it literally. It is therefore restricted to characters
#   that cannot end a `case` branch or start a substitution, and a pattern
#   outside that set is rejected when the parser is generated.
#
#   #### Grouping options in help
#
#   `dybatpho::opts::msg` puts a line of free text in the help output, which is
#   what a long option list needs to stay readable. It declares no switch, and
#   completion, schema, and man output ignore it.
#
#   ```bash
#   dybatpho::opts::msg "Connection options:"
#   dybatpho::opts::param "Host to reach" HOST --host
#   dybatpho::opts::msg ""
#   dybatpho::opts::msg "Output options:"
#   dybatpho::opts::flag "Colorize output" COLOR --color
#   ```
#
#   #### Validation
#
#   ```bash
#   _validate_port() {
#     [[ "${1}" =~ ^[0-9]+$ ]] && [ "${1}" -ge 1 ] && [ "${1}" -le 65535 ]
#   }
#
#   dybatpho::opts::param "Port" PORT --port validate:"_validate_port \$OPTARG"
#   ```
#
#   #### Subcommand tree
#
#   ```bash
#   function _spec_root {
#     dybatpho::opts::setup "Tool root" ROOT_ARGS action:"dybatpho::generate_help _spec_root"
#     dybatpho::opts::cmd user _spec_user
#     dybatpho::opts::cmd config _spec_config
#   }
#
#   function _spec_user {
#     dybatpho::opts::setup "User commands" USER_ARGS action:"dybatpho::generate_help _spec_user"
#     dybatpho::opts::cmd add _spec_user_add
#   }
#   ```
#
#   ### Error messages
#
#   The parser reports these standard errors:
#
#   - `Unrecognized option: ...`
#   - `Does not allow an argument: ...`
#   - `Requires an argument: ...`
#   - `Missing required option: ...`
#   - `Expected ... arguments, got ...`
#   - `Invalid command: ...`
#   - `Validation error (...): ...`
#
#   `Unrecognized option` and `Invalid command` carry a suggestion when the
#   input is close to something the command accepts, compared by Levenshtein
#   distance with leading dashes ignored:
#
#   ```text
#   Unrecognized option: --colr. Did you mean '--color'?
#   Invalid command: depoy. Did you mean 'deploy'?
#   ```
#
#   A command that declares at least one switch rejects any unmatched `-x` or
#   `--xy` rather than collecting it as a positional argument. Use `--` to pass
#   dashed values through. A command that declares no switches at all is a
#   passthrough wrapper and keeps collecting them.
#
#   ### Debugging
#
#   Set `DYBATPHO_CLI_DEBUG=true` to print the generated parser script.
#
#   ```bash
#   DYBATPHO_CLI_DEBUG=true bash example/cli_basic.sh --help
#   ```
#
#   This is useful when debugging:
#
#   - dispatch flow
#   - generated actions
#   - switch matching
#   - help generation
#
#   ### Advanced UX example
#
#   `example/cli_ux.sh` is a complete spec-driven CLI example:
#
#   - `_spec_root` declares the root command, a persistent `count:true` verbosity
#     flag, plus `deploy`, `completion`, `schema`, and `man` subcommands.
#   - `_spec_deploy` demonstrates `arg`, `env:`, `config:`, `choices:`,
#     `prompt:`, `multiple:`, `negatable:`, and boolean toggles.
#   - `_spec_completion`, `_spec_schema`, and `_spec_man` define the artifact subcommands.
#   - `_run_root`, `_run_completion`, `_run_schema`, and `_run_man` implement their actions.
#   - `_run_deploy` consumes the parsed values and performs the deploy action.
#
#   Run it with:
#
#   ```bash
#   bash example/cli_ux.sh deploy --component api api
#   bash example/cli_ux.sh deploy -vv --no-color --component api api
#   bash example/cli_ux.sh depoy                      # suggests 'deploy'
#   bash example/cli_ux.sh completion --shell bash
#   bash example/cli_ux.sh schema
#   bash example/cli_ux.sh man
#   ```
#
#   ### Completion cache
#
#   `dybatpho::generate_completion` caches its output under
#   `DYBATPHO_CLI_CACHE_DIR`, so a shell startup that sources a generated
#   completion does not walk the whole spec tree again. The cache key hashes the
#   script that declares the spec, so editing that script invalidates the entry
#   by itself and there is nothing to clear by hand. Set
#   `DYBATPHO_CLI_CACHE=false` to regenerate every time, and note that a spec
#   declared somewhere with no readable source file is never cached.
#
# @see
#   - `example/cli_basic.sh`
#   - `example/cli_advanced.sh`
#   - `example/cli_ux.sh`
# @tip Set `DYBATPHO_CLI_DEBUG=true` while developing a spec to inspect the generated parser and help logic.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CLI_DEBUG bool Set to `true` to dump generated parser details while developing specs
DYBATPHO_CLI_DEBUG="${DYBATPHO_CLI_DEBUG:-false}"
# @env DYBATPHO_CLI_CACHE bool Set to `false` to regenerate completion output instead of reusing the cached copy.
#   Default
#   is `true`
DYBATPHO_CLI_CACHE="${DYBATPHO_CLI_CACHE:-true}"
# @env DYBATPHO_CLI_CACHE_DIR string Directory holding cached completion output. Default is
#   `${XDG_CACHE_HOME:-$HOME/.cache}/dybatpho/cli`
DYBATPHO_CLI_CACHE_DIR="${DYBATPHO_CLI_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/dybatpho/cli}"

# Label marking a help row as free text from `dybatpho::opts::msg`. `\x02` is a
# control character, so it cannot collide with a switch, a command name, or a
# `label:` a spec might set.
[[ -n "${__DYBATPHO_CLI_MSG_LABEL-}" ]] || readonly __DYBATPHO_CLI_MSG_LABEL=$'\x02msg'

# Field separator of the spec metadata records the generators read back. Not a
# tab: a tab is whitespace to `read`, which merges a run of them into one, so an
# empty field (a description of "") moved every later field one place left. The
# unit separator is not whitespace, so `read` keeps empty fields where they are,
# and it cannot occur in a description or a switch a spec writes.
[[ -n "${__DYBATPHO_CLI_META_SEP-}" ]] || readonly __DYBATPHO_CLI_META_SEP=$'\x1f'

#######################################
# @description Read a line from the terminal (or stdin) with an optional default.
# @arg $1 string Prompt text
# @arg $2 string Optional default value
# @tip The prompt is written to stderr so the returned value remains clean on stdout.
# @stdout Entered value
# @exitcode 0
#######################################
function dybatpho::prompt {
  local prompt="${1:-}" default="${2:-}" value
  printf "%s" "${prompt}" >&2
  [[ -n "${default}" ]] && printf " [%s]" "${default}" >&2
  printf ": " >&2
  IFS= read -r value || return 1
  [[ -n "${value}" ]] || value="${default}"
  printf "%s" "${value}"
}

#######################################
# @description Prompt for one or more values from a comma-separated list or numeric range.
# @arg $1 string Prompt text
# @arg $2 string Comma-separated choices
# @arg $3 bool Allow multiple selections
# @tip Pass `true` for the third argument to accept comma-separated values and numeric ranges such as `1-3`.
# @tip Invalid or out-of-range selections are rejected and prompt again.
# @stdout Selected value(s), separated by spaces
# @exitcode 0
#######################################
function dybatpho::select {
  local prompt="${1:-}" choices="${2:-}" multiple="${3:-false}"
  local -a items=() selected=()
  local entry answer index
  IFS=',' read -r -a items <<< "${choices}"
  printf "%s\n" "${prompt}" >&2
  for index in "${!items[@]}"; do
    printf "  %d) %s\n" "$((index + 1))" "${items[index]}" >&2
  done
  while :; do
    local selection_prompt
    selection_prompt="$(__dybatpho_log_text cli.select "Select")"
    dybatpho::is true "${multiple}" \
      && selection_prompt+="$(__dybatpho_log_text cli.select_multiple \
        " (comma-separated or ranges, e.g. 1-3)")"
    answer="$(dybatpho::prompt "${selection_prompt}")" || return 1
    selected=()
    local -a answers=()
    IFS=',' read -r -a answers <<< "${answer}"
    local token range_start range_end range_index
    for token in "${answers[@]}"; do
      if [[ "${token}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        range_start="${BASH_REMATCH[1]}"
        range_end="${BASH_REMATCH[2]}"
        if dybatpho::is false "${multiple}"; then
          continue
        fi
        if ((range_start < 1 || range_end > ${#items[@]} || range_start > range_end)); then
          continue
        fi
        for ((range_index = range_start; range_index <= range_end; range_index++)); do
          selected+=("${items[$((range_index - 1))]}")
        done
      elif [[ "${token}" =~ ^[0-9]+$ ]] && [[ "${token}" -ge 1 ]] && [[ "${token}" -le "${#items[@]}" ]]; then
        selected+=("${items[$((token - 1))]}")
      else
        for entry in "${items[@]}"; do
          [[ "${token}" = "${entry}" ]] && selected+=("${entry}") && break
        done
      fi
    done
    [[ "${#selected[@]}" -gt 0 ]] || {
      dybatpho::warn "Choose a valid selection."
      continue
    }
    if dybatpho::is false "${multiple}"; then
      [[ "${#selected[@]}" -eq 1 ]] || {
        dybatpho::warn "Choose one selection."
        continue
      }
    fi
    printf "%s" "${selected[*]}"
    return 0
  done
}

#######################################
# @description Check that a value belongs to a comma-separated choice list.
# @arg $1 string Value
# @arg $2 string Comma-separated choices
# @exitcode 0 Value is allowed
#######################################
function dybatpho::opts::validate_choice {
  local value="${1-}" choices="${2-}" choice
  IFS=',' read -r -a __choice_items <<< "${choices}"
  for choice in "${__choice_items[@]}"; do
    [[ "${value}" = "${choice}" ]] && return 0
  done
  return 1
}

#######################################
# @description Compute the Levenshtein edit distance between two strings.
#   Kept for existing callers; it answers exactly as
#   `dybatpho::string_distance`, which it delegates to.
# @example
#   distance="$(dybatpho::cli_levenshtein color colour)"
#
# @arg $1 string First string
# @arg $2 string Second string
# @stdout Edit distance as a decimal number
# @exitcode 0
# @see
#   - `dybatpho::string_distance`
#######################################
function dybatpho::cli_levenshtein {
  dybatpho::string_distance "${1-}" "${2-}"
}

#######################################
# @description Print the candidates closest to a mistyped switch or command name.
#              Leading dashes are ignored while comparing, so `--colr` still
#              matches `--color`, and a candidate that shares a prefix with the
#              input always wins over a pure edit-distance match.
# @example
#   dybatpho::cli_suggest --colr --color --cold --verbose
#
# @arg $1 string Mistyped input
# @arg $@ string Known candidates
# @stdout Up to three closest candidates, one per line
# @exitcode 0 At least one close candidate was found
# @exitcode 1 Nothing was close enough to suggest
#######################################
function dybatpho::cli_suggest {
  local input="${1-}"
  shift || true
  local candidate plain lowered_input lowered_candidate entry
  local -i threshold=2 best=-1 distance emitted=0 entry_distance
  local stripped="${input#--}"
  stripped="${stripped#-}"
  ((${#stripped} < 2)) && return 1
  ((${#stripped} > 5)) && threshold=3
  lowered_input="$(dybatpho::lower "${stripped}")"
  local -a seen=() scored=()
  for candidate in "$@"; do
    [[ -n "${candidate}" ]] || continue
    [[ "${candidate}" = "${input}" ]] && continue
    [[ " ${seen[*]-} " == *" ${candidate} "* ]] && continue
    seen+=("${candidate}")
    plain="${candidate#--}"
    plain="${plain#-}"
    lowered_candidate="$(dybatpho::lower "${plain}")"
    # Typing a prefix of a longer switch is an abbreviation, not a typo, so it
    # outranks every edit-distance match. The reverse is not true: `-e` is a
    # prefix of `--enviroment` without being a plausible correction for it.
    if [[ "${lowered_candidate}" == "${lowered_input}"* ]]; then
      distance=0
    else
      __dybatpho_string_distance_into distance "${lowered_input}" "${lowered_candidate}"
    fi
    ((distance > threshold)) && continue
    if ((best < 0 || distance < best)); then best=${distance}; fi
    scored+=("${distance} ${candidate}")
  done
  ((best < 0)) && return 1
  for entry in "${scored[@]}"; do
    entry_distance="${entry%% *}"
    ((entry_distance == best)) || continue
    printf '%s\n' "${entry#* }"
    emitted+=1
    ((emitted >= 3)) && break
  done
  return 0
}

#######################################
# @description Raise a log level by the number of times a counting `-v` flag was repeated.
# @example
#   LOG_LEVEL="$(dybatpho::cli_verbosity_level 2)" # info -> trace
#
# @arg $1 number Repeat count, default `0`
# @arg $2 string Base level, default `LOG_LEVEL`
# @stdout Resulting log level, capped at `trace`
# @exitcode 0
#######################################
function dybatpho::cli_verbosity_level {
  local -i count="${1:-0}" index=3 position
  local base
  base="$(dybatpho::lower "${2:-${LOG_LEVEL:-info}}")"
  local -a ladder=(fatal error warn info debug trace)
  for position in "${!ladder[@]}"; do
    [[ "${ladder[position]}" = "${base}" ]] && index=${position} && break
  done
  ((count < 0)) && count=0
  index=$((index + count))
  ((index > 5)) && index=5
  printf '%s\n' "${ladder[index]}"
}

#######################################
# @description Apply a repeat count from a counting `-v` flag to `LOG_LEVEL`.
# @example
#   dybatpho::opts::flag "Increase verbosity" VERBOSITY -v alias:--verbose count:true
#   # then, from the command action or a prerun hook:
#   dybatpho::cli_apply_verbosity "${VERBOSITY}"
#
# @arg $1 number Repeat count, default `0`
# @arg $2 string Base level, default `LOG_LEVEL`
# @set LOG_LEVEL string Raised log level
# @exitcode 0
#######################################
function dybatpho::cli_apply_verbosity {
  LOG_LEVEL="$(dybatpho::cli_verbosity_level "${1:-0}" "${2:-${LOG_LEVEL:-info}}")"
  export LOG_LEVEL
}

# @section Internal functions
# @description Functions are triggered by `dybatpho::generate_from_spec`

#######################################
# @description Read a key bound with `config:<key>` out of the configuration
#              loaded by `src/config.sh`. Missing keys and an unloaded config
#              module both report failure so the generated parser falls through
#              to the option's declared default.
#
#              `cli` does not load `config`: only this lookup touches it, and
#              registering it as a dependency would load it into every script
#              that parses an option. The guard is what makes that safe. With
#              `config` absent, `DYBATPHO_CONFIG` is not an associative array,
#              and testing a key such as `server.port` against it would be
#              read as arithmetic and stop the script. It names an internal
#              helper on purpose: `dybatpho::` functions are exported and a
#              child shell inherits them without the internals they call.
# @arg $1 string Configuration key
# @stdout Configuration value
# @exitcode 0 The key is present
# @exitcode 1 The key is absent, or no configuration has been loaded
# @internal
#######################################
function __dybatpho_cli_config_get {
  local key="${1-}"
  [[ -n "${key}" ]] || return 1
  declare -F __dybatpho_config_set > /dev/null || return 1
  [[ -v "DYBATPHO_CONFIG[${key}]" ]] || return 1
  printf '%s' "${DYBATPHO_CONFIG[${key}]}"
}

#######################################
# @description Record one switch of an option on the first pass over its spec:
#   the long switch becomes the label shown in help unless a long one is
#   already there, and a short one joins the cluster of short flags or
#   parameters the parser accepts.
#   `alias:`, each name in `aliases:`, and a bare switch all go through here,
#   so the three spellings of the same switch cannot drift apart.
# @arg $1 bool Whether the option takes an argument
# @arg $2 string Switch, such as `-v` or `--verbose`
# @exitcode 1 Stop the script when the switch is neither `-x` nor `--name`
# @internal
#######################################
function __dybatpho_cli_label_switch {
  case $2 in
    --*)
      if [[ -z "${__label}" ]] || [[ "${__label#--}" == "${__label}" ]]; then
        __label="$2"
      fi
      ;;
    -?)
      [[ -n "${__label}" ]] || __label="$2"
      if dybatpho::is true "$1"; then
        __params="${__params}${2#-}"
      else
        __flags="${__flags}${2#-}"
      fi
      ;;
    *)
      local __switch_error # kcov(skip)
      __switch_error=$(__dybatpho_log_text cli.invalid_switch_alias \
        "Invalid switch alias: $2" "alias=$2") # kcov(skip)
      dybatpho::die "${__switch_error}"        # kcov(skip)
      ;;
  esac
}

#######################################
# @description Add one switch of an option to the `case` pattern the generated
#   parser matches, on the second pass over its spec. `--{no-}name` expands to
#   `--name` and `--no-name`, and `--with{out}-name` to `--with-name` and
#   `--without-name`.
#   `alias:`, each name in `aliases:`, and a bare switch all go through here,
#   so the three spellings of the same switch cannot drift apart.
# @arg $1 string Switch, such as `-v`, `--verbose` or `--{no-}color`
# @exitcode 1 Stop the script when the switch is neither `-x` nor `--name`
# @internal
#######################################
function __dybatpho_cli_case_switch {
  local __switch_name
  case $1 in
    --\{no-\}*)
      __switch_name=${1#--?no-?}
      __dybatpho_cli_add_switch "'--${__switch_name}'|'--no-${__switch_name}'"
      ;;
    --with\{out\}-*)
      __switch_name=${1#--*-}
      __dybatpho_cli_add_switch "'--with-${__switch_name}'|'--without-${__switch_name}'"
      ;;
    -? | --*) __dybatpho_cli_add_plain_switch "$1" ;;
    *)
      local __switch_error # kcov(skip)
      __switch_error=$(__dybatpho_log_text cli.invalid_switch_alias \
        "Invalid switch alias: $1" "alias=$1") # kcov(skip)
      dybatpho::die "${__switch_error}"        # kcov(skip)
      ;;
  esac
}

#######################################
# @description Parse options with a spec from `dybatpho::opts::flag`,
#              `dybatpho::opts::param`
# @arg $1 bool Flag that defined option that take argument in spec
# @arg $2 number Count of non-option metadata args to skip after the mode flags
# @arg $@ string Passed arguments from `dybatpho::opts::(flag|param|disp)`
# @exitcode 0
# @internal
#######################################
function __dybatpho_cli_parse_opt {
  local need_argument=$1
  local skip_meta=$2
  shift 2

  # `negatable:` and `count:` change how the switches that precede them in the
  # argument list are expanded, so they are read before the ordered pass below.
  __negatable="false" __count="false"
  local __scan __has_explicit_off=false
  for __scan in "$@"; do
    case ${__scan} in
      negatable:*) __negatable="${__scan#negatable:}" ;;
      count:*) __count="${__scan#count:}" ;;
      off:*) __has_explicit_off=true ;;
      *) ;;
    esac
  done
  # A generated `--no-x` is only useful if it lands on a falsy value, so a
  # negatable option without an explicit `off:` turns off to `false` instead of
  # the empty string every other option defaults to.
  local __negatable_off=false
  if dybatpho::is true "${__negatable}" && dybatpho::is false "${__has_explicit_off}"; then
    __negatable_off=true
  fi

  if dybatpho::is false "${__done_initial}"; then
    __on="true" __off="" __init="@empty" __export="true" __required="false" __persistent="false" __hidden="false"
    __deprecated="" __label="" __env="" __multiple="false" __prompt="" __choices="" __config="" __pattern="" __type=""
    # A counting flag accumulates repeats, so it starts from zero rather than
    # from the empty string every other option type uses.
    if dybatpho::is true "${__count}"; then __init="=0"; fi
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
        alias:*) __dybatpho_cli_label_switch "${need_argument}" "${1#alias:}" ;;
        aliases:*)
          local -a __opt_aliases=()
          local __opt_alias
          __dybatpho_cli_parse_alias_list __opt_aliases "${1#aliases:}"
          for __opt_alias in "${__opt_aliases[@]}"; do
            __dybatpho_cli_label_switch "${need_argument}" "${__opt_alias}"
          done
          ;;
        [!-]*) __dybatpho_cli_parse_key_value "$1" "__" ;;
        --* | -?) __dybatpho_cli_label_switch "${need_argument}" "$1" ;;
        *) ;;
      esac
      shift
    done
    if dybatpho::is true "${__negatable_off}"; then __off="false"; fi
  else
    __validate="" __on="true" __off="" __export="true" __optional="false" __required="false" __persistent="false"
    __hidden="false" __deprecated="" __switch="" __env="" __multiple="false" __prompt="" __choices="" __config=""
    __pattern="" __type=""
    shift "${skip_meta}"
    while (($#)); do
      case $1 in
        alias:*) __dybatpho_cli_case_switch "${1#alias:}" ;;
        aliases:*)
          local -a __opt_aliases=()
          local __opt_alias
          __dybatpho_cli_parse_alias_list __opt_aliases "${1#aliases:}"
          for __opt_alias in "${__opt_aliases[@]}"; do
            __dybatpho_cli_case_switch "${__opt_alias}"
          done
          ;;
        --\{no-\}* | --with\{out\}-* | -? | --*) __dybatpho_cli_case_switch "$1" ;;
        *) __dybatpho_cli_parse_key_value "$1" "__" ;;
      esac
      shift
    done
    if dybatpho::is true "${__negatable_off}"; then __off="false"; fi
    __dybatpho_cli_assign_quoted __on "${__on}"
    __dybatpho_cli_assign_quoted __off "${__off}"
  fi
}

#######################################
# @description Write script with indentation to stdout
# @arg $1 number Number of indentation level
# @arg $@ string Line of code to generate
# @stdout Generated code
# @exitcode 0
# @internal
#######################################
function __dybatpho_cli_print_indent {
  local indent=$1
  shift
  # One `printf`, not an `echo -n` per level: this runs for every generated
  # line, and `echo` would swallow a line that is exactly `-n` or `-e`.
  printf '%*s%s\n' "$((indent * 2))" '' "$*"
}

#######################################
# @description Validate a shell variable name used by generated parser code.
# @arg $1 string Variable name, or `-` to intentionally skip assignment
# @exitcode 0 The name is valid, or the sentinel `-` was used
# @internal
#######################################
function __dybatpho_cli_require_shell_name {
  local name="${1:-}"
  [[ "${name}" == "-" ]] && return 0
  # shellcheck disable=SC2154 # declared by `src/validate.sh`, which `cli` loads
  [[ "${name}" =~ ${__DYBATPHO_VALIDATE_RE_IDENTIFIER} ]] \
    || dybatpho::die "$(__dybatpho_log_text cli.invalid_var_name \
      "Invalid shell variable name: ${name}" "name=${name}")"
}

#######################################
# @description Collect every long switch a spec accepts, for abbreviation
#              matching. The metadata walk is reused because it already expands
#              `--{no-}x`, aliases, and negatable forms.
# @arg $1 string Name of the array variable receiving the switches
# @arg $2 string Name of the spec function
# @exitcode 0 The array is left empty when the spec declares no long switch
# @internal
#######################################
function __dybatpho_cli_collect_long_switches {
  __dybatpho_cli_require_shell_name "$1"
  local -n __long_out="$1"
  local __long_spec="$2"
  __long_out=()
  local -a __long_options=() __long_commands=()
  local __long_description=""
  __dybatpho_cli_collect_spec_metadata "${__long_spec}" __long_options __long_commands __long_description
  local __long_item __long_switches __long_switch
  for __long_item in ${__long_options[@]+"${__long_options[@]}"}; do
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r _ _ _ __long_switches _ <<< "${__long_item}"
    for __long_switch in ${__long_switches}; do
      case "${__long_switch}" in
        --?*) __long_out+=("${__long_switch}") ;;
        *) ;;
      esac
    done
  done
  # Every command answers `--help` even when the spec never declares it.
  __long_out+=("--help")
  return 0
}

#######################################
# @description Resolve an abbreviated long option against the switches a command
#              accepts, the way `--vers` stands for `--version`. An exact match
#              wins outright, so a switch that is also the prefix of a longer one
#              stays reachable.
# @arg $1 string Switch as typed
# @arg $@ string Long switches the command accepts
# @stdout The resolved switch, or the candidate list when the input is ambiguous
# @exitcode 0 Resolved to exactly one switch
# @exitcode 1 Matched nothing, so the caller reports it as unrecognized
# @exitcode 2 Matched more than one switch; the candidates are on stdout
# @internal
#######################################
function __dybatpho_cli_expand_abbr {
  local __typed="$1"
  shift
  local __candidate
  local -a __matches=()
  for __candidate in "$@"; do
    [[ -n "${__candidate}" ]] || continue
    # An exact match is never an abbreviation of anything else.
    if [[ "${__candidate}" = "${__typed}" ]]; then
      printf '%s' "${__typed}"
      return 0
    fi
    case "${__candidate}" in
      "${__typed}"*) __matches+=("${__candidate}") ;;
      *) ;;
    esac
  done
  case "${#__matches[@]}" in
    0) return 1 ;;
    1)
      printf '%s' "${__matches[0]}"
      return 0
      ;;
    *)
      # `, ` is the separator an `error:` handler reads the candidate list by,
      # so it stays fixed rather than following the locale.
      local __joined="" __match
      for __match in "${__matches[@]}"; do
        __joined="${__joined}${__joined:+, }${__match}"
      done
      printf '%s' "${__joined}"
      return 2
      ;;
  esac
}

#######################################
# @description Validate a `case` glob supplied by `pattern:<glob>`. Unlike every
#              other spec value, a pattern cannot be quoted on its way into the
#              generated script — quoting it would make `case` compare it
#              literally and defeat the point. This restricts it to characters
#              that cannot end the `case` branch or start a substitution, so a
#              spec still cannot inject code into the parser it generates.
# @arg $1 string Pattern to validate
# @exitcode 0 The pattern is safe to interpolate
# @internal
#######################################
function __dybatpho_cli_require_case_pattern {
  local pattern="${1:-}"
  [[ -n "${pattern}" ]] \
    || dybatpho::die "$(__dybatpho_log_text cli.empty_pattern \
      "Empty pattern: is not a valid pattern")"
  # Deliberately excluded: `)` and `;` end the branch, `$` and a backtick start
  # a substitution, `(` `&` `<` `>` `\` and quotes redirect or group, and a
  # newline ends the statement outright. `]` leads the bracket expression and
  # `-` trails it so both are read as literals rather than as syntax.
  local allowed='^[]a-zA-Z0-9_.,:@/^!?*[|+%=~#-]+$'
  [[ "${pattern}" =~ ${allowed} ]] \
    || dybatpho::die "$(__dybatpho_log_text cli.invalid_pattern \
      "Invalid pattern: ${pattern}" "pattern=${pattern}")"
}

#######################################
# @description Assign the quoted string to a variable
# @arg $1 string Variable name to be assigned
# @arg $2 string Input string to be quoted
# @exitcode 0
# @internal
#######################################
function __dybatpho_cli_assign_quoted {
  __dybatpho_cli_require_shell_name "$1"
  local quote="$2'" result=""
  while [[ -n "${quote}" ]]; do
    result="${result}${quote%%\'*}'\''" && quote=${quote#*\'}
  done
  quote="'${result%????}'" && quote=${quote#\'\'} && quote=${quote%\'\'}
  printf -v "$1" '%s' "${quote:-"''"}"
}

#######################################
# @description Prepend export of before string of command,
#              based on `export:<bool>` switch
# @arg $1 string String of command
# @internal
#######################################
function __dybatpho_cli_prepend_export {
  # `dybatpho::is` answers a question, so a `no` is not a failure of this
  # function: the prefix is simply empty.
  local is=""
  if dybatpho::is true "${__export}"; then
    is="export "
  fi
  echo "${is}$1"
}

#######################################
# @description Define variable from spec from `dybatpho::opts::flag`,
#              `dybatpho::opts::param`
# @arg $1 string Name of variable to be defined
# @internal
#######################################
function __dybatpho_cli_define_var {
  [[ "$1" = "-" ]] && return 0
  __dybatpho_cli_require_shell_name "$1"
  local __env_name="${__env:-}"
  if [[ "${__env_name}" = "true" ]]; then __env_name="$1"; fi
  [[ "${__env_name}" = "false" ]] && __env_name=""
  [[ -z "${__env_name}" ]] || __dybatpho_cli_require_shell_name "${__env_name}"
  local __config_key="${__config:-}"
  if [[ -n "${__env_name}" ]] && [[ "${__init}" != "@unset" ]]; then
    __dybatpho_cli_print_indent 0 "if [ \"\${${__env_name}+x}\" ]; then"
    local __env_line
    __env_line=$(__dybatpho_cli_prepend_export "$1=\${${__env_name}}")
    __dybatpho_cli_print_indent 1 "${__env_line}"
    __dybatpho_cli_print_indent 0 "else"
    local __saved_env="${__env}"
    local __fallback
    __env=""
    __fallback="$(__dybatpho_cli_define_var "$1")"
    __env="${__saved_env}"
    __dybatpho_cli_print_indent 1 "${__fallback}"
    __dybatpho_cli_print_indent 0 "fi"
    return 0
  fi
  # Config keys sit between the environment fallback above and the declared
  # default below, so the precedence is flag > env > config file > default.
  if [[ -n "${__config_key}" ]] && [[ "${__init}" != "@unset" ]]; then
    local __config_quoted
    __dybatpho_cli_assign_quoted __config_quoted "${__config_key}"
    __dybatpho_cli_print_indent 0 "if $1=\"\$(__dybatpho_cli_config_get ${__config_quoted})\"; then"
    if dybatpho::is true "${__export}"; then
      __dybatpho_cli_print_indent 1 "export $1"
    else
      __dybatpho_cli_print_indent 1 ":"
    fi
    __dybatpho_cli_print_indent 0 "else"
    local __saved_config="${__config}"
    local __config_fallback
    __config=""
    __config_fallback="$(__dybatpho_cli_define_var "$1")"
    __config="${__saved_config}"
    __dybatpho_cli_print_indent 1 "${__config_fallback}"
    __dybatpho_cli_print_indent 0 "fi"
    return 0
  fi
  case ${__init} in
    @keep) : ;;
    @empty)
      local __empty_export
      __empty_export=$(__dybatpho_cli_prepend_export "$1=''")
      __dybatpho_cli_print_indent 0 "${__empty_export}"
      ;;
    @unset) __dybatpho_cli_print_indent 0 "unset $1 ||:" ;;
    *)
      case ${__init} in @on) __init=${__on} ;; *) ;; esac
      case ${__init} in @off) __init=${__off} ;; *) ;; esac
      case ${__init} in =*)
        local __init_line
        __init_line=$(__dybatpho_cli_prepend_export "$1${__init}")
        __dybatpho_cli_print_indent 0 "${__init_line}"
        return 0
        ;;
      *) ;;
      esac
      case ${__init} in action:*)
        local action=""
        __dybatpho_cli_parse_key_value "${__init#init:}"
        __dybatpho_cli_print_indent 0 "${action}"
        return 0
        ;;
      *) ;;
      esac
      __dybatpho_cli_assign_quoted __init "${__init#=}"
      local cli_prepend_export
      cli_prepend_export=$(__dybatpho_cli_prepend_export "$1=${__init}")
      __dybatpho_cli_print_indent 0 "${cli_prepend_export}"
      ;;
  esac
}

#######################################
# @description Extract key value from spec with format `x:y`,
#              to get settings of option
# @arg $1 key:value Key-value string to extract
# @arg $2 string Prefix of key to assign as variable
# @internal
#######################################
function __dybatpho_cli_parse_key_value {
  local target="${2-}${1%%:*}"
  __dybatpho_cli_require_shell_name "${target}"
  printf -v "${target}" '%s' "${1#*:}"
}

# shellcheck disable=2016
#######################################
# @description Generate logic from spec of script/function to get options
# @arg $1 string Name of function that has spec of parent function or script
# @arg $@ string Original CLI arguments
# @stdout Generated logic
# @internal
#######################################
function __dybatpho_cli_generate_logic {
  local __dybatpho_cli_logic_spec
  dybatpho::expect_args __dybatpho_cli_logic_spec -- "$@"
  declare -F "${__dybatpho_cli_logic_spec}" > /dev/null || return 0
  shift

  # For get list of options, separated by space
  local IFS=" "
  # For get all rest arguments
  local __rest=""
  # For get function name of custom error handler, validation and
  local __error="" __validate=""
  # For get all flags and params of command
  local __flags="" __params=""
  # For handle argument of param, effective for rest arguments and options
  local __on="1" __off="" __init="@empty"
  # For handle export variable of `dybatpho::opts::*` commands via name
  local __export="true"
  # Param value optionality, option presence, persistence, visibility,
  # deprecation, preferred switch label
  local __optional="true" __required="false" __persistent="false" __hidden="false" __deprecated="" __label=""
  # For get action and setup hooks in spec
  local __action="" __setup_action="" __prerun="" __setup_prerun="" __postrun="" __setup_postrun=""
  # For validate positional argument count from opts::setup
  local __args="any"
  # For accept an unambiguous prefix of a long switch, from `abbr:` in opts::setup
  local __abbr="false"
  # For get switch of options
  local __switch=""
  declare -a __required_checks=()
  declare -a __persistent_defs=()
  local __has_sub_cmd="false"
  local __has_help="false"
  declare -a __sub_specs=()
  local __dybatpho_cli_logic_sub_spec __required_check
  declare -a __prompt_defs=()
  declare -a __known_switches=()
  declare -a __declared_args=()

  #######################################
  # @description Emit generated code that rebuilds positional parameters from a serialized argument list.
  # @arg $1 string Shell expression that expands to serialized arguments
  # @stdout Generated parser code
  # @internal
  #######################################
  function __dybatpho_cli_print_get_arg {
    __dybatpho_cli_print_indent 4 "eval 'set -- $1' \${1+'\"\$@\"'}"
  }

  #######################################
  # @description
  #   Emit generated code that appends the remaining positional arguments to the configured rest variable and stops
  #   option parsing.
  # @noargs
  # @stdout Generated parser code
  # @internal
  #######################################
  function __dybatpho_cli_print_rest {
    __dybatpho_cli_print_indent 4 'while [ $# -gt 0 ]; do'
    # Appending to a real array is what keeps an argument containing spaces,
    # quotes, or newlines intact. Joining into a scalar would lose the
    # boundaries between arguments beyond recovery.
    __dybatpho_cli_print_indent 5 "${__rest}+=(\"\$1\")"
    __dybatpho_cli_print_indent 5 '__rest_argc=$((__rest_argc + 1))'
    __dybatpho_cli_print_indent 5 "shift"
    __dybatpho_cli_print_indent 4 "done"
    __dybatpho_cli_print_indent 4 "break"
    __dybatpho_cli_print_indent 4 ";;"
  }

  # Initial all variables before get value of options
  local __done_initial=false
  __dybatpho_cli_replay_persistent_defs
  "${__dybatpho_cli_logic_spec}" "$*"
  # An explicit `args:<rule>` always wins; otherwise the declared positional
  # arguments describe the count well enough to validate it.
  case "${__args}" in
    "" | any | arbitrary)
      __dybatpho_cli_derive_args_rule __args ${__declared_args[@]+"${__declared_args[@]}"}
      ;;
    *) ;;
  esac
  __dybatpho_cli_print_indent 0 "dybatpho::opts::parse::${__dybatpho_cli_logic_spec}() {"
  __dybatpho_cli_print_indent 1 'local __rest_argc=0'
  # The rest variable is an array now, so it can no longer double as the
  # "stop parsing" sentinel the way a scalar did: writing `end` into it would
  # clobber the first collected argument.
  __dybatpho_cli_print_indent 1 'local __rest_end=""'
  dybatpho::is true "${__abbr}" \
    && __dybatpho_cli_print_indent 1 'local __abbr_rc=0 __abbr_out=""'
  __dybatpho_cli_print_persistent_help_defs
  # shellcheck disable=2016
  __dybatpho_cli_print_indent 1 \
    "while OPTARG= && [ \"\${__rest_end}\" != end ] && [ \$# -gt 0 ]; do"
  __dybatpho_cli_print_indent 2 "case \$1 in"
  __dybatpho_cli_print_indent 3 "--?*=*)"
  __dybatpho_cli_print_indent 4 "OPTARG=\$1; shift"
  __dybatpho_cli_print_get_arg '"${OPTARG%%\=*}" "${OPTARG#*\=}"'
  __dybatpho_cli_print_indent 4 ";;"
  __dybatpho_cli_print_indent 3 "--no-*|--without-*)"
  __dybatpho_cli_print_indent 4 "unset OPTARG"
  __dybatpho_cli_print_indent 4 ";;"
  [[ -n "${__params}" ]] && {
    __dybatpho_cli_print_indent 3 "-[${__params}]?*)"
    __dybatpho_cli_print_indent 4 "OPTARG=\$1; shift"
    __dybatpho_cli_print_get_arg '"${OPTARG%"${OPTARG#??}"}" "${OPTARG#??}"'
    __dybatpho_cli_print_indent 4 ";;"
  }
  [[ -n "${__flags}" ]] && {
    __dybatpho_cli_print_indent 3 "-[${__flags}]?*) OPTARG=\$1; shift"
    __dybatpho_cli_print_get_arg '"${OPTARG%"${OPTARG#??}"}" -"${OPTARG#??}"'
    __dybatpho_cli_print_indent 4 \
      'case $2 in --*) set -- "$1" unknown "$2" && __rest_end=end; esac'
    __dybatpho_cli_print_indent 4 'OPTARG='
    __dybatpho_cli_print_indent 4 ';;'
  }
  __dybatpho_cli_print_indent 2 "esac"

  # Expand an abbreviated long option once the prologue has split `--opt=value`
  # and unbundled short switches, so `$1` is a whole switch by the time it is
  # compared against the ones the command accepts.
  if dybatpho::is true "${__abbr}"; then
    local -a __abbr_long=()
    __dybatpho_cli_collect_long_switches __abbr_long "${__dybatpho_cli_logic_spec}"
    if ((${#__abbr_long[@]})); then
      local __abbr_list="" __abbr_switch
      for __abbr_switch in "${__abbr_long[@]}"; do
        __abbr_list="${__abbr_list}${__abbr_list:+ }$(printf '%q' "${__abbr_switch}")"
      done
      __dybatpho_cli_print_indent 2 'case $1 in'
      __dybatpho_cli_print_indent 3 '--?*)'
      __dybatpho_cli_print_indent 4 \
        "__abbr_rc=0; __abbr_out=\$(__dybatpho_cli_expand_abbr \"\$1\" ${__abbr_list}) || __abbr_rc=\$?"
      __dybatpho_cli_print_indent 4 'case ${__abbr_rc} in'
      __dybatpho_cli_print_indent 5 '0) set -- "${__abbr_out}" "${@:2}" ;;'
      # Status 1 means nothing matched, which the normal dispatch already
      # reports as an unrecognized option with a suggestion.
      __dybatpho_cli_print_indent 5 '2) OPTARG=${__abbr_out}; set "ambiguous" "$1"; break ;;'
      __dybatpho_cli_print_indent 4 'esac'
      __dybatpho_cli_print_indent 4 ';;'
      __dybatpho_cli_print_indent 2 'esac'
    fi
  fi

  # Get value of options
  __dybatpho_cli_print_indent 2 'case $1 in'
  __done_initial=true
  __dybatpho_cli_replay_persistent_defs
  if dybatpho::is false "${__has_help}"; then
    __dybatpho_cli_print_indent 3 "--help|-h)"
    __dybatpho_cli_print_indent 4 "dybatpho::generate_help ${__dybatpho_cli_logic_spec}"
    __dybatpho_cli_print_indent 4 "exit 0"
    __dybatpho_cli_print_indent 4 ";;"
  fi
  "${__dybatpho_cli_logic_spec}" "$*"
  __dybatpho_cli_print_indent 3 "--)"
  __dybatpho_cli_print_indent 4 "shift"
  __dybatpho_cli_print_rest
  __dybatpho_cli_print_indent 3 "*)"
  if dybatpho::is false "${__has_sub_cmd}"; then
    # Anything still starting with a dash matched no declared switch, so it is
    # a typo rather than a positional argument. A lone `-` keeps its usual
    # stdin meaning, and `--` is still the way to pass dashed values through.
    # A command that declares no switches at all is a passthrough wrapper
    # though, and has no option list to have mistyped in the first place.
    ((${#__known_switches[@]})) \
      && __dybatpho_cli_print_indent 4 'case $1 in -?*) set "unknown" "$1"; break ;; esac'
    __dybatpho_cli_print_rest
  else
    __dybatpho_cli_print_indent 4 "case \$1 in"
    for __dybatpho_cli_logic_sub_spec in "${__sub_specs[@]}"; do
      local __dybatpho_cli_logic__sub_spec __dybatpho_cli_logic__cmd_match __dybatpho_cli_logic__cmd_name
      local __dybatpho_cli_logic__cmd_deprecated
      IFS=$'\t' read -r __dybatpho_cli_logic__sub_spec __dybatpho_cli_logic__cmd_match __dybatpho_cli_logic__cmd_name \
        __dybatpho_cli_logic__cmd_deprecated <<< "${__dybatpho_cli_logic_sub_spec}"
      __dybatpho_cli_print_indent 5 "${__dybatpho_cli_logic__cmd_match})"
      [[ -n "${__dybatpho_cli_logic__cmd_deprecated}" ]] && __dybatpho_cli_print_deprecated_warning "command" \
        "${__dybatpho_cli_logic__cmd_name}" "${__dybatpho_cli_logic__cmd_deprecated}"
      __dybatpho_cli_print_indent 6 \
        "__current_cmd_path=\"\${__current_cmd_path:+\${__current_cmd_path} }${__dybatpho_cli_logic__cmd_name}\""
      __dybatpho_cli_print_indent 6 "shift"
      __dybatpho_cli_print_indent 6 "dybatpho::opts::parse::${__dybatpho_cli_logic__sub_spec} \"\$@\""
      __dybatpho_cli_print_indent 6 ";;"
    done
    __dybatpho_cli_print_indent 5 "*)"
    # A leftover switch is a mistyped option, not a mistyped command, so it is
    # reported against the option list to get a useful suggestion.
    __dybatpho_cli_print_indent 6 'case $1 in'
    __dybatpho_cli_print_indent 7 '-?*) set "unknown" "$1" ;;'
    __dybatpho_cli_print_indent 7 '*) set "notcmd" "$1" ;;'
    __dybatpho_cli_print_indent 6 'esac'
    __dybatpho_cli_print_indent 6 "break"
    __dybatpho_cli_print_indent 6 ";;"
    __dybatpho_cli_print_indent 4 "esac"
    __dybatpho_cli_print_rest
  fi
  __dybatpho_cli_print_indent 2 "esac"
  __dybatpho_cli_print_indent 2 "shift"
  __dybatpho_cli_print_indent 1 "done"

  # Show error messages if invalid, otherwise run action command
  __dybatpho_cli_print_indent 1 '[ $# -eq 0 ] && {'
  __dybatpho_cli_print_indent 2 'unset OPTARG'
  for __required_check in "${__required_checks[@]}"; do
    __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
    __dybatpho_cli_print_indent 3 "${__required_check}"
    __dybatpho_cli_print_indent 2 '}'
  done
  __dybatpho_cli_print_args_check "${__args}"
  # Binding runs after the count check, so an argument variable is only ever
  # read once the command is known to have been called correctly.
  __dybatpho_cli_print_arg_bindings "${__rest}" ${__declared_args[@]+"${__declared_args[@]}"}
  local __prompt_def __prompt_var __prompt_text __prompt_choices __prompt_multiple __prompt_export
  for __prompt_def in "${__prompt_defs[@]}"; do
    IFS=$'\x1f' read -r __prompt_var __prompt_text __prompt_choices __prompt_multiple __prompt_export <<< \
      "${__prompt_def}"
    __dybatpho_cli_assign_quoted __prompt_text "${__prompt_text}"
    # Quote the choices only after testing them: quoting an empty value yields `''`.
    if [[ -n "${__prompt_choices}" ]]; then
      __dybatpho_cli_assign_quoted __prompt_choices "${__prompt_choices}"
      __dybatpho_cli_print_indent 2 "if [ -z \"\${${__prompt_var}:-}\" ]; then"
      __dybatpho_cli_print_indent 3 \
        "${__prompt_var}=\$(dybatpho::select ${__prompt_text} ${__prompt_choices} ${__prompt_multiple})"
      [[ "${__prompt_export}" = "true" ]] && __dybatpho_cli_print_indent 3 "export ${__prompt_var}"
      __dybatpho_cli_print_indent 2 "fi"
    else
      __dybatpho_cli_print_indent 2 "if [ -z \"\${${__prompt_var}:-}\" ]; then"
      __dybatpho_cli_print_indent 3 "${__prompt_var}=\$(dybatpho::prompt ${__prompt_text})"
      [[ "${__prompt_export}" = "true" ]] && __dybatpho_cli_print_indent 3 "export ${__prompt_var}"
      __dybatpho_cli_print_indent 2 "fi"
    fi
  done
  __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
  [[ -n "${__setup_prerun}" ]] && __dybatpho_cli_print_indent 3 "${__setup_prerun}"
  [[ -n "${__setup_action}" ]] && __dybatpho_cli_print_indent 3 "${__setup_action}"
  [[ -n "${__setup_postrun}" ]] && __dybatpho_cli_print_indent 3 "${__setup_postrun}"
  __dybatpho_cli_print_indent 3 'return 0'
  __dybatpho_cli_print_indent 2 '}'
  __dybatpho_cli_print_indent 1 '}'
  # The parser knows every switch and command name it accepts, so a typo can be
  # answered with the closest match instead of a bare "Unrecognized option".
  __dybatpho_cli_print_known_candidates
  __dybatpho_cli_print_indent 1 'case $1 in'
  # Each parser error names the switch or command it rejected, so the English
  # sentence cannot double as its own message id; the generated code calls the
  # keyed hook and keeps the English as the fallback rendering. The suggestion
  # suffix translates itself and is appended afterwards.
  __dybatpho_cli_print_indent 2 'unknown) set "$(__dybatpho_log_text cli.unrecognized_option "Unrecognized option: $2" "option=$2")$(__dybatpho_cli_suggest_suffix "$2" ${__cli_known_opts[@]+"${__cli_known_opts[@]}"})" "$@" ;;'
  __dybatpho_cli_print_indent 2 \
    'noarg) set "$(__dybatpho_log_text cli.no_argument_allowed "Does not allow an argument: $2" "option=$2")" "$@" ;;'
  __dybatpho_cli_print_indent 2 \
    'needarg) set "$(__dybatpho_log_text cli.argument_required "Requires an argument: $2" "option=$2")" "$@" ;;'
  __dybatpho_cli_print_indent 2 'missingopt) set "$(__dybatpho_log_text cli.missing_required_option "Missing required option: $2" "option=$2")" "$@" ;;'
  __dybatpho_cli_print_indent 2 'argcount) set "$2" "$@" ;;'
  __dybatpho_cli_print_indent 2 'notcmd) set "$(__dybatpho_log_text cli.invalid_command "Invalid command: $2" "command=$2")$(__dybatpho_cli_suggest_suffix "$2" ${__cli_known_cmds[@]+"${__cli_known_cmds[@]}"})" "$@" ;;'
  # The error name carries the pattern itself, so the message can name what
  # the value failed to match instead of only that it failed.
  __dybatpho_cli_print_indent 2 'pattern:*) set "$(__dybatpho_log_text cli.pattern_mismatch "Does not match the pattern (${1#*:}): $2" "pattern=${1#*:}" "value=$2")" "$@" ;;'
  # The error name carries the type, so the message can name the shape the
  # value failed to have rather than only that it failed.
  __dybatpho_cli_print_indent 2 'type:*) set "$(__dybatpho_log_text cli.type_mismatch "Expected $(dybatpho::validate_describe "${1#*:}"): $2" "type=${1#*:}" "value=$2")" "$@" ;;'
  __dybatpho_cli_print_indent 2 'ambiguous) set "$(__dybatpho_log_text cli.ambiguous_option "Ambiguous option: $2 (matches ${OPTARG})" "option=$2" "candidates=${OPTARG}")" "$@" ;;'
  __dybatpho_cli_print_indent 2 \
    '*) set "$(__dybatpho_log_text cli.validation_error "Validation error ($1): $2" "kind=$1" "detail=$2")" "$@"'
  __dybatpho_cli_print_indent 1 "esac"
  [[ -n "${__error}" ]] && __dybatpho_cli_print_indent 1 "${__error}" '"$@" >&2 || exit $?'
  __dybatpho_cli_print_indent 1 'dybatpho::die "$1" 1'
  __dybatpho_cli_print_indent 0 "} # End of dybatpho::opts::parse::${__dybatpho_cli_logic_spec}"

  # Generate sub-command logics
  for __dybatpho_cli_logic_sub_spec in "${__sub_specs[@]}"; do
    local __dybatpho_cli_logic__sub_spec __dybatpho_cli_logic__cmd_match __dybatpho_cli_logic__cmd_name
    local __dybatpho_cli_logic__cmd_deprecated
    IFS=$'\t' read -r __dybatpho_cli_logic__sub_spec __dybatpho_cli_logic__cmd_match __dybatpho_cli_logic__cmd_name \
      __dybatpho_cli_logic__cmd_deprecated <<< "${__dybatpho_cli_logic_sub_spec}"
    [[ "${__dybatpho_cli_logic__cmd_match}" = "${__dybatpho_cli_logic__cmd_name}" ]] || continue
    __dybatpho_cli_generate_child_logic "${__dybatpho_cli_logic__sub_spec}" "$@"
  done

  # The root spec is not triggered from inside the generated file. Writing the
  # arguments into it as shell source and sourcing that put every value through
  # a round of expansion: `--name '$(id)'` ran `id`, `--name '$VAR'` expanded
  # it, and a value ending in a backslash escaped the closing quote and left
  # the file unparseable. `dybatpho::generate_from_spec` calls the parser with
  # the real argument vector instead, where a value is a value.

}

#######################################
# @description Get help description for options from spec.
#              Sets __help_mode=true so dybatpho::opts::* collect help data
#              via dynamic scoping into dybatpho::generate_help's locals,
#              then prints the buffered sections in the correct order.
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Help description
# @exitcode 0 exit code
# @internal
#######################################
function __dybatpho_cli_generate_help {
  local __dybatpho_cli_help_spec
  dybatpho::expect_args __dybatpho_cli_help_spec -- "$@"
  local __dybatpho_cli_help_type
  __dybatpho_cli_help_type=$(type -t "${__dybatpho_cli_help_spec}")
  [[ "${__dybatpho_cli_help_type}" != 'function' ]] && return

  __help_mode=true
  __dybatpho_cli_replay_persistent_defs
  local __persistent_def
  local __persistent_replay=true
  # shellcheck disable=SC2154 # populated by __dybatpho_cli_replay_persistent_defs
  for __persistent_def in "${__persistent_help_defs[@]}"; do
    eval "${__persistent_def}"
  done
  "${__dybatpho_cli_help_spec}"
  # A command that declares no help option of its own is still given `--help`
  # and `-h` by the parser, so the generated help lists them too.
  if dybatpho::is false "${__has_help}"; then
    __help_opt_rows+=(
      "$(__dybatpho_cli_help_row disp "-" "$(__dybatpho_log_text cli.show_help "Show this help")" -h alias:--help)"
    )
  fi
  __help_mode=false
  # A command that declares a persistent option sees it twice: once replayed as
  # an inherited definition, once from its own spec. Both rows are identical, so
  # the later one is dropped.
  __dybatpho_cli_help_dedupe __help_opt_rows

  local __width
  __dybatpho_cli_help_width_for __width \
    ${__help_arg_rows[@]+"${__help_arg_rows[@]}"} \
    ${__help_cmd_rows[@]+"${__help_cmd_rows[@]}"} \
    ${__help_opt_rows[@]+"${__help_opt_rows[@]}"}

  local __dybatpho_cli_help_cli_help_usage
  __dybatpho_cli_help_cli_help_usage=$(__dybatpho_cli_help_usage)
  dybatpho::print "${__dybatpho_cli_help_cli_help_usage}"
  if [[ -n "${__help_description}" ]]; then
    dybatpho::print ""
    dybatpho::print "${__help_description}"
  fi
  # Help is the library's own chrome rather than the caller's text, so each
  # piece carries a stable key instead of being looked up by its English.
  if ((${#__help_arg_rows[@]})); then
    dybatpho::print ""
    local __heading
    __heading=$(__dybatpho_log_text cli.heading_arguments "Arguments:")
    dybatpho::print "${__heading}"
    __dybatpho_cli_help_render_rows "${__width}" "${__help_arg_rows[@]}"
  fi
  if ((${#__help_cmd_rows[@]})); then
    dybatpho::print ""
    local __heading
    __heading=$(__dybatpho_log_text cli.heading_commands "Commands:")
    dybatpho::print "${__heading}"
    __dybatpho_cli_help_render_rows "${__width}" "${__help_cmd_rows[@]}"
  fi
  dybatpho::print ""
  local __dybatpho_cli_help_log_text
  __dybatpho_cli_help_log_text=$(__dybatpho_log_text cli.heading_options "Options:")
  dybatpho::print "${__dybatpho_cli_help_log_text}"
  __dybatpho_cli_help_render_rows "${__width}" ${__help_opt_rows[@]+"${__help_opt_rows[@]}"}
  if ((${#__help_cmd_rows[@]})); then
    local __invocation="${0##*/}${__help_subcmd:+ ${__help_subcmd}}"
    dybatpho::print ""
    dybatpho::print "$(__dybatpho_log_text cli.more_info \
      "Run '${__invocation} COMMAND --help' for more information on a command." \
      "command=${__invocation}")"
  fi
}

#######################################
# @description Build the usage line from what the command actually accepts, so
#              it names a COMMAND only when there are subcommands and shows the
#              declared positional arguments when there are any.
# @noargs
# @stdout Usage line
# @internal
#######################################
function __dybatpho_cli_help_usage {
  # The label and the three placeholders are translated one by one rather than
  # as a sentence: their order around the program name is fixed by the shell
  # syntax being described, so only the words themselves can change.
  local label placeholder_options
  label="$(__dybatpho_log_text cli.heading_usage "Usage:")"
  placeholder_options="$(__dybatpho_log_text cli.placeholder_options "[OPTIONS]")"
  local usage="${label} ${0##*/}${__help_subcmd:+ ${__help_subcmd}} ${placeholder_options}"
  ((${#__help_cmd_rows[@]})) \
    && usage="${usage} $(__dybatpho_log_text cli.placeholder_command "COMMAND")"
  if [[ -n "${__help_arg_usage}" ]]; then
    usage="${usage} ${__help_arg_usage}"
  else
    case "${__help_args_rule,,}" in
      none | noargs) ;;
      *) usage="${usage} $(__dybatpho_log_text cli.placeholder_args "[ARGS]...")" ;;
    esac
  fi
  printf '%s' "${usage}"
}

#######################################
# @description Generate a JSON CLI schema from the same option spec used by parsing.
# @arg $1 string Spec function
# @arg $2 string Optional command name
# @tip Use the schema to drive external validation, form generation, tooling, or documentation from the same source of
#   truth.
# @stdout JSON schema
#######################################
function dybatpho::generate_schema {
  local __dybatpho_cli_gs_spec __dybatpho_cli_gs_name="${2:-${0##*/}}"
  dybatpho::expect_args __dybatpho_cli_gs_spec -- "$@"
  __dybatpho_cli_generate_schema_command "${__dybatpho_cli_gs_spec}" "${__dybatpho_cli_gs_name}"
}

#######################################
# @description Write one command of a spec as a JSON object, and recurse into
#   its subcommands. `dybatpho::generate_schema` is the entry point; this is
#   the body it calls for the root and for every command under it.
# @arg $1 string Spec function
# @arg $2 string Command name, as it appears in the schema
# @arg $3 string Optional aliases of the command, or `@none`
# @stdout The command as a JSON object
# @internal
#######################################
function __dybatpho_cli_generate_schema_command {
  local __dybatpho_cli_gsc_spec="$1" __dybatpho_cli_gsc_name="$2" __dybatpho_cli_gsc_command_aliases="${3:-}" \
    __dybatpho_cli_gsc_description
  local -a __dybatpho_cli_gsc_options=() __dybatpho_cli_gsc_commands=() __dybatpho_cli_gsc_arguments=()
  __dybatpho_cli_collect_spec_metadata "${__dybatpho_cli_gsc_spec}" __dybatpho_cli_gsc_options \
    __dybatpho_cli_gsc_commands __dybatpho_cli_gsc_description __dybatpho_cli_gsc_arguments
  local __dybatpho_cli_gsc_q_name __dybatpho_cli_gsc_q_description __dybatpho_cli_gsc_option \
    __dybatpho_cli_gsc_argument __dybatpho_cli_gsc_command __dybatpho_cli_gsc_first=true \
    __dybatpho_cli_gsc_aliases="${__dybatpho_cli_gsc_command_aliases}"
  # `@none` is the sentinel an alias-less command records, not a real alias.
  [[ "${__dybatpho_cli_gsc_aliases}" = "@none" ]] && __dybatpho_cli_gsc_aliases=""
  __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_name "${__dybatpho_cli_gsc_name}"
  __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_description "${__dybatpho_cli_gsc_description}"
  local __dybatpho_cli_gsc_alias __dybatpho_cli_gsc_alias_first=true
  printf '{"name":%s,"description":%s,"aliases":[' "${__dybatpho_cli_gsc_q_name}" "${__dybatpho_cli_gsc_q_description}"
  for __dybatpho_cli_gsc_alias in ${__dybatpho_cli_gsc_aliases:-}; do
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_alias "${__dybatpho_cli_gsc_alias}"
    [[ "${__dybatpho_cli_gsc_alias_first}" = true ]] || printf ","
    __dybatpho_cli_gsc_alias_first=false
    printf "%s" "${__dybatpho_cli_gsc_alias}"
  done
  printf '],"options":['
  for __dybatpho_cli_gsc_option in "${__dybatpho_cli_gsc_options[@]}"; do
    local __dybatpho_cli_gsc_type __dybatpho_cli_gsc_var __dybatpho_cli_gsc_desc __dybatpho_cli_gsc_switches
    local __dybatpho_cli_gsc_env __dybatpho_cli_gsc_multiple __dybatpho_cli_gsc_choices __dybatpho_cli_gsc_prompt
    local __dybatpho_cli_gsc_hidden __dybatpho_cli_gsc_required __dybatpho_cli_gsc_deprecated __dybatpho_cli_gsc_label
    local __dybatpho_cli_gsc_config __dybatpho_cli_gsc_count __dybatpho_cli_gsc_negatable
    local __dybatpho_cli_gsc_pattern __dybatpho_cli_gsc_value_type
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gsc_type __dybatpho_cli_gsc_var __dybatpho_cli_gsc_desc \
      __dybatpho_cli_gsc_switches __dybatpho_cli_gsc_env __dybatpho_cli_gsc_multiple __dybatpho_cli_gsc_choices \
      __dybatpho_cli_gsc_prompt __dybatpho_cli_gsc_hidden \
      __dybatpho_cli_gsc_required __dybatpho_cli_gsc_deprecated __dybatpho_cli_gsc_label __dybatpho_cli_gsc_config \
      __dybatpho_cli_gsc_count __dybatpho_cli_gsc_negatable __dybatpho_cli_gsc_pattern __dybatpho_cli_gsc_value_type \
      <<< "${__dybatpho_cli_gsc_option}"
    [[ "${__dybatpho_cli_gsc_env}" = "@none" ]] && __dybatpho_cli_gsc_env=""
    [[ "${__dybatpho_cli_gsc_choices}" = "@none" ]] && __dybatpho_cli_gsc_choices=""
    [[ "${__dybatpho_cli_gsc_prompt}" = "@none" ]] && __dybatpho_cli_gsc_prompt=""
    [[ "${__dybatpho_cli_gsc_deprecated}" = "@none" ]] && __dybatpho_cli_gsc_deprecated=""
    [[ "${__dybatpho_cli_gsc_label}" = "@none" ]] && __dybatpho_cli_gsc_label=""
    [[ "${__dybatpho_cli_gsc_config}" = "@none" ]] && __dybatpho_cli_gsc_config=""
    [[ "${__dybatpho_cli_gsc_pattern}" = "@none" ]] && __dybatpho_cli_gsc_pattern=""
    [[ "${__dybatpho_cli_gsc_value_type:-@none}" = "@none" ]] && __dybatpho_cli_gsc_value_type=""
    local __dybatpho_cli_gsc_q_type __dybatpho_cli_gsc_q_var __dybatpho_cli_gsc_q_desc __dybatpho_cli_gsc_q_env
    local __dybatpho_cli_gsc_q_choices __dybatpho_cli_gsc_q_prompt __dybatpho_cli_gsc_q_deprecated
    local __dybatpho_cli_gsc_q_label __dybatpho_cli_gsc_q_config __dybatpho_cli_gsc_q_pattern
    local __dybatpho_cli_gsc_q_value_type
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_config "${__dybatpho_cli_gsc_config}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_type "${__dybatpho_cli_gsc_type}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_var "${__dybatpho_cli_gsc_var}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_desc "${__dybatpho_cli_gsc_desc}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_env "${__dybatpho_cli_gsc_env}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_choices "${__dybatpho_cli_gsc_choices}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_prompt "${__dybatpho_cli_gsc_prompt}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_deprecated "${__dybatpho_cli_gsc_deprecated}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_label "${__dybatpho_cli_gsc_label}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_pattern "${__dybatpho_cli_gsc_pattern}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_value_type "${__dybatpho_cli_gsc_value_type}"
    [[ "${__dybatpho_cli_gsc_first}" = true ]] || printf ","
    __dybatpho_cli_gsc_first=false
    printf '{"type":%s,"name":%s,"description":%s,"switches":[' "${__dybatpho_cli_gsc_q_type}" \
      "${__dybatpho_cli_gsc_q_var}" "${__dybatpho_cli_gsc_q_desc}"
    local __dybatpho_cli_gsc_switch __dybatpho_cli_gsc_switch_first=true
    for __dybatpho_cli_gsc_switch in ${__dybatpho_cli_gsc_switches}; do
      __dybatpho_cli_json_quote __dybatpho_cli_gsc_switch "${__dybatpho_cli_gsc_switch}"
      [[ "${__dybatpho_cli_gsc_switch_first}" = true ]] || printf ","
      __dybatpho_cli_gsc_switch_first=false
      printf "%s" "${__dybatpho_cli_gsc_switch}"
    done
    local \
      __dybatpho_cli_gsc_option_format='],"env":%s,"config":%s,"multiple":%s,"count":%s,"negatable":%s,"choices":%s,'
    __dybatpho_cli_gsc_option_format+='"pattern":%s,"valueType":%s,"prompt":%s,"hidden":%s,"required":%s,"deprecated":%s,"label":%s}'
    # shellcheck disable=SC2059 # the format is built above, not taken from input
    printf "${__dybatpho_cli_gsc_option_format}" \
      "${__dybatpho_cli_gsc_q_env}" "${__dybatpho_cli_gsc_q_config}" "${__dybatpho_cli_gsc_multiple:-false}" \
      "${__dybatpho_cli_gsc_count:-false}" "${__dybatpho_cli_gsc_negatable:-false}" \
      "${__dybatpho_cli_gsc_q_choices}" "${__dybatpho_cli_gsc_q_pattern}" "${__dybatpho_cli_gsc_q_value_type}" \
      "${__dybatpho_cli_gsc_q_prompt}" "${__dybatpho_cli_gsc_hidden:-false}" \
      "${__dybatpho_cli_gsc_required:-false}" "${__dybatpho_cli_gsc_q_deprecated}" "${__dybatpho_cli_gsc_q_label}"
  done
  printf '],"arguments":['
  __dybatpho_cli_gsc_first=true
  for __dybatpho_cli_gsc_argument in ${__dybatpho_cli_gsc_arguments[@]+"${__dybatpho_cli_gsc_arguments[@]}"}; do
    local __dybatpho_cli_gsc_arg_name __dybatpho_cli_gsc_arg_desc __dybatpho_cli_gsc_arg_required
    local __dybatpho_cli_gsc_arg_variadic __dybatpho_cli_gsc_q_arg_name __dybatpho_cli_gsc_q_arg_desc
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gsc_arg_name __dybatpho_cli_gsc_arg_desc \
      __dybatpho_cli_gsc_arg_required __dybatpho_cli_gsc_arg_variadic <<< "${__dybatpho_cli_gsc_argument}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_arg_name "${__dybatpho_cli_gsc_arg_name}"
    __dybatpho_cli_json_quote __dybatpho_cli_gsc_q_arg_desc "${__dybatpho_cli_gsc_arg_desc}"
    [[ "${__dybatpho_cli_gsc_first}" = true ]] || printf ","
    __dybatpho_cli_gsc_first=false
    printf '{"name":%s,"description":%s,"required":%s,"variadic":%s}' \
      "${__dybatpho_cli_gsc_q_arg_name}" "${__dybatpho_cli_gsc_q_arg_desc}" "${__dybatpho_cli_gsc_arg_required:-true}" \
      "${__dybatpho_cli_gsc_arg_variadic:-false}"
  done
  printf '],"commands":['
  __dybatpho_cli_gsc_first=true
  for __dybatpho_cli_gsc_command in "${__dybatpho_cli_gsc_commands[@]}"; do
    local __dybatpho_cli_gsc_cmd __dybatpho_cli_gsc_child __dybatpho_cli_gsc_aliases __dybatpho_cli_gsc_child_hidden
    local __dybatpho_cli_gsc_child_deprecated
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gsc_cmd __dybatpho_cli_gsc_child \
      __dybatpho_cli_gsc_aliases __dybatpho_cli_gsc_child_hidden __dybatpho_cli_gsc_child_deprecated <<< \
      "${__dybatpho_cli_gsc_command}"
    [[ "${__dybatpho_cli_gsc_first}" = true ]] || printf ","
    __dybatpho_cli_gsc_first=false
    __dybatpho_cli_generate_schema_command "${__dybatpho_cli_gsc_child}" "${__dybatpho_cli_gsc_cmd}" \
      "${__dybatpho_cli_gsc_aliases}"
  done
  printf "]}"
}

#######################################
# @description Generate a roff man page from a CLI option spec.
# @arg $1 string Spec function
# @arg $2 string Optional command name
# @tip Generate the page from the root spec to include the complete nested command tree.
# @stdout Man page
#######################################
function dybatpho::generate_man {
  local __dybatpho_cli_gm_spec __dybatpho_cli_gm_name="${2:-${0##*/}}"
  dybatpho::expect_args __dybatpho_cli_gm_spec -- "$@"
  __dybatpho_cli_generate_man_command "${__dybatpho_cli_gm_spec}" "${__dybatpho_cli_gm_name}" 1
}

#######################################
# @description Write one command of a spec as a roff section, and recurse into
#   its subcommands. The root becomes the page, and every command under it a
#   subsection of the same page.
# @arg $1 string Spec function
# @arg $2 string Command name
# @arg $3 number Manual section
# @arg $4 bool Whether this is a subcommand rather than the root
# @stdout The command as roff
# @internal
#######################################
function __dybatpho_cli_generate_man_command {
  local __dybatpho_cli_gmc_spec="$1" __dybatpho_cli_gmc_name="$2" __dybatpho_cli_gmc_section="${3:-1}" \
    __dybatpho_cli_gmc_nested="${4:-false}" __dybatpho_cli_gmc_description
  local -a __dybatpho_cli_gmc_options=() __dybatpho_cli_gmc_commands=() __dybatpho_cli_gmc_arguments=()
  __dybatpho_cli_collect_spec_metadata "${__dybatpho_cli_gmc_spec}" __dybatpho_cli_gmc_options \
    __dybatpho_cli_gmc_commands __dybatpho_cli_gmc_description __dybatpho_cli_gmc_arguments
  local __dybatpho_cli_gmc_escaped
  __dybatpho_cli_gmc_escaped="${__dybatpho_cli_gmc_name//\\/\\\\}"
  __dybatpho_cli_gmc_escaped="${__dybatpho_cli_gmc_escaped//\"/\\\"}"
  local __dybatpho_cli_gmc_synopsis="${__dybatpho_cli_gmc_escaped} [OPTIONS]"
  local __dybatpho_cli_gmc_arg_item __dybatpho_cli_gmc_arg_name __dybatpho_cli_gmc_arg_desc
  local __dybatpho_cli_gmc_arg_required __dybatpho_cli_gmc_arg_variadic __dybatpho_cli_gmc_arg_placeholder
  local __dybatpho_cli_gmc_option __dybatpho_cli_gmc_command
  for __dybatpho_cli_gmc_arg_item in ${__dybatpho_cli_gmc_arguments[@]+"${__dybatpho_cli_gmc_arguments[@]}"}; do
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gmc_arg_name __dybatpho_cli_gmc_arg_desc \
      __dybatpho_cli_gmc_arg_required __dybatpho_cli_gmc_arg_variadic <<< "${__dybatpho_cli_gmc_arg_item}"
    __dybatpho_cli_gmc_arg_placeholder="$(__dybatpho_cli_arg_placeholder "${__dybatpho_cli_gmc_arg_name}" "${__dybatpho_cli_gmc_arg_required}" "${__dybatpho_cli_gmc_arg_variadic}")"
    __dybatpho_cli_gmc_synopsis="${__dybatpho_cli_gmc_synopsis} ${__dybatpho_cli_gmc_arg_placeholder}"
  done
  if [[ "${__dybatpho_cli_gmc_nested}" = false ]]; then
    printf '.TH "%s" "%s" "" "" "dybatpho"\n' "${__dybatpho_cli_gmc_escaped}" "${__dybatpho_cli_gmc_section}"
    printf '.SH NAME\n%s \\- %s\n' "${__dybatpho_cli_gmc_escaped}" "${__dybatpho_cli_gmc_description}"
    printf '.SH SYNOPSIS\n.B %s\n' "${__dybatpho_cli_gmc_synopsis}"
    if ((${#__dybatpho_cli_gmc_arguments[@]})); then
      printf '.SH ARGUMENTS\n'
      for __dybatpho_cli_gmc_arg_item in "${__dybatpho_cli_gmc_arguments[@]}"; do
        IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gmc_arg_name __dybatpho_cli_gmc_arg_desc \
          __dybatpho_cli_gmc_arg_required __dybatpho_cli_gmc_arg_variadic <<< "${__dybatpho_cli_gmc_arg_item}"
        __dybatpho_cli_gmc_arg_placeholder="$(__dybatpho_cli_arg_placeholder "${__dybatpho_cli_gmc_arg_name}" "${__dybatpho_cli_gmc_arg_required}" "${__dybatpho_cli_gmc_arg_variadic}")"
        printf '.TP\n.B %s\n%s\n' "${__dybatpho_cli_gmc_arg_placeholder}" "${__dybatpho_cli_gmc_arg_desc}"
      done
    fi
    printf '.SH OPTIONS\n'
  else
    printf '.SS %s\n%s\n' "${__dybatpho_cli_gmc_escaped}" "${__dybatpho_cli_gmc_description}"
  fi
  for __dybatpho_cli_gmc_option in "${__dybatpho_cli_gmc_options[@]}"; do
    local __dybatpho_cli_gmc_type __dybatpho_cli_gmc_var __dybatpho_cli_gmc_desc __dybatpho_cli_gmc_switches
    local __dybatpho_cli_gmc_env __dybatpho_cli_gmc_multiple __dybatpho_cli_gmc_choices __dybatpho_cli_gmc_prompt
    local __dybatpho_cli_gmc_hidden __dybatpho_cli_gmc_required __dybatpho_cli_gmc_deprecated __dybatpho_cli_gmc_label
    local __dybatpho_cli_gmc_config __dybatpho_cli_gmc_count __dybatpho_cli_gmc_negatable
    local __dybatpho_cli_gmc_pattern __dybatpho_cli_gmc_value_type
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gmc_type __dybatpho_cli_gmc_var __dybatpho_cli_gmc_desc \
      __dybatpho_cli_gmc_switches __dybatpho_cli_gmc_env __dybatpho_cli_gmc_multiple __dybatpho_cli_gmc_choices \
      __dybatpho_cli_gmc_prompt __dybatpho_cli_gmc_hidden \
      __dybatpho_cli_gmc_required __dybatpho_cli_gmc_deprecated __dybatpho_cli_gmc_label __dybatpho_cli_gmc_config \
      __dybatpho_cli_gmc_count __dybatpho_cli_gmc_negatable __dybatpho_cli_gmc_pattern __dybatpho_cli_gmc_value_type \
      <<< "${__dybatpho_cli_gmc_option}"
    [[ "${__dybatpho_cli_gmc_env}" = "@none" ]] && __dybatpho_cli_gmc_env=""
    [[ "${__dybatpho_cli_gmc_deprecated}" = "@none" ]] && __dybatpho_cli_gmc_deprecated=""
    [[ "${__dybatpho_cli_gmc_label}" = "@none" ]] && __dybatpho_cli_gmc_label=""
    [[ "${__dybatpho_cli_gmc_config}" = "@none" ]] && __dybatpho_cli_gmc_config=""
    [[ "${__dybatpho_cli_gmc_choices}" = "@none" ]] && __dybatpho_cli_gmc_choices=""
    [[ "${__dybatpho_cli_gmc_pattern}" = "@none" ]] && __dybatpho_cli_gmc_pattern=""
    [[ "${__dybatpho_cli_gmc_value_type:-@none}" = "@none" ]] && __dybatpho_cli_gmc_value_type=""
    [[ "${__dybatpho_cli_gmc_hidden:-false}" = true ]] && continue
    local __dybatpho_cli_gmc_option_label="${__dybatpho_cli_gmc_switches// /, }"
    [[ "${__dybatpho_cli_gmc_type}" = param ]] \
      && __dybatpho_cli_gmc_option_label="${__dybatpho_cli_gmc_option_label} <${__dybatpho_cli_gmc_var}>"
    printf '.TP\n.B %s\n%s' "${__dybatpho_cli_gmc_option_label}" "${__dybatpho_cli_gmc_desc}"
    [[ "${__dybatpho_cli_gmc_required:-false}" = true ]] && printf ' (required)'
    [[ -n "${__dybatpho_cli_gmc_choices}" ]] && printf ' [choices: %s]' "${__dybatpho_cli_gmc_choices//,/, }"
    [[ -n "${__dybatpho_cli_gmc_pattern}" ]] && printf ' [pattern: %s]' "${__dybatpho_cli_gmc_pattern}"
    [[ -n "${__dybatpho_cli_gmc_value_type}" ]] && printf ' [type: %s]' "${__dybatpho_cli_gmc_value_type}"
    [[ -n "${__dybatpho_cli_gmc_env}" ]] && printf ' [env: %s]' "${__dybatpho_cli_gmc_env}"
    [[ -n "${__dybatpho_cli_gmc_config}" ]] && printf ' [config: %s]' "${__dybatpho_cli_gmc_config}"
    printf '\n'
  done
  if [[ "${#__dybatpho_cli_gmc_commands[@]}" -gt 0 ]]; then
    printf '.SH COMMANDS\n'
    for __dybatpho_cli_gmc_command in "${__dybatpho_cli_gmc_commands[@]}"; do
      local __dybatpho_cli_gmc_cmd __dybatpho_cli_gmc_child __dybatpho_cli_gmc_aliases __dybatpho_cli_gmc_child_hidden
      local __dybatpho_cli_gmc_child_deprecated
      # shellcheck disable=SC2034 # child_deprecated fills a field slot this loop doesn't read
      IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gmc_cmd __dybatpho_cli_gmc_child \
        __dybatpho_cli_gmc_aliases __dybatpho_cli_gmc_child_hidden __dybatpho_cli_gmc_child_deprecated <<< \
        "${__dybatpho_cli_gmc_command}"
      [[ "${__dybatpho_cli_gmc_child_hidden:-false}" = true ]] && continue
      printf '.TP\n.B %s\n' "${__dybatpho_cli_gmc_cmd}"
      __dybatpho_cli_generate_man_command "${__dybatpho_cli_gmc_child}" "${__dybatpho_cli_gmc_cmd}" \
        "${__dybatpho_cli_gmc_section}" true
    done
  fi
}

#######################################
# @description Generate Bash, Zsh, or Fish completion from a CLI option spec.
# @arg $1 string Spec function
# @arg $2 string Shell (`bash`, `zsh`, or `fish`)
# @arg $3 string Optional command name
# @tip Keep completion generation in a display option declared inside the spec when the CLI should complete itself.
# @tip Generate completion from the root spec so subcommand options and aliases are included.
# @note Output is cached under `DYBATPHO_CLI_CACHE_DIR`, keyed by the hash of the
#       script that declares the spec, so editing the script invalidates the
#       entry on its own. Set `DYBATPHO_CLI_CACHE=false` to bypass the cache.
# @stdout Completion script
#######################################
function dybatpho::generate_completion {
  local __dybatpho_cli_gc_spec __dybatpho_cli_gc_shell __dybatpho_cli_gc_name="${3:-${0##*/}}"
  dybatpho::expect_args __dybatpho_cli_gc_spec __dybatpho_cli_gc_shell -- "$@"
  case "${__dybatpho_cli_gc_shell}" in
    bash | zsh | fish) ;; # kcov(skip)
    *) dybatpho::die "$(__dybatpho_log_text cli.unsupported_shell \
      "Unsupported completion shell: ${__dybatpho_cli_gc_shell}" "shell=${__dybatpho_cli_gc_shell}")" 1 ;; # kcov(skip)
  esac

  local __dybatpho_cli_gc_cache_file=""
  if __dybatpho_cli_cache_file __dybatpho_cli_gc_cache_file completion "${__dybatpho_cli_gc_spec}" \
    "${__dybatpho_cli_gc_shell}" "${__dybatpho_cli_gc_name}" \
    && [[ -s "${__dybatpho_cli_gc_cache_file}" ]]; then
    dybatpho::debug "Reusing cached ${__dybatpho_cli_gc_shell} completion at ${__dybatpho_cli_gc_cache_file}"
    cat -- "${__dybatpho_cli_gc_cache_file}"
    return 0
  fi

  local __dybatpho_cli_gc_generated
  __dybatpho_cli_gc_generated="$(__dybatpho_cli_generate_completion_command "${__dybatpho_cli_gc_spec}" "${__dybatpho_cli_gc_shell}" "${__dybatpho_cli_gc_name}" "${__dybatpho_cli_gc_name}")"
  printf '%s\n' "${__dybatpho_cli_gc_generated}"
  if [[ -n "${__dybatpho_cli_gc_cache_file}" ]]; then
    printf '%s\n' "${__dybatpho_cli_gc_generated}" > "${__dybatpho_cli_gc_cache_file}" 2> /dev/null || true
  fi
  return 0
}

#######################################
# @description Resolve the cache file for a generated artifact, creating the
#              cache directory when needed. The key hashes the script that
#              declares the spec, so a spec change produces a new key instead of
#              a stale hit; a spec declared from an unreadable source (a `bash -c`
#              one-liner, for example) is simply not cached.
# @arg $1 string Name of the variable receiving the cache file path
# @arg $@ string Key parts, such as the artifact kind, spec, shell, and command name
# @exitcode 0 A cache file path was resolved
# @exitcode 1 Caching is disabled or unavailable for this invocation
# @internal
#######################################
function __dybatpho_cli_cache_file {
  __dybatpho_cli_require_shell_name "$1"
  local target="$1"
  printf -v "${target}" '%s' ""
  dybatpho::is true "${DYBATPHO_CLI_CACHE}" || return 1
  shift

  local source="$0"
  [[ -f "${source}" ]] || source="${BASH_SOURCE[-1]:-}"
  [[ -f "${source}" ]] || return 1
  local digest
  digest="$(dybatpho::file_hash "${source}" 2> /dev/null)" || return 1
  [[ -n "${digest}" ]] || return 1

  local key="${digest:0:32}-$*"
  key="${key//[^a-zA-Z0-9._-]/_}"
  mkdir -p -- "${DYBATPHO_CLI_CACHE_DIR}" 2> /dev/null || return 1
  printf -v "${target}" '%s' "${DYBATPHO_CLI_CACHE_DIR}/${key}"
  return 0
}

#######################################
# @description Collect the switches a completion should offer, skipping the
#   options the spec hides.
# @arg $1 string Name of the array to fill
# @arg $@ string Option records, as `__dybatpho_cli_collect_spec_metadata` builds them
# @set The named array, one switch per element
# @internal
#######################################
function __dybatpho_cli_completion_words {
  local -n __completion_out="$1"
  local -a options=("${@:2}") option switches switch
  for option in "${options[@]}"; do
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r _ _ _ switches _ _ _ _ hidden _ _ _ _ _ _ <<< "${option}"
    [[ "${hidden:-false}" = true ]] && continue
    for switch in ${switches}; do __completion_out+=("${switch}"); done
  done
}

#######################################
# @description Write the completion for one command in the requested shell, and
#   recurse into its subcommands.
# @arg $1 string Spec function
# @arg $2 string Shell to generate for
# @arg $3 string Command name
# @arg $4 string Root command name, which the generated function is named after
# @stdout The completion script for that command
# @internal
#######################################
function __dybatpho_cli_generate_completion_command {
  # shellcheck disable=SC2034 # root keeps the positional signature uniform across generators
  local __dybatpho_cli_gcc_spec="$1" __dybatpho_cli_gcc_shell="$2" __dybatpho_cli_gcc_name="$3" \
    __dybatpho_cli_gcc_root="$4" __dybatpho_cli_gcc_description
  local -a __dybatpho_cli_gcc_options=() __dybatpho_cli_gcc_commands=() __dybatpho_cli_gcc_words=()
  __dybatpho_cli_collect_spec_metadata "${__dybatpho_cli_gcc_spec}" __dybatpho_cli_gcc_options \
    __dybatpho_cli_gcc_commands __dybatpho_cli_gcc_description
  __dybatpho_cli_completion_words __dybatpho_cli_gcc_words "${__dybatpho_cli_gcc_options[@]}"
  local __dybatpho_cli_gcc_word_list="${__dybatpho_cli_gcc_words[*]}" __dybatpho_cli_gcc_cmd_list="" \
    __dybatpho_cli_gcc_command __dybatpho_cli_gcc_cmd __dybatpho_cli_gcc_child __dybatpho_cli_gcc_aliases \
    __dybatpho_cli_gcc_hidden __dybatpho_cli_gcc_deprecated
  for __dybatpho_cli_gcc_command in "${__dybatpho_cli_gcc_commands[@]}"; do
    IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gcc_cmd __dybatpho_cli_gcc_child \
      __dybatpho_cli_gcc_aliases __dybatpho_cli_gcc_hidden __dybatpho_cli_gcc_deprecated <<< \
      "${__dybatpho_cli_gcc_command}"
    if [[ "${__dybatpho_cli_gcc_hidden:-false}" != true ]]; then
      # `@none` is the sentinel an alias-less command records, not a word the
      # user can ever type.
      [[ "${__dybatpho_cli_gcc_aliases}" = "@none" ]] && __dybatpho_cli_gcc_aliases=""
      __dybatpho_cli_gcc_cmd_list+=" ${__dybatpho_cli_gcc_cmd}${__dybatpho_cli_gcc_aliases:+ ${__dybatpho_cli_gcc_aliases}}"
      # shellcheck disable=SC2034 # out-params required by collect_spec_metadata's signature
      local -a __dybatpho_cli_gcc_child_options=() __dybatpho_cli_gcc_child_commands=()
      # shellcheck disable=SC2034 # out-param required by collect_spec_metadata's signature
      local __dybatpho_cli_gcc_child_description
      __dybatpho_cli_collect_spec_metadata "${__dybatpho_cli_gcc_child}" __dybatpho_cli_gcc_child_options \
        __dybatpho_cli_gcc_child_commands __dybatpho_cli_gcc_child_description
      __dybatpho_cli_completion_words __dybatpho_cli_gcc_words "${__dybatpho_cli_gcc_child_options[@]}"
    fi
  done
  __dybatpho_cli_gcc_word_list="${__dybatpho_cli_gcc_words[*]}"
  case "${__dybatpho_cli_gcc_shell}" in
    bash)
      # shellcheck disable=SC2016 # this is generated shell source, expanded by the caller's shell
      local __dybatpho_cli_gcc_bash_template='_%s_completion() {\n  local cur="${COMP_WORDS[COMP_CWORD]}"\n'
      # shellcheck disable=SC2016 # this is generated shell source, expanded by the caller's shell
      __dybatpho_cli_gcc_bash_template+='  COMPREPLY=( $(compgen -W %q -- "${cur}") )\n}\ncomplete -F _%s_completion %s\n'
      # shellcheck disable=SC2059 # the template is built above, not taken from input
      printf "${__dybatpho_cli_gcc_bash_template}" \
        "${__dybatpho_cli_gcc_name//[^a-zA-Z0-9_]/_}" \
        "${__dybatpho_cli_gcc_word_list} ${__dybatpho_cli_gcc_cmd_list} --help -h" \
        "${__dybatpho_cli_gcc_name//[^a-zA-Z0-9_]/_}" "${__dybatpho_cli_gcc_name}"
      ;;
    zsh)
      printf '_%s_completion() {\n  _arguments "*: :((%s))"\n}\ncompdef _%s_completion %s\n' \
        "${__dybatpho_cli_gcc_name//[^a-zA-Z0-9_]/_}" \
        "${__dybatpho_cli_gcc_word_list} ${__dybatpho_cli_gcc_cmd_list} --help -h" \
        "${__dybatpho_cli_gcc_name//[^a-zA-Z0-9_]/_}" "${__dybatpho_cli_gcc_name}"
      ;;
    fish)
      local __dybatpho_cli_gcc_switch
      for __dybatpho_cli_gcc_switch in "${__dybatpho_cli_gcc_words[@]}"; do
        case "${__dybatpho_cli_gcc_switch}" in
          --*) printf "complete -c %s -l %s\n" "${__dybatpho_cli_gcc_name}" "${__dybatpho_cli_gcc_switch#--}" ;;
          -?) printf "complete -c %s -s %s\n" "${__dybatpho_cli_gcc_name}" "${__dybatpho_cli_gcc_switch#-}" ;;
          *) ;;
        esac
      done
      for __dybatpho_cli_gcc_command in "${__dybatpho_cli_gcc_commands[@]}"; do
        IFS="${__DYBATPHO_CLI_META_SEP}" read -r __dybatpho_cli_gcc_cmd __dybatpho_cli_gcc_child \
          __dybatpho_cli_gcc_aliases __dybatpho_cli_gcc_hidden __dybatpho_cli_gcc_deprecated <<< \
          "${__dybatpho_cli_gcc_command}"
        [[ "${__dybatpho_cli_gcc_hidden:-false}" = true ]] || printf "complete -c %s -f -a %q\n" \
          "${__dybatpho_cli_gcc_name}" "${__dybatpho_cli_gcc_cmd}"
      done
      ;;
    *) ;;
  esac
}

#######################################
# @description Pad string $2 to at least length $3 and store result in variable $1
# @arg $1 string Variable name to store result
# @arg $2 string String to pad
# @arg $3 number Minimum length
# @internal
#######################################
function __dybatpho_cli_help_pad {
  __dybatpho_cli_require_shell_name "$1"
  local __p=$2
  while [[ "${#__p}" -lt "$3" ]]; do __p="${__p} "; done
  printf -v "$1" '%s' "${__p}"
}

#######################################
# @description Append a formatted switch to caller-local variable `sw`.
# Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so
# that short+long pairs align as "-s, --long".
# @arg $1 number Minimum pad width before appending $2
# @arg $2 string Switch string to append
# @internal
#######################################
function __dybatpho_cli_help_sw {
  __dybatpho_cli_help_pad sw "${sw}${sw:+, }" "$1"
  sw="${sw}$2"
}

#######################################
# @description Build one help row and print it as a record for later rendering.
#              Rendering is deferred because the column width is only known once
#              every row of every section has been collected.
# @arg $1 string Type: flag | param | disp | cmd
# @arg $2 string Variable name (or command name for cmd type)
# @arg $3 string Description
# @arg $@ switch|key:value Switches and settings of this option
# @stdout Record of `label<TAB>description<TAB>annotations`, where annotations
#         are separated by a unit separator. Nothing for a hidden row.
# @internal
#######################################
function __dybatpho_cli_help_row {
  local _type=$1 _var=$2 _desc=$3
  shift 3
  local sw="" label="" hidden="" required="false" deprecated=""
  local _env="" _config="" _choices="" _default="" _multiple="false" _count="false" _pattern="" _vtype=""
  local _negatable=false _spec_part
  # Switches are buffered by length so the label reads `-s, --long` whichever
  # order the spec declared them in.
  local -a _short_forms=() _long_forms=()
  for _spec_part in "$@"; do
    case ${_spec_part} in
      negatable:*) _negatable="${_spec_part#negatable:}" ;;
      *) ;;
    esac
  done
  while [[ $# -gt 0 ]]; do
    local _spec_part=$1 && shift
    case ${_spec_part} in
      alias:*) __dybatpho_cli_help_add_switch "${_spec_part#alias:}" "${_negatable}" ;;
      aliases:*)
        local -a _aliases=()
        local _alias_item
        __dybatpho_cli_parse_alias_list _aliases "${_spec_part#aliases:}"
        for _alias_item in "${_aliases[@]}"; do
          __dybatpho_cli_help_add_switch "${_alias_item}" "${_negatable}"
        done
        ;;
      -*) __dybatpho_cli_help_add_switch "${_spec_part}" "${_negatable}" ;;
      hidden:*) hidden="${_spec_part#hidden:}" ;;
      label:*) label="${_spec_part#label:}" ;;
      required:*) required="${_spec_part#required:}" ;;
      deprecated:*) deprecated="${_spec_part#deprecated:}" ;;
      env:*) _env="${_spec_part#env:}" ;;
      config:*) _config="${_spec_part#config:}" ;;
      choices:*) _choices="${_spec_part#choices:}" ;;
      pattern:*) _pattern="${_spec_part#pattern:}" ;;
      type:*) _vtype="${_spec_part#type:}" ;;
      init:*) _default="${_spec_part#init:}" ;;
      multiple:*) _multiple="${_spec_part#multiple:}" ;;
      count:*) _count="${_spec_part#count:}" ;;
      *) : ;;
    esac
  done

  local _form
  for _form in ${_short_forms[@]+"${_short_forms[@]}"}; do
    __dybatpho_cli_help_sw 0 "${_form}"
  done
  for _form in ${_long_forms[@]+"${_long_forms[@]}"}; do
    __dybatpho_cli_help_sw 4 "${_form}"
  done

  dybatpho::is true "${hidden}" && return 0
  if [[ "${_type}" = "param" ]] && dybatpho::is true "${required}"; then
    _desc="${_desc:+${_desc} }(required)"
  fi
  if [[ -n "${deprecated}" ]]; then
    _desc="${_desc:+${_desc} }(deprecated: ${deprecated})"
  fi

  [[ -n "${label}" ]] || case ${_type} in
    flag | disp) label="${sw}" ;;
    param) label="${sw} <${_var}>" ;;
    cmd) label="${_var}" ;;
    *) ;;
  esac

  # `env:true` reuses the variable name, and `env:false` disables the fallback.
  case "${_env}" in
    true) _env="${_var}" ;;
    false | "") _env="" ;;
    *) ;;
  esac

  local _annotations=""
  __dybatpho_cli_help_annotate _annotations "env" "${_env}"
  __dybatpho_cli_help_annotate _annotations "config" "${_config}"
  __dybatpho_cli_help_annotate _annotations "choices" "${_choices//,/, }"
  __dybatpho_cli_help_annotate _annotations "pattern" "${_pattern}"
  __dybatpho_cli_help_annotate _annotations "type" "${_vtype}"
  local cli_help_default
  cli_help_default=$(__dybatpho_cli_help_default "${_default}")
  __dybatpho_cli_help_annotate _annotations "default" "${cli_help_default}"
  dybatpho::is true "${_multiple}" \
    && _annotations="${_annotations}${_annotations:+$'\x1f'}[repeatable]"
  dybatpho::is true "${_count}" \
    && _annotations="${_annotations}${_annotations:+$'\x1f'}[repeat to increase]"

  printf '%s\t%s\t%s\n' "${label}" "${_desc}" "${_annotations}"
}

#######################################
# @description Sort one declared switch into the caller-local `_short_forms` and
#              `_long_forms` buffers, expanding bracketed and `negatable:true`
#              forms on the way.
# @arg $1 switch Declared switch
# @arg $2 bool Whether the owning option is negatable
# @internal
#######################################
function __dybatpho_cli_help_add_switch {
  local -a _forms=()
  local _form
  __dybatpho_cli_expand_switch _forms "$1" "${2:-false}"
  for _form in ${_forms[@]+"${_forms[@]}"}; do
    case ${_form} in
      -?) _short_forms+=("${_form}") ;;
      *) _long_forms+=("${_form}") ;;
    esac
  done
  return 0
}

#######################################
# @description Append a `[name: value]` annotation to a caller variable, or do
#              nothing when the value is empty.
# @arg $1 string Name of the variable holding the annotation list
# @arg $2 string Annotation name
# @arg $3 string Annotation value
# @internal
#######################################
function __dybatpho_cli_help_annotate {
  __dybatpho_cli_require_shell_name "$1"
  local _value="${3-}"
  [[ -n "${_value}" ]] || return 0
  local _current="${!1}"
  printf -v "$1" '%s' "${_current}${_current:+$'\x1f'}[$2: ${_value}]"
}

#######################################
# @description Render the literal default of an `init:` form, or nothing when
#              the default is empty, dynamic, or an `init:@...` directive that
#              has no value to show.
# @arg $1 string Raw `init:` value
# @stdout Literal default value
# @internal
#######################################
function __dybatpho_cli_help_default {
  local _raw="${1-}"
  case "${_raw}" in
    "" | @*) return 0 ;;
    action:*) return 0 ;;
    *) ;;
  esac
  _raw="${_raw#=}"
  case "${_raw}" in
    \"*\") _raw="${_raw:1:${#_raw}-2}" ;;
    \'*\') _raw="${_raw:1:${#_raw}-2}" ;;
    *) ;;
  esac
  # A command substitution or variable reference is resolved at run time, so
  # printing the expression itself would mislead more than it helps.
  case "${_raw}" in
    *'$'* | *'`'*) return 0 ;;
    *) ;;
  esac
  [[ -n "${_raw}" ]] || return 0
  printf '%s' "${_raw}"
}

#######################################
# @description Print every collected help row, aligned to a shared column.
# @arg $1 number Description column width
# @arg $@ string Row records from `__dybatpho_cli_help_row`
# @stdout Rendered rows
# @internal
#######################################
function __dybatpho_cli_help_render_rows {
  local _width="$1"
  shift
  local _row _label _desc _annotations _padded _blank _annotation
  __dybatpho_cli_help_pad _blank "" "${_width}"
  for _row in "$@"; do
    [[ -n "${_row}" ]] || continue
    # Split by hand rather than with `read`: a tab is whitespace to `read`, so an
    # empty description would collapse into the separators around it and the
    # annotations would land in the description column.
    _label="${_row%%$'\t'*}"
    _desc=""
    [[ "${_row}" == *$'\t'* ]] && _desc="${_row#*$'\t'}"
    _annotations=""
    if [[ "${_desc}" == *$'\t'* ]]; then
      _annotations="${_desc#*$'\t'}"
      _desc="${_desc%%$'\t'*}"
    fi
    # A `msg` row is free text, not an option: it owns the whole line instead of
    # the description column, so a spec can head a group of options with it.
    if [[ "${_label}" = "${__DYBATPHO_CLI_MSG_LABEL}" ]]; then
      printf '%s\n' "${_desc}"
      continue
    fi
    __dybatpho_cli_help_pad _padded "${__help_leading}${_label}" "${_width}"
    if [[ "${#_padded}" -le "${_width}" ]]; then
      printf '%s\n' "${_padded}${_desc}"
    else
      printf '%s\n' "${_padded}"
      [[ -n "${_desc}" ]] && printf '%s\n' "${_blank}${_desc}"
    fi
    if [[ -n "${_annotations}" ]]; then
      # Annotations are read into an array rather than word-split in place:
      # they look like `[env: NAME]`, which pathname expansion would treat as a
      # bracket glob and drop entirely under `nullglob`.
      local -a _parts=()
      IFS=$'\x1f' read -r -a _parts <<< "${_annotations}"
      for _annotation in ${_parts[@]+"${_parts[@]}"}; do
        [[ -n "${_annotation}" ]] && printf '%s\n' "${_blank}${_annotation}"
      done
    fi
  done
  return 0
}

#######################################
# @description Drop rows whose label was already collected, keeping the first.
# @arg $1 string Name of the array of row records to rewrite in place
# @internal
#######################################
function __dybatpho_cli_help_dedupe {
  __dybatpho_cli_require_shell_name "$1"
  local -n _rows="$1"
  ((${#_rows[@]})) || return 0
  local -a _unique=()
  local -A _seen=()
  local _row _label
  for _row in "${_rows[@]}"; do
    [[ -n "${_row}" ]] || continue
    _label="${_row%%$'\t'*}"
    # Message rows all carry the same sentinel label; deduping by label would
    # keep only the first of them.
    if [[ "${_label}" = "${__DYBATPHO_CLI_MSG_LABEL}" ]]; then
      _unique+=("${_row}")
      continue
    fi
    [[ -v "_seen[${_label}]" ]] && continue
    _seen["${_label}"]=1
    _unique+=("${_row}")
  done
  _rows=(${_unique[@]+"${_unique[@]}"})
  return 0
}

#######################################
# @description Choose the description column width that fits every row, so the
#              Arguments, Commands, and Options sections line up with each other.
# @arg $1 string Name of the variable receiving the width
# @arg $@ string Row records from `__dybatpho_cli_help_row`
# @internal
#######################################
function __dybatpho_cli_help_width_for {
  __dybatpho_cli_require_shell_name "$1"
  local _target="$1" _row _label
  local -i _width=0 _length
  shift
  for _row in "$@"; do
    [[ -n "${_row}" ]] || continue
    _label="${_row%%$'\t'*}"
    [[ "${_label}" = "${__DYBATPHO_CLI_MSG_LABEL}" ]] && continue
    _length=$((${#_label} + ${#__help_leading} + 2))
    ((_length > _width)) && _width=${_length}
  done
  # Below the floor the descriptions crowd the labels; above the ceiling a
  # single long switch would push every description off the right of the screen.
  ((_width < 12)) && _width=12
  ((_width > 36)) && _width=36
  printf -v "${_target}" '%s' "${_width}"
}

#######################################
# @description Add to switches list if flag/param has multiple switches
# @arg $1 switch Switch
# @internal
#######################################
function __dybatpho_cli_add_switch {
  __switch="${__switch}${__switch:+|}$1"
  # The same switches feed the "did you mean" suggestion list, so they are
  # recorded here rather than walked a second time.
  local __token
  for __token in ${1//|/ }; do
    __token="${__token#\'}"
    __token="${__token%\'}"
    [[ -n "${__token}" ]] && __known_switches+=("${__token}")
  done
  return 0
}

#######################################
# @description Build the `Did you mean ...` suffix appended to an unrecognized
#              option or command error. Called from generated parser code.
# @arg $1 string Mistyped input
# @arg $@ string Known candidates
# @stdout Suggestion suffix, or nothing when no candidate is close enough
# @exitcode 0
# @internal
#######################################
function __dybatpho_cli_suggest_suffix {
  local input="${1-}"
  shift || true
  (($#)) || return 0
  local -a matches=()
  mapfile -t matches < <(dybatpho::cli_suggest "${input}" "$@" || true)
  ((${#matches[@]})) || return 0
  if ((${#matches[@]} == 1)); then
    __dybatpho_log_text cli.did_you_mean \
      "$(printf ". Did you mean '%s'?" "${matches[0]}")" \
      "suggestion=${matches[0]}"
  else
    local joined="" match
    for match in "${matches[@]}"; do joined="${joined}${joined:+, }'${match}'"; done
    __dybatpho_log_text cli.did_you_mean_one_of \
      "$(printf ". Did you mean one of %s?" "${joined}")" \
      "suggestions=${joined}"
  fi
  return 0
}

#######################################
# @description Add a literal switch to the switches list, pairing a long switch
#              with its `--no-` form when the option is declared `negatable:true`.
#              Short switches and switches that already carry a negative prefix
#              are added unchanged.
# @arg $1 switch Switch such as `-c` or `--color`
# @internal
#######################################
function __dybatpho_cli_add_plain_switch {
  local __plain="$1"
  if dybatpho::is true "${__negatable:-false}"; then
    case ${__plain} in
      --no-* | --without-*) ;;
      --*)
        __dybatpho_cli_add_switch "'${__plain}'|'--no-${__plain#--}'"
        return 0
        ;;
      *) ;;
    esac
  fi
  __dybatpho_cli_add_switch "'${__plain}'"
}

#######################################
# @description Expand one declared switch into the concrete switches a user can
#              type, honouring `--{no-}name`, `--with{out}-name`, and
#              `negatable:true`. Results are appended to a caller-provided array.
# @arg $1 string Name of destination array variable
# @arg $2 switch Declared switch
# @arg $3 bool Whether the owning option is `negatable:true`, default `false`
# @internal
#######################################
function __dybatpho_cli_expand_switch {
  __dybatpho_cli_require_shell_name "$1"
  local -n __expand_out="$1"
  local __declared="$2" __expand_negatable="${3:-false}"
  case ${__declared} in
    --\{no-\}*)
      __expand_out+=("--${__declared#--\{no-\}}" "--no-${__declared#--\{no-\}}")
      ;;
    --with\{out\}-*)
      __expand_out+=("--with-${__declared#--with\{out\}-}" "--without-${__declared#--with\{out\}-}")
      ;;
    --no-* | --without-*) __expand_out+=("${__declared}") ;;
    --*)
      __expand_out+=("${__declared}")
      dybatpho::is true "${__expand_negatable}" \
        && __expand_out+=("--no-${__declared#--}")
      ;;
    -?) __expand_out+=("${__declared}") ;;
    *) ;;
  esac
  return 0
}

#######################################
# @description Emit generated code that validates the current `OPTARG` and assigns it to the destination variable.
# @arg $1 string Destination variable name, or `-` to skip assignment
# @stdout Generated parser code
# @note Uses caller-local `__validate` when a custom validator was configured for the current option
# @internal
#######################################
function __dybatpho_cli_print_validate {
  set -- "${__validate}" "$1"
  if [[ -n "${__choices:-}" ]]; then
    local __choices_quoted
    __dybatpho_cli_assign_quoted __choices_quoted "${__choices}"
    __dybatpho_cli_print_indent 4 \
      "dybatpho::opts::validate_choice \"\$OPTARG\" ${__choices_quoted} || { set \"choice\" \"\$OPTARG\"; break; }"
  fi
  if [[ -n "${__type:-}" ]]; then
    # The type name is resolved here rather than in the generated script, so a
    # spec naming a type that does not exist fails while the parser is being
    # built instead of on the first value a user types. A canonical name is
    # `^[a-z][a-z0-9_]*$`, which is why it can be interpolated unquoted.
    local __type_canonical
    __dybatpho_validate_canonical __type_canonical "${__type}" \
      || dybatpho::die "$(__dybatpho_log_text cli.unknown_type \
        "Unknown type: ${__type}" "type=${__type}")"
    __dybatpho_cli_print_indent 4 "dybatpho::validate_is ${__type_canonical} \"\$OPTARG\" || { set \"type:${__type_canonical}\" \"\$OPTARG\"; break; }"
  fi
  if [[ -n "${__pattern:-}" ]]; then
    # The pattern is a `case` glob, so it reaches the generated script
    # unquoted on purpose; `__dybatpho_cli_require_case_pattern` is what keeps
    # that from turning into an injection point.
    __dybatpho_cli_require_case_pattern "${__pattern}"
    local __pattern_message
    __dybatpho_cli_assign_quoted __pattern_message "pattern:${__pattern}"
    __dybatpho_cli_print_indent 4 \
      "case \$OPTARG in ${__pattern}) ;; *) set ${__pattern_message} \"\$OPTARG\"; break ;; esac"
  fi
  [[ -n "$1" ]] && __dybatpho_cli_print_indent 4 "$1 || { set -- ${1%% *}:\$? \"\$1\" $1; break; }"
  if [[ "$2" != "-" ]]; then
    if dybatpho::is true "${__count:-false}"; then
      # A counting flag ignores the on/off value and records how often it was
      # repeated, so `-vv` and `-v -v` both land on 2.
      __dybatpho_cli_print_indent 4 "$2=\$(( \${$2:-0} + 1 ))"
      [[ "${__export}" = "true" ]] && __dybatpho_cli_print_indent 4 "export $2"
    elif dybatpho::is true "${__multiple:-false}"; then
      __dybatpho_cli_print_indent 4 "[ -n \"\${$2:-}\" ] && $2=\"\${$2} \$OPTARG\" || $2=\"\$OPTARG\""
      [[ "${__export}" = "true" ]] && __dybatpho_cli_print_indent 4 "export $2"
    else
      local cli_prepend_export
      cli_prepend_export=$(__dybatpho_cli_prepend_export "$2=\$OPTARG")
      __dybatpho_cli_print_indent 4 "${cli_prepend_export}"
    fi
  fi
}

#######################################
# @description Split a comma-separated alias list into a caller-provided array.
# @arg $1 string Name of destination array variable
# @arg $2 string Comma-separated aliases
# @exitcode 0 Aliases appended to destination array
# @internal
#######################################
function __dybatpho_cli_parse_alias_list {
  __dybatpho_cli_require_shell_name "$1"
  local -n __alias_out="$1"
  local __alias_raw="${2:-}" __alias_item
  local -a __alias_items=()
  IFS=',' read -r -a __alias_items <<< "${__alias_raw}"
  for __alias_item in "${__alias_items[@]}"; do
    [[ -n "${__alias_item}" ]] && __alias_out+=("${__alias_item}")
  done
}

#######################################
# @description Serialize an option definition so it can be replayed for persistent descendant commands.
# @arg $1 string Option type (`flag`, `param`, or `disp`)
# @arg $@ string Original arguments passed to the option helper
# @exitcode 0 Definition stored for later replay
# @internal
#######################################
function __dybatpho_cli_record_persistent_def {
  local __kind="$1" __serialized="dybatpho::opts::$1" __part
  shift
  for __part in "$@"; do
    printf -v __part '%q' "${__part}"
    __serialized+=" ${__part}"
  done
  __persistent_defs+=("${__serialized}")
}

#######################################
# @description Replay inherited persistent option definitions inside the current parser/help generation context.
# @noargs
# @exitcode 0 All inherited persistent definitions were replayed
# @internal
#######################################
function __dybatpho_cli_replay_persistent_defs {
  local __persistent_def
  local __persistent_replay=true
  for __persistent_def in "${__persistent_inherited_defs[@]}"; do
    eval "${__persistent_def}"
  done
}

#######################################
# @description Emit generated code that seeds persistent option definitions for nested help output.
# @noargs
# @stdout Generated parser code
# @internal
#######################################
function __dybatpho_cli_print_persistent_help_defs {
  local __persistent_def __quoted_def __has_defs=false
  for __persistent_def in "${__persistent_inherited_defs[@]}" "${__persistent_defs[@]}"; do
    [[ -n "${__persistent_def}" ]] || continue
    if dybatpho::is false "${__has_defs}"; then
      __dybatpho_cli_print_indent 1 'local -a __persistent_help_defs=()'
      __has_defs=true
    fi
    __dybatpho_cli_assign_quoted __quoted_def "${__persistent_def}"
    __dybatpho_cli_print_indent 1 "__persistent_help_defs+=( ${__quoted_def} )"
  done
}

#######################################
# @description Emit generated code declaring the switches and command names the
#              current command accepts, used to suggest a close match when the
#              user mistypes one.
# @noargs
# @stdout Generated parser code
# @internal
#######################################
function __dybatpho_cli_print_known_candidates {
  local __candidate __quoted __line=""
  for __candidate in ${__known_switches[@]+"${__known_switches[@]}"} "--help" "-h"; do
    printf -v __quoted '%q' "${__candidate}"
    __line="${__line}${__line:+ }${__quoted}"
  done
  __dybatpho_cli_print_indent 1 "local -a __cli_known_opts=(${__line})"
  __line=""
  local __sub_entry __sub_name
  for __sub_entry in ${__sub_specs[@]+"${__sub_specs[@]}"}; do
    __sub_name="${__sub_entry#*$'\t'}"
    __sub_name="${__sub_name%%$'\t'*}"
    [[ -n "${__sub_name}" ]] || continue
    printf -v __quoted '%q' "${__sub_name}"
    __line="${__line}${__line:+ }${__quoted}"
  done
  __dybatpho_cli_print_indent 1 "local -a __cli_known_cmds=(${__line})"
}

#######################################
# @description Emit generated code that warns when a deprecated CLI item is used.
# @arg $1 string Item type label (`option` or `command`)
# @arg $2 string Item label shown in the warning
# @arg $3 string Deprecation message
# @stdout Generated parser code
# @internal
#######################################
function __dybatpho_cli_print_deprecated_warning {
  local __item_type="$1" __item_label="$2" __message="$3"
  local __warning __english
  __english="$(__dybatpho_log_text "cli.deprecated_${__item_type}" \
    "Deprecated ${__item_type}: ${__item_label}. ${__message}" \
    "item=${__item_label}" "message=${__message}")"
  __dybatpho_cli_assign_quoted __warning "${__english}"
  __dybatpho_cli_print_indent 4 "dybatpho::warn ${__warning}"
}

#######################################
# @description Generate parser logic for a child command with inherited persistent option definitions.
# @arg $1 string Child spec function
# @arg $@ string Original CLI arguments
# @stdout Generated parser code
# @internal
#######################################
function __dybatpho_cli_generate_child_logic {
  local __child_spec="$1"
  shift
  local -a __persistent_inherited_defs=("${__persistent_inherited_defs[@]}" "${__persistent_defs[@]}")
  __dybatpho_cli_generate_logic "${__child_spec}" "$@"
}

#######################################
# @description Emit generated code that copies the collected positional
#              arguments into the variables declared with `dybatpho::opts::arg`,
#              in declaration order. A `variadic:true` argument is the last one
#              and receives every remaining value as an array, so the values it
#              holds keep their boundaries.
# @arg $1 string Name of the rest array holding the collected arguments
# @arg $@ string Declared argument records of `required<TAB>variadic<TAB>varname`
# @stdout Generated parser code
# @exitcode 0 Nothing is emitted when no argument was declared
# @internal
#######################################
function __dybatpho_cli_print_arg_bindings {
  local __rest_name="$1"
  shift
  (($#)) || return 0
  local __entry __entry_required __entry_variadic __entry_var
  local -i __index=0
  for __entry in "$@"; do
    IFS=$'\t' read -r __entry_required __entry_variadic __entry_var <<< "${__entry}"
    # `-` is the documented way to describe an argument in help without binding
    # it, matching what `flag` and `param` accept for their destination.
    [[ "${__entry_var}" = "-" ]] && {
      __index+=1
      continue
    }
    __dybatpho_cli_require_shell_name "${__entry_var}"
    if dybatpho::is true "${__entry_variadic}"; then
      __dybatpho_cli_print_indent 2 "${__entry_var}=(\"\${${__rest_name}[@]:${__index}}\")"
    else
      # `-` as the fallback keeps an omitted optional argument as the empty
      # string rather than tripping `set -u`.
      __dybatpho_cli_print_indent 2 "${__entry_var}=\"\${${__rest_name}[${__index}]-}\""
    fi
    __index+=1
  done
  return 0
}

#######################################
# @description
#   Emit generated code that validates the positional argument count configured by `args:<rule>` in
#   `dybatpho::opts::setup`.
# @arg $1 string Argument count rule (`none`, `exact:N`, `min:N`, `max:N`, `range:M:N`, `any`)
# @stdout Generated parser code
# @exitcode 0 Rule accepted and code emitted
# @internal
#######################################
# shellcheck disable=SC2016 # every literal here is generated shell source, expanded by the caller
function __dybatpho_cli_print_args_check {
  local rule="${1:-any}"
  local expected min max noun

  case "${rule}" in
    "" | any | arbitrary) return 0 ;;
    none | noargs)
      __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
      __dybatpho_cli_print_indent 3 '[ "${__rest_argc}" -eq 0 ] || set "argcount" "$(__dybatpho_log_text cli.args_none "Expected no arguments, got ${__rest_argc}" "got=${__rest_argc}")"'
      __dybatpho_cli_print_indent 2 '}'
      ;;
    exact:*)
      expected="${rule#exact:}"
      dybatpho::validate_is uint "${expected}" \
        || {
          local log_text_detail
          log_text_detail=$(__dybatpho_log_text cli.invalid_args_rule "Invalid args rule: ${rule}" "rule=${rule}")
          dybatpho::die "${log_text_detail}"
        }
      noun="arguments"
      [[ "${expected}" -eq 1 ]] && noun="argument"
      __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
      __dybatpho_cli_print_indent 3 "[ \"\${__rest_argc}\" -eq ${expected} ] || set \"argcount\" \"\$(__dybatpho_log_text_n cli.args_exact ${expected} \"Expected exactly ${expected} ${noun}, got \${__rest_argc}\" \"expected=${expected}\" \"got=\${__rest_argc}\")\""
      __dybatpho_cli_print_indent 2 '}'
      ;;
    min:*)
      min="${rule#min:}"
      dybatpho::validate_is uint "${min}" \
        || {
          local log_text_detail
          log_text_detail=$(__dybatpho_log_text cli.invalid_args_rule "Invalid args rule: ${rule}" "rule=${rule}")
          dybatpho::die "${log_text_detail}"
        }
      noun="arguments"
      [[ "${min}" -eq 1 ]] && noun="argument"
      __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
      __dybatpho_cli_print_indent 3 "[ \"\${__rest_argc}\" -ge ${min} ] || set \"argcount\" \"\$(__dybatpho_log_text_n cli.args_min ${min} \"Expected at least ${min} ${noun}, got \${__rest_argc}\" \"expected=${min}\" \"got=\${__rest_argc}\")\""
      __dybatpho_cli_print_indent 2 '}'
      ;;
    max:*)
      max="${rule#max:}"
      dybatpho::validate_is uint "${max}" \
        || {
          local log_text_detail
          log_text_detail=$(__dybatpho_log_text cli.invalid_args_rule "Invalid args rule: ${rule}" "rule=${rule}")
          dybatpho::die "${log_text_detail}"
        }
      noun="arguments"
      [[ "${max}" -eq 1 ]] && noun="argument"
      __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
      __dybatpho_cli_print_indent 3 "[ \"\${__rest_argc}\" -le ${max} ] || set \"argcount\" \"\$(__dybatpho_log_text_n cli.args_max ${max} \"Expected at most ${max} ${noun}, got \${__rest_argc}\" \"expected=${max}\" \"got=\${__rest_argc}\")\""
      __dybatpho_cli_print_indent 2 '}'
      ;;
    range:*)
      min="${rule#range:}"
      max="${min#*:}"
      min="${min%%:*}"
      dybatpho::validate_is uint "${min}" && dybatpho::validate_is uint "${max}" \
        && [[ "${min}" -le "${max}" ]] \
        || {
          local log_text_detail
          log_text_detail=$(__dybatpho_log_text cli.invalid_args_rule "Invalid args rule: ${rule}" "rule=${rule}")
          dybatpho::die "${log_text_detail}"
        }
      __dybatpho_cli_print_indent 2 '[ $# -eq 0 ] && {'
      __dybatpho_cli_print_indent 3 "[ \"\${__rest_argc}\" -ge ${min} ] && [ \"\${__rest_argc}\" -le ${max} ] || set \"argcount\" \"\$(__dybatpho_log_text cli.args_range \"Expected between ${min} and ${max} arguments, got \${__rest_argc}\" \"min=${min}\" \"max=${max}\" \"got=\${__rest_argc}\")\""
      __dybatpho_cli_print_indent 2 '}'
      ;;
    *)
      local log_text
      log_text=$(__dybatpho_log_text cli.invalid_args_rule "Invalid args rule: ${rule}" "rule=${rule}")
      dybatpho::die "${log_text}" # kcov(skip)
      ;;
  esac
}

#######################################
# @description Expand option switches and aliases into a caller-provided array.
# @arg $1 string Name of destination array
# @arg $@ switch|key:value Option metadata
# @internal
#######################################
function __dybatpho_cli_collect_switches {
  __dybatpho_cli_require_shell_name "$1"
  local __target="$1"
  shift
  local __spec_part __alias __collect_negatable=false
  for __spec_part in "$@"; do
    case "${__spec_part}" in
      negatable:*) __collect_negatable="${__spec_part#negatable:}" ;;
      *) ;;
    esac
  done
  for __spec_part in "$@"; do
    case "${__spec_part}" in
      alias:*)
        __dybatpho_cli_expand_switch "${__target}" "${__spec_part#alias:}" "${__collect_negatable}"
        ;;
      aliases:*)
        local -a __aliases=()
        __dybatpho_cli_parse_alias_list __aliases "${__spec_part#aliases:}"
        for __alias in "${__aliases[@]}"; do
          __dybatpho_cli_expand_switch "${__target}" "${__alias}" "${__collect_negatable}"
        done
        ;;
      -*) __dybatpho_cli_expand_switch "${__target}" "${__spec_part}" "${__collect_negatable}" ;;
      *) continue ;;
    esac
  done
}

#######################################
# @description Escape a value for JSON and store it in a caller variable.
# @arg $1 string Name of the variable to write into
# @arg $2 string Value to quote
# @internal
#######################################
function __dybatpho_cli_json_quote {
  __dybatpho_cli_require_shell_name "$1"
  local __dybatpho_cli_json_value
  __dybatpho_log_json_escape_into __dybatpho_cli_json_value "${2-}"
  printf -v "$1" '%s' "\"${__dybatpho_cli_json_value}\""
}

#######################################
# @description Join metadata fields into one record with the metadata separator.
# @arg $1 string Name of the variable receiving the record
# @arg $@ string Fields, in record order
# @set The named variable
# @internal
#######################################
function __dybatpho_cli_meta_join {
  local -n __meta_join_out="$1"
  shift
  local IFS="${__DYBATPHO_CLI_META_SEP}"
  __meta_join_out="$*"
}

#######################################
# @description Collect option and command metadata from a CLI spec.
# @arg $1 string Spec function
# @arg $2 string Name of the array to fill with the options
# @arg $3 string Name of the array to fill with the commands
# @arg $4 string Name of the variable to fill with the description
# @arg $5 string Optional name of the array to fill with the arguments
# @internal
#######################################
function __dybatpho_cli_collect_spec_metadata {
  local __meta_spec="$1"
  local -n __meta_options_out="$2" __meta_commands_out="$3" __meta_description_out="$4"
  local __meta_mode=true __meta_description=""
  local -a __meta_options=() __meta_commands=() __meta_args=()
  local __done_initial=false __flags="" __params=""
  "${__meta_spec}"
  __meta_options_out=("${__meta_options[@]}")
  __meta_commands_out=("${__meta_commands[@]}")
  __meta_description_out="${__meta_description}"
  # The arguments array is optional so existing three-output callers keep
  # working; only the schema and man generators ask for it.
  if [[ -n "${5-}" ]]; then
    local -n __meta_args_out="$5"
    __meta_args_out=(${__meta_args[@]+"${__meta_args[@]}"})
  fi
  return 0
}

# @section Spec functions
# @description Functions work in spec of script or function via `dybatpho::generate_from_spec`.

#######################################
# @description Setup global settings for getting options (mandatory) in spec
# of script or function
# @arg $1 string Description of sub-command/root command
# @arg $2 string Name of the array variable receiving positional arguments, or `-` to discard them
# @arg $@ key:value Settings `key:value` for sub-command/root command such as `action:<code>`, `prerun:<code>`,
#   `postrun:<code>`, and `args:<rule>`
# @tip Call `setup` before declaring any flags, params, display options, or subcommands.
# @note The rest variable is a Bash array. Read it as `"${REST[@]}"` to iterate
#       and `"${#REST[@]}"` to count. An argument containing spaces, quotes, or
#       newlines therefore survives parsing as one element.
# @warning Bash cannot export an array, so `export:` does not apply to it. Under
#          `set -u` a scalar read such as `${REST}` fails on an empty array
#          instead of yielding the empty string.
# @tip Keep the action focused on command behavior; validation and lifecycle hooks are applied by the generated parser.
# @note `args:<rule>` supports raw rules plus Cobra-like names such as `NoArgs`, `ExactArgs:N`, and `RangeArgs:M:N`
# @note `prerun:<code>` runs before `action:<code>`, and `postrun:<code>` runs after it
# @exitcode 0 exit code
#######################################
function dybatpho::opts::setup {
  local description
  dybatpho::expect_args description -- "$@"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __meta_description="${description}"
    return 0
  fi

  if dybatpho::is true "${__cmd_desc_mode:-false}"; then
    __cmd_desc="${description}"
    return 0
  fi

  shift

  if dybatpho::is true "${__help_mode:-false}"; then
    __help_description="${description}"
    # The usage line is built once the whole spec has been walked, because it
    # depends on subcommands and positional arguments declared after `setup`.
    local __setup_item
    for __setup_item in "$@"; do
      case "${__setup_item}" in
        args:*) __help_args_rule="${__setup_item#args:}" ;;
        *) ;;
      esac
    done
    return 0
  fi

  # HACK: __rest is defined in __dybatpho_cli_generate_logic, so we need to define it here
  if [[ -n "${1#-}" ]]; then
    __dybatpho_cli_require_shell_name "$1"
    __rest="$1"
  else
    __rest="__rest"
  fi

  if dybatpho::is false "${__done_initial}"; then
    __init="@empty"
    while dybatpho::still_has_args "$@" && shift; do
      __dybatpho_cli_parse_key_value "$1" "__"
    done
    # The rest variable collects positional arguments, so it is an array rather
    # than a string. `__dybatpho_cli_define_var` models scalar options with
    # `env:`/`config:`/`init:` fallbacks, none of which apply here. `-g` is
    # required because the generated script is sourced from inside a function,
    # where a bare `declare` would create a local the action could not read.
    # Bash cannot export an array, so `export:` has nothing to say about it.
    __dybatpho_cli_print_indent 0 "declare -ga ${__rest}=()"
    __setup_prerun="${__prerun}"
    __setup_action="${__action}"
    __setup_postrun="${__postrun}"
  fi
}

# shellcheck disable=2016
#######################################
# @description Define an option that take no argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` /
#   `aliases:<a,b>`
# @tip Use `on:` and `off:` with a paired `--{no-}name` switch to model boolean toggles.
# @tip Use `persistent:true` for options that must be accepted by every descendant command.
# @note Use `persistent:true` to make the flag available to descendant subcommands
# @exitcode 0 exit code
#######################################
function dybatpho::opts::flag {
  local description var
  dybatpho::expect_args description var -- "$@"
  __dybatpho_cli_require_shell_name "${var}"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __dybatpho_cli_parse_opt false 2 "$@"
    local -a __meta_switches=()
    __dybatpho_cli_collect_switches __meta_switches "${@:3}"
    local __meta_record
    __dybatpho_cli_meta_join __meta_record flag "${var}" "${description}" "${__meta_switches[*]}" \
      "${__env:-@none}" "${__multiple:-false}" "${__choices:-@none}" "${__prompt:-@none}" \
      "${__hidden:-false}" "${__required:-false}" "${__deprecated:-@none}" "${__label:-@none}" \
      "${__config:-@none}" "${__count:-false}" "${__negatable:-false}" "${__pattern:-@none}" \
      "${__type:-@none}"
    __meta_options+=("${__meta_record}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__dybatpho_cli_help_row flag "${var}" "${description}" "${@:3}")
    [[ -n "${_line}" ]] && __help_opt_rows+=("${_line}")
    return 0
  fi

  __dybatpho_cli_parse_opt false 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    if dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
      __dybatpho_cli_record_persistent_def flag "$@"
    fi
    __dybatpho_cli_define_var "${var}"
  else
    __dybatpho_cli_print_indent 3 "${__switch})"
    [[ -n "${__deprecated}" ]] && __dybatpho_cli_print_deprecated_warning "option" "${__label:-${var}}" "${__deprecated}"
    __dybatpho_cli_print_indent 4 '[ "${OPTARG:-}" ] && OPTARG=${OPTARG#*\=} && set "noarg" "$1" && break'
    __dybatpho_cli_print_indent 4 "eval '[ \${OPTARG+x} ] &&:' && OPTARG=${__on} || OPTARG=${__off}"
    __dybatpho_cli_print_validate "${var}" '$OPTARG'
    __dybatpho_cli_print_indent 4 ";;"
  fi
}

# shellcheck disable=2016
#######################################
# @description Define an option that take an argument
# @arg $1 string Description of option to display
# @arg $2 string Variable name for getting option. `-` if want to omit
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` /
#   `aliases:<a,b>`
# @tip Use `required:true` when the option itself must be present
# @tip Use `optional:true` when the option may appear without an explicit value
# @tip `optional:true` controls whether a value is required after the switch appears, while `required:true` controls
#   whether the switch itself must appear at all
# @tip Keep conditional requirements such as "required unless `--list` is set" in your action or validation logic
# @note Use `persistent:true` to make the param available to descendant subcommands
# @tip Use `env:NAME` for an environment fallback; an explicit command-line value always takes precedence.
# @tip Combine `prompt:` with `choices:` to interactively request a missing value from a constrained set.
# @exitcode 0 exit code
#######################################
function dybatpho::opts::param {
  local description var
  dybatpho::expect_args description var -- "$@"
  __dybatpho_cli_require_shell_name "${var}"

  if dybatpho::is true "${__meta_mode:-false}"; then
    __dybatpho_cli_parse_opt true 2 "$@"
    local -a __meta_switches=()
    __dybatpho_cli_collect_switches __meta_switches "${@:3}"
    local __meta_record
    __dybatpho_cli_meta_join __meta_record param "${var}" "${description}" "${__meta_switches[*]}" \
      "${__env:-@none}" "${__multiple:-false}" "${__choices:-@none}" "${__prompt:-@none}" \
      "${__hidden:-false}" "${__required:-false}" "${__deprecated:-@none}" "${__label:-@none}" \
      "${__config:-@none}" "${__count:-false}" "${__negatable:-false}" "${__pattern:-@none}" \
      "${__type:-@none}"
    __meta_options+=("${__meta_record}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__dybatpho_cli_help_row param "${var}" "${description}" "${@:3}")
    [[ -n "${_line}" ]] && __help_opt_rows+=("${_line}")
    return 0
  fi

  __dybatpho_cli_parse_opt true 2 "$@"
  if dybatpho::is false "${__done_initial}"; then
    if dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
      __dybatpho_cli_record_persistent_def param "$@"
    fi
    __dybatpho_cli_define_var "${var}"
    if [[ -n "${__prompt}" ]]; then
      # A unit separator keeps empty fields, which tabs would collapse on read.
      __prompt_defs+=("${var}"$'\x1f'"${__prompt}"$'\x1f'"${__choices}"$'\x1f'"${__multiple}"$'\x1f'"${__export}")
    fi
    if dybatpho::is true "${__required}"; then
      local __required_marker="__dybatpho_required_${__dybatpho_cli_logic_spec//[^a-zA-Z0-9_]/_}_${var}"
      local __saved_init="${__init}" __saved_export="${__export}"
      __init="@empty"
      __export="false"
      __dybatpho_cli_define_var "${__required_marker}"
      __init="${__saved_init}"
      __export="${__saved_export}"
      __required_checks+=("[ \"\${${__required_marker}}\" ] || set \"missingopt\" \"${__label:-${var}}\"")
    fi
  else
    local __required_marker=""
    if dybatpho::is true "${__required}"; then
      __required_marker="__dybatpho_required_${__dybatpho_cli_logic_spec//[^a-zA-Z0-9_]/_}_${var}"
    fi
    __dybatpho_cli_print_indent 3 "${__switch})"
    [[ -n "${__deprecated}" ]] && __dybatpho_cli_print_deprecated_warning "option" "${__label:-${var}}" "${__deprecated}"
    if dybatpho::is false "${__optional}"; then
      __dybatpho_cli_print_indent 4 '[ $# -le 1 ] && set "needarg" "$1" && break'
      __dybatpho_cli_print_indent 4 'OPTARG=$2'
    else
      __dybatpho_cli_print_indent 4 'set -- "$1" "$@"'
      __dybatpho_cli_print_indent 4 '[ ${OPTARG+x} ] && {'
      __dybatpho_cli_print_indent 5 'case $1 in --no-*|--without-*) set "noarg" "${1%%\=*}"; break; esac'
      __dybatpho_cli_print_indent 5 '[ "${OPTARG:-}" ] && { shift; OPTARG=$2; } || {'
      __dybatpho_cli_print_indent 6 'case ${3:-} in'
      __dybatpho_cli_print_indent 7 '"") OPTARG='"${__on}"' ;;'
      __dybatpho_cli_print_indent 7 '-*) OPTARG='"${__on}"' ;;'
      __dybatpho_cli_print_indent 7 '*) shift; OPTARG=$2 ;;'
      __dybatpho_cli_print_indent 6 'esac'
      __dybatpho_cli_print_indent 5 '}'
      __dybatpho_cli_print_indent 4 "} || OPTARG=${__off}"
    fi
    __dybatpho_cli_print_validate "${var}" '$OPTARG'
    [[ -n "${__required_marker}" ]] && __dybatpho_cli_print_indent 4 "${__required_marker}=true"
    __dybatpho_cli_print_indent 4 "shift"
    __dybatpho_cli_print_indent 4 ";;"
  fi
}

#######################################
# @description Define an option that display only
# @arg $1 string Description of option to display
# @arg $@ switch|key:value Other switches and settings `key:value` of this option, including `alias:<switch>` /
#   `aliases:<a,b>`
# @tip Use a display option for help, schema, man-page, completion, or other actions that should exit after running.
# @tip Define a custom help display option only when the default `--help` / `-h` behavior is not sufficient.
# @note Use `persistent:true` to make the display option available to descendant subcommands
# @exitcode 0 exit code
#######################################
function dybatpho::opts::disp {
  local description
  dybatpho::expect_args description -- "$@"

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__meta_mode:-false}"; then
    __dybatpho_cli_parse_opt false 1 "$@"
    local -a __meta_switches=()
    __dybatpho_cli_collect_switches __meta_switches "${@:2}"
    local __meta_record
    __dybatpho_cli_meta_join __meta_record disp - "${description}" "${__meta_switches[*]}" \
      @none false @none @none "${__hidden:-false}" false "${__deprecated:-@none}" \
      "${__label:-@none}" @none false false @none
    __meta_options+=("${__meta_record}")
    return 0
  fi

  if dybatpho::is false "${__done_initial:-false}"; then
    local __help_arg
    for __help_arg in "${@:2}"; do
      case "${__help_arg}" in
        --help | -h | alias:--help | alias:-h | aliases:--help,* | aliases:*,-h)
          __has_help=true
          break
          ;;
        *) ;;
      esac
    done
  fi

  if dybatpho::is true "${__help_mode:-false}"; then
    local _line
    _line=$(__dybatpho_cli_help_row disp "-" "${description}" "${@:2}")
    [[ -n "${_line}" ]] && __help_opt_rows+=("${_line}")
    return 0
  fi

  __dybatpho_cli_parse_opt false 1 "$@"
  if ! dybatpho::is false "${__done_initial}"; then
    __dybatpho_cli_print_indent 3 "${__switch})"
    [[ -n "${__deprecated}" ]] && __dybatpho_cli_print_deprecated_warning "option" "${__label:-${description}}" \
      "${__deprecated}"
    [[ -n "${__action}" ]] && __dybatpho_cli_print_indent 4 "${__action}"
    __dybatpho_cli_print_indent 4 "exit 0"
    __dybatpho_cli_print_indent 4 ";;"
  elif dybatpho::is true "${__persistent}" && dybatpho::is false "${__persistent_replay:-false}"; then
    __dybatpho_cli_record_persistent_def disp "$@"
  fi
}

#######################################
# @description Place a line of free text in the generated help, so a long option
#              list can be broken into labelled groups. It declares no switch and
#              affects nothing but help output.
# @arg $@ string Message text, and optionally `hidden:<bool>`
# @example
#   dybatpho::opts::msg "Connection options:"
#   dybatpho::opts::param "Host to reach" HOST --host
#   dybatpho::opts::msg ""
#   dybatpho::opts::msg "Output options:"
#   dybatpho::opts::flag "Colorize output" COLOR --color
# @tip Pass an empty string for a blank separator line.
# @note Completion, schema, and man output ignore messages, because none of them
#       has a place for text that describes no option.
# @exitcode 0 exit code
#######################################
function dybatpho::opts::msg {
  local __msg_text="${1-}" __msg_hidden="false" __msg_item
  for __msg_item in "${@:2}"; do
    case "${__msg_item}" in
      hidden:*) __msg_hidden="${__msg_item#hidden:}" ;;
      *) ;;
    esac
  done

  # Help is the only walk that renders a message; every other mode collects
  # switches, variables, or commands, and a message declares none of them.
  dybatpho::is true "${__help_mode:-false}" || return 0
  dybatpho::is true "${__msg_hidden}" && return 0
  __help_opt_rows+=("${__DYBATPHO_CLI_MSG_LABEL}"$'\t'"${__msg_text}"$'\t')
  return 0
}

#######################################
# @description Define a sub-command in spec
# @arg $1 string Command name
# @arg $2 string Name of function that has spec of sub-command
# @arg $@ key:value Optional metadata such as `alias:<name>` or `aliases:<a,b>`
# @tip Declare each subcommand with its own spec function so help, completion, schema, and man output stay consistent.
# @tip Aliases are accepted during dispatch and are included in generated help and schema metadata.
#######################################
function dybatpho::opts::cmd {
  local __dybatpho_cli_cmd_sub_cmd __dybatpho_cli_cmd_sub_spec
  dybatpho::expect_args __dybatpho_cli_cmd_sub_cmd __dybatpho_cli_cmd_sub_spec -- "$@"
  shift 2

  local -a __cmd_aliases=()
  local __cmd_alias __cmd_hidden="false" __cmd_deprecated=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      alias:*) __cmd_aliases+=("${1#alias:}") ;;
      aliases:*) __dybatpho_cli_parse_alias_list __cmd_aliases "${1#aliases:}" ;;
      hidden:*) __cmd_hidden="${1#hidden:}" ;;
      deprecated:*) __cmd_deprecated="${1#deprecated:}" ;;
      *) ;;
    esac
    shift
  done

  if dybatpho::is true "${__meta_mode:-false}"; then
    local __meta_record
    __dybatpho_cli_meta_join __meta_record "${__dybatpho_cli_cmd_sub_cmd}" "${__dybatpho_cli_cmd_sub_spec}" \
      "${__cmd_aliases[*]:-@none}" \
      "${__cmd_hidden:-false}" "${__cmd_deprecated:-@none}"
    __meta_commands+=("${__meta_record}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  if dybatpho::is true "${__help_mode:-false}"; then
    local __cmd_desc="" __cmd_desc_mode=true
    "${__dybatpho_cli_cmd_sub_spec}"
    local __cmd_label="${__dybatpho_cli_cmd_sub_cmd}"
    for __cmd_alias in "${__cmd_aliases[@]}"; do
      __cmd_label="${__cmd_label}, ${__cmd_alias}"
    done
    local __dybatpho_cli_cmd__line
    __dybatpho_cli_cmd__line=$(__dybatpho_cli_help_row cmd "${__cmd_label}" "${__cmd_desc}" \
      "hidden:${__cmd_hidden}" "deprecated:${__cmd_deprecated}")
    [[ -n "${__dybatpho_cli_cmd__line}" ]] && __help_cmd_rows+=("${__dybatpho_cli_cmd__line}")
    return 0
  fi

  if dybatpho::is true "${__done_initial}"; then
    __has_sub_cmd="true"
    local __dybatpho_cli_cmd_spec="${__dybatpho_cli_cmd_sub_spec}" \
      __dybatpho_cli_cmd_name="${__dybatpho_cli_cmd_sub_cmd}"
    __sub_specs+=("${__dybatpho_cli_cmd_spec}"$'\t'"${__dybatpho_cli_cmd_name}"$'\t'"${__dybatpho_cli_cmd_name}"$'\t'"${__cmd_deprecated}")
    for __cmd_alias in "${__cmd_aliases[@]}"; do
      __sub_specs+=("${__dybatpho_cli_cmd_spec}"$'\t'"${__cmd_alias}"$'\t'"${__dybatpho_cli_cmd_name}"$'\t'"${__cmd_deprecated}")
    done
  fi
}

# shellcheck disable=2016
#######################################
# @description Declare a positional argument. Its value is assigned to the named
#              variable once parsing succeeds, and it also gives the usage line a
#              real placeholder and the generated help, schema, and man page an
#              `Arguments` section. Every value still lands in the rest array
#              named by `dybatpho::opts::setup` as well.
# @note Arguments bind in declaration order. A `variadic:true` argument is an
#       array holding every remaining value; the others are strings, and an
#       omitted optional argument is the empty string. Pass `-` as the variable
#       name to document an argument without binding it.
# @example
#   dybatpho::opts::arg "File to read" SOURCE
#   dybatpho::opts::arg "Where to write it" TARGET required:false
#   dybatpho::opts::arg "Extra files" EXTRA required:false variadic:true
#
# @arg $1 string Description of the argument
# @arg $2 string Placeholder name, shown uppercase in usage and help
# @arg $@ key:value Settings: `required:<bool>` (default `true`) and `variadic:<bool>` (default `false`)
# @note When `dybatpho::opts::setup` declares no `args:<rule>`, the rule is
#       derived from the declared arguments, so the count is validated without
#       stating it twice.
# @tip Declare arguments in the order they are typed; a variadic argument must come last.
# @exitcode 0 exit code
#######################################
function dybatpho::opts::arg {
  local description var
  dybatpho::expect_args description var -- "$@"
  __dybatpho_cli_require_shell_name "${var}"
  shift 2

  local __arg_required="true" __arg_variadic="false" __arg_item
  for __arg_item in "$@"; do
    case "${__arg_item}" in
      required:*) __arg_required="${__arg_item#required:}" ;;
      variadic:*) __arg_variadic="${__arg_item#variadic:}" ;;
      *) ;;
    esac
  done

  if dybatpho::is true "${__meta_mode:-false}"; then
    local __meta_record
    __dybatpho_cli_meta_join __meta_record "${var}" "${description}" "${__arg_required}" "${__arg_variadic}"
    __meta_args+=("${__meta_record}")
    return 0
  fi

  dybatpho::is true "${__cmd_desc_mode:-false}" && return 0

  local __arg_placeholder
  __arg_placeholder="$(__dybatpho_cli_arg_placeholder "${var}" "${__arg_required}" "${__arg_variadic}")"

  if dybatpho::is true "${__help_mode:-false}"; then
    __help_arg_rows+=("${__arg_placeholder}"$'\t'"${description}"$'\t')
    __help_arg_usage="${__help_arg_usage:+${__help_arg_usage} }${__arg_placeholder}"
    return 0
  fi

  # Only the first spec walk feeds the derived `args:` rule and the binding
  # order; the code-generating walk would otherwise count every argument twice.
  if dybatpho::is false "${__done_initial:-false}"; then
    __declared_args+=("${__arg_required}"$'\t'"${__arg_variadic}"$'\t'"${var}")
  fi
  return 0
}

#######################################
# @description Render a positional argument the way usage lines conventionally
#              do: angle brackets when it is required, square brackets when it
#              is optional, and a trailing ellipsis when it is variadic.
# @arg $1 string Placeholder name
# @arg $2 bool Whether the argument is required
# @arg $3 bool Whether the argument is variadic
# @stdout Rendered placeholder
# @internal
#######################################
function __dybatpho_cli_arg_placeholder {
  local name="${1^^}" required="${2:-true}" variadic="${3:-false}" rendered
  if dybatpho::is true "${required}"; then
    rendered="<${name}>"
  else
    rendered="[${name}]"
  fi
  dybatpho::is true "${variadic}" && rendered="${rendered}..."
  printf '%s' "${rendered}"
}

#######################################
# @description Derive the `args:<rule>` a command would need to accept exactly
#              the positional arguments it declared with `dybatpho::opts::arg`.
# @arg $1 string Name of the variable receiving the rule
# @arg $@ string Declared argument records of `required<TAB>variadic`
# @exitcode 0 The variable is left untouched when nothing was declared
# @internal
#######################################
function __dybatpho_cli_derive_args_rule {
  __dybatpho_cli_require_shell_name "$1"
  local __target="$1"
  shift
  (($#)) || return 0
  local __entry __entry_required __entry_variadic __entry_var __variadic=false
  local -i __required=0 __optional=0
  for __entry in "$@"; do
    IFS=$'\t' read -r __entry_required __entry_variadic __entry_var <<< "${__entry}"
    dybatpho::is true "${__entry_variadic}" && __variadic=true
    if dybatpho::is true "${__entry_required}"; then
      __required+=1
    else
      __optional+=1
    fi
  done
  if dybatpho::is true "${__variadic}"; then
    printf -v "${__target}" '%s' "min:${__required}"
  elif ((__optional > 0)); then
    printf -v "${__target}" '%s' "range:${__required}:$((__required + __optional))"
  else
    printf -v "${__target}" '%s' "exact:${__required}"
  fi
  return 0
}

# @section Parse functions
# @description Functions to parse spec and put value of options to variable with corresponding name
# @tip Generate the parser once at the end of the script after defining the complete spec tree.
# @tip The generated parser preserves the original command-line arguments while dispatching nested subcommands.

#######################################
# @description Create the file a generated parser is written to.
#   `dybatpho::create_temp` refuses a library-prefixed name, and the variable
#   in `dybatpho::generate_from_spec` has to carry one, so the file is made
#   here under a plain name, in a scope the parser never runs in.
# @arg $1 string Name of the variable receiving the path
# @set The named variable
# @internal
#######################################
function __dybatpho_cli_generated_file_into {
  local -n __dybatpho_cli_generated_ref="$1"
  local gen_file
  dybatpho::create_temp gen_file ".sh" "genopts"
  __dybatpho_cli_generated_ref="${gen_file}"
}

#######################################
# @description Define spec of parent function or script, spec contains below commands
# @arg $1 string Name of function that has spec of parent function or script
# @exitcode 0 exit code
#######################################
function dybatpho::generate_from_spec {
  # The generated parser runs inside this function and assigns the variables
  # the spec names, so these locals carry the module prefix: an option or
  # positional variable called `spec` would otherwise be set here and lost.
  local __dybatpho_cli_spec
  dybatpho::expect_args __dybatpho_cli_spec -- "$@"
  shift

  __current_cmd_path=""
  local __dybatpho_cli_gen_file
  __dybatpho_cli_generated_file_into __dybatpho_cli_gen_file
  __dybatpho_cli_generate_logic "${__dybatpho_cli_spec}" "$@" >> "${__dybatpho_cli_gen_file}"
  if dybatpho::is true "${DYBATPHO_CLI_DEBUG}"; then
    dybatpho::debug_command "Generate script of \"${__dybatpho_cli_spec}\" - \"$*\"" \
      "dybatpho::show_file '${__dybatpho_cli_gen_file}'"
  fi
  # shellcheck disable=1090
  . "${__dybatpho_cli_gen_file}"
  # Sourced, the file has done its job. It goes now rather than on the EXIT
  # trap, which an action ending in `exec` never reaches: such a script used to
  # leave one file behind per run.
  rm -f -- "${__dybatpho_cli_gen_file}"
  # The generated file only defines parsers. Running one is done here, with the
  # argument vector this function was given, so nothing a caller typed is ever
  # read as shell source.
  "dybatpho::opts::parse::${__dybatpho_cli_spec}" "$@"
}

#######################################
# @description Show help description of root command/sub-command.
#              Declares help state as locals so dybatpho::opts::* in the call
#              chain can read/write them via bash dynamic scoping.
# @arg $1 string Name of function that has spec of parent function or script
# @stdout Help description
# @tip The current subcommand path is tracked automatically during parser dispatch
# @tip A command receives automatic `--help` and `-h` unless the spec declares its own help display option.
#######################################
function dybatpho::generate_help {
  local __dybatpho_cli_gh_spec
  dybatpho::expect_args __dybatpho_cli_gh_spec -- "$@"

  # Help generation state — local here, visible to the whole call chain via
  # bash dynamic scoping (dybatpho::opts::* write, __dybatpho_cli_generate_help reads)
  local __help_mode=false
  local __cmd_desc_mode=false
  local __help_leading="  "
  local __help_subcmd="${__current_cmd_path:-}"
  local __help_description=""
  local __help_args_rule="any"
  local __help_arg_usage=""
  local __has_help=false
  local -a __help_opt_rows=()
  local -a __help_cmd_rows=()
  local -a __help_arg_rows=()

  __dybatpho_cli_generate_help "${__dybatpho_cli_gh_spec}"
}
