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

@test "dybatpho::screen_put places runs by column on a row of wide glyphs and marks" {
  # Each wide glyph pushes the columns after it one index to the left, and a
  # combining mark pulls them one back; the styles have to follow both.
  dybatpho::screen_put 0 0 "世界" "31"
  dybatpho::screen_put 0 4 $'e\u0301x' "32"
  dybatpho::screen_put 0 6 "ok" "33"
  dybatpho::screen_put 0 8 "🎉x" "34"
  dybatpho::screen_put 0 39 "|" "2"
  local blank
  printf -v blank '%*s' 28 ""
  assert_equal "$(screen_raw 0)" \
    $'\033[31m世界\033[32me\u0301x\033[33mok\033[34m🎉x\033[0m'"${blank}"$'\033[2m|\033[0m'
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

@test "dybatpho::screen_gauge keeps its glyphs whole under the C locale" {
  # Under `C` Bash slices by byte, and a bar cut into halves split `█` apart.
  LC_ALL=C dybatpho::screen_gauge "0 0 10 1" 5 10 label:""
  local row
  row="$(screen_row 0)"
  assert_equal "${row}" "█████░░░░░                              "
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

# @description Draw every widget that reads an array by name from arrays
#   called `$1`, and print the rows they drew.
draw_named() {
  dybatpho::screen_clear
  local -n named="$1"
  named=("a,b" "1,2")
  dybatpho::screen_table "0 0 20 3" "$1" header:true delimiter:,
  named=(One Two)
  dybatpho::screen_tabs "0 3 20 1" "$1" active:1
  named=(1 5 3 8)
  dybatpho::screen_sparkline "0 4 10 1" "$1"
  dybatpho::screen_chart "0 5 10 2" "$1"
  dybatpho::screen_barchart "0 7 20 3" "$1"
  local -a values=(1 5 3)
  named=(a b c)
  dybatpho::screen_barchart "20 7 20 3" values "labels:$1"
  local row
  for ((row = 0; row < 10; row++)); do
    screen_row "${row}"
    printf '\n'
  done
}

@test "rectangles, layouts and widgets work whatever the caller named its variables" {
  # Each of these writes or reads through a name the caller chose, so a name
  # shared with one of their own locals lost the result or drew nothing.
  local expected inner center name
  dybatpho::screen_rect_inner inner "0 0 10 6" 1
  dybatpho::screen_rect_center center "0 0 10 10" 4 2
  local -a parts=()
  dybatpho::screen_layout parts vertical "0 0 100 30" length:3 fill:1
  expected="$(draw_named zz_safe)"
  [[ "${expected}" == *One*Two* ]]
  for name in x y width height margin inner_width inner_height want_width \
    rect options rows_var result_var direction sizes index total offset; do
    unset "${name}"
    dybatpho::screen_rect_inner "${name}" "0 0 10 6" 1
    assert_equal "${!name}" "${inner}"
    dybatpho::screen_rect_center "${name}" "0 0 10 10" 4 2
    assert_equal "${!name}" "${center}"
    unset "${name}"
    local -a "${name}=()"
    dybatpho::screen_layout "${name}" vertical "0 0 100 30" length:3 fill:1
    local -n laid="${name}"
    assert_equal "${laid[*]}" "${parts[*]}"
    unset -n laid
    assert_equal "$(draw_named "${name}")" "${expected}"
  done
}

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

@test "dybatpho::screen_begin says so when the system has no terminal device" {
  # A container started without one has no `/dev/tty` at all.
  local __DYBATPHO_SCREEN_TTY="${BATS_TEST_TMPDIR}/no-such-tty"
  run_traced --separate-stderr dybatpho::screen_begin
  assert_failure
  assert_stderr --partial "dybatpho::screen_begin: No terminal to draw on"
  assert_equal "${DYBATPHO_SCREEN_ACTIVE}" "false"
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

@test "dybatpho::screen_theme sets the Catppuccin flavours in 24-bit colour" {
  unset NO_COLOR
  export FORCE_COLOR=1
  dybatpho::screen_theme catppuccin-mocha
  # mauve #cba6f7, base #1e1e2e
  assert_equal "${DYBATPHO_SCREEN_STYLE_FOCUS}" "38;2;203;166;247"
  assert_equal "${DYBATPHO_SCREEN_STYLE_SELECTED}" "1;38;2;30;30;46;48;2;203;166;247"
  # green #a6e3a1
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "1;38;2;166;227;161"
  dybatpho::screen_theme catppuccin-latte
  # red #d20f39
  assert_equal "${DYBATPHO_SCREEN_STYLE_ERROR}" "1;38;2;210;15;57"
  dybatpho::screen_theme catppuccin-frappe
  # mantle #292c3c behind subtext0 #a5adce
  assert_equal "${DYBATPHO_SCREEN_STYLE_KEYBAR}" "38;2;165;173;206;48;2;41;44;60"
  dybatpho::screen_theme catppuccin-macchiato
  # yellow #eed49f
  assert_equal "${DYBATPHO_SCREEN_STYLE_WARN}" "38;2;238;212;159"
}

@test "dybatpho::screen_theme falls back to mono when colour is not wanted" {
  export NO_COLOR=1
  local theme name
  for theme in dusk catppuccin-latte catppuccin-frappe catppuccin-macchiato catppuccin-mocha; do
    dybatpho::screen_theme default
    dybatpho::screen_theme "${theme}"
    for name in "${!DYBATPHO_SCREEN_STYLE_@}"; do
      [[ "${!name}" != *"38;"* && "${!name}" != *"48;"* ]] || fail "${theme}: ${name} has a colour: ${!name}"
    done
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
  # Neither an unknown flavour, nor NO_COLOR turning it into a valid theme.
  NO_COLOR=1 run dybatpho::screen_theme catppuccin-espresso
  assert_failure
  assert_equal "${DYBATPHO_SCREEN_STYLE_OK}" "32"
}

@test "dybatpho::screen_event reads the carriage return raw mode delivers as enter" {
  local event
  dybatpho::screen_event event < <(printf '\r')
  assert_equal "${event}" "enter"
  dybatpho::screen_event event < <(printf '\n')
  assert_equal "${event}" "enter"
}

@test "dybatpho::screen_text never globs a word of the text" {
  local dir="${BATS_TEST_TMPDIR}/globbed"
  mkdir "${dir}"
  : > "${dir}/a.sh"
  : > "${dir}/b.sh"
  cd "${dir}"
  dybatpho::screen_text "0 0 12 3" 'press * or *.sh to go'
  cd - > /dev/null
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:12}" "press * or  "
  row="$(screen_row 1)"
  assert_equal "${row:0:12}" "*.sh to go  "
}

@test "__dybatpho_screen_braille_table has 256 glyphs in the C locale too" {
  # From a file, not `bash -c`: a `-c` shell has an empty `BASH_SOURCE`, which
  # the kcov hook expands on every command once `init.sh` turns on `set -u`.
  local script="${BATS_TEST_TMPDIR}/braille.sh"
  # shellcheck disable=SC2016 # expanded by the child shell
  printf '%s\n' 'LC_ALL=C' ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules screen" \
    '__dybatpho_screen_braille_table' \
    'printf "%s %s" "${#__dybatpho_screen_braille[@]}" "${__dybatpho_screen_braille[255]}"' > "${script}"
  run_traced bash "${script}"
  assert_output "256 ⣿"
}

# =============================================================================
# edge paths of the drawing helpers
# =============================================================================

@test "__dybatpho_screen_truncate_into cuts by column and never halves a wide glyph" {
  local cut
  __dybatpho_screen_truncate_into cut "abc" 0
  assert_equal "${cut}" ""
  __dybatpho_screen_truncate_into cut "日本語" 3
  assert_equal "${cut}" "日"
  __dybatpho_screen_truncate_into cut "日本語" 4
  assert_equal "${cut}" "日本"
}

@test "__dybatpho_screen_index_into answers a plain row with the column itself" {
  dybatpho::screen_put 0 0 "plain" "0"
  local index
  __dybatpho_screen_index_into index 0 3
  assert_equal "${index}" 3
}

@test "dybatpho::screen_put drops the part of the text left of the screen" {
  dybatpho::screen_put 0 -2 "abcdef" "0"
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:4}" "cdef"
}

@test "dybatpho::screen_flush writes to stderr when no terminal was opened" {
  __dybatpho_screen_fd=""
  dybatpho::screen_put 0 0 "frame" "0"
  run_traced -0 --separate-stderr dybatpho::screen_flush
  assert_output ""
  [[ "${stderr}" == *frame* ]] || fail "frame not on stderr: ${stderr}"
}

@test "dybatpho::screen_layout takes a deficit from several parts at the end" {
  local -a parts=()
  dybatpho::screen_layout parts vertical "0 0 100 3" length:4 length:1
  assert_equal "${parts[0]}" "0 0 100 3"
  assert_equal "${parts[1]}" "0 3 100 0"
}

@test "dybatpho::screen_layout names an unknown constraint and stops" {
  # A child shell, since the refusal ends it; from a file, not `bash -c`.
  local script="${BATS_TEST_TMPDIR}/layout.sh"
  cat > "${script}" << 'SCRIPT'
. "${1}/init.sh" --modules screen
declare -a parts=()
dybatpho::screen_layout parts vertical "0 0 10 10" wider:2
SCRIPT
  run_traced -1 --separate-stderr bash "${script}" "${DYBATPHO_DIR}"
  assert_stderr --partial "Unknown constraint 'wider:2', expected length:"
}

@test "dybatpho::screen_event reports a resize the window signal noted" {
  __dybatpho_screen_resized=false
  __dybatpho_screen_on_resize
  local event
  dybatpho::screen_event event < /dev/null
  assert_equal "${event}" "resize"
}

@test "dybatpho::screen_event names every mouse button and a release" {
  local event
  dybatpho::screen_event event < <(printf '\033[<0;3;4m')
  assert_equal "${event}" "mouse:release"
  dybatpho::screen_event event < <(printf '\033[<1;3;4M')
  assert_equal "${event}" "mouse:middle"
  dybatpho::screen_event event < <(printf '\033[<2;3;4M')
  assert_equal "${event}" "mouse:right"
  dybatpho::screen_event event < <(printf '\033[<64;3;4M')
  assert_equal "${event}" "mouse:scrollup"
  dybatpho::screen_event event < <(printf '\033[<65;3;4M')
  assert_equal "${event}" "mouse:scrolldown"
  dybatpho::screen_event event < <(printf '\033[<35;3;4M')
  assert_equal "${event}" "mouse:other"
}

@test "dybatpho::screen_block draws double and thick borders and centres a title" {
  local row
  dybatpho::screen_block "0 0 10 3" border:double
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" "╔════════╗"
  dybatpho::screen_block "0 3 10 3" border:thick title:"Hi" align:center
  row="$(screen_row 3)"
  assert_equal "${row:0:10}" "┏━━ Hi ━━┓"
  row="$(screen_row 5)"
  assert_equal "${row:0:10}" "┗━━━━━━━━┛"
}

@test "dybatpho::screen_list keeps a scrolled offset inside the list" {
  local -a items=(a b c d e)
  dybatpho::screen_list "0 0 10 2" items offset:9
  assert_equal "${DYBATPHO_SCREEN_OFFSET}" 3
}

@test "dybatpho::screen_chart honours min: given without max:" {
  # A flat series at 10 sits at the top of a 0-to-10 scale; with `min:` dropped
  # the scale shrank to 10-to-11 and the line fell to the bottom row.
  # shellcheck disable=SC2034 # read by name by the widget
  local -a flat=(10 10 10 10)
  dybatpho::screen_chart "0 0 2 4" flat min:0
  local top bottom
  top="$(screen_row 0)"
  bottom="$(screen_row 3)"
  [[ "${top:0:2}" != "  " ]] || fail "the line is not on the top row"
  assert_equal "${bottom:0:2}" "  "
}

@test "dybatpho::screen_chart draws samples that share a column" {
  local -a series=(0 5 9)
  dybatpho::screen_chart "0 0 1 2" series
  local row
  row="$(screen_row 0)"
  [[ "${row:0:1}" != " " ]] || fail "nothing plotted: ${row}"
}

@test "dybatpho::screen_ansi reads a reset that carries a colour and skips a broken sequence" {
  dybatpho::screen_ansi 0 0 40 $'\033[0;31mred\033[~x'
  assert_equal "$(screen_row 0 | sed -E 's/ +$//')" "red~x"
  [[ "$(screen_raw 0)" == *$'\033[31mred'* ]] || fail "colour lost: $(screen_raw 0)"
}

# =============================================================================
# regressions
# =============================================================================

@test "dybatpho::screen_put blanks what is left of a wide glyph it half covers" {
  # Drawing over one column of `世` kept the glyph whole, so the row grew a
  # column and everything right of it shifted off the edge.
  local row columns
  dybatpho::screen_put 0 4 "世界" "0"
  dybatpho::screen_put 0 5 "x" "0"
  row="$(screen_row 0)"
  dybatpho::screen_width columns "${row}"
  assert_equal "${columns}" 40
  assert_equal "${row:0:7}" "     x界"

  dybatpho::screen_put 1 4 "世界" "0"
  dybatpho::screen_put 1 4 "y" "0"
  row="$(screen_row 1)"
  dybatpho::screen_width columns "${row}"
  assert_equal "${columns}" 40
  assert_equal "${row:0:7}" "    y 界"
}

@test "dybatpho::screen_barchart keeps a value above max: inside its rectangle" {
  local -a values=(20)
  dybatpho::screen_barchart "0 0 6 1" values max:10
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:7}" "██████ "
}

@test "dybatpho::screen_layout never grows a max: part to absorb rounding" {
  local -a parts=()
  dybatpho::screen_layout parts horizontal "0 0 10 1" length:3 max:2
  assert_equal "${parts[0]}" "0 0 8 1"
  assert_equal "${parts[1]}" "8 0 2 1"
  # With nothing flexible the last part still takes the rounding, so the parts
  # tile the rectangle.
  dybatpho::screen_layout parts horizontal "0 0 5 1" percent:50 percent:50
  assert_equal "${parts[1]}" "2 0 3 1"
}

@test "dybatpho::screen_tabs cuts the tab that reaches the edge of its rectangle" {
  # shellcheck disable=SC2034 # read by name by the widget
  local -a names=(Overview Logs)
  dybatpho::screen_tabs "0 0 8 1" names active:0
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:10}" " Overvie  "
}

