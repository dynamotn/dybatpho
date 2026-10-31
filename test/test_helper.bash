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
DYBATPHO_DIR="${BASH_SOURCE[0]%/*}/.."

# Bats keeps a DEBUG trap and `set -T -E` armed so it can print a stack trace for
# the failing line. That trap fires once per executed command, and sourcing the
# bats libraries plus every dybatpho module runs tens of thousands of commands —
# which costs ~800ms per test instead of ~150ms. None of that setup is code under
# test, so the trap is parked for the duration of the sourcing and restored
# afterwards; failures inside a test body still get their full trace.
__dybatpho_helper_saved_trap="$(trap -p DEBUG)"
trap - DEBUG
set +T +E

# Each bats library is sourced the way its `load.bash` would, without the
# `$(dirname ...)` that file runs once per source file: those are a fork each,
# and bats-support, bats-assert and bats-file together ran seventeen of them in
# every test, about as long as sourcing the whole of dybatpho. bats-support's
# one other statement, its `BATS_SAVED_PATH` assignment, is made here; a
# `load.bash` holding anything else is sourced as it is.
BATS_SAVED_PATH="${BATS_SAVED_PATH-${PATH}}"
__dybatpho_helper_pattern='^source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/([^"]+)"$'
for __dybatpho_helper_lib in support assert file; do
  __dybatpho_helper_lib="${DYBATPHO_DIR}/test/lib/${__dybatpho_helper_lib}"
  mapfile -t __dybatpho_helper_lines < "${__dybatpho_helper_lib}/load.bash"
  __dybatpho_helper_parts=()
  for __dybatpho_helper_line in ${__dybatpho_helper_lines[@]+"${__dybatpho_helper_lines[@]}"}; do
    if [[ "${__dybatpho_helper_line}" =~ ${__dybatpho_helper_pattern} ]]; then
      __dybatpho_helper_parts+=("${__dybatpho_helper_lib}/${BASH_REMATCH[1]}")
    elif [[ ! "${__dybatpho_helper_line}" =~ ^[[:space:]]*(#.*)?$ &&
      "${__dybatpho_helper_line}" != BATS_SAVED_PATH=* ]]; then
      __dybatpho_helper_parts=("${__dybatpho_helper_lib}/load.bash")
      break
    fi
  done
  for __dybatpho_helper_line in ${__dybatpho_helper_parts[@]+"${__dybatpho_helper_parts[@]}"}; do
    # shellcheck source=/dev/null
    . "${__dybatpho_helper_line}"
  done
done
unset -v __dybatpho_helper_pattern __dybatpho_helper_lib __dybatpho_helper_lines \
  __dybatpho_helper_parts __dybatpho_helper_line
. "${DYBATPHO_DIR}/test/lib/mock/stub.bash"
# Caches go to the test's own directory, read when `init.sh` is sourced: under
# the real home, generated completions survived from one run to the next, and
# a later run answered from them without running the code under test.
export XDG_CACHE_HOME="${BATS_TEST_TMPDIR:-${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}}}/cache"
export XDG_STATE_HOME="${XDG_CACHE_HOME%/cache}/state"
# The host's own git config reached every throwaway repository: with signing
# forced there (`tag.forcesignannotated`, a signing key the sandbox cannot
# read), each test commit and tag failed. Tests see only this identity.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${XDG_CACHE_HOME%/cache}/gitconfig"
printf '[user]\n\tname = dybatpho\n\temail = dybatpho@example.test\n[init]\n\tdefaultBranch = main\n' \
  > "${GIT_CONFIG_GLOBAL}"
# The module tests reach across the whole library, so the helper asks for every
# module. A script under test that cares about a narrower module set sources
# `init.sh` itself in a fresh shell, the way `test/init.bats` does.
. "${DYBATPHO_DIR}/init.sh" --modules all

# The same trap stays armed in the test body, where it captures a stack trace
# for every command, the library's own included: a test driving the Bash math
# engine over twenty-digit values spent 28s in the trap and 0.1s in the code.
# The trap Bats installs is therefore put back behind a test of where the
# command comes from, so a command of `src/` or of a bats library never calls
# the handler, and a failure is reported at the line of the `.bats` file that
# called into it. Telling Bats to exclude those paths is not enough: a skipped
# call into the handler still costs some fifty microseconds. A trap of any
# other shape, from another Bats version, is put back as it was.
#
# `$_` is saved first, since the assignments clear it before it reaches the
# handler. And skipping the library shifts the trace Bats reports when the
# library ends the test itself, as `dybatpho::die` does: no ERR trap runs for
# an `exit`, so Bats takes the trace before last, assuming the last one was
# taken for the `exit`, and pointed at the line above the call. A library
# command therefore marks the last trace -- the line of the test that called
# in -- as the one to report, as Bats does around its own `load`, and a
# command of the test clears the mark again.
__DYBATPHO_HELPER_QUIET_SRC="${DYBATPHO_DIR}/src/"
__DYBATPHO_HELPER_QUIET_LIB="${DYBATPHO_DIR}/test/lib/"
# The expansions are the trap's own, made each time it fires.
# shellcheck disable=SC2016
if [[ "${__dybatpho_helper_saved_trap}" == "trap -- 'bats_debug_trap \"\$BASH_SOURCE\" \"\$_\"' DEBUG" ]]; then
  # One line: Bash counts the lines of a trap into the line numbers Bats
  # reads, so a trap spread over several would shift every reported line.
  __dybatpho_helper_saved_trap='__DYBATPHO_HELPER_LAST_ARG=$_; '
  __dybatpho_helper_saved_trap+='if [[ "${BASH_SOURCE}" == "${__DYBATPHO_HELPER_QUIET_SRC}"* || '
  __dybatpho_helper_saved_trap+='"${BASH_SOURCE}" == "${__DYBATPHO_HELPER_QUIET_LIB}"* ]]; '
  __dybatpho_helper_saved_trap+='then BATS_DEBUG_LAST_STACK_TRACE_IS_VALID=1; '
  __dybatpho_helper_saved_trap+='else BATS_DEBUG_LAST_STACK_TRACE_IS_VALID=; '
  __dybatpho_helper_saved_trap+='bats_debug_trap "$BASH_SOURCE" "${__DYBATPHO_HELPER_LAST_ARG}"; fi'
  printf -v __dybatpho_helper_saved_trap 'trap -- %q DEBUG' "${__dybatpho_helper_saved_trap}"
fi

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

# The library reads its settings under a `DYBATPHO_` prefix first and the bare
# names second, so a developer's exported `DYBATPHO_LOG_LEVEL` or
# `DYBATPHO_DRY_RUN` would win over what a test sets. The tests start from none.
unset DYBATPHO_LOG_LEVEL DYBATPHO_LOG_FORMAT DYBATPHO_LOG_FILE DYBATPHO_LOG_FILE_LEVEL \
  DYBATPHO_LOG_FILE_MAX_BYTES DYBATPHO_LOG_FILE_MAX_BACKUPS DYBATPHO_LOG_REQUEST_ID DYBATPHO_DRY_RUN

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
  local __run_traced_expected_rc="" __run_traced_separate=""
  while (($#)) && [[ "$1" == -* || "$1" == '!' ]]; do
    case "$1" in
      '!') __run_traced_expected_rc="-1" ;;
      -[0-9]*) __run_traced_expected_rc="${1#-}" ;;
      --separate-stderr) __run_traced_separate="1" ;;
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

  local __run_traced_dir="${BATS_TEST_TMPDIR:-${BATS_FILE_TMPDIR:-${BATS_RUN_TMPDIR}}}"
  local __run_traced_output_file="${__run_traced_dir}/run_traced.out"
  local __run_traced_stderr_file="${__run_traced_dir}/run_traced.err"
  status=0
  if [[ -n "${__run_traced_separate}" ]]; then
    "$@" > "${__run_traced_output_file}" 2> "${__run_traced_stderr_file}" || status=$?
  else
    "$@" > "${__run_traced_output_file}" || status=$?
  fi
  output="$(< "${__run_traced_output_file}")"
  if [[ -n "${output}" ]]; then
    mapfile -t lines <<< "${output}"
  else
    lines=()
  fi
  if [[ -n "${__run_traced_separate}" ]]; then
    stderr="$(< "${__run_traced_stderr_file}")"
    if [[ -n "${stderr}" ]]; then
      mapfile -t stderr_lines <<< "${stderr}"
    else
      stderr_lines=()
    fi
  else
    unset -v stderr stderr_lines
  fi

  if [[ -z "${__run_traced_expected_rc}" ]]; then
    return 0
  fi
  if [[ "${__run_traced_expected_rc}" == "-1" ]]; then
    if ((status == 0)); then
      printf 'run_traced: expected nonzero exit code, got 0\n%s\n' "${output}" >&2
      return 1
    fi
  elif ((status != 10#${__run_traced_expected_rc})); then
    printf 'run_traced: expected exit code %s, got %s\n%s\n' \
      "${__run_traced_expected_rc}" "${status}" "${output}" >&2
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
#
#   A directory such as `/usr/bin` holds around a thousand commands, and one
#   `ln` per command made a single call cost seconds; a test hiding the same
#   tool several times paid that again each time. Each directory is mirrored by
#   one `ln` over all of its entries instead.
function path_without {
  local tool="$1" bin="${BATS_TEST_TMPDIR}/path-without-$1"
  local kept="" entry target
  local -a entries=() targets=()
  mkdir -p "${bin}"
  IFS=':' read -r -a entries <<< "${PATH}"
  for entry in ${entries[@]+"${entries[@]}"}; do
    [[ -n "${entry}" ]] || continue
    if [[ ! -x "${entry}/${tool}" ]]; then
      kept+="${entry}:"
      continue
    fi
    targets=()
    for target in "${entry}"/*; do
      [[ -e "${target}" || -L "${target}" ]] || continue
      [[ "${target##*/}" != "${tool}" ]] || continue
      targets+=("${target}")
    done
    ((${#targets[@]})) || continue
    # A name an earlier directory, or an earlier call, already linked keeps
    # that link, the way `PATH` lookup would: `ln` refuses it and carries on
    # with the rest, so its status and complaint are expected.
    # dyshellint disable=BSG095 # test scaffolding must act even when a test sets DRY_RUN for the code under test
    ln -s ${targets[@]+"${targets[@]}"} "${bin}/" 2> /dev/null || true
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
  # dyshellint disable=BSG095 # test scaffolding must act even when a test sets DRY_RUN for the code under test
  sed -e "${script}" "${file}" > "${file}.sed" && mv -f -- "${file}.sed" "${file}"
}
