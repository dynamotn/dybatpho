#!/usr/bin/env bash
# @file entrypoint.sh
# @brief An entrypoint script to preload dybatpho library and run a command inside a container
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"
dybatpho::register_common_handlers

"$@"
