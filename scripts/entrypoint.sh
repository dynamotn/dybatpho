#!/usr/bin/env bash
# @file entrypoint.sh
# @brief An entrypoint script to preload dybatpho library and run a command inside a container
# @description
#   The container entrypoint: it sources the library once, installs the common
#   handlers, and then runs whatever command the container was given, so an
#   image can call a `dybatpho::` function without sourcing anything itself.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"
dybatpho::register_common_handlers

"$@"
