# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break.
# dyshellint disable=BSG050,BSG011
# @file tui.sh
# @brief Interactive terminal widgets: spinners, progress bars, menus, and confirmations
# @namespace dybatpho
# @description
#   `cli.sh` turns a declarative spec into a parser, a help screen, and
#   completions -- everything a command line needs before it runs. This module
#   covers what happens once it is running and has to talk to a person: a
#   spinner the script starts and stops around work of its own, a progress bar
#   it drives from a loop, arrow-key menus for one or several choices, and a
#   confirmation that reads as a question rather than a `[y/N]` stub.
#
#   Every widget has two renderings and the module chooses between them, rather
#   than asking the caller to. On a terminal it draws in place with ANSI escape
#   sequences and reads raw keys. Anywhere else -- a pipe, a log file, CI, a
#   `$( )` -- it falls back to the numbered prompts of `cli.sh` and to ordinary
#   log lines. A script therefore calls the same function in both places, which
#   is why the example and the tests in this repository exercise the whole
#   interactive API without a terminal attached.
#
#   Widgets draw on stderr. A value a script prints to stdout stays clean, so
#   the menus remain usable in a command substitution and the progress of a
#   pipeline never lands in its own output.
#
# @tip `DYBATPHO_TUI=never` forces the fallback rendering everywhere, which is what a CI job wants;
#   `DYBATPHO_TUI=always`
#   forces the drawn one, which is what a demo recording wants
# @tip A menu asks through `dybatpho::prompt` when it cannot draw, so feeding `2` to the script answers it the same way
#   pressing `enter` on the second entry does -- with a redirect rather than a pipe, which would run the call in a
#   subshell and lose the answer with it
# @see
#   - `example/tui_ops.sh`
#   - `src/cli.sh`
#   - `src/safety.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_TUI string When widgets draw in place (`auto|always|never`). `auto` draws only when both stdin and
#   stderr
#   are terminals. Default `auto`
DYBATPHO_TUI="${DYBATPHO_TUI:-auto}"
export DYBATPHO_TUI
# @env DYBATPHO_TUI_INTERVAL string Seconds between spinner frames. Default is `DYBATPHO_SPINNER_INTERVAL`
DYBATPHO_TUI_INTERVAL="${DYBATPHO_TUI_INTERVAL:-${DYBATPHO_SPINNER_INTERVAL:-0.1}}"
export DYBATPHO_TUI_INTERVAL
# @env DYBATPHO_TUI_FRAMES string Space-separated frames the spinner cycles through. Default is
#   `DYBATPHO_SPINNER_FRAMES`
DYBATPHO_TUI_FRAMES="${DYBATPHO_TUI_FRAMES:-${DYBATPHO_SPINNER_FRAMES:-⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏}}"
export DYBATPHO_TUI_FRAMES
# @env DYBATPHO_TUI_BAR_WIDTH number Width of a progress bar in columns when none is given. Default `30`
DYBATPHO_TUI_BAR_WIDTH="${DYBATPHO_TUI_BAR_WIDTH:-30}"
export DYBATPHO_TUI_BAR_WIDTH
# @env DYBATPHO_TUI_BAR_FILLED string Character drawn for the completed part of a bar. Default `█`
DYBATPHO_TUI_BAR_FILLED="${DYBATPHO_TUI_BAR_FILLED:-█}"
export DYBATPHO_TUI_BAR_FILLED
# @env DYBATPHO_TUI_BAR_EMPTY string Character drawn for the remaining part of a bar. Default `░`
DYBATPHO_TUI_BAR_EMPTY="${DYBATPHO_TUI_BAR_EMPTY:-░}"
export DYBATPHO_TUI_BAR_EMPTY
# @env DYBATPHO_TUI_PROGRESS_STEP number Percentage granularity of the progress lines logged when there is no terminal
#   to
#   draw on. `0` logs every update. Default `10`
DYBATPHO_TUI_PROGRESS_STEP="${DYBATPHO_TUI_PROGRESS_STEP:-10}"
export DYBATPHO_TUI_PROGRESS_STEP
# @env DYBATPHO_TUI_POINTER string Marker drawn beside the highlighted menu entry. Default `❯`
DYBATPHO_TUI_POINTER="${DYBATPHO_TUI_POINTER:-❯}"
export DYBATPHO_TUI_POINTER
# @env DYBATPHO_TUI_CHECKED string Marker drawn beside a selected multi-select entry. Default `◉`
DYBATPHO_TUI_CHECKED="${DYBATPHO_TUI_CHECKED:-◉}"
export DYBATPHO_TUI_CHECKED
# @env DYBATPHO_TUI_UNCHECKED string Marker drawn beside an unselected multi-select entry. Default `◯`
DYBATPHO_TUI_UNCHECKED="${DYBATPHO_TUI_UNCHECKED:-◯}"
export DYBATPHO_TUI_UNCHECKED
# @env DYBATPHO_TUI_MENU_HEIGHT number Entries a drawn menu shows at once before it scrolls. Default `10`
DYBATPHO_TUI_MENU_HEIGHT="${DYBATPHO_TUI_MENU_HEIGHT:-10}"
export DYBATPHO_TUI_MENU_HEIGHT
# @env DYBATPHO_TUI_DEFAULT string Comma-separated 1-based entries a menu starts on, and the answer it uses when the
#   script
#   cannot ask at all. Empty means no default, and a menu that cannot ask then fails instead of choosing
DYBATPHO_TUI_DEFAULT="${DYBATPHO_TUI_DEFAULT:-}"
export DYBATPHO_TUI_DEFAULT

# @env DYBATPHO_TUI_SPINNER_PID number PID of the running spinner, or empty when none is running
DYBATPHO_TUI_SPINNER_PID=""
# @env DYBATPHO_TUI_INDEX number 1-based position the last `dybatpho::tui_menu` returned
DYBATPHO_TUI_INDEX=0
# @env DYBATPHO_TUI_INDEXES string Space-separated 1-based positions the last `dybatpho::tui_multi_menu` returned
DYBATPHO_TUI_INDEXES=""
# @env DYBATPHO_TUI_PROGRESS_CURRENT number Units of work the running progress bar has recorded
DYBATPHO_TUI_PROGRESS_CURRENT=0
# @env DYBATPHO_TUI_PROGRESS_TOTAL number Units of work the running progress bar expects in total
DYBATPHO_TUI_PROGRESS_TOTAL=0

# Path of the file the spinner re-reads on every frame. The message lives in a
# file rather than in a variable because the animation runs in a background
# shell: a variable the parent assigns after the fork never reaches it, so
# `dybatpho::tui_spinner_message` would silently do nothing.
__dybatpho_tui_spinner_file=""
__dybatpho_tui_progress_label=""
__dybatpho_tui_progress_started_ms=0
__dybatpho_tui_progress_active=false
# Last percentage reported to the log in the fallback rendering, so an update
# that does not move the bar by `DYBATPHO_TUI_PROGRESS_STEP` stays quiet.
__dybatpho_tui_progress_reported=-1
__dybatpho_tui_cursor_hidden=false
__dybatpho_tui_cursor_trapped=false

