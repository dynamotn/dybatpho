setup() {
  load test_helper

  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  TICKET="${BATS_TEST_TMPDIR}/ticket"
  mkdir -p "${STUB_DIR}"
  export SUDO_STUB_TICKET="${TICKET}"

  # A `sudo` that behaves like the real one in the ways this module depends
  # on: `-v` authenticates and caches a ticket, `-n` refuses rather than
  # prompting when there is none, and anything else runs the command.
  cat > "${STUB_DIR}/sudo" << 'STUB'
#!/usr/bin/env bash
ticket="${SUDO_STUB_TICKET:?}"
case "$1" in
  -n)
    shift
    [[ -f "${ticket}" ]] || { printf 'sudo: a password is required\n' >&2; exit 1; }
    [[ "$1" == "-v" ]] && exit 0
    exec "$@"
    ;;
  -v) : > "${ticket}"; exit 0 ;;
  *) printf 'STUB_PROMPTED\n' >&2; : > "${ticket}"; exec "$@" ;;
esac
STUB
  chmod +x "${STUB_DIR}/sudo"
  PATH="${STUB_DIR}:${PATH}"
  export PATH

  DYBATPHO_PRIVILEGE=auto
  DYBATPHO_PRIVILEGE_COMMAND=auto
  DYBATPHO_PRIVILEGE_SUSPEND_HOOK=""
}

teardown() {
  dybatpho::privilege_release || true
}

@test "dybatpho::privilege_command prefers sudo and honours an override" {
  run_traced -0 dybatpho::privilege_command
  assert_output "sudo"

  DYBATPHO_PRIVILEGE_COMMAND=doas run_traced -0 dybatpho::privilege_command
  assert_output "doas"
}

@test "dybatpho::privilege_command falls back to doas and then reports neither" {
  # PATH is pinned to the stub directory throughout: the host's own `sudo` is
  # still installed, so removing the stub does not make it absent.
  rm -f "${STUB_DIR}/sudo"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/doas"
  chmod +x "${STUB_DIR}/doas"
  PATH="${STUB_DIR}" run_traced -0 dybatpho::privilege_command
  assert_output "doas"

  rm -f "${STUB_DIR}/doas"
  PATH="${STUB_DIR}" run_traced -1 dybatpho::privilege_command
  assert_output ""
}

@test "dybatpho::privilege_needed says no when there is nothing to do" {
  DYBATPHO_PRIVILEGE=false run_traced -1 dybatpho::privilege_needed

  # Already root: there is nothing to escalate to.
  dybatpho::is_root() { return 0; }
  run_traced -1 dybatpho::privilege_needed
  unset -f dybatpho::is_root

  # No escalation command installed. PATH is pinned for the same reason as
  # above: the host's own `sudo` would otherwise be found.
  rm -f "${STUB_DIR}/sudo"
  dybatpho::is_root() { return 1; }
  PATH="${STUB_DIR}" run_traced -1 dybatpho::privilege_needed
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_needed says yes when a command has to be elevated" {
  dybatpho::is_root() { return 1; }
  run_traced -0 dybatpho::privilege_needed
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_run prefixes the command when elevation is needed" {
  dybatpho::is_root() { return 1; }
  : > "${TICKET}"
  run_traced -0 dybatpho::privilege_run -- printf 'elevated\n'
  assert_output "elevated"
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_run runs the command plainly when it is not needed" {
  # The call reads the same either way, which is the point: a caller does not
  # branch on whether it happens to be root.
  DYBATPHO_PRIVILEGE=false run_traced -0 dybatpho::privilege_run -- printf 'plain\n'
  assert_output "plain"
}

@test "dybatpho::privilege_run reports under DRY_RUN instead of running" {
  DRY_RUN=true DYBATPHO_PRIVILEGE=false \
    run_traced -0 dybatpho::privilege_run -- printf 'should not run\n'
  assert_output --partial "DRY RUN"
  refute_output --partial "should not run
"
}

@test "dybatpho::privilege_run needs a separator and a command" {
  run --separate-stderr dybatpho::privilege_run printf hi
  assert_failure
  assert_stderr --partial "Expected: -- command"

  run --separate-stderr dybatpho::privilege_run --
  assert_failure
  assert_stderr --partial "Expected a command"
}

@test "dybatpho::privilege_acquire does nothing when elevation is not needed" {
  DYBATPHO_PRIVILEGE=false run_traced -0 dybatpho::privilege_acquire
  assert_equal "${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}" ""
}

@test "dybatpho::privilege_acquire refuses rather than blocking where nothing can answer" {
  # A script run from cron must fail, not hang on a password prompt that no
  # one will ever see.
  dybatpho::is_root() { return 1; }
  dybatpho::is_tty() { return 1; }
  rm -f "${TICKET}"

  run_traced --separate-stderr -1 dybatpho::privilege_acquire
  assert_stderr --partial "cannot prompt"
  unset -f dybatpho::is_root dybatpho::is_tty
}

