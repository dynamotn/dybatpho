# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it keeps its declarations with the functions they
# describe.
# dyshellint disable=BSG050,BSG011,BSG033
# @file screen.sh
# @brief Full-screen terminal applications: layout, widgets, and an event loop
# @namespace dybatpho
# @description
#   `tui.sh` draws widgets beside a script's ordinary output. This module takes
#   the whole terminal instead: it switches to the alternate screen, puts the
#   terminal in raw mode, splits the area into rectangles with a constraint
#   solver, draws widgets into them, and hands keystrokes, mouse clicks, and
#   resizes back one event at a time. It is the `ratatui` shape, in Bash.
#
#   ## Why rows and not cells
#
#   `ratatui` keeps a buffer of cells, diffs it against the previous frame, and
#   writes the cells that changed. Measured in Bash that model costs about 50
#   microseconds per cell, which is 0.5 seconds for one frame of a 200x50
#   terminal -- the per-cell loop itself is the cost, so a smarter diff does not
#   rescue it. This module keeps a buffer of rows instead: a row is one string,
#   painted with Bash's own string operations, and the diff compares rows. The
#   same 200x50 frame then costs about 6 milliseconds, which is the difference
#   between an unusable and a comfortable frame rate.
#
#   Styles are kept beside each row as a list of runs (`column`, `SGR`) rather
#   than one entry per cell, so painting and rendering both cost what the
#   drawing actually contains instead of what the screen could hold.
#
#   ## Drawing a frame
#
#   Every frame follows the same three steps: clear the buffer, draw into it,
#   flush it. Widgets never write to the terminal themselves, so the order they
#   are called in only decides what covers what.
#
#   ```sh
#   dybatpho::screen_begin
#   while true; do
#     dybatpho::screen_clear
#     dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" length:3 fill:1
#     dybatpho::screen_block "${rows[0]}" title:"Status"
#     dybatpho::screen_list "${rows[1]}" items selected:"${cursor}"
#     dybatpho::screen_flush
#     dybatpho::screen_event key
#     case "${key}" in
#       char:q | escape) break ;;
#       down) cursor=$((cursor + 1)) ;;
#     esac
#   done
#   dybatpho::screen_end
#   ```
#
#   ## Rectangles
#
#   A rectangle is the string `x y width height`, with `x` and `y` zero-based.
#   `DYBATPHO_SCREEN_RECT` always holds the whole terminal, and
#   `dybatpho::screen_layout` splits any rectangle into more of them.
#
# @tip Everything is drawn on `/dev/tty` rather than on stdout, so an application can still print a result that a caller
#   captures
# @tip Character widths come from the Unicode tables built into the core `logging` module, so CJK text and emoji line
#   up without calling out to another program
# @see
#   - `example/screen_ops.sh`
#   - `src/tui.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_SCREEN_MOUSE bool Report mouse clicks as events. Default `true`
DYBATPHO_SCREEN_MOUSE="${DYBATPHO_SCREEN_MOUSE:-true}"
export DYBATPHO_SCREEN_MOUSE
# @env DYBATPHO_SCREEN_POINTER string Marker drawn beside the selected list or table row. Default `❯`
DYBATPHO_SCREEN_POINTER="${DYBATPHO_SCREEN_POINTER:-❯}"
export DYBATPHO_SCREEN_POINTER
# @env DYBATPHO_SCREEN_STYLE_SELECTED string SGR parameters for a selected row. Default `1;7`
DYBATPHO_SCREEN_STYLE_SELECTED="${DYBATPHO_SCREEN_STYLE_SELECTED:-1;7}"
export DYBATPHO_SCREEN_STYLE_SELECTED
# @env DYBATPHO_SCREEN_STYLE_BORDER string SGR parameters for a block border. Default `2`
DYBATPHO_SCREEN_STYLE_BORDER="${DYBATPHO_SCREEN_STYLE_BORDER:-2}"
export DYBATPHO_SCREEN_STYLE_BORDER
# @env DYBATPHO_SCREEN_STYLE_TITLE string SGR parameters for a block title. Default `1`
DYBATPHO_SCREEN_STYLE_TITLE="${DYBATPHO_SCREEN_STYLE_TITLE:-1}"
export DYBATPHO_SCREEN_STYLE_TITLE
# @env DYBATPHO_SCREEN_STYLE_FOCUS string SGR parameters for the border of a block drawn with `focus:true`. Default `1`
DYBATPHO_SCREEN_STYLE_FOCUS="${DYBATPHO_SCREEN_STYLE_FOCUS:-1}"
export DYBATPHO_SCREEN_STYLE_FOCUS
# @env DYBATPHO_SCREEN_STYLE_TAB_ACTIVE string SGR parameters for the active tab. Default `1;7`
DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="${DYBATPHO_SCREEN_STYLE_TAB_ACTIVE:-1;7}"
export DYBATPHO_SCREEN_STYLE_TAB_ACTIVE
# @env DYBATPHO_SCREEN_STYLE_KEYBAR string SGR parameters for the background of a key bar. Default `7`
DYBATPHO_SCREEN_STYLE_KEYBAR="${DYBATPHO_SCREEN_STYLE_KEYBAR:-7}"
export DYBATPHO_SCREEN_STYLE_KEYBAR
# @env DYBATPHO_SCREEN_STYLE_KEY string SGR parameters for a key named in a key bar. Default `1`
DYBATPHO_SCREEN_STYLE_KEY="${DYBATPHO_SCREEN_STYLE_KEY:-1}"
export DYBATPHO_SCREEN_STYLE_KEY
# @env DYBATPHO_SCREEN_STYLE_ACCENT string SGR parameters an application uses for what should stand out. Default `1`
DYBATPHO_SCREEN_STYLE_ACCENT="${DYBATPHO_SCREEN_STYLE_ACCENT:-1}"
export DYBATPHO_SCREEN_STYLE_ACCENT
# @env DYBATPHO_SCREEN_STYLE_DIM string SGR parameters for secondary text, and for the divider between tabs. Default `2`
DYBATPHO_SCREEN_STYLE_DIM="${DYBATPHO_SCREEN_STYLE_DIM:-2}"
export DYBATPHO_SCREEN_STYLE_DIM
# @env DYBATPHO_SCREEN_STYLE_OK string SGR parameters for success. Default `32`
DYBATPHO_SCREEN_STYLE_OK="${DYBATPHO_SCREEN_STYLE_OK:-32}"
export DYBATPHO_SCREEN_STYLE_OK
# @env DYBATPHO_SCREEN_STYLE_WARN string SGR parameters for a warning. Default `33`
DYBATPHO_SCREEN_STYLE_WARN="${DYBATPHO_SCREEN_STYLE_WARN:-33}"
export DYBATPHO_SCREEN_STYLE_WARN
# @env DYBATPHO_SCREEN_STYLE_ERROR string SGR parameters for an error. Default `31`
DYBATPHO_SCREEN_STYLE_ERROR="${DYBATPHO_SCREEN_STYLE_ERROR:-31}"
export DYBATPHO_SCREEN_STYLE_ERROR

# The state below is written for the application to read: the rectangle a block
# left inside itself, the offset a list scrolled to, where a mouse event landed.
# Nothing in this module reads them back, so they are exported rather than
# merely assigned -- which is also what stops a static check reading a variable
# only ever written as one that is never used.
# @env DYBATPHO_SCREEN_WIDTH number Columns of the terminal the buffer is sized for
DYBATPHO_SCREEN_WIDTH=0
# @env DYBATPHO_SCREEN_HEIGHT number Rows of the terminal the buffer is sized for
DYBATPHO_SCREEN_HEIGHT=0
# @env DYBATPHO_SCREEN_RECT string The whole terminal as a rectangle, `x y width height`
DYBATPHO_SCREEN_RECT="0 0 0 0"
# @env DYBATPHO_SCREEN_ACTIVE bool `true` between `dybatpho::screen_begin` and `dybatpho::screen_end`
DYBATPHO_SCREEN_ACTIVE=false
# @env DYBATPHO_SCREEN_MOUSE_COLUMN number Zero-based column of the last mouse event
DYBATPHO_SCREEN_MOUSE_COLUMN=0
# @env DYBATPHO_SCREEN_MOUSE_ROW number Zero-based row of the last mouse event
DYBATPHO_SCREEN_MOUSE_ROW=0
# @env DYBATPHO_SCREEN_INNER string Rectangle left inside the last block or popup
DYBATPHO_SCREEN_INNER="0 0 0 0"
# @env DYBATPHO_SCREEN_OFFSET number Index of the first item the last list or table drew, after it scrolled to keep the
#   selection visible
DYBATPHO_SCREEN_OFFSET=0
export DYBATPHO_SCREEN_WIDTH DYBATPHO_SCREEN_HEIGHT DYBATPHO_SCREEN_RECT
export DYBATPHO_SCREEN_ACTIVE DYBATPHO_SCREEN_INNER DYBATPHO_SCREEN_OFFSET
export DYBATPHO_SCREEN_MOUSE_COLUMN DYBATPHO_SCREEN_MOUSE_ROW

# Plain text of each row, padded to exactly `DYBATPHO_SCREEN_WIDTH` columns.
declare -ga __dybatpho_screen_text=()
# Style runs of each row, as `column<US>sgr` entries joined by `<RS>`, sorted by
# column. A run reaches to the column the next run starts at.
declare -ga __dybatpho_screen_style=()
# `1` while every character on a row spans exactly one column and one string
# index, which is the case where a display column is also an index and nothing
# has to be measured to find it. Box-drawing characters and accented Latin keep
# a row on this path in a UTF-8 locale; a wide glyph such as `世` is what takes
# a row off it, and only that row.
declare -ga __dybatpho_screen_plain=()
# The escape sequence last written for each row, so a frame only sends rows that
# actually changed.
declare -ga __dybatpho_screen_front=()
# The text and style runs each row was last rendered from. Identical content
# renders to an identical sequence, so comparing this is a way of deciding that
# a row does not need rendering at all -- which is the common case, because a
# keystroke in a real application changes a couple of rows and leaves the rest
# of the screen exactly as it was.
declare -ga __dybatpho_screen_key=()
# The column the last run on each row starts at, and the style in force from it
# to the end of the row. Widgets paint left to right, so a new run almost always
# belongs after every run already there, and these two turn that case into an
# append instead of a rebuild of the whole list.
declare -ga __dybatpho_screen_last_column=()
declare -ga __dybatpho_screen_last_style=()
# Where the last span inserted between existing runs ended up: the length of the
# run list up to and including it, its column, and its style. Everything before
# that point is known to start left of the column, so the next span painted
# further right on the same row copies it as it is instead of reading it again.
declare -ga __dybatpho_screen_hint_offset=()
declare -ga __dybatpho_screen_hint_column=()
declare -ga __dybatpho_screen_hint_style=()
# Terminal state captured by `dybatpho::screen_begin` and restored by
# `dybatpho::screen_end`.
__dybatpho_screen_saved_stty=""
__dybatpho_screen_fd=""
__dybatpho_screen_resized=false
__dybatpho_screen_trapped=false

readonly __DYBATPHO_SCREEN_US=$'\x1f'
readonly __DYBATPHO_SCREEN_RS=$'\x1e'

