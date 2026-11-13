setup() {
  load test_helper
  # A copy of the parts `scripts/docs.sh` reads, so a file made stale here
  # never dirties the shared tree that other test files compare against.
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}/scripts" "${REPO}/skills/dybatpho"
  cp -R "${DYBATPHO_DIR}/src" "${DYBATPHO_DIR}/docs" "${REPO}/"
  cp "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}/VERSION" "${REPO}/"
  cp "${DYBATPHO_DIR}/scripts/docs.sh" "${DYBATPHO_DIR}/scripts/llms.awk" "${REPO}/scripts/"
  ln -s "${DYBATPHO_DIR}/scripts/sh-docs" "${REPO}/scripts/sh-docs"
}

# Run the copied `docs.sh` the way a user would.
repo_docs() {
  env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${REPO}/scripts/docs.sh" "$@"
}

@test "docs.sh writes llms.txt, llms-full.txt and the skill's module table, and --check accepts them" {
  if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)); then
    skip "sh-docs needs Bash 4.4 or newer; this is Bash ${BASH_VERSION}"
  fi
  run --separate-stderr repo_docs
  assert_success
  assert_file_exists "${REPO}/llms.txt"
  assert_file_exists "${REPO}/llms-full.txt"
  assert_file_exists "${REPO}/skills/dybatpho/references/modules.md"
  run grep -F -- '- [semver](docs/semver.md): ' "${REPO}/llms.txt"
  assert_success
  run grep -F -- '- `dybatpho::semver_compare <string> <string>` — ' "${REPO}/llms-full.txt"
  assert_success

  run --separate-stderr repo_docs --check
  assert_success
  assert_output --partial "skill's module table are up to date"
}

@test "docs.sh --check fails on a stale llms.txt and names it" {
  if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)); then
    skip "sh-docs needs Bash 4.4 or newer; this is Bash ${BASH_VERSION}"
  fi
  repo_docs > /dev/null 2>&1
  printf -- '- [gone](docs/gone.md): A module that was removed\n' >> "${REPO}/llms.txt"
  run --separate-stderr repo_docs --check
  assert_failure
  assert_stderr --partial "llms.txt is missing or out of date"
  refute_stderr --partial "llms-full.txt is missing"
  assert_output --partial "-- [gone](docs/gone.md)"
}

@test "docs.sh --check fails when a new public function is missing from llms-full.txt" {
  if ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)); then
    skip "sh-docs needs Bash 4.4 or newer; this is Bash ${BASH_VERSION}"
  fi
  repo_docs > /dev/null 2>&1
  cat >> "${REPO}/src/semver.sh" << 'EOF'

#######################################
# @description Do nothing, loudly. A second sentence.
# @arg $1 string Anything
#######################################
function dybatpho::semver_noop {
  :
}
EOF
  run --separate-stderr repo_docs --check
  assert_failure
  assert_stderr --partial "llms-full.txt is missing or out of date"
  assert_output --partial '+- `dybatpho::semver_noop <string>` — Do nothing, loudly.'
}

@test "llms.awk keeps public functions only and builds their signatures" {
  local source="${BATS_TEST_TMPDIR}/demo.sh"
  cat > "${source}" << 'EOF'
# @file demo.sh
# @brief A demo module
#######################################
# @description Fetch a thing, e.g. a file. It is
#   fetched once.
# @option --force Fetch again
# @arg $1 string Name
# @arg $2 number? Timeout
# @arg $3 string [default: x] Mode
# @arg $@ string Extra words
#######################################
function dybatpho::demo_fetch {
  :
}

#######################################
# @description Hidden helper.
# @internal
#######################################
function dybatpho::demo_hidden {
  :
}

# @description Private by name.
function __dybatpho_demo_private {
  :
}
EOF
  run gawk -f "${DYBATPHO_DIR}/scripts/llms.awk" "${source}"
  assert_success
  assert_output "$(printf '%s\t%s\t%s\n' M demo 'A demo module'
    printf '%s\t%s\t%s\t%s' F demo \
      'dybatpho::demo_fetch [options] <string> [number] [string] <string...>' \
      'Fetch a thing, e.g. a file.')"
}

@test "every dybatpho:: name in llms.txt and the skill is a real function" {
  local name violations=""
  while read -r name; do
    # `dybatpho::opts::*` names a namespace, not a function.
    [[ "${name}" == *:: ]] && continue
    grep -qE "^function ${name} " "${DYBATPHO_DIR}/init.sh" "${DYBATPHO_DIR}"/src/*.sh \
      || violations+="${name}"$'\n'
  done < <(grep -rhoE 'dybatpho::[A-Za-z0-9_:]+' \
    "${DYBATPHO_DIR}/llms.txt" "${DYBATPHO_DIR}/skills" | sort -u)
  [[ -z "${violations}" ]] || {
    printf 'Names that no source defines:\n%s' "${violations}" >&2
    return 1
  }
}
