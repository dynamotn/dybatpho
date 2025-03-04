# process.sh

Utilities for process handling

## Overview

This module contains functions to error handling, fork process...

DYBATPHO_USED_ERR_HANDLER bool Flag that script used dybatpho::register_err_handler

## Index

* [dybatpho::die](#dybatphodie)
* [dybatpho::register_err_handler](#dybatphoregistererrhandler)
* [dybatpho::run_err_handler](#dybatphorunerrhandler)
* [dybatpho::trap](#dybatphotrap)
* [dybatpho::cleanup_file_on_exit](#dybatphocleanupfileonexit)

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

#### Variables set

* DYBATPHO_USED_ERR_HANDLING

### dybatpho::run_err_handler

Run error handling. If you activate by `dybatpho::register_err_handler`, you don't need to invoke this function.

#### Arguments

* **$1** (number): Exit code

### dybatpho::trap

Trap multiple signals

#### Arguments

* **$1** (string): Command run when trapped
* **$2** (string_list): Signals to trap

### dybatpho::cleanup_file_on_exit

Clean up file on exit

#### Arguments

* **$1** (string): File path