#######################################
# @description Validate a whole number, or end the script naming what was wrong.
# @arg $1 string Name of the caller, used in the message
# @arg $2 string Description of the value, used in the message
# @arg $3 string Value to check
# @arg $4 number Smallest value accepted
# @internal
#######################################
function __dybatpho_screen_expect_int {
  [[ "${3-}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "$1: $2 must be a whole number, got '${3-}'"
  (($3 >= $4)) \
    || dybatpho::die "$1: $2 must be at least $4, got '$3'"
}

#######################################
# @description Return the number of terminal columns a string occupies.
#
#   Text that is nothing but ASCII is its own length, which is the
#   overwhelmingly common case and is answered without looking at a single
#   character. Anything else is measured against the Unicode tables built into
#   the core `logging` module, the same measure `text`, `table` and the boxed
#   log helpers use, so a screen and a log line never disagree about a glyph.
# @example
#   local columns
#   dybatpho::screen_width columns "漢字ab"   # 6
#
# @arg $1 string Name of the variable receiving the width
# @arg $2 string Text to measure
# @set The named variable
# @exitcode 0 Always
#######################################
function dybatpho::screen_width {
  dybatpho::expect_ref "$1"
  __dybatpho_log_width_into "$1" "${2-}"
}

#######################################
# @description Cut a string down to a number of columns, never splitting a
#   character in half and never leaving half of a double-width glyph behind.
# @arg $1 string Name of the variable receiving the text
# @arg $2 string Text to cut
# @arg $3 number Columns available
# @set The named variable
# @internal
#######################################
function __dybatpho_screen_truncate_into {
  local -n __dybatpho_screen_t_out="$1"
  local __dybatpho_screen_t_text="$2" __dybatpho_screen_t_limit="$3"

  if ((__dybatpho_screen_t_limit <= 0)); then
    __dybatpho_screen_t_out=""
    return 0
  fi

  if __dybatpho_log_is_ascii "${__dybatpho_screen_t_text}"; then
    __dybatpho_screen_t_out="${__dybatpho_screen_t_text:0:__dybatpho_screen_t_limit}"
    return 0
  fi

  local -a __dybatpho_screen_t_chars=()
  local __dybatpho_screen_t_char __dybatpho_screen_t_each __dybatpho_screen_t_used=0
  __dybatpho_log_chars_into __dybatpho_screen_t_chars "${__dybatpho_screen_t_text}"
  __dybatpho_screen_t_out=""
  for __dybatpho_screen_t_char in ${__dybatpho_screen_t_chars[@]+"${__dybatpho_screen_t_chars[@]}"}; do
    __dybatpho_log_char_width_into __dybatpho_screen_t_each "${__dybatpho_screen_t_char}"
    ((__dybatpho_screen_t_used + __dybatpho_screen_t_each > __dybatpho_screen_t_limit)) && break
    __dybatpho_screen_t_out+="${__dybatpho_screen_t_char}"
    __dybatpho_screen_t_used=$((__dybatpho_screen_t_used + __dybatpho_screen_t_each))
  done
  return 0
}

#######################################
# @description Return the string index that a display column falls at in a row.
#   A row of plain ASCII answers immediately; any other row is walked once.
# @arg $1 string Name of the variable receiving the index
# @arg $2 number Row
# @arg $3 number Display column
# @set The named variable
# @internal
#######################################
function __dybatpho_screen_index_into {
  local -n __dybatpho_screen_i_out="$1"
  local __dybatpho_screen_i_row="$2" __dybatpho_screen_i_column="$3"

  if ((__dybatpho_screen_plain[__dybatpho_screen_i_row])); then
    __dybatpho_screen_i_out="${__dybatpho_screen_i_column}"
    return 0
  fi

  local -a __dybatpho_screen_i_chars=()
  local __dybatpho_screen_i_char __dybatpho_screen_i_each
  local __dybatpho_screen_i_used=0 __dybatpho_screen_i_index=0
  __dybatpho_log_chars_into __dybatpho_screen_i_chars "${__dybatpho_screen_text[__dybatpho_screen_i_row]}"
  for __dybatpho_screen_i_char in ${__dybatpho_screen_i_chars[@]+"${__dybatpho_screen_i_chars[@]}"}; do
    ((__dybatpho_screen_i_used >= __dybatpho_screen_i_column)) && break
    __dybatpho_log_char_width_into __dybatpho_screen_i_each "${__dybatpho_screen_i_char}"
    __dybatpho_screen_i_used=$((__dybatpho_screen_i_used + __dybatpho_screen_i_each))
    __dybatpho_screen_i_index=$((__dybatpho_screen_i_index + ${#__dybatpho_screen_i_char}))
  done
  __dybatpho_screen_i_out="${__dybatpho_screen_i_index}"
  return 0
}

#######################################
# @description Replace a span of style runs on a row with one run, restoring
#   whatever style was in force at the far end.
#
#   Runs are kept instead of one style per cell because a row holds a handful of
#   runs and a few hundred cells: painting and rendering then cost what was
#   drawn rather than how wide the terminal is.
# @arg $1 number Row
# @arg $2 number First column covered
# @arg $3 number First column past the span
# @arg $4 string SGR parameters
# @internal
#######################################
function __dybatpho_screen_style_set {
  local row="$1" start="$2" end="$3" style="$4"
  local -a entries=()
  local entry column tail_style="0"

  # Nothing already on this row starts at or after the new span, so the span
  # belongs on the end and the style it interrupts is the one running to the
  # end of the row. Appending is all that is needed, and this is the path a
  # widget drawing left to right takes every time.
  if ((start >= __dybatpho_screen_last_column[row])); then
    tail_style="${__dybatpho_screen_last_style[row]}"
    __dybatpho_screen_style[row]+="${start}${__DYBATPHO_SCREEN_US}${style}${__DYBATPHO_SCREEN_RS}"
    if ((end < DYBATPHO_SCREEN_WIDTH)); then
      __dybatpho_screen_style[row]+="${end}${__DYBATPHO_SCREEN_US}${tail_style}${__DYBATPHO_SCREEN_RS}"
      __dybatpho_screen_last_column[row]="${end}"
    else
      __dybatpho_screen_last_column[row]="${start}"
      __dybatpho_screen_last_style[row]="${style}"
    fi
    return 0
  fi

  # Anything drawn inside a bordered panel lands here, because the right border
  # is already on the row, so this is paid for most cells of a real frame. Two
  # things keep it cheap. A widget paints left to right, so when the new span
  # starts after the one inserted last, the runs up to that one are reused as
  # they are and only the few to the right of it are read. Those are split in
  # one expansion -- they hold only digits, `;` and the unit separator, so there
  # is nothing to glob -- and rebuilt in a single pass. Reading every run of the
  # row one at a time, filtering them twice and joining them again cost a held
  # arrow key most of a second per frame.
  local rest="${__dybatpho_screen_style[row]}" joined=""
  local last_column=0 last_style="0" placed=false
  if ((start > ${__dybatpho_screen_hint_column[row]:--1})); then
    local offset="${__dybatpho_screen_hint_offset[row]:-0}"
    joined="${rest:0:offset}"
    rest="${rest:offset}"
    tail_style="${__dybatpho_screen_hint_style[row]:-0}"
  fi
  local IFS="${__DYBATPHO_SCREEN_RS}"
  # shellcheck disable=SC2206 # split on the record separator on purpose
  entries=(${rest})
  for entry in ${entries[@]+"${entries[@]}"}; do
    [[ -n "${entry}" ]] || continue
    column="${entry%%"${__DYBATPHO_SCREEN_US}"*}"
    if ((column < start)); then
      tail_style="${entry#*"${__DYBATPHO_SCREEN_US}"}"
      joined+="${entry}${__DYBATPHO_SCREEN_RS}"
      last_column="${column}" last_style="${tail_style}"
      continue
    fi
    if ((column <= end)); then
      # Covered by the new span; only the style it leaves in force survives.
      tail_style="${entry#*"${__DYBATPHO_SCREEN_US}"}"
      continue
    fi
    if [[ "${placed}" == false ]]; then
      joined+="${start}${__DYBATPHO_SCREEN_US}${style}${__DYBATPHO_SCREEN_RS}"
      __dybatpho_screen_hint_offset[row]="${#joined}"
      ((end < DYBATPHO_SCREEN_WIDTH)) \
        && joined+="${end}${__DYBATPHO_SCREEN_US}${tail_style}${__DYBATPHO_SCREEN_RS}"
      placed=true
    fi
    joined+="${entry}${__DYBATPHO_SCREEN_RS}"
    last_column="${column}" last_style="${entry#*"${__DYBATPHO_SCREEN_US}"}"
  done
  if [[ "${placed}" == false ]]; then
    joined+="${start}${__DYBATPHO_SCREEN_US}${style}${__DYBATPHO_SCREEN_RS}"
    __dybatpho_screen_hint_offset[row]="${#joined}"
    last_column="${start}" last_style="${style}"
    if ((end < DYBATPHO_SCREEN_WIDTH)); then
      joined+="${end}${__DYBATPHO_SCREEN_US}${tail_style}${__DYBATPHO_SCREEN_RS}"
      last_column="${end}" last_style="${tail_style}"
    fi
  fi
  __dybatpho_screen_style[row]="${joined}"
  __dybatpho_screen_last_column[row]="${last_column}"
  __dybatpho_screen_last_style[row]="${last_style}"
  __dybatpho_screen_hint_column[row]="${start}"
  __dybatpho_screen_hint_style[row]="${style}"
  return 0
}

#######################################
# @description Draw text into the buffer at one position, clipped to the screen.
#   Nothing reaches the terminal until `dybatpho::screen_flush` runs.
# @example
#   dybatpho::screen_put 2 4 "Ready" "1;32"
#
# @arg $1 number Row, zero-based
# @arg $2 number Column, zero-based
# @arg $3 string Text to draw, without escape sequences
# @arg $4 string Optional SGR parameters, default is `0`
# @exitcode 0 Always, including when the position is off screen
# @tip Pass the text without escape sequences and give the style separately; a style passed inside the text would break
#   the
#   column arithmetic
#######################################
function dybatpho::screen_put {
  local row="${1:-0}" column="${2:-0}" text="${3-}" style="${4:-0}"
  ((row >= 0 && row < DYBATPHO_SCREEN_HEIGHT)) || return 0
  ((column < DYBATPHO_SCREEN_WIDTH)) || return 0
  [[ -n "${text}" ]] || return 0

  local skip=0
  if ((column < 0)); then
    skip=$((-column))
    column=0
  fi
  if ((skip > 0)); then
    local dropped
    __dybatpho_screen_truncate_into dropped "${text}" "${skip}"
    text="${text:${#dropped}}"
  fi

  local available=$((DYBATPHO_SCREEN_WIDTH - column))
  local drawn="${text}" width
  # Measuring first means the common case -- text that fits -- never walks the
  # string a second time to cut it.
  __dybatpho_log_width_into width "${drawn}"
  if ((width > available)); then
    __dybatpho_screen_truncate_into drawn "${drawn}" "${available}"
    __dybatpho_log_width_into width "${drawn}"
  fi
  [[ -n "${drawn}" ]] || return 0
  ((width > 0)) || return 0

  # The indices are resolved against the row as it stands, so the flag is
  # updated only once the new text is in place.
  local start_index end_index
  if ((__dybatpho_screen_plain[row])); then
    start_index="${column}"
    end_index=$((column + width))
  else
    __dybatpho_screen_index_into start_index "${row}" "${column}"
    __dybatpho_screen_index_into end_index "${row}" "$((column + width))"
  fi
  local head="${__dybatpho_screen_text[row]:0:start_index}"
  local tail="${__dybatpho_screen_text[row]:end_index}"
  __dybatpho_screen_text[row]="${head}${drawn}${tail}"

  # A row keeps the fast column-to-index path as long as every character it
  # holds spans one column and one index. Comparing the two counts says exactly
  # that, and it keeps box-drawing borders on the fast path, where testing for
  # ASCII instead dropped every bordered row onto the slow one -- which is what
  # made a frame cost most of a second.
  ((width == ${#drawn})) || __dybatpho_screen_plain[row]=0

  __dybatpho_screen_style_set "${row}" "${column}" "$((column + width))" "${style}"
  return 0
}

#######################################
# @description Build the escape sequence for one row from its text and runs.
# @arg $1 string Name of the variable receiving the sequence
# @arg $2 number Row
# @set The named variable
# @internal
#######################################
function __dybatpho_screen_render_into {
  local -n __dybatpho_screen_r_out="$1"
  local __dybatpho_screen_r_row="$2"
  local -a __dybatpho_screen_r_entries=()
  local __dybatpho_screen_r_entry __dybatpho_screen_r_rest
  local __dybatpho_screen_r_column __dybatpho_screen_r_style
  local __dybatpho_screen_r_previous=0 __dybatpho_screen_r_previous_style="0"
  local __dybatpho_screen_r_start __dybatpho_screen_r_stop

  __dybatpho_screen_r_rest="${__dybatpho_screen_style[__dybatpho_screen_r_row]}"
  while [[ -n "${__dybatpho_screen_r_rest}" ]]; do
    __dybatpho_screen_r_entry="${__dybatpho_screen_r_rest%%"${__DYBATPHO_SCREEN_RS}"*}"
    if [[ "${__dybatpho_screen_r_entry}" == "${__dybatpho_screen_r_rest}" ]]; then
      __dybatpho_screen_r_rest=""
    else
      __dybatpho_screen_r_rest="${__dybatpho_screen_r_rest#*"${__DYBATPHO_SCREEN_RS}"}"
    fi
    [[ -n "${__dybatpho_screen_r_entry}" ]] && __dybatpho_screen_r_entries+=("${__dybatpho_screen_r_entry}")
  done

  __dybatpho_screen_r_out=""
  if ((${#__dybatpho_screen_r_entries[@]} == 0)); then
    __dybatpho_screen_r_out="${__dybatpho_screen_text[__dybatpho_screen_r_row]}"
    return 0
  fi

  # The runs are already in column order: `__dybatpho_screen_style_set` rebuilds
  # the list as the runs before the span, the span, and the runs after it, which
  # keeps the order it was given. Sorting here instead would cost a `sort`
  # process per row per frame -- fifty forks a frame, which is far more than the
  # whole rest of the renderer.
  # On a row where every character is one column wide the index is the column,
  # so the lookup is skipped entirely. It was two function calls per run per
  # row per frame, and at 35 microseconds each that was most of the cost of
  # drawing a frame.
  local __dybatpho_screen_r_plain="${__dybatpho_screen_plain[__dybatpho_screen_r_row]}"
  for __dybatpho_screen_r_entry in "${__dybatpho_screen_r_entries[@]}"; do
    __dybatpho_screen_r_column="${__dybatpho_screen_r_entry%%"${__DYBATPHO_SCREEN_US}"*}"
    __dybatpho_screen_r_style="${__dybatpho_screen_r_entry#*"${__DYBATPHO_SCREEN_US}"}"
    if ((__dybatpho_screen_r_column > __dybatpho_screen_r_previous)); then
      if ((__dybatpho_screen_r_plain)); then
        __dybatpho_screen_r_start="${__dybatpho_screen_r_previous}"
        __dybatpho_screen_r_stop="${__dybatpho_screen_r_column}"
      else
        __dybatpho_screen_index_into __dybatpho_screen_r_start "${__dybatpho_screen_r_row}" \
          "${__dybatpho_screen_r_previous}"
        __dybatpho_screen_index_into __dybatpho_screen_r_stop "${__dybatpho_screen_r_row}" \
          "${__dybatpho_screen_r_column}"
      fi
      __dybatpho_screen_r_out+=$'\033'"[${__dybatpho_screen_r_previous_style}m"
      local __dybatpho_screen_r_width=$((__dybatpho_screen_r_stop - __dybatpho_screen_r_start))
      local __dybatpho_screen_r_line="${__dybatpho_screen_text[__dybatpho_screen_r_row]}"
      __dybatpho_screen_r_out+="${__dybatpho_screen_r_line:__dybatpho_screen_r_start:__dybatpho_screen_r_width}"
    fi
    __dybatpho_screen_r_previous="${__dybatpho_screen_r_column}"
    __dybatpho_screen_r_previous_style="${__dybatpho_screen_r_style}"
  done

  if ((__dybatpho_screen_r_plain)); then
    __dybatpho_screen_r_start="${__dybatpho_screen_r_previous}"
  else
    __dybatpho_screen_index_into __dybatpho_screen_r_start "${__dybatpho_screen_r_row}" \
      "${__dybatpho_screen_r_previous}"
  fi
  __dybatpho_screen_r_out+=$'\033'"[${__dybatpho_screen_r_previous_style}m"
  __dybatpho_screen_r_out+="${__dybatpho_screen_text[__dybatpho_screen_r_row]:__dybatpho_screen_r_start}"
  __dybatpho_screen_r_out+=$'\033[0m'
  return 0
}

#######################################
# @description Reset the buffer to blank, which is where every frame starts.
# @noargs
# @exitcode 0 Always
# @tip The front buffer is deliberately left alone, so a cleared frame still only sends the rows that actually changed
#######################################
function dybatpho::screen_clear {
  local row blank
  printf -v blank '%*s' "${DYBATPHO_SCREEN_WIDTH}" ''
  for ((row = 0; row < DYBATPHO_SCREEN_HEIGHT; row++)); do
    __dybatpho_screen_text[row]="${blank}"
    __dybatpho_screen_style[row]=""
    __dybatpho_screen_plain[row]=1
    __dybatpho_screen_last_column[row]=0
    __dybatpho_screen_last_style[row]="0"
    __dybatpho_screen_hint_offset[row]=0
    __dybatpho_screen_hint_column[row]=-1
    __dybatpho_screen_hint_style[row]="0"
  done
  return 0
}

#######################################
# @description Resize the buffer to the terminal, and report whether it changed.
# @noargs
# @set DYBATPHO_SCREEN_WIDTH number Columns the buffer now holds
# @set DYBATPHO_SCREEN_HEIGHT number Rows the buffer now holds
# @set DYBATPHO_SCREEN_RECT string The whole terminal as a rectangle
# @exitcode 0 The size changed and the buffer was rebuilt
# @exitcode 1 The size is unchanged
#######################################
function dybatpho::screen_size {
  local width height
  width="$(dybatpho::terminal_width 80)"
  height="$(dybatpho::terminal_height 24)"
  if ((width == DYBATPHO_SCREEN_WIDTH && height == DYBATPHO_SCREEN_HEIGHT)); then
    return 1
  fi

  DYBATPHO_SCREEN_WIDTH="${width}"
  DYBATPHO_SCREEN_HEIGHT="${height}"
  DYBATPHO_SCREEN_RECT="0 0 ${width} ${height}"
  __dybatpho_screen_text=()
  __dybatpho_screen_style=()
  __dybatpho_screen_plain=()
  __dybatpho_screen_last_column=()
  __dybatpho_screen_last_style=()
  __dybatpho_screen_hint_offset=()
  __dybatpho_screen_hint_column=()
  __dybatpho_screen_hint_style=()
  # Every row is now of a different width, so nothing already on the terminal
  # can be reused: the front buffer is dropped rather than compared against.
  __dybatpho_screen_front=()
  __dybatpho_screen_key=()
  local row
  for ((row = 0; row < height; row++)); do
    __dybatpho_screen_front[row]=$'\x00'
    __dybatpho_screen_key[row]=$'\x00'
  done
  dybatpho::screen_clear
  return 0
}

#######################################
# @description Write the rows that changed since the last frame to the terminal.
# @noargs
# @stderr Nothing; the frame goes to the terminal directly
# @exitcode 0 Always
# @tip A frame costs what changed: redrawing a screen where one list row moved sends one or two rows, not the whole
#   screen
#######################################
function dybatpho::screen_flush {
  local row rendered key out=""
  for ((row = 0; row < DYBATPHO_SCREEN_HEIGHT; row++)); do
    # Rendering a row costs far more than comparing what it would be rendered
    # from, so a row whose text and runs are untouched is skipped before any of
    # that work happens.
    key="${__dybatpho_screen_text[row]}${__DYBATPHO_SCREEN_RS}${__dybatpho_screen_style[row]}"
    [[ "${key}" == "${__dybatpho_screen_key[row]-}" ]] && continue
    __dybatpho_screen_key[row]="${key}"
    __dybatpho_screen_render_into rendered "${row}"
    [[ "${rendered}" == "${__dybatpho_screen_front[row]-}" ]] && continue
    __dybatpho_screen_front[row]="${rendered}"
    out+=$'\033'"[$((row + 1));1H"$'\033[K'"${rendered}"
  done
  [[ -n "${out}" ]] || return 0
  if [[ -n "${__dybatpho_screen_fd}" ]]; then
    printf '%s' "${out}" 1>&"${__dybatpho_screen_fd}"
  else
    printf '%s' "${out}" >&2
  fi
  return 0
}

#######################################
# @description Build a rectangle from its parts.
# @example
#   local box
#   dybatpho::screen_rect box 0 0 40 10
#
# @arg $1 string Name of the variable receiving the rectangle
# @arg $2 number Column of the left edge, zero-based
# @arg $3 number Row of the top edge, zero-based
# @arg $4 number Width in columns
# @arg $5 number Height in rows
# @set The named variable to `x y width height`
#######################################
function dybatpho::screen_rect {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_screen_rect_out="$1"
  __dybatpho_screen_rect_out="${2:-0} ${3:-0} ${4:-0} ${5:-0}"
  return 0
}

#######################################
# @description Split a rectangle into parts that satisfy a list of constraints.
#
#   The constraints are the ones `ratatui` uses, and they are resolved in the
#   same order of authority: the fixed sizes are taken out first, what is left
#   is shared between the flexible ones, and the last part absorbs the rounding
#   so the pieces always add up to the whole.
#
#   | Constraint | Meaning |
#   | --- | --- |
#   | `length:N` | exactly `N` |
#   | `percent:N` | `N` percent of the rectangle |
#   | `ratio:A/B` | the fraction `A/B` of the rectangle |
#   | `min:N` | at least `N`, and grows into what is left |
#   | `max:N` | at most `N`, and grows into what is left |
#   | `fill:W` | no size of its own; shares what is left by weight `W` |
#
# @example
#   local -a rows=()
#   dybatpho::screen_layout rows vertical "${DYBATPHO_SCREEN_RECT}" \
#     length:3 fill:1 length:1
#   # rows[0] is a three-row header, rows[2] a one-row footer,
#   # rows[1] is everything in between
#
# @arg $1 string Name of the array variable receiving the rectangles
# @arg $2 string `vertical` to split the height, `horizontal` to split the width
# @arg $3 string Rectangle to split
# @arg $@ string One constraint per part
# @set The named array, one rectangle per constraint, in order
# @exitcode 1 The direction is unknown, or a constraint is malformed
# @tip A part can come out zero-sized when the rectangle is too small for its constraints; a widget drawn into it simply
#   draws nothing
#######################################
function dybatpho::screen_layout {
  local result_var direction rect
  dybatpho::expect_args result_var direction rect -- "$@"
  dybatpho::expect_ref "${result_var}"
  shift 3
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one constraint"

  local -n __dybatpho_screen_l_out="${result_var}"
  local x y width height
  read -r x y width height <<< "${rect}"

  local total
  case "${direction}" in
    vertical) total="${height}" ;;
    horizontal) total="${width}" ;;
    *) dybatpho::die "${FUNCNAME[0]}: Direction must be vertical or horizontal, got '${direction}'" ;;
  esac
  ((total > 0)) || total=0

  local -a sizes=() weights=() caps=()
  local constraint value fixed=0 flexible=0 index=0
  for constraint in "$@"; do
    value="${constraint#*:}"
    sizes[index]=0
    weights[index]=0
    caps[index]=-1
    case "${constraint}" in
      length:*)
        __dybatpho_screen_expect_int "${FUNCNAME[0]}" "A length" "${value}" 0
        sizes[index]="${value}"
        ;;
      percent:*)
        __dybatpho_screen_expect_int "${FUNCNAME[0]}" "A percentage" "${value}" 0
        sizes[index]=$((total * value / 100))
        ;;
      ratio:*)
        [[ "${value}" =~ ^([0-9]+)/([0-9]+)$ ]] \
          || dybatpho::die "${FUNCNAME[0]}: A ratio must be written A/B, got '${value}'"
        ((BASH_REMATCH[2] > 0)) \
          || dybatpho::die "${FUNCNAME[0]}: A ratio cannot be divided by zero"
        sizes[index]=$((total * BASH_REMATCH[1] / BASH_REMATCH[2]))
        ;;
      min:*)
        __dybatpho_screen_expect_int "${FUNCNAME[0]}" "A minimum" "${value}" 0
        sizes[index]="${value}"
        weights[index]=1
        ;;
      max:*)
        __dybatpho_screen_expect_int "${FUNCNAME[0]}" "A maximum" "${value}" 0
        weights[index]=1
        caps[index]="${value}"
        ;;
      fill:*)
        __dybatpho_screen_expect_int "${FUNCNAME[0]}" "A fill weight" "${value}" 0
        weights[index]="${value}"
        ;;
      *)
        dybatpho::die \
          "${FUNCNAME[0]}: Unknown constraint '${constraint}', expected length:, percent:, ratio:, min:, max: or fill:"
        ;;
    esac
    fixed=$((fixed + sizes[index]))
    flexible=$((flexible + weights[index]))
    index=$((index + 1))
  done

  local count="${index}" leftover=$((total - fixed))
  if ((leftover > 0 && flexible > 0)); then
    local share
    for ((index = 0; index < count; index++)); do
      ((weights[index] > 0)) || continue
      share=$((leftover * weights[index] / flexible))
      if ((caps[index] >= 0 && sizes[index] + share > caps[index])); then
        share=$((caps[index] - sizes[index]))
        ((share > 0)) || share=0
      fi
      sizes[index]=$((sizes[index] + share))
    done
  elif ((leftover < 0)); then
    # More was asked for than exists. Shrink from the end, which keeps the
    # first parts -- usually a header and the content -- at the size they asked
    # for rather than smearing the loss over everything.
    local deficit=$((-leftover))
    for ((index = count - 1; index >= 0 && deficit > 0; index--)); do
      if ((sizes[index] >= deficit)); then
        sizes[index]=$((sizes[index] - deficit))
        deficit=0
      else
        deficit=$((deficit - sizes[index]))
        sizes[index]=0
      fi
    done
  fi

  # Rounding loses a column or a row at a time; the last part that can take it
  # absorbs the difference so the pieces tile the rectangle exactly.
  local assigned=0
  for ((index = 0; index < count; index++)); do
    assigned=$((assigned + sizes[index]))
  done
  if ((assigned != total && count > 0)); then
    local correction=$((total - assigned))
    for ((index = count - 1; index >= 0; index--)); do
      if ((weights[index] > 0 || count == 1)); then
        sizes[index]=$((sizes[index] + correction))
        ((sizes[index] >= 0)) || sizes[index]=0
        break
      fi
    done
  fi

  __dybatpho_screen_l_out=()
  local offset=0
  for ((index = 0; index < count; index++)); do
    if [[ "${direction}" == vertical ]]; then
      __dybatpho_screen_l_out+=("${x} $((y + offset)) ${width} ${sizes[index]}")
    else
      __dybatpho_screen_l_out+=("$((x + offset)) ${y} ${sizes[index]} ${height}")
    fi
    offset=$((offset + sizes[index]))
  done
  return 0
}

#######################################
# @description Shrink a rectangle by a margin on every side.
# @example
#   local inner
#   dybatpho::screen_rect_inner inner "${box}" 1
#
# @arg $1 string Name of the variable receiving the rectangle
# @arg $2 string Rectangle to shrink
# @arg $3 number Optional margin in cells, default is `1`
# @set The named variable
#######################################
function dybatpho::screen_rect_inner {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_screen_in_out="$1"
  local margin="${3:-1}"
  local x y width height
  read -r x y width height <<< "${2-}"

  local inner_width=$((width - margin * 2))
  local inner_height=$((height - margin * 2))
  ((inner_width > 0)) || inner_width=0
  ((inner_height > 0)) || inner_height=0
  __dybatpho_screen_in_out="$((x + margin)) $((y + margin)) ${inner_width} ${inner_height}"
  return 0
}

#######################################
# @description Centre a rectangle of a given size inside another, which is what
#   a popup needs.
# @example
#   local popup
#   dybatpho::screen_rect_center popup "${DYBATPHO_SCREEN_RECT}" 40 10
#
# @arg $1 string Name of the variable receiving the rectangle
# @arg $2 string Rectangle to centre inside
# @arg $3 number Width of the centred rectangle
# @arg $4 number Height of the centred rectangle
# @set The named variable
#######################################
function dybatpho::screen_rect_center {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_screen_c_out="$1"
  local want_width="${3:-0}" want_height="${4:-0}"
  local x y width height
  read -r x y width height <<< "${2-}"

  ((want_width <= width)) || want_width="${width}"
  ((want_height <= height)) || want_height="${height}"
  __dybatpho_screen_c_out="$((x + (width - want_width) / 2)) $((y + (height - want_height) / 2))"
  __dybatpho_screen_c_out+=" ${want_width} ${want_height}"
  return 0
}

#######################################
# @description Note that the terminal changed size, so the next event reports it.
#######################################
# @noargs
# @internal
function __dybatpho_screen_on_resize {
  __dybatpho_screen_resized=true
}

#######################################
# @description Take over the terminal: alternate screen, raw mode, hidden
#   cursor, and mouse reporting.
#
#   The terminal is opened directly rather than taken from stdin and stdout, so
#   an application can still read a pipe and print a result that a caller
#   captures while it is drawing.
# @example
#   dybatpho::screen_begin
#   dybatpho::trap dybatpho::screen_end EXIT
#
# @noargs
# @set DYBATPHO_SCREEN_ACTIVE bool `true`
# @set DYBATPHO_SCREEN_WIDTH number Columns of the terminal
# @set DYBATPHO_SCREEN_HEIGHT number Rows of the terminal
# @set DYBATPHO_SCREEN_RECT string The whole terminal as a rectangle
# @exitcode 1 There is no terminal to take over
# @env DYBATPHO_SCREEN_MOUSE bool Turns mouse reporting on
# @tip The restore is registered on `EXIT`, `INT` and `TERM`, so a killed application still gives the terminal back
#######################################
function dybatpho::screen_begin {
  [[ "${DYBATPHO_SCREEN_ACTIVE}" == true ]] && return 0
  if [[ ! -e /dev/tty ]]; then
    dybatpho::error "${FUNCNAME[0]}: No terminal to draw on"
    return 1
  fi
  # kcov(disabled)
  exec {__dybatpho_screen_fd}<> /dev/tty || {
    dybatpho::error "${FUNCNAME[0]}: Cannot open the terminal"
    return 1
  }

  __dybatpho_screen_saved_stty="$(stty -g <&"${__dybatpho_screen_fd}" 2> /dev/null)" || {
    dybatpho::error "${FUNCNAME[0]}: Cannot put the terminal in raw mode"
    exec {__dybatpho_screen_fd}>&-
    __dybatpho_screen_fd=""
    return 1
  }
  stty raw -echo <&"${__dybatpho_screen_fd}" 2> /dev/null || true

  if [[ "${__dybatpho_screen_trapped}" != true ]]; then
    dybatpho::trap "dybatpho::screen_end" EXIT INT TERM
    dybatpho::trap "__dybatpho_screen_on_resize" WINCH
    __dybatpho_screen_trapped=true
  fi

  # Alternate screen, cursor hidden, and the cursor parked at the origin.
  printf '\033[?1049h\033[?25l\033[H' 1>&"${__dybatpho_screen_fd}"
  if dybatpho::is true "${DYBATPHO_SCREEN_MOUSE}"; then
    printf '\033[?1000h\033[?1006h' 1>&"${__dybatpho_screen_fd}"
  fi

  DYBATPHO_SCREEN_ACTIVE=true
  DYBATPHO_SCREEN_WIDTH=0
  DYBATPHO_SCREEN_HEIGHT=0
  dybatpho::screen_size || true
  return 0
  # kcov(enabled)
}

#######################################
# @description Give the terminal back: mouse reporting off, cursor shown, the
#   alternate screen left, and the original line settings restored.
# @noargs
# @set DYBATPHO_SCREEN_ACTIVE bool `false`
# @exitcode 0 Always, so it is safe in a trap and safe to call twice
#######################################
function dybatpho::screen_end {
  [[ "${DYBATPHO_SCREEN_ACTIVE}" == true ]] || return 0
  # kcov(disabled)
  DYBATPHO_SCREEN_ACTIVE=false
  if [[ -n "${__dybatpho_screen_fd}" ]]; then
    printf '\033[?1006l\033[?1000l\033[?25h\033[?1049l' 1>&"${__dybatpho_screen_fd}" 2> /dev/null || true
    [[ -n "${__dybatpho_screen_saved_stty}" ]] \
      && stty "${__dybatpho_screen_saved_stty}" <&"${__dybatpho_screen_fd}" 2> /dev/null
    # The redirection is on a group, not on `exec` itself: an `exec` without a
    # command keeps every redirection it is given, so `2> /dev/null` there
    # would silence the script's stderr for the rest of its life.
    { exec {__dybatpho_screen_fd}>&-; } 2> /dev/null || true
    __dybatpho_screen_fd=""
  fi
  __dybatpho_screen_saved_stty=""
  return 0
  # kcov(enabled)
}

#######################################
# @description Wait for the next event and report it under a stable name.
#
#   Keys come back as `up`, `down`, `left`, `right`, `enter`, `space`, `tab`,
#   `backspace`, `escape`, `home`, `end`, `pageup`, `pagedown`, `delete`, or
#   `char:<c>`. A terminal that changed size reports `resize`, a mouse click
#   reports `mouse:<button>`, and a closed input reports `eof`.
# @example
#   dybatpho::screen_event key
#   case "${key}" in
#     char:q | escape) break ;;
#     resize) dybatpho::screen_size && continue ;;
#     mouse:left) _click "${DYBATPHO_SCREEN_MOUSE_ROW}" "${DYBATPHO_SCREEN_MOUSE_COLUMN}" ;;
#   esac
#
# @arg $1 string Name of the variable receiving the event
# @arg $2 string Optional timeout in seconds; without one the call waits
# @set The named variable
# @set DYBATPHO_SCREEN_MOUSE_COLUMN number Zero-based column of a mouse event
# @set DYBATPHO_SCREEN_MOUSE_ROW number Zero-based row of a mouse event
# @exitcode 0 An event was read
# @exitcode 1 The timeout passed with no event, and the variable is set to `timeout`
# @tip A resize is delivered as an event rather than acted on, so an application redraws at a moment of its choosing
#   instead of in the middle of a frame
#######################################
function dybatpho::screen_event {
  dybatpho::expect_ref "$1"
  local -n __dybatpho_screen_e_out="$1"
  local __dybatpho_screen_e_timeout="${2-}"
  local -a __dybatpho_screen_e_read=(-rsn1)
  [[ -n "${__dybatpho_screen_e_timeout}" ]] \
    && __dybatpho_screen_e_read+=(-t "${__dybatpho_screen_e_timeout}")

  # A resize noticed while the last frame was drawing is reported before the
  # next key, so it is never lost behind a keystroke that has not come yet.
  if [[ "${__dybatpho_screen_resized}" == true ]]; then
    __dybatpho_screen_resized=false
    __dybatpho_screen_e_out="resize"
    return 0
  fi

  # kcov(disabled)
  local __dybatpho_screen_e_char __dybatpho_screen_e_status=0
  # The flags are in an array because the timeout is optional; `-r` is always
  # among them, which a static check cannot see through the expansion.
  # shellcheck disable=SC2162
  if [[ -n "${__dybatpho_screen_fd}" ]]; then
    IFS= read "${__dybatpho_screen_e_read[@]}" __dybatpho_screen_e_char \
      <&"${__dybatpho_screen_fd}" || __dybatpho_screen_e_status=$?
  else
    IFS= read "${__dybatpho_screen_e_read[@]}" __dybatpho_screen_e_char \
      || __dybatpho_screen_e_status=$?
  fi

  if ((__dybatpho_screen_e_status != 0)); then
    if [[ "${__dybatpho_screen_resized}" == true ]]; then
      __dybatpho_screen_resized=false
      __dybatpho_screen_e_out="resize"
      return 0
    fi
    # `read` reports a timeout with a status above 128 and end of input with a
    # lower one, which is the only way to tell "nothing yet" from "never again".
    if ((__dybatpho_screen_e_status > 128)); then
      __dybatpho_screen_e_out="timeout"
      return 1
    fi
    __dybatpho_screen_e_out="eof"
    return 0
  fi

  case "${__dybatpho_screen_e_char}" in
    '') __dybatpho_screen_e_out="enter" ;;
    ' ') __dybatpho_screen_e_out="space" ;;
    $'\t') __dybatpho_screen_e_out="tab" ;;
    $'\177' | $'\b') __dybatpho_screen_e_out="backspace" ;;
    $'\033')
      __dybatpho_screen_read_escape __dybatpho_screen_e_out
      ;;
    *) __dybatpho_screen_e_out="char:${__dybatpho_screen_e_char}" ;;
  esac
  return 0
  # kcov(enabled)
}

