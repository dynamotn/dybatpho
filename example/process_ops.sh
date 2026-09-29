#!/usr/bin/env bash
# This file shares some variables with the caller or across calls on purpose,
# which is what `local` would break.
# dyshellint disable=BSG011
# @file process_ops.sh
# @brief Example showing process control utilities
# @description Demonstrates dybatpho::retry, retry_until, dry_run, breakpoint,
#              expect_args, expect_envs, require, command_exists_all, is,
#              coalesce, coalesce_cmd, default_env, require_envs_any, assert,
#              run_with_timeout, background_run, wait_all, kill_children,
#              pid_file_write, pid_file_is_running, pid_file_remove,
#              and error/signal handlers
# shellcheck disable=SC2154 # `dybatpho::expect_args` assigns these names through a nameref
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# --- retry ----------------------------------------------------------------

_ATTEMPT_COUNT=0

# @description A command that fails twice and succeeds on the third attempt.
# @noargs
function _flaky_command {
  # Succeeds on the 3rd attempt
  _ATTEMPT_COUNT=$((_ATTEMPT_COUNT + 1))
  if [[ "${_ATTEMPT_COUNT}" -lt 3 ]]; then
    dybatpho::warn "Attempt ${_ATTEMPT_COUNT}: command failed (simulated)"
    return 1
  fi
  dybatpho::info "Attempt ${_ATTEMPT_COUNT}: command succeeded"
}

# @description Run the `RETRY WITH BACKOFF` section of this example.
# @noargs
function _demo_retry {
  dybatpho::header "RETRY WITH BACKOFF"
  dybatpho::retry 5 _flaky_command
  dybatpho::success "Flaky command eventually succeeded"
}

# --- dry_run --------------------------------------------------------------

# @description A pretend deploy, so `dry_run` has something to report.
# @arg $1 string target
function _deploy {
  dybatpho::expect_args _target -- "$@"
  dybatpho::dry_run "rsync -avz ./dist/ ${_target}:/var/www/app/"
  dybatpho::dry_run "ssh ${_target} 'systemctl restart app'"
}

# @description Run the `DRY RUN` section of this example.
# @noargs
function _demo_dry_run {
  dybatpho::header "DRY RUN"
  dybatpho::info "With DRY_RUN=true, commands are printed but NOT executed"
  DRY_RUN=true _deploy "my-server.example.com"
  dybatpho::info "With DRY_RUN unset, commands execute normally"
  # shellcheck disable=SC1007 # clearing DRY_RUN for one command, not assigning a value
  # shellcheck disable=SC2310 # the demo keeps going so the next section can run
  DRY_RUN= _deploy "my-server.example.com" || true
}

# --- expect_args ----------------------------------------------------------

# @description A two-argument command, used to show how arguments are named.
# @arg $1 string name
# @arg $2 string greeting
function _greet {
  dybatpho::expect_args _name _greeting -- "$@"
  dybatpho::info "${_greeting}, ${_name}!"
}

# @description Run the `EXPECT ARGS` section of this example.
# @noargs
function _demo_expect_args {
  dybatpho::header "EXPECT ARGS"
  _greet "Alice" "Hello"
  _greet "Bob" "Good morning"
}

# --- expect_envs ----------------------------------------------------------

# @description Run the `EXPECT ENVS` section of this example.
# @noargs
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

# @description Run the `REQUIRE COMMAND` section of this example.
# @noargs
function _demo_require {
  dybatpho::header "REQUIRE COMMAND"
  dybatpho::require "bash"
  dybatpho::require "cat"
  dybatpho::success "bash and cat are available"
  dybatpho::info "(Requiring a missing command would call dybatpho::die)"
}

# @description Run the `COMMAND CHECKS` section of this example.
# @noargs
function _demo_command_checks {
  dybatpho::header "COMMAND CHECKS"
  local command_exists_all
  command_exists_all=$(dybatpho::command_exists_all bash cat && echo yes || echo no)
  dybatpho::info "bash + cat available? ${command_exists_all}"
  local coalesce_cmd
  coalesce_cmd=$(dybatpho::coalesce_cmd jq python3 bash)
  dybatpho::info "Preferred JSON tool  : ${coalesce_cmd}"
}

# --- is -------------------------------------------------------------------

# @description Run the `IS — CONDITION TESTING` section of this example.
# @noargs
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

# @description Run the `COALESCE` section of this example.
# @noargs
function _demo_coalesce {
  dybatpho::header "COALESCE"
  local primary_host=""
  local fallback_host="https://backup.example.com"
  local coalesce
  coalesce=$(dybatpho::coalesce "${primary_host}" "${fallback_host}" "http://localhost:8080")
  dybatpho::info "Selected host: ${coalesce}"
}

# @description Run the `DEFAULT ENV / REQUIRE ANY ENV` section of this example.
# @noargs
function _demo_env_defaults {
  dybatpho::header "DEFAULT ENV / REQUIRE ANY ENV"
  unset APP_ENDPOINT
  local default_env
  default_env=$(dybatpho::default_env APP_ENDPOINT "http://localhost:8080")
  dybatpho::info "Defaulted endpoint: ${default_env}"
  export APP_BACKUP_TOKEN="configured"
  dybatpho::require_envs_any APP_TOKEN APP_BACKUP_TOKEN
  dybatpho::success "At least one application token is configured"
}

