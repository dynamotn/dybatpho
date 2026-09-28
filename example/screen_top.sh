#!/usr/bin/env bash
# @file screen_top.sh
# @brief A complete process viewer built on the screen module
# @description
#   A working `top`-like application: a sortable, filterable, scrollable table
#   of every running process, with CPU and memory gauges, history sparklines, a
#   detail panel for the selection, and a confirmation dialog for sending a
#   signal.
#
#   It is a full application rather than a tour of the widgets, so it shows the
#   parts an application needs and a widget gallery does not: collecting data
#   portably, re-collecting on a timer without blocking the keyboard, a text
#   input mode for the filter, a modal dialog, and a redraw that survives a
#   resize.
#
#   ```sh
#   bash example/screen_top.sh                 # interactive
#   bash example/screen_top.sh --sort mem      # start sorted by memory
#   bash example/screen_top.sh --filter ssh    # start filtered
#   bash example/screen_top.sh --once          # one frame to stdout, then exit
#   ```
#
#   ## Keys
#
#   | Key | Action |
#   | --- | --- |
#   | `↑` `↓` `j` `k` | Move the selection |
#   | `PgUp` `PgDn` `Home` `End` | Move a page, or to either end |
#   | `c` `m` `p` `n` | Sort by CPU, memory, PID, or name |
#   | `r` | Reverse the sort |
#   | `/` | Filter; type, `Enter` to keep it, `Esc` to drop it |
#   | `K` | Signal the selected process, after a confirmation |
#   | `Tab` | Switch between the process list and the help |
#   | `F5` `.` | Refresh now |
#   | `q` `Esc` | Quit |
#
#   Without a terminal -- in a pipeline, in CI, under the example suite -- it
#   renders one frame to stdout and exits, which is what `--once` forces.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules screen cli

dybatpho::register_common_handlers

# Every process as `pid ppid user cpu mem rss stat command`, already sorted.
declare -a PROCESSES=()
# The rows currently shown, after filtering, as the table's delimited strings.
declare -a VISIBLE=()
# The `pid` of each visible row, so the selection maps back to a real process.
declare -a VISIBLE_PIDS=()
declare -a CPU_HISTORY=()
declare -a MEM_HISTORY=()
declare -a TAB_NAMES=(Processes Help)

CURSOR=0
TOP_TAB=0
MODE="list"
FILTER_DRAFT=""
STATUS=""
CPU_PERCENT=0
MEM_PERCENT=0
MEM_TOTAL_KB=0
MEM_USED_KB=0
CPU_COUNT=1
REVERSE=false
RUNNING=true

readonly HISTORY_LIMIT=240

#######################################
# @description Collect every process, normalised to
#   `pid ppid user cpu mem rss stat command` and sorted by the current key.
#
#   Three `ps` spellings are tried. The first is what GNU and BSD both accept
#   and prints no header; the second is the same without the `=` suffixes, for
#   a `ps` that rejects them; the third rearranges `ps aux`, which is all a
#   BusyBox `ps` may offer. An example runs in CI on more than one of these.
#######################################
function _collect {
  local raw=""
  raw="$(ps -eo pid=,ppid=,user=,pcpu=,pmem=,rss=,stat=,args= 2> /dev/null)" || raw=""
  if [[ -z "${raw}" ]]; then
    raw="$(ps -eo pid,ppid,user,pcpu,pmem,rss,stat,args 2> /dev/null | tail -n +2)" || raw=""
  fi
  if [[ -z "${raw}" ]]; then
    raw="$(ps aux 2> /dev/null | tail -n +2 \
      | awk '{printf "%s 0 %s %s %s %s %s ", $2, $1, $3, $4, $6, $8
              for (i = 11; i <= NF; i++) printf "%s ", $i
              print ""}')" || raw=""
  fi

  local key direction="" sorted=""
  case "${SORT_BY}" in
    cpu) key="-k4,4" direction="-rn" ;;
    mem) key="-k5,5" direction="-rn" ;;
    pid) key="-k1,1" direction="-n" ;;
    *) key="-k8,8" direction="" ;;
  esac
  if dybatpho::is true "${REVERSE}"; then
    case "${direction}" in
      -rn) direction="-n" ;;
      -n) direction="-rn" ;;
      *) direction="-r" ;;
    esac
  fi

  if [[ -n "${raw}" ]]; then
    # One `sort` per refresh rather than a comparison ladder in Bash: sorting
    # several hundred rows in the shell costs far more than the process does.
    # shellcheck disable=SC2086
    sorted="$(printf '%s\n' "${raw}" | LC_ALL=C sort ${key} ${direction} 2> /dev/null)" \
      || sorted="${raw}"
  fi

  PROCESSES=()
  local line
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    PROCESSES+=("${line}")
  done <<< "${sorted}"

  _measure_totals
}

