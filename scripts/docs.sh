#!/usr/bin/env bash
# @file docs.sh
# @brief Generate documentation of dybatpho
# @description
#   Writes `docs/<module>.md` from the shdoc comments in each source file.
#
#   `--check` compares instead of writing, which is what CI needs: the
#   committed documentation is generated, so it can silently fall behind the
#   source it describes. Locally the `gen-doc` pre-commit hook rewrites the
#   files and a dirty tree makes the drift obvious; a pull request has no such
#   signal without this flag. Both modes run `sh-docs --strict`, so a comment
#   it cannot document properly fails as well.
#
# @example
#   scripts/docs.sh                 # regenerate every document
#   scripts/docs.sh --check         # fail if a committed document is stale
#   scripts/docs.sh src/logging.sh  # regenerate one module
#
# @see
#   - `scripts/sh-docs/`
#   - `scripts/lint.sh`
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=init.sh
. "${SCRIPT_DIR}/../init.sh" --modules cli

dybatpho::register_common_handlers

# `sh-docs` is vendored as a submodule. Its defaults already describe this
# repository -- sources in `src/`, `init.sh` at the root, documents in `docs/`
# -- so no layout option is needed.
SH_DOCS="${SCRIPT_DIR}/sh-docs/sh-docs"

# This function declares no command line; it names `dybatpho::opts::setup`
# in a comment to explain how the array it reads was filled.
# dyshellint disable=BSG052
# @description Print the source files to document, one per line: the ones named
#   on the command line, or every documented source when none were.
#   `init.sh` ships public functions of its own, so it is documented alongside
#   the modules it loads.
# @noargs
# @stdout Paths of the source files
# @internal
function __dybatpho_doc_sources {
  # `dybatpho::opts::setup` collects the positional arguments into a Bash array,
  # which `dybatpho::generate_from_spec` always declares, empty or not.
  #
  # Reading it as a string instead is silent in both directions and wrong in
  # both: `"${DOC_ARGS}"` is element zero alone, so only the first source was
  # ever documented, and on an empty array it is unset, which `errexit` turns
  # into a failure inside the process substitution below -- where it stops the
  # loop without stopping the caller.
  # shellcheck disable=SC2154 # set by the option spec of this script
  if ((${#DOC_ARGS[@]})); then
    printf '%s\n' "${DOC_ARGS[@]}"
    return 0
  fi
  printf '%s\n' "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/src/"*.sh
}

# @description Write `docs/<module>.md` for every source, or compare instead.
#   One `sh-docs --output-dir` run covers every source, and `--check` turns it
#   into a comparison with the committed documents that prints a diff for a
#   stale one. `--strict` runs either way, so a misspelt tag, a public function
#   without a description or a positional argument without `@arg` fails here
#   rather than silently missing from the document.
# @arg $1 bool `true` to compare instead of writing
# @exitcode 0 Every document was written, or matches its source
# @exitcode 1 A document is stale, or `--strict` found a problem in a comment
# @internal
function __dybatpho_doc_sh_docs {
  local _compare
  dybatpho::expect_args _compare -- "$@"
  local -a _sources=() _args=(--strict --output-dir "${DYBATPHO_DIR}/docs")
  local doc_sources_output
  doc_sources_output=$(__dybatpho_doc_sources)
  [[ -z "${doc_sources_output}" ]] || mapfile -t _sources <<< "${doc_sources_output}"
  # A guard that documented or compared nothing has not shown anything, and
  # reporting success for it is how a check quietly stops checking.
  ((${#_sources[@]})) \
    || dybatpho::die "${FUNCNAME[0]}: No source file to document"
  [[ "${_compare}" == true ]] && _args+=(--check)

  if ! "${SH_DOCS}" "${_args[@]}" ${_sources[@]+"${_sources[@]}"}; then
    [[ "${_compare}" == true ]] \
      && dybatpho::error "Generated documentation is out of date or a comment is wrong; run scripts/docs.sh"
    return 1
  fi
  [[ "${_compare}" == true ]] && dybatpho::success "Generated documentation is up to date"
  return 0
}

# @description Generate or check, depending on `--check`.
# @noargs
# @internal
function __dybatpho_doc_run {
  dybatpho::require "gawk"
  [[ -x "${SH_DOCS}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: ${SH_DOCS} is missing; run \`git submodule update --init scripts/sh-docs\`"

  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${CHECK}"; then
    __dybatpho_doc_sh_docs true
    return
  fi
  __dybatpho_doc_sh_docs false
}

# @description CLI specification for this script.
# @noargs
# dyshellint disable=BSG052 # `dybatpho::generate_from_spec` adds `--help` to every spec, so the option already exists
function _spec {
  dybatpho::opts::setup \
    "Generate docs/<module>.md from the shdoc comments in each source file" \
    DOC_ARGS action:"__dybatpho_doc_run"

  dybatpho::opts::arg "Source files to document; defaults to all of them" \
    SOURCE required:false variadic:true

  dybatpho::opts::flag "Fail if a committed document is stale instead of writing" \
    CHECK --check on:true off:false init:="false"
}

dybatpho::generate_from_spec _spec "$@"
