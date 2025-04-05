# opts.sh

Utilities for getting options when calling command in script or from CLI

## Overview

This module contains functions to define, get options (flags, parameters...) for command or subcommand
when calling it from CLI or in shell script.

## Index

* [__parse_opt](#parseopt)
* [__print_indent](#printindent)
* [__assign_quoted](#assignquoted)
* [__prepend_export](#prependexport)
* [__define_var](#definevar)
* [__parse_key_value](#parsekeyvalue)
* [__generate_logic](#generatelogic)
* [dybatpho::opts::setup](#dybatphooptssetup)
* [dybatpho::opts::flag](#dybatphooptsflag)
* [dybatpho::opts::param](#dybatphooptsparam)
* [dybatpho::opts::disp](#dybatphooptsdisp)
* [dybatpho::opts::cmd](#dybatphooptscmd)
* [dybatpho::generate_from_spec](#dybatphogeneratefromspec)
* [_help_opt](#helpopt)
* [dybatpho::generate_help](#dybatphogeneratehelp)

## Functions are triggered by `dybatpho::generate_from_spec`

This module contains functions to define, get options (flags, parameters...) for command or subcommand
when calling it from CLI or in shell script.

### __parse_opt

Parse options with a spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

#### Arguments

* **$1** (bool): Flag that defined option that take argument in spec
* **...** (string): Passed arguments from `dybatpho::opts::(flag|param)`

#### Exit codes

* 0

### __print_indent

Write script with indentation to stdout, trigger by `__generate_logic`

#### Arguments

* **$1** (Number): of indentation level
* **...** (Line): of code to generate

#### Exit codes

* 0

### __assign_quoted

Assign the quoted string to a variable

#### Arguments

* **$1** (Variable): name to be assigned
* **$2** (Input): string to be quoted

#### Exit codes

* 0

### __prepend_export

Prepend export of before string of command, based on <export:bool> switch

#### Arguments

* **$1** (string): String of command

### __define_var

Define variable from spec from `dybatpho::opts::flag`,
`dybatpho::opts::param`

#### Arguments

* **$1** (string): Name of variable to be defined

### __parse_key_value

Extract key value from spec with format `x:y`, to get settings of option

#### Arguments

* **$1** (key:value): Key-value string to extract
* **$2** (string): Prefix of key to assign as variable

### __generate_logic

Generate logic from spec of script/function

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script

#### Output on stdout

* Generated logic

## Functions work in spec of script or function via `dybatpho::generate_from_spec`.

Setup global settings for getting options (mandatory) in spec
of script or function

### dybatpho::opts::setup

Setup global settings for getting options (mandatory) in spec
of script or function

#### Arguments

* **$1** (string): Description of sub-command/root command
* **$2** (string): Variable name for getting rest arguments after parse options.
* **$3** (string): Sub-command string to invoke, `-` if want to invoke from root
* **$4** (action:statement): Name of function to call after parse options
* **...** (key:value): Settings `key:value` for sub-command/root command

#### Exit codes

* **0**: exit code

### dybatpho::opts::flag

Define an option that take no argument

#### Arguments

* **$1** (string): Description of option to display
* **$2** (string): Variable name for getting option. `-` if want to omit
* **...** (switch_or_key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::param

Define an option that take an argument

#### Arguments

* **$1** (string): Description of option to display
* **$2** (string): Variable name for getting option. `-` if want to omit
* **...** (switch_or_key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::disp

Define an option that display only

#### Arguments

* **$1** (string): Description of option to display
* **$2** (string): Action to render
* **...** (switch_or_key:value): Other switches and settings `key:value` of this option

#### Exit codes

* **0**: exit code

### dybatpho::opts::cmd

Define a sub-command in spec

#### Arguments

* **$1** (string): Description of sub-command to display
* **$2** (string): Sub-command string
* **$3** (switch): Name of function will be executed, # @exitcode 0 exit code

## Functions to parse spec and put value of options to variable with

Define spec of parent function or script, spec contains below commands

### dybatpho::generate_from_spec

Define spec of parent function or script, spec contains below commands

#### Arguments

* **$1** (string): Name of function that has spec of parent function or script
* **$2** (string): Name of function will be executed after parse, default is empty

#### Exit codes

* **0**: exit code

### _help_opt

Get help description for option with a spec from
`dybatpho::opts::flag`, `dybatpho::opts::param`

#### Arguments

* **$1** (bool): Flag that defined option that take argument in spec
* **...** (string): Arguments pass from `dybatpho::opts::(flag|param)`

#### Exit codes

* **0**: exit code

### dybatpho::generate_help

Show help description of root command/sub-command

#### Output on stdout

* Help description