#######################################
# @description Read the rest of an escape sequence and name it.
# @arg $1 string Name of the variable receiving the event
# @set The named variable
# @internal
#######################################
function __dybatpho_screen_read_escape {
  # kcov(disabled)
  local -n __dybatpho_screen_esc_out="$1"
  local __dybatpho_screen_esc_char __dybatpho_screen_esc_body=""

  __dybatpho_screen_esc_out="escape"
  __dybatpho_screen_read_char __dybatpho_screen_esc_char 0.05 || return 0
  case "${__dybatpho_screen_esc_char}" in
    'O')
      __dybatpho_screen_read_char __dybatpho_screen_esc_char 0.05 || return 0
      case "${__dybatpho_screen_esc_char}" in
        A) __dybatpho_screen_esc_out="up" ;;
        B) __dybatpho_screen_esc_out="down" ;;
        C) __dybatpho_screen_esc_out="right" ;;
        D) __dybatpho_screen_esc_out="left" ;;
        H) __dybatpho_screen_esc_out="home" ;;
        F) __dybatpho_screen_esc_out="end" ;;
        *) ;;
      esac
      return 0
      ;;
    '[') ;;
    *) return 0 ;;
  esac

  # A CSI sequence runs until a letter or a tilde, so it is read to that end
  # rather than to a fixed length: a mouse report is far longer than an arrow.
  while __dybatpho_screen_read_char __dybatpho_screen_esc_char 0.05; do
    __dybatpho_screen_esc_body+="${__dybatpho_screen_esc_char}"
    case "${__dybatpho_screen_esc_char}" in
      [A-Za-z~]) break ;;
      *) ;;
    esac
    ((${#__dybatpho_screen_esc_body} < 32)) || break
  done

  case "${__dybatpho_screen_esc_body}" in
    A) __dybatpho_screen_esc_out="up" ;;
    B) __dybatpho_screen_esc_out="down" ;;
    C) __dybatpho_screen_esc_out="right" ;;
    D) __dybatpho_screen_esc_out="left" ;;
    H | '1~' | '7~') __dybatpho_screen_esc_out="home" ;;
    F | '4~' | '8~') __dybatpho_screen_esc_out="end" ;;
    '5~') __dybatpho_screen_esc_out="pageup" ;;
    '6~') __dybatpho_screen_esc_out="pagedown" ;;
    '3~') __dybatpho_screen_esc_out="delete" ;;
    '2~') __dybatpho_screen_esc_out="insert" ;;
    '<'*)
      __dybatpho_screen_parse_mouse __dybatpho_screen_esc_out "${__dybatpho_screen_esc_body}"
      ;;
    *) ;;
  esac
  return 0
  # kcov(enabled)
}

