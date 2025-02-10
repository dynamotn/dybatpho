#!/usr/bin/env bash
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# Check command dependency is installed.
# Arguments:
#   1: command need to be installed
# Outputs:
#   Exit script if isn't installed, otherwise run seamlessly
#######################################
_require() {
  hash "$*" || _fatal "$* isn't installed" 127
}
