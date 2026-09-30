# Enforces the repository contract from AGENT.md mechanically, so a module or a
# public function that ships without its spec, doc, example, test or namespace
# fails the suite instead of waiting for a reviewer to notice.
#
# Each test collects every violation before failing, so a contributor sees the
# whole list at once rather than fixing them one run at a time.

setup() {
  load test_helper
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

# @description Print every public `dybatpho::` function defined in a source file.
public_functions() {
  grep -oE '^function (dybatpho::[A-Za-z0-9_:]+)' "$1" | awk '{print $2}'
}

# @description Print every top-level function name defined in a source file.
all_functions() {
  grep -oE '^function [A-Za-z0-9_:]+' "$1" | awk '{print $2}'
}

# @description Fail with a heading followed by one violation per line.
fail_with() {
  local heading="$1" violations="$2"
  printf '%s\n\n%s\n' "${heading}" "${violations}" >&2
  return 1
}

# The documentation check is what keeps the committed `docs/` honest, and a
# guard that stops guarding is worse than no guard: it reports success either
# way. These two cover the ways it went quiet rather than the drift it reports,
# which the guard itself already covers when it runs.

@test "the documentation check reads its sources without tripping over an empty argument list" {
  # The positional arguments arrive as a Bash array. Read as a string, an empty
  # one is unset, `errexit` ended the source listing inside a process
  # substitution, and the check then compared nothing and called it clean.
  run_traced "${REPO_ROOT}/scripts/docs.sh" --check
  refute_output --partial "unbound variable"
  refute_output --partial "DOC_ARGS"
}

@test "the documentation check inspects every source it is given" {
  # Read as a string, the argument list was its own first element, so only the
  # first source was ever compared. A stale document anywhere after it passed.
  #
  # The stale source is a copy in this test's own directory, whose `docs/` file
  # therefore does not exist. Making a committed document stale in place would
  # dirty the shared repository for as long as the check runs, and the suite
  # runs its files in parallel: `test/examples.bats` compares the working tree
  # before and after every example, so it would fail on whichever example
  # happened to overlap this window.
  local stale_source="${BATS_TEST_TMPDIR}/zzz_unpublished.sh"
  cp "${REPO_ROOT}/src/semver.sh" "${stale_source}"

  run "${REPO_ROOT}/scripts/docs.sh" --check \
    "${REPO_ROOT}/src/os.sh" "${stale_source}"
  assert_failure
  # Naming the second source proves the first did not end the listing.
  assert_output --partial "docs/zzz_unpublished.md is stale"
}

@test "every module has a doc, a spec, a test file and an example" {
  local violations="" module
  for source in "${REPO_ROOT}"/src/*.sh; do
    module="$(basename "${source}" .sh)"
    [ -f "${REPO_ROOT}/docs/${module}.md" ] ||
      violations+="${module}: missing docs/${module}.md"$'\n'
    [ -f "${REPO_ROOT}/docs/spec/${module}.md" ] ||
      violations+="${module}: missing docs/spec/${module}.md"$'\n'
    [ -f "${REPO_ROOT}/test/${module}.bats" ] ||
      violations+="${module}: missing test/${module}.bats"$'\n'
    compgen -G "${REPO_ROOT}/example/${module}*.sh" > /dev/null ||
      violations+="${module}: missing example/${module}*.sh"$'\n'
  done
  [ -z "${violations}" ] ||
    fail_with "Modules missing a required artifact (AGENT.md 'Module scope'):" "${violations}"
}

@test "a script is executable and a sourced module is not" {
  # The split is deliberate and the tree already follows it: everything under
  # `example/` and `scripts/` is run, everything under `src/` and `init.sh` is
  # sourced. It drifts silently, though — `example/math_ops.sh` lost its bit
  # after a commit had just set it across every example — because nothing runs
  # an example by path, so nothing notices.
  #
  # The mode is read from the index rather than the filesystem: that is the one
  # every other checkout gets, and a umask can make a working tree disagree
  # with what was committed.
  local violations="" mode path
  while read -r mode _ _ path; do
    case "${path}" in
      example/*.sh | scripts/*.sh)
        [[ "${mode}" == "100755" ]] ||
          violations+="${path} is run directly but is not executable"$'\n'
        ;;
      src/*.sh | init.sh)
        [[ "${mode}" == "100644" ]] ||
          violations+="${path} is sourced, so it should not be executable"$'\n'
        ;;
    esac
  done < <(git -C "${REPO_ROOT}" ls-files -s)

  [ -z "${violations}" ] ||
    fail_with "Files whose executable bit does not match how they are used:" "${violations}"
}

@test "every module is registered in init.sh" {
  # The registry is read as the shell sees it, not grepped out of the source.
  # Matching the text meant the check answered to how the assignment happens to
  # be laid out: splitting the list over `+=` continuations so no line runs past
  # the length limit left the pattern matching only the first line, and every
  # module after it was reported missing from a registry that in fact held it.
  local violations="" module
  local registry=" ${DYBATPHO_CORE_MODULES} ${DYBATPHO_OPTIONAL_MODULES} "
  for source in "${REPO_ROOT}"/src/*.sh; do
    module="$(basename "${source}" .sh)"
    [[ "${registry}" == *" ${module} "* ]] ||
      violations+="${module}: not listed in DYBATPHO_CORE_MODULES or DYBATPHO_OPTIONAL_MODULES"$'\n'
  done
  [ -z "${violations}" ] ||
    fail_with "Modules absent from the init.sh registry:" "${violations}"
}

@test "every spec is listed in the spec index" {
  local index violations="" module
  index="$(cat "${REPO_ROOT}/docs/spec/README.md")"
  for spec in "${REPO_ROOT}"/docs/spec/*.md; do
    module="$(basename "${spec}" .md)"
    [ "${module}" = "README" ] && continue
    [[ "${index}" == *"${module}.md"* ]] ||
      violations+="${module}: docs/spec/${module}.md not listed in docs/spec/README.md"$'\n'
  done
  [ -z "${violations}" ] ||
    fail_with "Specs missing from the docs/spec/README.md index:" "${violations}"
}

@test "every public function is documented in its module doc" {
  local violations="" module doc
  for source in "${REPO_ROOT}"/src/*.sh; do
    module="$(basename "${source}" .sh)"
    doc="${REPO_ROOT}/docs/${module}.md"
    [ -f "${doc}" ] || continue
    while read -r fn; do
      [ -n "${fn}" ] || continue
      # Match the name followed by a non-name character so a shorter function
      # can't be satisfied by a longer one that merely starts with it.
      grep -qE "${fn}([^A-Za-z0-9_]|$)" "${doc}" ||
        violations+="${module}: ${fn} is not documented in docs/${module}.md"$'\n'
    done < <(public_functions "${source}")
  done
  [ -z "${violations}" ] ||
    fail_with "Public functions missing from their module documentation:" "${violations}"
}

@test "every public function is exercised by its module test file" {
  local violations="" module test_file
  for source in "${REPO_ROOT}"/src/*.sh; do
    module="$(basename "${source}" .sh)"
    test_file="${REPO_ROOT}/test/${module}.bats"
    [ -f "${test_file}" ] || continue
    while read -r fn; do
      [ -n "${fn}" ] || continue
      grep -qE "${fn}([^A-Za-z0-9_]|$)" "${test_file}" ||
        violations+="${module}: ${fn} is never named in test/${module}.bats"$'\n'
    done < <(public_functions "${source}")
  done
  [ -z "${violations}" ] ||
    fail_with "Public functions with no direct test (AGENT.md 'Completion checklist'):" "${violations}"
}

@test "every function is namespaced under dybatpho:: or __dybatpho_" {
  local violations="" module
  for source in "${REPO_ROOT}"/src/*.sh "${REPO_ROOT}/init.sh"; do
    module="$(basename "${source}" .sh)"
    while read -r fn; do
      [ -n "${fn}" ] || continue
      case "${fn}" in
        dybatpho::* | __dybatpho_*) ;;
        *)
          violations+="${module}: ${fn} must be named dybatpho::* or __dybatpho_*"$'\n'
          ;;
      esac
    done < <(all_functions "${source}")
  done
  [ -z "${violations}" ] ||
    fail_with "Functions that can collide with a caller's helpers (AGENT.md 'Bash conventions'):" "${violations}"
}
