setup() {
  load test_helper
  # The buffer is sized from the environment rather than from a terminal, so
  # every assertion below is about the drawing and not about the machine the
  # suite happens to run on.
  export COLUMNS=40 LINES=12
  export NO_COLOR=1
  DYBATPHO_SCREEN_WIDTH=0
  DYBATPHO_SCREEN_HEIGHT=0
  dybatpho::screen_size || true
  dybatpho::screen_clear
}

# @description Print one row of the buffer with its styles stripped, which is
#   what makes a layout assertion readable.
screen_row() {
  local rendered
  __dybatpho_screen_render_into rendered "$1"
  printf '%s' "${rendered}" | LC_ALL=C sed -E 's/\x1B\[[0-9;]*m//g'
}

# @description Print one row of the buffer with its escape sequences intact.
screen_raw() {
  local rendered
  __dybatpho_screen_render_into rendered "$1"
  printf '%s' "${rendered}"
}

# =============================================================================
# dybatpho::screen_width
# =============================================================================

@test "dybatpho::screen_width measures ASCII, CJK, emoji and combining marks" {
  local columns
  dybatpho::screen_width columns "hello"
  assert_equal "${columns}" 5
  # A CJK ideograph takes two columns, which is the whole reason a length is
  # not a width.
  dybatpho::screen_width columns "漢字ab"
  assert_equal "${columns}" 6
  dybatpho::screen_width columns "🚀x"
  assert_equal "${columns}" 3
  # A combining acute adds no column of its own.
  dybatpho::screen_width columns $'é'
  assert_equal "${columns}" 1
  dybatpho::screen_width columns "─┐"
  assert_equal "${columns}" 2
  dybatpho::screen_width columns ""
  assert_equal "${columns}" 0
}

@test "dybatpho::screen_width refuses a reserved result variable" {
  run dybatpho::screen_width __dybatpho_stolen "text"
  assert_failure
  assert_output --partial "is reserved"
}

# =============================================================================
# dybatpho::screen_rect, dybatpho::screen_rect_inner, dybatpho::screen_rect_center
# =============================================================================

@test "dybatpho::screen_rect builds a rectangle from its parts" {
  local box
  dybatpho::screen_rect box 2 3 10 4
  assert_equal "${box}" "2 3 10 4"
}

@test "dybatpho::screen_rect_inner shrinks a rectangle and never goes negative" {
  local inner
  dybatpho::screen_rect_inner inner "0 0 10 10" 1
  assert_equal "${inner}" "1 1 8 8"
  dybatpho::screen_rect_inner inner "0 0 1 1" 1
  assert_equal "${inner}" "1 1 0 0"
}

@test "dybatpho::screen_rect_center centres a rectangle and clamps it to fit" {
  local middle
  dybatpho::screen_rect_center middle "0 0 100 30" 40 10
  assert_equal "${middle}" "30 10 40 10"
  dybatpho::screen_rect_center middle "0 0 10 4" 40 10
  assert_equal "${middle}" "0 0 10 4"
}

# =============================================================================
# dybatpho::screen_layout
# =============================================================================

@test "dybatpho::screen_layout splits a rectangle vertically and horizontally" {
  local -a parts=()
  dybatpho::screen_layout parts vertical "0 0 100 30" length:3 fill:1 length:1
  assert_equal "${#parts[@]}" 3
  assert_equal "${parts[0]}" "0 0 100 3"
  assert_equal "${parts[1]}" "0 3 100 26"
  assert_equal "${parts[2]}" "0 29 100 1"

  dybatpho::screen_layout parts horizontal "0 0 100 30" percent:30 fill:1
  assert_equal "${parts[0]}" "0 0 30 30"
  assert_equal "${parts[1]}" "30 0 70 30"
}

