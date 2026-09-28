setup() {
  load test_helper
  # The report reads PATH, so every test decides for itself what is installed.
  DOCTOR_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${DOCTOR_BIN}"
  ORIGINAL_PATH="${PATH}"
}

teardown() {
  PATH="${ORIGINAL_PATH}"
}

# Put a fake command on a PATH that holds nothing else, so "installed" means
# exactly what the test says it means.
fake_command() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${DOCTOR_BIN}/$1"
  # `only_fakes` may already have narrowed PATH down to the fake directory,
  # which is exactly the directory `chmod` is not in.
  PATH="${ORIGINAL_PATH}" chmod +x "${DOCTOR_BIN}/$1"
}

only_fakes() {
  PATH="${DOCTOR_BIN}"
}

# A fake that answers any version probe with the given text, so that a test can
# decide what version the host appears to have.
#
# The shebang is an absolute `/bin/sh` rather than `/usr/bin/env bash`, because
# `only_fakes` narrows PATH down to the fake directory: `env` would find no
# `bash` there, the fake would never run, and every version would read as
# undetectable no matter what the test set up.
fake_versioned_command() {
  printf '#!/bin/sh\necho %q\n' "$2" > "${DOCTOR_BIN}/$1"
  PATH="${ORIGINAL_PATH}" chmod +x "${DOCTOR_BIN}/$1"
}

@test "dybatpho::doctor_requirements lists required dependencies" {
  run -0 dybatpho::doctor_requirements archive required
  assert_output "tar"
}

@test "dybatpho::doctor_requirements lists what the forge module needs" {
  # `forge` reaches the API with curl and reads the remote with git, so a
  # missing one of those is a required failure rather than a partial module.
  run -0 dybatpho::doctor_requirements forge required
  assert_line --index 0 "curl"
  assert_line --index 1 "git"
}

@test "dybatpho::doctor_requirements lists what the screen module needs" {
  # Without `stty` there is no raw mode, so a keystroke only reaches a
  # full-screen application once Return is pressed: the module cannot work at
  # all rather than working partially.
  run -0 dybatpho::doctor_requirements screen required
  assert_output "stty"
}

@test "dybatpho::doctor_requirements lists optional dependencies" {
  run -0 dybatpho::doctor_requirements json optional
  assert_output "jq"
}

@test "dybatpho::doctor_requirements lists the host probes of the os module" {
  run -0 dybatpho::doctor_requirements os optional
  assert_line --index 0 "hostname"
  assert_line --index 1 "nproc|sysctl|getconf"
  assert_line --index 2 "tput"
}

@test "dybatpho::doctor_requirements defaults to every kind" {
  run -0 dybatpho::doctor_requirements json
  assert_line --index 0 "yq>=4"
  assert_line --index 1 "jq"
}

@test "dybatpho::doctor_requirements prints nothing for a module without dependencies" {
  run -0 dybatpho::doctor_requirements string
  assert_output ""
}

@test "dybatpho::doctor_requirements rejects an unknown module" {
  run -1 dybatpho::doctor_requirements nosuch
  assert_output --partial "Unknown module 'nosuch'"
}

@test "dybatpho::doctor_requirements rejects an unknown kind" {
  run -1 dybatpho::doctor_requirements json sometimes
  assert_output --partial "Unknown kind 'sometimes'"
}

@test "dybatpho::doctor_bash_supported accepts the running shell" {
  run -0 dybatpho::doctor_bash_supported
}

@test "dybatpho::doctor reports the version, the bash version and the modules" {
  run -0 dybatpho::doctor --modules string
  assert_line --index 0 --partial "dybatpho $(dybatpho::version)"
  assert_output --partial "minimum 4.3"
  assert_output --partial "modules  string"
}

@test "dybatpho::doctor says so when a module set needs nothing external" {
  run -0 dybatpho::doctor --modules "string array"
  assert_output --partial "No external dependency is needed"
}

@test "dybatpho::doctor marks an installed dependency ok with its path" {
  only_fakes
  fake_command curl
  run -0 dybatpho::doctor --modules network
  assert_output --partial "curl"
  assert_output --partial "ok (${DOCTOR_BIN}/curl)"
}

@test "dybatpho::doctor fails when a required dependency is missing" {
  only_fakes
  run -1 dybatpho::doctor --modules network
  assert_output --partial "Missing required: curl"
}

@test "dybatpho::doctor succeeds when only optional dependencies are missing" {
  only_fakes
  fake_command curl
  run -0 dybatpho::doctor --modules network
  assert_output --partial "Optional, some functions are unavailable:"
  assert_output --partial "No required dependency is missing."
}

@test "dybatpho::doctor accepts any alternative of an any-of dependency" {
  only_fakes
  fake_command shasum
  run -0 dybatpho::doctor --modules file
  assert_output --partial "sha256sum|shasum|openssl"
  assert_output --partial "ok (${DOCTOR_BIN}/shasum)"
}

@test "dybatpho::doctor reports an any-of dependency missing only when every alternative is" {
  only_fakes
  run -0 dybatpho::doctor --modules file
  assert_output --partial "sha256sum|shasum|openssl"
  assert_output --partial "missing"
}

@test "dybatpho::doctor accepts a comma separated module list" {
  run -0 dybatpho::doctor --modules "string,array"
  assert_output --partial "modules  string array"
}

@test "dybatpho::doctor covers the registry with --all" {
  run dybatpho::doctor --all
  assert_output --partial "archive"
  assert_output --partial "git"
}

@test "dybatpho::doctor defaults to the loaded modules" {
  run dybatpho::doctor
  assert_output --partial "modules  ${DYBATPHO_LOADED_MODULES}"
}

