#!/usr/bin/env bash
# @file process_ops.sh
# @brief Example showing process control utilities
# @description Demonstrates dybatpho::retry, retry_until, dry_run, breakpoint,
#              expect_args, expect_envs, require, command_exists_all, is,
#              coalesce, coalesce_cmd, default_env, require_envs_any, assert,
#              and error/signal handlers
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

function _demo_command_checks {
  dybatpho::header "COMMAND CHECKS"
  dybatpho::info "bash + cat available? $(dybatpho::command_exists_all bash cat && echo yes || echo no)"
  dybatpho::info "Preferred JSON tool  : $(dybatpho::coalesce_cmd jq python3 bash)"
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

# --- coalesce -------------------------------------------------------------

function _demo_coalesce {
  dybatpho::header "COALESCE"
  local primary_host=""
  local fallback_host="https://backup.example.com"
  dybatpho::info "Selected host: $(dybatpho::coalesce "${primary_host}" "${fallback_host}" "http://localhost:8080")"
}

function _demo_env_defaults {
  dybatpho::header "DEFAULT ENV / REQUIRE ANY ENV"
  unset APP_ENDPOINT
  dybatpho::info "Defaulted endpoint: $(dybatpho::default_env APP_ENDPOINT "http://localhost:8080")"
  export APP_BACKUP_TOKEN="configured"
  dybatpho::require_envs_any APP_TOKEN APP_BACKUP_TOKEN
  dybatpho::success "At least one application token is configured"
}

function _demo_assert {
  dybatpho::header "ASSERT"
  dybatpho::assert '[[ 2 -gt 1 ]]' "math should still work"
  dybatpho::success "Assertion passed"
}

function _demo_retry_until {
  dybatpho::header "RETRY UNTIL"
  local fixed_attempts=0
  _fixed_delay_flaky() {
    fixed_attempts=$((fixed_attempts + 1))
    [[ "${fixed_attempts}" -ge 2 ]]
  }
  dybatpho::retry_until 2 1 _fixed_delay_flaky fixed-delay-demo
  dybatpho::success "Fixed-delay retry succeeded"
}

# --- main -----------------------------------------------------------------

function _main {
  _demo_retry
  _demo_dry_run
  _demo_expect_args
  _demo_expect_envs
  _demo_require
  _demo_command_checks
  _demo_is
  _demo_coalesce
  _demo_env_defaults
  _demo_assert
  _demo_retry_until
  dybatpho::success "Process operations demo complete"
}

_main "$@"
