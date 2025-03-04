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
* [dybatpho::gen_temp_file](#dybatphogentempfile)
* [dybatpho::gen_temp_dir](#dybatphogentempdir)

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

### dybatpho::gen_temp_file

Generate temporary file

#### Arguments

* **$1** (string): Name of file in TMPDIR
* **$2** (string): TMPDIR, default is /tmp
* **$3** (bool): Flag to delete temporary file when exit, default is true

### dybatpho::gen_temp_dir

Generate temporary directory

#### Arguments

* **$1** (string): Name of directory in /tmp
* **$2** (bool): Flag to delete temporary directory when exit. Default is true

