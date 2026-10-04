#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file array_ops.sh
# @brief Example showing array manipulation utilities
# @description
#   Demonstrates dybatpho::array_print, array_reverse, array_unique, array_compact, array_filter, array_map,
#   array_reject, array_find, array_every, array_some, array_first, array_last, array_contains, array_index_of,
#   array_join
# shellcheck disable=SC2034 # every array here is passed to the library by name,
#   which ShellCheck cannot follow through the nameref on the other side.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# @description Run the `ARRAY PRINT` section of this example.
# @noargs
function _demo_print {
  dybatpho::header "ARRAY PRINT"
  local -a fruits=("apple" "banana" "cherry" "date" "elderberry")
  dybatpho::info "Array elements:"
  local array_print_output
  array_print_output=$(dybatpho::array_print "fruits")
  while IFS= read -r item || [[ -n "${item}" ]]; do
    dybatpho::print "  ${item}"
  done < <(printf '%s' "${array_print_output}")
}

# @description Run the `ARRAY REVERSE` section of this example.
# @noargs
function _demo_reverse {
  dybatpho::header "ARRAY REVERSE"
  local -a nums=(1 2 3 4 5)
  local array_join_2
  array_join_2=$(dybatpho::array_join "nums" " ")
  dybatpho::info "Before: ${array_join_2}"
  dybatpho::array_reverse "nums"
  local array_join
  array_join=$(dybatpho::array_join "nums" " ")
  dybatpho::info "After : ${array_join}"
}

# @description Run the `ARRAY UNIQUE` section of this example.
# @noargs
function _demo_unique {
  dybatpho::header "ARRAY UNIQUE"
  local -a dupes=("cat" "dog" "cat" "bird" "dog" "dog" "fish")
  dybatpho::info "Before (${#dupes[@]} items): ${dupes[*]}"
  dybatpho::array_unique "dupes"
  dybatpho::info "After  (${#dupes[@]} items): ${dupes[*]}"
}

# @description Run the `ARRAY JOIN` section of this example.
# @noargs
function _demo_join {
  dybatpho::header "ARRAY JOIN"
  local -a tags=("bash" "shell" "scripting" "dybatpho")
  local array_join_2
  array_join_2=$(dybatpho::array_join "tags" " | ")
  dybatpho::info "Tags joined with ' | ': ${array_join_2}"
  local array_join
  array_join=$(dybatpho::array_join "tags" ",")
  dybatpho::info "Tags joined with ',': ${array_join}"
}

# @description Run the `ARRAY LOOKUP` section of this example.
# @noargs
function _demo_lookup {
  dybatpho::header "ARRAY LOOKUP"
  local -a tools=("bash" "curl" "git" "bats")
  local array_contains_2
  array_contains_2=$(dybatpho::array_contains "tools" "curl" && echo yes || echo no)
  dybatpho::info "Has curl? ${array_contains_2}"
  local array_contains
  array_contains=$(dybatpho::array_contains "tools" "jq" && echo yes || echo no)
  dybatpho::info "Has jq?   ${array_contains}"
  local array_index_of
  array_index_of=$(dybatpho::array_index_of "tools" "git")
  dybatpho::info "Index of git: ${array_index_of}"
}

# @description Run the `ARRAY COMPACT` section of this example.
# @noargs
function _demo_compact {
  dybatpho::header "ARRAY COMPACT"
  local -a values=("alpha" "" "beta" "" "gamma")
  dybatpho::info "Before (${#values[@]} items): ${values[*]}"
  dybatpho::array_compact "values"
  dybatpho::info "After  (${#values[@]} items): ${values[*]}"
}

# @description Predicate for `array_filter`: keep the names that start with `go`.
# @arg $1 string One element of the array
function _keep_go_like {
  [[ "$1" == go* ]]
}

# @description Run the `ARRAY FILTER` section of this example.
# @noargs
function _demo_filter {
  dybatpho::header "ARRAY FILTER"
  local -a langs=("go" "bash" "golang" "rust")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_filter "langs" "_keep_go_like"
  dybatpho::info "After : ${langs[*]}"
}

# @description Mapper for `array_map`: print one word in upper case.
# @arg $1 string One element of the array
# @stdout The element in upper case
function _upper_word {
  printf '%s\n' "${1^^}"
}

# @description Run the `ARRAY MAP` section of this example.
# @noargs
function _demo_map {
  dybatpho::header "ARRAY MAP"
  local -a langs=("go" "bash" "dybatpho")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_map "langs" "_upper_word"
  dybatpho::info "After : ${langs[*]}"
}

# @description Run the `ARRAY FIND` section of this example.
# @noargs
function _demo_find {
  dybatpho::header "ARRAY FIND"
  local -a langs=("bash" "golang" "go" "rust")
  local array_find
  array_find=$(dybatpho::array_find "langs" "_keep_go_like")
  dybatpho::info "First go-like value: ${array_find}"
}

# @description Run the `ARRAY REJECT` section of this example.
# @noargs
function _demo_reject {
  dybatpho::header "ARRAY REJECT"
  local -a langs=("go" "bash" "golang" "rust")
  dybatpho::info "Before: ${langs[*]}"
  dybatpho::array_reject "langs" "_keep_go_like"
  dybatpho::info "After : ${langs[*]}"
}

