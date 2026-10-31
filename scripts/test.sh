#!/usr/bin/env bash
# A `$(...)` inside an argument passes a value on, the way this code calls the library; the inner command prints its
# own diagnostic when it fails, so a separate assignment for each would only add lines.
# shellcheck disable=SC2312 # values are passed on through $(...)
# @file test.sh
# @brief Test all modules of dybatpho
# @description
#   Runs the Bats suite and reports it as a per-file table plus one set of
#   totals, instead of the several thousand TAP lines the suite emits. Failure
#   detail is replayed once, grouped, after the totals.
#
#   Speed comes from letting Bats schedule at the *test* level (`--jobs`), so a
#   single heavy file such as `cli.bats` spreads over every core instead of
#   pinning one. `test/test_helper.bash` does the other half of the work by
#   parking the Bats `DEBUG` trap while it sources the library, which is what
#   makes a test cost ~150ms instead of ~800ms.
#
#   Bats needs GNU `parallel` for `--jobs`. Without it -- or with `--shards` --
#   the files are shared out to `--jobs` background Bats processes instead, each
#   running one file at a time: a worker claims the next unclaimed file, the
#   heaviest first, with an atomic `mkdir`, so a slow file never holds up a
#   queue of others behind it. The slowest file sets the floor of the run. Their TAP and JUnit output is merged into the
#   same report, so the table and totals read the same either way.
#
#   Coverage is opt-in, because kcov roughly triples the wall clock. kcov also
#   accumulates trace state for every process it follows and never releases it,
#   so a single invocation over the whole suite grows until the OOM killer takes
#   the run down. `--coverage` therefore runs one kcov invocation per chunk of
#   `--chunk` files and merges the parts into `coverage/bats`, the layout the CI
#   upload step expects.
#
#   `--related` takes changed files instead of test files and runs only the
#   `.bats` files that cover them, which is what the pre-commit hook passes.
#
# @example
#   scripts/test.sh                       # whole suite, no coverage
#   scripts/test.sh test/cli.bats         # one file, or several
#   scripts/test.sh --coverage            # whole suite + coverage report
#   scripts/test.sh --filter semver       # only tests whose name matches
#   scripts/test.sh --related src/json.sh # the tests a change can break
#
# @env DYBATPHO_TEST_JOBS number Initial value of `--jobs`.
# @env DYBATPHO_TEST_CHUNK number Initial value of `--chunk`.
# @env DYBATPHO_TEST_SHARDS string Initial value of `--shards`, `true` to always run the Bash workers.
#
# @see
#   - `test/test_helper.bash`
#   - `.github/workflows/ci.yaml`
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules cli

dybatpho::register_common_handlers

BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"

# How many `@test` cases each collected file declares, keyed by its path.
# `__dybatpho_test_collect_into` counts each file once; the ordering, the chunk
# packing and the expected total all read it from here.
declare -A __DYBATPHO_TEST_COUNTS=()

