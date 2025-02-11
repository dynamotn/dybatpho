# process.sh

Utilities for process handling

## Overview

This module contains functions to error handling, fork process...

## Index

* [dybatpho::die](#dybatphodie)
* [dybatpho::register_err_handler](#dybatphoregistererrhandler)
* [dybatpho::run_err_handler](#dybatphorunerrhandler)

### dybatpho::die

Stop script/process.

#### Arguments

* **$1** (string): Message
* **$2** (number): Exit code, default is 1

#### Exit codes

* $**2**: Stop to process anything else

### dybatpho::register_err_handler

Register error handling.

_Function has no arguments._

### dybatpho::run_err_handler

Run error handling.

#### Arguments

* **$1** (number): Exit code

