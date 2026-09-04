DYBATPHO_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
. "${DYBATPHO_DIR}/test/lib/support/load.bash"
. "${DYBATPHO_DIR}/test/lib/assert/load.bash"
. "${DYBATPHO_DIR}/test/lib/file/load.bash"
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
. "${DYBATPHO_DIR}/init.sh"

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
