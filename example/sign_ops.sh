#!/usr/bin/env bash
# @file sign_ops.sh
# @brief Example showing how to sign files and check signatures
# @description Lists the signing backends this machine has.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules sign

dybatpho::register_common_handlers

# @description Run every section of this example, in order.
# @noargs
function _main {
  dybatpho::header "BACKENDS"
  dybatpho::sign_backends verify
}

_main "$@"
