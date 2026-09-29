#!/usr/bin/env bash
# This file keeps its declarations with the functions they describe.
# dyshellint disable=BSG033
# @file doctor_ops.sh
# @brief Example showing the environment report a script can run before it works
# @description Demonstrates dybatpho::version, dybatpho::doctor with a module
#   scope, --json and --quiet, dybatpho::doctor_requirements, and
#   dybatpho::doctor_bash_supported
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules doctor json archive git

dybatpho::register_common_handlers

# @description Run the `WHICH LIBRARY AM I RUNNING?` section of this example.
# @noargs
function _demo_version {
  dybatpho::header "WHICH LIBRARY AM I RUNNING?"
  # Available from `init.sh` alone, so a script can report it before deciding
  # whether it has the functions it needs.
  local version
  version=$(dybatpho::version)
  dybatpho::info "dybatpho ${version}"
}

# @description Run the `WHAT THIS SHELL LOADED, AND WHAT IT NEEDS` section of this example.
# @noargs
function _demo_report {
  dybatpho::header "WHAT THIS SHELL LOADED, AND WHAT IT NEEDS"
  # No argument means the modules this script asked `init.sh` for. The report
  # returns non-zero when a required dependency is missing, and this example
  # keeps going either way so the rest of it still runs on a bare machine.
  dybatpho::doctor || dybatpho::warn "Something required is missing, see the report above"
}

# @description Run the `CHECKING A MODULE A SCRIPT HAS NOT LOADED YET` section of this example.
# @noargs
function _demo_scope {
  dybatpho::header "CHECKING A MODULE A SCRIPT HAS NOT LOADED YET"
  # Useful before `dybatpho::load`: ask whether the environment can support a
  # module before the script commits to it.
  dybatpho::doctor --modules "archive,git" || true
}

# @description Run the `WHAT ONE MODULE CALLS` section of this example.
# @noargs
function _demo_requirements {
  dybatpho::header "WHAT ONE MODULE CALLS"
  local kind spec
  for kind in required optional; do
    dybatpho::info "${kind} for archive:"
    local doctor_requirements_output
    doctor_requirements_output=$(dybatpho::doctor_requirements archive "${kind}")
    while read -r spec || [[ -n "${spec}" ]]; do
      dybatpho::print "  ${spec}"
    done < <(printf '%s' "${doctor_requirements_output}")
  done
}

# @description Run the `A GATE FOR CI` section of this example.
# @noargs
function _demo_quiet {
  dybatpho::header "A GATE FOR CI"
  # `--quiet` prints nothing and answers through the exit code, which is what a
  # pipeline step wants.
  if dybatpho::doctor --modules json --quiet; then
    dybatpho::success "The json module can run here"
  else
    dybatpho::warn "The json module is missing a required dependency"
  fi
}

# @description Run the `MACHINE-READABLE REPORT` section of this example.
# @noargs
function _demo_json {
  dybatpho::header "MACHINE-READABLE REPORT"
  local report
  # The report is built without `jq`, on purpose: a diagnostic that needs a tool
  # the user may be missing is of no use.
  report="$(dybatpho::doctor --modules "json,archive" --json || true)"
  if dybatpho::is command jq; then
    dybatpho::print "Missing dependencies, as jq sees them:"
    printf '%s' "${report}" \
      | jq -r '.dependencies[] | select(.status == "missing") | "  \(.module): \(.dependency) (\(.kind))"'
    local printf
    printf=$(printf '%s' "${report}" | jq -r '.ok')
    dybatpho::print "Everything required is present: ${printf}"
  else
    dybatpho::print "${report:0:120}..."
  fi
}

# @description Run the `IS THIS SHELL NEW ENOUGH?` section of this example.
# @noargs
function _demo_bash {
  dybatpho::header "IS THIS SHELL NEW ENOUGH?"
  if dybatpho::doctor_bash_supported; then
    # shellcheck disable=SC2154 # set by the option spec of this script
    dybatpho::success "Bash ${BASH_VERSION} is at least ${DYBATPHO_BASH_MINIMUM}"
  else
    dybatpho::error "Bash ${BASH_VERSION} is older than ${DYBATPHO_BASH_MINIMUM}"
  fi
}

# @description Show what a dependency that names a version looks like in the
#   report. `json` needs the Go `yq` from v4 on, so being installed is not the
#   whole question.
# @noargs
function _demo_versioned_dependency {
  dybatpho::header "A DEPENDENCY THAT NAMES A VERSION"
  local doctor_requirements
  doctor_requirements=$(dybatpho::doctor_requirements json required)
  dybatpho::print "json requires: ${doctor_requirements}"
  # `ok` means installed and new enough, `outdated` means installed and not,
  # and `unknown` means the version could not be read, which is reported but
  # never treated as a failure.
  dybatpho::doctor --modules json || true
}

_demo_version
_demo_report
_demo_scope
_demo_requirements
_demo_versioned_dependency
_demo_quiet
_demo_json
_demo_bash

dybatpho::success "Doctor example finished"
