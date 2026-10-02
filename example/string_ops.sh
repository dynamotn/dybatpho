#!/usr/bin/env bash
# @file string_ops.sh
# @brief Example showing string manipulation utilities
# @description
#   Demonstrates dybatpho::trim, split, string matching, string_replace, string_trim_prefix, string_trim_suffix,
#   string_trim_chars, string_is_blank, string_truncate, string_lines, string_wrap, string_slugify, string_repeat,
#   string_pad, url_encode, url_decode, upper, lower, string_match, string_distance, string_closest
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# @description Run the `TRIM` section of this example.
# @noargs
function _demo_trim {
  dybatpho::header "TRIM"
  local raw="   hello world   "
  dybatpho::info "Input : '${raw}'"
  local trimmed
  trimmed=$(dybatpho::trim "${raw}")
  dybatpho::info "Trimmed: '${trimmed}'"
}

# @description Run the `SPLIT` section of this example.
# @noargs
function _demo_split {
  dybatpho::header "SPLIT"
  local csv="apple,banana,cherry,date"
  dybatpho::info "Splitting '${csv}' on ','"
  local split_output
  split_output=$(dybatpho::split "${csv}" ",")
  while IFS= read -r item || [[ -n "${item}" ]]; do
    dybatpho::print "  - ${item}"
  done < <(printf '%s' "${split_output}")
}

# @description Run the `URL ENCODE / DECODE` section of this example.
# @noargs
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

# @description Run the `STRING MATCHING` section of this example.
# @noargs
function _demo_match {
  dybatpho::header "STRING MATCHING"
  local text="dybatpho-demo.sh"
  dybatpho::info "Text      : ${text}"
  local string_starts_with
  string_starts_with=$(dybatpho::string_starts_with "${text}" "dybatpho" && echo yes || echo no)
  dybatpho::info "Starts with 'dybatpho': ${string_starts_with}"
  local string_ends_with
  string_ends_with=$(dybatpho::string_ends_with "${text}" ".sh" && echo yes || echo no)
  dybatpho::info "Ends with '.sh'       : ${string_ends_with}"
  local string_contains
  string_contains=$(dybatpho::string_contains "${text}" "demo" && echo yes || echo no)
  dybatpho::info "Contains 'demo'       : ${string_contains}"
}

# @description Run the `STRING REPLACE` section of this example.
# @noargs
function _demo_replace {
  dybatpho::header "STRING REPLACE"
  local text="go,bash,go,rust"
  dybatpho::info "Before: ${text}"
  local string_replace
  string_replace=$(dybatpho::string_replace "${text}" "go" "python")
  dybatpho::info "After : ${string_replace}"
}

# @description Run the `TRIM PREFIX / SUFFIX` section of this example.
# @noargs
function _demo_trim_affixes {
  dybatpho::header "TRIM PREFIX / SUFFIX"
  local ref="refs/heads/main"
  local archive="release.tar.gz"
  local string_trim_prefix
  string_trim_prefix=$(dybatpho::string_trim_prefix "${ref}" "refs/heads/")
  dybatpho::info "Trim prefix from '${ref}'      : ${string_trim_prefix}"
  local string_trim_suffix
  string_trim_suffix=$(dybatpho::string_trim_suffix "${archive}" ".gz")
  dybatpho::info "Trim suffix from '${archive}' : ${string_trim_suffix}"
}

# @description Run the `SLUGIFY` section of this example.
# @noargs
function _demo_slugify {
  dybatpho::header "SLUGIFY"
  local title="Hello, Dybatpho World! Release 2026"
  dybatpho::info "Input : ${title}"
  local string_slugify
  string_slugify=$(dybatpho::string_slugify "${title}")
  dybatpho::info "Slug  : ${string_slugify}"
}

# @description Run the `BLANK / TRIM CHARS` section of this example.
# @noargs
function _demo_blank_and_trim_chars {
  dybatpho::header "BLANK / TRIM CHARS"
  local padded="__release-candidate__"
  local string_is_blank
  string_is_blank=$(dybatpho::string_is_blank "   " && echo yes || echo no)
  dybatpho::info "Blank? whitespace only => ${string_is_blank}"
  local string_trim_chars
  string_trim_chars=$(dybatpho::string_trim_chars "${padded}" "_")
  dybatpho::info "Trim '_' from '${padded}': ${string_trim_chars}"
}

# @description Run the `TRUNCATE / LINES / WRAP` section of this example.
# @noargs
function _demo_truncate_lines_wrap {
  dybatpho::header "TRUNCATE / LINES / WRAP"
  local paragraph="dybatpho helps shell scripts stay readable and composable across many small utilities"
  local string_truncate
  string_truncate=$(dybatpho::string_truncate "${paragraph}" 18)
  dybatpho::info "Truncate to 18 chars: ${string_truncate}"
  local string_lines
  string_lines=$(dybatpho::string_lines $'alpha\nbeta\ngamma')
  dybatpho::info "Logical lines in sample: ${string_lines}"
  dybatpho::info "Wrapped paragraph:"
  local string_wrap_output
  string_wrap_output=$(dybatpho::string_wrap "${paragraph}" 24 "> ")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    dybatpho::print "  ${line}"
  done < <(printf '%s' "${string_wrap_output}")
}

