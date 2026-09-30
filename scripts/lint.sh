#!/usr/bin/env bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one.
# dyshellint disable=BSG050
# @file lint.sh
# @brief Check the repository itself: shell syntax, dyshellint, changelog format
# @description
#   `scripts/test.sh` answers whether the library behaves; this script answers
#   whether the repository is in the shape `AGENT.md` says it must be. The rules
#   already existed as prose a contributor had to remember, which is how a
#   `.shellcheckrc` ended up in the repository without a single automated
#   ShellCheck run.
#
#   The style pass is `dyshellint`, the linter for the Bash coding style guide
#   this library follows. It is one command for three checks — the guide's own
#   rules (`BSG###`), ShellCheck (`SC####`) and shfmt (`FMT001`) — so a finding
#   in any of them is reported in one list, with the `.shellcheckrc` of the
#   repository still honoured. Calling ShellCheck directly here would leave the
#   guide's own rules unchecked, which is what let them drift.
#
#   Scripts are discovered the way Git sees them, so nothing has to be
#   registered by hand: every tracked file that either ends in `.sh` or opens
#   with a Bash shebang is checked. Vendored code under `test/lib/` is a set of
#   submodules, so `git ls-files` never descends into it and upstream's style is
#   never this repository's problem.
#
#   `.bats` files are deliberately excluded: `@test "name" {` is Bats syntax,
#   not Bash, and neither ShellCheck nor shfmt has a dialect for it.
#
#   Stages run in order and each reports everything it finds before the script
#   moves on, so one run lists the whole backlog instead of one item at a time.
#
# @example
#   scripts/lint.sh                # every stage
#   scripts/lint.sh --stage shell  # dyshellint and `bash -n` only
#   scripts/lint.sh --list         # print the discovered scripts and exit
#
# @see
#   - `test/conventions.bats`
#   - `.github/workflows/ci.yaml`
#   - `.shellcheckrc`
#   - https://github.com/dynamotn/dyshellint
# Every stage runs even after one fails, so each is called for its status
# and the failures are counted rather than fatal.
# shellcheck disable=SC2310
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules cli

dybatpho::register_common_handlers

# @description Print every tracked file that is a Bash script, one per line.
#   Extension alone is not enough — `scripts/` may hold extensionless helpers —
#   so a file with no `.sh` suffix is admitted on its shebang instead. A
#   `.bash` file is sourced rather than run, so it carries no shebang either
#   and has to be named: `test/test_helper.bash` went unchecked until it was.
# @noargs
# @stdout Repository-relative paths
function __dybatpho_lint_scripts {
  local file
  local git_output
  git_output=$(git -C "${DYBATPHO_DIR}" ls-files)
  while IFS= read -r file || [[ -n "${file}" ]]; do
    case "${file}" in
      *.sh | *.bash)
        printf '%s\n' "${file}"
        continue
        ;;
      *.bats) continue ;;
      *) ;;
    esac
    [[ -f "${file}" ]] || continue
    if IFS= read -r first < "${file}" && [[ "${first}" == '#!'*bash* ]]; then
      printf '%s\n' "${file}"
    fi
  done < <(printf '%s' "${git_output}")
}

# @description Parse every discovered script with `bash -n`.
# @noargs
# @exitcode 0 Every script parses
# @exitcode 1 At least one script has a syntax error
function __dybatpho_lint_syntax {
  local script failures=0
  local lint_scripts_output
  lint_scripts_output=$(__dybatpho_lint_scripts)
  while IFS= read -r script || [[ -n "${script}" ]]; do
    bash -n "${DYBATPHO_DIR}/${script}" || failures=$((failures + 1))
  done < <(printf '%s' "${lint_scripts_output}")

  if ((failures)); then
    dybatpho::error "${failures} script(s) failed to parse"
    return 1
  fi
  dybatpho::success "Shell syntax is valid"
}

# @description Run `dyshellint` over every discovered script: the rules of the
#   Bash coding style guide, ShellCheck and shfmt in a single pass.
#   The linter separates the two ways a run can end badly — `1` is the code
#   having findings, `2` is the linter itself unable to run, usually a missing
#   ShellCheck or shfmt — so a broken toolchain is not reported as a style
#   backlog.
# @noargs
# @exitcode 0 `dyshellint` reports nothing
# @exitcode 1 `dyshellint` reports at least one finding, or could not run
function __dybatpho_lint_dyshellint {
  dybatpho::require "dyshellint"

  local -a scripts=()
  mapfile -t scripts < <(__dybatpho_lint_scripts)
  if [[ "${#scripts[@]}" -eq 0 ]]; then
    dybatpho::warn "No scripts discovered to check"
    return 0
  fi

  local status=0
  (cd "${DYBATPHO_DIR}" && dyshellint "${scripts[@]}") || status=$?
  case "${status}" in
    0)
      dybatpho::success "dyshellint is clean over ${#scripts[@]} script(s)"
      return 0
      ;;
    1) dybatpho::error "dyshellint reported findings" ;;
    *) dybatpho::error "dyshellint could not run (exit ${status}); is shellcheck or shfmt missing?" ;;
  esac
  return 1
}