@test "dybatpho::screen_table splits on a delimiter of several characters" {
  local -a rows=("a::b")
  dybatpho::screen_table "0 0 20 1" rows delimiter:"::"
  local row
  row="$(screen_row 0)"
  assert_equal "${row:0:20}" "a         b         "
}

# @description Run a script on a pseudo-terminal, in the BSD form of `script` or
#   in the util-linux and BusyBox one, skipping the test when there is none.
screen_on_pty() {
  if script -q /dev/null true < /dev/null > /dev/null 2>&1; then
    script -q /dev/null bash "$1" < /dev/null > /dev/null 2>&1 || true
  elif script -qc true /dev/null < /dev/null > /dev/null 2>&1; then
    script -qc "bash '$1'" /dev/null < /dev/null > /dev/null 2>&1 || true
  else
    skip "no pseudo-terminal to test with"
  fi
}

@test "dybatpho::screen_begin measures the terminal it draws on, not stdout" {
  # With stdout and stderr both redirected, the size fell back to 80x24 while
  # the frame was still drawn on a terminal of another size.
  # The application runs with both streams redirected, the way a caller that
  # captures its output runs it; only the terminal is left to measure.
  local app="${BATS_TEST_TMPDIR}/size-app.sh" script="${BATS_TEST_TMPDIR}/size.sh"
  local result="${BATS_TEST_TMPDIR}/size.out"
  cat > "${app}" << SCRIPT
unset COLUMNS LINES
. "${DYBATPHO_DIR}/init.sh" --modules screen
dybatpho::screen_begin || exit 0
size="\${DYBATPHO_SCREEN_WIDTH}x\${DYBATPHO_SCREEN_HEIGHT}"
dybatpho::screen_end
printf '%s\n' "\${size}" > "${result}"
SCRIPT
  cat > "${script}" << SCRIPT
stty cols 123 rows 41 2> /dev/null || exit 0
bash "${app}" > /dev/null 2>&1
SCRIPT
  screen_on_pty "${script}"
  [[ -s "${result}" ]] || skip "no pseudo-terminal to test with"
  assert_equal "$(< "${result}")" "123x41"
}