@test "dybatpho::screen_layout honors ratio, min and max constraints" {
  local -a parts=()
  dybatpho::screen_layout parts horizontal "0 0 90 10" ratio:1/3 ratio:2/3
  assert_equal "${parts[0]}" "0 0 30 10"
  assert_equal "${parts[1]}" "30 0 60 10"

  dybatpho::screen_layout parts vertical "0 0 100 10" min:4 min:4
  assert_equal "${parts[0]}" "0 0 100 5"

  dybatpho::screen_layout parts vertical "0 0 100 10" max:3 fill:1
  assert_equal "${parts[0]}" "0 0 100 3"
  assert_equal "${parts[1]}" "0 3 100 7"
}

@test "dybatpho::screen_layout always tiles the rectangle exactly" {
  # Percentages round down, so three of them would leave a row unaccounted for
  # and the bottom of the screen would never be drawn.
  local -a parts=()
  local part total=0
  dybatpho::screen_layout parts vertical "0 0 100 30" percent:33 percent:33 fill:1
  for part in "${parts[@]}"; do
    total=$((total + ${part##* }))
  done
  assert_equal "${total}" 30
}

@test "dybatpho::screen_layout shrinks from the end when asked for too much" {
  local -a parts=()
  dybatpho::screen_layout parts vertical "0 0 100 5" length:4 length:4
  assert_equal "${parts[0]}" "0 0 100 4"
  assert_equal "${parts[1]}" "0 4 100 1"
}

@test "dybatpho::screen_layout refuses an unknown direction or constraint" {
  local -a parts=()
  run dybatpho::screen_layout parts sideways "0 0 10 10" fill:1
  assert_failure
  assert_output --partial "must be vertical or horizontal"
  run dybatpho::screen_layout parts vertical "0 0 10 10" wider:2
  assert_failure
  assert_output --partial "Unknown constraint"
  run dybatpho::screen_layout parts vertical "0 0 10 10" ratio:1/0
  assert_failure
  assert_output --partial "divided by zero"
}

# =============================================================================
# dybatpho::screen_clear, dybatpho::screen_put, dybatpho::screen_size
# =============================================================================

@test "dybatpho::screen_size sizes the buffer and reports only real changes" {
  assert_equal "${DYBATPHO_SCREEN_WIDTH}" 40
  assert_equal "${DYBATPHO_SCREEN_HEIGHT}" 12
  assert_equal "${DYBATPHO_SCREEN_RECT}" "0 0 40 12"
  # Nothing changed, so there is nothing to rebuild.
  run_traced dybatpho::screen_size
  assert_failure
}

@test "dybatpho::screen_put draws text and dybatpho::screen_clear blanks it" {
  dybatpho::screen_put 0 0 "hello" "1;32"
  assert_equal "$(screen_row 0)" "hello                                   "
  dybatpho::screen_clear
  assert_equal "$(screen_row 0)" "                                        "
}

@test "dybatpho::screen_put applies a style over the span it drew and no further" {
  dybatpho::screen_put 0 0 "aaaaaaaaaa" "31"
  dybatpho::screen_put 0 2 "bb" "32"
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "aabbaaaaaa"
  # The style in force before the span has to come back after it, or every
  # later cell on the row inherits the colour of whatever was drawn over it.
  [[ "$(screen_raw 0)" == *$'\033[32m'bb$'\033[31m'aaaaaa* ]] \
    || fail "style not restored after the span: $(screen_raw 0)"
}

@test "dybatpho::screen_put inside a bordered row keeps every run in place" {
  # The right border is on the row before anything inside it, which is the
  # case every panel puts its content through: each span lands between runs
  # that are already there rather than after the last one.
  dybatpho::screen_put 0 0 "|" "2"
  dybatpho::screen_put 0 39 "|" "2"
  dybatpho::screen_put 0 5 "bb" "32"
  dybatpho::screen_put 0 2 "aa" "31"
  dybatpho::screen_put 0 4 "cccc" "33"
  local blank
  printf -v blank '%*s' 31 ""
  assert_equal "$(screen_raw 0)" \
    $'\033[2m|\033[0m \033[31maa\033[33mcccc\033[0m'"${blank}"$'\033[2m|\033[0m'
}

@test "dybatpho::screen_put keeps wide characters aligned to the grid" {
  dybatpho::screen_put 0 0 "hello" "0"
  dybatpho::screen_put 0 6 "世界" "0"
  local row columns
  row="$(screen_row 0)"
  assert_equal "${row:0:8}" "hello 世界"
  # The row still occupies exactly the width of the terminal: a two-column
  # glyph written as one character is how a screen ends up one column short.
  dybatpho::screen_width columns "${row}"
  assert_equal "${columns}" 40
}

@test "dybatpho::screen_put clips at the edges and ignores off-screen writes" {
  dybatpho::screen_put 0 38 "abcdef" "0"
  local row columns
  row="$(screen_row 0)"
  dybatpho::screen_width columns "${row}"
  assert_equal "${columns}" 40
  assert_equal "${row:38:2}" "ab"

  # Off the buffer entirely: these must do nothing rather than grow it.
  dybatpho::screen_put 99 0 "below" "0"
  dybatpho::screen_put -5 0 "above" "0"
  assert_equal "${DYBATPHO_SCREEN_HEIGHT}" 12
}

# =============================================================================
# dybatpho::screen_flush
# =============================================================================

@test "dybatpho::screen_flush writes only the rows that changed" {
  local output_file="${BATS_TEST_TMPDIR}/frame"
  exec {fd}> "${output_file}"
  __dybatpho_screen_fd="${fd}"

  dybatpho::screen_put 0 0 "first" "0"
  dybatpho::screen_flush
  # A frame drawn again unchanged must send nothing at all.
  local before after
  before="$(wc -c < "${output_file}")"
  dybatpho::screen_flush
  after="$(wc -c < "${output_file}")"
  assert_equal "${before}" "${after}"

  dybatpho::screen_put 3 0 "second" "0"
  dybatpho::screen_flush
  after="$(wc -c < "${output_file}")"
  [[ "${after}" -gt "${before}" ]] || fail "a changed row was not written"

  exec {fd}>&-
  __dybatpho_screen_fd=""
  # Only the changed row travelled, not the whole screen.
  local sent
  sent="$(LC_ALL=C grep -ao 'second' "${output_file}" | wc -l | tr -d ' ')"
  assert_equal "${sent}" 1
}

# =============================================================================
# dybatpho::screen_block, dybatpho::screen_popup
# =============================================================================

@test "dybatpho::screen_block draws a titled border and reports the inner area" {
  dybatpho::screen_block "0 0 20 4" title:"Pods" border:rounded
  assert_equal "$(screen_row 0)" "╭ Pods ────────────╮                    "
  assert_equal "$(screen_row 3)" "╰──────────────────╯                    "
  assert_equal "${DYBATPHO_SCREEN_INNER}" "1 1 18 2"
}

@test "dybatpho::screen_block with no border leaves the whole rectangle inside" {
  dybatpho::screen_block "0 0 10 3" border:none
  assert_equal "${DYBATPHO_SCREEN_INNER}" "0 0 10 3"
  assert_equal "$(screen_row 0)" "                                        "
}

@test "dybatpho::screen_popup erases whatever it is drawn over" {
  dybatpho::screen_put 0 0 "background text that runs the whole way" "0"
  dybatpho::screen_popup "2 0 12 3" title:"Hi"
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:14}" "ba┌ Hi ──────┐"
}

# =============================================================================
# dybatpho::screen_text
# =============================================================================

@test "dybatpho::screen_text wraps on word boundaries" {
  dybatpho::screen_text "0 0 10 3" "hello world again"
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "hello     "
  row="$(screen_row 1)"
  assert_equal "${row:0:10}" "world     "
}

@test "dybatpho::screen_text aligns left, centre and right" {
  dybatpho::screen_text "0 0 11 1" "hi" align:center
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:11}" "    hi     "
  dybatpho::screen_clear
  dybatpho::screen_text "0 0 11 1" "hi" align:right
  row="$(screen_row 0)"
  assert_equal "${row:0:11}" "         hi"
}

@test "dybatpho::screen_text with wrap off cuts a long line instead of folding it" {
  dybatpho::screen_text "0 0 10 3" "hello world again" wrap:false
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "hello worl"
  row="$(screen_row 1)"
  assert_equal "${row:0:10}" "          "
}

# =============================================================================
# dybatpho::screen_list
# =============================================================================

@test "dybatpho::screen_list marks the selected item" {
  local -a items=(alpha beta gamma delta epsilon)
  dybatpho::screen_list "0 0 20 3" items selected:0
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:12}" "❯ alpha     "
  row="$(screen_row 1)"
  assert_equal "${row:0:12}" "  beta      "
  assert_equal "${DYBATPHO_SCREEN_OFFSET}" 0
}