#######################################
# @description Work out the CPU and memory pressure shown in the gauges, and
#   append both to the history the sparklines draw.
#######################################
function _measure_totals {
  local line pid ppid user cpu mem rss stat command
  local cpu_sum=0 mem_sum=0 cpu_whole mem_whole

  for line in ${PROCESSES[@]+"${PROCESSES[@]}"}; do
    read -r pid ppid user cpu mem rss stat command <<< "${line}"
    # The values carry one decimal; the fraction is noise at this scale and
    # dropping it keeps the arithmetic in the shell's integers.
    cpu_whole="${cpu%%.*}"
    mem_whole="${mem%%.*}"
    [[ "${cpu_whole}" =~ ^[0-9]+$ ]] && cpu_sum=$((cpu_sum + cpu_whole))
    [[ "${mem_whole}" =~ ^[0-9]+$ ]] && mem_sum=$((mem_sum + mem_whole))
  done

  CPU_PERCENT=$((cpu_sum / CPU_COUNT))
  ((CPU_PERCENT <= 100)) || CPU_PERCENT=100

  # `/proc/meminfo` is exact where it exists; the sum of per-process shares is
  # the portable approximation everywhere else.
  MEM_PERCENT="${mem_sum}"
  if [[ -r /proc/meminfo ]]; then
    local total=0 available=0 field value
    while read -r field value _; do
      case "${field}" in
        MemTotal:) total="${value}" ;;
        MemAvailable:) available="${value}" ;;
      esac
    done < /proc/meminfo
    if ((total > 0)); then
      MEM_TOTAL_KB="${total}"
      MEM_USED_KB=$((total - available))
      MEM_PERCENT=$((MEM_USED_KB * 100 / total))
    fi
  fi
  ((MEM_PERCENT <= 100)) || MEM_PERCENT=100

  CPU_HISTORY+=("${CPU_PERCENT}")
  MEM_HISTORY+=("${MEM_PERCENT}")
  ((${#CPU_HISTORY[@]} <= HISTORY_LIMIT)) || CPU_HISTORY=("${CPU_HISTORY[@]: -HISTORY_LIMIT}")
  ((${#MEM_HISTORY[@]} <= HISTORY_LIMIT)) || MEM_HISTORY=("${MEM_HISTORY[@]: -HISTORY_LIMIT}")
}

#######################################
# @description Print a size in kilobytes the way a person reads it.
# @arg $1 string Name of the variable receiving the text
# @arg $2 number Size in kilobytes
#######################################
function _format_size {
  local -n _size_out="$1"
  local kilobytes="${2:-0}"
  [[ "${kilobytes}" =~ ^[0-9]+$ ]] || kilobytes=0
  if ((kilobytes >= 1048576)); then
    printf -v _size_out '%s.%sG' "$((kilobytes / 1048576))" "$((kilobytes % 1048576 * 10 / 1048576))"
  elif ((kilobytes >= 1024)); then
    printf -v _size_out '%sM' "$((kilobytes / 1024))"
  else
    printf -v _size_out '%sK' "${kilobytes}"
  fi
}

#######################################
# @description Rebuild the visible rows from the processes and the filter, and
#   keep the selection inside them.
# @arg $1 number Width available for the command column
#######################################
function _rebuild_visible {
  local command_width="${1:-40}"
  ((command_width > 4)) || command_width=4

  VISIBLE=()
  VISIBLE_PIDS=()
  local line pid ppid user cpu mem rss stat command size shown
  for line in ${PROCESSES[@]+"${PROCESSES[@]}"}; do
    read -r pid ppid user cpu mem rss stat command <<< "${line}"
    if [[ -n "${FILTER}" ]]; then
      # Match the command or the user, case-insensitively, as a substring
      # rather than a pattern: a filter is typed in a hurry and should not need
      # escaping.
      local haystack="${command,,} ${user,,} ${pid}"
      [[ "${haystack}" == *"${FILTER,,}"* ]] || continue
    fi
    _format_size size "${rss}"
    # The table cuts a cell to its column, so the command is handed over whole
    # rather than trimmed twice.
    shown="${command}"
    VISIBLE+=("${pid}|${user}|${cpu}|${mem}|${size}|${shown}")
    VISIBLE_PIDS+=("${pid}")
  done

  if ((${#VISIBLE[@]} == 0)); then
    CURSOR=0
  elif ((CURSOR >= ${#VISIBLE[@]})); then
    CURSOR=$((${#VISIBLE[@]} - 1))
  fi
  ((CURSOR >= 0)) || CURSOR=0
}

#######################################
# @description Draw the header: the two gauges and their history sparklines.
# @arg $1 string Rectangle to draw in
#######################################
function _draw_header {
  local -a halves=() cpu_parts=() mem_parts=()
  dybatpho::screen_layout halves horizontal "$1" ratio:1/2 ratio:1/2

  dybatpho::screen_block "${halves[0]}" title:"CPU" border:rounded
  dybatpho::screen_layout cpu_parts vertical "${DYBATPHO_SCREEN_INNER}" length:1 fill:1
  local cpu_style="1;32"
  ((CPU_PERCENT >= 75)) && cpu_style="1;31"
  ((CPU_PERCENT >= 50 && CPU_PERCENT < 75)) && cpu_style="1;33"
  dybatpho::screen_gauge "${cpu_parts[0]}" "${CPU_PERCENT}" 100 \
    label:"${CPU_PERCENT}% of ${CPU_COUNT} cores" style:"${cpu_style}"
  dybatpho::screen_sparkline "${cpu_parts[1]}" CPU_HISTORY max:100 style:"36"

  dybatpho::screen_block "${halves[1]}" title:"Memory" border:rounded
  dybatpho::screen_layout mem_parts vertical "${DYBATPHO_SCREEN_INNER}" length:1 fill:1
  local mem_label="${MEM_PERCENT}%"
  if ((MEM_TOTAL_KB > 0)); then
    local used total
    _format_size used "${MEM_USED_KB}"
    _format_size total "${MEM_TOTAL_KB}"
    mem_label="${used} / ${total}"
  fi
  local mem_style="1;32"
  ((MEM_PERCENT >= 75)) && mem_style="1;31"
  ((MEM_PERCENT >= 50 && MEM_PERCENT < 75)) && mem_style="1;33"
  dybatpho::screen_gauge "${mem_parts[0]}" "${MEM_PERCENT}" 100 \
    label:"${mem_label}" style:"${mem_style}"
  dybatpho::screen_sparkline "${mem_parts[1]}" MEM_HISTORY max:100 style:"35"
}

#######################################
# @description Draw the detail panel for the selected process.
# @arg $1 string Rectangle to draw in
#######################################
function _draw_detail {
  local title="Detail"
  dybatpho::screen_block "$1" title:"${title}"
  local inner="${DYBATPHO_SCREEN_INNER}"
  local x y width height
  read -r x y width height <<< "${inner}"
  ((width > 0 && height > 0)) || return 0

  if ((${#VISIBLE[@]} == 0)); then
    dybatpho::screen_text "${inner}" "No process matches the filter." align:center style:"2"
    return 0
  fi

  local wanted="${VISIBLE_PIDS[CURSOR]}"
  local line pid ppid user cpu mem rss stat command
  for line in ${PROCESSES[@]+"${PROCESSES[@]}"}; do
    read -r pid ppid user cpu mem rss stat command <<< "${line}"
    [[ "${pid}" == "${wanted}" ]] && break
  done

  local size
  _format_size size "${rss}"
  dybatpho::screen_put "${y}" "${x}" "PID ${pid}   PPID ${ppid}   USER ${user}   STATE ${stat}" "1"
  ((height > 1)) && dybatpho::screen_put "$((y + 1))" "${x}" \
    "CPU ${cpu}%   MEM ${mem}%   RSS ${size}" "0"
  if ((height > 2)); then
    local command_rect
    dybatpho::screen_rect command_rect "${x}" "$((y + 2))" "${width}" "$((height - 2))"
    dybatpho::screen_text "${command_rect}" "${command}" style:"2"
  fi
}

#######################################
# @description Draw the help tab.
# @arg $1 string Rectangle to draw in
#######################################
function _draw_help {
  dybatpho::screen_block "$1" title:"Keys" border:rounded
  local -a keys=(
    "↑ ↓ j k          move the selection"
    "PgUp PgDn        move a page"
    "Home End         jump to either end"
    "c m p n          sort by cpu, memory, pid, name"
    "r                reverse the sort"
    "/                filter; Enter keeps it, Esc drops it"
    "K                signal the selected process"
    "Tab              switch tab"
    "F5 or .          refresh now"
    "q Esc            quit"
  )
  local index inner="${DYBATPHO_SCREEN_INNER}"
  local x y width height
  read -r x y width height <<< "${inner}"
  for ((index = 0; index < ${#keys[@]} && index < height; index++)); do
    dybatpho::screen_put "$((y + index))" "$((x + 1))" "${keys[index]}" "0"
  done
}

#######################################
# @description Draw the whole frame into the buffer.
#######################################
function _draw {
  dybatpho::screen_clear

  local -a frame=()
  dybatpho::screen_layout frame vertical "${DYBATPHO_SCREEN_RECT}" \
    length:1 length:4 fill:1 length:6 length:1

  dybatpho::screen_tabs "${frame[0]}" TAB_NAMES active:"${TOP_TAB}"

  if ((TOP_TAB == 1)); then
    _draw_header "${frame[1]}"
    _draw_help "${frame[2]}"
    _draw_status "${frame[4]}"
    return 0
  fi

  _draw_header "${frame[1]}"

  local title="Processes"
  [[ -n "${FILTER}" ]] && title="Processes  filter: ${FILTER}"
  dybatpho::screen_block "${frame[2]}" title:"${title}" border:rounded

  # The scrollbar lives inside the block, in its last column and below the
  # header row, so the thumb lines up with the rows it is describing rather
  # than with the border.
  local -a body=()
  dybatpho::screen_layout body horizontal "${DYBATPHO_SCREEN_INNER}" fill:1 length:1
  local table_rect="${body[0]}"

  # Only the width of the table and the position of the scrollbar column are
  # needed; the rest of each rectangle is read into `_` rather than into names
  # that would then go unused.
  local table_width bx by bh
  read -r _ _ table_width _ <<< "${table_rect}"
  read -r bx by _ bh <<< "${body[1]}"
  local scroll_rect
  dybatpho::screen_rect scroll_rect "${bx}" "$((by + 1))" 1 "$((bh - 1))"

  # Each fixed column carries its own trailing space: the table pads a cell to
  # its column and nothing separates one from the next, so a value that fills
  # its width exactly would touch the column beside it. A seven-digit PID in a
  # seven-wide column is how that shows up.
  local pid_w=8 user_w=12 cpu_w=7 mem_w=7 rss_w=9
  local command_w=$((table_width - pid_w - user_w - cpu_w - mem_w - rss_w))
  ((command_w > 4)) || command_w=4

  _rebuild_visible "${command_w}"

  dybatpho::screen_table "${table_rect}" VISIBLE \
    header:"PID|USER|CPU%|MEM%|RSS|COMMAND" \
    widths:"${pid_w},${user_w},${cpu_w},${mem_w},${rss_w},${command_w}" \
    selected:"${CURSOR}"
  # A lighter track than the default: the scrollbar sits directly against the
  # block's own border, and two solid verticals side by side read as a second
  # border rather than as a scrollbar.
  dybatpho::screen_scrollbar "${scroll_rect}" "${DYBATPHO_SCREEN_OFFSET}" "${#VISIBLE[@]}" \
    track:"┊"

  _draw_detail "${frame[3]}"
  _draw_status "${frame[4]}"

  if [[ "${MODE}" == "confirm" ]]; then
    local box
    dybatpho::screen_rect_center box "${DYBATPHO_SCREEN_RECT}" 46 7
    dybatpho::screen_popup "${box}" title:"Signal process" border:double
    local pid="${VISIBLE_PIDS[CURSOR]-}"
    dybatpho::screen_text "${DYBATPHO_SCREEN_INNER}" \
      $'Send SIGTERM to PID '"${pid}"$'?\n\ny = yes    n = cancel' align:center
  fi
}

#######################################
# @description Draw the status line, which is also the filter's input field.
# @arg $1 string Rectangle to draw in
#######################################
function _draw_status {
  local text style="7"
  case "${MODE}" in
    filter)
      text=" filter: ${FILTER_DRAFT}_   (Enter to keep, Esc to drop)"
      style="1;7;33"
      ;;
    confirm)
      text=" y to send SIGTERM, n to cancel"
      style="1;7;31"
      ;;
    *)
      local order="${SORT_BY}"
      dybatpho::is true "${REVERSE}" && order="${order} reversed"
      text=" ${#VISIBLE[@]}/${#PROCESSES[@]} processes   sort: ${order}   q quit   Tab help"
      [[ -n "${STATUS}" ]] && text=" ${STATUS}"
      ;;
  esac
  local x y width height padded
  read -r x y width height <<< "$1"
  __dybatpho_screen_align_into padded "${text}" "${width}" left
  dybatpho::screen_put "${y}" "${x}" "${padded}" "${style}"
}

#######################################
# @description Act on one key while the process list has focus.
# @arg $1 string Event name
#######################################
function _handle_list_key {
  local page=$((DYBATPHO_SCREEN_HEIGHT - 12))
  ((page > 0)) || page=1
  local count=${#VISIBLE[@]}

  case "$1" in
    char:q | escape) RUNNING=false ;;
    up | char:k) ((count > 0)) && CURSOR=$(((CURSOR - 1 + count) % count)) ;;
    down | char:j) ((count > 0)) && CURSOR=$(((CURSOR + 1) % count)) ;;
    pageup)
      CURSOR=$((CURSOR - page))
      ((CURSOR >= 0)) || CURSOR=0
      ;;
    pagedown)
      CURSOR=$((CURSOR + page))
      ((count > 0 && CURSOR >= count)) && CURSOR=$((count - 1))
      ;;
    home) CURSOR=0 ;;
    end) ((count > 0)) && CURSOR=$((count - 1)) ;;
    char:c)
      SORT_BY="cpu"
      _collect
      ;;
    char:m)
      SORT_BY="mem"
      _collect
      ;;
    char:p)
      SORT_BY="pid"
      _collect
      ;;
    char:n)
      SORT_BY="name"
      _collect
      ;;
    char:r)
      if dybatpho::is true "${REVERSE}"; then REVERSE=false; else REVERSE=true; fi
      _collect
      ;;
    char:/)
      MODE="filter"
      FILTER_DRAFT="${FILTER}"
      ;;
    char:K)
      ((${#VISIBLE[@]} > 0)) && MODE="confirm"
      ;;
    tab) TOP_TAB=$(((TOP_TAB + 1) % ${#TAB_NAMES[@]})) ;;
    char:. | f5)
      STATUS=""
      _collect
      ;;
    resize) dybatpho::screen_size || true ;;
    eof) RUNNING=false ;;
  esac
  return 0
}

#######################################
# @description Act on one key while the filter is being typed.
# @arg $1 string Event name
#######################################
function _handle_filter_key {
  case "$1" in
    enter)
      FILTER="${FILTER_DRAFT}"
      MODE="list"
      CURSOR=0
      ;;
    escape)
      MODE="list"
      FILTER_DRAFT=""
      ;;
    backspace) FILTER_DRAFT="${FILTER_DRAFT%?}" ;;
    space) FILTER_DRAFT+=" " ;;
    char:*) FILTER_DRAFT+="${1#char:}" ;;
    resize) dybatpho::screen_size || true ;;
    eof) RUNNING=false ;;
  esac
  return 0
}

