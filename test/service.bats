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

# Pretend to run on an OS, as `uname -s` reports it. Unlike the manager stubs it
# records nothing, so CALLS holds only what was asked of the manager.
_os() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "${STUBS}/uname"
  chmod +x "${STUBS}/uname"
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

# Assert the commands `service_command` prints for foo, one per argument.
# System actions are elevated with `sudo`, whoever runs the test.
_commands() {
  local manager="$1" action="$2" scope="$3" expected
  shift 3
  local -a flag=()
  [[ "${scope}" != user ]] || flag=(--user)
  dybatpho::privilege_needed() { return 0; }
  DYBATPHO_PRIVILEGE_COMMAND=sudo DYBATPHO_SERVICE_MANAGER="${manager}" \
    run_traced -0 dybatpho::service_command "${action}" foo ${flag[@]+"${flag[@]}"}
  printf -v expected '%s\n' "$@"
  assert_output "${expected%$'\n'}"
}

@test "dybatpho::service_command prints the systemd commands of every action" {
  _commands systemd enable system "sudo -- systemctl enable --now foo"
  _commands systemd enable user "systemctl --user enable --now foo"
  _commands systemd disable system "sudo -- systemctl disable --now foo"
  _commands systemd start system "sudo -- systemctl start foo"
  _commands systemd stop user "systemctl --user stop foo"
  _commands systemd restart system "sudo -- systemctl restart foo"
  _commands systemd is-active system "systemctl is-active foo"
  _commands systemd is-enabled user "systemctl --user is-enabled foo"
}

@test "dybatpho::service_command prints the OpenRC commands of every action" {
  _commands openrc enable system "sudo -- rc-update add foo default" "sudo -- rc-service foo start"
  _commands openrc enable user "rc-update --user add foo default" "rc-service --user foo start"
  _commands openrc disable system "sudo -- rc-service foo stop" "sudo -- rc-update del foo default"
  _commands openrc start user "rc-service --user foo start"
  _commands openrc stop system "sudo -- rc-service foo stop"
  _commands openrc restart system "sudo -- rc-service foo restart"
  _commands openrc is-active system "rc-service foo status"
  _commands openrc is-enabled user "rc-update --user show default"
}

@test "dybatpho::service_command prints the runit commands, never elevated" {
  PREFIX="/data/usr"
  _commands runit enable system "sv-enable foo" "sv up foo"
  _commands runit enable user "sv-enable foo" "sv up foo"
  _commands runit disable system "sv down foo" "sv-disable foo"
  _commands runit start system "sv up foo"
  _commands runit stop system "sv down foo"
  _commands runit restart system "sv restart foo"
  _commands runit is-active system "sv status foo"
  _commands runit is-enabled system 'test \! -e /data/usr/var/service/foo/down'
}

@test "dybatpho::service_command prints the launchd commands in the right domain" {
  local uid
  uid="$(id -u)"
  _commands launchd enable user "launchctl enable gui/${uid}/foo" "launchctl kickstart gui/${uid}/foo"
  _commands launchd enable system "sudo -- launchctl enable system/foo" "sudo -- launchctl kickstart system/foo"
  _commands launchd disable user "launchctl disable gui/${uid}/foo" "launchctl bootout gui/${uid}/foo"
  _commands launchd start user "launchctl kickstart gui/${uid}/foo"
  _commands launchd stop user "launchctl bootout gui/${uid}/foo"
  _commands launchd restart system "sudo -- launchctl kickstart -k system/foo"
  _commands launchd is-active user "launchctl print gui/${uid}/foo"
  _commands launchd is-enabled user "launchctl print-disabled gui/${uid}"
}

@test "dybatpho::service_command keeps a .service suffix and drops a .plist one" {
  dybatpho::privilege_needed() { return 1; }
  DYBATPHO_SERVICE_MANAGER=systemd run_traced -0 dybatpho::service_command start foo.service
  assert_output "systemctl start foo.service"
  DYBATPHO_SERVICE_MANAGER=launchd run_traced -0 dybatpho::service_command start dev.example.foo.plist
  assert_output "launchctl kickstart system/dev.example.foo"
}

