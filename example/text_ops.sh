#!/usr/bin/env bash
# @file text_ops.sh
# @brief Example showing multi-line text utilities
# @description Demonstrates dybatpho::text_indent, text_dedent, text_strip_ansi, text_bullet_list, text_columns,
#   text_box, text_center, text_number_lines, and text_truncate_lines
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

# @description Run the `BOX` section of this example.
# @noargs
function _demo_box {
  local summary=$'3 files changed\n2 tests added\n0 warnings'
  dybatpho::header "BOX"
  dybatpho::text_box "${summary}" "Build summary"
  dybatpho::text_box "plain ASCII for old terminals" "" ascii
}

# @description Run the `CENTER` section of this example.
# @noargs
function _demo_center {
  dybatpho::header "CENTER"
  dybatpho::text_center $'dybatpho\na bash utility library' 40
}

# @description Run the `NUMBER LINES` section of this example.
# @noargs
function _demo_number_lines {
  local script=$'#!/usr/bin/env bash\nset -euo pipefail\nprintf "hello\\n"'
  dybatpho::header "NUMBER LINES"
  dybatpho::text_number_lines "${script}"
  # Quote a fragment of a longer file with its real line numbers.
  dybatpho::text_number_lines $'local name\nname="world"' 41 " | "
}

# @description Run the `TRUNCATE LINES` section of this example.
# @noargs
function _demo_truncate_lines {
  local log=$'step 1 ok\nstep 2 ok\nstep 3 ok\nstep 4 ok\nstep 5 ok'
  dybatpho::header "TRUNCATE LINES"
  dybatpho::text_truncate_lines "${log}" 2
  printf '%s\n' "${log}" | dybatpho::text_truncate_lines - 3 "(+{count} steps hidden)"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_indent
  _demo_dedent
  _demo_strip_ansi
  _demo_bullets
  _demo_columns
  _demo_box
  _demo_center
  _demo_number_lines
  _demo_truncate_lines
  dybatpho::success "Text operations demo complete"
}

_main "$@"
