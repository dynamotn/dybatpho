# helpers.sh

Utilities for writing efficient script

## Overview

This module contains functions to write efficient script.

## Index

* [dybatpho::require](#dybatphorequire)
* [dybatpho::is](#dybatphois)

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

