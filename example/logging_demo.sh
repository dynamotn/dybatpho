#!/usr/bin/env bash
# @file logging_demo.sh
# @brief Example showing all logging and tracing utilities
# @description Demonstrates every logging function: debug, info, warn, error, fatal,
#              progress, progress_bar, spinner, header, success, start/end trace,
#              structured JSON output enriched with request ID/hostname/PID/duration,
#              context fields, step timers, and file logging with rotation and
#              independent verbosity
# shellcheck disable=SC2030,SC2031 # the subshells scope LOG_* on purpose, so each demo
#   section restores the caller's logging configuration by construction.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# @description Run the `LOG LEVELS` section of this example.
# @noargs
function _demo_log_levels {
  dybatpho::header "LOG LEVELS"
  dybatpho::info "Set LOG_LEVEL=debug to see debug messages (current: ${LOG_LEVEL:-info})"

  dybatpho::debug "This debug message is hidden unless LOG_LEVEL=debug"
  dybatpho::info "This is an informational message"
  dybatpho::warn "This is a warning — something looks off"
  dybatpho::error "This is an error — something went wrong (non-fatal)"
  # dybatpho::fatal "This would log + exit immediately — skipped in demo"
  dybatpho::success "This operation completed successfully"
}

# @description Run the `PRINT vs INFO` section of this example.
# @noargs
function _demo_print {
  dybatpho::header "PRINT vs INFO"
  dybatpho::info "dybatpho::info goes to STDERR (always visible)"
  dybatpho::print "dybatpho::print goes to STDOUT (can be piped/captured)"
}

# @description Run the `PROGRESS INDICATOR` section of this example.
# @noargs
function _demo_progress {
  dybatpho::header "PROGRESS INDICATOR"
  dybatpho::progress "Doing something important..."
  sleep 0.3
  dybatpho::progress "Still working..."
  sleep 0.3
  dybatpho::success "Done!"
}

# @description Run the `PROGRESS BAR` section of this example.
# @noargs
function _demo_progress_bar {
  dybatpho::header "PROGRESS BAR"
  dybatpho::info "Simulating a 10-step task..."
  local total_steps=10
  local bar_width=30
  local step percentage
  for ((step = 1; step <= total_steps; step++)); do
    percentage=$((step * 100 / total_steps))
    dybatpho::progress_bar "${percentage}" "${bar_width}"
    sleep 0.1
  done
  printf '\n' >&2
  dybatpho::success "Task complete!"
}

# @description Run the `DEBUG COMMAND` section of this example.
# @noargs
function _demo_debug_command {
  dybatpho::header "DEBUG COMMAND"
  dybatpho::info "Capturing output of 'ls example/' as debug:"
  dybatpho::debug_command \
    "Listing example directory" \
    "ls '$(dirname "${BASH_SOURCE[0]}")'"
}

# @description Run the `TRACE (start/end)` section of this example.
# @noargs
function _demo_trace {
  dybatpho::header "TRACE (start/end)"
  dybatpho::info "Enabling trace for a small block..."
  dybatpho::start_trace
  local x=42
  local y=$((x * 2))
  echo "x=${x}, y=${y}" >&2
  dybatpho::end_trace
  dybatpho::info "Trace disabled again"
}

# @description Run the `STRUCTURED JSON CONTEXT` section of this example.
# @noargs
function _demo_json_context {
  dybatpho::header "STRUCTURED JSON CONTEXT"
  dybatpho::info "Set LOG_FORMAT=json to emit machine-readable events enriched"
  dybatpho::info "with request_id, hostname, pid, and duration_ms:"
  (
    export LOG_FORMAT=json
    dybatpho::info "first structured event"
    dybatpho::warn "second structured event, same request_id"
  )
  dybatpho::info "Set LOG_REQUEST_ID to correlate logs across multiple processes,"
  dybatpho::info "for example a CI/CD pipeline propagating one ID per run:"
  (
    export LOG_FORMAT=json LOG_REQUEST_ID="ci-pipeline-42"
    dybatpho::info "event tagged with a caller-supplied request_id"
  )
}