@test "dybatpho::service_command refuses an unknown action, a missing name and a path" {
  DYBATPHO_SERVICE_MANAGER=systemd run -1 --separate-stderr dybatpho::service_command reboot foo
  assert_stderr --partial "Unknown action: reboot"
  DYBATPHO_SERVICE_MANAGER=systemd run -1 --separate-stderr dybatpho::service_command start
  assert_stderr --partial "Expected a service name"
  DYBATPHO_SERVICE_MANAGER=systemd run -1 --separate-stderr dybatpho::service_command start ../foo
  assert_stderr --partial "Invalid service name: ../foo"
}

@test "dybatpho::service_enable elevates a system action and not a user one" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  STUB_OUT_systemctl=running
  export STUB_OUT_systemctl
  dybatpho::privilege_run() { printf 'ELEVATED %s\n' "${*:2}" >> "${CALLS}"; }
  run_traced -0 dybatpho::service_enable foo
  run_traced -0 dybatpho::service_enable foo --user
  run -0 cat "${CALLS}"
  assert_line "ELEVATED systemctl enable --now foo"
  assert_line "systemctl --user enable --now foo"
  refute_line "ELEVATED systemctl --user enable --now foo"
}

@test "dybatpho::service_enable on OpenRC stops at the first command that fails" {
  _os Linux
  _stub rc-service
  _stub rc-update
  # Only `add` fails: the user scope probe, `rc-update --user show`, succeeds.
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' \"rc-update \$*\" >> '${CALLS}'" \
    '[[ "$2" != add ]] || exit 3' > "${STUBS}/rc-update"
  run_traced -3 dybatpho::service_enable foo --user
  run -0 cat "${CALLS}"
  assert_line "rc-update --user add foo default"
  refute_line "rc-service --user foo start"
}

@test "DYBATPHO_DRY_RUN prints an action and runs nothing, but a question still runs" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  DYBATPHO_DRY_RUN=true run_traced -0 dybatpho::service_restart foo --user
  assert_output --partial "systemctl --user restart foo"
  run -0 cat "${CALLS}"
  refute_line "systemctl --user restart foo"
  DYBATPHO_DRY_RUN=true run_traced -0 dybatpho::service_is_active foo --user
  run -0 cat "${CALLS}"
  assert_line "systemctl --user is-active foo"
}

@test "an action warns and skips where no manager can act, and fails when strict" {
  _os Linux
  run_traced -0 --separate-stderr dybatpho::service_enable foo
  assert_stderr --partial "No service manager can act on the system scope here; skipping enable foo"
  DYBATPHO_SERVICE_STRICT=true run_traced -1 --separate-stderr dybatpho::service_enable foo
  run_traced -1 --separate-stderr dybatpho::service_is_active foo
  assert_stderr ""
}

@test "dybatpho::service_is_active reads a running launchd job and an anchored runit status" {
  local uid
  uid="$(id -u)"
  _os Darwin
  _stub launchctl
  STUB_OUT_launchctl=$'gui/'"${uid}"$'/foo = {\n\tstate = running\n\tpid = 42\n}' \
    run_traced -0 dybatpho::service_is_active foo --user
  STUB_OUT_launchctl=$'gui/'"${uid}"$'/foo = {\n\tstate = not running\n}' \
    run_traced -1 dybatpho::service_is_active foo --user
  _os Linux
  rm -f "${STUBS}/launchctl"
  _stub sv-enable
  _stub sv
  STUB_OUT_sv="run: foo: (pid 12) 9s; run: log: (pid 13) 9s" run_traced -0 dybatpho::service_is_active foo
  STUB_OUT_sv="down: foo: 5s, normally up; run: log: (pid 12) 9s" run_traced -1 dybatpho::service_is_active foo
  STUB_OUT_sv="fail: foo: unable to change to service directory" run_traced -1 dybatpho::service_is_active foo
}

