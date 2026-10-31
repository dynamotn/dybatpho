setup() {
  load test_helper
  # The suite runs without a terminal, so `auto` would already pick the
  # fallback. Saying so explicitly keeps a test from depending on how the
  # runner happens to attach its streams.
  export DYBATPHO_TUI=never
  export DYBATPHO_TUI_DEFAULT=""
  export DYBATPHO_FORCE=false
  export DYBATPHO_INTERACTIVE=auto
  export NO_COLOR=1
  export LOG_LEVEL=info
}

# =============================================================================
# dybatpho::tui_supported
# =============================================================================

@test "dybatpho::tui_supported follows DYBATPHO_TUI over the attached streams" {
  DYBATPHO_TUI=never run dybatpho::tui_supported
  assert_failure
  DYBATPHO_TUI=always run dybatpho::tui_supported
  assert_success
}

@test "dybatpho::tui_supported reports no terminal when the streams are captured" {
  # `auto` is the interesting case: `run` gives the call a pipe, which is
  # exactly the situation where drawing would corrupt the output.
  DYBATPHO_TUI=auto run dybatpho::tui_supported
  assert_failure
}

@test "dybatpho::tui_supported falls back on a dumb terminal" {
  # Only a pseudo-terminal shows the difference, so the check runs under
  # `script`, in its BSD form or its util-linux and BusyBox one.
  local probe="${BATS_TEST_TMPDIR}/probe.sh" out=""
  cat > "${probe}" << EOF
. "${DYBATPHO_DIR}/init.sh" --modules tui
DYBATPHO_TUI=auto
for term in xterm dumb; do
  if TERM="\${term}" dybatpho::tui_supported; then
    echo "\${term}=draw"
  else
    echo "\${term}=fallback"
  fi
done
EOF
  if script -q /dev/null true < /dev/null > /dev/null 2>&1; then
    out="$(script -q /dev/null bash "${probe}" < /dev/null 2>&1)" || true
  elif script -qc true /dev/null < /dev/null > /dev/null 2>&1; then
    out="$(script -qc "bash '${probe}'" /dev/null < /dev/null 2>&1)" || true
  fi
  [[ "${out}" == *"xterm=draw"* ]] || skip "no pseudo-terminal to test with"
  [[ "${out}" == *"dumb=fallback"* ]] || fail "TERM=dumb drew in place: ${out}"
}

# =============================================================================
# dybatpho::tui_bar
# =============================================================================

@test "dybatpho::tui_bar renders a proportional bar with its percentage" {
  run_traced dybatpho::tui_bar 3 4 8
  assert_success
  assert_output "[██████░░]  75%"
}

@test "dybatpho::tui_bar renders the empty and full ends of the range" {
  run_traced dybatpho::tui_bar 0 5 5
  assert_output "[░░░░░]   0%"
  run_traced dybatpho::tui_bar 5 5 5
  assert_output "[█████] 100%"
}

@test "dybatpho::tui_bar clamps a position past the total instead of overflowing" {
  run_traced dybatpho::tui_bar 9 5 5
  assert_success
  assert_output "[█████] 100%"
}

@test "dybatpho::tui_bar honors the configured bar characters and default width" {
  DYBATPHO_TUI_BAR_FILLED="#" DYBATPHO_TUI_BAR_EMPTY="-" DYBATPHO_TUI_BAR_WIDTH=10 \
    run_traced dybatpho::tui_bar 1 2
  assert_success
  assert_output "[#####-----]  50%"
}

@test "dybatpho::tui_bar refuses a total of zero rather than dividing by it" {
  run dybatpho::tui_bar 1 0
  assert_failure
  assert_output --partial "Total units must be at least 1"
}

@test "dybatpho::tui_bar refuses arguments that are not whole numbers" {
  run dybatpho::tui_bar "half" 4
  assert_failure
  assert_output --partial "Completed units must be a whole number"
  run dybatpho::tui_bar 1 4 "wide"
  assert_failure
  assert_output --partial "Bar width must be a whole number"
}

