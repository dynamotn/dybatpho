#!/usr/bin/env bash
# @file basic.sh
# @brief A starter script to show how to use `dybatpho` library
# @description An example script to write a simple script using `dybatpho` library
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" # correct path of dybatpho at here

dybatpho::register_common_handlers

function _main {
  dybatpho::info "This is simple script using dybatpho library"
}
_main "$@"
