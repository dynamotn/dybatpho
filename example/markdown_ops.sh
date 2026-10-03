#!/usr/bin/env bash
# @file markdown_ops.sh
# @brief Example building a release report in Markdown
# @description Demonstrates dybatpho::md_heading, md_list, md_task_list, md_link, md_badge,
#   md_code_block, md_table, md_collapsible, md_raw, md_escape, md_mention, and md_emoji
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules markdown table

dybatpho::register_common_handlers

# The values a real script would read from `git log`, a CI variable or a
# command's output. They carry the characters that make hand-built Markdown go
# wrong: `*`, `[`, `|`, and a leading `-`.
RELEASE_TITLE='Release v2.0.0 [stable]'
CHANGES=$'fix: stop *masking* the exit code\nfeat: add the | delimiter option\n- chore: drop the legacy path'
BUILD_LOG=$'Compiling 12 files\nAll tests passed'

# @description Build the report header: title, badges and the release link.
# @noargs
function _demo_header {
  dybatpho::header "HEADER"
  dybatpho::md_heading 1 "${RELEASE_TITLE}"
  printf '\n'
  # A builder's own output is already Markdown, so placing two badges on one
  # line is ordinary concatenation; nothing re-escapes them.
  printf '%s %s\n\n' \
    "$(dybatpho::md_badge "build" "passing" "green")" \
    "$(dybatpho::md_badge "version" "2.0.0" "blue" "https://example.com/releases/v2.0.0")"
  printf 'Released by %s %s -- see %s\n' \
    "$(dybatpho::md_mention dynamotn)" \
    "$(dybatpho::md_emoji rocket)" \
    "$(dybatpho::md_link "the full changelog" "https://example.com/CHANGELOG.md")"
}

# @description Build the change list, escaped from the raw commit subjects.
# @noargs
function _demo_changes {
  dybatpho::header "CHANGES"
  dybatpho::md_heading 2 "What changed"
  dybatpho::md_list "${CHANGES}"
}

# @description Build the remaining release checklist.
# @noargs
function _demo_checklist {
  dybatpho::header "CHECKLIST"
  dybatpho::md_heading 2 "Before publishing"
  dybatpho::md_task_list $'x|Tag the commit\nx|Upload the artifacts\n|Announce the release'
}

# @description Build the artifact table.
#   Cells are escaped first and joined with `::`, which the escape leaves alone;
#   joining with `|` would not survive escaping the cell values.
# @noargs
function _demo_table {
  dybatpho::header "ARTIFACTS"
  local rows="Artifact::Size"
  local name
  for name in "dybatpho-linux-amd64.tar.gz" "dybatpho-darwin-arm64.tar.gz"; do
    rows+=$'\n'"$(dybatpho::md_escape "${name}")::1.2 MB"
  done
  dybatpho::md_heading 2 "Artifacts"
  dybatpho::md_table "${rows}" "::"
}

# @description Fold the build log into a collapsible section.
# @noargs
function _demo_collapsible {
  dybatpho::header "BUILD LOG"
  dybatpho::md_collapsible "Full build log" "$(dybatpho::md_code_block "" "${BUILD_LOG}")"
}

# @description Show what the escape prevents, side by side.
# @noargs
function _demo_escaping {
  dybatpho::header "ESCAPING"
  # Passed straight into a builder, an interpolated value is escaped; wrapped in
  # `md_raw`, it is embedded as the Markdown it already is.
  dybatpho::md_list "$(dybatpho::md_raw "$(dybatpho::md_link "a real link" "https://example.com")")"
  dybatpho::md_list "[not a link](https://example.com)"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_header
  _demo_changes
  _demo_checklist
  _demo_table
  _demo_collapsible
  _demo_escaping
  dybatpho::success "Markdown operations demo complete"
}

_main "$@"