# @description Check `CHANGELOG.md` against the Keep a Changelog format the file
#   claims to follow: an `## [Unreleased]` section, released sections dated
#   `YYYY-MM-DD`, only the six defined change groups, and a link reference for
#   every version.
# @noargs
# @exitcode 0 The changelog is well formed
# @exitcode 1 The changelog has at least one format violation
function __dybatpho_lint_changelog {
  local changelog="${DYBATPHO_DIR}/CHANGELOG.md"
  local violations="" line version

  dybatpho::is file "${changelog}" || dybatpho::die "Missing CHANGELOG.md"

  grep -qE '^## \[Unreleased\]' "${changelog}" \
    || violations+="No '## [Unreleased]' section"$'\n'

  local grep_output
  grep_output=$(grep -E '^## ' "${changelog}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^##\ \[Unreleased\] ]] && continue
    [[ "${line}" =~ ^##\ \[[0-9]+\.[0-9]+\.[0-9]+\]\ -\ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
      || violations+="Malformed release heading: ${line}"$'\n'
  done < <(printf '%s' "${grep_output}")

  local grep_output
  grep_output=$(grep -E '^### ' "${changelog}")
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      '### Added' | '### Changed' | '### Deprecated') ;;
      '### Removed' | '### Fixed' | '### Security') ;;
      *) violations+="Unknown change group: ${line}"$'\n' ;;
    esac
  done < <(printf '%s' "${grep_output}")

  local reference
  local grep_output
  grep_output=$(grep -oE '^## \[[^]]+\]' "${changelog}" | sed 's/^## \[//; s/\]$//')
  while IFS= read -r version || [[ -n "${version}" ]]; do
    reference="$(grep -E "^\[${version}\]: " "${changelog}")" || {
      violations+="Version ${version} has no link reference at the bottom"$'\n'
      continue
    }
    # A reference that exists but is not a URL is worse than a missing one: it
    # renders as a dead link. `scripts/release.sh` builds these, so a bug there
    # lands here silently.
    [[ "${reference}" =~ ^\[[^]]+\]:\ https://[a-zA-Z0-9.-]+/[^[:space:]]+$ ]] \
      || violations+="Malformed link reference: ${reference}"$'\n'
  done < <(printf '%s' "${grep_output}")

  if [[ -n "${violations}" ]]; then
    dybatpho::error "CHANGELOG.md does not follow Keep a Changelog:"
    printf '%s' "${violations}" >&2
    return 1
  fi
  dybatpho::success "CHANGELOG.md follows Keep a Changelog"
}

# @description Verify the committed documentation still matches what
#   `scripts/docs.sh` generates from the sources.
# @noargs
# @exitcode 0 No drift
# @exitcode 1 At least one generated document is stale
function __dybatpho_lint_doc {
  "${SCRIPT_DIR}/docs.sh" --check
}

# @description Regenerate the single-file bundle and let its own smoke test run.
#   `scripts/bundle.sh` already parses its output and sources it in a pristine
#   shell; nothing ever invoked it, so those checks never protected anything.
# @noargs
# @exitcode 0 The bundle builds and loads
# @exitcode 1 The bundle is broken
function __dybatpho_lint_bundle {
  local output
  dybatpho::create_temp output ".sh" "bundle"
  DYBATPHO_FORCE=true "${SCRIPT_DIR}/bundle.sh" --modules all --output "${output}" > /dev/null
  dybatpho::success "Bundle builds and loads"
}

# @description Validator for `--stage`.
# @arg $1 string Value to check
function __dybatpho_lint_is_stage {
  dybatpho::opts::validate_choice "$1" "all,shell,changelog,doc,bundle" \
    || dybatpho::die "Unknown stage '$1'. Choose one of: all, shell, changelog, doc, bundle"
}

# @description Run the requested stages and summarise.
#   Every stage runs even after one fails, so a single invocation reports the
#   whole backlog rather than stopping at the first problem.
# @noargs
function __dybatpho_lint_run {
  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${LIST}"; then
    __dybatpho_lint_scripts
    return 0
  fi

  local failures=0
  # shellcheck disable=SC2154 # set by the option spec of this script
  case "${STAGE}" in
    all | shell)
      __dybatpho_lint_syntax || failures=$((failures + 1))
      __dybatpho_lint_dyshellint || failures=$((failures + 1))
      ;;&
    all | changelog)
      __dybatpho_lint_changelog || failures=$((failures + 1))
      ;;&
    all | doc)
      __dybatpho_lint_doc || failures=$((failures + 1))
      ;;&
    all | bundle)
      __dybatpho_lint_bundle || failures=$((failures + 1))
      ;;
    *) ;;
  esac

  ((failures)) && dybatpho::die "${failures} lint stage(s) failed"
  dybatpho::success "Repository lint passed"
}

# @description CLI specification for this script.
# @noargs
function _spec {
  dybatpho::opts::setup \
    "Check the repository's own shape: syntax, dyshellint, changelog, docs, bundle" \
    LINT_ARGS action:"__dybatpho_lint_run"

  dybatpho::opts::flag "Print the discovered scripts and exit" LIST --list \
    on:true off:false init:="false"
  dybatpho::opts::param "Run one stage only" STAGE --stage \
    init:="all" validate:"__dybatpho_lint_is_stage \$OPTARG"
}

dybatpho::generate_from_spec _spec "$@"
