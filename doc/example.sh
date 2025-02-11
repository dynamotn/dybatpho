#!/usr/bin/env bash
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$SCRIPT_DIR/../init.sh" # correct path of dybatpho at here

tmpfile="$(mktemp -t myprogram-XXXXXX)"
trap __clean_up EXIT
dybatpho::register_err_handler

function __clean_up {
  rm -f "$tmpfile"
}

function __main {
  dybatpho::require "chezmoi"
  dybatpho::info "This is example script that used dybatpho"
  dybatpho::start_trace
  dybatpho::breakpoint
  whoami
  dybatpho::pause_trace
  dybatpho::end_trace
  dybatpho::success "Finish all logics of this script"
  dybatpho::die "Test" 1
}

# shellcheck disable=SC2034
LOG_LEVEL=trace
__main
