# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# parses its own options, so the raw form is what the reader sees.
#
# Calling the escalation command is this module's whole purpose, so the rule
# against doing it from a script is answered here rather than at each call.
# dyshellint disable=BSG050,BSG051,BSG033,BSG035
# @file privilege.sh
# @brief Acquiring and holding a privilege escalation for a run
# @namespace dybatpho
# @description
#   `pkg.sh` can put `sudo` in front of one command. A script that runs twenty
#   of them over several minutes needs something else: the password asked for
#   once at the start, the ticket kept alive while the work runs, and no child
#   process able to stop and ask for it again halfway through.
#
#   That is what this module holds. `dybatpho::privilege_acquire` authenticates
#   once, refreshes the ticket in the background for as long as the script
#   lives, and -- when asked to -- puts a non-interactive `sudo` first on
#   `PATH` so nothing underneath can prompt. The refresher is tied to this
#   process and torn down through `process.sh`'s trap handling, so it cannot
#   outlive the script that started it.
#
#   Only the escalation itself lives here. Whether an action should happen at
#   all is `safety.sh`'s question, and the two are independent: reading a
#   protected file needs privilege and destroys nothing, while deleting your
#   own work needs no privilege at all.
# @tip A full-screen application has to give the terminal back before the
#   password prompt is drawn, which is what `DYBATPHO_PRIVILEGE_SUSPEND_HOOK`
#   is for
# @env DYBATPHO_PRIVILEGE_COMMAND string Escalation command, `auto` to detect `sudo` then `doas`
# @env DYBATPHO_PRIVILEGE string `auto` elevates when not root, `true`/`false` override the detection
# @env DYBATPHO_PRIVILEGE_SUSPEND_HOOK string Function called with `suspend` before prompting and `resume` after
# @env DYBATPHO_PRIVILEGE_REFRESH number Seconds between ticket refreshes, default is `60`
# @see
#   - `example/privilege_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_PRIVILEGE string Whether to elevate at all: `auto`, `true`, or `false`
DYBATPHO_PRIVILEGE="${DYBATPHO_PRIVILEGE:-auto}"
# @env DYBATPHO_PRIVILEGE_COMMAND string Escalation command to use, or `auto` to detect one
DYBATPHO_PRIVILEGE_COMMAND="${DYBATPHO_PRIVILEGE_COMMAND:-auto}"
# @env DYBATPHO_PRIVILEGE_SUSPEND_HOOK string Function handing the terminal over around a prompt
DYBATPHO_PRIVILEGE_SUSPEND_HOOK="${DYBATPHO_PRIVILEGE_SUSPEND_HOOK:-}"
# @env DYBATPHO_PRIVILEGE_REFRESH number Seconds between ticket refreshes
DYBATPHO_PRIVILEGE_REFRESH="${DYBATPHO_PRIVILEGE_REFRESH:-60}"

# The background refresher, and the directory holding the non-interactive
# wrapper. Both belong to the process that acquired the escalation, and
# `dybatpho::privilege_release` is what clears them.
DYBATPHO_PRIVILEGE_KEEPALIVE_PID=""
DYBATPHO_PRIVILEGE_SHIELD_DIR=""

#######################################
# @description Print the escalation command this host should use.
#   `sudo` first, then `doas`. `run0` is deliberately not detected: it is new
#   enough that a script finding it would more often be finding a system where
#   `sudo` was the intended path.
# @noargs
# @stdout `sudo`, `doas`, or nothing when neither is installed
# @exitcode 0 A command was printed
# @exitcode 1 Neither is installed
#######################################
function dybatpho::privilege_command {
  if [[ "${DYBATPHO_PRIVILEGE_COMMAND}" != "auto" ]]; then
    printf '%s\n' "${DYBATPHO_PRIVILEGE_COMMAND}"
    return 0
  fi

  local candidate
  for candidate in sudo doas; do
    if dybatpho::is command "${candidate}" > /dev/null; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Return success when a command has to be elevated to run.
#   Already root, no escalation command installed, or the caller turning it
#   off all mean no.
# @noargs
# @exitcode 0 Elevation is needed
# @exitcode 1 It is not
# @example
#   dybatpho::privilege_needed && dybatpho::privilege_acquire
#######################################
function dybatpho::privilege_needed {
  case "${DYBATPHO_PRIVILEGE}" in
    false | no | off | 1) return 1 ;;
    *) ;; # kcov(skip) - a case arm has no command to fire on
  esac

  ! dybatpho::is_root || return 1
  dybatpho::privilege_command > /dev/null || return 1
  return 0
}

