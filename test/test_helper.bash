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
eval "${__dybatpho_helper_saved_trap}"
unset -v __dybatpho_helper_saved_trap

bats_require_minimum_version 1.5.0

# Like `run`, but the command executes in the current shell instead of a
# capturing subshell, so coverage instrumentation (which traces through stderr)
# still sees the executed lines. Only stdout is captured; use `run` for commands
# that must fail or whose stderr is asserted.
run_traced() {
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
