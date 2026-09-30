#!/usr/bin/env bash
# @file docs.sh
# @brief Generate documentation of dybatpho
# @description
#   Writes `docs/<module>.md` from the shdoc comments in each source file.
#
#   `--check` generates into a temporary directory and compares instead of
#   writing, which is what CI needs: the committed documentation is generated,
#   so it can silently fall behind the source it describes. Locally the
#   `gen-doc` pre-commit hook rewrites the files and a dirty tree makes the
#   drift obvious; a pull request has no such signal without this flag.
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

# @description Write `docs/<module>.md` for every source.
# @noargs
function __dybatpho_doc_generate {
  local _src _module _written=0
  local doc_sources_output
  doc_sources_output=$(__dybatpho_doc_sources)
  while IFS= read -r _src || [[ -n "${_src}" ]]; do
    _module="$(basename "${_src}" .sh)"
    "${SH_DOCS}" "${_src}" \
      --output "${DYBATPHO_DIR}/docs/${_module}.md"
    _written=$((_written + 1))
  done < <(printf '%s' "${doc_sources_output}")
  ((_written > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: No source file to document"
}

# @description Compare the committed documents against freshly generated ones.
# @noargs
# @exitcode 0 Every document matches its source
# @exitcode 1 At least one document is stale
function __dybatpho_doc_check {
  local _generated _src _module _stale="" _checked=0
  dybatpho::create_temp_dir _generated "doc-check"

  local doc_sources_output
  doc_sources_output=$(__dybatpho_doc_sources)
  while IFS= read -r _src || [[ -n "${_src}" ]]; do
    _module="$(basename "${_src}" .sh)"
    "${SH_DOCS}" "${_src}" \
      --output "${_generated}/${_module}.md"
    _checked=$((_checked + 1))
    if ! diff -q "${DYBATPHO_DIR}/docs/${_module}.md" "${_generated}/${_module}.md" > /dev/null 2>&1; then
      _stale+="docs/${_module}.md is stale relative to $(basename "${_src}")"$'\n'
    fi
  done < <(printf '%s' "${doc_sources_output}")

  # A guard that compared nothing has not shown the documentation is current,
  # and reporting success for it is how this check quietly stopped checking.
  ((_checked > 0)) \
    || dybatpho::die "${FUNCNAME[0]}: No source file to check"

  if [[ -n "${_stale}" ]]; then
    dybatpho::error "Generated documentation is out of date; run scripts/docs.sh"
    printf '%s' "${_stale}" >&2
    return 1
  fi
  dybatpho::success "Generated documentation is up to date"
}

# @description Generate or check, depending on `--check`.
# @noargs
function __dybatpho_doc_run {
  dybatpho::require "gawk"
  [[ -x "${SH_DOCS}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: ${SH_DOCS} is missing; run \`git submodule update --init scripts/sh-docs\`"

  # shellcheck disable=SC2154 # set by the option spec of this script
  if dybatpho::is true "${CHECK}"; then
    __dybatpho_doc_check
    return
  fi
  __dybatpho_doc_generate
}

# @description CLI specification for this script.
# @noargs
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