#######################################
# @description Hand the terminal over, or take it back, around a prompt.
#   A full-screen application draws over the alternate screen, where a
#   password prompt is invisible; the hook is how such a caller steps aside
#   without this module knowing anything about `screen` or `tui`.
# @arg $1 string `suspend` or `resume`
#######################################
function __dybatpho_privilege_hand_over {
  [[ -n "${DYBATPHO_PRIVILEGE_SUSPEND_HOOK}" ]] || return 0
  dybatpho::is function "${DYBATPHO_PRIVILEGE_SUSPEND_HOOK}" > /dev/null || return 0
  "${DYBATPHO_PRIVILEGE_SUSPEND_HOOK}" "$1"
}

#######################################
# @description Return success when the escalation command already holds a
#   valid ticket, so no prompt would appear.
# @arg $1 string Escalation command
# @exitcode 0 A ticket is cached
# @exitcode 1 There is none, or this command has no cache to ask about
#######################################
function __dybatpho_privilege_cached {
  # Only `sudo` can be asked without prompting. `doas` has no equivalent, so
  # the honest answer for it is "unknown", which is reported as no ticket
  # rather than guessed as one.
  [[ "$1" == "sudo" ]] || return 1
  "$1" -n -v 2> /dev/null
}

#######################################
# @description Keep the escalation ticket alive until this process ends.
#   The refresher watches the parent rather than being signalled by it: a
#   script killed outright never gets to signal anything, and a refresher
#   left behind would hold a ticket for a process that no longer exists.
# @arg $1 string Escalation command
# @arg $2 number Seconds between refreshes
#######################################
function __dybatpho_privilege_keepalive {
  local parent="$$"
  (
    while kill -0 "${parent}" 2> /dev/null; do
      "$1" -n -v 2> /dev/null || true
      sleep "$2"
    done
  ) > /dev/null 2>&1 < /dev/null &
  DYBATPHO_PRIVILEGE_KEEPALIVE_PID=$!
}

#######################################
# @description Put a non-interactive escalation command first on `PATH`.
#   Without this, a child process deep inside a package manager can stop and
#   ask for a password that nothing is in a position to display. The wrapper
#   makes that failure loud and immediate instead of a run that hangs.
# @arg $1 string Escalation command
# @exitcode 0 The wrapper is in place and `PATH` points at it
#######################################
function __dybatpho_privilege_shield {
  local real
  real="$(command -v "$1")" || return 1

  dybatpho::create_temp_dir DYBATPHO_PRIVILEGE_SHIELD_DIR "privilege"
  printf '#!/bin/sh\nexec %q -n "$@"\n' "${real}" > "${DYBATPHO_PRIVILEGE_SHIELD_DIR}/$1"
  chmod +x "${DYBATPHO_PRIVILEGE_SHIELD_DIR}/$1"
  PATH="${DYBATPHO_PRIVILEGE_SHIELD_DIR}:${PATH}"
  export PATH
}

