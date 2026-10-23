setup() {
  load test_helper
}

# Nothing is exported by default, but a parent that called
# `dybatpho::export_functions` hands the library down. Drop any `dybatpho::`
# function first so that a child only sees what its own bootstrap loaded.
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
  assert_output "string os logging helpers process file secret array "
}

@test "sourcing without arguments leaves the optional modules out" {
  run_traced -0 init_sh "" 'dybatpho::module_loaded git || echo absent'
  assert_output "absent"
}

@test "sourcing turns on inherit_errexit where Bash has it" {
  ((BASH_VERSINFO[0] > 4 || BASH_VERSINFO[1] >= 4)) || skip "Bash 4.3 has no inherit_errexit"
  run_traced -0 init_sh "" 'shopt -q inherit_errexit && echo on'
  assert_output "on"
}

@test "a failing command stops the command substitution it runs in" {
  ((BASH_VERSINFO[0] > 4 || BASH_VERSINFO[1] >= 4)) || skip "Bash 4.3 has no inherit_errexit"
  run_traced '!' init_sh "" 'value="$(false; echo reached)"; echo "after ${value}"'
  refute_output --partial "reached"
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
  assert_output "string os logging helpers process file secret array semver "
}

@test "a module set can be requested through DYBATPHO_MODULES" {
  run_traced -0 init_sh_env "semver" "" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array semver "
}

@test "the command line module set wins over DYBATPHO_MODULES" {
  run_traced -0 init_sh_env "network" "--modules semver" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array semver "
}

@test "a module set accepts commas and repeated names" {
  run_traced -0 init_sh "--modules json,semver,json" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array json semver "
}

@test "the array helpers are core and need no module request" {
  # `doctor` walks the module graph with `dybatpho::array_toposort`, so the
  # graph helpers have to be there whatever a script asked for.
  run_traced -0 init_sh "" 'declare -F dybatpho::array_toposort dybatpho::array_closure > /dev/null && echo present'
  assert_output "present"
}

@test "the dependency map outlives a function that sourced init.sh" {
  # A plain `declare -A` in a sourced file is local to the function sourcing
  # it, so a later `dybatpho::load` resolved no dependency at all.
  local script="${BATS_TEST_TMPDIR}/in_function.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf 'bootstrap() { . %q; }\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'bootstrap' 'dybatpho::load forge' "$(loaded_line)"
  } > "${script}"
  run_traced -0 env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_output --partial "array network json git forge "
}

@test "the core selection loads the core modules only" {
  run_traced -0 init_sh "--modules core" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array "
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
  assert_output "string os logging helpers process file secret array text "

  run_traced -0 init_sh "--modules notification" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array network notification "

  # `testing` loads only what every assertion uses: the JSON and YAML
  # assertions ask for `json`, and a snapshot mismatch for `diff` to draw it.
  run_traced -0 init_sh "--modules testing" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array text testing "

  # `table` renders real CSV only when the script loaded `csv` itself, so it
  # does not bring the parser along.
  run_traced -0 init_sh "--modules table" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array text table "

  # `markdown` renders a table only when the script loaded `table` itself.
  run_traced -0 init_sh "--modules markdown" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array markdown "

  # `release` packages an artifact only when the script loaded `archive` itself.
  run_traced -0 init_sh "--modules release" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array semver git release "

  run_traced -0 init_sh "--modules diff" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array diff "

  # `csv` compares numbers through `math`, and asks for `json` only to write it.
  run_traced -0 init_sh "--modules csv" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array math csv "

  # `backup_diff` compares through `diff_dir` only when the script loaded `diff`.
  run_traced -0 init_sh "--modules backup" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array archive validate cli safety date backup "

  run_traced -0 init_sh "--modules ai" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array network json cache ai "

  # `cache` takes a lock only to serve stale entries, and asks for it then.
  run_traced -0 init_sh "--modules cache" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array cache "

  run_traced -0 init_sh "--modules agent" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array validate cli safety json agent "

  run_traced -0 init_sh "--modules tui" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array validate cli safety tui "

  # `metrics` loads nothing on its own: summaries ask for `math` and a push
  # asks for `network`, so counting and timing never pull in `curl`.
  run_traced -0 init_sh "--modules metrics" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array metrics "

  # `screen` calls nothing outside the core modules, so it must load on its own
  # rather than dragging the interactive helpers in behind it.
  run_traced -0 init_sh "--modules screen" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array screen "
}