#######################################
# @description Act on one key while the signal dialog is up.
#
#   Only an explicit `y` sends anything: every other key, including `Enter`,
#   cancels. A dialog that a stray keystroke can confirm is worse than no
#   dialog, because it reads as a safeguard.
# @arg $1 string Event name
#######################################
function _handle_confirm_key {
  case "$1" in
    char:y | char:Y)
      local pid="${VISIBLE_PIDS[CURSOR]-}"
      if [[ -n "${pid}" ]] && kill -TERM "${pid}" 2> /dev/null; then
        STATUS="Sent SIGTERM to PID ${pid}"
      else
        STATUS="Could not signal PID ${pid:-?}"
      fi
      MODE="list"
      _collect
      ;;
    resize) dybatpho::screen_size || true ;;
    eof) RUNNING=false ;;
    *) MODE="list" ;;
  esac
  return 0
}

#######################################
# @description Return success when there is a terminal to take over.
#   Both ends matter: keys come from stdin and the frame goes to the terminal,
#   and a run with either redirected is a run that has to draw once and stop.
#######################################
function _has_terminal {
  [[ -t 0 && -t 1 && -e /dev/tty ]]
}

#######################################
# @description Render one frame to stdout, for a run with no terminal.
#######################################
function _render_once {
  export COLUMNS="${COLUMNS:-100}" LINES="${LINES:-30}"
  dybatpho::screen_size || true
  _draw
  local row rendered
  for ((row = 0; row < DYBATPHO_SCREEN_HEIGHT; row++)); do
    __dybatpho_screen_render_into rendered "${row}"
    printf '%s\n' "${rendered}"
  done
}