#######################################
# @description Authenticate once and hold the escalation for this run.
#   Nothing happens when elevation is not needed, so a caller can ask
#   unconditionally. When a prompt is required and the session cannot answer
#   one, this fails rather than blocking on a password nothing will type --
#   which is what a script run from cron needs.
# @arg $1 string Options, in any order
# @opt --shield Put a non-interactive escalation command first on `PATH`, so no child can prompt
# @opt --no-keepalive Skip the background refresh, for a run short enough not to need it
# @exitcode 0 The escalation is held, or was not needed
# @exitcode 1 Authentication failed, or a prompt was needed and could not be answered
# @env DRY_RUN string When true-like, report what would be acquired and change nothing
# @example
#   dybatpho::privilege_acquire --shield || dybatpho::die "Cannot elevate"
#######################################
function dybatpho::privilege_acquire {
  local shield="false" keepalive="true"
  while (($#)); do
    case "$1" in
      --shield) shield="true" ;;
      --no-keepalive) keepalive="false" ;;
      *) dybatpho::die "${FUNCNAME[0]}: Unrecognized option: $1" ;;
    esac
    shift
  done

  dybatpho::privilege_needed || return 0

  local command_name
  command_name="$(dybatpho::privilege_command)"

  # Nothing to execute here, only a decision to report, so `DRY_RUN` is read
  # rather than handed a command: `dybatpho::dry_run` runs what it is given.
  if dybatpho::is true "${DRY_RUN:-}"; then
    dybatpho::info "${FUNCNAME[0]}: would acquire ${command_name} for this run"
    return 0
  fi

  if ! __dybatpho_privilege_cached "${command_name}"; then
    # A prompt is coming. Refuse it where nobody can answer, rather than
    # letting the script hang on a terminal that is not there.
    if ! dybatpho::is_tty stdin; then
      dybatpho::error "${FUNCNAME[0]}: ${command_name} needs a password and this session cannot prompt"
      return 1
    fi

    __dybatpho_privilege_hand_over suspend
    local status=0
    "${command_name}" -v || status=$?
    __dybatpho_privilege_hand_over resume
    ((status == 0)) || return 1
  fi

  if dybatpho::is true "${keepalive}" && [[ "${command_name}" == "sudo" ]]; then
    __dybatpho_privilege_keepalive "${command_name}" "${DYBATPHO_PRIVILEGE_REFRESH}"
  fi

  if dybatpho::is true "${shield}"; then
    __dybatpho_privilege_shield "${command_name}"
  fi

  # Registered after the work above succeeded, so a failed acquire leaves no
  # teardown behind for a resource that was never taken.
  dybatpho::trap "dybatpho::privilege_release" EXIT HUP INT TERM
  return 0
}

#######################################
# @description Let the escalation go: stop the refresher and take the wrapper
#   off `PATH`. Calling it when nothing was acquired does nothing.
# @noargs
# @exitcode 0 Anything that was held is released
# @example
#   dybatpho::privilege_release
#######################################
function dybatpho::privilege_release {
  if [[ -n "${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}" ]]; then
    kill "${DYBATPHO_PRIVILEGE_KEEPALIVE_PID}" 2> /dev/null || true
    DYBATPHO_PRIVILEGE_KEEPALIVE_PID=""
  fi

  if [[ -n "${DYBATPHO_PRIVILEGE_SHIELD_DIR}" ]]; then
    PATH="${PATH//"${DYBATPHO_PRIVILEGE_SHIELD_DIR}":/}"
    export PATH
    DYBATPHO_PRIVILEGE_SHIELD_DIR=""
  fi
  return 0
}

#######################################
# @description Run one command elevated, for a caller that needs that and no
#   session. When elevation is not needed the command runs as it is, so the
#   call reads the same either way.
# @arg $1 string Literal `--` separating the options from the command
# @arg $@ string Command and arguments to run
# @exitcode 0 The command ran
# @exitcode other The command's own exit code
# @env DRY_RUN string When true-like, print the command instead of running it
# @example
#   dybatpho::privilege_run -- systemctl restart nginx
#######################################
function dybatpho::privilege_run {
  local separator
  dybatpho::expect_args separator -- "$@"
  shift
  [[ "${separator}" == "--" ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected: -- command [args...]"
  (($#)) || dybatpho::die "${FUNCNAME[0]}: Expected a command after \`--\`"

  if ! dybatpho::privilege_needed; then
    dybatpho::dry_run "$@"
    return
  fi

  local command_name
  command_name="$(dybatpho::privilege_command)"
  dybatpho::dry_run "${command_name}" "$@"
}