# @description Run the `STRING REPEAT / PAD` section of this example.
# @noargs
function _demo_repeat_and_pad {
  dybatpho::header "STRING REPEAT / PAD"
  local string_repeat
  string_repeat=$(dybatpho::string_repeat "=" 10)
  dybatpho::info "Repeat '=' 10 times: ${string_repeat}"
  local string_pad
  string_pad=$(dybatpho::string_pad "go" 6 ".")
  dybatpho::info "Pad 'go' to width 6 : '${string_pad}'"
}

# @description Run the `UPPER / LOWER` section of this example.
# @noargs
function _demo_case {
  dybatpho::header "UPPER / LOWER"
  local word="Hello World"
  dybatpho::info "Original : ${word}"
  local upper
  upper=$(dybatpho::upper "${word}")
  dybatpho::info "Upper    : ${upper}"
  local lower
  lower=$(dybatpho::lower "${word}")
  dybatpho::info "Lower    : ${lower}"
}

# @description Move a name between the conventions a codebase mixes: a CLI flag
#   in kebab case, an environment variable in snake case, a function in camel.
# @noargs
function _demo_naming {
  dybatpho::header "NAMING CONVENTIONS"
  local name
  for name in "XMLHttpRequest" "deploy_to_prod" "deploy-to-prod" "Deploy To Prod"; do
    local padded
    padded=$(printf '%-16s' "${name}")
    local string_to_pascal
    string_to_pascal=$(dybatpho::string_to_pascal "${name}")
    local string_to_camel
    string_to_camel=$(dybatpho::string_to_camel "${name}")
    local string_to_kebab_2
    string_to_kebab_2=$(dybatpho::string_to_kebab "${name}")
    local string_to_snake
    string_to_snake=$(dybatpho::string_to_snake "${name}")
    dybatpho::print "  ${padded} -> snake ${string_to_snake},\
 kebab ${string_to_kebab_2},\
 camel ${string_to_camel},\
 pascal ${string_to_pascal}"
  done
  # Slugify has no idea where the words are; these read the boundaries the
  # convention implies.
  local string_slugify
  string_slugify=$(dybatpho::string_slugify XMLHttpRequest)
  dybatpho::print "  slugify XMLHttpRequest -> ${string_slugify}"
  local string_to_kebab
  string_to_kebab=$(dybatpho::string_to_kebab XMLHttpRequest)
  dybatpho::print "  kebab   XMLHttpRequest -> ${string_to_kebab}"
}

# @description Put a value into shell code that will be evaluated later, without
#   its spaces and quotes being read as syntax.
# @noargs
function _demo_quote {
  dybatpho::header "QUOTING FOR THE SHELL"
  local text
  for text in "a b" "it's" 'say "hi"' ""; do
    local string_quote_2
    string_quote_2=$(dybatpho::string_quote "${text}")
    dybatpho::print "  [${text}] -> ${string_quote_2}"
  done
  # The empty string quotes to something visible, which is the point: unquoted,
  # it would vanish from the command it was part of.
  local remote_command="ls -la /tmp/my dir"
  local string_quote
  string_quote=$(dybatpho::string_quote "${remote_command}")
  dybatpho::print "  ssh host ${string_quote}"
}

# @description Pull a version apart with capture groups, and tell a branch name
#   that is not a version from one that is.
# @noargs
function _demo_regex {
  dybatpho::header "REGEX CAPTURES"
  local -a parts=()
  local ref
  for ref in "v1.24.3" "main"; do
    if dybatpho::string_match parts "${ref}" '^v([0-9]+)\.([0-9]+)\.([0-9]+)$'; then
      dybatpho::print "  ${ref} -> major ${parts[1]}, minor ${parts[2]}, patch ${parts[3]}"
    else
      dybatpho::print "  ${ref} -> not a version tag"
    fi
  done
}

# @description Suggest what a user meant when a subcommand is mistyped.
# @noargs
function _demo_distance {
  dybatpho::header "EDIT DISTANCE / DID YOU MEAN"
  local distance
  distance=$(dybatpho::string_distance kitten sitting)
  dybatpho::info "kitten -> sitting takes ${distance} edits"
  local -a commands=(status start stash build deploy) guesses=()
  local typed
  for typed in "staus" "dploy" "frobnicate"; do
    if dybatpho::string_closest guesses "${typed}" 2 "${commands[@]}"; then
      dybatpho::print "  ${typed}: did you mean ${guesses[*]}?"
    else
      dybatpho::print "  ${typed}: no close command"
    fi
  done
}

# @description Run every section of this example, in order.
# @noargs
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
  _demo_naming
  _demo_quote
  _demo_regex
  _demo_distance
  dybatpho::success "String operations demo complete"
}

_main "$@"
