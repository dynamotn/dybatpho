#!/usr/bin/env bash
# @file logging_demo.sh
# @brief Example showing all logging and tracing utilities
# @description Demonstrates every logging function: debug, info, warn, error, fatal,
#              progress, progress_bar, header, success, start/end trace, structured
#              JSON output enriched with request ID/hostname/PID/duration, and
#              file logging with rotation and independent verbosity
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

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

function _demo_print {
  dybatpho::header "PRINT vs INFO"
  dybatpho::info "dybatpho::info goes to STDERR (always visible)"
  dybatpho::print "dybatpho::print goes to STDOUT (can be piped/captured)"
}

function _demo_progress {
  dybatpho::header "PROGRESS INDICATOR"
  dybatpho::progress "Doing something important..."
  sleep 0.3
  dybatpho::progress "Still working..."
  sleep 0.3
  dybatpho::success "Done!"
}

function _demo_progress_bar {
  dybatpho::header "PROGRESS BAR"
  dybatpho::info "Simulating a 10-step task..."
  local total_steps=10
  local bar_width=30
  local i percentage
  for i in $(seq 1 ${total_steps}); do
    percentage=$((i * 100 / total_steps))
    dybatpho::progress_bar "${percentage}" "${bar_width}"
    sleep 0.1
  done
  printf '\n' >&2
  dybatpho::success "Task complete!"
}

function _demo_debug_command {
  dybatpho::header "DEBUG COMMAND"
  dybatpho::info "Capturing output of 'ls example/' as debug:"
  dybatpho::debug_command \
    "Listing example directory" \
    "ls '$(dirname "${BASH_SOURCE[0]}")'"
}

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
  dybatpho::print "$(cat "${log_file}")"

  dybatpho::info "Simulating rotation with a tiny LOG_FILE_MAX_BYTES..."
  (
    export LOG_FILE="${log_file}" LOG_FILE_MAX_BYTES=200 LOG_FILE_MAX_BACKUPS=2
    for i in $(seq 1 5); do
      dybatpho::info "padding event number ${i} to exceed the rotation threshold"
    done
  )
  dybatpho::info "Files present after rotation:"
  dybatpho::print "$(ls -1 "${demo_dir}")"
}

function _main {
  _demo_log_levels
  _demo_print
  _demo_progress
  _demo_progress_bar
  _demo_debug_command
  _demo_trace
  _demo_json_context
  _demo_file_logging
  dybatpho::success "Logging demo complete"
}

_main "$@"
