setup() {
  load test_helper
}

# The bats process exports every `dybatpho::` function, and a child shell
# inherits them all. Drop them first so that a child only sees what its own
# bootstrap loaded.
PRISTINE='while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'

# Write the child bootstrap to a real file rather than passing it to `bash -c`.
# A `-c` shell has an empty `BASH_SOURCE` array, and the coverage instrumentation
# that kcov injects through `BASH_ENV` expands `${BASH_SOURCE}` on every command.
# Once `init.sh` turns on `set -u` that expansion aborts the child shell, which
# made these tests fail only under `scripts/test.sh`. A file-backed script gives
# `BASH_SOURCE` a real value, which is also what `init.sh` requires of its
# callers.
bootstrap_script() {
  local script="${BATS_TEST_TMPDIR}/bootstrap.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf '. %q %s\n' "${DYBATPHO_DIR}/init.sh" "${1}"
    printf '%s\n' "${2}"
  } > "${script}"
  printf '%s' "${script}"
}

# Run a script in a pristine shell so that the module set of the current test
# process does not leak into the assertion.
init_sh() {
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES \
    bash "$(bootstrap_script "${1}" "${2}")"
}

# Same, with DYBATPHO_MODULES set in the environment instead of on the command
# line.
init_sh_env() {
  env -u DYBATPHO_LOADED_MODULES DYBATPHO_MODULES="${1}" \
    bash "$(bootstrap_script "${2}" "${3}")"
}

loaded_line() {
  printf 'dybatpho::module_list loaded | tr "\\n" " "'
}

@test "sourcing without arguments loads the core modules only" {
  run -0 init_sh "" "$(loaded_line)"
  assert_output "string logging helpers process file secret "
}

@test "sourcing without arguments leaves the optional modules out" {
  run -0 init_sh "" 'dybatpho::module_loaded git || echo absent'
  assert_output "absent"
}

@test "the all selection loads every module" {
  run -0 init_sh "--modules all" "$(loaded_line)"
  # `loaded_line` leaves a trailing space, so pad the front to make every module
  # name match the same way.
  output=" ${output}"
  local module
  for module in $(dybatpho::module_list all); do
    assert_output --partial " ${module} "
  done
}

@test "an explicit module set loads only that module and the core modules" {
  run -0 init_sh "--modules semver" "$(loaded_line)"
  assert_output "string logging helpers process file secret semver "
}

@test "a module set can be requested through DYBATPHO_MODULES" {
  run -0 init_sh_env "semver" "" "$(loaded_line)"
  assert_output "string logging helpers process file secret semver "
}

@test "the command line module set wins over DYBATPHO_MODULES" {
  run -0 init_sh_env "network" "--modules semver" "$(loaded_line)"
  assert_output "string logging helpers process file secret semver "
}

@test "a module set accepts commas and repeated names" {
  run -0 init_sh "--modules json,semver,json" "$(loaded_line)"
  assert_output "string logging helpers process file secret json semver "
}

@test "the core selection loads the core modules only" {
  run -0 init_sh "--modules core" "$(loaded_line)"
  assert_output "string logging helpers process file secret "
}

@test "the default and the core selection agree" {
  run -0 init_sh "--modules core" "$(loaded_line)"
  local explicit="${output}"
  run -0 init_sh "" "$(loaded_line)"
  assert_equal "${output}" "${explicit}"
}

@test "a module set excludes the modules that were not requested" {
  run -0 init_sh "--modules semver" \
    'declare -F dybatpho::curl_do > /dev/null && echo leaked || echo absent'
  assert_output "absent"
}

@test "requesting a module loads its dependencies first" {
  run -0 init_sh "--modules text" "$(loaded_line)"
  assert_output "string logging helpers process file secret table text "

  run -0 init_sh "--modules notification" "$(loaded_line)"
  assert_output "string logging helpers process file secret network notification "

  run -0 init_sh "--modules testing" "$(loaded_line)"
  assert_output "string logging helpers process file secret json network table text testing "

  run -0 init_sh "--modules ai" "$(loaded_line)"
  assert_output "string logging helpers process file secret network json ai "

  run -0 init_sh "--modules agent" "$(loaded_line)"
  assert_output "string logging helpers process file secret cli archive safety json agent "
}

@test "a dependency cycle loads every module once and terminates" {
  run -0 init_sh "--modules safety" "$(loaded_line)"
  assert_output "string logging helpers process file secret archive cli safety "

  run -0 init_sh "--modules archive" "$(loaded_line)"
  assert_output "string logging helpers process file secret cli safety archive "
}

