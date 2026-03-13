# cli.sh

Utilities for getting options when calling command from CLI or in script with CLI-like format

## Overview

This module contains functions to define, get options (flags, parameters...) for command or subcommand
when calling it from CLI or in shell script.

Theses are type of function arguments that defined in this file

|Type|Description|
|----|-----------|
|`switch`|A type as a string with format `-?`, `--*`, `--no-*`, `--with-*`, `--without-*`, `--{no-}*` (expand to use both `--flag` and `--no-flag`), `--with{out}-*` (expand to `--with-flag` and `--without-flag`)|
|`key:value`|`key1:value1` style arguments, if `:value` is omitted, it is the same as `key:key`|

### Key-value type
|Format|Description|
|------|-----------|
|`action:<code>`|List of multiple statements, split by `;` as `key:value`, eg `"action:foo; bar"`|
|`init:<method>`|Method to initial value of variable from spec by variable name with key `init:`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`, see `Initial variable kind` below|
|`on:<string>`|The positive value whether option is switch as `--flag`, `--with-flag`, default is `"true"`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`off:<string>`|The negative value whether option is not presence, or as `--no-flag`, `--without-flag`, default is empty `''`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`export:<bool>`|Export variable in spec command or not, default is true, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`optional:<bool>`|Used for `dybatpho::opts::param` whether option value is optional when the switch appears, default is false|
|`required:<bool>`|Used for `dybatpho::opts::param` whether the option itself must appear, default is false|
|`validate:<code>`|Validate statements for options, eg: `"_function1 \$OPTARG"` (must have `\$OPTARG` to pass param value of option), used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`error:<code>`|Custom error messages function for options, eg: `"_show_error1"`,  used for `dybatpho::opts::flag` and `dybatpho::opts::param`|

### Initial variable kind
|Format|Description|
|------|-----------|
|`init:@empty`|Initial value as empty. It's default behavior|
|`init:@on`|Initial value with same as `on` key|
|`init:@off`|Initial value with same as `off` key|
|`init:@unset`|Unset the variable|
|`init:@keep`|Do not initialization (Use the current value as it is)|
|`init:action:<code>`|Initialize by run statement(s) and not assigned to variable|
|`init:=<code>`| Initialize by plain code and assigned to variable|

## Index

* [__parse_opt](#parseopt)
* [__print_indent](#printindent)
* [__assign_quoted](#assignquoted)
* [__prepend_export](#prependexport)
* [__define_var](#definevar)
* [__parse_key_value](#parsekeyvalue)
* [__generate_logic](#generatelogic)
* [__generate_help](#generatehelp)
* [__help_pad](#helppad)
* [__help_sw](#helpsw)
* [__help_row](#helprow)
* [__add_switch](#addswitch)
* [dybatpho::opts::setup](#dybatphooptssetup)
* [dybatpho::opts::flag](#dybatphooptsflag)
* [dybatpho::opts::param](#dybatphooptsparam)
* [dybatpho::opts::disp](#dybatphooptsdisp)
* [dybatpho::opts::cmd](#dybatphooptscmd)
* [dybatpho::generate_from_spec](#dybatphogeneratefromspec)
* [dybatpho::generate_help](#dybatphogeneratehelp)

## Internal functions

This module contains functions to define, get options (flags, parameters...) for command or subcommand
when calling it from CLI or in shell script.

Theses are type of function arguments that defined in this file

|Type|Description|
|----|-----------|
|`switch`|A type as a string with format `-?`, `--*`, `--no-*`, `--with-*`, `--without-*`, `--{no-}*` (expand to use both `--flag` and `--no-flag`), `--with{out}-*` (expand to `--with-flag` and `--without-flag`)|
|`key:value`|`key1:value1` style arguments, if `:value` is omitted, it is the same as `key:key`|

### Key-value type
|Format|Description|
|------|-----------|
|`action:<code>`|List of multiple statements, split by `;` as `key:value`, eg `"action:foo; bar"`|
|`init:<method>`|Method to initial value of variable from spec by variable name with key `init:`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`, see `Initial variable kind` below|
|`on:<string>`|The positive value whether option is switch as `--flag`, `--with-flag`, default is `"true"`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`off:<string>`|The negative value whether option is not presence, or as `--no-flag`, `--without-flag`, default is empty `''`, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`export:<bool>`|Export variable in spec command or not, default is true, used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`optional:<bool>`|Used for `dybatpho::opts::param` whether option value is optional when the switch appears, default is false|
|`required:<bool>`|Used for `dybatpho::opts::param` whether the option itself must appear, default is false|
|`validate:<code>`|Validate statements for options, eg: `"_function1 \$OPTARG"` (must have `\$OPTARG` to pass param value of option), used for `dybatpho::opts::flag` and `dybatpho::opts::param`|
|`error:<code>`|Custom error messages function for options, eg: `"_show_error1"`,  used for `dybatpho::opts::flag` and `dybatpho::opts::param`|

