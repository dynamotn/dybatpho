#!/usr/bin/env bash
source init.sh

tmpfile="$(mktemp -t myprogram-XXXXXX)"
trap _clean_up EXIT

_clean_up() {
  rm -f "$tmpfile"
}

_main() {
  _require "chezmoi"
  _info "This is example script that used dybatpho"
  _start_trace
  whoami
  _end_trace
  _success "Finish all logics of this script"
}

# shellcheck disable=SC2034
LOG_LEVEL=trace
_main