#######################################
# @description Return success when the widgets may draw in place and read raw
#   keys, which is what separates the interactive rendering from the fallback.
#
#   `auto` requires a terminal on both ends: stdin is where the keys come from,
#   and stderr is where the frames go. A script whose diagnostics are piped
#   still has a terminal on stdin, and drawing a menu into that pipe would
#   corrupt it.
# @example
#   dybatpho::tui_supported || dybatpho::info "No terminal; answering from flags"
#
# @noargs
# @exitcode 0 Widgets draw in place
# @exitcode 1 Widgets fall back to prompts and log lines
# @env DYBATPHO_TUI string `auto` detects the terminals, `always` and `never` override the detection
#######################################
function dybatpho::tui_supported {
  case "${DYBATPHO_TUI}" in
    never) return 1 ;;
    always) return 0 ;;
    *) [[ -t 0 && -t 2 ]] ;;
  esac
}

#######################################
# @description Return the SGR sequence for a style, or nothing when color is off.
# @arg $1 string Name of the variable receiving the sequence
# @arg $2 string Style, as the parameters of an SGR escape
# @set The named variable
# @internal
#######################################
function __dybatpho_tui_sgr_into {
  local -n __dybatpho_tui_sgr_out="$1"
  # The widgets are drawn on stderr, so that is the stream to ask about.
  if ! dybatpho::color_supported stderr; then
    __dybatpho_tui_sgr_out=""
    return 0
  fi
  printf -v __dybatpho_tui_sgr_out '\033[%sm' "$2"
}

#######################################
# @description Repeat a string into a named variable, without a subshell.
# @arg $1 string Name of the variable receiving the result
# @arg $2 string Text to repeat
# @arg $3 number Number of repetitions
# @set The named variable
# @internal
#######################################
function __dybatpho_tui_repeat_into {
  __dybatpho_log_repeat_into "$@"
}

#######################################
# @description Hide the cursor while a widget is drawing, and arrange for it to
#   come back however the script ends.
#
#   A script killed mid-menu would otherwise leave the terminal with no cursor,
#   and that outlives the script: it has to be undone by hand afterwards.
#######################################
# @noargs
# @internal
function __dybatpho_tui_hide_cursor {
  # kcov(disabled)
  dybatpho::tui_supported || return 0
  if [[ "${__dybatpho_tui_cursor_trapped}" != true ]]; then
    dybatpho::trap "__dybatpho_tui_show_cursor" EXIT INT TERM
    __dybatpho_tui_cursor_trapped=true
  fi
  __dybatpho_tui_cursor_hidden=true
  printf '\033[?25l' >&2
  # kcov(enabled)
}

#######################################
# @description Show the cursor again, if a widget hid it.
# @noargs
# @exitcode 0 Always, so it cannot change the exit status of a trap
# @internal
#######################################
function __dybatpho_tui_show_cursor {
  # kcov(disabled)
  [[ "${__dybatpho_tui_cursor_hidden}" == true ]] || return 0
  __dybatpho_tui_cursor_hidden=false
  printf '\033[?25h' >&2
  return 0
  # kcov(enabled)
}

#######################################
# @description Redraw the current line on stderr, erasing whatever was on it.
# @arg $1 string Text to draw
# @stderr The text, preceded by a carriage return and followed by an erase
# @internal
#######################################
function __dybatpho_tui_draw_line {
  printf '\r%s\033[K' "${1-}" >&2
}

#######################################
# @description Erase the current line on stderr and leave the cursor at its
#   start, so the next output begins on a clean column.
#######################################
# @noargs
# @internal
function __dybatpho_tui_erase_line {
  printf '\r\033[K' >&2
}

#######################################
# @description Format a whole number of seconds as a compact duration.
# @arg $1 string Name of the variable receiving the text
# @arg $2 number Seconds
# @set The named variable
# @internal
#######################################
function __dybatpho_tui_duration_into {
  local -n __dybatpho_tui_duration_out="$1"
  local __dybatpho_tui_duration_seconds="${2:-0}"
  ((__dybatpho_tui_duration_seconds >= 0)) || __dybatpho_tui_duration_seconds=0
  if ((__dybatpho_tui_duration_seconds < 60)); then
    printf -v __dybatpho_tui_duration_out '%ss' "${__dybatpho_tui_duration_seconds}"
  elif ((__dybatpho_tui_duration_seconds < 3600)); then
    printf -v __dybatpho_tui_duration_out '%dm%02ds' \
      "$((__dybatpho_tui_duration_seconds / 60))" \
      "$((__dybatpho_tui_duration_seconds % 60))"
  else
    printf -v __dybatpho_tui_duration_out '%dh%02dm' \
      "$((__dybatpho_tui_duration_seconds / 3600))" \
      "$((__dybatpho_tui_duration_seconds % 3600 / 60))"
  fi
}

#######################################
# @description Validate a whole number, or end the script naming what was wrong.
# @arg $1 string Name of the caller, used in the message
# @arg $2 string Description of the value, used in the message
# @arg $3 string Value to check
# @arg $4 number Smallest value accepted
# @internal
#######################################
function __dybatpho_tui_expect_int {
  [[ "${3-}" =~ ^-?[0-9]+$ ]] \
    || dybatpho::die "$1: $2 must be a whole number, got '${3-}'"
  (($3 >= $4)) \
    || dybatpho::die "$1: $2 must be at least $4, got '$3'"
}

#######################################
# @description Render a progress bar as text.
#
#   This is the whole of the bar drawing, kept apart from the state the
#   `dybatpho::tui_progress_*` helpers carry, so that a script with a progress
#   model of its own can reuse the rendering and so that the rendering can be
#   asserted without a terminal.
# @example
#   dybatpho::tui_bar 3 4       # [██████████████████████░░░░░░░░]  75%
#   dybatpho::tui_bar 1 3 12    # [████░░░░░░░░]  33%
#
# @arg $1 number Units of work completed, clamped to the total
# @arg $2 number Units of work in total, at least 1
# @arg $3 number Optional bar width in characters, default is `DYBATPHO_TUI_BAR_WIDTH`
# @stdout The bar and its percentage, with no trailing newline
# @exitcode 1 An argument is not a whole number, or is out of range
# @env DYBATPHO_TUI_BAR_FILLED string Character drawn for the completed part
# @env DYBATPHO_TUI_BAR_EMPTY string Character drawn for the remaining part
# @tip The bar carries no carriage return of its own, so it composes with a label and can be written to a file as
#   readily
#   as to a terminal
#######################################
function dybatpho::tui_bar {
  local current total
  dybatpho::expect_args current total -- "$@"
  local width="${3:-${DYBATPHO_TUI_BAR_WIDTH}}"

  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Completed units" "${current}" 0
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Total units" "${total}" 1
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Bar width" "${width}" 1

  ((current <= total)) || current="${total}"
  local percentage=$((current * 100 / total))
  local filled=$((current * width / total))
  local filled_text empty_text
  __dybatpho_tui_repeat_into filled_text "${DYBATPHO_TUI_BAR_FILLED}" "${filled}"
  __dybatpho_tui_repeat_into empty_text "${DYBATPHO_TUI_BAR_EMPTY}" "$((width - filled))"
  printf '[%s%s] %3d%%' "${filled_text}" "${empty_text}" "${percentage}"
}