@test "a dependency pulled in on demand stays usable" {
  run -0 init_sh "--modules text" 'dybatpho::text_indent body'
  assert_output "  body"
}

@test "an unknown module set stops the bootstrap" {
  run -1 init_sh "--modules nonexistent" 'echo reached'
  refute_output --partial "reached"
  assert_output --partial "unknown module 'nonexistent'"
  assert_output --partial "known modules are"
}

@test "dybatpho::load adds a module after the bootstrap" {
  run -0 init_sh "--modules core" "dybatpho::load json
printf '%s' '{\"a\":1}' | dybatpho::json_query - '.a'"
  assert_output "1"
}

@test "dybatpho::load resolves dependencies and is idempotent" {
  run -0 init_sh "--modules core" "dybatpho::load text
dybatpho::load text
$(loaded_line)"
  assert_output "string logging helpers process file secret table text "
}

@test "dybatpho::load accepts several modules at once" {
  run -0 init_sh "--modules core" "dybatpho::load json semver
$(loaded_line)"
  assert_output "string logging helpers process file secret json semver "
}

@test "dybatpho::load without arguments stops the script" {
  run -1 init_sh "--modules core" 'dybatpho::load
echo reached'
  refute_output --partial "reached"
  assert_output --partial "Expected at least one module name"
}

@test "dybatpho::load rejects an unknown module" {
  run -1 init_sh "--modules core" 'dybatpho::load nonexistent
echo reached'
  refute_output --partial "reached"
  assert_output --partial "unknown module 'nonexistent'"
}

@test "dybatpho::module_loaded reports the current module set" {
  run -0 init_sh "--modules semver" \
    'dybatpho::module_loaded semver && echo yes
dybatpho::module_loaded network || echo no'
  assert_line --index 0 "yes"
  assert_line --index 1 "no"
}

@test "dybatpho::module_loaded requires a module name" {
  run ! dybatpho::module_loaded
}

@test "dybatpho::module_list prints each selection" {
  assert_equal "$(dybatpho::module_list core | tr '\n' ' ')" "${DYBATPHO_CORE_MODULES} "
  assert_equal "$(dybatpho::module_list optional | tr '\n' ' ')" "${DYBATPHO_OPTIONAL_MODULES} "
  assert_equal "$(dybatpho::module_list all | wc -l)" "$(ls "${DYBATPHO_DIR}"/src/*.sh | wc -l)"
  assert_equal "$(dybatpho::module_list | tr '\n' ' ')" "$(dybatpho::module_list loaded | tr '\n' ' ')"
}

@test "dybatpho::module_list rejects an unknown selection" {
  run -1 init_sh "--modules core" 'dybatpho::module_list bogus
echo reached'
  refute_output --partial "reached"
  assert_output --partial "Unknown selection 'bogus'"
}

@test "the loaded module set is not inherited by a child shell" {
  # Internal `__` helpers are never exported, so a child shell that sources
  # `init.sh` has to source the module files again instead of trusting the
  # parent's module set.
  # The grandchild is a script file for the same reason as `bootstrap_script`:
  # a `bash -c` shell has no `BASH_SOURCE` for the coverage hook to expand.
  local child="${BATS_TEST_TMPDIR}/child.sh"
  printf '. %q --modules json\ndybatpho::info child\n' "${DYBATPHO_DIR}/init.sh" > "${child}"

  run -0 init_sh "--modules logging" \
    "export DYBATPHO_LOADED_MODULES
bash $(printf '%q' "${child}") 2>&1"
  assert_output --partial "child"
  refute_output --partial "command not found"
}

@test "every registered module has a file under src" {
  # The registry is maintained by hand while the file path is derived from the
  # module name, so a registered name with no matching file would otherwise be
  # reported as loaded without ever being sourced.
  run -0 init_sh "--modules core" \
    'for module in $(dybatpho::module_list all); do dybatpho::load "${module}"; done
dybatpho::module_list loaded | wc -l'
  assert_output "$(dybatpho::module_list all | wc -l)"
}

@test "a registered module with no file under src is reported" {
  run -1 init_sh "--modules core" \
    'DYBATPHO_OPTIONAL_MODULES="${DYBATPHO_OPTIONAL_MODULES} ghost"
dybatpho::load ghost
echo reached'
  refute_output --partial "reached"
  assert_output --partial "does not exist"
}
