#!/usr/bin/env bash
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
#   Coverage is opt-in, because kcov roughly triples the wall clock. kcov also
#   accumulates trace state for every process it follows and never releases it,
#   so a single invocation over the whole suite grows until the OOM killer takes
#   the run down. `--coverage` therefore runs one kcov invocation per chunk of
#   `--chunk` files and merges the parts into `coverage/bats`, the layout the CI
#   upload step expects.
#
# @example
#   scripts/test.sh                       # whole suite, no coverage
#   scripts/test.sh test/cli.bats         # one file, or several
#   scripts/test.sh --coverage            # whole suite + coverage report
#   scripts/test.sh --filter semver       # only tests whose name matches
#
# @env DYBATPHO_TEST_JOBS number Initial value of `--jobs`.
# @env DYBATPHO_TEST_CHUNK number Initial value of `--chunk`.
#
# @see
#   - `test/test_helper.bash`
#   - `.github/workflows/ci.yaml`
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules cli

dybatpho::register_common_handlers
dybatpho::require "nproc"

BATS_CMD="${DYBATPHO_DIR}/test/lib/core/bin/bats"

# @description Validator for the option values that must be a worker or chunk
#   count.
# @arg $1 string Value to check
# @exitcode 0 If the value is a positive integer
# @exitcode 1 Otherwise
function __dybatpho_test_is_count {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# @description Default for `--color`, so a terminal gets a live progress line
#   and a pipe or a CI log gets plain text.
# @stdout `true` when stdout is a terminal, `false` otherwise
function __dybatpho_test_tty {
  if [[ -t 1 ]]; then printf 'true'; else printf 'false'; fi
}

# @description Collect the `.bats` files to run, ordered by test count
#   descending. Bats hands files to its workers in the order it receives them,
#   so starting the longest file first stops a run from ending with a lone
#   straggler while every other core sits idle.
# @arg $@ path Files or directories; the whole `test/` directory when empty
# @stdout One file path per line
function __dybatpho_test_collect {
  local _target
  {
    if (($#)); then
      for _target in "$@"; do
        if [[ -d "${_target}" ]]; then
          find "${_target}" -maxdepth 1 -name '*.bats' -type f
        else
          echo "${_target}"
        fi
      done
    else
      find "${DYBATPHO_DIR}/test" -maxdepth 1 -name '*.bats' -type f
    fi
  } | while read -r _file; do
    printf '%s\t%s\n' "$(grep -c '^@test' "${_file}" || true)" "${_file}"
  done | sort -rn | cut -f2
}

# @description Filter a raw TAP stream down to a live view: one rewritten
#   progress line, plus every failure the moment it happens. The rest stays in
#   the log and is replayed, grouped, once the run is over — the unfiltered
#   stream is what made a run unreadable.
# @arg $1 number Total number of tests expected
# @stdin TAP output from Bats
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

# @description Run the suite and report it.
# @noargs
# @exitcode 0 If every test ran and passed
# @exitcode 1 Otherwise
function __dybatpho_test_run {
  if [[ "${COLOR}" == "true" ]]; then
    __DYBATPHO_TEST_RESET=$'\033[0m' __DYBATPHO_TEST_DIM=$'\033[2m'
    __DYBATPHO_TEST_RED=$'\033[31m' __DYBATPHO_TEST_GREEN=$'\033[32m'
    __DYBATPHO_TEST_BOLD=$'\033[1m'
  else
    __DYBATPHO_TEST_RESET="" __DYBATPHO_TEST_DIM=""
    __DYBATPHO_TEST_RED="" __DYBATPHO_TEST_GREEN=""
    __DYBATPHO_TEST_BOLD=""
  fi
  local _reset="${__DYBATPHO_TEST_RESET}" _dim="${__DYBATPHO_TEST_DIM}"
  local _red="${__DYBATPHO_TEST_RED}" _green="${__DYBATPHO_TEST_GREEN}"
  local _bold="${__DYBATPHO_TEST_BOLD}"

  # `dybatpho::opts::setup` collects the positional arguments into a single
  # space-joined string, so they are split back out here.
  local -a _targets _files
  read -r -a _targets <<< "${TEST_ARGS}"
  mapfile -t _files < <(__dybatpho_test_collect "${_targets[@]}")
  ((${#_files[@]})) || dybatpho::die "No test files found"

  local -A _expected_in
  local _expected=0 _file _count
  for _file in "${_files[@]}"; do
    _count="$(grep -c '^@test' "${_file}" || true)"
    _expected_in["$(basename "${_file}")"]="${_count}"
    _expected=$((_expected + _count))
  done

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

  printf '%s%d files · %d tests · %s jobs%s%s\n\n' \
    "${_dim}" "${#_files[@]}" "${_expected}" "${JOBS}" \
    "$([[ "${COVERAGE}" == "true" ]] && printf ' · coverage in chunks of %s' "${CHUNK}")" \
    "${_reset}"

  local _start="${SECONDS}"
  local -a _parts=()
  if [[ "${COVERAGE}" == "true" ]]; then
    dybatpho::require "kcov"
    local _coverage_dir="${DYBATPHO_DIR}/coverage"
    rm -rf "${_coverage_dir}"
    mkdir -p "${_coverage_dir}"
    : > "${_tap}"
    local _index=0 _part _chunk_out
    # One Bats run per chunk, so each writes its own junit report; they are
    # concatenated afterwards and summarised as one.
    while ((_index < ${#_files[@]})); do
      _part="${_coverage_dir}/part$((_index / CHUNK))"
      _chunk_out="${_run_dir}/chunk$((_index / CHUNK))"
      mkdir -p "${_chunk_out}"
      kcov \
        --clean \
        --dump-summary \
        --include-path="${DYBATPHO_DIR}/init.sh" \
        --include-path="${DYBATPHO_DIR}/src" \
        --exclude-line="# kcov(skip)" \
        --exclude-region="# kcov(disabled):# kcov(enabled)" \
        "${_part}" \
        "${BATS_CMD}" "${_bats_args[@]/${_run_dir}/${_chunk_out}}" \
        "${_files[@]:_index:CHUNK}" \
        2>&1 | tee -a "${_tap}" | __dybatpho_test_progress "${_expected}" || true
      _parts+=("${_part}")
      _index=$((_index + CHUNK))
    done
    cat "${_run_dir}"/chunk*/report.xml > "${_run_dir}/report.xml" 2> /dev/null
  else
    # `|| true`: a failing suite has to reach the summary below, and dybatpho
    # runs with both `errexit` and `pipefail` on.
    "${BATS_CMD}" "${_bats_args[@]}" "${_files[@]}" 2>&1 \
      | tee "${_tap}" | __dybatpho_test_progress "${_expected}" || true
  fi
  local _elapsed_total=$((SECONDS - _start))

  # Read the per-file table back from the junit report rather than the TAP
  # stream: TAP carries no file attribution, and with `--jobs` the lines from
  # different files interleave.
  local _files_passed=0 _files_failed=0 _tests_passed=0 _tests_failed=0
  local -a _failed_files=()
  local _name _tests _failures _errors _elapsed _bad _passed _short

  printf '\n'
  if [[ -s "${_run_dir}/report.xml" ]]; then
    while IFS=$'\t' read -r _name _tests _failures _errors _elapsed; do
      _bad=$((_failures + _errors))
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
        _files_failed=$((_files_failed + 1))
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
        _files_failed=$((_files_failed + 1))
        _failed_files+=("${_name}")
        printf '  %s✘%s %-18s %s%3d passed%s, %s%d failed%s %s%6.1fs%s\n' \
          "${_red}" "${_reset}" "${_name}" \
          "${_dim}" "${_passed}" "${_reset}" \
          "${_red}" "${_bad}" "${_reset}" \
          "${_dim}" "${_elapsed}" "${_reset}"
      fi
    done < <(
      grep -o '<testsuite [^>]*>' "${_run_dir}/report.xml" \
        | sed -E 's/.*name="([^"]*)".*tests="([^"]*)".*failures="([^"]*)".*errors="([^"]*)".*time="([^"]*)".*/\1\t\2\t\3\t\4\t\5/' \
        | sort
    )
  else
    printf '  %s✘ Bats produced no report — see the output above%s\n' \
      "${_red}" "${_reset}"
    _files_failed=1
  fi

  local _executed=$((_tests_passed + _tests_failed))
  printf '\n%sFiles%s  %d passed, %d failed, %d total\n' \
    "${_bold}" "${_reset}" "${_files_passed}" "${_files_failed}" "${#_files[@]}"
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
  local _missing=0
  if [[ -z "${FILTER}" ]] && ((_executed < _expected)); then
    _missing=$((_expected - _executed))
    printf '\n%s%s%d test(s) never ran%s — a worker died or a file failed to load.\n' \
      "${_bold}" "${_red}" "${_missing}" "${_reset}"
  fi

  # Replayed only when something failed, so a green run stops at the table above
  # and a red run still shows every assertion message without a second run.
  if ((${#_failed_files[@]} || _missing)); then
    printf '\n%s%sFailures%s\n\n' "${_bold}" "${_red}" "${_reset}"
    awk '
      /^not ok /        { show = 1; sub(/^not ok [0-9]+ /, ""); print "  \xe2\x9c\x98 " $0; next }
      /^ok /            { show = 0; next }
      /^1\.\./          { show = 0; next }
      /^# bats warning/ { print "  " $0; next }
      show              { print "    " $0 }
    ' "${_tap}"
  fi

  if [[ "${COVERAGE}" == "true" ]]; then
    dybatpho::progress "Merging ${#_parts[@]} coverage part(s)"
    kcov --merge "${_coverage_dir}/merged" "${_parts[@]}" > /dev/null
    rm -rf "${_coverage_dir}/bats"
    mv "${_coverage_dir}/merged/kcov-merged" "${_coverage_dir}/bats"
    # Leave only the merged report behind; the per-chunk parts are an
    # implementation detail and are several times its size.
    rm -rf "${_coverage_dir}/merged" "${_parts[@]}"
    dybatpho::success "Coverage written to ${_coverage_dir}/bats"
  fi

  if ((_files_failed || _missing)); then
    exit 1
  fi
  exit 0
}

function _spec {
  dybatpho::opts::setup "Run the dybatpho test suite" TEST_ARGS \
    action:"__dybatpho_test_run"

  dybatpho::opts::flag "Collect coverage with kcov" COVERAGE -c --coverage \
    on:true off:false init:="false"
  dybatpho::opts::flag "Trace every command Bats runs" VERBOSE_RUN -v --verbose-run \
    on:true off:false init:="false"
  # shellcheck disable=SC1083 # `--{no-}color` is dybatpho's toggle-switch syntax
  dybatpho::opts::flag "Colourise the report" COLOR --{no-}color \
    on:true off:false init:="$(__dybatpho_test_tty)"

  dybatpho::opts::param "Bats workers to run at once" JOBS -j --jobs \
    env:DYBATPHO_TEST_JOBS init:="$(nproc)" \
    validate:"__dybatpho_test_is_count \$OPTARG"
  dybatpho::opts::param "Test files per kcov invocation" CHUNK --chunk \
    env:DYBATPHO_TEST_CHUNK init:="5" \
    validate:"__dybatpho_test_is_count \$OPTARG"
  dybatpho::opts::param "Only run tests whose name matches" FILTER -f --filter \
    init:@empty

  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

dybatpho::generate_from_spec _spec "$@"
