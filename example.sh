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
  _success "Finish all logics of this script"
}

_main