@test "dybatpho::service_is_enabled reads OpenRC, runit and both launchd spellings" {
  _os Linux
  _stub rc-service
  _stub rc-update
  STUB_OUT_rc_update=$'            foo | default\n            bar | default' \
    run_traced -0 dybatpho::service_is_enabled foo --user
  STUB_OUT_rc_update=$'         foobar | default' run_traced -1 dybatpho::service_is_enabled foo --user
  rm -f "${STUBS}/rc-service" "${STUBS}/rc-update"
  _stub sv-enable
  export PREFIX="${BATS_TEST_TMPDIR}/usr"
  mkdir -p "${PREFIX}/var/service/foo"
  run_traced -0 dybatpho::service_is_enabled foo
  : > "${PREFIX}/var/service/foo/down"
  run_traced -1 dybatpho::service_is_enabled foo
  run_traced -1 dybatpho::service_is_enabled missing
  _os Darwin
  _stub launchctl
  STUB_OUT_launchctl=$'disabled services = {\n\t"foo" => disabled\n\t"bar" => enabled\n}' \
    run_traced -1 dybatpho::service_is_enabled foo --user
  STUB_OUT_launchctl=$'disabled services = {\n\t"foo" => true\n}' run_traced -1 dybatpho::service_is_enabled foo --user
  STUB_OUT_launchctl=$'disabled services = {\n\t"bar" => disabled\n}' run_traced -0 dybatpho::service_is_enabled foo --user
}

@test "dybatpho::service_disable, service_start and service_stop run their table's commands" {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  run_traced -0 dybatpho::service_start foo --user
  run_traced -0 dybatpho::service_stop foo --user
  run_traced -0 dybatpho::service_disable foo --user
  run -0 cat "${CALLS}"
  assert_line "systemctl --user start foo"
  assert_line "systemctl --user stop foo"
  assert_line "systemctl --user disable --now foo"
}

# A systemd host whose user manager answers, with a home of the test's own.
_systemd_user() {
  _os Linux
  _stub systemctl
  mkdir -p "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
}

_unit() {
  local file="${BATS_TEST_TMPDIR}/$1"
  printf '[Service]\nExecStart=/bin/true %s\n' "${2:-one}" > "${file}"
  printf '%s\n' "${file}"
}

@test "dybatpho::service_install puts a systemd user unit in place, reloads, then enables it" {
  _systemd_user
  local unit
  unit="$(_unit foo.service)"
  run_traced -0 dybatpho::service_install "${unit}" --user
  assert_file_exists "${XDG_CONFIG_HOME}/systemd/user/foo.service"
  run -0 grep -v 'show-environment\|is-active' "${CALLS}"
  assert_output $'systemctl --user daemon-reload\nsystemctl --user enable --now foo.service'
}

@test "dybatpho::service_install of an unchanged unit writes and reloads nothing, but still enables" {
  _systemd_user
  local unit
  unit="$(_unit foo.service)"
  dybatpho::service_install "${unit}" --user
  : > "${CALLS}"
  run_traced -0 dybatpho::service_install "${unit}" --user
  run -0 cat "${CALLS}"
  refute_line "systemctl --user daemon-reload"
  assert_line "systemctl --user enable --now foo.service"
}

@test "dybatpho::service_install of a changed unit reloads and restarts a running service" {
  _systemd_user
  dybatpho::service_install "$(_unit foo.service one)" --user
  : > "${CALLS}"
  run_traced -0 dybatpho::service_install "$(_unit foo.service two)" --user
  run -0 cat "${CALLS}"
  assert_line "systemctl --user daemon-reload"
  assert_line "systemctl --user restart foo.service"
  assert_equal "$(tail -1 "${XDG_CONFIG_HOME}/systemd/user/foo.service")" "ExecStart=/bin/true two"
}

