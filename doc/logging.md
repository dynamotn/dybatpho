# logging.sh

Utilities for logging to stdout/stderr

## Overview

This module contains functions to log messages to stdout/stderr.

**LOG_LEVEL** (string): Run time log level of all messages (trace|debug|info|warn|error|fatal). Default is `info`
**NO_COLOR** (string): Prevents the addition of ANSI color to the output when present and not an empty string. Default is ``

## Index

* [__log](#log)
* [dybatpho::compare_log_level](#dybatphocompareloglevel)
* [__log_inspect](#loginspect)
* [dybatpho::validate_log_level](#dybatphovalidateloglevel)
* [dybatpho::debug](#dybatphodebug)
* [dybatpho::debug_command](#dybatphodebugcommand)
* [dybatpho::info](#dybatphoinfo)
* [dybatpho::print](#dybatphoprint)
* [dybatpho::progress](#dybatphoprogress)
* [dybatpho::progress_bar](#dybatphoprogressbar)
* [dybatpho::notice](#dybatphonotice)
* [dybatpho::success](#dybatphosuccess)
* [dybatpho::warn](#dybatphowarn)
* [dybatpho::error](#dybatphoerror)
* [dybatpho::fatal](#dybatphofatal)
* [dybatpho::start_trace](#dybatphostarttrace)
* [dybatpho::end_trace](#dybatphoendtrace)

### __log

Log a message to stdout/stderr with color and caution

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

### dybatpho::compare_log_level

Verify input log level is less than runtime log level

#### Arguments

* **$1** (string): Input log level

#### Exit codes

* **0**: If less than
* **1**: Otherwise

### __log_inspect

Log a message with date time and invoke file indicator for easier
to recognize on tty

#### Arguments

* **$1** (string): String of log level
* **$2** (string): Text of log level
* **$3** (string): Message
* **$4** (string): Indicator of message, default is `<invoke file>:<line number of invoke file>`
* **$5** (string): ANSI escape color code

### dybatpho::validate_log_level

Validate log level from input.

#### Arguments

* **$1** (string): String of log level

#### Exit codes

* **0**: If is valid log level
* **1**: If invalid

### dybatpho::debug

Show debug message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than debug level

### dybatpho::debug_command

Show debug result of a command.

#### Arguments

* **$1** (string): Message
* **$2** (string): Command

#### Output on stderr

* Show message if log level of message is less than debug level

### dybatpho::info

Show info message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than info level

### dybatpho::print

Show normal message.

#### Arguments

* **$1** (string): Message

#### Output on stdout

* Show message if log level of message is less than info level

### dybatpho::progress

Show in progress message.

#### Arguments

* **$1** (string): Message

#### Output on stdout

* Show message if log level of message is less than info level

### dybatpho::progress_bar

Show progress bar.

#### Arguments

* **$1** (number): Elapsed percentage
* **$2** (number): Total length of progress bar in chars. Default is 50

#### Output on stdout

* Show progress bar and it's disappeared after done

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

### dybatpho::warn

Show warning message.

#### Arguments

* **$1** (string): Message

#### Output on stderr

* Show message if log level of message is less than warn level

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
* **$2** (string): Indicator of message, default is `<invoke file>:<line number of invoke file>`

#### Output on stderr

* Show message if log level of message is less than fatal level

### dybatpho::start_trace

Start tracing script.

_Function has no arguments._

### dybatpho::end_trace

End tracing script.

_Function has no arguments._