@test "a dependency cycle loads every module once and terminates" {
  # The registry holds no cycle of its own any more -- the one between `safety`
  # and `archive` went with the edge `archive` never used -- so the test plants
  # one between two modules that are not loaded yet.
  run_traced -0 init_sh "--modules core" '__dybatpho_module_deps[semver]="git"
__dybatpho_module_deps[git]="semver"
dybatpho::load semver
'"$(loaded_line)"
  assert_output "string os logging helpers process file secret array git semver "
}

@test "safety and archive load without each other" {
  run_traced -0 init_sh "--modules safety" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array validate cli safety "

  run_traced -0 init_sh "--modules archive" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array archive "
}

@test "the shared validator is loaded ahead of the modules that check with it" {
  # `config` and `cli` no longer carry their own type checks, so a script that
  # asks for either of them has to end up with `validate` defined. The edge is
  # pinned here because a missing one does not fail at load time: it fails
  # later, on the first value anybody validates.
  run_traced -0 init_sh "--modules config" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array validate config "

  run_traced -0 init_sh "--modules cli" 'dybatpho::validate_is port 8080 && echo reachable'
  assert_output "reachable"

  # `cli` reads a `config:` binding only when the script loaded `config`
  # itself, so the validator is all it brings along.
  run_traced -0 init_sh "--modules cli" "$(loaded_line)"
  assert_output "string os logging helpers process file secret array validate cli "
}

@test "a dependency pulled in on demand stays usable" {
  run_traced -0 init_sh "--modules text" 'dybatpho::text_indent body'
  assert_output "  body"
}

@test "an unknown module set fails the bootstrap without ending the caller" {
  # The bootstrap returns rather than exits, so the sourcing script decides
  # what a failure means, and it fails before strict mode is turned on.
  local script="${BATS_TEST_TMPDIR}/unknown.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf 'before="$-"\n'
    printf '. %q --modules nonexistent || printf "returned %%s\\n" "$?"\n' "${DYBATPHO_DIR}/init.sh"
    printf '[[ "$-" == "${before}" ]] && echo options-untouched\n'
    printf 'echo reached\n'
  } > "${script}"
  run_traced -0 --separate-stderr env -u DYBATPHO_MODULES bash "${script}"
  assert_line --index 0 "returned 1"
  assert_line --index 1 "options-untouched"
  assert_line --index 2 "reached"
  assert_stderr --partial "unknown module 'nonexistent'"
  assert_stderr --partial "known modules are"
}

@test "an unknown module set stops a strict script that does not check" {
  local script="${BATS_TEST_TMPDIR}/unknown_strict.sh"
  printf 'set -e\n. %q --modules nonexistent\necho reached\n' "${DYBATPHO_DIR}/init.sh" > "${script}"
  run -1 env -u DYBATPHO_MODULES bash "${script}"
  assert_output --partial "unknown module 'nonexistent'"
  refute_output --partial "reached"
}

@test "executing init.sh directly is refused" {
  run_traced -1 --separate-stderr bash "${DYBATPHO_DIR}/init.sh"
  assert_stderr --partial "can't be executed directly"
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
  assert_output "string os logging helpers process file secret array text "
}

