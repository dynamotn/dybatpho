#!/usr/bin/env bash
# @file process_ops.sh
# @brief Example showing process control utilities
# @description Demonstrates dybatpho::retry, dry_run, breakpoint, expect_args,
#              expect_envs, require, is, and error/signal handlers
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# --- retry ----------------------------------------------------------------

_ATTEMPT_COUNT=0

function _flaky_command {
  # Succeeds on the 3rd attempt
  _ATTEMPT_COUNT=$((_ATTEMPT_COUNT + 1))
  if [[ "${_ATTEMPT_COUNT}" -lt 3 ]]; then
    dybatpho::warn "Attempt ${_ATTEMPT_COUNT}: command failed (simulated)"
    return 1
  fi
  dybatpho::info "Attempt ${_ATTEMPT_COUNT}: command succeeded"
}

function _demo_retry {
  dybatpho::header "RETRY WITH BACKOFF"
  dybatpho::retry 5 _flaky_command
  dybatpho::success "Flaky command eventually succeeded"
}

# --- dry_run --------------------------------------------------------------

function _deploy {
  dybatpho::expect_args _target -- "$@"
  dybatpho::dry_run "rsync -avz ./dist/ ${_target}:/var/www/app/"
  dybatpho::dry_run "ssh ${_target} 'systemctl restart app'"
}

function _demo_dry_run {
  dybatpho::header "DRY RUN"
  dybatpho::info "With DRY_RUN=true, commands are printed but NOT executed"
  DRY_RUN=true _deploy "my-server.example.com"
  dybatpho::info "With DRY_RUN unset, commands execute normally"
  DRY_RUN= _deploy "my-server.example.com" || true
}

# --- expect_args ----------------------------------------------------------

function _greet {
  dybatpho::expect_args _name _greeting -- "$@"
  dybatpho::info "${_greeting}, ${_name}!"
}

function _demo_expect_args {
  dybatpho::header "EXPECT ARGS"
  _greet "Alice" "Hello"
  _greet "Bob" "Good morning"
}

# --- expect_envs ----------------------------------------------------------

function _demo_expect_envs {
  dybatpho::header "EXPECT ENVS"
  dybatpho::info "Checking for required environment variables..."

  # Set and check APP_ENV
  export APP_ENV="production"
  dybatpho::expect_envs "APP_ENV"
  dybatpho::success "APP_ENV is set to: ${APP_ENV}"
  unset APP_ENV

  dybatpho::info "(Requiring a missing variable would call dybatpho::die)"
}

# --- require --------------------------------------------------------------

function _demo_require {
  dybatpho::header "REQUIRE COMMAND"
  dybatpho::require "bash"
  dybatpho::require "cat"
  dybatpho::success "bash and cat are available"
  dybatpho::info "(Requiring a missing command would call dybatpho::die)"
}

# --- is -------------------------------------------------------------------

function _demo_is {
  dybatpho::header "IS — CONDITION TESTING"

  dybatpho::is "command" "bash" && dybatpho::info "bash command exists"
  dybatpho::is "command" "definitely_not_a_command_xyz" \
    || dybatpho::warn "definitely_not_a_command_xyz not found (expected)"

  local TMPFILE_IS TMPDIR_IS
  dybatpho::create_temp TMPFILE_IS ".txt"
  dybatpho::is "file" "${TMPFILE_IS}" && dybatpho::info "Temp file exists"

  dybatpho::create_temp TMPDIR_IS "/"
  dybatpho::is "dir" "${TMPDIR_IS}" && dybatpho::info "Temp dir exists"

  dybatpho::is "int" "42" && dybatpho::info "42 is an integer"
  dybatpho::is "int" "abc" || dybatpho::warn "'abc' is not an integer (expected)"
}

# --- main -----------------------------------------------------------------

function _main {
  _demo_retry
  _demo_dry_run
  _demo_expect_args
  _demo_expect_envs
  _demo_require
  _demo_is
  dybatpho::success "Process operations demo complete"
}

_main "$@"
