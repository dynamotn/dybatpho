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
  run_traced -0 init_sh "" "$(loaded_line)"
  assert_output "string os logging helpers process file secret "
}

@test "sourcing without arguments leaves the optional modules out" {
  run_traced -0 init_sh "" 'dybatpho::module_loaded git || echo absent'
  assert_output "absent"
}

@test "the all selection loads every module" {
  run_traced -0 init_sh "--modules all" "$(loaded_line)"
  # `loaded_line` leaves a trailing space, so pad the front to make every module
  # name match the same way.
  output=" ${output}"
  local module
  for module in $(dybatpho::module_list all); do
    assert_output --partial " ${module} "
  done
}

@test "an explicit module set loads only that module and the core modules" {
  run_traced -0 init_sh "--modules semver" "$(loaded_line)"
  assert_output "string os logging helpers process file secret semver "
}

@test "a module set can be requested through DYBATPHO_MODULES" {
  run_traced -0 init_sh_env "semver" "" "$(loaded_line)"
  assert_output "string os logging helpers process file secret semver "
}

@test "the command line module set wins over DYBATPHO_MODULES" {
  run_traced -0 init_sh_env "network" "--modules semver" "$(loaded_line)"
  assert_output "string os logging helpers process file secret semver "
}

@test "a module set accepts commas and repeated names" {
  run_traced -0 init_sh "--modules json,semver,json" "$(loaded_line)"
  assert_output "string os logging helpers process file secret json semver "
}

@test "the core selection loads the core modules only" {
  run_traced -0 init_sh "--modules core" "$(loaded_line)"
  assert_output "string os logging helpers process file secret "
}

@test "the default and the core selection agree" {
  run_traced -0 init_sh "--modules core" "$(loaded_line)"
  local explicit="${output}"
  run_traced -0 init_sh "" "$(loaded_line)"
  assert_equal "${output}" "${explicit}"
}

@test "a module set excludes the modules that were not requested" {
  run_traced -0 init_sh "--modules semver" \
    'declare -F dybatpho::curl_do > /dev/null && echo leaked || echo absent'
  assert_output "absent"
}

@test "requesting a module loads its dependencies first" {
  # `text` aligns columns only when the script loaded `table` itself.
  run_traced -0 init_sh "--modules text" "$(loaded_line)"
  assert_output "string os logging helpers process file secret text "

  run_traced -0 init_sh "--modules notification" "$(loaded_line)"
  assert_output "string os logging helpers process file secret network validate notification "

  # `testing` loads only what every assertion uses: the JSON and YAML
  # assertions ask for `json`, and a snapshot mismatch for `diff` to draw it.
  run_traced -0 init_sh "--modules testing" "$(loaded_line)"
  assert_output "string os logging helpers process file secret text testing "

  # `table` renders real CSV only when the script loaded `csv` itself, so it
  # does not bring the parser along.
  run_traced -0 init_sh "--modules table" "$(loaded_line)"
  assert_output "string os logging helpers process file secret text table "

  # `markdown` renders a table only when the script loaded `table` itself.
  run_traced -0 init_sh "--modules markdown" "$(loaded_line)"
  assert_output "string os logging helpers process file secret markdown "

  run_traced -0 init_sh "--modules diff" "$(loaded_line)"
  assert_output "string os logging helpers process file secret diff "

  # `csv` compares numbers through `math`, and asks for `json` only to write it.
  run_traced -0 init_sh "--modules csv" "$(loaded_line)"
  assert_output "string os logging helpers process file secret math csv "

  # `backup_diff` compares two snapshots through `diff_dir`.
  run_traced -0 init_sh "--modules backup" "$(loaded_line)"
  assert_output "string os logging helpers process file secret validate config cli safety archive date diff backup "

  run_traced -0 init_sh "--modules ai" "$(loaded_line)"
  assert_output "string os logging helpers process file secret network json lock cache ai "

  # `cache` guards its background refresh with a lock.
  run_traced -0 init_sh "--modules cache" "$(loaded_line)"
  assert_output "string os logging helpers process file secret lock cache "

  run_traced -0 init_sh "--modules agent" "$(loaded_line)"
  assert_output "string os logging helpers process file secret validate config cli archive safety json agent "

  run_traced -0 init_sh "--modules tui" "$(loaded_line)"
  assert_output "string os logging helpers process file secret validate config cli archive safety tui "

  # `metrics` loads nothing on its own: summaries ask for `math` and a push
  # asks for `network`, so counting and timing never pull in `curl`.
  run_traced -0 init_sh "--modules metrics" "$(loaded_line)"
  assert_output "string os logging helpers process file secret metrics "

  # `screen` calls nothing outside the core modules, so it must load on its own
  # rather than dragging the interactive helpers in behind it.
  run_traced -0 init_sh "--modules screen" "$(loaded_line)"
  assert_output "string os logging helpers process file secret screen "
}