# @description Run the `ARRAY EVERY / SOME / EDGES` section of this example.
# @noargs
function _demo_quantifiers {
  dybatpho::header "ARRAY EVERY / SOME / EDGES"
  local -a lowercase=("bash" "go" "rust")
  local -a mixed=("Bash" "go")
  # @description Predicate for `array_every` and `array_some`: a word of lowercase letters.
  # @noargs
  function _is_lowercase_word { [[ "$1" =~ ^[a-z]+$ ]]; }
  local every_answer
  every_answer=$(dybatpho::array_every "lowercase" "_is_lowercase_word" && echo yes || echo no)
  dybatpho::info "All lowercase? lowercase => ${every_answer}"
  local some_answer
  some_answer=$(dybatpho::array_some "mixed" "_is_lowercase_word" && echo yes || echo no)
  dybatpho::info "Any lowercase? mixed      => ${some_answer}"
  local array_first
  array_first=$(dybatpho::array_first "lowercase")
  dybatpho::info "First lowercase value     => ${array_first}"
  local array_last
  array_last=$(dybatpho::array_last "lowercase")
  dybatpho::info "Last lowercase value      => ${array_last}"
}

# @description Run the `COMBINED: SPLIT → UNIQUE → SORT → JOIN` section of this example.
# @noargs
function _demo_pipeline {
  dybatpho::header "COMBINED: SPLIT → UNIQUE → SORT → JOIN"
  local raw="go,bash,python,go,bash,rust,python,go"
  dybatpho::info "Input  : ${raw}"

  local -a langs
  local split_output
  split_output=$(dybatpho::split "${raw}" ",")
  while IFS= read -r lang || [[ -n "${lang}" ]]; do
    langs+=("${lang}")
  done < <(printf '%s' "${split_output}")

  dybatpho::array_unique "langs"

  local -a sorted
  local array_print_output
  array_print_output=$(dybatpho::array_print "langs" | sort)
  while IFS= read -r lang || [[ -n "${lang}" ]]; do
    sorted+=("${lang}")
  done < <(printf '%s' "${array_print_output}")

  local array_join
  array_join=$(dybatpho::array_join "sorted" ", ")
  dybatpho::info "Output : ${array_join}"
}

# @description Put an array in order. Numbers are the reason: as text, `10`
#   sorts before `9`.
# @noargs
function _demo_order {
  dybatpho::header "ORDER"
  local -a releases=(1.10 1.9 2.0)
  dybatpho::array_sort releases
  dybatpho::print "  text:    ${releases[*]}"

  local -a sizes=(10 9 100 -3)
  dybatpho::array_sort sizes
  dybatpho::print "  as text: ${sizes[*]}"
  sizes=(10 9 100 -3)
  dybatpho::array_sort sizes --numeric
  dybatpho::print "  numeric: ${sizes[*]}"
  dybatpho::array_sort sizes --numeric --reverse
  dybatpho::print "  largest first: ${sizes[*]}"

  # A negative start counts back from the end, so the last two need no length
  # arithmetic at the call site.
  local -a recent=(build-1 build-2 build-3 build-4 build-5)
  dybatpho::array_slice recent -2
  dybatpho::print "  last two builds: ${recent[*]}"
}

# @description Compare two lists of permissions, which is what set operations
#   are for in a deployment script.
# @noargs
function _demo_sets {
  dybatpho::header "SETS"
  local -a requested=(read write admin read)
  local -a granted=(read write)

  local -a missing=("${requested[@]}")
  dybatpho::array_difference missing granted
  dybatpho::print "  requested but not granted: ${missing[*]}"

  local -a usable=("${requested[@]}")
  dybatpho::array_intersect usable granted
  dybatpho::print "  usable now:                ${usable[*]}"

  local -a everything=("${requested[@]}")
  dybatpho::array_union everything granted
  # The result is a set, so the duplicate `read` appears once.
  dybatpho::print "  either side:               ${everything[*]}"
}

# @description Run every section of this example, in order.
# @noargs
# @description Order a dependency graph, and ask what a root pulls in.
# @noargs
function _demo_graph {
  dybatpho::header "DEPENDENCY GRAPH"
  # The shape `init.sh` keeps its own module dependencies in: an entry maps to
  # the entries it needs, separated by spaces.
  local -A deps=(
    [cli]="config validate"
    [config]="validate"
    [tui]="cli safety"
    [safety]="archive"
  )

  local -a order=()
  dybatpho::array_toposort deps order
  printf 'load order: %s\n' "${order[*]}"

  # Only what one entry reaches, for "what would installing this pull in".
  local -a needed=()
  dybatpho::array_closure deps needed tui
  printf 'tui needs:  %s\n' "${needed[*]}"

  # A cycle is reported rather than refused: some graphs have one on purpose,
  # and an order is still useful.
  local -A cyclic=([text]="table" [table]="text")
  local -a broken=()
  if ! dybatpho::array_toposort cyclic broken; then
    printf 'cycle found, order still usable: %s\n' "${broken[*]}"
  fi
}

# @description Run every section of this example, in order.
# @noargs
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
  _demo_order
  _demo_sets
  _demo_graph
  dybatpho::success "Array operations demo complete"
}

_main "$@"
