#!/usr/bin/env bash
# @file example.sh
# @brief An example script to show how to use `dybatpho` library
# @description An example script to show how to use most of useful `dybatpho` commands
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" # correct path of dybatpho at here

export TEMP_FILE=$(mktemp)
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
  dybatpho::is empty "${BREAK}" || dybatpho::breakpoint
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

export LOG_LEVEL=debug
# _main "This is example script that used dybatpho"

_spec_main() {
  dybatpho::opts::setup "This is example script for dybatpho" MAIN_ARGS - action:_main
  dybatpho::opts::flag "Dry run" DRY_RUN --dry-run -d
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" validate:"trace|debug|info|warn|error|fatal"
  dybatpho::opts::param "Message show in command" MESSAGE --message -m optional:false
  dybatpho::opts::disp "Show help" --help action:dybatpho::generate_help
  dybatpho::opts::disp "Show version" --version action:"echo ${VERSION}"
  dybatpho::opts::cmd _spec_weather
}

_spec_weather() {
  dybatpho::opts::setup "Get weather of your location" WEATHER_ARGS weather action:_get_weather
}

dybatpho::generate_from_spec _spec_main