# @description Validator for the option values that must be a worker or chunk
#   count.
# @arg $1 string Value to check
# @exitcode 0 If the value is a positive integer
# @exitcode 1 Otherwise
# @internal
function __dybatpho_test_is_count {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# @description Default for `--color`, so a terminal gets a live progress line
#   and a pipe or a CI log gets plain text.
# @noargs
# @stdout `true` when stdout is a terminal, `false` otherwise
# @internal
function __dybatpho_test_tty {
  if dybatpho::is_tty stdout; then printf 'true'; else printf 'false'; fi
}

# @description Collect the `.bats` files to run, ordered by test count
#   descending, and record each file's count in `__DYBATPHO_TEST_COUNTS`. Bats
#   hands files to its workers in the order it receives them, so starting the
#   longest file first stops a run from ending with a lone straggler while
#   every other core sits idle.
# @arg $1 string Name of the array receiving the file paths
# @arg $@ path Files or directories; the whole `test/` directory when empty
# @set The named array, and `__DYBATPHO_TEST_COUNTS`
# @internal
function __dybatpho_test_collect_into {
  local -n _collected="$1"
  shift
  local -a _found=()
  local _target _file
  if (($#)); then
    for _target in "$@"; do
      if [[ -d "${_target}" ]]; then
        mapfile -t -O "${#_found[@]}" _found < <(find "${_target}" -maxdepth 1 -name '*.bats' -type f)
      else
        _found+=("${_target}")
      fi
    done
  else
    mapfile -t _found < <(find "${DYBATPHO_DIR}/test" -maxdepth 1 -name '*.bats' -type f)
  fi
  for _file in ${_found[@]+"${_found[@]}"}; do
    __DYBATPHO_TEST_COUNTS["${_file}"]="$(grep -c '^@test' "${_file}" || true)"
  done
  mapfile -t _collected < <(
    for _file in ${_found[@]+"${_found[@]}"}; do
      printf '%s\t%s\n' "${__DYBATPHO_TEST_COUNTS["${_file}"]}" "${_file}"
    done | sort -rn | cut -f2
  )
}

# @description Print the names of the functions a module defines, public and
#   internal alike: a module that asks for another one probes it through an
#   internal name, so both count as a use.
# @arg $1 string Module name
# @stdout One function name per line
# @internal
function __dybatpho_test_functions_of {
  sed -nE 's/^function ([A-Za-z0-9_:]+).*/\1/p' "${DYBATPHO_DIR}/src/$1.sh"
}

# @description Map changed files to the `.bats` files that can catch a
#   regression in them, so a commit runs a few files instead of the suite.
#
#   A module is covered by its own test file, by the test file of every module
#   that calls into it, and by any test or example calling it. Calls are found
#   by name rather than read from the dependency table in `init.sh`, because a
#   module may ask for another one at run time without declaring it. Anything every
#   test passes through — `init.sh`, a core module, the test helper, this
#   runner — maps to the whole suite.
# @arg $@ path Changed files, relative to the repository root or absolute
# @stdout One test path per line, or the `test/` directory for the whole suite
# @internal
function __dybatpho_test_related {
  local _test_dir="${DYBATPHO_DIR}/test"
  local -A _modules=() _tests=()
  local _file _name
  for _file in "$@"; do
    _file="${_file#"${DYBATPHO_DIR}"/}"
    _file="${_file#./}"
    case "${_file}" in
      init.sh | scripts/test.sh | test/test_helper.bash | test/lib/*)
        printf '%s\n' "${_test_dir}"
        return 0
        ;;
      src/*.sh)
        _name="${_file#src/}"
        _name="${_name%.sh}"
        if [[ " ${DYBATPHO_CORE_MODULES} " == *" ${_name} "* ]]; then
          printf '%s\n' "${_test_dir}"
          return 0
        fi
        _modules["${_name}"]=1
        _tests["${_test_dir}/conventions.bats"]=1
        _tests["${_test_dir}/modules_isolated.bats"]=1
        ;;
      test/*.bats) _tests["${DYBATPHO_DIR}/${_file}"]=1 ;;
      example/*.sh) _tests["${_test_dir}/examples.bats"]=1 ;;
      scripts/*.sh)
        while read -r _name; do
          _tests["${_name}"]=1
        done < <(grep -lF -- "${_file}" "${_test_dir}"/*.bats || true)
        ;;
      *) ;;
    esac
  done

  if ((${#_modules[@]})); then
    local _patterns
    # `create_temp` registers the file for cleanup on exit.
    dybatpho::create_temp _patterns ".txt" "test-related"
    for _name in "${!_modules[@]}"; do
      __dybatpho_test_functions_of "${_name}"
    done > "${_patterns}"
    # Only direct callers: followed transitively, `json` alone reaches through
    # `network`, `validate` and `cli` to most of the suite, and CI runs the
    # whole of it anyway.
    while read -r _file; do
      _name="$(basename -- "${_file}" .sh)"
      _tests["${_test_dir}/${_name}.bats"]=1
    done < <(grep -lwFf "${_patterns}" "${DYBATPHO_DIR}"/src/*.sh || true)
    # A test file of another area, or an example, may call the module directly.
    while read -r _file; do
      _tests["${_file}"]=1
    done < <(grep -lwFf "${_patterns}" "${_test_dir}"/*.bats || true)
    if grep -qwFf "${_patterns}" "${DYBATPHO_DIR}"/example/*.sh; then
      _tests["${_test_dir}/examples.bats"]=1
    fi
  fi

  for _file in "${!_tests[@]}"; do
    [[ -f "${_file}" ]] && printf '%s\n' "${_file}"
  done
  return 0
}

# @description Filter a raw TAP stream down to a live view: one rewritten
#   progress line, plus every failure the moment it happens. The rest stays in
#   the log and is replayed, grouped, once the run is over — the unfiltered
#   stream is what made a run unreadable.
# @arg $1 number Total number of tests expected
# @stdin TAP output from Bats
# @internal
function __dybatpho_test_progress {
  awk -v total="$1" -v color="${COLOR}" \
    -v red="${__DYBATPHO_TEST_RED}" \
    -v dim="${__DYBATPHO_TEST_DIM}" \
    -v reset="${__DYBATPHO_TEST_RESET}" '
    function clear() { if (color == "true") printf "\r\033[K" }
    /^not ok / {
      finished++
      sub(/^not ok [0-9]+ /, "")
      sub(/ # in [0-9]+ ms$/, "")
      clear()
      printf "  %s\xe2\x9c\x98%s %s\n", red, reset, $0
      fflush()
      next
    }
    /^ok / {
      finished++
      if (color == "true") {
        printf "\r\033[K  %s%d/%d%s", dim, finished, total, reset
        fflush()
      }
      next
    }
    END { clear() }
  '
}

# @description Spread the test files over chunks of at most `--chunk` files,
#   balanced by test count. Slicing the count-ordered list directly, which is
#   what the chunking used to do, puts the heaviest files together: that one
#   chunk decides how much trace state kcov accumulates, so it sets the memory
#   ceiling for the whole run, while the tail chunks end up too small to keep
#   the workers busy. Handing each file to the emptiest chunk keeps every chunk
#   near the average, which lowers the ceiling without changing how many times
#   kcov runs.
# @arg $1 number Maximum files per chunk
# @arg $@ path Test files, ordered by test count descending
# @stdout One chunk per line, file paths separated by tabs
# @internal
function __dybatpho_test_pack {
  local _chunk="$1"
  shift
  # The chunk size is checked by `__dybatpho_test_is_count` in the option spec, and the other counts are the plain
  # digits of the junit report Bats writes.
  # dyshellint disable=BSG087 # counts are checked or plain digits
  local _bins=$((($# + _chunk - 1) / _chunk)) _file _b _best
  local -a _load=() _held=() _names=()
  for ((_b = 0; _b < _bins; _b++)); do
    _load[_b]=0
    _held[_b]=0
    _names[_b]=""
  done
  for _file in "$@"; do
    _best=-1
    for ((_b = 0; _b < _bins; _b++)); do
      ((_held[_b] < _chunk)) || continue
      ((_best < 0 || _load[_b] < _load[_best])) && _best="${_b}"
    done
    _load[_best]=$((_load[_best] + ${__DYBATPHO_TEST_COUNTS["${_file}"]:-0}))
    _held[_best]=$((_held[_best] + 1))
    _names[_best]+="${_file}"$'\t'
  done
  for ((_b = 0; _b < _bins; _b++)); do
    printf '%s\n' "${_names[_b]%$'\t'}"
  done
}

# @description Set the colours the report uses, or none when `--no-color`.
# @noargs
# @set `__DYBATPHO_TEST_RESET`, `__DYBATPHO_TEST_DIM`, `__DYBATPHO_TEST_RED`,
#   `__DYBATPHO_TEST_GREEN` and `__DYBATPHO_TEST_BOLD`
# @internal
function __dybatpho_test_palette {
  if [[ "${COLOR}" == "true" ]]; then
    __DYBATPHO_TEST_RESET=$'\033[0m' __DYBATPHO_TEST_DIM=$'\033[2m'
    __DYBATPHO_TEST_RED=$'\033[31m' __DYBATPHO_TEST_GREEN=$'\033[32m'
    __DYBATPHO_TEST_BOLD=$'\033[1m'
  else
    __DYBATPHO_TEST_RESET="" __DYBATPHO_TEST_DIM=""
    __DYBATPHO_TEST_RED="" __DYBATPHO_TEST_GREEN=""
    __DYBATPHO_TEST_BOLD=""
  fi
}

# The steps below read the run's state through Bash's dynamic scope rather
# than taking a dozen arguments each: `_files`, `_expected`, `_expected_in`,
# `_run_dir`, `_tap`, `_bats_args`, `_coverage_dir` and `_kcov_source_args`
# are locals of `__dybatpho_test_run`. What a step hands back goes through a
# variable the run names.

# @description Run Bats once over every collected file, feeding the live
#   progress view and keeping the raw TAP for the summary.
# @noargs
# @internal
function __dybatpho_test_bats {
  # `|| true`: a failing suite has to reach the summary below, and dybatpho
  # runs with both `errexit` and `pipefail` on.
  # shellcheck disable=SC2310 # a failing suite has to reach the summary below
  "${BATS_CMD}" "${_bats_args[@]}" "${_files[@]}" 2>&1 \
    | tee "${_tap}" | __dybatpho_test_progress "${_expected}" || true
}

# @description One worker of `__dybatpho_test_bats_shards`: walk the file list,
#   heaviest first, and run every file it manages to claim. A claim is a
#   `mkdir`, which exactly one process can win, so files are handed out as
#   workers come free. It reads the run's state through dynamic scope, like the
#   other steps, and writes each file's TAP to a capture of its own as well as to
#   the shared live view.
# @noargs
# @stdout The TAP of every file it ran, one whole line at a time
# @internal
function __dybatpho_test_shard_worker {
  local _i _out
  for ((_i = 0; _i < ${#_files[@]}; _i++)); do
    mkdir "${_claims}/${_i}" 2> /dev/null || continue
    _out="${_run_dir}/file${_i}"
    mkdir -p "${_out}"
    # `awk` writes each line whole, so the workers' lines interleave in the
    # live view without tearing one another apart. `|| true`: a failing file
    # has to reach the summary.
    "${BATS_CMD}" "${_worker_args[@]/"${_run_dir}"/"${_out}"}" "${_files[_i]}" 2>&1 \
      | tee "${_out}/run.tap" | awk '{ print; fflush() }' || true
  done
}

# @description Run the collected files on `JOBS` background Bats workers, for a
#   machine without GNU `parallel`, which Bats needs to spread files over
#   `--jobs`.
#   Files are handed out by `__dybatpho_test_shard_worker` as workers come free
#   rather than split up front by a guess at their cost, and each one runs its
#   tests one after another: Bats can run the tests of a file side by side
#   without `parallel`, but its semaphore waits forever for a slot whose test
#   was killed, and a run hung on it. The slowest file therefore sets the
#   floor of the run's wall clock. Every file gets its own Bats run, writing its own TAP capture and JUnit report,
#   and those are merged afterwards into the ones a single run would have
#   written: the TAP file by file, so a failure's detail stays with it, and the
#   JUnit reports into one, whose `<testsuite>` elements the summary reads.
# @noargs
# @internal
function __dybatpho_test_bats_shards {
  local _claims="${_run_dir}/claims" _workers="${JOBS}" _w _i
  mkdir -p "${_claims}"
  ((_workers <= ${#_files[@]})) || _workers="${#_files[@]}"
  # Each worker's Bats runs with `--jobs 1`: the width comes from the workers.
  local -a _worker_args=()
  local _arg _after_jobs=0
  for _arg in "${_bats_args[@]}"; do
    ((_after_jobs)) && _arg=1
    _after_jobs=0
    [[ "${_arg}" == "--jobs" ]] && _after_jobs=1
    _worker_args+=("${_arg}")
  done

  # Each worker swallows its files' failures itself, and a failing file has to
  # reach the summary below rather than stop the run.
  # shellcheck disable=SC2310 # a failing file has to reach the summary below
  {
    for ((_w = 0; _w < _workers; _w++)); do
      __dybatpho_test_shard_worker &
    done
    wait
  } | __dybatpho_test_progress "${_expected}" || true

  # Merge in collection order, so the replayed failures come out grouped by
  # file and in the same order on every run.
  : > "${_tap}"
  : > "${_run_dir}/report.xml"
  for ((_i = 0; _i < ${#_files[@]}; _i++)); do
    if [[ -f "${_run_dir}/file${_i}/run.tap" ]]; then
      cat "${_run_dir}/file${_i}/run.tap" >> "${_tap}"
    fi
    if [[ -f "${_run_dir}/file${_i}/report.xml" ]]; then
      cat "${_run_dir}/file${_i}/report.xml" >> "${_run_dir}/report.xml"
    fi
  done
  return 0
}

# @description Run Bats under kcov once per chunk of files, so no single kcov
#   process accumulates trace state for the whole suite, and gather each
#   chunk's junit report into one.
# @arg $1 string Name of the array receiving the coverage directory of every chunk
# @set The named array
# @internal
function __dybatpho_test_bats_coverage {
  local -n _chunk_parts="$1"
  dybatpho::require "kcov"
  [[ -n "${_coverage_dir}" ]] || dybatpho::die "No coverage directory"
  rm -rf "${_coverage_dir}"
  mkdir -p "${_coverage_dir}"
  : > "${_tap}"
  local _index=0 _part _chunk_out _line
  local -a _chunk_files
  # One Bats run per chunk, so each writes its own junit report; they are
  # concatenated afterwards and summarised as one.
  local test_pack_output
  test_pack_output=$(__dybatpho_test_pack "${CHUNK}" "${_files[@]}")
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    IFS=$'\t' read -r -a _chunk_files <<< "${_line}"
    ((${#_chunk_files[@]})) || continue
    _part="${_coverage_dir}/part${_index}"
    _chunk_out="${_run_dir}/chunk${_index}"
    mkdir -p "${_chunk_out}"
    # shellcheck disable=SC2310 # a failing suite has to reach the summary below
    kcov \
      --clean \
      --dump-summary \
      "${_kcov_source_args[@]}" \
      "${_part}" \
      "${BATS_CMD}" "${_bats_args[@]/"${_run_dir}"/"${_chunk_out}"}" \
      ${_chunk_files[@]+"${_chunk_files[@]}"} \
      2>&1 | tee -a "${_tap}" | __dybatpho_test_progress "${_expected}" || true
    _chunk_parts+=("${_part}")
    _index=$((_index + 1))
  done < <(printf '%s' "${test_pack_output}")
  cat "${_run_dir}"/chunk*/report.xml > "${_run_dir}/report.xml" 2> /dev/null
}

# @description Print the per-file table, the totals, and every failure once.
#   The table is read back from the junit report rather than the TAP stream:
#   TAP carries no file attribution, and with `--jobs` the lines from
#   different files interleave.
# @arg $1 number Seconds the run took
# @arg $2 string Name of the variable receiving the number of failed files
# @arg $3 string Name of the variable receiving the number of tests that never ran
# @set The two named variables
# @internal
function __dybatpho_test_summary {
  local _elapsed_total="$1"
  local -n _summary_failed="$2" _summary_missing="$3"
  local _failed_count=0 _never_ran=0
  local _reset="${__DYBATPHO_TEST_RESET}" _dim="${__DYBATPHO_TEST_DIM}"
  local _red="${__DYBATPHO_TEST_RED}" _green="${__DYBATPHO_TEST_GREEN}"
  local _bold="${__DYBATPHO_TEST_BOLD}"
  local _files_passed=0 _tests_passed=0 _tests_failed=0
  local -a _failed_files=()
  local _name _tests _failures _errors _elapsed _bad _passed _short
  # The five attributes of one `<testsuite>` element, as tab-separated fields.
  local _suite_fields='s/.*name="([^"]*)".*tests="([^"]*)".*failures="([^"]*)".*'
  _suite_fields+='errors="([^"]*)".*time="([^"]*)".*/\1\t\2\t\3\t\4\t\5/'

  printf '\n'
  if [[ -s "${_run_dir}/report.xml" ]]; then
    while IFS=$'\t' read -r _name _tests _failures _errors _elapsed; do
      # The chunk size is checked by `__dybatpho_test_is_count` in the option spec, and the other counts are the plain
      # digits of the junit report Bats writes.
      # dyshellint disable=BSG087 # counts are checked or plain digits
      _bad=$((_failures + _errors))
      # The chunk size is checked by `__dybatpho_test_is_count` in the option spec, and the other counts are the plain
      # digits of the junit report Bats writes.
      # dyshellint disable=BSG087 # counts are checked or plain digits
      _passed=$((_tests - _bad))
      _tests_passed=$((_tests_passed + _passed))
      _tests_failed=$((_tests_failed + _bad))
      # A file can report fewer tests than it declares when a worker dies
      # mid-run. Counting the remainder as a clean pass is how that goes
      # unnoticed, so a shortfall fails the file on its own.
      _short=0
      [[ -z "${FILTER}" ]] \
        && _short=$((${_expected_in["${_name}"]:-_tests} - _tests))
      if ((_short > 0)); then
        _failed_count=$((_failed_count + 1))
        _failed_files+=("${_name}")
        printf '  %s✘%s %-18s %s%3d passed%s, %s%d never ran%s %s%6.1fs%s\n' \
          "${_red}" "${_reset}" "${_name}" \
          "${_dim}" "${_passed}" "${_reset}" \
          "${_red}" "${_short}" "${_reset}" \
          "${_dim}" "${_elapsed}" "${_reset}"
      elif ((_bad == 0)); then
        _files_passed=$((_files_passed + 1))
        printf '  %s✔%s %-18s %s%3d passed%s %s%6.1fs%s\n' \
          "${_green}" "${_reset}" "${_name}" \
          "${_dim}" "${_passed}" "${_reset}" \
          "${_dim}" "${_elapsed}" "${_reset}"
      else
        _failed_count=$((_failed_count + 1))
        _failed_files+=("${_name}")
        printf '  %s✘%s %-18s %s%3d passed%s, %s%d failed%s %s%6.1fs%s\n' \
          "${_red}" "${_reset}" "${_name}" \
          "${_dim}" "${_passed}" "${_reset}" \
          "${_red}" "${_bad}" "${_reset}" \
          "${_dim}" "${_elapsed}" "${_reset}"
      fi
    done < <(
      grep -o '<testsuite [^>]*>' "${_run_dir}/report.xml" \
        | sed -E "${_suite_fields}" \
        | sort
    )
  else
    printf '  %s✘ Bats produced no report%s\n' "${_red}" "${_reset}"
    # Whatever Bats said before giving up is in the TAP capture, where the
    # progress filter dropped it as not being a test line.
    if [[ -s "${_tap}" ]]; then
      sed 's/^/    /' "${_tap}" | tail -n 20
    fi
    _failed_count=1
  fi

  local _executed=$((_tests_passed + _tests_failed))
  printf '\n%sFiles%s  %d passed, %d failed, %d total\n' \
    "${_bold}" "${_reset}" "${_files_passed}" "${_failed_count}" "${#_files[@]}"
  if [[ -n "${FILTER}" ]]; then
    printf '%sTests%s  %d passed, %d failed, %d matched %s\n' \
      "${_bold}" "${_reset}" "${_tests_passed}" "${_tests_failed}" \
      "${_executed}" "${FILTER}"
  else
    printf '%sTests%s  %d passed, %d failed, %d of %d\n' \
      "${_bold}" "${_reset}" "${_tests_passed}" "${_tests_failed}" \
      "${_executed}" "${_expected}"
  fi
  printf '%sTime%s   %ds\n' "${_bold}" "${_reset}" "${_elapsed_total}"

  # A test that never ran is not a pass. Bats only says so in a warning line
  # that used to scroll past unnoticed, so it gets its own verdict here.
  if [[ -z "${FILTER}" ]] && ((_executed < _expected)); then
    _never_ran=$((_expected - _executed))
    printf '\n%s%s%d test(s) never ran%s — a worker died or a file failed to load.\n' \
      "${_bold}" "${_red}" "${_never_ran}" "${_reset}"
  fi

  # Replayed only when something failed, so a green run stops at the table above
  # and a red run still shows every assertion message without a second run.
  if ((${#_failed_files[@]} || _never_ran)); then
    printf '\n%s%sFailures%s\n\n' "${_bold}" "${_red}" "${_reset}"
    awk '
      /^not ok /        { show = 1; sub(/^not ok [0-9]+ /, ""); print "  \xe2\x9c\x98 " $0; next }
      /^ok /            { show = 0; next }
      /^1\.\./          { show = 0; next }
      /^# bats warning/ { print "  " $0; next }
      show              { print "    " $0 }
    ' "${_tap}"
  fi
  _summary_failed="${_failed_count}"
  _summary_missing="${_never_ran}"
}

# @description Merge the per-chunk coverage into `coverage/bats`, the layout
#   the CI upload step expects, and drop the parts.
# @arg $@ path Coverage directory of every chunk
# @internal
function __dybatpho_test_coverage_merge {
  local -a _parts=("$@")
  dybatpho::progress "Merging ${#_parts[@]} coverage part(s)"
  [[ -n "${_coverage_dir}" ]] || dybatpho::die "No coverage directory"
  kcov --merge "${_kcov_source_args[@]}" \
    "${_coverage_dir}/merged" "${_parts[@]}" > /dev/null
  rm -rf "${_coverage_dir}/bats"
  mv "${_coverage_dir}/merged/kcov-merged" "${_coverage_dir}/bats"
  # Leave only the merged report behind; the per-chunk parts are an
  # implementation detail and are several times its size.
  # dyshellint disable=BSG089 # `_parts` holds the chunk directories this function created under the run directory
  rm -rf "${_coverage_dir}/merged" "${_parts[@]}"
  dybatpho::success "Coverage written to ${_coverage_dir}/bats"
}

# This function declares no command line; it names `dybatpho::opts::setup`
# in a comment to explain how the array it reads was filled.
# dyshellint disable=BSG052
# @description Run the suite and report it.
# @noargs
# @exitcode 0 If every test ran and passed
# @exitcode 1 Otherwise
# @internal
function __dybatpho_test_run {
  __dybatpho_test_palette
  local _reset="${__DYBATPHO_TEST_RESET}" _dim="${__DYBATPHO_TEST_DIM}"

  # `dybatpho::opts::setup` collects the positional arguments into an array, so
  # a path containing a space reaches the collector as one target.
  local -a _targets=(${TEST_ARGS[@]+"${TEST_ARGS[@]}"})
  if [[ "${RELATED}" == "true" ]]; then
    local _related
    # shellcheck disable=SC2310 # the handler's status is the point of the `if`: a failing job is counted, not fatal
    _related="$(__dybatpho_test_related ${_targets[@]+"${_targets[@]}"})" \
      || dybatpho::die "Could not tell which tests cover the changed files"
    _targets=()
    [[ -z "${_related}" ]] || mapfile -t _targets <<< "${_related}"
    if ! ((${#_targets[@]})); then
      printf '%sNo test covers the changed files%s\n' "${_dim}" "${_reset}"
      exit 0
    fi
  fi

  local -a _files=()
  __dybatpho_test_collect_into _files ${_targets[@]+"${_targets[@]}"}
  ((${#_files[@]})) || dybatpho::die "No test files found"

  local -A _expected_in
  local _expected=0 _file _count
  for _file in ${_files[@]+"${_files[@]}"}; do
    _count="${__DYBATPHO_TEST_COUNTS["${_file}"]}"
    _expected_in["$(basename "${_file}")"]="${_count}"
    _expected=$((_expected + _count))
  done

  # Bats needs GNU parallel for more than one worker, and without it exits
  # before running anything. A machine without `parallel` used to get a run
  # that reported every test as never run and nothing about why; it now gets
  # the Bash workers instead. kcov follows one process tree at a time, so a
  # coverage run without `parallel` still has one worker.
  local _runner="bats"
  if ((JOBS > 1)); then
    if [[ "${SHARDS}" == "true" ]] || ! command -v parallel &> /dev/null; then
      _runner="shards"
    fi
    if [[ "${_runner}" == "shards" && "${COVERAGE}" == "true" ]]; then
      dybatpho::warn "GNU parallel is not installed; coverage runs with one worker"
      JOBS=1
      _runner="bats"
    fi
  fi

  local _run_dir
  # `create_temp` registers the directory for cleanup on exit.
  dybatpho::create_temp _run_dir "/" "test"
  local _tap="${_run_dir}/run.tap"

  local -a _bats_args=(
    --print-output-on-failure
    --timing
    --formatter tap
    --report-formatter junit
    --output "${_run_dir}"
    --jobs "${JOBS}"
  )
  [[ "${VERBOSE_RUN}" == "true" ]] && _bats_args+=(--verbose-run)
  [[ -n "${FILTER}" ]] && _bats_args+=(--filter "${FILTER}")

  local value=""
  if [[ "${COVERAGE}" == "true" ]]; then
    printf -v value ' · coverage in chunks of %s' "${CHUNK}"
  fi
  [[ "${_runner}" == "shards" ]] && value="${value} · bash workers"
  printf '%s%d files · %d tests · %s jobs%s%s\n\n' \
    "${_dim}" "${#_files[@]}" "${_expected}" "${JOBS}" \
    "${value}" \
    "${_reset}"

  local _coverage_dir="${DYBATPHO_DIR}/coverage"
  local -a _kcov_source_args=(
    --include-path="${DYBATPHO_DIR}/init.sh,${DYBATPHO_DIR}/src"
    --strip-path="${DYBATPHO_DIR}"
    --exclude-line="# kcov(skip)"
    --exclude-region="# kcov(disabled):# kcov(enabled)"
  )
  local -a _parts=()
  local _start="${SECONDS}"
  if [[ "${COVERAGE}" == "true" ]]; then
    __dybatpho_test_bats_coverage _parts
  elif [[ "${_runner}" == "shards" ]]; then
    __dybatpho_test_bats_shards
  else
    __dybatpho_test_bats
  fi

  local _files_failed _missing
  __dybatpho_test_summary "$((SECONDS - _start))" _files_failed _missing
  if [[ "${COVERAGE}" == "true" ]]; then
    __dybatpho_test_coverage_merge ${_parts[@]+"${_parts[@]}"}
  fi

  if ((_files_failed || _missing)); then
    exit 1
  fi
  exit 0
}

#######################################
# @description CLI specification for this script.
#######################################
# @noargs
# dyshellint disable=BSG052 # `dybatpho::generate_from_spec` adds `--help` to every spec, so the option already exists
function _spec {
  dybatpho::opts::setup "Run the dybatpho test suite" TEST_ARGS \
    action:"__dybatpho_test_run"

  dybatpho::opts::flag "Collect coverage with kcov" COVERAGE -c --coverage \
    on:true off:false init:="false"
  dybatpho::opts::flag "Treat the arguments as changed files and run their tests" \
    RELATED -r --related on:true off:false init:="false"
  dybatpho::opts::flag "Trace every command Bats runs" VERBOSE_RUN -v --verbose-run \
    on:true off:false init:="false"
  local test_tty
  test_tty=$(__dybatpho_test_tty)
  # shellcheck disable=SC1083 # `--{no-}color` is dybatpho's toggle-switch syntax
  dybatpho::opts::flag "Colourise the report" COLOR --{no-}color \
    on:true off:false init:="${test_tty}"

  local cpu_count
  cpu_count=$(dybatpho::cpu_count || printf '1')
  dybatpho::opts::param "Bats workers to run at once" JOBS -j --jobs \
    env:DYBATPHO_TEST_JOBS init:="${cpu_count}" \
    validate:"__dybatpho_test_is_count \$OPTARG"
  dybatpho::opts::param "Test files per kcov invocation" CHUNK --chunk \
    env:DYBATPHO_TEST_CHUNK init:="5" \
    validate:"__dybatpho_test_is_count \$OPTARG"
  dybatpho::opts::param "Only run tests whose name matches" FILTER -f --filter \
    init:@empty
  dybatpho::opts::flag "Run the files on Bash workers even when GNU parallel is installed" \
    SHARDS --shards on:true off:false env:DYBATPHO_TEST_SHARDS init:="false"
}

dybatpho::generate_from_spec _spec "$@"
