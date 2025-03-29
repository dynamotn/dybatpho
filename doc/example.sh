#!/usr/bin/env bash
# @file example.sh
# @brief An example script to show how to use `dybatpho` library
# @description An example script to show how to use most of useful `dybatpho` commands
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" # correct path of dybatpho at here

TEMP_FILE=$(mktemp)
# shellcheck disable=2034
VERSION="v1.0.0"
dybatpho::register_err_handler
dybatpho::cleanup_file_on_exit "${TEMP_FILE}"

function _main {
  local message
  dybatpho::expect_args message -- "$@"
  if ! dybatpho::is "command" "chezmoi"; then
    dybatpho::require "chezmoi"
  else
    dybatpho::debug "chezmoi is installed"
  fi
  dybatpho::info "${message}"
  dybatpho::start_trace
  dybatpho::is "set" "dyfoooo"
  dybatpho::breakpoint
  whoami
  dybatpho::end_trace
  dybatpho::success "Finish all logics of this script"
  dybatpho::die "Test" 1
}

#######################################
# @description Get weather
#######################################
function _get_weather {
  dybatpho::curl_do https://wttr.in
}

# shellcheck disable=SC2034
LOG_LEVEL=trace
# __main "This is example script that used dybatpho"

_spec_main() {
  export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  # set -x
  dybatpho::opts::setup "This is example script for dybatpho" MAIN_ARGS -
  dybatpho::opts::flag "Dry run" DRY_RUN --dry-run -d
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l
  dybatpho::opts::param "Breakpoint before show whoami" BREAK --break -b init:@off
  dybatpho::opts::disp "Show help" action:dybatpho::generate_help --help
  dybatpho::opts::disp "Show version" VERSION --version
  dybatpho::opts::cmd weather _spec_weather
}

_spec_weather() {
  dybatpho::opts::setup "This is example script for dybatpho" WEATHER_ARGS -
}

dybatpho::generate_from_spec _spec_main _main
