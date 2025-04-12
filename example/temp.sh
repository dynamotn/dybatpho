#!/usr/bin/env bash
# @file example.sh
# @brief An example script to show how to use `dybatpho` library
# @description An example script to show how to use most of useful `dybatpho` commands
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" # correct path of dybatpho at here

dybatpho::register_err_handler
TEMP_FILE=1
dybatpho::create_temp TEMP_FILE "" "temp" /tmp/1
if dybatpho::is file "${TEMP_FILE}"; then
  echo 1111 > "${TEMP_FILE}"
  cat "${TEMP_FILE}"
elif dybatpho::is dir "${TEMP_FILE}"; then
  realpath "${TEMP_FILE}"
  ls -la "${TEMP_FILE}"
fi
set -x
