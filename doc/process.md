# process.sh

Utilities for process handling

## Overview

This module contains functions to error handling, fork process...

## Index

* [dybatpho::die](#dybatphodie)

### dybatpho::die

Stop script/process.

#### Arguments

* **$1** (string): Message
* **$2** (number): Exit code, default is 1

#### Variables set

* **SELF_PID** (number): Top level PID

#### Exit codes

* $**2**: Stop to process anything else

