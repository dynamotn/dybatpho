# array.sh

Utilities for working with array

## Overview

This module contains functions to work with array.

## Index

* [dybatpho::array_print](#dybatphoarrayprint)
* [dybatpho::array_reverse](#dybatphoarrayreverse)
* [dybatpho::array_unique](#dybatphoarrayunique)
* [dybatpho::array_join](#dybatphoarrayjoin)

### dybatpho::array_print

Print an array

#### Arguments

* **$1** (string): Name of array

#### Output on stdout

* Print array with each element separated by newline

### dybatpho::array_reverse

Reverse an array

#### Arguments

* **$1** (string): Name of array
* **$2** (string): Set `--` to print to stdout

#### Output on stdout

* Print array if $2 is `--`

### dybatpho::array_unique

Remove duplicate elements in array

#### Arguments

* **$1** (string): Name of array
* **$2** (string): Set `--` to print to stdout

#### Output on stdout

* Print array if $2 is `--`

### dybatpho::array_join

Join array with given separator into a string

#### Arguments

* **$1** (string): Name of array
* **$2** (string): Separator

#### Output on stdout

* Print outputted string

