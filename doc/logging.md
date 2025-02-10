# logging.sh

Utilities for logging to stdout/stderr

## Overview

This module contains functions to log messages to stdout/stderr.

## Index

* [__verify_log_level](#verifyloglevel)
* [__log](#log)
* [dybatpho::debug](#dybatphodebug)
* [dybatpho::info](#dybatphoinfo)
* [dybatpho::progress](#dybatphoprogress)
* [dybatpho::notice](#dybatphonotice)
* [dybatpho::success](#dybatphosuccess)
* [dybatpho::warning](#dybatphowarning)
* [dybatpho::error](#dybatphoerror)
* [dybatpho::fatal](#dybatphofatal)
* [dybatpho::start_trace](#dybatphostarttrace)
* [dybatpho::end_trace](#dybatphoendtrace)

### __verify_log_level

Verify log level from input.

#### Arguments

* **$1** (string): String of log level

#### Exit codes

* **0**: If is valid log level
* **1**: If invalid

### __log

Log a message to stdout/stderr with color and caution.

#### Arguments

* **$1** (string): Log level of message
* **$2** (string): Message
* **$3** (string): `stderr` to output to stderr, otherwise then to stdout
* **$4** (string): ANSI escape color code
* **$5** (string): Command to run after log

#### Variables set

* **LOG_LEVEL** (string): Log level of script

#### Output on stdout

* Show message if log level of message is less than runtime log level and $3 is not `stderr`

#### Output on stderr

* Show message if log level of message is less than runtime log level and $3 is `stderr`

### dybatpho::debug

Show debug message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than debug level

### dybatpho::info

Show info message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than info level

### dybatpho::progress

Show in progress message.

#### Arguments

* **$1** (string): Message

#### Output on stdout

* Show message if log level of message is less than info level

### dybatpho::notice

Show notice message with banner.

#### Arguments

* **$1** (string): Message

#### Output on stdout

* Show message if log level of message is less than info level

### dybatpho::success

Show success message.

#### Arguments

* **$1** (string): Message

#### Output on stdout

* Show message if log level of message is less than info level

### dybatpho::warning

Show warning message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than warning level

### dybatpho::error

Show error message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than error level

### dybatpho::fatal

Show fatal message and exit process.

#### Arguments

* **$1** (string): Message
* **$2** (number): Exit code, default is 1

#### Exit codes

* $**2**: Stop to process anything else

#### Output on stderr

* Show message if log level of message is less than fatal level

### dybatpho::start_trace

Start tracing script.

_Function has no arguments._

### dybatpho::end_trace

End tracing script.

_Function has no arguments._

