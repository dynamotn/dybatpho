#!/usr/bin/env bash
# @file profile_ops.sh
# @brief Example showing how to find where a script spends its time
# @description
#   Times nested blocks by hand, then, on Bash 5, every function of a small
#   pipeline, and prints both reports.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules profile

dybatpho::register_common_handlers

# @description A step that takes a little time.
# @noargs
function _fetch {
  sleep 0.05
}

# @description A step that takes more, and calls another.
# @noargs
function _transform {
  sleep 0.1
  _fetch
}

# --- marked blocks -------------------------------------------------------------

# @description Run the `MARKED BLOCKS` section of this example.
# @noargs
function _demo_marked {
  dybatpho::header "MARKED BLOCKS"
  dybatpho::profile_begin "whole run"
  dybatpho::profile_run "fetch" -- sleep 0.05
  dybatpho::profile_begin "transform"
  sleep 0.1
  dybatpho::profile_end "transform"
  dybatpho::profile_end "whole run"
  dybatpho::profile_report
  dybatpho::profile_reset
}

# --- every function --------------------------------------------------------------

# @description Run the `EVERY FUNCTION` section of this example, where Bash has
#   `EPOCHREALTIME`.
# @noargs
function _demo_every_function {
  dybatpho::header "EVERY FUNCTION"
  if [[ -z "${EPOCHREALTIME:-}" ]]; then
    dybatpho::warn "Per-function timing needs Bash 5; skipping"
    return 0
  fi
  # The switch a user would set for one run: DYBATPHO_PROFILE=true ./script.sh
  DYBATPHO_PROFILE=true dybatpho::profile_start
  _transform
  _fetch
  dybatpho::profile_stop
  dybatpho::profile_report
}

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_marked
  _demo_every_function
  dybatpho::success "Profiling demo complete"
}

_main "$@"
