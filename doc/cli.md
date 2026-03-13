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

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CLI_DEBUG`** | bool | Set to `true` to dump generated parser details while developing specs |

### 🚀 Highlights

- [`__parse_opt`](#__parse_opt) — Functions are triggered by `dybatpho::generate_from_spec` Parse options with a spec from `dybatpho::opts::flag`, `dybatpho::opts::param`
- [`__print_indent`](#__print_indent) — Write script with indentation to stdout
- [`__require_shell_name`](#__require_shell_name) — Validate a shell variable name used by generated parser code.
- [`__assign_quoted`](#__assign_quoted) — Assign the quoted string to a variable
- [`__prepend_export`](#__prepend_export) — Prepend export of before string of command, based on `export:<bool>` switch
- [`__define_var`](#__define_var) — Define variable from spec from `dybatpho::opts::flag`, `dybatpho::opts::param`
- [`__parse_key_value`](#__parse_key_value) — Extract key value from spec with format `x:y`, to get settings of option
- [`__generate_logic`](#__generate_logic) — Generate logic from spec of script/function to get options
- [`__print_get_arg`](#__print_get_arg) — Emit generated code that rebuilds positional parameters from a serialized argument list.
- [`__print_rest`](#__print_rest) — Emit generated code that appends the remaining positional arguments to the configured rest variable and stops option parsing.
- [`__generate_help`](#__generate_help) — Get help description for options from spec. Sets __help_mode=true so dybatpho::opts::* collect help data via dynamic scoping into dybatpho::generate_help's locals, then prints the buffered sections in the correct order.
- [`__help_pad`](#__help_pad) — Pad string $2 to at least length $3 and store result in variable $1
- [`__help_sw`](#__help_sw) — Append a formatted switch to caller-local variable `sw`. Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so that short+long pairs align as "-s, --long".
- [`__help_row`](#__help_row) — Format one help row and print to stdout
- [`__add_switch`](#__add_switch) — Add to switches list if flag/param has multiple switches
- [`__print_validate`](#__print_validate) — Emit generated code that validates the current `OPTARG` and assigns it to the destination variable.
- [`__parse_alias_list`](#__parse_alias_list) — Split a comma-separated alias list into a caller-provided array.
- [`__record_persistent_def`](#__record_persistent_def) — Serialize an option definition so it can be replayed for persistent descendant commands.
- [`__replay_persistent_defs`](#__replay_persistent_defs) — Replay inherited persistent option definitions inside the current parser/help generation context.
- [`__print_persistent_help_defs`](#__print_persistent_help_defs) — Emit generated code that seeds persistent option definitions for nested help output.
- [`__print_deprecated_warning`](#__print_deprecated_warning) — Emit generated code that warns when a deprecated CLI item is used.
- [`__generate_child_logic`](#__generate_child_logic) — Generate parser logic for a child command with inherited persistent option definitions.
- [`__print_args_check`](#__print_args_check) — Emit generated code that validates the positional argument count configured by `args:<rule>` in `dybatpho::opts::setup`.
- [`dybatpho::opts::setup`](#dybatphooptssetup) — Functions work in spec of script or function via `dybatpho::generate_from_spec`. Setup global settings for getting options (mandatory) in spec of script or function
- [`dybatpho::opts::flag`](#dybatphooptsflag) — Define an option that take no argument
- [`dybatpho::opts::param`](#dybatphooptsparam) — Define an option that take an argument
- [`dybatpho::opts::disp`](#dybatphooptsdisp) — Define an option that display only
- [`dybatpho::opts::cmd`](#dybatphooptscmd) — Define a sub-command in spec
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
| `alias:<name>` | `flag`, `param`, `disp`, `cmd` | Add one alias switch or command name |
| `aliases:<a,b>` | `flag`, `param`, `disp`, `cmd` | Add multiple aliases separated by commas |
| `init:<value>` | `flag`, `param` | Initial variable value |
| `on:<string>` | `flag`, `param` | Positive value when the option is enabled |
| `off:<string>` | `flag`, `param` | Negative value when the option is disabled or absent |
| `persistent:<bool>` | `flag`, `param`, `disp` | Make the option available in descendant subcommands |
| `export:<bool>` | `flag`, `param` | Export the variable |
| `optional:<bool>` | `param` | Whether the option value is optional when the switch appears |
| `required:<bool>` | `param` | Whether the option itself must appear |
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


### Help generation


`dybatpho::generate_help` automatically handles:


- usage line
- description from `dybatpho::opts::setup`
- option rows
- command rows
- current subcommand path
- automatic `(required)` suffix for `required:true` params


By default:


- `flag` rows show switches only
- `param` rows show switches plus `<VARNAME>`
- `disp` rows show switches only
- `cmd` rows show the command name


You can override the rendered label with `label:<string>`.


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



<a id="see-also"></a>
## 🔗 See also

- [example/cli_basic.sh](../example/cli_basic.sh)
- [example/cli_advanced.sh](../example/cli_advanced.sh)

<a id="tips"></a>
## 💡 Tips

- Set `DYBATPHO_CLI_DEBUG=true` while developing a spec to inspect the generated parser and help logic.

### `dybatpho::opts::param`

- Use `required:true` when the option itself must be present
- Use `optional:true` when the option may appear without an explicit value
- `optional:true` controls whether a value is required after the switch appears, while `required:true` controls whether the switch itself must appear at all
- Keep conditional requirements such as "required unless `--list` is set" in your action or validation logic

### `dybatpho::generate_help`

- The current subcommand path is tracked automatically during parser dispatch

<a id="reference"></a>
## 📚 Reference

<a id="internal-functions"></a>
### 🧩 Internal functions

#### `__parse_opt`

Functions are triggered by `dybatpho::generate_from_spec`
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

### `__print_indent`

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

### `__require_shell_name`

Validate a shell variable name used by generated parser code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name, or `-` to intentionally skip assignment |

**🚦 Exit codes**

- `0`: The name is valid, or the sentinel `-` was used


---

### `__assign_quoted`

Assign the quoted string to a variable

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name to be assigned |
| `$2` | string | Input string to be quoted |

**🚦 Exit codes**

- 0


---

### `__prepend_export`

Prepend export of before string of command,
             based on `export:<bool>` switch

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | String of command |


---

### `__define_var`

Define variable from spec from `dybatpho::opts::flag`,
             `dybatpho::opts::param`

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of variable to be defined |


---

### `__parse_key_value`

Extract key value from spec with format `x:y`,
             to get settings of option

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | key:value | Key-value string to extract |
| `$2` | string | Prefix of key to assign as variable |


---

### `__generate_logic`

Generate logic from spec of script/function to get options

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of function that has spec of parent function or script |
| `$2` | string | Command of spec (`-` for root command trigger from CLI, otherwise is sub-command) |

**📤 Output on stdout**

- Generated logic


---

### `__print_get_arg`

Emit generated code that rebuilds positional parameters from a serialized argument list.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Shell expression that expands to serialized arguments |

**📤 Output on stdout**

- Generated parser code


---

### `__print_rest`

Emit generated code that appends the remaining positional arguments to the configured rest variable and stops option parsing.

_Function has no arguments._

**📤 Output on stdout**

- Generated parser code


---

### `__generate_help`

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

### `__help_pad`

Pad string $2 to at least length $3 and store result in variable $1

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name to store result |
| `$2` | string | String to pad |
| `$3` | number | Minimum length |


---

### `__help_sw`

Append a formatted switch to caller-local variable `sw`.
Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so
that short+long pairs align as "-s, --long".

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Minimum pad width before appending $2 |
| `$2` | string | Switch string to append |


---

### `__help_row`

Format one help row and print to stdout

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Type: flag \| param \| disp \| cmd |
| `$2` | string | Variable name (or command name for cmd type) |
| `$3` | string | Description |
| `$@` | switch\|key:value | Switches and settings of this option |

**📤 Output on stdout**

- Formatted help row


---

### `__add_switch`

Add to switches list if flag/param has multiple switches

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | switch | Switch |


---

### `__print_validate`

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

### `__parse_alias_list`

Split a comma-separated alias list into a caller-provided array.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Name of destination array variable |
| `$2` | string | Comma-separated aliases |

**🚦 Exit codes**

- `0`: Aliases appended to destination array


---

### `__record_persistent_def`

Serialize an option definition so it can be replayed for persistent descendant commands.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option type (`flag`, `param`, or `disp`) |
| `$@` | string | Original arguments passed to the option helper |

**🚦 Exit codes**

- `0`: Definition stored for later replay


---

### `__replay_persistent_defs`

Replay inherited persistent option definitions inside the current parser/help generation context.

_Function has no arguments._

**🚦 Exit codes**

- `0`: All inherited persistent definitions were replayed


---

### `__print_persistent_help_defs`

Emit generated code that seeds persistent option definitions for nested help output.

_Function has no arguments._

**📤 Output on stdout**

- Generated parser code


---

### `__print_deprecated_warning`

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

### `__generate_child_logic`

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

### `__print_args_check`

Emit generated code that validates the positional argument count configured by `args:<rule>` in `dybatpho::opts::setup`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Argument count rule (`none`, `exact:N`, `min:N`, `max:N`, `range:M:N`, `any`) |

**📤 Output on stdout**

- Generated parser code

**🚦 Exit codes**

- `0`: Rule accepted and code emitted


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
| `$@` | key:value | Settings `key:value` for sub-command/root command such as `action:<code>`, `prerun:<code>`, `postrun:<code>`, and `args:<rule>` |

**📝 Notes**

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

### `dybatpho::opts::cmd`

Define a sub-command in spec

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command name |
| `$2` | string | Name of function that has spec of sub-command |
| `$@` | key:value | Optional metadata such as `alias:<name>` or `aliases:<a,b>` |


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