@test "dybatpho::service_install loads a launchd agent: enable, bootout ignoring failure, bootstrap" {
  _os Darwin
  _stub launchctl
  # bootout fails, as it does when the agent is not loaded yet.
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' \"launchctl \$*\" >> '${CALLS}'" \
    '[[ "$1" != bootout ]] || exit 3' > "${STUBS}/launchctl"
  export HOME="${BATS_TEST_TMPDIR}/home"
  local uid plist dest
  uid="$(id -u)"
  plist="$(_unit dev.example.foo.plist)"
  dest="${HOME}/Library/LaunchAgents/dev.example.foo.plist"
  run_traced -0 dybatpho::service_install "${plist}" --user
  assert_file_exists "${dest}"
  run -0 grep -v "print gui/${uid}\$" "${CALLS}"
  assert_line --index 0 "launchctl enable gui/${uid}/dev.example.foo"
  assert_line --index 1 "launchctl bootout gui/${uid} ${dest}"
  assert_line --index 2 "launchctl bootstrap gui/${uid} ${dest}"
}

@test "dybatpho::service_install elevates a system unit, root-owned on launchd" {
  dybatpho::privilege_run() { printf 'ELEVATED %s\n' "${*:2}" >> "${CALLS}"; }
  _systemd_user
  STUB_OUT_systemctl=running
  export STUB_OUT_systemctl
  local unit
  unit="$(_unit foo.service)"
  run_traced -0 dybatpho::service_install "${unit}"
  run -0 cat "${CALLS}"
  assert_line "ELEVATED install -m 644 -- ${unit} ${__DYBATPHO_SERVICE_ROOT}/etc/systemd/system/foo.service"
  assert_line "ELEVATED systemctl daemon-reload"
  assert_line "ELEVATED systemctl enable --now foo.service"
  : > "${CALLS}"
  _os Darwin
  _stub launchctl
  run_traced -0 dybatpho::service_install "$(_unit dev.example.foo.plist)"
  run -0 cat "${CALLS}"
  assert_line --partial "ELEVATED install -m 644 -o root -g wheel -- "
  assert_line --partial "/Library/LaunchDaemons/dev.example.foo.plist"
}

@test "dybatpho::service_install stops on OpenRC and runit, which take no unit file" {
  _os Linux
  _stub rc-service
  _stub rc-update
  run -1 --separate-stderr dybatpho::service_install "$(_unit foo.service)" --user
  assert_stderr --partial "takes no unit file: openrc"
}

@test "dybatpho::service_install under DYBATPHO_DRY_RUN copies and reloads nothing" {
  _systemd_user
  DYBATPHO_DRY_RUN=true run_traced -0 dybatpho::service_install "$(_unit foo.service)" --user
  assert_output --partial "systemctl --user daemon-reload"
  assert_file_not_exists "${XDG_CONFIG_HOME}/systemd/user/foo.service"
  run -0 cat "${CALLS}"
  refute_line "systemctl --user daemon-reload"
}

@test "dybatpho::service_install takes a unit whose path holds a space, and --name" {
  _systemd_user
  mkdir -p "${BATS_TEST_TMPDIR}/my units"
  printf '[Service]\nExecStart=/bin/true\n' > "${BATS_TEST_TMPDIR}/my units/app.service"
  run_traced -0 dybatpho::service_install "${BATS_TEST_TMPDIR}/my units/app.service" --user --name other.service
  assert_file_exists "${XDG_CONFIG_HOME}/systemd/user/other.service"
}

@test "dybatpho::service_uninstall disables, removes the unit and reloads" {
  _systemd_user
  dybatpho::service_install "$(_unit foo.service)" --user
  : > "${CALLS}"
  run_traced -0 dybatpho::service_uninstall foo.service --user
  assert_file_not_exists "${XDG_CONFIG_HOME}/systemd/user/foo.service"
  run -0 grep -v 'show-environment' "${CALLS}"
  assert_output $'systemctl --user disable --now foo.service\nsystemctl --user daemon-reload'
}

@test "dybatpho::service_reload_manager reloads systemd and does nothing elsewhere" {
  _systemd_user
  run_traced -0 dybatpho::service_reload_manager --user
  run -0 cat "${CALLS}"
  assert_line "systemctl --user daemon-reload"
  DYBATPHO_SERVICE_MANAGER=openrc run_traced -0 dybatpho::service_reload_manager
}