@test "dybatpho::screen_list scrolls to keep the selection on screen" {
  # The caller only tracks which item is selected; working out the offset that
  # keeps it visible is the widget's job.
  local -a items=(alpha beta gamma delta epsilon)
  dybatpho::screen_list "0 0 20 3" items selected:4
  assert_equal "${DYBATPHO_SCREEN_OFFSET}" 2
  local row
  row="$(screen_row 2)"
  assert_equal "${row:0:12}" "❯ epsilon   "
}

@test "dybatpho::screen_list reads an array whose name collides with its own locals" {
  # The widget binds a nameref to a name the caller chose, so a caller array
  # called `width` or `count` must still be the one that is read.
  local -a width=(first second)
  dybatpho::screen_list "0 0 20 2" width selected:1
  local row
  row="$(screen_row 1)"
  assert_equal "${row:0:10}" "❯ second  "
}

# =============================================================================
# dybatpho::screen_table
# =============================================================================

@test "dybatpho::screen_table draws a header and the rows under it" {
  local -a rows=("api|run|3" "worker|idle|1")
  dybatpho::screen_table "0 0 24 4" rows header:"NAME|STATE|N" widths:"10,8,6" selected:1
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:24}" "NAME      STATE   N     "
  row="$(screen_row 1)"
  assert_equal "${row:0:24}" "api       run     3     "
  row="$(screen_row 2)"
  assert_equal "${row:0:24}" "worker    idle    1     "
}