# =============================================================================
# dybatpho::tui_spinner_start, dybatpho::tui_spinner_message, dybatpho::tui_spinner_stop
# =============================================================================

@test "dybatpho::tui_spinner_start logs the message when there is no terminal to animate on" {
  run_traced --separate-stderr dybatpho::tui_spinner_start "Resolving dependencies"
  assert_success
  # Nothing reaches stdout: a spinner beside a value being computed would end
  # up inside whatever captured that value.
  assert_output ""
  [[ "${stderr}" == *"Resolving dependencies"* ]] || fail "message not logged: ${stderr}"
}

@test "dybatpho::tui_spinner_message narrates a step without a running animation" {
  run_traced --separate-stderr dybatpho::tui_spinner_message "Resolving logging"
  assert_success
  [[ "${stderr}" == *"Resolving logging"* ]] || fail "message not logged: ${stderr}"
}

@test "dybatpho::tui_spinner_message refuses when a terminal is attached and nothing is spinning" {
  DYBATPHO_TUI=always run dybatpho::tui_spinner_message "Nothing is running"
  assert_failure
  assert_output --partial "No spinner is running"
}

@test "dybatpho::tui_spinner_stop reports success and returns the status it was given" {
  run_traced --separate-stderr dybatpho::tui_spinner_stop 0 "Resolved 3 modules"
  assert_success
  [[ "${stderr}" == *"Resolved 3 modules"* ]] || fail "closing message missing: ${stderr}"

  run_traced --separate-stderr dybatpho::tui_spinner_stop 2 "Resolution failed"
  assert_equal "${status}" 2
  [[ "${stderr}" == *"Resolution failed"* ]] || fail "failure message missing: ${stderr}"
}

@test "dybatpho::tui_spinner_stop refuses a status a return cannot carry" {
  # `return 256` is `return 0`: a failure would have been reported as success.
  run dybatpho::tui_spinner_stop 256 "Resolution failed"
  assert_failure
  assert_output --partial "Exit status must be at most 255, got '256'"
}

@test "dybatpho::tui_spinner_stop keeps its closing banner off stdout" {
  # `dybatpho::success` draws its banner on stdout, which is right for a script
  # reporting its own result and wrong for a widget: the banner landed inside
  # whatever captured the value the script was computing.
  local captured
  captured="$(dybatpho::tui_spinner_stop 0 "Resolved" 2> /dev/null; printf 'value')"
  assert_equal "${captured}" "value"
}

@test "dybatpho::tui_spinner_stop is quiet when it is given no message" {
  run_traced --separate-stderr dybatpho::tui_spinner_stop
  assert_success
  assert_output ""
}

@test "dybatpho::tui_spinner_start refuses to start a second spinner over the first" {
  DYBATPHO_TUI_SPINNER_PID=424242 run dybatpho::tui_spinner_start "Second"
  assert_failure
  assert_output --partial "A spinner is already running"
}

# =============================================================================
# dybatpho::tui_progress_start, _update, _step, _stop
# =============================================================================

@test "dybatpho::tui_progress_step advances the bar and reports on a percentage grid" {
  local log="${BATS_TEST_TMPDIR}/progress.log" recorded
  {
    dybatpho::tui_progress_start "Uploading" 5
    local _step
    for _step in 1 2 3 4 5; do dybatpho::tui_progress_step; done
    dybatpho::tui_progress_stop
  } 2> "${log}"
  recorded="$(< "${log}")"

  [[ "${recorded}" == *"Uploading: 0% (0/5)"* ]] || fail "missing first frame: ${recorded}"
  [[ "${recorded}" == *"Uploading: 60% (3/5)"* ]] || fail "missing middle frame: ${recorded}"
  [[ "${recorded}" == *"Uploading: 100% (5/5)"* ]] || fail "missing final frame: ${recorded}"
  # The closing frame repeats the percentage the last update already logged, so
  # reporting it again printed `100%` twice for every loop that ran to the end.
  assert_equal "$(grep -c '100% (5/5)' "${log}")" 1
}