@test "dybatpho::screen_begin gives the terminal back and still dies on TERM" {
  # Its handler on TERM replaced the signal's default, so the screen was
  # restored and the script then carried on as if nothing had happened.
  # The application is a child of the script on the terminal, so its status can
  # be recorded; both are files, not `bash -c`, for the kcov hook.
  local app="${BATS_TEST_TMPDIR}/app.sh" script="${BATS_TEST_TMPDIR}/signal.sh"
  local result="${BATS_TEST_TMPDIR}/signal.out"
  cat > "${app}" << SCRIPT
. "${DYBATPHO_DIR}/init.sh" --modules screen
dybatpho::screen_begin || exit 0
kill -s TERM "\${BASHPID}"
echo "still running" >> "${result}"
SCRIPT
  cat > "${script}" << SCRIPT
bash "${app}" 2> /dev/null
printf 'status=%s\n' "\$?" >> "${result}"
SCRIPT
  screen_on_pty "${script}"
  [[ -s "${result}" ]] || skip "no pseudo-terminal to test with"
  assert_equal "$(< "${result}")" "status=143"
}

@test "screen charts read values with a leading zero in base ten" {
  # Arithmetic read `08` as an invalid octal number and `010` as eight.
  local -a plain=(0 4 8 10) padded=(00 04 08 010)
  local chart row
  for chart in sparkline barchart chart; do
    dybatpho::screen_clear
    "dybatpho::screen_${chart}" "0 0 20 4" plain
    "dybatpho::screen_${chart}" "0 4 20 4" padded
    for row in 0 1 2 3; do
      assert_equal "$(screen_row "$((row + 4))")" "$(screen_row "${row}")"
    done
  done
}

