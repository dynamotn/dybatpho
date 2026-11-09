#!/usr/bin/env bash
# @file service_ops.sh
# @brief Example showing how to inspect and preview service management
# @description Reports the machine's service manager. It never changes a service.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules service

dybatpho::register_common_handlers

# @description Run every section of this example, in order.
# @noargs
function _main {
  dybatpho::header "MANAGER"
  local manager=""
  manager="$(dybatpho::service_manager)" || true
  dybatpho::info "Service manager: ${manager:-none}"
}

_main "$@"