@test "a dependency cycle loads every module once and terminates" {
  run_traced -0 init_sh "--modules safety" "$(loaded_line)"
  assert_output "string os logging helpers process file secret archive validate config cli safety "

  run_traced -0 init_sh "--modules archive" "$(loaded_line)"
  assert_output "string os logging helpers process file secret validate config cli safety archive "
}

@test "the shared validator is loaded ahead of the modules that check with it" {
  # `config` and `cli` no longer carry their own type checks, so a script that
  # asks for either of them has to end up with `validate` defined. The edge is
  # pinned here because a missing one does not fail at load time: it fails
  # later, on the first value anybody validates.
  run_traced -0 init_sh "--modules config" "$(loaded_line)"
  assert_output "string os logging helpers process file secret validate config "

  run_traced -0 init_sh "--modules cli" 'dybatpho::validate_is port 8080 && echo reachable'
  assert_output "reachable"
}

@test "a dependency pulled in on demand stays usable" {
  run_traced -0 init_sh "--modules text" 'dybatpho::text_indent body'
  assert_output "  body"
}

@test "an unknown module set stops the bootstrap" {
  run -1 init_sh "--modules nonexistent" 'echo reached'
  refute_output --partial "reached"
  assert_output --partial "unknown module 'nonexistent'"
  assert_output --partial "known modules are"
}

@test "dybatpho::load adds a module after the bootstrap" {
  run_traced -0 init_sh "--modules core" "dybatpho::load json
printf '%s' '{\"a\":1}' | dybatpho::json_query - '.a'"
  assert_output "1"
}

@test "dybatpho::load resolves dependencies and is idempotent" {
  run_traced -0 init_sh "--modules core" "dybatpho::load text
dybatpho::load text
$(loaded_line)"
  assert_output "string os logging helpers process file secret text "
}

@test "dybatpho::load accepts several modules at once" {
  run_traced -0 init_sh "--modules core" "dybatpho::load json semver
$(loaded_line)"
  assert_output "string os logging helpers process file secret json semver "
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
  run_traced -0 init_sh "--modules semver" \
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
  assert_equal "$(dybatpho::module_list all | wc -l | tr -d ' ')" "$(ls "${DYBATPHO_DIR}"/src/*.sh | wc -l | tr -d ' ')"
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

  run_traced -0 init_sh "--modules logging" \
    "export DYBATPHO_LOADED_MODULES
bash $(printf '%q' "${child}") 2>&1"
  assert_output --partial "child"
  refute_output --partial "command not found"
}

