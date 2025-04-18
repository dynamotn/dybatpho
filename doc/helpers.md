# helpers.sh

Utilities for writing efficient script

## Overview

This module contains functions to write efficient script.

**DYBATPHO_REPL_HISTORY_FILE** (string): Path of REPL history file for dybatpho, used in `dybatpho::breakpoint`

## Index

* [dybatpho::expect_args](#dybatphoexpectargs)
* [dybatpho::still_has_args](#dybatphostillhasargs)
* [dybatpho::require](#dybatphorequire)
* [dybatpho::is](#dybatphois)
* [dybatpho::retry](#dybatphoretry)
* [dybatpho::breakpoint](#dybatphobreakpoint)

### dybatpho::expect_args

Validate argument when invoke function. It adds a small performance penalty but is a sane option.

#### Example

```bash
local arg1 arg2 .. argN
dybatpho::expect_args arg1 arg2 .. argN -- "$@"
```

#### Exit codes

* **1**: Stop script if not correct spec: enough variable names to get, `--`, and list of arguments to pass `$@`
* **0**: Otherwise run seamlessly, pass value of argument to variable name

### dybatpho::still_has_args

Check that function still has next argument after shift.
This function is useful to check argument of function that you don't now
count of arguments when triggered, and you just only need to process next
argument

#### Example

```bash
  while dybatpho::still_has_args "$@" && shift; do
    echo "Function has next argument is $1"
  done
@exitcode 0 Still has an argument
@exitcode 1 Not has any arguments
```

### dybatpho::require

Check command dependency is installed.

#### Arguments

* **$1** (string): Command need to be installed

#### Exit codes

* **127**: Stop script if command isn't installed
* **0**: Otherwise run seamlessly

### dybatpho::is

Check input is matching with a condition

#### Arguments

* **$1** (string): Condition (command|file|dir|link|exist|readable|writing|executable|set|empty|number|int|true|false)
* **$2** (string): Input need to check

#### Exit codes

* **0**: If matched
* **1**: If not matched

### dybatpho::retry

Retry a command multiple times until it succeeds,
with escalating delay between attempts.

#### Arguments

* **$1** (number): Number of retries
* **$2** (string): Command to run
* **$3** (string): Description of command

#### Exit codes

* **0**: Run command successfully
* **1**: Out of retries

### dybatpho::breakpoint

Hit breakpoint to debug script.

_Function has no arguments._

