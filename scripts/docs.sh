#!/usr/bin/env bash
# @file docs.sh
# @brief Generate documentation of dybatpho
# @description
#   Writes `docs/<module>.md` from the shdoc comments in each source file, and
#   from the same comments the files agents read: `llms.txt`, `llms-full.txt`
#   and `skills/dybatpho/references/modules.md`.
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
LLMS_AWK="${SCRIPT_DIR}/llms.awk"
# Where the skill's links point: it is read outside the repository.
DOC_REPO_URL="https://github.com/dynamotn/dybatpho/blob/main"

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

# @description Print how a script loads a module: `always` for `init` and the
#   core modules, otherwise the `--modules` argument that names it.
# @arg $1 string Module name
# @stdout How the module is loaded
# @internal
function __dybatpho_doc_llms_loads {
  local _module
  dybatpho::expect_args _module -- "$@"
  if [[ "${_module}" == init || " ${DYBATPHO_CORE_MODULES} " == *" ${_module} "* ]]; then
    printf 'always\n'
    return 0
  fi
  printf '\x60--modules %s\x60\n' "${_module}"
}

# @description Write the files agents read instead of the whole `docs/`:
#   `llms.txt` (one line per module), `llms-full.txt` (every public signature
#   with the first sentence of its description) and the module table of the
#   Agent Skill, all from the `@brief`, `@description` and `@arg` comments that
#   `scripts/llms.awk` reads out of the sources. Every source is read whatever
#   the command line named, because each file covers the whole library.
#
#   `llms.txt` and `llms-full.txt` link relative to the repository root, which
#   resolves both in a checkout and under raw.githubusercontent.com. The skill
#   is copied out of the repository when it is installed, so its table links
#   to GitHub instead.
# @arg $1 path Directory to write the three files under, at their repository paths
# @internal
function __dybatpho_doc_llms_write {
  local _dir
  dybatpho::expect_args _dir -- "$@"
  local records
  records=$(gawk -f "${LLMS_AWK}" "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/src/"*.sh) \
    || dybatpho::die "${FUNCNAME[0]}: Cannot read the source comments"
  [[ -n "${records}" ]] || dybatpho::die "${FUNCNAME[0]}: No module found in the sources"

  local index="" full="" table="" kind module text summary tier loads
  while IFS=$'\t' read -r kind module text summary; do
    if [[ "${kind}" == F ]]; then
      full+="- \`${text}\` — ${summary}"$'\n'
      continue
    fi
    tier="${__dybatpho_module_tiers[${module}]-stable}"
    loads="$(__dybatpho_doc_llms_loads "${module}")"
    index+="- [${module}](docs/${module}.md): ${text}"
    [[ "${tier}" == experimental ]] && index+=" (experimental)"
    index+=$'\n'
    full+=$'\n'"## ${module}"$'\n\n'"${text}. Loaded: ${loads}. Stability: ${tier}."
    full+=" Reference: [docs/${module}.md](docs/${module}.md)"$'\n\n'
    table+="| [${module}](${DOC_REPO_URL}/docs/${module}.md) | ${loads} | ${tier} | ${text//|/\\|} |"$'\n'
  done <<< "${records}"

  mkdir -p "${_dir}/skills/dybatpho/references"
  cat > "${_dir}/llms.txt" << EOF
# dybatpho

> A Bash 4.3+ library of \`dybatpho::*\` functions for writing robust shell
> scripts: strict mode, logging, CLI parsing from a declared spec, cleanup
> traps, temporary files, retries, JSON, networking and more, split into
> modules a script loads on demand.

- Source \`init.sh\` once, naming the modules the script needs:
  \`. dybatpho/init.sh --modules cli network\`. Without \`--modules\` only the
  core modules load: ${DYBATPHO_CORE_MODULES// /, }.
- Every public function is named \`dybatpho::<name>\`; a name starting with
  \`__dybatpho_\` is internal. Before writing a helper by hand, look for an
  existing function in [llms-full.txt](llms-full.txt).
- An experimental module may change in any minor release; the others keep
  their contract across minor releases.
- Links are relative to the repository root, so they resolve in a checkout and
  under https://raw.githubusercontent.com/dynamotn/dybatpho/main/.
- Generated by \`scripts/docs.sh\` from the source comments;
  \`scripts/docs.sh --check\` fails when it is stale.

## Modules

${index}
## Optional

- [llms-full.txt](llms-full.txt): Every public function's signature and one-line description, grouped by module
- [Agent Skill](skills/dybatpho/SKILL.md): How an agent writes a script on dybatpho
- [Migration guide](docs/MIGRATING.md): What each major version breaks and how to move a script
- [Specifications](docs/spec/README.md): The behaviour every module promises
EOF
  cat > "${_dir}/llms-full.txt" << EOF
# dybatpho function reference

> Every public \`dybatpho::\` function, grouped by module, with its signature
> and the first sentence of its description. A signature lists argument types
> in order: \`<type>\` is required, \`[type]\` optional, \`type...\` repeats,
> and \`[options]\` takes flags first. The full reference of a module is
> docs/<module>.md.

Generated by \`scripts/docs.sh\` from the source comments; see
[llms.txt](llms.txt) for how to load the library.
${full%$'\n'}
EOF
  cat > "${_dir}/skills/dybatpho/references/modules.md" << EOF
# dybatpho modules

Generated by \`scripts/docs.sh\` from each module's \`@brief\`; do not edit it by hand.

Load a module with \`. dybatpho/init.sh --modules <name>...\`. An experimental
module may change in any minor release. The core modules are always loaded:
${DYBATPHO_CORE_MODULES// /, }.

| Module | Loaded | Stability | What it covers |
| --- | --- | --- | --- |
${table%$'\n'}
EOF
}

# @description Compare the committed agent files with freshly generated ones,
#   printing a diff for each stale one.
# @noargs
# @exitcode 0 Every file matches its sources
# @exitcode 1 A file is stale or missing
# @internal
function __dybatpho_doc_llms_check {
  local fresh file stale=0
  dybatpho::create_temp_dir fresh llms
  __dybatpho_doc_llms_write "${fresh}"
  for file in llms.txt llms-full.txt skills/dybatpho/references/modules.md; do
    diff -u --label "${file}" --label "${file} (generated)" \
      "${DYBATPHO_DIR}/${file}" "${fresh}/${file}" 2> /dev/null \
      || {
        dybatpho::error "${file} is missing or out of date; run scripts/docs.sh"
        stale=1
      }
  done
  ((stale == 0)) || return 1
  dybatpho::success "llms.txt, llms-full.txt and the skill's module table are up to date"
}

# @description Generate or check, depending on `--check`.
# @noargs
# @internal
function __dybatpho_doc_run {
  dybatpho::require "gawk"
  [[ -x "${SH_DOCS}" ]] \
    || dybatpho::die "${FUNCNAME[0]}: ${SH_DOCS} is missing; run \`git submodule update --init scripts/sh-docs\`"

  if dybatpho::is true "${CHECK}"; then
    # Both run, so one stale file does not hide another.
    local failed=0
    # shellcheck disable=SC2310 # a stale document has to reach the next check
    __dybatpho_doc_sh_docs true || failed=1
    # shellcheck disable=SC2310 # the status is collected and returned below
    __dybatpho_doc_llms_check || failed=1
    return "${failed}"
  fi
  __dybatpho_doc_sh_docs false
  __dybatpho_doc_llms_write "${DYBATPHO_DIR}"
}

# @description CLI specification for this script.
# @noargs
# dyshellint disable=BSG052 # `dybatpho::generate_from_spec` adds `--help` to every spec, so the option already exists
function _spec {
  dybatpho::opts::setup \
    "Generate docs/<module>.md, llms.txt and llms-full.txt from the shdoc comments" \
    DOC_ARGS action:"__dybatpho_doc_run"

  dybatpho::opts::arg "Source files to document; defaults to all of them" \
    SOURCE required:false variadic:true

  dybatpho::opts::flag "Fail if a committed document is stale instead of writing" \
    CHECK --check on:true off:false init:="false"
}

dybatpho::generate_from_spec _spec "$@"