#######################################
# @description Animate the spinner on stderr until the shell that started it
#   kills it, re-reading its message from the state file on every frame. Runs as
#   a background job, so it never returns on its own.
# @arg $1 string Path of the file holding the current message
# @stderr One frame per interval, redrawn over the same line
# @internal
#######################################
function __dybatpho_tui_spin {
  # kcov(disabled)
  local file="$1"
  local -a frames=()
  read -r -a frames <<< "${DYBATPHO_TUI_FRAMES}"
  ((${#frames[@]} > 0)) || frames=('-' "\\" '|' '/')
  local index=0 message=""
  while true; do
    message="$(< "${file}")" 2> /dev/null || message=""
    printf '\r%s %s\033[K' "${frames[index % ${#frames[@]}]}" "${message}" >&2
    index=$((index + 1))
    sleep "${DYBATPHO_TUI_INTERVAL}" 2> /dev/null || sleep 1
  done
  # kcov(enabled)
}

#######################################
# @description Start a spinner that runs until `dybatpho::tui_spinner_stop`
#   stops it.
#
#   `dybatpho::spinner` wraps one command and is the right tool when the work is
#   one command. This one brackets a region instead, which is what a script
#   needs when the work is a loop, a pipeline, or a sequence whose steps deserve
#   to be named as they happen.
#
#   Without a terminal to draw on the message is logged once at `info`, so a CI
#   log keeps the same narration without the frames.
# @example
#   dybatpho::tui_spinner_start "Resolving dependencies"
#   for module in "${modules[@]}"; do
#     dybatpho::tui_spinner_message "Resolving ${module}"
#     _resolve "${module}"
#   done
#   dybatpho::tui_spinner_stop 0 "Resolved ${#modules[@]} modules"
#
# @arg $1 string Message shown beside the frame
# @set DYBATPHO_TUI_SPINNER_PID number PID of the animation, or empty when it is not animating
# @stderr The animation, or one log line when there is no terminal
# @exitcode 1 A spinner is already running
# @tip Registered secrets are masked before the message is drawn, exactly as the logging helpers mask them
#######################################
function dybatpho::tui_spinner_start {
  local message
  dybatpho::expect_args message -- "$@"

  if [[ -n "${DYBATPHO_TUI_SPINNER_PID}" ]]; then
    dybatpho::error "${FUNCNAME[0]}: A spinner is already running; stop it with dybatpho::tui_spinner_stop first"
    return 1
  fi

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  if ! dybatpho::tui_supported; then
    __dybatpho_tui_spinner_file=""
    dybatpho::info "${message}"
    return 0
  fi

  # kcov(disabled)
  # `dybatpho::create_temp` refuses to write through a nameref whose name is the
  # library's own, so the path is created into a plain local and moved into the
  # module's state afterwards.
  local spinner_file
  dybatpho::create_temp spinner_file ".txt" "tui_spinner"
  __dybatpho_tui_spinner_file="${spinner_file}"
  printf '%s' "${message}" > "${__dybatpho_tui_spinner_file}"
  __dybatpho_tui_hide_cursor
  __dybatpho_tui_spin "${__dybatpho_tui_spinner_file}" &
  DYBATPHO_TUI_SPINNER_PID=$!
  # kcov(enabled)
}

#######################################
# @description Replace the message of the running spinner without restarting it.
# @example
#   dybatpho::tui_spinner_message "Uploading layer 3 of 7"
#
# @arg $1 string New message
# @stderr The next frame carries the new message, or one log line when there is no terminal
# @exitcode 1 A terminal is attached but no spinner is running
#######################################
function dybatpho::tui_spinner_message {
  local message
  dybatpho::expect_args message -- "$@"

  if ((${DYBATPHO_SECRET_COUNT:-0} > 0)) && declare -F __dybatpho_secret_mask_var > /dev/null; then
    __dybatpho_secret_mask_var message
  fi

  if [[ -z "${__dybatpho_tui_spinner_file}" ]]; then
    if [[ -z "${DYBATPHO_TUI_SPINNER_PID}" ]] && dybatpho::tui_supported; then
      dybatpho::error "${FUNCNAME[0]}: No spinner is running"
      return 1
    fi
    dybatpho::info "${message}"
    return 0
  fi
  # kcov(disabled)
  printf '%s' "${message}" > "${__dybatpho_tui_spinner_file}"
  # kcov(enabled)
}

#######################################
# @description Stop the running spinner, erase its line, and report the outcome.
# @example
#   dybatpho::tui_spinner_stop 0 "Uploaded"
#   dybatpho::tui_spinner_stop 1 "Upload failed"
#
# @arg $1 number Optional exit status the work ended with, default is `0`
# @arg $2 string Optional closing message, default is none
# @set DYBATPHO_TUI_SPINNER_PID string Cleared
# @stderr A success or failure banner, when a message is given
# @exitcode The status passed in, so the call can both report and propagate an outcome
# @tip `dybatpho::tui_spinner_stop "$?" "Done"` reports the work and keeps its exit status
#######################################
function dybatpho::tui_spinner_stop {
  local status="${1:-0}"
  local message="${2-}"
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Exit status" "${status}" 0

  if [[ -n "${DYBATPHO_TUI_SPINNER_PID}" ]]; then
    # kcov(disabled)
    kill "${DYBATPHO_TUI_SPINNER_PID}" 2> /dev/null || true
    wait "${DYBATPHO_TUI_SPINNER_PID}" 2> /dev/null || true
    DYBATPHO_TUI_SPINNER_PID=""
    __dybatpho_tui_erase_line
    __dybatpho_tui_show_cursor
    # kcov(enabled)
  fi
  __dybatpho_tui_spinner_file=""

  [[ -z "${message}" ]] || __dybatpho_tui_banner "${status}" "${message}"
  return "${status}"
}

#######################################
# @description Draw a closing banner for a widget, on stderr.
#
#   `dybatpho::success` writes its banner to stdout, which is right for a
#   script reporting its own result and wrong here: a widget that printed to
#   stdout would land inside whatever captured the value the script was
#   computing. The same box is drawn on stderr instead, so every byte this
#   module emits goes to the same place.
# @arg $1 number Exit status the work ended with
# @arg $2 string Message
# @stderr The banner
# @internal
#######################################
function __dybatpho_tui_banner {
  local message label
  message="$(__dybatpho_log_translate "$2")"
  if (($1 == 0)); then
    label="$(__dybatpho_log_text logging.done "DONE:")"
    __dybatpho_log_box "╭" "─" "╮" "│" "│" "╰" "╯" "✅ ${label} ${message}" stderr "1;3;32"
    return 0
  fi
  dybatpho::error "${message}"
}

#######################################
# @description Draw or log one frame of the running progress bar.
# @arg $1 bool `true` when this is the closing frame
# @internal
#######################################
function __dybatpho_tui_progress_render {
  local final="${1:-false}"
  local current="${DYBATPHO_TUI_PROGRESS_CURRENT}"
  local total="${DYBATPHO_TUI_PROGRESS_TOTAL}"
  local percentage=$((current * 100 / total))

  if ! dybatpho::tui_supported; then
    # A log line per update would bury the log of a thousand-item loop, so the
    # fallback reports on a percentage grid instead of on every call.
    local step="${DYBATPHO_TUI_PROGRESS_STEP}"
    ((step > 0)) || step=1
    local bucket=$((percentage / step * step))
    # The closing frame is a report of the same percentage the last update
    # already logged, so reporting it again put `100%` in the log twice for
    # every loop that ran to completion.
    ((bucket > __dybatpho_tui_progress_reported)) || return 0
    __dybatpho_tui_progress_reported="${bucket}"
    dybatpho::info "${__dybatpho_tui_progress_label}: ${percentage}% (${current}/${total})"
    return 0
  fi

  # kcov(disabled)
  local elapsed_ms
  elapsed_ms=$(($(__dybatpho_log_now_ms) - __dybatpho_tui_progress_started_ms))
  ((elapsed_ms >= 0)) || elapsed_ms=0
  local timing=""
  if ((current > 0 && current < total)); then
    local remaining_ms=$((elapsed_ms * (total - current) / current))
    __dybatpho_tui_duration_into timing "$((remaining_ms / 1000))"
    timing=" ETA ${timing}"
  elif [[ "${final}" == true ]]; then
    __dybatpho_tui_duration_into timing "$((elapsed_ms / 1000))"
    timing=" in ${timing}"
  fi

  local bold reset bar line
  __dybatpho_tui_sgr_into bold "1"
  __dybatpho_tui_sgr_into reset "0"
  bar="$(dybatpho::tui_bar "${current}" "${total}")"
  printf -v line '%s%s%s %s (%s/%s)%s' \
    "${bold}" "${__dybatpho_tui_progress_label}" "${reset}" \
    "${bar}" "${current}" "${total}" "${timing}"
  __dybatpho_tui_draw_line "${line}"
  # kcov(enabled)
}

#######################################
# @description Start a progress bar over a known amount of work.
# @example
#   dybatpho::tui_progress_start "Uploading" "${#files[@]}"
#   for file in "${files[@]}"; do
#     _upload "${file}"
#     dybatpho::tui_progress_step
#   done
#   dybatpho::tui_progress_stop "Uploaded ${#files[@]} files"
#
# @arg $1 string Label drawn in front of the bar
# @arg $2 number Units of work in total, at least 1
# @set DYBATPHO_TUI_PROGRESS_TOTAL number Units of work expected
# @set DYBATPHO_TUI_PROGRESS_CURRENT number Reset to `0`
# @stderr The first frame, or one log line when there is no terminal
# @exitcode 1 The total is not a whole number of at least 1
#######################################
function dybatpho::tui_progress_start {
  local label total
  dybatpho::expect_args label total -- "$@"
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Total units" "${total}" 1

  __dybatpho_tui_progress_label="${label}"
  DYBATPHO_TUI_PROGRESS_TOTAL="${total}"
  DYBATPHO_TUI_PROGRESS_CURRENT=0
  __dybatpho_tui_progress_started_ms="$(__dybatpho_log_now_ms)"
  __dybatpho_tui_progress_reported=-1
  __dybatpho_tui_progress_active=true
  __dybatpho_tui_hide_cursor
  __dybatpho_tui_progress_render false
}

#######################################
# @description Move the progress bar to an absolute position.
# @arg $1 number Units of work completed, clamped to the total
# @arg $2 string Optional new label
# @set DYBATPHO_TUI_PROGRESS_CURRENT number Units recorded
# @stderr The redrawn bar, or a log line when the percentage crosses a reporting step
# @exitcode 1 No progress bar is running, or the position is not a whole number
#######################################
function dybatpho::tui_progress_update {
  local current
  dybatpho::expect_args current -- "$@"
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Completed units" "${current}" 0

  if [[ "${__dybatpho_tui_progress_active}" != true ]]; then
    dybatpho::error "${FUNCNAME[0]}: No progress bar is running; start one with dybatpho::tui_progress_start"
    return 1
  fi
  ((current <= DYBATPHO_TUI_PROGRESS_TOTAL)) || current="${DYBATPHO_TUI_PROGRESS_TOTAL}"
  DYBATPHO_TUI_PROGRESS_CURRENT="${current}"
  [[ -z "${2-}" ]] || __dybatpho_tui_progress_label="$2"
  __dybatpho_tui_progress_render false
}

#######################################
# @description Advance the progress bar by a number of units.
# @arg $1 number Optional units to add, default is `1`
# @arg $2 string Optional new label
# @set DYBATPHO_TUI_PROGRESS_CURRENT number Units recorded
# @exitcode 1 No progress bar is running, or the increment is not a whole number
#######################################
function dybatpho::tui_progress_step {
  local increment="${1:-1}"
  __dybatpho_tui_expect_int "${FUNCNAME[0]}" "Increment" "${increment}" 0
  dybatpho::tui_progress_update "$((DYBATPHO_TUI_PROGRESS_CURRENT + increment))" "${2-}"
}

#######################################
# @description Finish the progress bar, leaving the line complete rather than
#   part-drawn.
#
#   The bar is filled to its total first: a loop that ended early would
#   otherwise leave a terminal showing `80%` for work that is over, which reads
#   as a hang rather than as a finish.
# @arg $1 string Optional closing message replacing the bar
# @set DYBATPHO_TUI_PROGRESS_CURRENT number Set to the total
# @stderr The final frame, then a newline, or a closing log line
# @exitcode 0 Even when no progress bar was running, so it is safe to call from a trap
#######################################
function dybatpho::tui_progress_stop {
  local message="${1-}"
  [[ "${__dybatpho_tui_progress_active}" == true ]] || return 0

  DYBATPHO_TUI_PROGRESS_CURRENT="${DYBATPHO_TUI_PROGRESS_TOTAL}"
  __dybatpho_tui_progress_render true
  if dybatpho::tui_supported; then
    # kcov(disabled)
    if [[ -n "${message}" ]]; then
      __dybatpho_tui_erase_line
    else
      printf '\n' >&2
    fi
    __dybatpho_tui_show_cursor
    # kcov(enabled)
  fi
  __dybatpho_tui_progress_active=false
  [[ -z "${message}" ]] || __dybatpho_tui_banner 0 "${message}"
  return 0
}

#######################################
# @description Read one keypress and report it under a stable name, so the menu
#   loops never deal with escape sequences themselves.
# @arg $1 string Name of the variable receiving the key name
# @set The named variable to `up`, `down`, `left`, `right`, `enter`, `space`, `escape`, `eof`, or `char:<c>`
# @internal
#######################################
function __dybatpho_tui_read_key_into {
  # kcov(disabled)
  local -n __dybatpho_tui_key_out="$1"
  local __dybatpho_tui_key_char __dybatpho_tui_key_rest=""

  if ! IFS= read -rsn1 __dybatpho_tui_key_char; then
    __dybatpho_tui_key_out="eof"
    return 0
  fi
  case "${__dybatpho_tui_key_char}" in
    # `read -n1` strips the newline, so `enter` arrives as an empty character.
    '') __dybatpho_tui_key_out="enter" ;;
    ' ') __dybatpho_tui_key_out="space" ;;
    $'\033')
      # An escape on its own is the cancel key; an escape followed by `[A` is an
      # arrow. The timeout is what tells them apart, so it has to be short
      # enough not to be felt and long enough for the rest of the sequence.
      IFS= read -rsn2 -t 0.05 __dybatpho_tui_key_rest || __dybatpho_tui_key_rest=""
      case "${__dybatpho_tui_key_rest}" in
        '[A') __dybatpho_tui_key_out="up" ;;
        '[B') __dybatpho_tui_key_out="down" ;;
        '[C') __dybatpho_tui_key_out="right" ;;
        '[D') __dybatpho_tui_key_out="left" ;;
        *) __dybatpho_tui_key_out="escape" ;;
      esac
      ;;
    *) __dybatpho_tui_key_out="char:${__dybatpho_tui_key_char}" ;;
  esac
  # kcov(enabled)
}

