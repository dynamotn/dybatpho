#!/usr/bin/env bash
# @file helpers.sh
# @brief Utilities for writing efficient script
# @description
#   This module contains functions to write efficient script.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"

#######################################
# @description Check command dependency is installed.
# @arg $1 String command need to be installed
# @exitcode 127 Stop script if command isn't installed
# @exitcode 0 Otherwise run seamlessly
#######################################
function dybatpho::require {
  hash "$1" || dybatpho::die "$1 isn't installed" 127
}