@test "dybatpho::load accepts several modules at once" {
  run_traced -0 init_sh "--modules core" "dybatpho::load json semver
$(loaded_line)"
  assert_output "string os logging helpers process file secret array json semver "
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
  # A child shell that sources `init.sh` has to source the module files again
  # instead of trusting the parent's module set.
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

@test "sourcing init.sh twice in one shell redeclares nothing read-only" {
  # A library constant declared `readonly` at the top of a module could not be
  # declared again, so a second source of init.sh -- or a script that sources
  # a helper which sources it too -- printed `readonly variable` for each one.
  local script="${BATS_TEST_TMPDIR}/twice.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf '. %q --modules all\n' "${DYBATPHO_DIR}/init.sh"
    printf '. %q --modules all\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' "dybatpho::load cache lock screen cli" "printf 'loaded twice\n'"
  } > "${script}"
  run --separate-stderr env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_output "loaded twice"
  refute_stderr --partial "readonly variable"
}

@test "a relative source path resolves the library whatever CDPATH holds" {
  # `cd` looks a relative directory up in `CDPATH` first, so a directory of the
  # same name there used to become `DYBATPHO_DIR`, and `cd` printed it too.
  local work="${BATS_TEST_TMPDIR}/work" decoy="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${work}/lib" "${decoy}/lib/dybatpho"
  ln -s "${DYBATPHO_DIR}" "${work}/lib/dybatpho"
  local script="${work}/use.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf '. lib/dybatpho/init.sh\n'
    printf 'printf "%%s\\n" "${DYBATPHO_DIR}"\n'
  } > "${script}"
  # A function rather than `bash -c`, for the reason `bootstrap_script` gives.
  run_from_work() { cd "${work}" && env -u DYBATPHO_MODULES CDPATH="${decoy}" bash use.sh; }
  run_traced -0 run_from_work
  assert_output "${work}/lib/dybatpho"
}

@test "a source path without a directory resolves to the working directory" {
  local script="${BATS_TEST_TMPDIR}/here.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf '. init.sh\n'
    printf 'printf "%%s\\n" "${DYBATPHO_DIR}"\n'
  } > "${script}"
  run_from_library() { cd "${DYBATPHO_DIR}" && env -u DYBATPHO_MODULES bash "${script}"; }
  run_traced -0 run_from_library
  assert_output "$(cd "${DYBATPHO_DIR}" && pwd)"
}

@test "nothing is exported to a child process by default" {
  # A child sees no dybatpho function, and the environment grows by a few
  # variables rather than by every function body: exporting them all made each
  # child several times slower and could overflow what `execve` accepts.
  local script="${BATS_TEST_TMPDIR}/default_export.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf 'before="$(env | wc -c)"\n'
    printf '. %q --modules all\n' "${DYBATPHO_DIR}/init.sh"
    printf 'after="$(env | wc -c)"\n'
    printf '%s\n' 'echo "growth $((after - before))"'
    printf '%s\n' "bash -c 'compgen -A function | grep -c dybatpho || true'"
    printf '%s\n' 'echo "bash_env ${BASH_ENV-unset}"'
  } > "${script}"
  run_traced -0 env -u DYBATPHO_MODULES -u DYBATPHO_EXPORT_FUNCTIONS -u DYBATPHO_EXPORT_MODULES \
    -u BASH_ENV bash "${script}"
  local growth="${lines[0]#growth }"
  ((growth < 4096)) || fail "the environment grew by ${growth} bytes"
  assert_line --index 1 "0"
  assert_line --index 2 "bash_env unset"
}

# Run a script that opts in to exporting, with a clean environment.
export_sh() {
  env -u DYBATPHO_MODULES -u DYBATPHO_EXPORT_MODULES -u DYBATPHO_EXPORT_BASH_ENV \
    bash "$(bootstrap_script "${1}" "${2}")"
}

@test "DYBATPHO_EXPORT_FUNCTIONS hands the whole library to a bash -c child" {
  # The module state and the internal helpers come along, not just the public
  # names: each of these failed, or answered wrongly, with exported functions.
  DYBATPHO_EXPORT_FUNCTIONS=true BASH_ENV="" run_traced -0 export_sh "--modules semver csv" \
    'bash -c "dybatpho::info hello 2>&1; dybatpho::semver_compare 1.2.0 1.10.0; printf \"name,size\\n\" | dybatpho::csv_header -"'
  assert_line --index 0 --partial "hello"
  assert_line --index 1 "-1"
  assert_line --index 2 "name"
  assert_line --index 3 "size"
}