#######################################
# @description Fill an array with the 1-based positions named by
#   `DYBATPHO_TUI_DEFAULT`, dropping anything outside the menu.
# @arg $1 string Name of the array variable receiving the positions
# @arg $2 number Number of entries in the menu
# @set The named variable
# @internal
#######################################
function __dybatpho_tui_defaults_into {
  local -n __dybatpho_tui_defaults_out="$1"
  local __dybatpho_tui_defaults_count="$2"
  local -a __dybatpho_tui_defaults_tokens=()
  local __dybatpho_tui_defaults_token

  __dybatpho_tui_defaults_out=()
  [[ -n "${DYBATPHO_TUI_DEFAULT}" ]] || return 0
  IFS=',' read -r -a __dybatpho_tui_defaults_tokens <<< "${DYBATPHO_TUI_DEFAULT}"
  for __dybatpho_tui_defaults_token in ${__dybatpho_tui_defaults_tokens[@]+"${__dybatpho_tui_defaults_tokens[@]}"}; do
    __dybatpho_tui_defaults_token="${__dybatpho_tui_defaults_token//[[:space:]]/}"
    [[ "${__dybatpho_tui_defaults_token}" =~ ^[0-9]+$ ]] || continue
    ((__dybatpho_tui_defaults_token >= 1 && __dybatpho_tui_defaults_token <= __dybatpho_tui_defaults_count)) || continue
    __dybatpho_tui_defaults_out+=("${__dybatpho_tui_defaults_token}")
  done
}