# =============================================================================
# dybatpho::screen_gauge, dybatpho::screen_scrollbar, dybatpho::screen_tabs
# =============================================================================

@test "dybatpho::screen_gauge fills in proportion to its value" {
  dybatpho::screen_gauge "0 0 10 1" 5 10 label:""
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "█████░░░░░"
  dybatpho::screen_clear
  dybatpho::screen_gauge "0 0 10 1" 10 10 label:""
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "██████████"
}

@test "dybatpho::screen_gauge labels itself with a percentage by default" {
  dybatpho::screen_gauge "0 0 20 1" 1 4
  local row
  row="$(screen_row 0)"
  [[ "${row}" == *"25%"* ]] || fail "no percentage drawn: ${row}"
}

@test "dybatpho::screen_scrollbar shows a thumb only when there is more than fits" {
  dybatpho::screen_scrollbar "0 0 1 4" 0 8
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:1}" "█"
  row="$(screen_row 3)"
  assert_equal "${row:0:1}" "│"

  dybatpho::screen_clear
  dybatpho::screen_scrollbar "0 0 1 4" 0 2
  row="$(screen_row 0)"
  assert_equal "${row:0:1}" " "
}

@test "dybatpho::screen_tabs draws every tab with the active one marked" {
  local -a names=(One Two)
  dybatpho::screen_tabs "0 0 30 1" names active:1
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:15}" " One  │  Two   "
}

# =============================================================================
# dybatpho::screen_sparkline, dybatpho::screen_barchart, dybatpho::screen_chart
# =============================================================================

@test "dybatpho::screen_sparkline scales the series to the block ladder" {
  local -a samples=(0 4 8)
  dybatpho::screen_sparkline "0 0 10 1" samples
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:3}" "▁▄█"
}