@test "screen widgets read numeric arguments and options with a leading zero in base ten" {
  # Arithmetic read `08` as an invalid octal number and `010` as eight, and a
  # value such as `a[$(cmd)]` ran the command.
  local -a parts=() expected=()
  dybatpho::screen_layout expected vertical "0 0 20 40" length:8 percent:10 ratio:1/8 min:9 max:8 fill:1
  dybatpho::screen_layout parts vertical "0 0 20 40" length:08 percent:010 ratio:1/08 min:09 max:08 fill:01
  assert_equal "${parts[*]}" "${expected[*]}"

  local -a items=(a b c d e f g h i j k) values=(3 9) tabs=(0 1 2 3 4 5 6 7 8 9)
  local -a rows=(r0\|x r1\|x r2\|x r3\|x r4\|x r5\|x r6\|x r7\|x r8\|x r9\|x r10\|x)
  local -a plain=() padded=()
  # Compared with their styles, which is all `selected:` and `active:` change.
  plain=("list items selected:9 offset:8" "table rows selected:9" "table rows offset:8 widths:3,10"
    "tabs tabs active:9 divider:|" "barchart values max:10 label_width:8" "sparkline values max:10"
    "chart values max:10 min:8" "gauge 9 10" "scrollbar 8 9")
  padded=("list items selected:09 offset:08" "table rows selected:09" "table rows offset:08 widths:03,010"
    "tabs tabs active:09 divider:|" "barchart values max:010 label_width:08" "sparkline values max:010"
    "chart values max:010 min:08" "gauge 09 010" "scrollbar 08 09")
  local index row widget
  local -a words=()
  for index in "${!plain[@]}"; do
    dybatpho::screen_clear
    read -r -a words <<< "${plain[index]}"
    widget="${words[0]}"
    "dybatpho::screen_${widget}" "0 0 40 3" "${words[@]:1}"
    read -r -a words <<< "${padded[index]}"
    "dybatpho::screen_${widget}" "0 4 40 3" "${words[@]:1}"
    for row in 0 1 2; do
      assert_equal "$(screen_raw "$((row + 4))")" "$(screen_raw "${row}")"
    done
  done

  local marker="${BATS_TEST_TMPDIR}/ran"
  dybatpho::screen_clear
  dybatpho::screen_sparkline "0 0 10 1" values "max:x[\$(touch ${marker})]"
  dybatpho::screen_spans 0 0 08 "" text 0
  [[ ! -e "${marker}" ]] || fail "an option ran a command"
}

