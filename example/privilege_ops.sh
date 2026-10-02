#!/usr/bin/env bash
# @file privilege_ops.sh
# @brief Example holding a privilege escalation for the length of a run
# @description Demonstrates dybatpho::privilege_command, privilege_needed,
#   privilege_run, privilege_acquire, and privilege_release
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules privilege

dybatpho::register_common_handlers

# @description Put a stub escalation command first on PATH, so the example
#   asks for nothing and changes nothing on the machine running it.
#   `example/network_ops.sh` stubs `curl` the same way: a real executable in a
#   temporary directory, because the module calls the command rather than a
#   shell function.
# @arg $1 string Name of the variable receiving the stub directory
# @set The named variable
function _install_stub {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  # shellcheck disable=SC2034 # output for the caller; nothing here reads it back
  local -n stub_ref="${target}"

  dybatpho::create_temp_dir stub_ref "privilege-demo"
  cat > "${stub_ref}/sudo" << 'STUB'
#!/usr/bin/env bash
# Pretends a ticket is always cached, so nothing prompts.
case "$1" in
  -n) shift; [[ "$1" == "-v" ]] && exit 0; exec "$@" ;;
  -v) exit 0 ;;
  *) exec "$@" ;;
esac
STUB
  chmod +x "${stub_ref}/sudo"
  PATH="${stub_ref}:${PATH}"
  export PATH
}

# @description Show what the module decides before it does anything.
# @noargs
function _demo_detect {
  dybatpho::header "DETECT"
  dybatpho::info "Escalation command: $(dybatpho::privilege_command)"
  if dybatpho::privilege_needed; then
    dybatpho::info "Elevation is needed here"
  else
    dybatpho::info "Nothing to elevate: already root, or turned off"
  fi
}

# @description Run a single command, which reads the same whether or not
#   elevation turns out to be needed.
# @noargs
function _demo_run {
  dybatpho::header "ONE COMMAND"
  dybatpho::privilege_run -- printf 'this ran through the escalation command\n'

  # Nothing is executed while DRY_RUN is set, which is how a change gets
  # reviewed before it runs unattended.
  DRY_RUN=true dybatpho::privilege_run -- printf 'this one does not run\n'
}

# @description Hand the terminal over around a password prompt, and take it
#   back afterwards. A real caller would end and restart its full-screen
#   display here.
# @arg $1 string `suspend` before the prompt, `resume` after it
function _hand_over {
  local phase
  dybatpho::expect_args phase -- "$@"
  dybatpho::info "terminal: ${phase}"
}

# @description Hold the escalation for a whole run, the way a long install
#   needs it.
# @noargs
function _demo_session {
  dybatpho::header "A WHOLE RUN"

  # A full-screen application has to give the terminal back before a password
  # prompt is drawn over it; `_hand_over` is where `screen_end` and
  # `screen_begin` would go.
  export DYBATPHO_PRIVILEGE_SUSPEND_HOOK=_hand_over

  # `--shield` puts a non-interactive escalation command first on PATH, so a
  # child process cannot stop and ask for a password nothing can display.
  dybatpho::privilege_acquire --shield

  dybatpho::info "Shielded command: $(command -v sudo)"
  local step
  for step in "update the index" "install the tools" "enable the service"; do
    dybatpho::privilege_run -- printf 'would %s\n' "${step}"
  done

  # Releasing stops the background refresh and takes the shield off PATH. The
  # trap registered at acquire time does this too, so a script that dies part
  # way through leaves nothing behind.
  dybatpho::privilege_release
  dybatpho::success "Released; sudo is back to $(command -v sudo)"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  # shellcheck disable=SC2034 # filled for the caller's sake; PATH is the effect
  local stub
  _install_stub stub
  _demo_detect
  _demo_run
  _demo_session
  dybatpho::success "Privilege operations demo complete"
}

_main "$@"