#######################################
# @description Read one character with a timeout.
# @arg $1 string Name of the variable receiving the character
# @arg $2 string Timeout in seconds
# @set The named variable
# @exitcode 1 Nothing arrived before the timeout
# @internal
#######################################
function __dybatpho_screen_read_char {
  # kcov(disabled)
  local -n __dybatpho_screen_rc_out="$1"
  if [[ -n "${__dybatpho_screen_fd}" ]]; then
    IFS= read -rsn1 -t "$2" __dybatpho_screen_rc_out <&"${__dybatpho_screen_fd}" || return 1
  else
    IFS= read -rsn1 -t "$2" __dybatpho_screen_rc_out || return 1
  fi
  return 0
  # kcov(enabled)
}

#######################################
# @description Return success when an event is already waiting, so reading it
#   with `dybatpho::screen_event` will not block.
#
#   A frame drawn in Bash takes longer than a terminal takes to repeat a held
#   key, so an application that draws once per event falls further behind for
#   as long as the key is held, and keeps moving after it is released. Handling
#   every event that is waiting before drawing the next frame keeps the screen
#   in step with the keyboard instead.
# @example
#   while true; do
#     _draw
#     dybatpho::screen_flush
#     dybatpho::screen_event key || continue
#     _handle "${key}"
#     while dybatpho::screen_pending; do
#       dybatpho::screen_event key
#       _handle "${key}"
#     done
#   done
#
# @noargs
# @exitcode 0 A key, or a resize, is waiting
# @exitcode 1 Nothing is waiting
# @tip Nothing is consumed: the event is still there for the next `dybatpho::screen_event`
#######################################
function dybatpho::screen_pending {
  [[ "${__dybatpho_screen_resized}" == true ]] && return 0
  # kcov(disabled)
  # `read -t 0` reads nothing; it only reports whether input is ready.
  if [[ -n "${__dybatpho_screen_fd}" ]]; then
    read -r -t 0 <&"${__dybatpho_screen_fd}"
  else
    read -r -t 0
  fi
  # kcov(enabled)
}

