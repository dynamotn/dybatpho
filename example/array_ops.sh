#!/usr/bin/env bash
# @file array_ops.sh
# @brief Example showing array manipulation utilities
# @description Demonstrates dybatpho::array_print, array_reverse, array_unique, array_join
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
  _demo_join
  _demo_pipeline
  dybatpho::success "Array operations demo complete"
}

_main "$@"