@test "screen widgets read a rectangle in base ten and refuse one that is not numbers" {
  # Arithmetic read `08` as an invalid octal number and `010` as eight, and a
  # part such as `x[$(cmd)]` ran the command.
  local -a items=(alpha beta gamma) values=(1 5 9)
  dybatpho::screen_list "0 0 10 3" items
  dybatpho::screen_list "00 04 010 03" items
  dybatpho::screen_sparkline "02 8 08 1" values
  dybatpho::screen_sparkline "2 9 8 1" values
  local row
  for row in 0 1 2; do
    assert_equal "$(screen_raw "$((row + 4))")" "$(screen_raw "${row}")"
  done
  assert_equal "$(screen_raw 8)" "$(screen_raw 9)"

  local inner centred
  dybatpho::screen_rect_inner inner "00 00 010 08" 1
  assert_equal "${inner}" "1 1 8 6"
  dybatpho::screen_rect_center centred "0 0 010 010" 4 2
  assert_equal "${centred}" "3 4 4 2"

  # An empty rectangle still draws nothing.
  run dybatpho::screen_list "" items
  assert_success

  local marker="${BATS_TEST_TMPDIR}/ran"
  # No blank inside the part, which the split would otherwise cut it at.
  run --separate-stderr dybatpho::screen_list "0 0 items[\$(:>${marker})] 1" items
  assert_failure
  assert_stderr --partial "Invalid rectangle"
  [[ ! -e "${marker}" ]] || fail "a rectangle ran a command"
}