@test "dybatpho::screen_sparkline keeps the tail of a series that is too long" {
  local -a samples=(8 8 8 0 4 8)
  dybatpho::screen_sparkline "0 0 3 1" samples
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:3}" "▁▄█"
}

@test "dybatpho::screen_barchart draws labelled bars with partial blocks" {
  local -a values=(10 5) labels=(api cron)
  dybatpho::screen_barchart "0 0 12 2" values labels:labels
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:12}" "api  ███████"
  # Half of seven columns is three and a half, and the half is drawn rather
  # than rounded away.
  row="$(screen_row 1)"
  assert_equal "${row:0:9}" "cron ███▌"
}

@test "dybatpho::screen_chart plots a continuous line in Braille" {
  local -a rising=(0 1 2 3 4 5 6 7)
  dybatpho::screen_chart "0 0 20 4" rising

  # A line chart that leaves gaps between its samples reads as scattered
  # specks, so every column of the plot must carry at least one dot.
  local column row_index found gaps=0 row
  for ((column = 0; column < 20; column++)); do
    found=0
    for ((row_index = 0; row_index < 4; row_index++)); do
      row="$(screen_row "${row_index}")"
      [[ "${row:column:1}" != " " ]] && found=1
    done
    ((found)) || gaps=$((gaps + 1))
  done
  assert_equal "${gaps}" 0
}

# =============================================================================
# dybatpho::screen_supported, dybatpho::screen_begin, dybatpho::screen_end,
# dybatpho::screen_event
# =============================================================================

@test "dybatpho::screen_end is safe when no screen was ever taken over" {
  DYBATPHO_SCREEN_ACTIVE=false
  run_traced dybatpho::screen_end
  assert_success
  assert_output ""
}

@test "dybatpho::screen_begin refuses when there is no terminal to take over" {
  # The suite has no controlling terminal of its own, so this is the path a
  # scheduled job takes: it must report the refusal rather than hang.
  if [[ -e /dev/tty ]] && (: < /dev/tty) 2> /dev/null; then
    skip "this runner has a controlling terminal"
  fi
  run_traced dybatpho::screen_begin
  assert_failure
}

@test "dybatpho::screen_event reports a resize before it reports a key" {
  # A resize seen while the last frame was drawing must not sit behind a
  # keystroke that has not been typed yet.
  __dybatpho_screen_resized=true
  local event
  dybatpho::screen_event event
  assert_equal "${event}" "resize"
}

@test "dybatpho::screen_event reports end of input and a timeout differently" {
  local event
  dybatpho::screen_event event < /dev/null
  assert_equal "${event}" "eof"

  # Nothing to read and a deadline: that is a timeout, and it is not an end of
  # input, because an application polls with one and stops on the other.
  local status=0
  dybatpho::screen_event event 0.05 < <(sleep 5) || status=$?
  assert_equal "${status}" 1
  assert_equal "${event}" "timeout"
}

@test "dybatpho::screen_pending reports a waiting event without consuming it" {
  local event status=0
  {
    dybatpho::screen_pending || status=$?
    dybatpho::screen_event event
  } <<< "j"
  assert_equal "${status}" 0
  assert_equal "${event}" "char:j"

  status=0
  dybatpho::screen_pending < <(sleep 5) || status=$?
  assert_equal "${status}" 1

  # A resize waiting to be reported counts, and is still there afterwards.
  __dybatpho_screen_resized=true
  dybatpho::screen_pending
  assert_equal "${__dybatpho_screen_resized}" true
}

@test "dybatpho::screen_event names ordinary keys" {
  local event
  dybatpho::screen_event event <<< "q"
  assert_equal "${event}" "char:q"
  dybatpho::screen_event event < <(printf ' ')
  assert_equal "${event}" "space"
  dybatpho::screen_event event < <(printf '\t')
  assert_equal "${event}" "tab"
  dybatpho::screen_event event < <(printf '\n')
  assert_equal "${event}" "enter"
}