### Initial variable kind
|Format|Description|
|------|-----------|
|`init:@empty`|Initial value as empty. It's default behavior|
|`init:@on`|Initial value with same as `on` key|
|`init:@off`|Initial value with same as `off` key|
|`init:@unset`|Unset the variable|
|`init:@keep`|Do not initialization (Use the current value as it is)|
|`init:action:<code>`|Initialize by run statement(s) and not assigned to variable|
|`init:=<code>`| Initialize by plain code and assigned to variable|

### __parse_opt

Parse options with a spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

#### Arguments

* **$1** (bool): Flag that defined option that take argument in spec
* **$2** (number): Count of non-option metadata args to skip after the mode flags
* **...** (string): Passed arguments from `dybatpho::opts::(flag|param|disp)`

#### Exit codes

* 0

### __print_indent

Write script with indentation to stdout

#### Arguments

* **$1** (number): Number of indentation level
* **...** (string): Line of code to generate

#### Exit codes

* 0

#### Output on stdout

* Generated code

### __assign_quoted

Assign the quoted string to a variable

#### Arguments

* **$1** (string): Variable name to be assigned
* **$2** (string): Input string to be quoted

#### Exit codes

* 0

### __prepend_export

Prepend export of before string of command,
based on `export:<bool>` switch

#### Arguments

* **$1** (string): String of command

### __define_var

Define variable from spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

#### Arguments

* **$1** (string): Name of variable to be defined

### __parse_key_value

Extract key value from spec with format `x:y`,
to get settings of option

#### Arguments

* **$1** (key:value): Key-value string to extract
* **$2** (string): Prefix of key to assign as variable

### __generate_logic

Generate logic from spec of script/function to get options

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script
* **$2** (string): Command of spec (`-` for root command trigger from CLI, otherwise is sub-command)

#### Output on stdout

* Generated logic

### __generate_help

Get help description for options from spec.
Sets __help_mode=true so dybatpho::opts::* collect help data
via dynamic scoping into dybatpho::generate_help's locals,
then prints the buffered sections in the correct order.

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script

#### Exit codes

* **0**: exit code

#### Output on stdout

* Help description

### __help_pad

Pad string $2 to at least length $3 and store result in variable $1

#### Arguments

* **$1** (string): Variable name to store result
* **$2** (string): String to pad
* **$3** (number): Minimum length

### __help_sw

Append a formatted switch to caller-local variable `sw`.
Short flags (-?) use pad width 0; long flags (--*) use pad width 4 so
that short+long pairs align as "-s, --long".

#### Arguments

* **$1** (number): Minimum pad width before appending $2
* **$2** (string): Switch string to append

### __help_row

Format one help row and print to stdout

#### Arguments

* **$1** (string): Type: flag | param | disp | cmd
* **$2** (string): Variable name (or command name for cmd type)
* **$3** (string): Description
* **...** (switch|key:value): Switches and settings of this option

#### Output on stdout

* Formatted help row

### __add_switch

Add to switches list if flag/param has multiple switches

#### Arguments

* **$1** (switch): Switch

## Spec functions

Functions work in spec of script or function via `dybatpho::generate_from_spec`.

### dybatpho::opts::setup

Setup global settings for getting options (mandatory) in spec
of script or function

#### Arguments

* **$1** (string): Description of sub-command/root command
* **...** (key:value): Settings `key:value` for sub-command/root command

#### Exit codes

* **0**: exit code

### dybatpho::opts::flag

Define an option that take no argument

#### Arguments

* **$1** (string): Description of option to display
* **$2** (string): Variable name for getting option. `-` if want to omit
* **...** (switch|key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::param

Define an option that take an argument

#### Arguments

* **$1** (string): Description of option to display
* **$2** (string): Variable name for getting option. `-` if want to omit
* **...** (switch|key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::disp

Define an option that display only

#### Arguments

* **$1** (string): Description of option to display
* **...** (switch|key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::cmd

Define a sub-command in spec

#### Arguments

* **$1** (string): Name of function that has spec of sub-command

## Parse functions

Functions to parse spec and put value of options to variable with corresponding name

### dybatpho::generate_from_spec

Define spec of parent function or script, spec contains below commands

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script

#### Exit codes

* **0**: exit code

### dybatpho::generate_help

Show help description of root command/sub-command.
Declares help state as locals so dybatpho::opts::* in the call
chain can read/write them via bash dynamic scoping.

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script

#### Output on stdout

* Help description