# @description Run the `ASSERT` section of this example.
# @noargs
function _demo_assert {
  dybatpho::header "ASSERT"
  dybatpho::assert '[[ 2 -gt 1 ]]' "math should still work"
  dybatpho::success "Assertion passed"
}

# @description Run the `RETRY UNTIL` section of this example.
# @noargs
function _demo_retry_until {
  dybatpho::header "RETRY UNTIL"
  local fixed_attempts=0
  # @description A command that fails once, to show a retry with a fixed delay.
  # @noargs
  function _fixed_delay_flaky {
    fixed_attempts=$((fixed_attempts + 1))
    [[ "${fixed_attempts}" -ge 2 ]]
  }
  dybatpho::retry_until 2 1 _fixed_delay_flaky fixed-delay-demo
  dybatpho::success "Fixed-delay retry succeeded"
}

# --- run_with_timeout -----------------------------------------------------

# @description Run the `RUN WITH TIMEOUT` section of this example.
# @noargs
function _demo_run_with_timeout {
  dybatpho::header "RUN WITH TIMEOUT"

  dybatpho::run_with_timeout 5 echo "Finished well inside the limit"

  local status=0
  dybatpho::run_with_timeout 1 sleep 30 || status=$?
  if ((status == 124)); then
    dybatpho::success "A command that overran was ended, reported as 124"
  else
    dybatpho::warn "Expected 124 for a timeout, got ${status}"
  fi

  # Unlike the `timeout` binary, this works on a shell function too.
  # @description A shell function that never finishes in time, for the timeout demo.
  # @noargs
  function _slow_function { sleep 30; }
  status=0
  dybatpho::run_with_timeout 1 _slow_function || status=$?
  dybatpho::info "A shell function also times out, reported as ${status}"
}

# --- background jobs ------------------------------------------------------

# @description Run the `BACKGROUND JOBS` section of this example.
# @noargs
function _demo_background_jobs {
  dybatpho::header "BACKGROUND JOBS"

  # @description A job that finishes, for the demo that waits on several at once.
  # @noargs
  function _quick_job { sleep 1; }
  # @description A job that exits non-zero, so the wait has a failure to report.
  # @noargs
  function _failing_job {
    sleep 1
    return 4
  }

  dybatpho::background_run fetch _quick_job
  dybatpho::background_run build _failing_job
  background_pid=$(dybatpho::background_pid fetch)
  dybatpho::info "fetch is running as pid ${background_pid}"

  local status=0
  dybatpho::wait_all || status=$?
  background_status_2=$(dybatpho::background_status fetch)
  dybatpho::info "fetch exited ${background_status_2}"
  background_status=$(dybatpho::background_status build)
  dybatpho::info "build exited ${background_status}"
  if ((status != 0)); then
    dybatpho::warn "At least one background job failed, as expected here"
  fi
}

# @description Run the `KILL CHILDREN` section of this example.
# @noargs
function _demo_kill_children {
  dybatpho::header "KILL CHILDREN"

  dybatpho::background_run watcher sleep 300
  local pid
  pid="$(dybatpho::background_pid watcher)"
  dybatpho::info "Started a long-running job as pid ${pid}"

  # In a real script this belongs on a trap, so an interrupt leaves nothing
  # behind: dybatpho::trap dybatpho::kill_children EXIT INT TERM
  dybatpho::kill_children
  if kill -0 "${pid}" 2> /dev/null; then
    dybatpho::warn "Job ${pid} is somehow still running"
  else
    dybatpho::success "Job ${pid} and its children are gone"
  fi
}

# --- PID files ------------------------------------------------------------

# @description Run the `PID FILE` section of this example.
# @noargs
function _demo_pid_file {
  dybatpho::header "PID FILE"

  local run_dir pid_file
  dybatpho::create_temp run_dir "/" "pid-demo"
  pid_file="${run_dir}/app.pid"

  dybatpho::pid_file_write "${pid_file}"
  local cat
  cat=$(cat "${pid_file}")
  dybatpho::info "Recorded pid ${cat} in ${pid_file}"

  if dybatpho::pid_file_is_running "${pid_file}"; then
    dybatpho::success "The recorded process is alive"
  fi

  # A PID file left behind by a process that has since exited reads as "nothing
  # is running", which is what a supervisor acts on.
  printf '%s\n' "99999999" > "${pid_file}"
  if dybatpho::pid_file_is_running "${pid_file}"; then
    dybatpho::warn "A stale PID file should not read as running"
  else
    dybatpho::success "A stale PID file reads as not running"
  fi

  # The removal only happens when the file still records this process, so an
  # exiting script cannot delete the PID file its replacement just wrote.
  dybatpho::pid_file_remove "${pid_file}" \
    || dybatpho::info "Left ${pid_file} alone: it records another process"
  dybatpho::pid_file_write "${pid_file}"
  dybatpho::pid_file_remove "${pid_file}"
  dybatpho::success "PID file removed on the way out"
}

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
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
  _demo_run_with_timeout
  _demo_background_jobs
  _demo_kill_children
  _demo_pid_file
  dybatpho::success "Process operations demo complete"
}

_main "$@"
