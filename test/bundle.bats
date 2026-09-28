setup() {
  load test_helper
  BUNDLE_SH="${DYBATPHO_DIR}/scripts/bundle.sh"
  OUTPUT="${BATS_TEST_TMPDIR}/dybatpho.bundle.sh"
}

# Source a generated bundle in a pristine shell. The bats process exports every
# `dybatpho::` function, so a child has to drop them first to prove the bundle
# defines what it claims to define.
use_bundle() {
  local script="${BATS_TEST_TMPDIR}/use.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q\n' "${OUTPUT}"
    printf '%s\n' "$1"
  } > "${script}"
  env -u DYBATPHO_DIR -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "${script}"
}

# The bats process exports every `dybatpho::` function and the generator is a
# dybatpho script of its own, so this also covers running one from a shell that
# already loaded the library.
bundle() {
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    "${BUNDLE_SH}" --output "${OUTPUT}" "$@"
}

@test "bundle.sh writes the core modules by default" {
  run -0 bundle
  assert_file_exist "${OUTPUT}"
  run -0 use_bundle 'dybatpho::module_list loaded | tr "\n" " "'
  assert_output "${DYBATPHO_CORE_MODULES} "
}

@test "bundle.sh resolves the dependencies of a requested module" {
  run -0 bundle --modules release
  run -0 use_bundle 'dybatpho::module_list loaded | tr "\n" " "'
  # `release` pulls in semver, git and archive, and archive pulls in safety.
  for module in semver git archive safety release; do
    assert_output --partial " ${module}"
  done
}

@test "a bundle needs no src directory beside it" {
  run -0 bundle --modules "logging semver"
  run -0 use_bundle 'dybatpho::semver_bump 1.2.3 minor'
  assert_output "1.3.0"
}

@test "a bundle reports the library version it was generated from" {
  run -0 bundle
  run -0 use_bundle 'dybatpho::version'
  assert_output "$(dybatpho::version)"
}

@test "a bundle refuses to be executed directly" {
  run -0 bundle
  run -1 bash "${OUTPUT}"
  assert_output --partial "can't be executed directly"
}

@test "dybatpho::load is a no-op for a module the bundle carries" {
  run -0 bundle --modules git
  run -0 use_bundle 'dybatpho::load git; echo loaded'
  assert_output "loaded"
}

@test "dybatpho::load names the regeneration command for an absent module" {
  run -0 bundle --modules git
  run -1 use_bundle 'dybatpho::load ai'
  assert_output --partial "Module 'ai' is not in this bundle"
  assert_output --partial "scripts/bundle.sh --modules"
}

@test "a bundle reports only what it carries as the registry" {
  run -0 bundle --modules git
  run -0 use_bundle 'dybatpho::module_list all | tr "\n" " "'
  assert_output --partial " git"
  refute_output --partial " ai"
}

@test "dybatpho::doctor inside a bundle checks the bundled modules" {
  run -0 bundle --modules "doctor git"
  run use_bundle 'dybatpho::doctor --all || true'
  assert_output --regexp 'git +git +required +ok'
}

@test "bundle.sh refuses to overwrite an existing bundle without --force" {
  run -0 bundle
  DYBATPHO_FORCE=false run -1 bundle
  assert_output --partial "already exists"
}

@test "bundle.sh overwrites an existing bundle when forced" {
  run -0 bundle
  DYBATPHO_FORCE=true run -0 bundle --modules semver
  run -0 use_bundle 'dybatpho::module_loaded semver && echo yes'
  assert_output "yes"
}

@test "bundle.sh writes nothing in dry-run mode" {
  DRY_RUN=true run -0 bundle
  assert_output --partial "would write"
  assert_file_not_exist "${OUTPUT}"
}

@test "bundle.sh rejects an unknown module" {
  run -1 bundle --modules nosuch
  assert_output --partial "nosuch"
  assert_file_not_exist "${OUTPUT}"
}

@test "bundle.sh keeps the module source verbatim" {
  run -0 bundle --modules semver
  # The bundled module is the library module, minus its shebang line.
  run -0 grep -c "^function dybatpho::semver_bump {" "${OUTPUT}"
  assert_output "1"
  run -0 grep -c '^#!/usr/bin/env bash' "${OUTPUT}"
  assert_output "1"
}

@test "introspection inside a bundle answers what it can and refuses the rest" {
  run -0 bundle --modules semver

  # The documentation travels with the code, so this is the part that still
  # works when there is no `src/` and no `docs/` to read.
  run -0 use_bundle 'dybatpho::describe semver_valid'
  assert_output --partial "Return success when the string is a valid semver"
  assert_output --partial '@arg $1 string Version string to validate'

  # A bundle holds every module in one file, so no function can be attributed
  # to a module. Naming the bundle file as the module would be a wrong answer
  # rather than a missing one.
  run ! use_bundle 'dybatpho::provides semver_valid'
  assert_output ""

  # The line is still exactly where the function is, inside the bundle.
  run -0 use_bundle 'dybatpho::provides --path semver_valid'
  assert_output --partial "${OUTPUT}:"

  # And an empty list would read as "that module exports nothing".
  run --separate-stderr ! use_bundle 'dybatpho::function_list semver'
  assert_stderr --partial "which is how a bundle looks"
}
