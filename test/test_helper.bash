# This file is the vocabulary the `.bats` files call, so its functions carry
# the flat names a test reads — `run_traced`, `assert_process_dead` — beside
# the `assert_*` of bats-assert, rather than a namespace of their own; and
# `run_traced` sets `status`, `output` and `lines` for the test that called it,
# which is the contract `run` already has and what `local` would break.
#
# BSG050 asks for `dybatpho::expect_args`, which these two cannot use: they take
# the argument list of the command under test, behind the same optional flags
# `run` accepts, so there is no fixed set of names to declare. `scripts/lint.sh`
# is excused the same rule for the same reason.
# dyshellint disable=BSG004,BSG011,BSG050
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

# Colour is decided from the environment, and a developer's shell commonly
# exports `FORCE_COLOR` -- Node tooling sets it, and this machine had
# `FORCE_COLOR=3`. Inherited, it makes the suite answer differently here and in
# CI, and a test asserting on colour would pass or fail by accident. A test
# that cares about the decision sets the variables for the call it makes.
unset FORCE_COLOR

# A git hook runs with the repository it fires in exported as `GIT_DIR`,
# `GIT_INDEX_FILE` and friends, and the pre-commit hook runs this suite. Left in
# place, every `git init`, `config`, `commit` and `tag` a test aims at its own
# temporary repository lands in the real one instead: run from a worktree's
# commit, the suite once set `core.bare`, rewrote `origin`, and created tags in
# the repository being committed to. These are the names
# `git rev-parse --local-env-vars` lists, so a test only ever reaches the
# repository its working directory is in.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS \
  GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE \
  GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS \
  GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR

bats_require_minimum_version 1.5.0

# @description Like `run`, but the command executes in the current shell instead
#   of a capturing subshell, so coverage instrumentation still sees the executed
#   lines.
#
#   `run` is unusable for anything the coverage report has to account for. kcov
#   instruments Bash through a DEBUG trap, and `run` clears that trap — it does
#   `trap - ERR DEBUG` before invoking the command — so every line a `run`
#   executes is recorded as never having run. That is not a small effect: the
#   suite reaches for `run` exactly where a command has to fail, so whole error
#   paths were reported as untested while being tested all along.
#
#   The flags mirror `run` so a call site converts by changing the word: `!`
#   requires a nonzero status and `-N` requires exactly N. `--separate-stderr`
#   captures standard error into `stderr` and `stderr_lines`; without it
#   standard error is left alone rather than folded into `output`, because the
#   library logs there and the call sites that already use this helper assert
#   `output` against stdout only.
#
#   The one thing this cannot do is host a command that ends the shell:
#   `dybatpho::die` calls `exit`, and with no subshell to absorb it that ends the
#   test. Those call sites keep using `run`, and the line they exercise carries a
#   `# kcov(skip)` naming this limitation.
# @arg $1 string Optionally `!`, `-N`, `--separate-stderr`, or `--`
# @arg $@ string The command to run, and its arguments
# @set status number Exit status of the command
# @set output string What the command wrote to stdout, and to stderr unless it
#   was asked to keep them apart
# @set lines array The output, one element per line
# @set stderr string What the command wrote to stderr, with `--separate-stderr`
# @set stderr_lines array The standard error, one element per line
# @exitcode 0 The command ran and any expected status held
# @exitcode 1 The status was not the one the flags asked for
# shellcheck disable=SC2034 # status, output and lines are read by the caller
function run_traced {
  local expected_rc="" separate=""
  while (($#)) && [[ "$1" == -* || "$1" == '!' ]]; do
    case "$1" in
      '!') expected_rc="-1" ;;
      -[0-9]*) expected_rc="${1#-}" ;;
      --separate-stderr) separate="1" ;;
      --)
        shift
        break
        ;;
      *)
        printf "Usage error: run_traced: unknown flag '%s'\n" "$1" >&2
        return 1
        ;;
    esac
    shift
  done

  local dir="${BATS_TEST_TMPDIR:-${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR}}}"
  local output_file="${dir}/run_traced.out" stderr_file="${dir}/run_traced.err"
  status=0
  if [[ -n "${separate}" ]]; then
    "$@" > "${output_file}" 2> "${stderr_file}" || status=$?
  else
    "$@" > "${output_file}" || status=$?
  fi
  output="$(< "${output_file}")"
  if [[ -n "${output}" ]]; then
    mapfile -t lines <<< "${output}"
  else
    lines=()
  fi
  if [[ -n "${separate}" ]]; then
    stderr="$(< "${stderr_file}")"
    if [[ -n "${stderr}" ]]; then
      mapfile -t stderr_lines <<< "${stderr}"
    else
      stderr_lines=()
    fi
  else
    unset -v stderr stderr_lines
  fi

  if [[ -z "${expected_rc}" ]]; then
    return 0
  fi
  if [[ "${expected_rc}" == "-1" ]]; then
    if ((status == 0)); then
      printf 'run_traced: expected nonzero exit code, got 0\n%s\n' "${output}" >&2
      return 1
    fi
  elif ((status != expected_rc)); then
    printf 'run_traced: expected exit code %s, got %s\n%s\n' \
      "${expected_rc}" "${status}" "${output}" >&2
    return 1
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

# @description Print a `PATH` on which one command cannot be found.
#
#   Dropping every directory that holds the command takes the rest of that
#   directory with it: `jq` lives in `/usr/bin` on a CI runner, so the stripped
#   path loses `date` too and the library dies on its own log line instead of
#   on the missing backend. This mirrors each such directory into a sandbox of
#   symlinks with that one name left out, so only the named command goes
#   missing. `command -v` is what the library asks, so the name has to be
#   absent rather than shadowed.
# @arg $1 string Name of the command to hide
# @stdout A `PATH` whose entries hold everything but that command
function path_without {
  local tool="$1" bin="${BATS_TEST_TMPDIR}/path-without-$1"
  local kept="" entry name target
  local -a entries=()
  mkdir -p "${bin}"
  IFS=':' read -r -a entries <<< "${PATH}"
  for entry in "${entries[@]}"; do
    [[ -n "${entry}" ]] || continue
    if [[ ! -x "${entry}/${tool}" ]]; then
      kept+="${entry}:"
      continue
    fi
    for target in "${entry}"/*; do
      [[ -e "${target}" || -L "${target}" ]] || continue
      name="${target##*/}"
      [[ "${name}" != "${tool}" ]] || continue
      [[ -e "${bin}/${name}" ]] || ln -s "${target}" "${bin}/${name}" 2> /dev/null
    done
  done
  printf '%s\n' "${bin}:${kept%:}"
}

# @description Rewrite a file through a `sed` script.
#
#   `sed -i` takes its backup suffix as an optional attached argument on GNU and
#   a mandatory separate one on BSD, so no single spelling works on both: BSD
#   reads a bare `-i` script as the suffix and the file name as the script. The
#   rewrite goes through a staging file instead.
# @arg $1 string `sed` script
# @arg $2 string File to rewrite
function sed_in_place {
  local script="$1" file="$2"
  sed -e "${script}" "${file}" > "${file}.sed" && mv -f -- "${file}.sed" "${file}"
}