@test "dybatpho::screen_event decodes arrows, navigation keys and a mouse click" {
  local event
  dybatpho::screen_event event < <(printf '\033[A')
  assert_equal "${event}" "up"
  dybatpho::screen_event event < <(printf '\033[B')
  assert_equal "${event}" "down"
  dybatpho::screen_event event < <(printf '\033[5~')
  assert_equal "${event}" "pageup"
  dybatpho::screen_event event < <(printf '\033OH')
  assert_equal "${event}" "home"
  # A bare escape is the cancel key, and it must not swallow the next key
  # waiting for a sequence that is never coming.
  dybatpho::screen_event event < <(printf '\033')
  assert_equal "${event}" "escape"

  dybatpho::screen_event event < <(printf '\033[<0;10;5M')
  assert_equal "${event}" "mouse:left"
  # The report is one-based and every rectangle here is zero-based.
  assert_equal "${DYBATPHO_SCREEN_MOUSE_COLUMN}" 9
  assert_equal "${DYBATPHO_SCREEN_MOUSE_ROW}" 4
}

# =============================================================================
# dybatpho::screen_end keeps stderr
# =============================================================================

# Take over a stand-in terminal and give it back, then write to stderr.
_end_then_write_stderr() {
  exec {__dybatpho_screen_fd}> /dev/null
  __dybatpho_screen_saved_stty=""
  DYBATPHO_SCREEN_ACTIVE=true
  dybatpho::screen_end
  printf 'still on stderr\n' >&2
}

@test "dybatpho::screen_end leaves the script's stderr working" {
  run _end_then_write_stderr
  assert_success
  assert_output --partial "still on stderr"
  assert_equal "${DYBATPHO_SCREEN_ACTIVE}" "false"
}

# =============================================================================
# dybatpho::screen_block focus, dybatpho::screen_tabs styles
# =============================================================================

@test "dybatpho::screen_block draws a focused border in its own style" {
  DYBATPHO_SCREEN_STYLE_BORDER="2" DYBATPHO_SCREEN_STYLE_FOCUS="35"
  dybatpho::screen_block "0 0 10 3" focus:true
  [[ "$(screen_raw 0)" == *$'\033[35m┌'* ]] || fail "focused border not styled: $(screen_raw 0)"
  dybatpho::screen_block "0 0 10 3"
  [[ "$(screen_raw 0)" == *$'\033[2m┌'* ]] || fail "plain border not styled: $(screen_raw 0)"
  # An explicit style still wins over the focus.
  dybatpho::screen_block "0 0 10 3" focus:true style:"36"
  [[ "$(screen_raw 0)" == *$'\033[36m┌'* ]] || fail "explicit style lost: $(screen_raw 0)"
}

@test "dybatpho::screen_tabs takes its active and divider styles from the theme" {
  local -a names=(One Two)
  DYBATPHO_SCREEN_STYLE_TAB_ACTIVE="1;35" DYBATPHO_SCREEN_STYLE_DIM="90"
  dybatpho::screen_tabs "0 0 40 1" names active:1
  [[ "$(screen_raw 0)" == *$'\033[90m │ \033[1;35m Two '* ]] || fail "theme not used: $(screen_raw 0)"
  dybatpho::screen_tabs "0 0 40 1" names active:0 divider_style:"33"
  [[ "$(screen_raw 0)" == *$'\033[33m │ '* ]] || fail "divider_style ignored: $(screen_raw 0)"
}

# =============================================================================
# dybatpho::screen_spans, dybatpho::screen_ansi, dybatpho::screen_keybar
# =============================================================================

@test "dybatpho::screen_spans draws styled pieces side by side and cuts them to the width" {
  dybatpho::screen_spans 0 0 12 "" "✔ " "32" "ripgrep" "1" " 12s" "2"
  assert_equal "$(screen_row 0)" "✔ ripgrep 12                            "
  [[ "$(screen_raw 0)" == *$'\033[32m✔ \033[1mripgrep\033[2m 12'* ]] \
    || fail "pieces not styled apart: $(screen_raw 0)"
}

