# This file is the vocabulary the `.bats` files call, so its functions carry
# the flat names a test reads — `run_traced`, `assert_process_dead` — beside
# the `assert_*` of bats-assert, rather than a namespace of their own; and
# `run_traced` sets `status`, `output` and `lines` for the test that called it,
# which is the contract `run` already has and what `local` would break.
# dyshellint disable=BSG004,BSG011
# @file test_helper.bash
# @brief What every `.bats` file in this repository loads first
# @description
#   Sources the bats libraries and the whole of dybatpho, then adds the two
#   helpers the suite needs beyond what bats-assert offers: a `run` that keeps
#   coverage instrumentation working, and an assertion about a killed process
#   that holds on a container whose PID 1 never reaps.
DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

# Bats keeps a DEBUG trap and `set -T -E` armed so it can print a stack trace for
# the failing line. That trap fires once per executed command, and sourcing the
# bats libraries plus every dybatpho module runs tens of thousands of commands —
# which costs ~800ms per test instead of ~150ms. None of that setup is code under
# test, so the trap is parked for the duration of the sourcing and restored
# afterwards; failures inside a test body still get their full trace.
__dybatpho_helper_saved_trap="$(trap -p DEBUG)"
trap - DEBUG
set +T +E

. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
# The module tests reach across the whole library, so the helper asks for every
# module. A script under test that cares about a narrower module set sources
# `init.sh` itself in a fresh shell, the way `test/init.bats` does.
. "${DYBATPHO_DIR}/init.sh" --modules all

set -T -E
# `trap -p` prints the command to restore the trap, so running it is how the
# trap comes back; there is no other form to build here.
# dyshellint disable=BSG040
eval "${__dybatpho_helper_saved_trap}"
unset -v __dybatpho_helper_saved_trap

bats_require_minimum_version 1.5.0

# @description Like `run`, but the command executes in the current shell instead
#   of a capturing subshell, so coverage instrumentation (which traces through
#   stderr) still sees the executed lines. Only stdout is captured; use `run`
#   for commands that must fail or whose stderr is asserted.
# @arg $@ string The command to run, and its arguments
# @set status number Exit status of the command
# @set output string What the command wrote to stdout
# @set lines array The output, one element per line
# @exitcode 0 Always, so a failing command does not end the test
# shellcheck disable=SC2034 # status, output and lines are read by the caller
function run_traced {
  local output_file="${BATS_TEST_TMPDIR:-${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR}}}/run_traced.out"
  status=0
  "$@" > "${output_file}" || status=$?
  output="$(< "${output_file}")"
  if [[ -n "${output}" ]]; then
    mapfile -t lines <<< "${output}"
  else
    lines=()
  fi
  return 0
}

# @description Assert that a process is no longer running.
#
#   `kill -0` alone is not enough: a process whose parent died with it is
#   reparented to PID 1, and the PID 1 of a container is usually a plain command
#   that never reaps. The killed process then lingers as a zombie, `kill -0`
#   keeps succeeding for it, and a test asserting "this got killed" fails on
#   every containerised CI job while passing on a host whose init reaps orphans.
#   A zombie has already been killed, so it counts as dead here.
# @arg $1 number Process id
# @exitcode 1 The process is still running
function assert_process_dead {
  local pid="$1" state=""
  kill -0 "${pid}" 2> /dev/null || return 0
  if [[ -r "/proc/${pid}/stat" ]]; then
    local stat
    stat="$(< "/proc/${pid}/stat")" || return 0
    # The command name is parenthesised and may itself hold spaces and
    # parentheses, so the state is the first field after the last `)`.
    stat="${stat##*) }"
    state="${stat%% *}"
  else
    state="$(ps -o state= -p "${pid}" 2> /dev/null)"
    state="${state#"${state%%[![:space:]]*}"}"
  fi
  case "${state}" in
    Z*) return 0 ;;
    *) ;;
  esac
  fail "process ${pid} is still running (state: ${state:-alive})"
}