@test "dybatpho::export_functions hands the library to a child and dybatpho::load re-exports" {
  BASH_ENV="" run_traced -0 export_sh "" 'bash -c "declare -F dybatpho::info || echo none"
dybatpho::export_functions
bash -c "declare -F __dybatpho_load_module"
dybatpho::load semver
bash -c "dybatpho::semver_compare 2.0.0 1.0.0; dybatpho::module_loaded semver && echo semver-loaded"'
  assert_line --index 0 "none"
  assert_line --index 1 "__dybatpho_load_module"
  assert_line --index 2 "1"
  assert_line --index 3 "semver-loaded"
}

@test "an exported library leaves the child's options and arguments alone" {
  local child="${BATS_TEST_TMPDIR}/child.sh"
  printf '%s\n' 'printf "%s|%s|%s\n" "$-" "$(shopt -p extglob)" "$*"' 'dybatpho::module_loaded semver && echo ok' \
    > "${child}"
  BASH_ENV="" run_traced -0 export_sh "--modules semver" "dybatpho::export_functions
bash $(printf '%q' "${child}") --modules nonexistent"
  # `--modules nonexistent` is the child's own argument, not a module request.
  assert_line --index 0 "hB|shopt -u extglob|--modules nonexistent"
  assert_line --index 1 "ok"
}

@test "an exported library still sources the BASH_ENV that was there before" {
  # Coverage tools and the caller's own hook live in `BASH_ENV` too.
  local hook="${BATS_TEST_TMPDIR}/previous_hook.sh"
  printf 'echo previous-hook\n' > "${hook}"
  local script
  script="$(bootstrap_script "" "dybatpho::export_functions
bash -c 'dybatpho::module_loaded string && echo library'")"
  # The parent is a non-interactive shell of its own, so it runs the hook first.
  BASH_ENV="${hook}" run_traced -0 env -u DYBATPHO_MODULES bash "${script}"
  assert_output "previous-hook
previous-hook
library"
}

@test "dybatpho::export_functions refuses a library path that BASH_ENV would expand" {
  local copy="${BATS_TEST_TMPDIR}/lib\$HOME"
  mkdir -p "${copy}/src"
  cp "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/VERSION" "${copy}/"
  cp "${DYBATPHO_DIR}/src/"*.sh "${copy}/src/"
  local script="${BATS_TEST_TMPDIR}/dollar.sh"
  printf '. %q\ndybatpho::export_functions\necho reached\n' "${copy}/init.sh" > "${script}"
  run -1 env -u DYBATPHO_MODULES -u BASH_ENV bash "${script}"
  assert_output --partial "Can't export through BASH_ENV"
  refute_output --partial "reached"
}

