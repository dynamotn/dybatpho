#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file parallel_ops.sh
# @brief Example showing bounded concurrency with ordered output
# @description Demonstrates dybatpho::parallel_map, parallel_run,
#   parallel_status, parallel_count, parallel_failed, fail-fast (the variable
#   and `--fail-fast`), per-job time limits with `--timeout`, `--progress`,
#   and DRY_RUN
# shellcheck disable=SC2034 # DYBATPHO_PARALLEL_FAILFAST is read by the parallel module
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
. "${SCRIPTDIR}/../init.sh" --modules parallel date

dybatpho::register_common_handlers

HOSTS=(web-01 web-02 db-01 cache-01 worker-01 worker-02)

# @description Pretend to check one host, slowly enough that the jobs really overlap.
# @arg $1 string Host to check
function _check_host {
  local host="$1"
  # Pretend work, long enough that the jobs really do overlap.
  sleep "0.$((RANDOM % 3 + 1))"
  dybatpho::print "  ${host}: reachable"
  # One host is deliberately unhealthy, to show per-job exit codes.
  [[ "${host}" == "db-01" ]] && return 1
  return 0
}

# @description Run the `ONE COMMAND OVER A LIST` section of this example.
# @noargs
function _demo_map {
  dybatpho::header "ONE COMMAND OVER A LIST"
  dybatpho::info "Checking ${#HOSTS[@]} hosts, 3 at a time"

  # Called directly rather than through a substitution: the per-job exit codes
  # are kept in this shell, and a subshell would take them with it.
  dybatpho::parallel_map 3 _check_host "${HOSTS[@]}" || true

  local parallel_failed
  parallel_failed=$(dybatpho::parallel_failed)
  local parallel_count
  parallel_count=$(dybatpho::parallel_count)
  dybatpho::info "Jobs: ${parallel_count}, failed: ${parallel_failed}"
  local index
  for ((index = 0; index < $(dybatpho::parallel_count); index++)); do
    local parallel_status
    parallel_status=$(dybatpho::parallel_status "${index}")
    dybatpho::print "  $(printf '%-10s' "${HOSTS[index]}") exit ${parallel_status}"
  done
}

# @description Run the `OUTPUT STAYS READABLE` section of this example.
# @noargs
function _demo_ordering {
  dybatpho::header "OUTPUT STAYS READABLE"
  dybatpho::info "Jobs overlap, but each one's lines are replayed together"

  # @description A job that writes while it runs, to show how output is kept apart.
  # @arg $1 string Name of the job
  function _noisy {
    printf '  [%s] starting\n' "$1"
    sleep "0.$((RANDOM % 3))"
    printf '  [%s] finished\n' "$1"
  }
  dybatpho::parallel_map 4 _noisy alpha bravo charlie delta
}

# @description Run the `DIFFERENT COMMANDS AT ONCE` section of this example.
# @noargs
function _demo_run {
  dybatpho::header "DIFFERENT COMMANDS AT ONCE"
  # `parallel_run` suits jobs that are not the same command over a list.
  dybatpho::parallel_run 3 \
    "printf '  linting...\n'; sleep 0.1; printf '  lint done\n'" \
    "printf '  testing...\n'; sleep 0.2; printf '  tests done\n'" \
    "printf '  building...\n'; sleep 0.1; printf '  build done\n'"
}

# @description Run the `FAIL FAST` section of this example.
# @noargs
function _demo_failfast {
  dybatpho::header "FAIL FAST"
  dybatpho::info "With fail-fast on, the jobs after a failure are never started"

  # @description One step of the pipeline; `step-2` fails, to show what a failure does.
  # @arg $1 string Name of the step
  function _step {
    dybatpho::print "  running $1"
    [[ "$1" == "step-2" ]] && return 1
    return 0
  }
  DYBATPHO_PARALLEL_FAILFAST=true
  dybatpho::parallel_map 1 _step step-1 step-2 step-3 step-4 || true
  DYBATPHO_PARALLEL_FAILFAST=false

  local index parallel_count parallel_status
  parallel_count=$(dybatpho::parallel_count)
  for ((index = 0; index < parallel_count; index++)); do
    parallel_status=$(dybatpho::parallel_status "${index}")
    dybatpho::print "  job ${index} -> ${parallel_status}"
  done
  dybatpho::info "A skipped job never ran, so it counts as neither pass nor fail"

  dybatpho::info "--fail-fast also ends a job that is still running when another fails"
  # @description A long build beside a short one that fails.
  # @arg $1 string Name of the job
  function _build {
    if [[ "$1" == "slow" ]]; then
      sleep 10
      return 0
    fi
    sleep 0.2
    return 2
  }
  dybatpho::parallel_map --fail-fast 2 _build slow broken || true
  local slow broken
  slow=$(dybatpho::parallel_status 0)
  broken=$(dybatpho::parallel_status 1)
  dybatpho::print "  slow -> ${slow}"
  dybatpho::print "  broken -> ${broken}"
}

# @description Run the `TIME LIMITS` section of this example.
# @noargs
function _demo_timeout {
  dybatpho::header "TIME LIMITS"
  dybatpho::info "--timeout ends a job that runs too long and records exit 124"

  # @description Probe a host; `db-01` hangs, to show what a timeout does.
  # @arg $1 string Host to probe
  function _probe {
    [[ "$1" == "db-01" ]] && sleep 30
    dybatpho::print "  $1: answered"
  }
  dybatpho::parallel_map --timeout 1s 3 _probe web-01 db-01 cache-01 || true
  local index parallel_status
  for index in 0 1 2; do
    parallel_status=$(dybatpho::parallel_status "${index}")
    dybatpho::print "  job ${index} -> ${parallel_status}"
  done
}

# @description Run the `PROGRESS` section of this example.
# @noargs
function _demo_progress {
  dybatpho::header "PROGRESS"
  dybatpho::info "--progress reports finished jobs on standard error; the output stays clean"

  # @description Pretend to convert one file.
  # @arg $1 string File to convert
  function _convert {
    sleep 0.1
    printf '  converted %s\n' "$1"
  }
  dybatpho::parallel_map --progress 2 _convert a.png b.png c.png d.png
}

# @description Run the `DRY RUN` section of this example.
# @noargs
function _demo_dry_run {
  dybatpho::header "DRY RUN"
  DRY_RUN=true dybatpho::parallel_map 2 _check_host web-01 db-01
  dybatpho::info "Nothing was contacted"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_map
  _demo_ordering
  _demo_run
  _demo_failfast
  _demo_timeout
  _demo_progress
  _demo_dry_run
  dybatpho::success "Parallel demo complete"
}

_main "$@"