# @description Run the `FILE LOGGING WITH ROTATION` section of this example.
# @noargs
function _demo_file_logging {
  dybatpho::header "FILE LOGGING WITH ROTATION"
  local demo_dir
  dybatpho::create_temp demo_dir "/"
  local log_file="${demo_dir}/app.log"

  dybatpho::info "Writing JSON events to ${log_file} independent of LOG_FORMAT..."
  (
    export LOG_FILE="${log_file}"
    # Keep the file more verbose than stdout: capture debug events on disk
    # while stdout (LOG_LEVEL=info by default) stays concise.
    export LOG_FILE_LEVEL=debug
    dybatpho::debug "captured on disk only"
    dybatpho::info "captured on disk and stdout"
    dybatpho::warn "captured on disk and stdout"
  )
  dybatpho::info "Log file content:"
  local cat
  cat=$(cat "${log_file}")
  dybatpho::print "${cat}"

  dybatpho::info "Simulating rotation with a tiny LOG_FILE_MAX_BYTES..."
  (
    export LOG_FILE="${log_file}" LOG_FILE_MAX_BYTES=200 LOG_FILE_MAX_BACKUPS=2
    for ((event = 1; event <= 5; event++)); do
      dybatpho::info "padding event number ${event} to exceed the rotation threshold"
    done
  )
  dybatpho::info "Files present after rotation:"
  local file
  for file in "${demo_dir}"/*; do
    [[ -e "${file}" ]] || continue
    dybatpho::print "${file##*/}"
  done
}

# @description Run the `CONFIGURING THE FILE SINK IN ONE CALL` section of this example.
# @noargs
function _demo_log_to_file {
  dybatpho::header "CONFIGURING THE FILE SINK IN ONE CALL"
  local demo_dir
  dybatpho::create_temp demo_dir "/"
  local log_file="${demo_dir}/configured.log"

  (
    # The same sink as above, named once instead of through four variables,
    # with the rotation threshold written the way an operator would say it.
    dybatpho::log_to_file "${log_file}" rotate:10M keep:3 level:debug
    dybatpho::info "Sink configured: ${LOG_FILE} (rotate at ${LOG_FILE_MAX_BYTES} bytes)"
    dybatpho::debug "this debug event reaches the file only"
    dybatpho::log_to_file off
    dybatpho::info "file logging is off again, so this event stays on stderr"
  )
  dybatpho::info "Log file content:"
  local cat
  cat=$(cat "${log_file}")
  dybatpho::print "${cat}"
}

# @description Run the `CONTEXT FIELDS` section of this example.
# @noargs
function _demo_log_context {
  dybatpho::header "CONTEXT FIELDS"
  dybatpho::info "Fields registered once ride along with every later event:"
  (
    export LOG_FORMAT=json
    dybatpho::log_context add run_id=demo-42 stage=build
    dybatpho::info "compiling"
    dybatpho::log_context add stage=test
    dybatpho::warn "a test was skipped"
    dybatpho::log_context remove stage
    dybatpho::info "stage is gone, run_id stays"
    dybatpho::log_context clear
  )
}

# @description Run the `TIMERS` section of this example.
# @noargs
function _demo_timers {
  dybatpho::header "TIMERS"
  dybatpho::timer_start demo_step
  sleep 0.2
  dybatpho::timer_end demo_step
  # shellcheck disable=SC2154 # set by the option spec of this script
  dybatpho::info "The duration is also readable as ${DYBATPHO_TIMER_LAST_MS}ms"
}

# @description Run the `SPINNER` section of this example.
# @noargs
function _demo_spinner {
  dybatpho::header "SPINNER"
  dybatpho::info "On a terminal the message spins; elsewhere it is logged once."
  dybatpho::spinner "Pretending to download something" -- sleep 1
  local status=0
  dybatpho::spinner "Running a command that fails" -- false || status=$?
  dybatpho::info "The spinner passed the command's exit code back: ${status}"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_log_levels
  _demo_print
  _demo_progress
  _demo_progress_bar
  _demo_debug_command
  _demo_trace
  _demo_json_context
  _demo_file_logging
  _demo_log_to_file
  _demo_log_context
  _demo_timers
  _demo_spinner
  dybatpho::success "Logging demo complete"
}

_main "$@"
