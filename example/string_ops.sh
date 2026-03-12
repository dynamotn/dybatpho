#!/usr/bin/env bash
# @file string_ops.sh
# @brief Example showing string manipulation utilities
# @description Demonstrates dybatpho::trim, split, url_encode, url_decode, upper, lower
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_trim {
  dybatpho::header "TRIM"
  local raw="   hello world   "
  dybatpho::info "Input : '${raw}'"
  local trimmed
  trimmed=$(dybatpho::trim "${raw}")
  dybatpho::info "Trimmed: '${trimmed}'"
}

function _demo_split {
  dybatpho::header "SPLIT"
  local csv="apple,banana,cherry,date"
  dybatpho::info "Splitting '${csv}' on ','"
  while IFS= read -r item; do
    dybatpho::print "  - ${item}"
  done < <(dybatpho::split "${csv}" ",")
}

function _demo_url {
  dybatpho::header "URL ENCODE / DECODE"
  local raw="hello world & foo=bar+baz"
  dybatpho::info "Original : ${raw}"
  local encoded
  encoded=$(dybatpho::url_encode "${raw}")
  dybatpho::info "Encoded  : ${encoded}"
  local decoded
  decoded=$(dybatpho::url_decode "${encoded}")
  dybatpho::info "Decoded  : ${decoded}"
}

function _demo_case {
  dybatpho::header "UPPER / LOWER"
  local word="Hello World"
  dybatpho::info "Original : ${word}"
  dybatpho::info "Upper    : $(dybatpho::upper "${word}")"
  dybatpho::info "Lower    : $(dybatpho::lower "${word}")"
}

function _main {
  _demo_trim
  _demo_split
  _demo_url
  _demo_case
  dybatpho::success "String operations demo complete"
}

_main "$@"