@test "dybatpho::tui_progress_update reports the percentage it was moved to" {
  local log="${BATS_TEST_TMPDIR}/progress.log" recorded
  {
    dybatpho::tui_progress_start "Copying" 10
    dybatpho::tui_progress_update 4 "Copying files"
    dybatpho::tui_progress_stop "Copied"
  } 2> "${log}"
  recorded="$(< "${log}")"

  [[ "${recorded}" == *"Copying files: 40% (4/10)"* ]] || fail "missing update: ${recorded}"
  # A loop that ended early still finishes at 100%, so a reader is not left
  # looking at 40% for work that is over.
  [[ "${recorded}" == *"Copying files: 100% (10/10)"* ]] || fail "not completed: ${recorded}"
  [[ "${recorded}" == *"Copied"* ]] || fail "closing message missing: ${recorded}"
}

@test "the drawn progress bar redraws one line with its colour and timing" {
  local log="${BATS_TEST_TMPDIR}/drawn.log" recorded
  local DYBATPHO_TUI=always NO_COLOR="" FORCE_COLOR=1
  {
    dybatpho::tui_progress_start "Copying" 4
    dybatpho::tui_progress_update 2
    dybatpho::tui_progress_stop
  } 2> "${log}"
  recorded="$(< "${log}")"

  # Each frame returns to the start of the line and erases what it leaves.
  [[ "${recorded}" == *$'\r\033[1mCopying\033[0m'* ]] || fail "missing styled label: ${recorded}"
  [[ "${recorded}" == *"(2/4) ETA 0s"$'\033[K'* ]] || fail "missing estimate: ${recorded}"
  [[ "${recorded}" == *"(4/4) in 0s"$'\033[K'* ]] || fail "missing total time: ${recorded}"
}

@test "the drawn progress bar draws no colour when colour is off" {
  local log="${BATS_TEST_TMPDIR}/plain.log" recorded
  local DYBATPHO_TUI=always
  {
    dybatpho::tui_progress_start "Copying" 2
    dybatpho::tui_progress_stop "Copied"
  } 2> "${log}"
  recorded="$(< "${log}")"
  [[ "${recorded}" == *$'\rCopying ['* ]] || fail "unexpected frame: ${recorded}"
  [[ "${recorded}" == *$'\r\033[K'* ]] || fail "line not erased: ${recorded}"
}

@test "__dybatpho_tui_duration_into reads seconds as seconds, minutes or hours" {
  local text
  __dybatpho_tui_duration_into text 59
  assert_equal "${text}" "59s"
  __dybatpho_tui_duration_into text 61
  assert_equal "${text}" "1m01s"
  __dybatpho_tui_duration_into text 3720
  assert_equal "${text}" "1h02m"
  __dybatpho_tui_duration_into text -5
  assert_equal "${text}" "0s"
}

@test "dybatpho::tui_progress_update refuses when no progress bar is running" {
  run dybatpho::tui_progress_update 1
  assert_failure
  assert_output --partial "No progress bar is running"
}

@test "dybatpho::tui_progress_start refuses a total that is not a positive whole number" {
  run dybatpho::tui_progress_start "Uploading" 0
  assert_failure
  assert_output --partial "Total units must be at least 1"
}

@test "dybatpho::tui_progress_stop is a no-op when nothing was started" {
  run_traced --separate-stderr dybatpho::tui_progress_stop "Never started"
  assert_success
  assert_output ""
  refute_output --partial "Never started"
}

# =============================================================================
# key decoding
# =============================================================================