@test "sourcing leaves nullglob and globstar alone" {
  run_traced -0 init_sh "" 'shopt -q nullglob || echo nullglob-off
shopt -q globstar || echo globstar-off
shopt -q extglob && echo extglob-on
for f in /nonexistent-dir/*.none; do echo "literal ${f}"; done'
  assert_line --index 0 "nullglob-off"
  assert_line --index 1 "globstar-off"
  assert_line --index 2 "extglob-on"
  assert_line --index 3 "literal /nonexistent-dir/*.none"
}

@test "--no-strict leaves every set and shopt option of the caller as it was" {
  local script="${BATS_TEST_TMPDIR}/no_strict.sh"
  {
    printf '%s\n' "${PRISTINE}"
    printf 'shopt -s nullglob\n'
    printf 'before="$- $(set +o) $(shopt -p)"\n'
    printf '. %q --no-strict --modules semver\n' "${DYBATPHO_DIR}/init.sh"
    printf 'after="$- $(set +o) $(shopt -p)"\n'
    printf '[[ "${before}" == "${after}" ]] && echo untouched\n'
    printf 'dybatpho::module_loaded semver && echo semver\n'
    printf '. %q --modules json --no-strict\n' "${DYBATPHO_DIR}/init.sh"
    printf 'dybatpho::module_loaded json && echo json\n'
    printf '[[ "$-" != *e* ]] && echo still-no-errexit\n'
  } > "${script}"
  run_traced -0 env -u DYBATPHO_MODULES bash "${script}"
  assert_output "untouched
semver
json
still-no-errexit"
}

@test "the core modules work without strict mode" {
  # Neither errexit, nounset, pipefail, extglob nor nullglob: the library must
  # not lean on an option it no longer sets.
  run_traced -0 init_sh "--no-strict" 'set +euo pipefail; shopt -u extglob nullglob
[[ "$-" != *e* && "$-" != *u* ]] && echo plain-shell
dybatpho::trim "  padded  "
dybatpho::goos > /dev/null && echo goos
dybatpho::is int 42 && echo is-int
dybatpho::path_join a b
arr=(b a b); dybatpho::array_unique arr; echo "${arr[*]}"
dybatpho::secret_register TOKEN_VALUE_123; dybatpho::secret_mask "use TOKEN_VALUE_123"
dybatpho::create_temp tmp ".txt"; [[ -f "${tmp}" ]] && echo temp
dybatpho::info logged 2>&1 | grep -c logged
dybatpho::try out err -- dybatpho::die "caught" 2 || echo "try $?"
dybatpho::dry_run -- printf "%s\n" ran'
  assert_line --index 0 "plain-shell"
  assert_line --index 1 "padded"
  assert_line --index 2 "goos"
  assert_line --index 3 "is-int"
  assert_line --index 4 "a/b"
  assert_line --index 5 "b a"
  assert_line --index 6 --partial "use "
  refute_line --index 6 --partial "TOKEN_VALUE_123"
  assert_line --index 7 "temp"
  assert_line --index 8 "1"
  assert_line --index 9 "try 2"
  assert_line --index 10 "ran"
}

@test "every registered module has a stability tier" {
  local module tier bad=""
  for module in $(dybatpho::module_list all); do
    tier="${__dybatpho_module_tiers[${module}]-}"
    [[ "${tier}" == "stable" || "${tier}" == "experimental" ]] || bad="${bad} ${module}=${tier:-none}"
  done
  for module in "${!__dybatpho_module_tiers[@]}"; do
    __dybatpho_module_exists "${module}" || bad="${bad} unregistered:${module}"
  done
  assert_equal "${bad}" ""
}

@test "the core modules are stable" {
  local module
  for module in ${DYBATPHO_CORE_MODULES}; do
    assert_equal "${module}=$(dybatpho::module_tier "${module}")" "${module}=stable"
  done
}

@test "a stable module depends only on stable modules" {
  # A script that keeps to stable modules must not be broken by an experimental
  # one loaded underneath it, so no hard edge may lead from one to the other.
  local module dep bad=""
  for module in $(dybatpho::module_list stable); do
    for dep in ${__dybatpho_module_deps[${module}]-}; do
      [[ "${__dybatpho_module_tiers[${dep}]}" == "stable" ]] || bad="${bad} ${module}->${dep}"
    done
  done
  assert_equal "${bad}" ""
}

@test "dybatpho::module_list selects by tier" {
  local stable experimental
  stable="$(dybatpho::module_list stable | tr '\n' ' ')"
  experimental="$(dybatpho::module_list experimental | tr '\n' ' ')"
  assert_regex " ${stable}" " json "
  assert_regex " ${experimental}" " tui "
  refute_regex " ${stable}" " tui "
  # The two tiers split the registry between them.
  assert_equal "$(printf '%s\n' ${stable} ${experimental} | sort | tr '\n' ' ')" \
    "$(dybatpho::module_list all | sort | tr '\n' ' ')"
}

@test "dybatpho::module_tier names the tier of a module" {
  run_traced -0 dybatpho::module_tier json
  assert_output "stable"
  run_traced -0 dybatpho::module_tier screen
  assert_output "experimental"
}

@test "dybatpho::module_tier rejects an unknown module" {
  run -1 dybatpho::module_tier nosuch
  assert_output --partial "Unknown module 'nosuch'"
}

@test "every soft dependency names a registered module" {
  local module dep bad=""
  for module in "${!__dybatpho_module_soft_deps[@]}"; do
    __dybatpho_module_exists "${module}" || bad="${bad} ${module}"
    for dep in ${__dybatpho_module_soft_deps[${module}]}; do
      __dybatpho_module_exists "${dep}" || bad="${bad} ${module}~>${dep}"
    done
  done
  assert_equal "${bad}" ""
}

@test "every module asked for on demand is a recorded soft dependency, and back" {
  # The registry is what doctor and the bundle read, so a call site that loads
  # a module on demand without an entry there would be invisible to both.
  local file module dep found="" bad=""
  local site_re='(__dybatpho_helpers_need_module|__dybatpho_helpers_load_soft|__dybatpho_metrics_need) ([a-z]+) '
  for file in "${DYBATPHO_DIR}"/src/*.sh; do
    module="$(basename "${file}" .sh)"
    while IFS= read -r dep; do
      [[ -n "${dep}" ]] || continue
      found="${found} ${module}~>${dep}"
      [[ " ${__dybatpho_module_soft_deps[${module}]-} " == *" ${dep} "* ]] \
        || bad="${bad} unrecorded:${module}~>${dep}"
    done < <(grep -oE "${site_re}" "${file}" | awk '{print $2}' | sort -u)
  done
  for module in "${!__dybatpho_module_soft_deps[@]}"; do
    for dep in ${__dybatpho_module_soft_deps[${module}]}; do
      [[ "${found} " == *" ${module}~>${dep} "* ]] || bad="${bad} unused:${module}~>${dep}"
    done
  done
  assert_equal "${bad}" ""
}

@test "each soft dependency loads on demand in a shell that loaded only its module" {
  # One child per module with soft dependencies, loading that module alone and
  # asking for each soft dependency the way its call sites do. The module
  # arrives, and its public functions reach a grandchild shell.
  local module dep marker script
  for module in "${!__dybatpho_module_soft_deps[@]}"; do
    for dep in ${__dybatpho_module_soft_deps[${module}]}; do
      # `sed` quits at the first match itself: `| head` would end it with
      # SIGPIPE, which `pipefail` turns into a failure on a slow host.
      marker="$(sed -nE '/^function __dybatpho_/{s/^function (__dybatpho_[a-z_0-9]+) .*/\1/p;q;}' "${DYBATPHO_DIR}/src/${dep}.sh")"
      script="${BATS_TEST_TMPDIR}/soft-${module}-${dep}.sh"
      {
        printf '%s\n' "${PRISTINE}"
        printf '. %q --modules %s\n' "${DYBATPHO_DIR}/init.sh" "${module}"
        printf 'dybatpho::module_loaded %s && echo "already loaded"\n' "${dep}"
        printf '__dybatpho_helpers_need_module %s %s caller\n' "${dep}" "${marker}"
        printf 'dybatpho::module_loaded %s && echo "loaded on demand"\n' "${dep}"
      } > "${script}"
      run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
      assert_success
      refute_output --partial "already loaded"
      assert_output --partial "loaded on demand"
    done
  done
}

@test "a soft dependency loaded inside a command substitution lives only there" {
  run_traced -0 init_sh "--modules csv" 'out="$(dybatpho::csv_to_json $'"'"'a\n1'"'"')"
printf "%s\n" "${out}"
dybatpho::module_loaded json || echo "json not loaded here"'
  assert_line --index 0 '[{"a":"1"}]'
  assert_line --index 1 "json not loaded here"
}
