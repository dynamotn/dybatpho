#!/usr/bin/env bash
# @file text_ops.sh
# @brief Example showing multi-line text utilities
# @description Demonstrates dybatpho::text_indent, text_dedent, text_strip_ansi, text_bullet_list, and text_columns
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules text

dybatpho::register_common_handlers

# @description Run the `INDENT` section of this example.
# @noargs
function _demo_indent {
  local block=$'alpha\nbeta'
  dybatpho::header "INDENT"
  dybatpho::text_indent "${block}" "> "
}

# @description Run the `DEDENT` section of this example.
# @noargs
function _demo_dedent {
  local block=$'    line one\n      line two\n    line three'
  dybatpho::header "DEDENT"
  dybatpho::text_dedent "${block}"
}

# @description Run the `STRIP ANSI` section of this example.
# @noargs
function _demo_strip_ansi {
  local colored=$'\e[1;32mgreen text\e[0m\n\e[0;34mblue text\e[0m'
  dybatpho::header "STRIP ANSI"
  dybatpho::text_strip_ansi "${colored}"
}

# @description Run the `BULLET LIST` section of this example.
# @noargs
function _demo_bullets {
  local items=$'install dependencies\nrun tests\nship release'
  dybatpho::header "BULLET LIST"
  dybatpho::text_bullet_list "${items}" "•"
}

# @description Run the `TEXT COLUMNS` section of this example.
# @noargs
function _demo_columns {
  local rows=$'Key::Value\nname::dybatpho\nversion::1.0.0'
  dybatpho::header "TEXT COLUMNS"
  dybatpho::text_columns "${rows}" "::" 1
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_indent
  _demo_dedent
  _demo_strip_ansi
  _demo_bullets
  _demo_columns
  dybatpho::success "Text operations demo complete"
}

_main "$@"
