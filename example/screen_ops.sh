#!/usr/bin/env bash
# @file screen_ops.sh
# @brief Example showing the full-screen widgets and the layout solver
# @description
#   Builds one frame of a process dashboard -- a theme, tabs, a two-column
#   split, a focused panel, a scrolling list, rows of differently styled spans,
#   a coloured log line, a gauge, a sparkline, a scrollbar, a key bar and a
#   popup -- and prints it as text instead of taking over the terminal.
#
#   `dybatpho::screen_begin` is deliberately not called here, because an
#   example has to run unattended: it would need a terminal, put it in raw
#   mode, and wait for a keystroke that never comes. Everything up to the
#   flush is the same code a real application runs, so this exercises the
#   layout and every widget without needing a terminal at all. The loop such
#   an application wraps around this is in the module documentation.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules screen

dybatpho::register_common_handlers

# Every widget takes the *name* of an array and binds a nameref to it, so the
# arrays below are read even though nothing in this function expands them.
# shellcheck disable=SC2034
# @description Run every section of this example, in order.
# @noargs
function _main {
  # Size the buffer from these rather than from a terminal, which is what makes
  # the output below identical wherever it runs.
  export COLUMNS=78 LINES=22
  dybatpho::screen_size || true
  dybatpho::screen_clear

  # One call styles every widget below; under NO_COLOR it falls back to mono.
  dybatpho::screen_theme catppuccin-macchiato

  local -a pods=(api-7f9 worker-2ab scheduler-91c cache-44d gateway-0ff)
  local -a tabs=(Overview Logs Settings)
  local -a rows=("api-7f9|Running|3" "worker-2ab|Idle|1" "scheduler-91c|Running|2")
  local -a load=(3 7 2 9 4 8 6 9 5 7)
  local -a usage=(64 38 12)
  local -a names=(cpu mem net)
  local selected=1

  local -a frame=() columns=() detail=()
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" \
    length:1 fill:1 length:3 length:1 length:1 length:1

  dybatpho::screen_tabs "${frame[0]}" tabs active:0

  # A 40/60 split: the list on the left, everything about the selection on the
  # right.
  dybatpho::screen_layout columns horizontal "${frame[1]}" percent:40 fill:1

  # The panel that takes the keys is the focused one.
  dybatpho::screen_block "${columns[0]}" title:"Pods" border:rounded focus:true
  # shellcheck disable=SC2154 # set by the option spec of this script
  local list_area="${DYBATPHO_SCREEN_INNER}"
  local -a list_parts=()
  dybatpho::screen_layout list_parts horizontal "${list_area}" fill:1 length:1
  dybatpho::screen_list "${list_parts[0]}" pods selected:"${selected}"
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::screen_scrollbar "${list_parts[1]}" "${DYBATPHO_SCREEN_OFFSET}" "${#pods[@]}"

  dybatpho::screen_block "${columns[1]}" title:"Detail"
  dybatpho::screen_layout detail vertical "${DYBATPHO_SCREEN_INNER}" \
    length:4 length:3 fill:1
  dybatpho::screen_table "${detail[0]}" rows header:"NAME|STATE|N" \
    selected:"${selected}"
  dybatpho::screen_barchart "${detail[1]}" usage labels:names max:100
  dybatpho::screen_chart "${detail[2]}" load style:"32"

  dybatpho::screen_block "${frame[2]}" title:"Load"
  dybatpho::screen_sparkline "${DYBATPHO_SCREEN_INNER}" load

  dybatpho::screen_gauge "${frame[3]}" "$((selected + 1))" "${#pods[@]}" \
    label:"pod $((selected + 1))/${#pods[@]}"

  # A line of program output keeps the colours it was written with, and a row
  # of spans styles each piece apart -- here a status, a name and a duration.
  local x y width
  read -r x y width _ <<< "${frame[4]}"
  dybatpho::screen_ansi "${y}" "${x}" "$((width / 2))" $'\033[1;32mReady\033[0m 5 pods scheduled'
  # shellcheck disable=SC2154 # declared by `src/screen.sh`, loaded above
  dybatpho::screen_spans "${y}" "$((x + width / 2))" "$((width - width / 2))" "" \
    "✔ " "${DYBATPHO_SCREEN_STYLE_OK}" "${pods[selected]}" "${DYBATPHO_SCREEN_STYLE_ACCENT}" \
    " 12s" "${DYBATPHO_SCREEN_STYLE_DIM}"

  dybatpho::screen_keybar "${frame[5]}" "↑↓" "move" "enter" "restart" "q" "quit"

  # A popup is drawn last and erases what it covers, so the frame underneath
  # never has to know about it.
  local popup
  dybatpho::screen_rect_center popup "${DYBATPHO_SCREEN_RECT}" 34 5
  dybatpho::screen_popup "${popup}" title:"Confirm" border:double
  dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" \
    "Restart ${pods[selected]}?" align:center

  # Print the buffer instead of flushing it to a terminal.
  local row rendered
  # shellcheck disable=SC2154 # set by the option spec of this script
  for ((row = 0; row < DYBATPHO_SCREEN_HEIGHT; row++)); do
    __dybatpho_screen_render_into rendered "${row}"
    printf '%s\n' "${rendered}"
  done

  local columns_used
  dybatpho::screen_width columns_used "漢字ab"
  dybatpho::info "A wide glyph is measured in columns, not characters: 漢字ab is ${columns_used}"
  dybatpho::success "Screen operations demo complete"
}

_main "$@"
