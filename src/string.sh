#!/usr/bin/env bash
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# Convert a string to lowercase.
# Arguments:
#   1: string to change
# Outputs:
#   Converted string
#######################################
_lower() {
  printf '%s\n' "${1,,}"
}

#######################################
# Convert a string to uppercase.
# Arguments:
#   1: string to change
# Outputs:
#   Converted string
#######################################
_upper() {
  printf '%s\n' "${1^^}"
}