#######################################
# @description Ask for a choice with a numbered prompt, which is the rendering
#   used whenever the menu cannot be drawn.
#
#   The answer is read through `dybatpho::prompt`, so a piped `2` and a typed
#   `2` are the same thing, and an empty answer takes `DYBATPHO_TUI_DEFAULT`.
# @arg $1 string Name of the variable receiving the selection
# @arg $2 bool `true` to accept several positions
# @arg $3 string Prompt text
# @arg $@ string Menu entries
# @set The named variable, `DYBATPHO_TUI_INDEX`, and `DYBATPHO_TUI_INDEXES`
# @exitcode 1 Nothing could be read and there is no default
# @internal
#######################################
function __dybatpho_tui_menu_fallback {
  local __dybatpho_tui_fb_var="$1"
  local __dybatpho_tui_fb_multiple="$2"
  local __dybatpho_tui_fb_prompt="$3"
  shift 3
  local -a __dybatpho_tui_fb_items=("$@")
  local -n __dybatpho_tui_fb_out="${__dybatpho_tui_fb_var}"
  local -a __dybatpho_tui_fb_defaults=()
  local __dybatpho_tui_fb_index __dybatpho_tui_fb_answer __dybatpho_tui_fb_token
  local -a __dybatpho_tui_fb_tokens=() __dybatpho_tui_fb_chosen=()

  __dybatpho_tui_defaults_into __dybatpho_tui_fb_defaults "${#__dybatpho_tui_fb_items[@]}"

  printf '%s\n' "${__dybatpho_tui_fb_prompt}" >&2
  for __dybatpho_tui_fb_index in "${!__dybatpho_tui_fb_items[@]}"; do
    printf '  %d) %s\n' "$((__dybatpho_tui_fb_index + 1))" \
      "${__dybatpho_tui_fb_items[__dybatpho_tui_fb_index]}" >&2
  done

  local __dybatpho_tui_fb_label
  if dybatpho::is true "${__dybatpho_tui_fb_multiple}"; then
    __dybatpho_tui_fb_label="$(__dybatpho_log_text tui.select_multiple "Select (comma-separated)")"
  else
    __dybatpho_tui_fb_label="$(__dybatpho_log_text tui.select "Select")"
  fi

  while true; do
    if ! __dybatpho_tui_fb_answer="$(dybatpho::prompt "${__dybatpho_tui_fb_label}" \
      "${DYBATPHO_TUI_DEFAULT}")"; then
      __dybatpho_tui_fb_answer=""
    fi
    if [[ -z "${__dybatpho_tui_fb_answer}" ]]; then
      if ((${#__dybatpho_tui_fb_defaults[@]} == 0)); then
        dybatpho::error "${__dybatpho_tui_fb_prompt}: no answer, and no DYBATPHO_TUI_DEFAULT to fall back on"
        return 1
      fi
      __dybatpho_tui_fb_answer="${DYBATPHO_TUI_DEFAULT}"
    fi

    # The positions are collected by walking the menu rather than the answer,
    # so `3,1` and `1,3` both come back in menu order and a position named
    # twice is still one selection. The drawn menu can only answer in menu
    # order, and the two renderings have to agree.
    local -A __dybatpho_tui_fb_wanted=()
    __dybatpho_tui_fb_chosen=()
    IFS=',' read -r -a __dybatpho_tui_fb_tokens <<< "${__dybatpho_tui_fb_answer}"
    for __dybatpho_tui_fb_token in ${__dybatpho_tui_fb_tokens[@]+"${__dybatpho_tui_fb_tokens[@]}"}; do
      __dybatpho_tui_fb_token="${__dybatpho_tui_fb_token//[[:space:]]/}"
      [[ "${__dybatpho_tui_fb_token}" =~ ^[0-9]+$ ]] || continue
      ((__dybatpho_tui_fb_token >= 1 && __dybatpho_tui_fb_token <= ${#__dybatpho_tui_fb_items[@]})) || continue
      __dybatpho_tui_fb_wanted["${__dybatpho_tui_fb_token}"]=1
    done
    for ((__dybatpho_tui_fb_index = 1;  \
    __dybatpho_tui_fb_index <= ${#__dybatpho_tui_fb_items[@]};  \
    __dybatpho_tui_fb_index++)); do
      [[ -n "${__dybatpho_tui_fb_wanted[${__dybatpho_tui_fb_index}]-}" ]] || continue
      __dybatpho_tui_fb_chosen+=("${__dybatpho_tui_fb_index}")
    done

    if ((${#__dybatpho_tui_fb_chosen[@]} == 0)); then
      dybatpho::warn "Enter a number between 1 and ${#__dybatpho_tui_fb_items[@]}"
      continue
    fi
    if dybatpho::is false "${__dybatpho_tui_fb_multiple}" && ((${#__dybatpho_tui_fb_chosen[@]} > 1)); then
      dybatpho::warn "Enter one number only"
      continue
    fi
    break
  done

  # The nameref is bound to an array for a multi-select and to a scalar for a
  # single one, which is the contract of the two public functions. ShellCheck
  # sees one variable assigned both ways and cannot know only one branch runs
  # for any given caller.
  # shellcheck disable=SC2178,SC2128
  if dybatpho::is true "${__dybatpho_tui_fb_multiple}"; then
    DYBATPHO_TUI_INDEXES="${__dybatpho_tui_fb_chosen[*]}"
    __dybatpho_tui_fb_out=()
    for __dybatpho_tui_fb_index in "${__dybatpho_tui_fb_chosen[@]}"; do
      __dybatpho_tui_fb_out+=("${__dybatpho_tui_fb_items[__dybatpho_tui_fb_index - 1]}")
    done
  else
    DYBATPHO_TUI_INDEX="${__dybatpho_tui_fb_chosen[0]}"
    # shellcheck disable=SC2034 # output for the caller; nothing in this module reads it back
    DYBATPHO_TUI_INDEXES="${DYBATPHO_TUI_INDEX}"
    # The output variable is an array when several entries are accepted and a
    # scalar when one is. Both are the documented contract, but a nameref is
    # one name to ShellCheck, so it reads the branch above as the type.
    # shellcheck disable=SC2178 # nameref to the caller's variable, a scalar here
    __dybatpho_tui_fb_out="${__dybatpho_tui_fb_items[DYBATPHO_TUI_INDEX - 1]}"
  fi
  return 0
}

#######################################
# @description Draw a menu and drive it from the keyboard until it is answered
#   or cancelled.
# @arg $1 string Name of the variable receiving the selection
# @arg $2 bool `true` to accept several entries
# @arg $3 string Prompt text
# @arg $@ string Menu entries
# @set The named variable, `DYBATPHO_TUI_INDEX`, and `DYBATPHO_TUI_INDEXES`
# @exitcode 1 The menu was cancelled
# @internal
#######################################
function __dybatpho_tui_menu_interactive {
  # kcov(disabled)
  local __dybatpho_tui_menu_var="$1"
  local __dybatpho_tui_menu_multiple="$2"
  local __dybatpho_tui_menu_prompt="$3"
  shift 3
  local -a __dybatpho_tui_menu_items=("$@")
  local -n __dybatpho_tui_menu_out="${__dybatpho_tui_menu_var}"
  local __dybatpho_tui_menu_count=${#__dybatpho_tui_menu_items[@]}
  local -a __dybatpho_tui_menu_checked=() __dybatpho_tui_menu_defaults=()
  local __dybatpho_tui_menu_index

  for ((__dybatpho_tui_menu_index = 0;  \
  __dybatpho_tui_menu_index < __dybatpho_tui_menu_count;  \
  __dybatpho_tui_menu_index++)); do
    __dybatpho_tui_menu_checked[__dybatpho_tui_menu_index]=0
  done
  __dybatpho_tui_defaults_into __dybatpho_tui_menu_defaults "${__dybatpho_tui_menu_count}"

  local __dybatpho_tui_menu_cursor=0
  if ((${#__dybatpho_tui_menu_defaults[@]} > 0)); then
    __dybatpho_tui_menu_cursor=$((__dybatpho_tui_menu_defaults[0] - 1))
    if dybatpho::is true "${__dybatpho_tui_menu_multiple}"; then
      for __dybatpho_tui_menu_index in "${__dybatpho_tui_menu_defaults[@]}"; do
        __dybatpho_tui_menu_checked[__dybatpho_tui_menu_index - 1]=1
      done
    fi
  fi

  local __dybatpho_tui_menu_window="${DYBATPHO_TUI_MENU_HEIGHT}"
  ((__dybatpho_tui_menu_window >= 1)) || __dybatpho_tui_menu_window=1
  ((__dybatpho_tui_menu_window <= __dybatpho_tui_menu_count)) \
    || __dybatpho_tui_menu_window="${__dybatpho_tui_menu_count}"

  local __dybatpho_tui_menu_hint
  if dybatpho::is true "${__dybatpho_tui_menu_multiple}"; then
    __dybatpho_tui_menu_hint="$(__dybatpho_log_text tui.hint_multiple \
      "↑/↓ move · space toggle · a all · n none · enter confirm · esc cancel")"
  else
    __dybatpho_tui_menu_hint="$(__dybatpho_log_text tui.hint_single \
      "↑/↓ move · enter select · esc cancel")"
  fi

  local __dybatpho_tui_menu_bold __dybatpho_tui_menu_dim
  local __dybatpho_tui_menu_accent __dybatpho_tui_menu_reset
  __dybatpho_tui_sgr_into __dybatpho_tui_menu_bold "1"
  __dybatpho_tui_sgr_into __dybatpho_tui_menu_dim "2"
  __dybatpho_tui_sgr_into __dybatpho_tui_menu_accent "1;36"
  __dybatpho_tui_sgr_into __dybatpho_tui_menu_reset "0"

  local __dybatpho_tui_menu_top=0 __dybatpho_tui_menu_drawn=0
  local __dybatpho_tui_menu_key
  local __dybatpho_tui_menu_answered=false __dybatpho_tui_menu_cancelled=false
  local __dybatpho_tui_menu_marker __dybatpho_tui_menu_pointer __dybatpho_tui_menu_style

  __dybatpho_tui_hide_cursor
  while true; do
    if ((__dybatpho_tui_menu_cursor < __dybatpho_tui_menu_top)); then
      __dybatpho_tui_menu_top="${__dybatpho_tui_menu_cursor}"
    elif ((__dybatpho_tui_menu_cursor >= __dybatpho_tui_menu_top + __dybatpho_tui_menu_window)); then
      __dybatpho_tui_menu_top=$((__dybatpho_tui_menu_cursor - __dybatpho_tui_menu_window + 1))
    fi

    ((__dybatpho_tui_menu_drawn == 0)) || printf '\033[%dA' "${__dybatpho_tui_menu_drawn}" >&2
    __dybatpho_tui_menu_drawn=0

    printf '\r%s%s%s\033[K\n' "${__dybatpho_tui_menu_bold}" \
      "${__dybatpho_tui_menu_prompt}" "${__dybatpho_tui_menu_reset}" >&2
    __dybatpho_tui_menu_drawn=$((__dybatpho_tui_menu_drawn + 1))

    for ((__dybatpho_tui_menu_index = __dybatpho_tui_menu_top;  \
    __dybatpho_tui_menu_index < __dybatpho_tui_menu_top + __dybatpho_tui_menu_window;  \
    __dybatpho_tui_menu_index++)); do
      if ((__dybatpho_tui_menu_index == __dybatpho_tui_menu_cursor)); then
        __dybatpho_tui_menu_pointer="${DYBATPHO_TUI_POINTER}"
        __dybatpho_tui_menu_style="${__dybatpho_tui_menu_accent}"
      else
        __dybatpho_tui_menu_pointer=" "
        __dybatpho_tui_menu_style=""
      fi
      if dybatpho::is true "${__dybatpho_tui_menu_multiple}"; then
        if ((__dybatpho_tui_menu_checked[__dybatpho_tui_menu_index] == 1)); then
          __dybatpho_tui_menu_marker="${DYBATPHO_TUI_CHECKED} "
        else
          __dybatpho_tui_menu_marker="${DYBATPHO_TUI_UNCHECKED} "
        fi
      else
        __dybatpho_tui_menu_marker=""
      fi
      printf '\r %s %s%s%s%s\033[K\n' "${__dybatpho_tui_menu_pointer}" \
        "${__dybatpho_tui_menu_style}" "${__dybatpho_tui_menu_marker}" \
        "${__dybatpho_tui_menu_items[__dybatpho_tui_menu_index]}" \
        "${__dybatpho_tui_menu_reset}" >&2
      __dybatpho_tui_menu_drawn=$((__dybatpho_tui_menu_drawn + 1))
    done

    printf '\r %s%s%s\033[K\n' "${__dybatpho_tui_menu_dim}" \
      "${__dybatpho_tui_menu_hint}" "${__dybatpho_tui_menu_reset}" >&2
    __dybatpho_tui_menu_drawn=$((__dybatpho_tui_menu_drawn + 1))

    if [[ "${__dybatpho_tui_menu_answered}" == true || "${__dybatpho_tui_menu_cancelled}" == true ]]; then
      break
    fi

    __dybatpho_tui_read_key_into __dybatpho_tui_menu_key
    case "${__dybatpho_tui_menu_key}" in
      up | char:k)
        __dybatpho_tui_menu_cursor=$((__dybatpho_tui_menu_cursor - 1 + __dybatpho_tui_menu_count))
        __dybatpho_tui_menu_cursor=$((__dybatpho_tui_menu_cursor % __dybatpho_tui_menu_count))
        ;;
      down | char:j)
        __dybatpho_tui_menu_cursor=$(((__dybatpho_tui_menu_cursor + 1) % __dybatpho_tui_menu_count))
        ;;
      space)
        dybatpho::is true "${__dybatpho_tui_menu_multiple}" || continue
        if ((__dybatpho_tui_menu_checked[__dybatpho_tui_menu_cursor] == 1)); then
          __dybatpho_tui_menu_checked[__dybatpho_tui_menu_cursor]=0
        else
          __dybatpho_tui_menu_checked[__dybatpho_tui_menu_cursor]=1
        fi
        ;;
      char:a)
        dybatpho::is true "${__dybatpho_tui_menu_multiple}" || continue
        for ((__dybatpho_tui_menu_index = 0;  \
        __dybatpho_tui_menu_index < __dybatpho_tui_menu_count;  \
        __dybatpho_tui_menu_index++)); do
          __dybatpho_tui_menu_checked[__dybatpho_tui_menu_index]=1
        done
        ;;
      char:n)
        dybatpho::is true "${__dybatpho_tui_menu_multiple}" || continue
        for ((__dybatpho_tui_menu_index = 0;  \
        __dybatpho_tui_menu_index < __dybatpho_tui_menu_count;  \
        __dybatpho_tui_menu_index++)); do
          __dybatpho_tui_menu_checked[__dybatpho_tui_menu_index]=0
        done
        ;;
      enter) __dybatpho_tui_menu_answered=true ;;
      escape | char:q | eof) __dybatpho_tui_menu_cancelled=true ;;
      *) ;;
    esac
  done

  # Erase the widget so the transcript keeps the answer rather than the menu.
  printf '\033[%dA' "${__dybatpho_tui_menu_drawn}" >&2
  for ((__dybatpho_tui_menu_index = 0;  \
  __dybatpho_tui_menu_index < __dybatpho_tui_menu_drawn;  \
  __dybatpho_tui_menu_index++)); do
    printf '\r\033[K\n' >&2
  done
  printf '\033[%dA' "${__dybatpho_tui_menu_drawn}" >&2
  __dybatpho_tui_show_cursor

  if [[ "${__dybatpho_tui_menu_cancelled}" == true ]]; then
    dybatpho::warn "${__dybatpho_tui_menu_prompt}: cancelled"
    return 1
  fi

  local -a __dybatpho_tui_menu_selected=() __dybatpho_tui_menu_positions=()
  # As in the fallback: one nameref, an array for a multi-select and a scalar
  # for a single one, and only one of the branches ever runs for a caller.
  # shellcheck disable=SC2178,SC2128,SC2034
  if dybatpho::is true "${__dybatpho_tui_menu_multiple}"; then
    for ((__dybatpho_tui_menu_index = 0;  \
    __dybatpho_tui_menu_index < __dybatpho_tui_menu_count;  \
    __dybatpho_tui_menu_index++)); do
      ((__dybatpho_tui_menu_checked[__dybatpho_tui_menu_index] == 1)) || continue
      __dybatpho_tui_menu_selected+=("${__dybatpho_tui_menu_items[__dybatpho_tui_menu_index]}")
      __dybatpho_tui_menu_positions+=("$((__dybatpho_tui_menu_index + 1))")
    done
    DYBATPHO_TUI_INDEXES="${__dybatpho_tui_menu_positions[*]-}"
    # shellcheck disable=SC2034
    __dybatpho_tui_menu_out=(${__dybatpho_tui_menu_selected[@]+"${__dybatpho_tui_menu_selected[@]}"})
    printf '%s%s%s %s\n' "${__dybatpho_tui_menu_bold}" "${__dybatpho_tui_menu_prompt}" \
      "${__dybatpho_tui_menu_reset}" "${__dybatpho_tui_menu_selected[*]-}" >&2
  else
    DYBATPHO_TUI_INDEX=$((__dybatpho_tui_menu_cursor + 1))
    # shellcheck disable=SC2034 # output for the caller; nothing in this module reads it back
    DYBATPHO_TUI_INDEXES="${DYBATPHO_TUI_INDEX}"
    # Single-select hands back a scalar, multi-select an array. See the same
    # note in `__dybatpho_tui_menu_fallback`.
    # shellcheck disable=SC2178 # nameref to the caller's variable, a scalar here
    __dybatpho_tui_menu_out="${__dybatpho_tui_menu_items[__dybatpho_tui_menu_cursor]}"
    # shellcheck disable=SC2128 # the same nameref, holding that scalar
    printf '%s%s%s %s\n' "${__dybatpho_tui_menu_bold}" "${__dybatpho_tui_menu_prompt}" \
      "${__dybatpho_tui_menu_reset}" "${__dybatpho_tui_menu_out}" >&2
  fi
  return 0
  # kcov(enabled)
}

#######################################
# @description Ask the user to pick one entry from a list.
#
#   The answer comes back through a named variable rather than on stdout,
#   because both renderings write to stderr and a `$( )` around the call would
#   swallow the menu it is supposed to show.
# @example
#   local environment
#   dybatpho::tui_menu environment "Deploy to which environment?" dev staging prod \
#     || dybatpho::die "No environment chosen"
#   dybatpho::info "Deploying to ${environment} (entry ${DYBATPHO_TUI_INDEX})"
#
# @arg $1 string Name of the variable receiving the chosen entry
# @arg $2 string Prompt text
# @arg $@ string Menu entries, at least one
# @set The named variable to the chosen entry
# @set DYBATPHO_TUI_INDEX number 1-based position of the chosen entry
# @set DYBATPHO_TUI_INDEXES string The same position, for symmetry with the multi-select
# @stderr The menu, drawn in place or printed as a numbered list
# @exitcode 1 The menu was cancelled, or nothing could be read and no default was set
# @env DYBATPHO_TUI_DEFAULT string 1-based entry the menu starts on, and the answer used when it cannot ask
# @tip Arrow keys and `j`/`k` both move, `enter` selects, and `esc` or `q` cancels
# @note Feed the numbered fallback with a redirect (`< <(printf '2\n')`), never with a pipe. A pipe runs the call in a
#   subshell, where the answer is written to a copy of the caller's variable and is lost on return.
#######################################
function dybatpho::tui_menu {
  local result_var prompt
  dybatpho::expect_args result_var prompt -- "$@"
  dybatpho::expect_ref "${result_var}"
  shift 2
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one menu entry"

  if dybatpho::tui_supported; then
    __dybatpho_tui_menu_interactive "${result_var}" false "${prompt}" "$@"
    return $?
  fi
  __dybatpho_tui_menu_fallback "${result_var}" false "${prompt}" "$@"
}

#######################################
# @description Ask the user to pick any number of entries from a list.
#
#   The answer comes back in a named array, so entries holding spaces survive a
#   round trip that a space-separated string would lose.
# @example
#   local -a components=()
#   dybatpho::tui_multi_menu components "Which components?" api worker scheduler \
#     || dybatpho::die "No component chosen"
#   dybatpho::info "Deploying ${#components[@]} components"
#
# @arg $1 string Name of the array variable receiving the chosen entries
# @arg $2 string Prompt text
# @arg $@ string Menu entries, at least one
# @set The named array to the chosen entries, in menu order
# @set DYBATPHO_TUI_INDEXES string Space-separated 1-based positions of the chosen entries
# @stderr The menu, drawn in place or printed as a numbered list
# @exitcode 1 The menu was cancelled, or nothing could be read and no default was set
# @env DYBATPHO_TUI_DEFAULT string Comma-separated entries preselected, and the answer used when the menu cannot ask
# @tip `space` toggles an entry, `a` selects every entry and `n` clears them all; the numbered fallback takes the same
#   list
#   as `1,3`
# @note In the drawn menu, confirming with nothing toggled is a valid answer and returns an empty array, which is how
#   "none
#   of these" is said. The numbered fallback has no such keystroke, so an empty line there takes `DYBATPHO_TUI_DEFAULT`
#   or fails
# @note Feed the numbered fallback with a redirect rather than a pipe, for the reason given on `dybatpho::tui_menu`
#######################################
function dybatpho::tui_multi_menu {
  local result_var prompt
  dybatpho::expect_args result_var prompt -- "$@"
  dybatpho::expect_ref "${result_var}"
  shift 2
  (($# > 0)) || dybatpho::die "${FUNCNAME[0]}: Expected at least one menu entry"

  if dybatpho::tui_supported; then
    __dybatpho_tui_menu_interactive "${result_var}" true "${prompt}" "$@"
    return $?
  fi
  __dybatpho_tui_menu_fallback "${result_var}" true "${prompt}" "$@"
}

#######################################
# @description Ask a yes/no question with the answer shown as a choice rather
#   than as a `[y/N]` hint.
#
#   Off a terminal this is `dybatpho::confirm`: the same `DYBATPHO_FORCE`
#   override, the same refusal to guess in an unattended shell, the same exit
#   codes. On a terminal the two answers are drawn side by side with the default
#   highlighted, `←`/`→` move between them, and `y`/`n` still answer directly.
# @example
#   dybatpho::tui_confirm "Delete the staging database?" no \
#     || dybatpho::die "Cancelled"
#
# @arg $1 string Question to ask
# @arg $2 string Optional default answer used on `enter`, default is `no`
# @stderr The question; nothing reaches stdout
# @exitcode 0 The answer is yes, or `DYBATPHO_FORCE` is enabled
# @exitcode 1 The answer is no, the question was cancelled, or the script is not interactive
# @env DYBATPHO_FORCE bool Answer yes without asking
# @tip The question is the whole contract: a `--force` flag bound to `DYBATPHO_FORCE` makes every one of them answer yes
#   at
#   once
#######################################
function dybatpho::tui_confirm {
  local question
  dybatpho::expect_args question -- "$@"
  local default_answer="${2:-no}"

  # shellcheck disable=SC2154 # declared by `src/safety.sh`
  if dybatpho::is true "${DYBATPHO_FORCE}"; then
    dybatpho::debug "DYBATPHO_FORCE answers yes: ${question}"
    return 0
  fi
  if ! dybatpho::tui_supported; then
    dybatpho::confirm "${question}" "${default_answer}"
    return $?
  fi

  # kcov(disabled)
  local yes=1
  dybatpho::is true "${default_answer}" || yes=0

  local bold accent dim reset key line
  local answered=false cancelled=false drawn=false
  __dybatpho_tui_sgr_into bold "1"
  __dybatpho_tui_sgr_into accent "1;7;36"
  __dybatpho_tui_sgr_into dim "2"
  __dybatpho_tui_sgr_into reset "0"

  local yes_label no_label hint
  yes_label="$(__dybatpho_log_text tui.yes "Yes")"
  no_label="$(__dybatpho_log_text tui.no "No")"
  hint="$(__dybatpho_log_text tui.hint_confirm "←/→ move · enter confirm · esc cancel")"

  __dybatpho_tui_hide_cursor
  while true; do
    local yes_style="" no_style=""
    if ((yes == 1)); then
      yes_style="${accent}"
    else
      no_style="${accent}"
    fi
    printf -v line '%s%s%s  %s %s %s  %s %s %s   %s%s%s' \
      "${bold}" "${question}" "${reset}" \
      "${yes_style}" "${yes_label}" "${reset}" \
      "${no_style}" "${no_label}" "${reset}" \
      "${dim}" "${hint}" "${reset}"
    __dybatpho_tui_draw_line "${line}"
    drawn=true

    if [[ "${answered}" == true || "${cancelled}" == true ]]; then
      break
    fi

    __dybatpho_tui_read_key_into key
    case "${key}" in
      left | right | up | down | char:h | char:l | char:j | char:k | space)
        yes=$((1 - yes))
        ;;
      char:y | char:Y)
        yes=1
        answered=true
        ;;
      char:n | char:N)
        yes=0
        answered=true
        ;;
      enter) answered=true ;;
      escape | char:q | eof) cancelled=true ;;
      *) ;;
    esac
  done

  [[ "${drawn}" == true ]] && __dybatpho_tui_erase_line
  __dybatpho_tui_show_cursor

  if [[ "${cancelled}" == true ]]; then
    dybatpho::warn "${question}: cancelled"
    return 1
  fi
  if ((yes == 1)); then
    printf '%s%s%s %s\n' "${bold}" "${question}" "${reset}" "${yes_label}" >&2
    return 0
  fi
  printf '%s%s%s %s\n' "${bold}" "${question}" "${reset}" "${no_label}" >&2
  return 1
  # kcov(enabled)
}
