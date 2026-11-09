setup() {
  load test_helper
  export DYBATPHO_SERVICE_MANAGER=""
  export DYBATPHO_SERVICE_STRICT=false
  export DYBATPHO_DRY_RUN=""
  export DRY_RUN=""
  # Paths the module probes, such as /run/systemd/system, resolve under here.
  export __DYBATPHO_SERVICE_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}"
  STUBS="${BATS_TEST_TMPDIR}/stubs"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "${STUBS}"
  : > "${CALLS}"
  # No real manager answers, whatever this machine runs; each test adds stubs.
  PATH="${STUBS}:$(_path_without_managers)"
}

# The PATH without any service manager tool, built once per file.
_path_without_managers() {
  local cache="${BATS_FILE_TMPDIR}/path-without-managers" tool path="${PATH}"
  if [[ ! -f "${cache}" ]]; then
    for tool in systemctl rc-service rc-update sv sv-enable sv-disable launchctl; do
      command -v "${tool}" > /dev/null || continue
      path="$(PATH="${path}" path_without "${tool}")"
    done
    printf '%s\n' "${path}" > "${cache}"
  fi
  cat "${cache}"
}

# A stub tool that records each call as one line in CALLS, prints the content
# of STUB_OUT_<tool> when set, and exits with STUB_EXIT_<tool> (default 0).
_stub() {
  local tool="$1" var="${1//-/_}"
  cat > "${STUBS}/${tool}" << EOF
#!/usr/bin/env bash
printf '%s\n' "${tool} \$*" >> '${CALLS}'
[[ -z "\${STUB_OUT_${var}-}" ]] || printf '%s\n' "\${STUB_OUT_${var}}"
exit "\${STUB_EXIT_${var}:-0}"
EOF
  chmod +x "${STUBS}/${tool}"
}

# Pretend to run on an OS, as `uname -s` reports it.
_os() {
  STUB_OUT_uname="$1"
  export STUB_OUT_uname
  _stub uname
}

@test "dybatpho::service_manager finds systemd when it booted the machine" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  run_traced -0 dybatpho::service_manager
  assert_output "systemd"
}

@test "dybatpho::service_manager picks OpenRC on a host that carries systemctl but booted OpenRC" {
  _os Linux
  _stub systemctl
  _stub rc-service
  run_traced -0 dybatpho::service_manager
  assert_output "openrc"
}

@test "dybatpho::service_manager finds runit on Termux and launchd on macOS" {
  _os Linux
  _stub sv-enable
  run_traced -0 dybatpho::service_manager
  assert_output "runit"
  _os Darwin
  _stub launchctl
  run_traced -0 dybatpho::service_manager
  assert_output "launchd"
}

@test "dybatpho::service_manager prints nothing and fails when no manager is found" {
  _os Linux
  _stub sv
  run_traced -1 dybatpho::service_manager
  assert_output ""
}

@test "dybatpho::service_manager honours DYBATPHO_SERVICE_MANAGER and refuses an unknown one" {
  _os Linux
  DYBATPHO_SERVICE_MANAGER=launchd run_traced -0 dybatpho::service_manager
  assert_output "launchd"
  DYBATPHO_SERVICE_MANAGER=upstart run -1 --separate-stderr dybatpho::service_manager
  assert_stderr --partial "Unknown service manager: upstart"
}

@test "dybatpho::service_manager_available reports the systemd user scope from show-environment" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  run_traced -0 dybatpho::service_manager_available --user
  run -0 cat "${CALLS}"
  assert_line "systemctl --user show-environment"
  STUB_EXIT_systemctl=1 run_traced -1 dybatpho::service_manager_available --user
}

@test "dybatpho::service_manager_available refuses the system scope offline or in a container" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  STUB_OUT_systemctl=running run_traced -0 dybatpho::service_manager_available
  STUB_OUT_systemctl=degraded STUB_EXIT_systemctl=1 run_traced -0 dybatpho::service_manager_available
  STUB_OUT_systemctl=offline STUB_EXIT_systemctl=1 run_traced -1 dybatpho::service_manager_available
  : > "${__DYBATPHO_SERVICE_ROOT}/.dockerenv"
  STUB_OUT_systemctl=running run_traced -1 dybatpho::service_manager_available
}

@test "dybatpho::service_manager_available probes the OpenRC user instance" {
  _os Linux
  _stub rc-service
  _stub rc-update
  run_traced -0 dybatpho::service_manager_available --user
  run -0 cat "${CALLS}"
  assert_line "rc-update --user show"
  STUB_EXIT_rc_update=1 run_traced -1 dybatpho::service_manager_available --user
}

@test "dybatpho::service_manager_available is false with no manager at all" {
  _os Linux
  run_traced -1 dybatpho::service_manager_available
  run_traced -1 dybatpho::service_manager_available --user
}
