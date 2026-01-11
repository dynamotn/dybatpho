#!/usr/bin/env bash
# @file common.sh
# @brief An example script to show how to use `dybatpho` library with real case
# @description An example script to show how to use most of useful `dybatpho` commands
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" # correct path of dybatpho at here

dybatpho::register_common_handlers
dybatpho::create_temp TEMP_FILE ".txt"
VERSION="v1.0.0"
MESSAGE=""

function _main {
  dybatpho::progress "Running main function with params ${MAIN_ARGS} ${BREAK}"

  dybatpho::info "This is sample progress bar"
  for i in {0..100}; do
    dybatpho::progress_bar "${i}"
    sleep 0.005
  done

  dybatpho::info "This is sample prerequisite setup"
  if dybatpho::is "command" "${PROGRAM}"; then
    dybatpho::debug "${PROGRAM} is installed"
  else
    dybatpho::require "${PROGRAM}"
  fi

  dybatpho::print "${MESSAGE}"
  dybatpho::is empty "${BREAK}" || dybatpho::breakpoint

  if dybatpho::compare_log_level trace; then
    dybatpho::info "This is sample tracing"
    dybatpho::start_trace
    whoami
    dybatpho::end_trace
  fi

  dybatpho::success "Finished main function" && exit 0
}

function _get_weather {
  local location
  dybatpho::expect_args location -- "$@"

  dybatpho::progress "Querying weather"
  dybatpho::dry_run "dybatpho::curl_do 'https://wttr.in/${location}' '${TEMP_FILE}'"
  dybatpho::dry_run "dybatpho::show_file '${TEMP_FILE}'"
  dybatpho::success "Finished getting weather of ${location}" && exit 0
}

function _get_cheatsheet {
  local keyword
  dybatpho::expect_args keyword -- "$@"

  dybatpho::progress "Querying cheatsheet"
  dybatpho::dry_run "dybatpho::curl_do 'https://cht.sh/${keyword}' '${TEMP_FILE}'"
  dybatpho::dry_run "dybatpho::show_file '${TEMP_FILE}'"
  dybatpho::success "Finished getting cheatsheet of ${keyword}" && exit 0
}

function _spec_weather {
  dybatpho::opts::setup "Get weather of your location" WEATHER_ARGS action:"_get_weather \$WEATHER_ARGS"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_weather"
}

function _spec_cheatsheet {
  dybatpho::opts::setup "Get cheatsheet of your keyword" CHTST_ARGS action:"_get_cheatsheet \$CHTST_ARGS"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_cheatsheet"
}

function _spec_main {
  dybatpho::opts::setup "This is example script for dybatpho" MAIN_ARGS action:"_main"
  dybatpho::opts::flag "Breakpoint" BREAK -b --break --no-break-point
  dybatpho::opts::param "Log level" LOG_LEVEL --log-level -l init:="info" validate:"dybatpho::validate_log_level \$OPTARG"
  dybatpho::opts::flag "Dry run" DRY_RUN --dry-run -D on:true off:false init:="false"
  dybatpho::opts::param "Message show in command" MESSAGE --message -m optional:true init:="Example script"
  dybatpho::opts::param "Program to check prerequisite" PROGRAM --program -p init:="cat"
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_main"
  dybatpho::opts::disp "Show version" --version action:"echo ${VERSION}"
  dybatpho::opts::cmd weather _spec_weather
  dybatpho::opts::cmd cheatsheet _spec_cheatsheet
}

LOG_LEVEL=debug
dybatpho::generate_from_spec _spec_main "$@"
