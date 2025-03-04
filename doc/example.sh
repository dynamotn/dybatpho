#!/usr/bin/env bash
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=1091
. "$SCRIPT_DIR/../init" # correct path of dybatpho at here

TEMP_FILE=$(mktemp)
dybatpho::register_err_handler
dybatpho::cleanup_file_on_exit "$TEMP_FILE"

function __main {
  local message
  dybatpho::expect_args message -- "$@"
  if ! dybatpho::is "command" "chezmoi"; then
    dybatpho::require "chezmoi"
  else
    dybatpho::debug "chezmoi is installed"
  fi
  dybatpho::curl_do https://github.com/dynamotn/dybatpho
  dybatpho::info "$message"
  dybatpho::start_trace
  dybatpho::is "set" "dyfoooo"
  dybatpho::breakpoint
  whoami
  dybatpho::end_trace
  dybatpho::success "Finish all logics of this script"
  dybatpho::die "Test" 1
}

# shellcheck disable=SC2034
LOG_LEVEL=trace
__main "This is example script that used dybatpho"