#######################################
# @description Turn an SGR mouse report into an event name and a position.
# @arg $1 string Name of the variable receiving the event
# @arg $2 string Body of the escape sequence, starting with `<`
# @set The named variable, `DYBATPHO_SCREEN_MOUSE_COLUMN`, `DYBATPHO_SCREEN_MOUSE_ROW`
# @internal
#######################################
function __dybatpho_screen_parse_mouse {
  local -n __dybatpho_screen_m_out="$1"
  local body="$2"
  __dybatpho_screen_m_out="escape"
  [[ "${body}" =~ ^\<([0-9]+)\;([0-9]+)\;([0-9]+)([Mm])$ ]] || return 0

  local button="${BASH_REMATCH[1]}"
  # The report is one-based, and every rectangle in this module is zero-based.
  DYBATPHO_SCREEN_MOUSE_COLUMN=$((BASH_REMATCH[2] - 1))
  DYBATPHO_SCREEN_MOUSE_ROW=$((BASH_REMATCH[3] - 1))
  if [[ "${BASH_REMATCH[4]}" == "m" ]]; then
    __dybatpho_screen_m_out="mouse:release"
    return 0
  fi
  case "${button}" in
    0) __dybatpho_screen_m_out="mouse:left" ;;
    1) __dybatpho_screen_m_out="mouse:middle" ;;
    2) __dybatpho_screen_m_out="mouse:right" ;;
    64) __dybatpho_screen_m_out="mouse:scrollup" ;;
    65) __dybatpho_screen_m_out="mouse:scrolldown" ;;
    *) __dybatpho_screen_m_out="mouse:other" ;;
  esac
  return 0
}

#######################################
# @description Read `key:value` widget options into an associative array.
#   Anything without a colon is left in place for the widget to read as a
#   positional argument.
# @arg $1 string Name of the associative array receiving the options
# @arg $@ string The options
# @set The named array
# @internal
#######################################
function __dybatpho_screen_options {
  local -n __dybatpho_screen_o_out="$1"
  shift
  local __dybatpho_screen_o_item
  for __dybatpho_screen_o_item in "$@"; do
    case "${__dybatpho_screen_o_item}" in
      *:*)
        __dybatpho_screen_o_out["${__dybatpho_screen_o_item%%:*}"]="${__dybatpho_screen_o_item#*:}"
        ;;
      *) ;;
    esac
  done
}

#######################################
# @description Copy a caller's array into one of the module's own.
#
#   Only namespaced locals exist in this function's scope, so a nameref bound to
#   a caller's array finds that array rather than a local of the same name. The
#   widgets that take small arrays copy through it instead of namespacing every
#   local they have; the ones that may be handed a long array bind the nameref
#   directly and namespace their locals instead, to avoid copying every frame.
# @arg $1 string Name of the array to fill
# @arg $2 string Name of the array to copy
# @set The named array
# @internal
#######################################
function __dybatpho_screen_copy_array {
  local -n __dybatpho_screen_ca_destination="$1"
  local -n __dybatpho_screen_ca_source="$2"
  __dybatpho_screen_ca_destination=(
    ${__dybatpho_screen_ca_source[@]+"${__dybatpho_screen_ca_source[@]}"}
  )
}

#######################################
# @description Pad text to a width, aligning it within the space.
# @arg $1 string Name of the variable receiving the padded text
# @arg $2 string Text
# @arg $3 number Width in columns
# @arg $4 string `left`, `center`, or `right`
# @set The named variable
# @internal
#######################################
function __dybatpho_screen_align_into {
  local -n __dybatpho_screen_a_out="$1"
  local __dybatpho_screen_a_text="$2" __dybatpho_screen_a_width="$3"
  local __dybatpho_screen_a_align="${4:-left}"
  local __dybatpho_screen_a_measured __dybatpho_screen_a_gap
  local __dybatpho_screen_a_left __dybatpho_screen_a_right

  __dybatpho_log_width_into __dybatpho_screen_a_measured "${__dybatpho_screen_a_text}"
  if ((__dybatpho_screen_a_measured > __dybatpho_screen_a_width)); then
    __dybatpho_screen_truncate_into __dybatpho_screen_a_out \
      "${__dybatpho_screen_a_text}" "${__dybatpho_screen_a_width}"
    __dybatpho_log_width_into __dybatpho_screen_a_measured "${__dybatpho_screen_a_out}"
    __dybatpho_screen_a_text="${__dybatpho_screen_a_out}"
  fi

  __dybatpho_screen_a_gap=$((__dybatpho_screen_a_width - __dybatpho_screen_a_measured))
  ((__dybatpho_screen_a_gap >= 0)) || __dybatpho_screen_a_gap=0
  case "${__dybatpho_screen_a_align}" in
    right)
      printf -v __dybatpho_screen_a_left '%*s' "${__dybatpho_screen_a_gap}" ''
      __dybatpho_screen_a_out="${__dybatpho_screen_a_left}${__dybatpho_screen_a_text}"
      ;;
    center)
      printf -v __dybatpho_screen_a_left '%*s' "$((__dybatpho_screen_a_gap / 2))" ''
      printf -v __dybatpho_screen_a_right '%*s' "$((__dybatpho_screen_a_gap - __dybatpho_screen_a_gap / 2))" ''
      __dybatpho_screen_a_out="${__dybatpho_screen_a_left}${__dybatpho_screen_a_text}${__dybatpho_screen_a_right}"
      ;;
    *)
      printf -v __dybatpho_screen_a_right '%*s' "${__dybatpho_screen_a_gap}" ''
      __dybatpho_screen_a_out="${__dybatpho_screen_a_text}${__dybatpho_screen_a_right}"
      ;;
  esac
  return 0
}

#######################################
# @description Draw a bordered box, optionally titled, and report the area left
#   inside it.
#
#   The inner rectangle is published rather than returned, because a block is
#   almost always followed by a widget drawn inside it and computing that
#   rectangle by hand is where off-by-one borders come from.
# @example
#   dybatpho::screen_block "${rect}" title:"Pods" border:rounded
#   dybatpho::screen_list "${DYBATPHO_SCREEN_INNER}" items selected:2
#
# @arg $1 string Rectangle to draw in
# @arg $@ string Options: `title:`, `border:`, `style:`, `title_style:`, `align:`, `focus:`
# @set DYBATPHO_SCREEN_INNER string The rectangle inside the border
# @exitcode 0 Always, including when the rectangle is too small to draw
# @tip `border:` takes `plain`, `rounded`, `double`, `thick`, or `none`; `none` still reserves no space, so the inner
#   rectangle is the whole one
# @tip `focus:true` draws the border in `DYBATPHO_SCREEN_STYLE_FOCUS`, which is how the panel that takes the keys stands
#   out from the others; an explicit `style:` still wins
#######################################
function dybatpho::screen_block {
  local rect="${1-}"
  shift || true
  local -A options=()
  __dybatpho_screen_options options "$@"

  local x y width height
  read -r x y width height <<< "${rect}"
  DYBATPHO_SCREEN_INNER="${x} ${y} ${width} ${height}"
  ((width > 0 && height > 0)) || return 0

  local kind="${options[border]:-plain}"
  local style="${DYBATPHO_SCREEN_STYLE_BORDER}"
  dybatpho::is true "${options[focus]:-false}" && style="${DYBATPHO_SCREEN_STYLE_FOCUS}"
  style="${options[style]:-${style}}"
  local horizontal vertical top_left top_right bottom_left bottom_right

  case "${kind}" in
    none)
      return 0
      ;;
    rounded)
      horizontal="─" vertical="│"
      top_left="╭" top_right="╮" bottom_left="╰" bottom_right="╯"
      ;;
    double)
      horizontal="═" vertical="║"
      top_left="╔" top_right="╗" bottom_left="╚" bottom_right="╝"
      ;;
    thick)
      horizontal="━" vertical="┃"
      top_left="┏" top_right="┓" bottom_left="┗" bottom_right="┛"
      ;;
    *)
      horizontal="─" vertical="│"
      top_left="┌" top_right="┐" bottom_left="└" bottom_right="┘"
      ;;
  esac

  local inner_width=$((width - 2))
  ((inner_width > 0)) || inner_width=0
  local bar="" index
  for ((index = 0; index < inner_width; index++)); do bar+="${horizontal}"; done

  dybatpho::screen_put "${y}" "${x}" "${top_left}${bar}${top_right}" "${style}"
  if ((height > 1)); then
    dybatpho::screen_put "$((y + height - 1))" "${x}" \
      "${bottom_left}${bar}${bottom_right}" "${style}"
  fi
  for ((index = y + 1; index < y + height - 1; index++)); do
    dybatpho::screen_put "${index}" "${x}" "${vertical}" "${style}"
    dybatpho::screen_put "${index}" "$((x + width - 1))" "${vertical}" "${style}"
  done

  if [[ -n "${options[title]-}" ]]; then
    local title=" ${options[title]} " placed
    __dybatpho_screen_truncate_into placed "${title}" "${inner_width}"
    local title_column=$((x + 1))
    if [[ "${options[align]-}" == center ]]; then
      local title_width
      __dybatpho_log_width_into title_width "${placed}"
      title_column=$((x + (width - title_width) / 2))
    fi
    dybatpho::screen_put "${y}" "${title_column}" "${placed}" \
      "${options[title_style]:-${DYBATPHO_SCREEN_STYLE_TITLE}}"
  fi

  local inner_height=$((height - 2))
  ((inner_height > 0)) || inner_height=0
  DYBATPHO_SCREEN_INNER="$((x + 1)) $((y + 1)) ${inner_width} ${inner_height}"
  return 0
}

