# helpers.sh

Utilities for writing efficient script

## Overview

This module contains functions to write efficient script.

## Index

* [dybatpho::expect_args](#dybatphoexpectargs)
* [dybatpho::require](#dybatphorequire)
* [dybatpho::is](#dybatphois)

### dybatpho::expect_args

Validate argument when invoke function. It adds a small performance penalty but is a sane option.

#### Example

```bash
  local arg1 arg2 .. argN
  dybatpho::expect_args arg1 arg2 .. argN -- "$@"
@exitcode 1 Stop script if not correct spec: enough variable names to get, `--`, and list of arguments to pass `$@`
            or not have enough arguments that follow by spec
@exitcode 0 Otherwise run seamlessly, pass value of argument to variable name
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