@test "every registered module has a file under src" {
  # The registry is maintained by hand while the file path is derived from the
  # module name, so a registered name with no matching file would otherwise be
  # reported as loaded without ever being sourced.
  run_traced -0 init_sh "--modules core" \
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

@test "dybatpho::version reports the stamped release version" {
  local stamped
  stamped="$(head -n 1 "${DYBATPHO_DIR}/VERSION")"
  run_traced -0 init_sh "" 'dybatpho::version'
  # The commit rides along as build metadata, so the release version is the
  # start of the answer rather than the whole of it.
  assert_output --regexp "^${stamped}([+]|$)"
}

@test "dybatpho::version names the commit the library is at" {
  local commit
  commit="$(git -C "${DYBATPHO_DIR}" rev-parse --short HEAD)"
  run_traced -0 init_sh "" 'dybatpho::version'
  assert_output --partial "+${commit}"
}

@test "dybatpho::version marks a dirty working tree" {
  # Only meaningful while the tree has uncommitted changes; a clean checkout
  # reports the commit without the marker, which is the other half of FR-018.
  run_traced -0 init_sh "" 'dybatpho::version'
  if git -C "${DYBATPHO_DIR}" diff --quiet HEAD; then
    refute_output --partial ".dirty"
  else
    assert_output --partial ".dirty"
  fi
}

@test "dybatpho::version reports a version without a leading v" {
  run_traced -0 init_sh "" 'dybatpho::version'
  refute_output --regexp '^v'
  assert_output --regexp '^[0-9]'
}

@test "dybatpho::version honors a version set in the environment" {
  run_traced -0 env DYBATPHO_VERSION=9.9.9-test bash "$(bootstrap_script "" 'dybatpho::version')"
  assert_output "9.9.9-test"
}

@test "dybatpho::version caches its answer" {
  run_traced -0 init_sh "" 'dybatpho::version > /dev/null
printf "%s\n" "${DYBATPHO_VERSION}"'
  assert_output "$(dybatpho::version)"
}

@test "dybatpho::version ignores the commits of a project it is vendored into" {
  # A copy inside another repository sits in that repository's working tree,
  # whose commits say nothing about which dybatpho is installed.
  local host="${BATS_TEST_TMPDIR}/host"
  mkdir -p "${host}/vendor/src"
  cp "${DYBATPHO_DIR}/init.sh" "${host}/vendor/init.sh"
  cp "${DYBATPHO_DIR}/VERSION" "${host}/vendor/VERSION"
  cp "${DYBATPHO_DIR}/src/"*.sh "${host}/vendor/src/"
  git -C "${host}" init -q .
  git -C "${host}" add -A
  git -C "${host}" -c user.email=t@example.com -c user.name=test commit -qm vendored
  local script="${BATS_TEST_TMPDIR}/vendored.sh"
  printf '. %q\ndybatpho::version\n' "${host}/vendor/init.sh" > "${script}"
  run_traced -0 env -u DYBATPHO_VERSION -u DYBATPHO_MODULES bash "${script}"
  assert_output "$(head -n 1 "${DYBATPHO_DIR}/VERSION")"
}

@test "dybatpho::version falls back to git describe without a VERSION file" {
  # A checkout that has not stamped a VERSION file still answers, so the
  # bundle header and `dybatpho::doctor` never print an empty version.
  local copy="${BATS_TEST_TMPDIR}/copy"
  mkdir -p "${copy}/src"
  cp "${DYBATPHO_DIR}/init.sh" "${copy}/init.sh"
  cp "${DYBATPHO_DIR}/src/"*.sh "${copy}/src/"
  local script="${BATS_TEST_TMPDIR}/nofile.sh"
  printf '. %q\ndybatpho::version\n' "${copy}/init.sh" > "${script}"
  run_traced -0 env -u DYBATPHO_VERSION -u DYBATPHO_MODULES bash "${script}"
  # The copy lives outside any repository, so `git describe` has nothing to say
  # either, and the documented last resort applies.
  assert_output --regexp '^(unknown|[0-9a-zA-Z._-]+)$'
}

@test "the doctor module is registered" {
  run_traced -0 init_sh "--modules doctor" 'dybatpho::module_loaded doctor && echo present'
  assert_output "present"
}