@test "dybatpho::privilege_acquire asks nothing when a ticket is already cached" {
  dybatpho::is_root() { return 1; }
  dybatpho::is_tty() { return 1; }
  : > "${TICKET}"

  # No tty, yet it succeeds: the cached ticket means no prompt is coming, so
  # the refusal above must not fire.
  run_traced --separate-stderr -0 dybatpho::privilege_acquire --no-keepalive
  refute_stderr --partial "cannot prompt"
  unset -f dybatpho::is_root dybatpho::is_tty
}

@test "dybatpho::privilege_acquire hands the terminal over around the prompt" {
  # A full-screen application draws over the alternate screen, where a
  # password prompt is invisible; the hook is how it steps aside.
  dybatpho::is_root() { return 1; }
  dybatpho::is_tty() { return 0; }
  rm -f "${TICKET}"

  SEEN=""
  record_hook() { SEEN+="$1 "; }
  DYBATPHO_PRIVILEGE_SUSPEND_HOOK=record_hook \
    dybatpho::privilege_acquire --no-keepalive
  assert_equal "${SEEN}" "suspend resume "
  unset -f dybatpho::is_root dybatpho::is_tty record_hook
}

@test "dybatpho::privilege_acquire --shield stops a child from prompting" {
  # Without this, something deep in a package manager stops and asks for a
  # password that nothing is in a position to display, and the run hangs.
  dybatpho::is_root() { return 1; }
  : > "${TICKET}"
  dybatpho::privilege_acquire --shield --no-keepalive

  assert_equal "$(command -v sudo)" "${DYBATPHO_PRIVILEGE_SHIELD_DIR}/sudo"

  rm -f "${TICKET}"
  run --separate-stderr sudo true
  assert_failure
  assert_stderr --partial "a password is required"
  refute_stderr --partial "STUB_PROMPTED"
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_acquire keeps the ticket alive and release stops it" {
  dybatpho::is_root() { return 1; }
  : > "${TICKET}"
  DYBATPHO_PRIVILEGE_REFRESH=1 dybatpho::privilege_acquire

  local refresher="${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}"
  [ -n "${refresher}" ]
  kill -0 "${refresher}"

  dybatpho::privilege_release
  sleep 1
  # A refresher left behind would hold a ticket for a process that is gone.
  run_traced -1 kill -0 "${refresher}"
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_acquire called twice holds one refresher, one shield and one trap" {
  # A second call used to start a second refresher, orphaning the first, put a
  # second wrapper in front of PATH that release then left behind, and append
  # the release to the traps again.
  dybatpho::is_root() { return 1; }
  : > "${TICKET}"
  local path_before="${PATH}"
  DYBATPHO_PRIVILEGE_REFRESH=1 dybatpho::privilege_acquire --shield
  local refresher="${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}"
  local shield="${DYBATPHO_PRIVILEGE_SHIELD_DIR}"
  local traps
  traps="$(trap -p EXIT)"

  DYBATPHO_PRIVILEGE_REFRESH=1 dybatpho::privilege_acquire --shield
  assert_equal "${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}" "${refresher}"
  assert_equal "${DYBATPHO_PRIVILEGE_SHIELD_DIR}" "${shield}"
  assert_equal "$(trap -p EXIT)" "${traps}"

  dybatpho::privilege_release
  assert_equal "${PATH}" "${path_before}"
  sleep 1
  run_traced -1 kill -0 "${refresher}"
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_release takes the shield off PATH and repeats harmlessly" {
  dybatpho::is_root() { return 1; }
  : > "${TICKET}"
  dybatpho::privilege_acquire --shield --no-keepalive
  local shield="${DYBATPHO_PRIVILEGE_SHIELD_DIR}"

  dybatpho::privilege_release
  assert_equal "${DYBATPHO_PRIVILEGE_SHIELD_DIR}" ""
  [[ ":${PATH}:" != *":${shield}:"* ]] || fail "the shield is still on PATH"

  run_traced -0 dybatpho::privilege_release
  unset -f dybatpho::is_root
}

@test "dybatpho::privilege_acquire rejects an option it does not have" {
  run --separate-stderr dybatpho::privilege_acquire --sudo-please
  assert_failure
  assert_stderr --partial "Unrecognized option: --sudo-please"
}

@test "dybatpho::privilege_acquire reports under DRY_RUN without acquiring" {
  dybatpho::is_root() { return 1; }
  rm -f "${TICKET}"

  DRY_RUN=true run_traced --separate-stderr -0 dybatpho::privilege_acquire
  assert_stderr --partial "would acquire sudo"
  assert_file_not_exist "${TICKET}"
  unset -f dybatpho::is_root
}