@test "dybatpho::doctor --quiet prints nothing and reports through the exit code" {
  only_fakes
  run -1 dybatpho::doctor --modules network --quiet
  assert_output ""
  fake_command curl
  run -0 dybatpho::doctor --modules network --quiet
  assert_output ""
}

@test "dybatpho::doctor --json prints one object with every dependency" {
  only_fakes
  fake_command curl
  fake_command yq
  run -0 dybatpho::doctor --modules "network,json" --json
  assert_output --partial '"version":"'
  assert_output --partial '"bash":{"version":'
  assert_output --partial '"modules":["network","json"]'
  assert_output --partial '{"module":"network","dependency":"curl","kind":"required","status":"ok"'
  assert_output --partial '"ok":true'
}

@test "dybatpho::doctor --json reports ok false when a required dependency is missing" {
  only_fakes
  run -1 dybatpho::doctor --modules network --json
  assert_output --partial '"status":"missing"'
  assert_output --partial '"ok":false'
}

@test "dybatpho::doctor --json output parses as JSON" {
  if ! dybatpho::is command jq; then
    skip "jq is not installed"
  fi
  run -0 dybatpho::doctor --modules "string array" --json
  printf '%s' "${output}" | jq -e '.bash.ok == true' > /dev/null
}

@test "dybatpho::doctor rejects an unknown module" {
  run -1 dybatpho::doctor --modules nosuch
  assert_output --partial "Unknown module 'nosuch'"
}

@test "dybatpho::doctor rejects an unknown option" {
  run -1 dybatpho::doctor --nope
  assert_output --partial "Unknown option '--nope'"
}

@test "dybatpho::doctor rejects --modules without a value" {
  run -1 dybatpho::doctor --modules
  assert_output --partial "--modules expects a module list"
}

@test "dybatpho::doctor marks a dependency ok and names the version when it satisfies the constraint" {
  only_fakes
  fake_versioned_command yq "yq (https://github.com/mikefarah/yq/) version v4.53.3"
  run -0 dybatpho::doctor --modules json
  assert_output --partial "yq>=4"
  assert_output --partial "ok (4.53.3, ${DOCTOR_BIN}/yq)"
  assert_output --partial "No required dependency is missing."
}

@test "dybatpho::doctor fails a required dependency that is installed but too old" {
  only_fakes
  fake_versioned_command yq "yq version 3.4.3"
  run -1 dybatpho::doctor --modules json
  assert_output --partial "outdated (3.4.3,"
  assert_output --partial "Required, too old: yq>=4 (found 3.4.3)"
  refute_output --partial "No required dependency is missing."
}

@test "dybatpho::doctor reports a version it cannot read without failing on it" {
  only_fakes
  # Installed, but silent on every probe: the report may not claim that this is
  # the wrong version, only that it could not tell.
  fake_command yq
  run -0 dybatpho::doctor --modules json
  assert_output --partial "unknown"
  assert_output --partial "Installed, version could not be read: yq>=4"
  refute_output --partial "Required, too old"
}

@test "dybatpho::doctor does not run a dependency that carries no constraint" {
  only_fakes
  # `curl` has no constraint, so the report has no reason to execute it. A fake
  # that fails the test if run proves the report stayed a report.
  printf '#!/bin/sh\necho ran > %q\n' "${BATS_TEST_TMPDIR}/ran" \
    > "${DOCTOR_BIN}/curl"
  PATH="${ORIGINAL_PATH}" chmod +x "${DOCTOR_BIN}/curl"
  run -0 dybatpho::doctor --modules network
  assert_output --partial "ok (${DOCTOR_BIN}/curl)"
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
}

@test "dybatpho::doctor prefers an alternative that satisfies its constraint" {
  only_fakes
  DYBATPHO_DOCTOR_REQUIRED[string]="oldtool>=2|newtool>=2"
  fake_versioned_command oldtool "oldtool 1.0.0"
  fake_versioned_command newtool "newtool 2.5.0"
  run -0 dybatpho::doctor --modules string
  assert_output --partial "ok (2.5.0, ${DOCTOR_BIN}/newtool)"
  unset 'DYBATPHO_DOCTOR_REQUIRED[string]'
}

@test "dybatpho::doctor reports outdated rather than missing when one alternative is merely old" {
  only_fakes
  DYBATPHO_DOCTOR_REQUIRED[string]="oldtool>=2|newtool>=2"
  fake_versioned_command oldtool "oldtool 1.0.0"
  run -1 dybatpho::doctor --modules string
  assert_output --partial "outdated (1.0.0,"
  unset 'DYBATPHO_DOCTOR_REQUIRED[string]'
}

@test "dybatpho::doctor --json carries the detected version" {
  only_fakes
  fake_versioned_command yq "yq version v4.53.3"
  run -0 dybatpho::doctor --modules json --json
  assert_output --partial '"dependency":"yq>=4"'
  assert_output --partial '"status":"ok"'
  assert_output --partial '"version":"4.53.3"'
}

@test "dybatpho::doctor --json reports an outdated required dependency as not ok" {
  only_fakes
  fake_versioned_command yq "yq version 3.4.3"
  run -1 dybatpho::doctor --modules json --json
  assert_output --partial '"status":"outdated"'
  assert_output --partial '"version":"3.4.3"'
  assert_output --partial '"ok":false'
}

@test "dybatpho::doctor keeps an outdated optional dependency out of the exit code" {
  only_fakes
  DYBATPHO_DOCTOR_OPTIONAL[string]="oldtool>=2"
  fake_versioned_command oldtool "oldtool 1.0.0"
  run -0 dybatpho::doctor --modules string
  assert_output --partial "Optional, too old: oldtool>=2 (found 1.0.0)"
  unset 'DYBATPHO_DOCTOR_OPTIONAL[string]'
}