@test "keys arriving as escape sequences are named whole" {
  # Application cursor mode sends `ESC O A` for an arrow, which used to read as
  # Escape and cancel the menu; Delete is `ESC [ 3 ~`, whose `~` used to be left
  # behind and read as the next key. From a file, not `bash -c`: the reader is
  # an internal helper a `-c` child would not inherit.
  local script="${BATS_TEST_TMPDIR}/keys.sh"
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules tui" \
    'key=""; seen=""' \
    'while __dybatpho_tui_read_key_into key; [[ "${key}" != eof ]]; do seen+="${key} "; done' \
    'printf "%s\n" "${seen}"' > "${script}"

  run_traced bash "${script}" < <(printf '\033OA\033[3~x\033[B\033OB\033[5~\033[1;5C')
  assert_success
  assert_output "up delete char:x down down pageup unknown "

  run_traced bash "${script}" < <(printf '\033')
  assert_output "escape "
}

# =============================================================================
# dybatpho::tui_menu
# =============================================================================

@test "dybatpho::tui_menu returns the chosen entry and its position" {
  local chosen=""
  dybatpho::tui_menu chosen "Environment?" dev staging prod <<< "2"
  assert_equal "${chosen}" "staging"
  assert_equal "${DYBATPHO_TUI_INDEX}" "2"
  assert_equal "${DYBATPHO_TUI_INDEXES}" "2"
}

@test "the menus return the choice whatever the caller's variable is named" {
  # The choice is written through the name the caller passes; `prompt` and
  # `result_var` were the wrappers' own locals and kept the answer.
  local each
  for each in prompt result_var; do
    unset "${each}"
    dybatpho::tui_menu "${each}" "Pick" alpha beta <<< "2" 2> /dev/null
    assert_equal "${!each}" "beta"
    unset "${each}"
    local -a "${each}=()"
    dybatpho::tui_multi_menu "${each}" "Pick" alpha beta gamma <<< "1,3" 2> /dev/null
    local -n chosen="${each}"
    assert_equal "${chosen[*]}" "alpha gamma"
    unset -n chosen
  done
}

@test "the drawn menus take their keys from standard input" {
  local DYBATPHO_TUI=always chosen=""
  local -a picked=()
  dybatpho::tui_menu chosen "Environment?" dev staging prod < <(printf 'j\n') 2> /dev/null
  assert_equal "${chosen}" "staging"
  dybatpho::tui_multi_menu picked "Components?" api worker < <(printf ' j \n') 2> /dev/null
  assert_equal "${picked[*]}" "api worker"
}

