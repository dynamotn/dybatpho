#!/usr/bin/env bash
# @file os_ops.sh
# @brief Example showing platform and command capability detection.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh"

dybatpho::header "PLATFORM"
dybatpho::print "platform: $(dybatpho::platform)"
dybatpho::print "architecture: $(dybatpho::goarch)"

if dybatpho::is_macos; then
  dybatpho::info "Running on macOS"
elif dybatpho::is_linux; then
  dybatpho::info "Running on Linux"
fi

if tool_path="$(dybatpho::command_path git gh curl)"; then
  dybatpho::print "available tool: ${tool_path}"
else
  dybatpho::warn "None of git, gh, or curl is installed"
fi
