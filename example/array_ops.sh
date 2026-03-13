#!/usr/bin/env bash
# @file array_ops.sh
# @brief Example showing array manipulation utilities
# @description Demonstrates dybatpho::array_print, array_reverse, array_unique, array_compact, array_filter, array_map, array_reject, array_find, array_every, array_some, array_first, array_last, array_contains, array_index_of, array_join
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_print {
  dybatpho::header "ARRAY PRINT"
  local -a fruits=("apple" "banana" "cherry" "date" "elderberry")
  dybatpho::info "Array elements:"
  dybatpho::array_print "fruits" | while IFS= read -r item; do
    dybatpho::print "  ${item}"
  done
}

function _demo_reverse {
  dybatpho::header "ARRAY REVERSE"
  local -a nums=(1 2 3 4 5)
  dybatpho::info "Before: $(dybatpho::array_join "nums" " ")"
  dybatpho::array_reverse "nums"
  dybatpho::info "After : $(dybatpho::array_join "nums" " ")"
}

function _demo_unique {
  dybatpho::header "ARRAY UNIQUE"
  local -a dupes=("cat" "dog" "cat" "bird" "dog" "dog" "fish")
  dybatpho::info "Before (${#dupes[@]} items): ${dupes[*]}"
  dybatpho::array_unique "dupes"
  dybatpho::info "After  (${#dupes[@]} items): ${dupes[*]}"
}

function _demo_join {
  dybatpho::header "ARRAY JOIN"
  local -a tags=("bash" "shell" "scripting" "dybatpho")
  dybatpho::info "Tags joined with ' | ': $(dybatpho::array_join "tags" " | ")"
  dybatpho::info "Tags joined with ',': $(dybatpho::array_join "tags" ",")"
}

function _demo_lookup {
  dybatpho::header "ARRAY LOOKUP"
  local -a tools=("bash" "curl" "git" "bats")
  dybatpho::info "Has curl? $(dybatpho::array_contains "tools" "curl" && echo yes || echo no)"
  dybatpho::info "Has jq?   $(dybatpho::array_contains "tools" "jq" && echo yes || echo no)"
  dybatpho::info "Index of git: $(dybatpho::array_index_of "tools" "git")"
}

function _demo_compact {
  dybatpho::header "ARRAY COMPACT"
  local -a values=("alpha" "" "beta" "" "gamma")
  dybatpho::info "Before (${#values[@]} items): ${values[*]}"
  dybatpho::array_compact "values"
  dybatpho::info "After  (${#values[@]} items): ${values[*]}"
}

function _keep_go_like {
  [[ "$1" == go* ]]
}

function _demo_filter {
  dybatpho::header "ARRAY FILTER"
  local -a langs=("go" "bash" "golang" "rust")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_filter "langs" "_keep_go_like"
  dybatpho::info "After : ${langs[*]}"
}

function _upper_word {
  printf '%s\n' "${1^^}"
}

function _demo_map {
  dybatpho::header "ARRAY MAP"
  local -a langs=("go" "bash" "dybatpho")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_map "langs" "_upper_word"
  dybatpho::info "After : ${langs[*]}"
}

function _demo_find {
  dybatpho::header "ARRAY FIND"
  local -a langs=("bash" "golang" "go" "rust")
  dybatpho::info "First go-like value: $(dybatpho::array_find "langs" "_keep_go_like")"
}

function _demo_reject {
  dybatpho::header "ARRAY REJECT"
  local -a langs=("go" "bash" "golang" "rust")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_reject "langs" "_keep_go_like"
  dybatpho::info "After : ${langs[*]}"
}

function _demo_quantifiers {
  dybatpho::header "ARRAY EVERY / SOME / EDGES"
  local -a lowercase=("bash" "go" "rust")
  local -a mixed=("Bash" "go")
  _is_lowercase_word() { [[ "$1" =~ ^[a-z]+$ ]]; }
  dybatpho::info "All lowercase? lowercase => $(dybatpho::array_every "lowercase" "_is_lowercase_word" && echo yes || echo no)"
  dybatpho::info "Any lowercase? mixed      => $(dybatpho::array_some "mixed" "_is_lowercase_word" && echo yes || echo no)"
  dybatpho::info "First lowercase value     => $(dybatpho::array_first "lowercase")"
  dybatpho::info "Last lowercase value      => $(dybatpho::array_last "lowercase")"
}

function _demo_pipeline {
  dybatpho::header "COMBINED: SPLIT → UNIQUE → SORT → JOIN"
  local raw="go,bash,python,go,bash,rust,python,go"
  dybatpho::info "Input  : ${raw}"

  local -a langs
  while IFS= read -r lang; do
    langs+=("${lang}")
  done < <(dybatpho::split "${raw}" ",")

  dybatpho::array_unique "langs"

  local -a sorted
  while IFS= read -r lang; do
    sorted+=("${lang}")
  done < <(dybatpho::array_print "langs" | sort)

  dybatpho::info "Output : $(dybatpho::array_join "sorted" ", ")"
}

function _main {
  _demo_print
  _demo_reverse
  _demo_unique
  _demo_compact
  _demo_filter
  _demo_map
  _demo_reject
  _demo_find
  _demo_quantifiers
  _demo_lookup
  _demo_join
  _demo_pipeline
  dybatpho::success "Array operations demo complete"
}

_main "$@"
