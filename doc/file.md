# file.sh

Utilities for file handling

## Overview

This module containss functions to file handling

## Index

* [dybatpho::show_file](#dybatphoshowfile)
* [dybatpho::create_temp](#dybatphocreatetemp)

### dybatpho::show_file

Show content of file

#### Arguments

* **$1** (string): File path

#### Output on stderr

* Content of file

### dybatpho::create_temp

Create temporary file or folder and cleanup it on exit

#### Arguments

* **$1** (string): Variable name to get file/folder path
* **$2** (string): Extension of file name, use `/` or empty for folder
* **$3** (string): Prefix of file/folder name, default is `temp`
* **$4** (string): Parent folder for file/folder, default is `$TMPDIR`