#######################################
# @description Take over the terminal and run until the user quits.
#######################################
function _run_interactive {
  dybatpho::screen_begin || return 1
  local key
  while dybatpho::is true "${RUNNING}"; do
    _draw
    dybatpho::screen_flush
    # The refresh is the read's deadline rather than a sleep, so the keyboard
    # stays live between refreshes instead of being ignored for a second at a
    # time.
    if ! dybatpho::screen_event key "${INTERVAL}"; then
      _collect
      continue
    fi
    case "${MODE}" in
      filter) _handle_filter_key "${key}" ;;
      confirm) _handle_confirm_key "${key}" ;;
      *) _handle_list_key "${key}" ;;
    esac
  done
  dybatpho::screen_end
  return 0
}

function _main {
  CPU_COUNT="$(dybatpho::cpu_count)"
  ((CPU_COUNT > 0)) || CPU_COUNT=1

  case "${SORT_BY}" in
    cpu | mem | pid | name) ;;
    *) dybatpho::die "--sort takes cpu, mem, pid or name, got '${SORT_BY}'" ;;
  esac
  [[ "${INTERVAL}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || dybatpho::die "--interval takes a number of seconds, got '${INTERVAL}'"

  _collect

  # No terminal, or asked for a single frame: draw once and leave. This is the
  # path the example suite takes, and it is why this file can be an example at
  # all rather than something that waits forever for a keystroke.
  if dybatpho::is true "${ONCE}" || ! _has_terminal; then
    _render_once
    return 0
  fi
  _run_interactive
}

function _spec {
  dybatpho::opts::setup "A process viewer drawn with the screen module" ARGS action:"_main"

  dybatpho::opts::param "Seconds between refreshes" INTERVAL -i --interval init:="2"
  dybatpho::opts::param "Initial sort: cpu, mem, pid or name" SORT_BY -s --sort init:="cpu"
  dybatpho::opts::param "Only show processes matching this text" FILTER -f --filter init:=""
  dybatpho::opts::flag "Render one frame to stdout and exit" ONCE --once on:true off:false init:="false"

  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

dybatpho::generate_from_spec _spec "$@"