#######################################
# @description Draw text in a rectangle, wrapped and aligned.
# @example
#   dybatpho::screen_text "${rect}" "${message}" align:center style:"1;33"
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Text; embedded newlines start a new line
# @arg $@ string Options: `style:`, `align:`, `wrap:`
# @exitcode 0 Always
# @tip `wrap:false` keeps one source line on one row and cuts what does not fit, which is what a status line wants
#######################################
function dybatpho::screen_text {
  local rect="${1-}" text="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local style="${options[style]:-0}"
  local align="${options[align]:-left}"
  local wrap="${options[wrap]:-true}"

  local -a source=() lines=()
  mapfile -t source <<< "${text}"

  local line word current current_width word_width
  for line in ${source[@]+"${source[@]}"}; do
    if dybatpho::is false "${wrap}"; then
      lines+=("${line}")
      continue
    fi
    __dybatpho_log_width_into current_width "${line}"
    if ((current_width <= width)); then
      lines+=("${line}")
      continue
    fi
    current=""
    current_width=0
    for word in ${line}; do
      __dybatpho_log_width_into word_width "${word}"
      if ((current_width > 0 && current_width + 1 + word_width > width)); then
        lines+=("${current}")
        current="${word}"
        current_width="${word_width}"
      elif ((current_width == 0)); then
        current="${word}"
        current_width="${word_width}"
      else
        current+=" ${word}"
        current_width=$((current_width + 1 + word_width))
      fi
    done
    [[ -n "${current}" ]] && lines+=("${current}")
  done

  local index padded
  for ((index = 0; index < height && index < ${#lines[@]}; index++)); do
    __dybatpho_screen_align_into padded "${lines[index]}" "${width}" "${align}"
    dybatpho::screen_put "$((y + index))" "${x}" "${padded}" "${style}"
  done
  return 0
}

#######################################
# @description Draw a scrollable list of items with one of them selected.
#
#   The list scrolls itself: the offset that keeps the selected item on screen
#   is worked out here and published, so an application only tracks which item
#   is selected.
# @example
#   local -a items=(alpha beta gamma)
#   dybatpho::screen_list "${rect}" items selected:1
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the items
# @arg $@ string Options: `selected:`, `offset:`, `style:`, `selected_style:`, `pointer:`
# @set DYBATPHO_SCREEN_OFFSET number Index of the first item drawn
# @exitcode 0 Always
# @tip Pass `pointer:false` for a list that marks the selection by highlight alone, which reads better in a narrow
#   column
#######################################
function dybatpho::screen_list {
  # Every local here is namespaced because the function binds a nameref to a
  # name the caller chose. A plain local called `width` or `count` would be
  # found first by a nameref pointing at a caller array of that name, and the
  # widget would quietly read its own variable instead.
  local __dybatpho_screen_l_rect="${1-}" __dybatpho_screen_l_var="${2-}"
  shift 2 2> /dev/null || true
  local -A __dybatpho_screen_l_options=()
  __dybatpho_screen_options __dybatpho_screen_l_options "$@"
  local -n __dybatpho_screen_l_items="${__dybatpho_screen_l_var}"

  local __dybatpho_screen_l_x __dybatpho_screen_l_y
  local __dybatpho_screen_l_width __dybatpho_screen_l_height
  read -r __dybatpho_screen_l_x __dybatpho_screen_l_y \
    __dybatpho_screen_l_width __dybatpho_screen_l_height <<< "${__dybatpho_screen_l_rect}"
  ((__dybatpho_screen_l_width > 0 && __dybatpho_screen_l_height > 0)) || return 0

  local __dybatpho_screen_l_count=${#__dybatpho_screen_l_items[@]}
  local __dybatpho_screen_l_selected="${__dybatpho_screen_l_options[selected]:--1}"
  local __dybatpho_screen_l_style="${__dybatpho_screen_l_options[style]:-0}"
  local __dybatpho_screen_l_selected_style
  __dybatpho_screen_l_selected_style="${__dybatpho_screen_l_options[selected_style]:-${DYBATPHO_SCREEN_STYLE_SELECTED}}"
  local __dybatpho_screen_l_pointer="${__dybatpho_screen_l_options[pointer]:-true}"
  local __dybatpho_screen_l_offset="${__dybatpho_screen_l_options[offset]:-0}"

  if ((__dybatpho_screen_l_selected >= 0)); then
    ((__dybatpho_screen_l_selected < __dybatpho_screen_l_offset)) \
      && __dybatpho_screen_l_offset="${__dybatpho_screen_l_selected}"
    ((__dybatpho_screen_l_selected >= __dybatpho_screen_l_offset + __dybatpho_screen_l_height)) \
      && __dybatpho_screen_l_offset=$((__dybatpho_screen_l_selected - __dybatpho_screen_l_height + 1))
  fi
  ((__dybatpho_screen_l_offset >= 0)) || __dybatpho_screen_l_offset=0
  ((__dybatpho_screen_l_count > __dybatpho_screen_l_height && \
  __dybatpho_screen_l_offset > __dybatpho_screen_l_count - __dybatpho_screen_l_height)) \
    && __dybatpho_screen_l_offset=$((__dybatpho_screen_l_count - __dybatpho_screen_l_height))
  ((__dybatpho_screen_l_offset >= 0)) || __dybatpho_screen_l_offset=0
  DYBATPHO_SCREEN_OFFSET="${__dybatpho_screen_l_offset}"

  local __dybatpho_screen_l_index __dybatpho_screen_l_source
  local __dybatpho_screen_l_marker __dybatpho_screen_l_padded __dybatpho_screen_l_row_style
  for ((__dybatpho_screen_l_index = 0;  \
  __dybatpho_screen_l_index < __dybatpho_screen_l_height;  \
  __dybatpho_screen_l_index++)); do
    __dybatpho_screen_l_source=$((__dybatpho_screen_l_offset + __dybatpho_screen_l_index))
    ((__dybatpho_screen_l_source < __dybatpho_screen_l_count)) || break
    __dybatpho_screen_l_marker=""
    __dybatpho_screen_l_row_style="${__dybatpho_screen_l_style}"
    if ((__dybatpho_screen_l_source == __dybatpho_screen_l_selected)); then
      __dybatpho_screen_l_row_style="${__dybatpho_screen_l_selected_style}"
      dybatpho::is false "${__dybatpho_screen_l_pointer}" \
        || __dybatpho_screen_l_marker="${DYBATPHO_SCREEN_POINTER} "
    elif dybatpho::is true "${__dybatpho_screen_l_pointer}"; then
      __dybatpho_screen_l_marker="  "
    fi
    __dybatpho_screen_align_into __dybatpho_screen_l_padded \
      "${__dybatpho_screen_l_marker}${__dybatpho_screen_l_items[__dybatpho_screen_l_source]}" \
      "${__dybatpho_screen_l_width}" left
    dybatpho::screen_put "$((__dybatpho_screen_l_y + __dybatpho_screen_l_index))" \
      "${__dybatpho_screen_l_x}" "${__dybatpho_screen_l_padded}" "${__dybatpho_screen_l_row_style}"
  done
  return 0
}

#######################################
# @description Draw a table with a header and an optional selected row.
# @example
#   local -a rows=("api|running|3" "worker|idle|1")
#   dybatpho::screen_table "${rect}" rows header:"NAME|STATE|COUNT" selected:0
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the rows
# @arg $@ string Options: `header:`, `delimiter:`, `widths:`, `selected:`, `style:`, `header_style:`, `selected_style:`
# @set DYBATPHO_SCREEN_OFFSET number Index of the first row drawn
# @exitcode 0 Always
# @tip `widths:` takes a comma-separated list of column widths; without it the columns share the space evenly
#######################################
function dybatpho::screen_table {
  local rect="${1-}" rows_var="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"
  local -a __dybatpho_screen_table_rows=()
  __dybatpho_screen_copy_array __dybatpho_screen_table_rows "${rows_var}"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local delimiter="${options[delimiter]:-|}"
  local header="${options[header]-}"
  local selected="${options[selected]:--1}"
  local style="${options[style]:-0}"
  local header_style="${options[header_style]:-1;4}"
  local selected_style="${options[selected_style]:-${DYBATPHO_SCREEN_STYLE_SELECTED}}"

  local body_y="${y}" body_height="${height}"
  if [[ -n "${header}" ]]; then
    body_y=$((y + 1))
    body_height=$((height - 1))
  fi
  ((body_height > 0)) || body_height=0

  # Column widths: the ones asked for, or an even share of the rectangle.
  local -a widths=()
  local sample="${header:-${__dybatpho_screen_table_rows[0]-}}"
  local -a sample_cells=()
  IFS="${delimiter}" read -r -a sample_cells <<< "${sample}"
  local column_count=${#sample_cells[@]}
  ((column_count > 0)) || return 0

  if [[ -n "${options[widths]-}" ]]; then
    IFS=',' read -r -a widths <<< "${options[widths]}"
  else
    local each=$((width / column_count)) index
    for ((index = 0; index < column_count; index++)); do
      widths[index]="${each}"
    done
    widths[column_count - 1]=$((width - each * (column_count - 1)))
  fi

  #######################################
  # @description Render one row of the table into a caller-named variable,
  #   padding each cell to the width the column was measured at.
  # @arg $1 string Name of the variable to write into
  # @arg $2 string The row, with its cells separated by the delimiter
  # @set The named variable
  # @internal
  #######################################
  function __dybatpho_screen_table_row_into {
    local -n __dybatpho_screen_tr_out="$1"
    local __dybatpho_screen_tr_line="$2"
    local -a __dybatpho_screen_tr_cells=()
    local __dybatpho_screen_tr_index __dybatpho_screen_tr_piece
    IFS="${delimiter}" read -r -a __dybatpho_screen_tr_cells <<< "${__dybatpho_screen_tr_line}"
    __dybatpho_screen_tr_out=""
    for ((__dybatpho_screen_tr_index = 0;  \
    __dybatpho_screen_tr_index < column_count;  \
    __dybatpho_screen_tr_index++)); do
      __dybatpho_screen_align_into __dybatpho_screen_tr_piece \
        "${__dybatpho_screen_tr_cells[__dybatpho_screen_tr_index]-}" \
        "${widths[__dybatpho_screen_tr_index]:-0}" left
      __dybatpho_screen_tr_out+="${__dybatpho_screen_tr_piece}"
    done
  }

  local line
  if [[ -n "${header}" ]]; then
    __dybatpho_screen_table_row_into line "${header}"
    dybatpho::screen_put "${y}" "${x}" "${line}" "${header_style}"
  fi

  local count=${#__dybatpho_screen_table_rows[@]}
  local offset="${options[offset]:-0}"
  if ((selected >= 0 && body_height > 0)); then
    ((selected < offset)) && offset="${selected}"
    ((selected >= offset + body_height)) && offset=$((selected - body_height + 1))
  fi
  ((offset >= 0)) || offset=0
  DYBATPHO_SCREEN_OFFSET="${offset}"

  local index source row_style
  for ((index = 0; index < body_height; index++)); do
    source=$((offset + index))
    ((source < count)) || break
    __dybatpho_screen_table_row_into line "${__dybatpho_screen_table_rows[source]}"
    row_style="${style}"
    ((source == selected)) && row_style="${selected_style}"
    dybatpho::screen_put "$((body_y + index))" "${x}" "${line}" "${row_style}"
  done
  unset -f __dybatpho_screen_table_row_into
  return 0
}

#######################################
# @description Draw a horizontal gauge filled to a ratio, with a label centred
#   on it.
# @example
#   dybatpho::screen_gauge "${rect}" 42 100 label:"42% used" style:"1;32"
#
# @arg $1 string Rectangle to draw in
# @arg $2 number Value reached
# @arg $3 number Value that counts as full, at least 1
# @arg $@ string Options: `label:`, `style:`, `empty_style:`, `filled:`, `empty:`
# @exitcode 0 Always
# @tip Leave `label:` out for the percentage, or pass an empty one for a bar with no text at all
#######################################
function dybatpho::screen_gauge {
  local rect="${1-}" value="${2:-0}" total="${3:-1}"
  shift 3 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0
  ((total > 0)) || total=1
  ((value >= 0)) || value=0
  ((value <= total)) || value="${total}"

  local filled_char="${options[filled]:-█}"
  local empty_char="${options[empty]:-░}"
  local style="${options[style]:-1;32}"
  local empty_style="${options[empty_style]:-2}"
  local filled=$((value * width / total))

  local label
  if [[ -v options[label] ]]; then
    label="${options[label]}"
  else
    label="$((value * 100 / total))%"
  fi

  local bar="" index
  for ((index = 0; index < width; index++)); do
    if ((index < filled)); then bar+="${filled_char}"; else bar+="${empty_char}"; fi
  done

  # The two halves are drawn separately so the filled part carries its own
  # colour, and the label is drawn over the top of both.
  local left="${bar:0:filled}" right="${bar:filled}"
  [[ -n "${left}" ]] && dybatpho::screen_put "${y}" "${x}" "${left}" "${style}"
  [[ -n "${right}" ]] && dybatpho::screen_put "${y}" "$((x + filled))" "${right}" "${empty_style}"

  if [[ -n "${label}" ]]; then
    local label_width
    __dybatpho_log_width_into label_width "${label}"
    dybatpho::screen_put "${y}" "$((x + (width - label_width) / 2))" "${label}" "1"
  fi
  return 0
}

#######################################
# @description Draw a row of tabs with one of them active.
# @example
#   local -a names=(Overview Logs Settings)
#   dybatpho::screen_tabs "${rect}" names active:0
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the tab titles
# @arg $@ string Options: `active:`, `style:`, `active_style:`, `divider:`, `divider_style:`
# @exitcode 0 Always
#######################################
function dybatpho::screen_tabs {
  local rect="${1-}" tabs_var="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"
  local -a __dybatpho_screen_tabs_items=()
  __dybatpho_screen_copy_array __dybatpho_screen_tabs_items "${tabs_var}"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local active="${options[active]:-0}"
  local style="${options[style]:-0}"
  local active_style="${options[active_style]:-${DYBATPHO_SCREEN_STYLE_TAB_ACTIVE}}"
  local divider="${options[divider]:- │ }"
  local divider_style="${options[divider_style]:-${DYBATPHO_SCREEN_STYLE_DIM}}"

  local index column=0 piece piece_width
  for index in "${!__dybatpho_screen_tabs_items[@]}"; do
    ((column < width)) || break
    if ((index > 0)); then
      dybatpho::screen_put "${y}" "$((x + column))" "${divider}" "${divider_style}"
      __dybatpho_log_width_into piece_width "${divider}"
      column=$((column + piece_width))
    fi
    piece=" ${__dybatpho_screen_tabs_items[index]} "
    __dybatpho_log_width_into piece_width "${piece}"
    if ((index == active)); then
      dybatpho::screen_put "${y}" "$((x + column))" "${piece}" "${active_style}"
    else
      dybatpho::screen_put "${y}" "$((x + column))" "${piece}" "${style}"
    fi
    column=$((column + piece_width))
  done
  return 0
}

#######################################
# @description Draw a vertical scrollbar showing where a window sits in a list
#   longer than the screen.
# @example
#   dybatpho::screen_scrollbar "${rect}" "${DYBATPHO_SCREEN_OFFSET}" "${#items[@]}"
#
# @arg $1 string Rectangle to draw in, normally one column wide
# @arg $2 number Index of the first visible item
# @arg $3 number Number of items in total
# @arg $@ string Options: `style:`, `track_style:`, `thumb:`, `track:`
# @exitcode 0 Always, including when everything fits and no bar is needed
#######################################
function dybatpho::screen_scrollbar {
  local rect="${1-}" position="${2:-0}" total="${3:-0}"
  shift 3 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0
  ((total > height)) || return 0

  local thumb_char="${options[thumb]:-█}"
  local track_char="${options[track]:-│}"
  local style="${options[style]:-0}"
  local track_style="${options[track_style]:-2}"

  local thumb_size=$((height * height / total))
  ((thumb_size > 0)) || thumb_size=1
  local span=$((total - height))
  local thumb_top=0
  ((span > 0)) && thumb_top=$((position * (height - thumb_size) / span))
  ((thumb_top >= 0)) || thumb_top=0
  ((thumb_top + thumb_size <= height)) || thumb_top=$((height - thumb_size))

  local index
  for ((index = 0; index < height; index++)); do
    if ((index >= thumb_top && index < thumb_top + thumb_size)); then
      dybatpho::screen_put "$((y + index))" "${x}" "${thumb_char}" "${style}"
    else
      dybatpho::screen_put "$((y + index))" "${x}" "${track_char}" "${track_style}"
    fi
  done
  return 0
}

#######################################
# @description Draw a one-row sparkline from a series of numbers.
# @example
#   local -a samples=(3 7 2 9 4)
#   dybatpho::screen_sparkline "${rect}" samples style:"36"
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the values
# @arg $@ string Options: `style:`, `max:`
# @exitcode 0 Always
# @tip Without `max:` the line scales to its own largest value, so a quiet series still fills the row
#######################################
function dybatpho::screen_sparkline {
  local rect="${1-}" data_var="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"
  local -a __dybatpho_screen_spark_data=()
  __dybatpho_screen_copy_array __dybatpho_screen_spark_data "${data_var}"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local -a levels=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  local maximum="${options[max]:-0}"
  local point
  if ((maximum <= 0)); then
    for point in ${__dybatpho_screen_spark_data[@]+"${__dybatpho_screen_spark_data[@]}"}; do
      [[ "${point}" =~ ^-?[0-9]+$ ]] || continue
      ((point > maximum)) && maximum="${point}"
    done
  fi
  ((maximum > 0)) || maximum=1

  # The most recent values are the interesting ones, so a series longer than the
  # rectangle keeps its tail rather than its head.
  local count=${#__dybatpho_screen_spark_data[@]}
  local first=0
  ((count > width)) && first=$((count - width))

  local line="" index level
  for ((index = first; index < count; index++)); do
    point="${__dybatpho_screen_spark_data[index]}"
    [[ "${point}" =~ ^-?[0-9]+$ ]] || point=0
    ((point >= 0)) || point=0
    level=$((point * 7 / maximum))
    ((level <= 7)) || level=7
    line+="${levels[level]}"
  done
  [[ -n "${line}" ]] && dybatpho::screen_put "${y}" "${x}" "${line}" "${options[style]:-0}"
  return 0
}

#######################################
# @description Draw horizontal bars, one per value, with optional labels.
# @example
#   local -a values=(12 30 7) names=(api worker cron)
#   dybatpho::screen_barchart "${rect}" values labels:names
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the values
# @arg $@ string Options: `labels:` naming an array, `style:`, `label_width:`, `max:`
# @exitcode 0 Always
# @tip Bars are drawn with eighth-width blocks, so a bar is accurate to an eighth of a column rather than rounded to a
#   whole one
#######################################
function dybatpho::screen_barchart {
  local rect="${1-}" data_var="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"
  local -a __dybatpho_screen_bar_data=()
  __dybatpho_screen_copy_array __dybatpho_screen_bar_data "${data_var}"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local -a __dybatpho_screen_bar_names=()
  if [[ -n "${options[labels]-}" ]]; then
    __dybatpho_screen_copy_array __dybatpho_screen_bar_names "${options[labels]}"
  fi

  local maximum="${options[max]:-0}" point
  if ((maximum <= 0)); then
    for point in ${__dybatpho_screen_bar_data[@]+"${__dybatpho_screen_bar_data[@]}"}; do
      [[ "${point}" =~ ^-?[0-9]+$ ]] || continue
      ((point > maximum)) && maximum="${point}"
    done
  fi
  ((maximum > 0)) || maximum=1

  local label_width="${options[label_width]:-0}"
  if ((label_width == 0)) && ((${#__dybatpho_screen_bar_names[@]} > 0)); then
    local measured
    for point in "${__dybatpho_screen_bar_names[@]}"; do
      __dybatpho_log_width_into measured "${point}"
      ((measured > label_width)) && label_width="${measured}"
    done
    label_width=$((label_width + 1))
  fi

  # An eighth-block ladder lets a bar end part way through a column, which is
  # the difference between a chart that moves smoothly and one that steps.
  local -a eighths=('' ▏ ▎ ▍ ▌ ▋ ▊ ▉)
  local bar_width=$((width - label_width))
  ((bar_width > 0)) || return 0

  local index padded filled remainder bar cell
  for ((index = 0; index < height && index < ${#__dybatpho_screen_bar_data[@]}; index++)); do
    point="${__dybatpho_screen_bar_data[index]}"
    [[ "${point}" =~ ^-?[0-9]+$ ]] || point=0
    ((point >= 0)) || point=0
    if ((label_width > 0)); then
      __dybatpho_screen_align_into padded "${__dybatpho_screen_bar_names[index]-}" "$((label_width - 1))" left
      dybatpho::screen_put "$((y + index))" "${x}" "${padded} " "0"
    fi
    local eighth_total=$((point * bar_width * 8 / maximum))
    filled=$((eighth_total / 8))
    remainder=$((eighth_total % 8))
    bar=""
    for ((cell = 0; cell < filled; cell++)); do bar+="█"; done
    ((remainder > 0 && filled < bar_width)) && bar+="${eighths[remainder]}"
    [[ -n "${bar}" ]] \
      && dybatpho::screen_put "$((y + index))" "$((x + label_width))" "${bar}" "${options[style]:-36}"
  done
  return 0
}

# The 256 Braille patterns, built on first use. Each is U+2800 plus a bit per
# dot, which gives a 2x4 grid of points inside one character cell.
declare -ga __dybatpho_screen_braille=()

#######################################
# @description Fill the Braille lookup table, once.
#
#   The table is built with a single `printf`: the format string is assembled
#   from `\Uxxxxxxxx` escapes first and expanded in one call, rather than
#   calling out once per character.
#######################################
# @noargs
# @internal
function __dybatpho_screen_braille_table {
  ((${#__dybatpho_screen_braille[@]} == 0)) || return 0
  local format="" index piece
  for ((index = 0; index < 256; index++)); do
    printf -v piece '\\U%08x' "$((0x2800 + index))"
    format+="${piece}"
  done
  local all
  # The format string is the point: it is 256 `\Uxxxxxxxx` escapes built above,
  # and one `printf` expands all of them at once instead of calling out per
  # character.
  # shellcheck disable=SC2059
  printf -v all "${format}"
  __dybatpho_log_chars_into __dybatpho_screen_braille "${all}"
  return 0
}

#######################################
# @description Plot a series as a line chart, using Braille dots for a
#   resolution of two points across and four down inside every character.
#
#   This is the one widget that works a cell at a time, because a chart is the
#   one thing whose every cell differs. It is bounded by the rectangle it is
#   given, so a chart in a corner of the screen costs what that corner is worth
#   rather than what the whole screen would be.
# @example
#   local -a series=(1 4 2 8 5 9 3)
#   dybatpho::screen_chart "${rect}" series style:"32"
#
# @arg $1 string Rectangle to draw in
# @arg $2 string Name of the array holding the values
# @arg $@ string Options: `style:`, `max:`, `min:`
# @exitcode 0 Always
# @tip A rectangle of 40x10 is 400 cells and costs a few milliseconds; a full-screen chart is where this model stops
#   being
#   cheap
#######################################
function dybatpho::screen_chart {
  local rect="${1-}" data_var="${2-}"
  shift 2 2> /dev/null || true
  local -A options=()
  __dybatpho_screen_options options "$@"
  local -a __dybatpho_screen_chart_data=()
  __dybatpho_screen_copy_array __dybatpho_screen_chart_data "${data_var}"

  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0
  local count=${#__dybatpho_screen_chart_data[@]}
  ((count > 0)) || return 0

  __dybatpho_screen_braille_table

  local point minimum="${options[min]:-0}" maximum="${options[max]:-0}"
  local have_range=0
  [[ -n "${options[max]-}" ]] && have_range=1
  if ((have_range == 0)); then
    maximum="${__dybatpho_screen_chart_data[0]}"
    minimum="${maximum}"
    for point in "${__dybatpho_screen_chart_data[@]}"; do
      [[ "${point}" =~ ^-?[0-9]+$ ]] || continue
      ((point > maximum)) && maximum="${point}"
      ((point < minimum)) && minimum="${point}"
    done
  fi
  ((maximum > minimum)) || maximum=$((minimum + 1))

  # Every character is two dots across and four down, so the plot resolution is
  # the rectangle multiplied out.
  local dots_x=$((width * 2)) dots_y=$((height * 4))
  local -A cells=()
  local index dot_x dot_y cell_x cell_y bit
  local -a bits=(0x01 0x02 0x04 0x40 0x08 0x10 0x20 0x80)

  # Consecutive samples are joined rather than left as separate dots: a series
  # of eight values across fifty columns would otherwise be eight specks with
  # nothing between them, which reads as noise instead of as a line.
  local previous_x=-1 previous_y=0 step_x step_y span
  for ((index = 0; index < count; index++)); do
    point="${__dybatpho_screen_chart_data[index]}"
    [[ "${point}" =~ ^-?[0-9]+$ ]] || continue
    dot_x=$((count > 1 ? index * (dots_x - 1) / (count - 1) : 0))
    dot_y=$(((maximum - point) * (dots_y - 1) / (maximum - minimum)))
    ((dot_y >= 0)) || dot_y=0
    ((dot_y < dots_y)) || dot_y=$((dots_y - 1))

    if ((previous_x >= 0)); then
      span=$((dot_x - previous_x))
      for ((step_x = previous_x; step_x <= dot_x; step_x++)); do
        if ((span > 0)); then
          step_y=$((previous_y + (dot_y - previous_y) * (step_x - previous_x) / span))
        else
          step_y="${dot_y}"
        fi
        cell_x=$((step_x / 2))
        cell_y=$((step_y / 4))
        bit="${bits[(step_x % 2) * 4 + (step_y % 4)]}"
        cells["${cell_y},${cell_x}"]=$((${cells["${cell_y},${cell_x}"]:-0} | bit))
      done
    else
      cell_x=$((dot_x / 2))
      cell_y=$((dot_y / 4))
      bit="${bits[(dot_x % 2) * 4 + (dot_y % 4)]}"
      cells["${cell_y},${cell_x}"]=$((${cells["${cell_y},${cell_x}"]:-0} | bit))
    fi
    previous_x="${dot_x}"
    previous_y="${dot_y}"
  done

  local key row column pattern line
  for ((row = 0; row < height; row++)); do
    line=""
    local drawn=0
    for ((column = 0; column < width; column++)); do
      key="${row},${column}"
      pattern="${cells[${key}]:-0}"
      if ((pattern == 0)); then
        line+=" "
      else
        line+="${__dybatpho_screen_braille[pattern]}"
        drawn=1
      fi
    done
    ((drawn)) && dybatpho::screen_put "$((y + row))" "${x}" "${line}" "${options[style]:-0}"
  done
  return 0
}

#######################################
# @description Blank a rectangle and draw a block over it, which is what a
#   dialog or a menu laid over the screen needs.
#
#   Whatever was underneath is erased rather than shown through, so the popup
#   can be drawn last over a frame that knows nothing about it.
# @example
#   local popup
#   dybatpho::screen_rect_center popup "${DYBATPHO_SCREEN_RECT}" 40 7
#   dybatpho::screen_popup "${popup}" title:"Confirm"
#   dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" "Delete the record?" align:center
#
# @arg $1 string Rectangle to clear and draw in
# @arg $@ string Options, the same ones `dybatpho::screen_block` takes
# @set DYBATPHO_SCREEN_INNER string The rectangle inside the border
# @exitcode 0 Always
#######################################
function dybatpho::screen_popup {
  local rect="${1-}"
  shift || true
  local x y width height
  read -r x y width height <<< "${rect}"
  ((width > 0 && height > 0)) || return 0

  local blank index
  printf -v blank '%*s' "${width}" ''
  for ((index = 0; index < height; index++)); do
    dybatpho::screen_put "$((y + index))" "${x}" "${blank}" "0"
  done
  dybatpho::screen_block "${rect}" "$@"
  return 0
}

#######################################
# @description Draw pieces of text side by side on one row, each in its own
#   style, cut to a width.
#
#   This is what a row needs as soon as it is more than one colour -- a check
#   mark in green before a name in bold, a key in a key bar before what it does
#   -- and what `dybatpho::screen_list` cannot do, because it styles a whole row
#   at once. With a background, every piece is drawn over it and the rest of
#   the width is filled with it, so a selected row or a status bar reads as one
#   band.
# @example
#   dybatpho::screen_spans 3 2 30 "" "✔ " "32" "ripgrep" "1" " 2s" "2"
#   dybatpho::screen_spans 4 2 30 "48;5;237" "▌ " "1;35" "selected row" "1"
#
# @arg $1 number Row, zero-based
# @arg $2 number Column, zero-based
# @arg $3 number Width in columns
# @arg $4 string SGR parameters of the background, or empty for none
# @arg $@ string Pairs of text and its SGR parameters
# @exitcode 0 Always; a piece that does not fit is cut, and the pieces after it are dropped
# @tip The background comes before each piece's own style, so a piece keeps its colours over it; a piece styled
#   `""` or `0` is drawn in the background alone
#######################################
# dyshellint disable=BSG050 drawn for every row of every frame, like dybatpho::screen_put
function dybatpho::screen_spans {
  local row="${1-}" column="${2-}" width="${3-}" background="${4-}"
  shift 4 2> /dev/null || return 0
  __dybatpho_screen_expect_int "${FUNCNAME[0]}" "width" "${width}" 0
  local left="${width}" text style used
  while (($# >= 2)) && ((left > 0)); do
    text="$1" style="$2"
    shift 2
    [[ -n "${text}" ]] || continue
    __dybatpho_log_width_into used "${text}"
    if ((used > left)); then
      __dybatpho_screen_truncate_into text "${text}" "${left}"
      __dybatpho_log_width_into used "${text}"
    fi
    if [[ -n "${background}" ]]; then
      if [[ -z "${style}" || "${style}" == 0 ]]; then
        style="${background}"
      else
        style="${background};${style}"
      fi
    fi
    dybatpho::screen_put "${row}" "${column}" "${text}" "${style}"
    column=$((column + used))
    left=$((left - used))
  done
  if [[ -n "${background}" ]] && ((left > 0)); then
    printf -v text '%*s' "${left}" ""
    dybatpho::screen_put "${row}" "${column}" "${text}" "${background}"
  fi
  return 0
}

#######################################
# @description Draw a line that carries its own SGR colour sequences -- the
#   output of a command, a log written by another program -- keeping its
#   colours.
#
#   Each sequence changes the style of the text after it, the way a terminal
#   reads it: parameters accumulate until a reset. A sequence that is not a
#   colour change, such as a cursor movement, is dropped rather than drawn,
#   because it would move the cursor out of the frame.
# @example
#   dybatpho::screen_ansi 5 1 60 $'\033[1;32mok\033[0m installed ripgrep'
#
# @arg $1 number Row, zero-based
# @arg $2 number Column, zero-based
# @arg $3 number Width in columns
# @arg $4 string The line, with its escape sequences
# @exitcode 0 Always
# @tip Strip `\r` and expand tabs before passing a line; they are control characters, not text with a width
#######################################
# dyshellint disable=BSG050 drawn for every row of every frame, like dybatpho::screen_put
function dybatpho::screen_ansi {
  local row="${1-}" column="${2-}" width="${3-}" rest="${4-}"
  local style="0" before params
  local -a spans=()
  while [[ "${rest}" == *$'\033['* ]]; do
    before="${rest%%$'\033['*}"
    [[ -n "${before}" ]] && spans+=("${before}" "${style}")
    rest="${rest#*$'\033['}"
    # The final byte of a control sequence is a letter; only `m` is a colour.
    if [[ "${rest}" =~ ^([0-9\;?]*)([A-Za-z]) ]]; then
      params="${BASH_REMATCH[1]}"
      rest="${rest:${#BASH_REMATCH[0]}}"
      [[ "${BASH_REMATCH[2]}" == m && "${params}" =~ ^[0-9\;]*$ ]] || continue
    else
      continue
    fi
    case "${params}" in
      "" | 0 | 00) style="0" ;;
      0\;* | 00\;*) style="${params#*;}" ;;
      *)
        if [[ "${style}" == "0" ]]; then
          style="${params}"
        else
          style+=";${params}"
        fi
        ;;
    esac
  done
  [[ -n "${rest}" ]] && spans+=("${rest}" "${style}")
  ((${#spans[@]} > 0)) || return 0
  dybatpho::screen_spans "${row}" "${column}" "${width}" "" "${spans[@]}"
}

#######################################
# @description Draw a one-row bar of key hints: each key in
#   `DYBATPHO_SCREEN_STYLE_KEY`, what it does after it, all over
#   `DYBATPHO_SCREEN_STYLE_KEYBAR` across the whole width.
# @example
#   dybatpho::screen_keybar "${footer}" "↑↓" "move" "space" "pick" "q" "quit"
#
# @arg $1 string Rectangle to draw in; only its first row is used
# @arg $@ string Pairs of a key and what it does
# @exitcode 0 Always; hints that do not fit are cut at the edge
#######################################
function dybatpho::screen_keybar {
  local rect x y width height
  dybatpho::expect_args rect -- "$@"
  shift
  read -r x y width height <<< "${rect}"
  ((${width:-0} > 0 && ${height:-0} > 0)) || return 0
  local -a spans=()
  while (($# >= 2)); do
    spans+=(" $1" "${DYBATPHO_SCREEN_STYLE_KEY}" " $2 " "")
    shift 2
  done
  dybatpho::screen_spans "${y}" "${x}" "${width}" "${DYBATPHO_SCREEN_STYLE_KEYBAR}" "${spans[@]}"
}

#######################################
# @description Set every `DYBATPHO_SCREEN_STYLE_*` variable from a named
#   palette, so an application gets a consistent look without choosing a
#   colour for each widget.
#
#   | Theme | Look |
#   | --- | --- |
#   | `default` | the module's own defaults: bold, dim, reverse and the eight basic colours |
#   | `dusk` | a 256-colour palette: violet frames and selection, soft green, amber and red |
#   | `mono` | no colour at all, only bold, dim and reverse |
#   | `catppuccin-latte` | [Catppuccin](https://catppuccin.com) Latte, the light flavour, in 24-bit colour |
#   | `catppuccin-frappe` | Catppuccin Frappé, a muted dark flavour |
#   | `catppuccin-macchiato` | Catppuccin Macchiato, a darker flavour |
#   | `catppuccin-mocha` | Catppuccin Mocha, the darkest flavour |
#
#   The Catppuccin themes take mauve for frames and selection, lavender for
#   titles, pink for keys, and the flavour's own green, yellow and red. They
#   colour text and bars but not the screen behind them, so pick the flavour
#   that matches the terminal: `catppuccin-latte` on a light background, one
#   of the others on a dark one.
#
#   A theme is downgraded to `mono` when colour is not wanted, so an
#   application can ask for a palette and still respect the environment it
#   runs in. `dybatpho::color_supported` decides, which means `NO_COLOR` and
#   `TERM=dumb` both reach `mono`, and `FORCE_COLOR` keeps the palette on a
#   stream that is not a terminal.
# @example
#   dybatpho::screen_theme dusk
#   dybatpho::screen_theme catppuccin-mocha
#   dybatpho::screen_block "${rect}" title:"Tools" focus:true
#
# @arg $1 string Theme name: `default`, `dusk`, `mono`, `catppuccin-latte`,
#   `catppuccin-frappe`, `catppuccin-macchiato`, or `catppuccin-mocha`
# @env NO_COLOR string Use `mono` in place of a coloured theme when set to a non-empty value
# @env FORCE_COLOR string Keep a coloured theme even when stdout is not a terminal
# @see dybatpho::color_supported
# @set DYBATPHO_SCREEN_STYLE_* string Every style variable of the module, from the palette
# @exitcode 0 The theme was applied
# @exitcode 1 The theme is unknown, and nothing was changed
#######################################
function dybatpho::screen_theme {
  local name
  dybatpho::expect_args name -- "$@"
  # `default` is downgraded too, not only the palettes: it carries three
  # colours of its own, and leaving them on under `NO_COLOR` was the module
  # answering the question differently depending on which theme was asked for.
  # Only a known coloured theme is downgraded, so an unknown name still
  # reaches the arm that rejects it rather than being quietly accepted as
  # `mono`.
  case "${name}" in
    default | dusk | catppuccin-latte | catppuccin-frappe | catppuccin-macchiato | catppuccin-mocha)
      dybatpho::color_supported stdout || name="mono"
      ;;
    *) ;;
  esac
  # Catppuccin publishes its palette in hex; keeping the hex here makes each
  # flavour checkable against https://catppuccin.com/palette at a glance.
  local -a palette=()
  case "${name}" in
    catppuccin-latte) palette=(eff1f5 e6e9ef bcc0cc 9ca0b0 6c6f85 7287fd 8839ef ea76cb 40a02b df8e1d d20f39) ;;
    catppuccin-frappe) palette=(303446 292c3c 51576d 737994 a5adce babbf1 ca9ee6 f4b8e4 a6d189 e5c890 e78284) ;;
    catppuccin-macchiato) palette=(24273a 1e2030 494d64 6e738d a5adcb b7bdf8 c6a0f6 f5bde6 a6da95 eed49f ed8796) ;;
    catppuccin-mocha) palette=(1e1e2e 181825 45475a 6c7086 a6adc8 b4befe cba6f7 f5c2e7 a6e3a1 f9e2af f38ba8) ;;
    *) ;;
  esac
  if ((${#palette[@]})); then
    local -a rgb=()
    local hex
    for hex in "${palette[@]}"; do
      rgb+=("$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))")
    done
    # base mantle surface1 overlay0 subtext0 lavender mauve pink green yellow red
    local base="${rgb[0]}" mantle="${rgb[1]}" surface1="${rgb[2]}" overlay0="${rgb[3]}"
    local subtext0="${rgb[4]}" lavender="${rgb[5]}" mauve="${rgb[6]}" pink="${rgb[7]}"
    local green="${rgb[8]}" yellow="${rgb[9]}" red="${rgb[10]}"
    DYBATPHO_SCREEN_STYLE_SELECTED="1;38;2;${base};48;2;${mauve}" DYBATPHO_SCREEN_STYLE_BORDER="38;2;${surface1}"
    DYBATPHO_SCREEN_STYLE_TITLE="1;38;2;${lavender}" DYBATPHO_SCREEN_STYLE_FOCUS="38;2;${mauve}"
    DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;38;2;${base};48;2;${mauve}"
    DYBATPHO_SCREEN_STYLE_KEYBAR="38;2;${subtext0};48;2;${mantle}"
    DYBATPHO_SCREEN_STYLE_KEY="1;38;2;${pink}" DYBATPHO_SCREEN_STYLE_ACCENT="1;38;2;${pink}"
    DYBATPHO_SCREEN_STYLE_DIM="38;2;${overlay0}" DYBATPHO_SCREEN_STYLE_OK="1;38;2;${green}"
    DYBATPHO_SCREEN_STYLE_WARN="38;2;${yellow}" DYBATPHO_SCREEN_STYLE_ERROR="1;38;2;${red}"
    return 0
  fi
  case "${name}" in
    default)
      DYBATPHO_SCREEN_STYLE_SELECTED="1;7" DYBATPHO_SCREEN_STYLE_BORDER="2"
      DYBATPHO_SCREEN_STYLE_TITLE="1" DYBATPHO_SCREEN_STYLE_FOCUS="1"
      DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;7" DYBATPHO_SCREEN_STYLE_KEYBAR="7"
      DYBATPHO_SCREEN_STYLE_KEY="1" DYBATPHO_SCREEN_STYLE_ACCENT="1"
      DYBATPHO_SCREEN_STYLE_DIM="2" DYBATPHO_SCREEN_STYLE_OK="32"
      DYBATPHO_SCREEN_STYLE_WARN="33" DYBATPHO_SCREEN_STYLE_ERROR="31"
      ;;
    dusk)
      DYBATPHO_SCREEN_STYLE_SELECTED="1;38;5;231;48;5;61" DYBATPHO_SCREEN_STYLE_BORDER="38;5;239"
      DYBATPHO_SCREEN_STYLE_TITLE="1;38;5;183" DYBATPHO_SCREEN_STYLE_FOCUS="38;5;141"
      DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;38;5;231;48;5;61" DYBATPHO_SCREEN_STYLE_KEYBAR="38;5;250;48;5;235"
      DYBATPHO_SCREEN_STYLE_KEY="1;38;5;213" DYBATPHO_SCREEN_STYLE_ACCENT="1;38;5;213"
      DYBATPHO_SCREEN_STYLE_DIM="38;5;243" DYBATPHO_SCREEN_STYLE_OK="1;38;5;114"
      DYBATPHO_SCREEN_STYLE_WARN="38;5;221" DYBATPHO_SCREEN_STYLE_ERROR="1;38;5;203"
      ;;
    mono)
      DYBATPHO_SCREEN_STYLE_SELECTED="1;7" DYBATPHO_SCREEN_STYLE_BORDER="2"
      DYBATPHO_SCREEN_STYLE_TITLE="1" DYBATPHO_SCREEN_STYLE_FOCUS="0"
      DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;7" DYBATPHO_SCREEN_STYLE_KEYBAR="7"
      DYBATPHO_SCREEN_STYLE_KEY="1" DYBATPHO_SCREEN_STYLE_ACCENT="1"
      DYBATPHO_SCREEN_STYLE_DIM="2" DYBATPHO_SCREEN_STYLE_OK="1"
      DYBATPHO_SCREEN_STYLE_WARN="0" DYBATPHO_SCREEN_STYLE_ERROR="1"
      ;;
    *)
      local expected="default, dusk, mono or catppuccin-{latte,frappe,macchiato,mocha}"
      dybatpho::error "${FUNCNAME[0]}: Unknown theme '${name}', expected ${expected}"
      return 1
      ;;
  esac
  return 0
}