@test "the drawn menus never draw a line wider than the terminal" {
  # A line that wraps takes two rows while the redraw moves up by one per line
  # drawn, so each keypress left a copy of the menu behind.
  local DYBATPHO_TUI=always COLUMNS=20 chosen=""
  local drawn="${BATS_TEST_TMPDIR}/menu.out"
  dybatpho::tui_menu chosen "Pick one of these long entries" \
    "a-very-long-entry-name-that-wraps" "漢字漢字漢字漢字漢字漢字" \
    < <(printf 'j\n') 2> "${drawn}"
  assert_equal "${chosen}" "漢字漢字漢字漢字漢字漢字"

  local -a rows=()
  local text row width
  text="$(sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' "${drawn}")"
  mapfile -t rows <<< "${text//$'\r'/$'\n'}"
  # The last row is the answer left in the transcript, which no redraw counts.
  assert_equal "${rows[-1]}" "Pick one of these long entries 漢字漢字漢字漢字漢字漢字"
  unset 'rows[-1]'
  ((${#rows[@]} > 0))
  for row in "${rows[@]}"; do
    dybatpho::screen_width width "${row}"
    ((width <= COLUMNS)) || fail "drawn row is ${width} columns wide: ${row}"
  done
}

@test "dybatpho::tui_menu asks again after an answer that names no entry" {
  local chosen=""
  dybatpho::tui_menu chosen "Environment?" dev staging prod <<< $'9\nnope\n1'
  assert_equal "${chosen}" "dev"
}

@test "dybatpho::tui_menu refuses more than one answer" {
  local chosen=""
  dybatpho::tui_menu chosen "Environment?" dev staging prod <<< $'1,2\n3'
  assert_equal "${chosen}" "prod"
}

@test "dybatpho::tui_menu falls back to DYBATPHO_TUI_DEFAULT when nothing can be read" {
  local chosen=""
  DYBATPHO_TUI_DEFAULT=3 dybatpho::tui_menu chosen "Environment?" dev staging prod < /dev/null
  assert_equal "${chosen}" "prod"
  assert_equal "${DYBATPHO_TUI_INDEX}" "3"
}

@test "dybatpho::tui_menu takes the first of several defaults when it cannot ask" {
  # A single choice given `1,3` used to refuse it as "one number only" and ask
  # again from an input with nothing left, forever; a child with a deadline
  # keeps that from hanging the suite.
  local script="${BATS_TEST_TMPDIR}/defaults.sh"
  # shellcheck disable=SC2016 # expanded by the child shell
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules tui" \
    'chosen=""' \
    'DYBATPHO_TUI=never DYBATPHO_TUI_DEFAULT=1,3 dybatpho::tui_menu chosen "Environment?" dev staging prod' \
    'printf "%s %s\n" "${chosen}" "${DYBATPHO_TUI_INDEX}"' > "${script}"
  run_traced -0 --separate-stderr dybatpho::run_with_timeout 10 bash "${script}" < /dev/null
  assert_output "dev 1"
}

@test "dybatpho::tui_menu fails rather than guessing when it can neither ask nor default" {
  local chosen=""
  run dybatpho::tui_menu chosen "Environment?" dev staging prod < /dev/null
  assert_failure
  assert_output --partial "no answer, and no DYBATPHO_TUI_DEFAULT"
}

@test "dybatpho::tui_menu refuses a reserved result variable and an empty entry list" {
  run dybatpho::tui_menu __dybatpho_stolen "Environment?" dev
  assert_failure
  assert_output --partial "is reserved"
  run dybatpho::tui_menu chosen "Environment?"
  assert_failure
  assert_output --partial "Expected at least one menu entry"
}

@test "the cursor handler restores the cursor and still lets TERM end the script" {
  # A handler on a signal replaces what the signal does, so restoring the
  # cursor alone left the script running after a `kill`. It restores, then
  # raises the signal again: the script ends with 128+n, the cursor back.
  local script="${BATS_TEST_TMPDIR}/signal.sh"
  # shellcheck disable=SC2016 # expanded by the child shell
  printf '%s\n' \
    ". $(printf '%q' "${DYBATPHO_DIR}")/init.sh --modules tui" \
    'DYBATPHO_TUI=always' \
    'dybatpho::tui_progress_start "Working" 2' \
    'kill -s TERM "${BASHPID}"' \
    'echo "still running"' > "${script}"
  run_traced -143 --separate-stderr bash "${script}"
  assert_output ""
  [[ "${stderr}" == *$'\033[?25h'* ]] || fail "cursor not shown again: ${stderr}"
}

# =============================================================================
# dybatpho::tui_multi_menu
# =============================================================================

@test "dybatpho::tui_multi_menu returns every chosen entry in menu order" {
  local -a chosen=()
  # The answer is given out of order and repeats a position: the result is
  # still menu order, with each entry once, so that the numbered fallback and
  # the drawn menu -- which can only answer in menu order -- agree.
  dybatpho::tui_multi_menu chosen "Components?" api worker scheduler <<< "3,1,3"
  assert_equal "${#chosen[@]}" 2
  assert_equal "${chosen[0]}" "api"
  assert_equal "${chosen[1]}" "scheduler"
  assert_equal "${DYBATPHO_TUI_INDEXES}" "1 3"
}

@test "dybatpho::tui_multi_menu keeps entries that contain spaces intact" {
  # This is why the answer comes back in an array: a space-separated string
  # would split `first thing` into two selections on the way out.
  local -a chosen=()
  dybatpho::tui_multi_menu chosen "Pick" "first thing" "second thing" <<< "1,2"
  assert_equal "${#chosen[@]}" 2
  assert_equal "${chosen[0]}" "first thing"
  assert_equal "${chosen[1]}" "second thing"
}

@test "dybatpho::tui_multi_menu preselects the entries named by DYBATPHO_TUI_DEFAULT" {
  local -a chosen=()
  DYBATPHO_TUI_DEFAULT="1,3" dybatpho::tui_multi_menu chosen "Components?" api worker scheduler < /dev/null
  assert_equal "${#chosen[@]}" 2
  assert_equal "${chosen[0]}" "api"
  assert_equal "${chosen[1]}" "scheduler"
}

@test "dybatpho::tui_multi_menu ignores positions outside the menu" {
  local -a chosen=()
  dybatpho::tui_multi_menu chosen "Components?" api worker <<< "2,7"
  assert_equal "${#chosen[@]}" 1
  assert_equal "${chosen[0]}" "worker"
}

# =============================================================================
# dybatpho::tui_confirm
# =============================================================================

@test "dybatpho::tui_confirm answers yes, no, and the default off a terminal" {
  DYBATPHO_INTERACTIVE=true dybatpho::tui_confirm "Continue?" <<< "y"
  run_traced -1 dybatpho::tui_confirm "Continue?" <<< "n"
  run_traced -1 dybatpho::tui_confirm "Continue?" <<< ""
  DYBATPHO_INTERACTIVE=true dybatpho::tui_confirm "Continue?" yes <<< ""
}

@test "dybatpho::tui_confirm refuses in an unattended shell and obeys DYBATPHO_FORCE" {
  run_traced dybatpho::tui_confirm "Continue?"
  assert_failure
  DYBATPHO_FORCE=true dybatpho::tui_confirm "Continue?"
}

@test "dybatpho::tui_confirm keeps stdout clean so it composes inside a substitution" {
  local captured
  captured="$(DYBATPHO_INTERACTIVE=true dybatpho::tui_confirm "Continue?" <<< "y" && printf 'yes')"
  assert_equal "${captured}" "yes"
}

@test "dybatpho::tui_menu and tui_multi_menu read positions with a leading zero in base ten" {
  # Arithmetic read `09` as an invalid octal number and `010` as eight.
  local -a items=(a b c d e f g h i j)
  local chosen=""
  DYBATPHO_TUI_DEFAULT=09 dybatpho::tui_menu chosen "Letter?" "${items[@]}" < /dev/null
  assert_equal "${chosen}" "i"
  local -a several=()
  dybatpho::tui_multi_menu several "Letters?" "${items[@]}" <<< "02,010"
  assert_equal "${several[*]}" "b j"
}

@test "tui bars, spinners and progress read numbers with a leading zero in base ten" {
  # Arithmetic read `08` as an invalid octal number and `010` as eight.
  run_traced dybatpho::tui_bar 06 08 08
  assert_success
  assert_output "[██████░░]  75%"

  run_traced --separate-stderr dybatpho::tui_spinner_stop 08 "Resolution failed"
  assert_equal "${status}" 8

  local log="${BATS_TEST_TMPDIR}/progress.log"
  DYBATPHO_TUI=never DYBATPHO_TUI_PROGRESS_STEP=08
  dybatpho::tui_progress_start "Work" 010 2> "${log}"
  dybatpho::tui_progress_step 08 2>> "${log}"
  DYBATPHO_TUI=auto DYBATPHO_TUI_PROGRESS_STEP=10
  assert_equal "${DYBATPHO_TUI_PROGRESS_TOTAL}/${DYBATPHO_TUI_PROGRESS_CURRENT}" "10/8"
  run grep -c 'value too great' "${log}"
  assert_output "0"
}
