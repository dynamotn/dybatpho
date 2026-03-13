#!/usr/bin/env bash
# @file string_ops.sh
# @brief Example showing string manipulation utilities
# @description Demonstrates dybatpho::trim, split, string matching, string_replace, string_trim_prefix, string_trim_suffix, string_trim_chars, string_is_blank, string_truncate, string_lines, string_wrap, string_slugify, string_repeat, string_pad, url_encode, url_decode, upper, lower
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

function _demo_match {
  dybatpho::header "STRING MATCHING"
  local text="dybatpho-demo.sh"
  dybatpho::info "Text      : ${text}"
  dybatpho::info "Starts with 'dybatpho': $(dybatpho::string_starts_with "${text}" "dybatpho" && echo yes || echo no)"
  dybatpho::info "Ends with '.sh'       : $(dybatpho::string_ends_with "${text}" ".sh" && echo yes || echo no)"
  dybatpho::info "Contains 'demo'       : $(dybatpho::string_contains "${text}" "demo" && echo yes || echo no)"
}

function _demo_replace {
  dybatpho::header "STRING REPLACE"
  local text="go,bash,go,rust"
  dybatpho::info "Before: ${text}"
  dybatpho::info "After : $(dybatpho::string_replace "${text}" "go" "python")"
}

function _demo_trim_affixes {
  dybatpho::header "TRIM PREFIX / SUFFIX"
  local ref="refs/heads/main"
  local archive="release.tar.gz"
  dybatpho::info "Trim prefix from '${ref}'      : $(dybatpho::string_trim_prefix "${ref}" "refs/heads/")"
  dybatpho::info "Trim suffix from '${archive}' : $(dybatpho::string_trim_suffix "${archive}" ".gz")"
}

function _demo_slugify {
  dybatpho::header "SLUGIFY"
  local title="Hello, Dybatpho World! Release 2026"
  dybatpho::info "Input : ${title}"
  dybatpho::info "Slug  : $(dybatpho::string_slugify "${title}")"
}

function _demo_blank_and_trim_chars {
  dybatpho::header "BLANK / TRIM CHARS"
  local padded="__release-candidate__"
  dybatpho::info "Blank? whitespace only => $(dybatpho::string_is_blank "   " && echo yes || echo no)"
  dybatpho::info "Trim '_' from '${padded}': $(dybatpho::string_trim_chars "${padded}" "_")"
}

function _demo_truncate_lines_wrap {
  dybatpho::header "TRUNCATE / LINES / WRAP"
  local paragraph="dybatpho helps shell scripts stay readable and composable across many small utilities"
  dybatpho::info "Truncate to 18 chars: $(dybatpho::string_truncate "${paragraph}" 18)"
  dybatpho::info "Logical lines in sample: $(dybatpho::string_lines $'alpha\nbeta\ngamma')"
  dybatpho::info "Wrapped paragraph:"
  dybatpho::string_wrap "${paragraph}" 24 "> " | while IFS= read -r line; do
    dybatpho::print "  ${line}"
  done
}

function _demo_repeat_and_pad {
  dybatpho::header "STRING REPEAT / PAD"
  dybatpho::info "Repeat '=' 10 times: $(dybatpho::string_repeat "=" 10)"
  dybatpho::info "Pad 'go' to width 6 : '$(dybatpho::string_pad "go" 6 ".")'"
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
  _demo_match
  _demo_replace
  _demo_trim_affixes
  _demo_blank_and_trim_chars
  _demo_truncate_lines_wrap
  _demo_slugify
  _demo_repeat_and_pad
  _demo_url
  _demo_case
  dybatpho::success "String operations demo complete"
}

_main "$@"