@test "dybatpho::screen_spans fills the width with a background" {
  dybatpho::screen_spans 1 2 10 "44" "ab" "1"
  assert_equal "$(screen_row 1)" "  ab                                    "
  [[ "$(screen_raw 1)" == *$'\033[44;1mab\033[44m        \033[0m'* ]] \
    || fail "background not filled: $(screen_raw 1)"
}

@test "dybatpho::screen_ansi keeps the colours a line was written with" {
  dybatpho::screen_ansi 0 0 40 $'plain \033[1;31mred\033[0m \033[32mgreen\033[1m bold'
  assert_equal "$(screen_row 0 | sed -E 's/ +$//')" "plain red green bold"
  [[ "$(screen_raw 0)" == *$'\033[1;31mred\033[0m \033[32mgreen\033[32;1m bold'* ]] \
    || fail "colours lost: $(screen_raw 0)"
}

@test "dybatpho::screen_ansi drops sequences that are not colours" {
  dybatpho::screen_ansi 0 0 40 $'a\033[2Kb\033[?25lc\033[10;3Hd'
  assert_equal "$(screen_row 0 | sed -E 's/ +$//')" "abcd"
}

@test "dybatpho::screen_keybar draws keys and what they do across the row" {
  DYBATPHO_SCREEN_STYLE_KEYBAR="7" DYBATPHO_SCREEN_STYLE_KEY="1"
  dybatpho::screen_keybar "0 11 40 1" "q" "quit" "space" "pick"
  assert_equal "$(screen_row 11)" " q quit  space pick                     "
  [[ "$(screen_raw 11)" == *$'\033[7;1m q\033[7m quit '* ]] || fail "key not styled: $(screen_raw 11)"
  # A theme whose bar sets a foreground does not take the key's colour away.
  DYBATPHO_SCREEN_STYLE_KEYBAR="37;44" DYBATPHO_SCREEN_STYLE_KEY="1;35"
  dybatpho::screen_keybar "0 11 40 1" "q" "quit"
  [[ "$(screen_raw 11)" == *$'\033[37;44;1;35m q\033[37;44m quit '* ]] || fail "key colour lost: $(screen_raw 11)"
}

# =============================================================================
# dybatpho::screen_theme
# =============================================================================

@test "dybatpho::screen_theme sets every style from a palette" {
  # The suite has no terminal, so colour has to be asked for; that is what
  # `FORCE_COLOR` is now for.
  unset NO_COLOR
  export FORCE_COLOR=1
  dybatpho::screen_theme dusk
  assert_equal "${DYBATPHO_SCREEN_STYLE_FOCUS}" "38;5;141"
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "1;38;5;114"
  dybatpho::screen_theme default
  assert_equal "${DYBATPHO_SCREEN_STYLE_SELECTED}" "1;7"
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "32"
}

@test "dybatpho::screen_theme falls back to mono when colour is not wanted" {
  export NO_COLOR=1
  dybatpho::screen_theme dusk
  local name
  for name in "${!DYBATPHO_SCREEN_STYLE_@}"; do
    [[ "${!name}" != *"38;5"* && "${!name}" != *"48;5"* ]] || fail "${name} has a colour: ${!name}"
  done

  # `default` is downgraded too. It used to keep its own three colours under
  # `NO_COLOR`, which made the answer depend on which theme was asked for.
  dybatpho::screen_theme default
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "1"

  # A terminal that cannot render colour reaches `mono` as well. `TERM` is
  # used rather than the absence of a tty: the suite'"'"'s own stdout may or may
  # not be one, and an assertion must not depend on how it was launched.
  unset NO_COLOR
  export TERM=dumb
  dybatpho::screen_theme dusk
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "1"
}

@test "dybatpho::screen_theme refuses an unknown theme and changes nothing" {
  # An unknown name must still be rejected rather than quietly downgraded to
  # `mono` along with the themes that are known.
  export FORCE_COLOR=1
  unset NO_COLOR
  dybatpho::screen_theme default
  run dybatpho::screen_theme neon
  assert_failure
  assert_output --partial "Unknown theme 'neon'"
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "32"
}
