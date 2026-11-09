# shellcheck shell=bash
# @file service.sh
# @brief Utilities for enabling, controlling and installing services
# @namespace dybatpho
# @description
#   This module drives the machine's service manager -- systemd, OpenRC,
#   runit on Termux, or launchd -- through one set of calls: enable, disable,
#   start, stop, restart, ask whether a service is active or enabled, and
#   install a unit file or plist so the manager picks it up.
#
#   An action takes the service name and an optional `--user`. Without it the
#   action is on the system scope and goes through `dybatpho::privilege_run`;
#   with it, on the user's own manager, never elevated. Every command can be
#   printed first with `dybatpho::service_command`, and `DYBATPHO_DRY_RUN`
#   prints instead of running.
#
#   A machine whose manager cannot act -- a container, a CI runner, SSH into a
#   Mac with no GUI session -- is skipped with a warning, so a bootstrap does
#   not fail on it; `DYBATPHO_SERVICE_STRICT` makes that a failure.
# @usage
#   ### Install a user unit and have it running, on systemd or launchd alike
#
#   ```bash
#   dybatpho::service_install "${HOME}/.config/app/app.service" --user
#   ```
#
#   ### Enable a system service, elevated as needed
#
#   ```bash
#   dybatpho::service_enable sshd
#   ```
# @see
#   - `example/service_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_SERVICE_MANAGER string Force a service manager: `systemd`, `openrc`, `runit` or `launchd`
DYBATPHO_SERVICE_MANAGER="${DYBATPHO_SERVICE_MANAGER:-}"
# @env DYBATPHO_SERVICE_STRICT bool [default: false] Fail, rather than warn and skip, when no manager can act
DYBATPHO_SERVICE_STRICT="${DYBATPHO_SERVICE_STRICT:-false}"

# Root the probed paths resolve under; tests point it at a directory of their own.
__DYBATPHO_SERVICE_ROOT="${__DYBATPHO_SERVICE_ROOT:-}"
__DYBATPHO_SERVICE_MANAGERS=(systemd openrc runit launchd)

#######################################
# @description Detect the service manager into a variable.
#   On Linux the manager that booted the machine wins: systemd when
#   `/run/systemd/system` exists -- a Gentoo host booted by OpenRC can still
#   carry `systemctl` -- then OpenRC, then runit on Termux (`sv-enable`). On
#   Darwin, launchd.
# @arg $1 string Name of the variable receiving the manager
# @set The named variable, empty when none is found
# @exitcode 0 A manager was found
# @exitcode 1 None was found
# @internal
#######################################
function __dybatpho_service_manager_into {
  local -n __dybatpho_service_manager_ref="$1"
  __dybatpho_service_manager_ref=""
  if [[ -n "${DYBATPHO_SERVICE_MANAGER}" ]]; then
    local known
    for known in "${__DYBATPHO_SERVICE_MANAGERS[@]}"; do
      if [[ "${known}" == "${DYBATPHO_SERVICE_MANAGER}" ]]; then
        __dybatpho_service_manager_ref="${known}"
        return 0
      fi
    done
    dybatpho::die "Unknown service manager: ${DYBATPHO_SERVICE_MANAGER}"
  fi
  local os
  os="$(uname -s 2> /dev/null)" || os=""
  if [[ "${os}" == Darwin ]]; then
    dybatpho::is command launchctl && __dybatpho_service_manager_ref=launchd
  elif [[ -d "${__DYBATPHO_SERVICE_ROOT}/run/systemd/system" ]] && dybatpho::is command systemctl; then
    __dybatpho_service_manager_ref=systemd
  elif dybatpho::is command rc-service; then
    __dybatpho_service_manager_ref=openrc
  elif dybatpho::is command sv-enable; then
    __dybatpho_service_manager_ref=runit
  fi
  [[ -n "${__dybatpho_service_manager_ref}" ]]
}

#######################################
# @description Tell whether the process runs in a container, where a system
#   service manager may be installed but is not the one in charge.
# @noargs
# @exitcode 0 It does
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_service_in_container {
  local root="${__DYBATPHO_SERVICE_ROOT}" cgroup=""
  [[ ! -e "${root}/.dockerenv" && ! -e "${root}/run/.containerenv" ]] || return 0
  if [[ -r "${root}/proc/self/cgroup" ]]; then
    cgroup="$(< "${root}/proc/self/cgroup")"
  fi
  [[ "${cgroup}" == *docker* || "${cgroup}" == *containerd* || "${cgroup}" == *libpod* ]]
}

#######################################
# @description Read a service name and an optional `--user` flag, in either order.
# @arg $1 string Name of the variable receiving the service name
# @arg $2 string Name of the variable receiving the scope, `user` or `system`
# @arg $3 string Literal `--`
# @arg $@ string The caller's arguments
# @set Both named variables
# @exitcode 1 Stop script on a missing name, an unknown option, or a name the
#   managers cannot take
# @internal
#######################################
function __dybatpho_service_parse_into {
  local -n __dybatpho_service_parse_name="$1" __dybatpho_service_parse_scope="$2"
  shift 3
  __dybatpho_service_parse_name="" __dybatpho_service_parse_scope=system
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --user) __dybatpho_service_parse_scope=user ;;
      -*) dybatpho::die "${FUNCNAME[1]}: Unknown option: ${arg}" ;;
      *)
        [[ -z "${__dybatpho_service_parse_name}" ]] \
          || dybatpho::die "${FUNCNAME[1]}: Expected one service name, got: ${__dybatpho_service_parse_name} ${arg}"
        __dybatpho_service_parse_name="${arg}"
        ;;
    esac
  done
  [[ -n "${__dybatpho_service_parse_name}" ]] || dybatpho::die "${FUNCNAME[1]}: Expected a service name"
  [[ "${__dybatpho_service_parse_name}" =~ ^[A-Za-z0-9@._:+-]+$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Invalid service name: ${__dybatpho_service_parse_name}"
}

#######################################
# @description Print the service manager this machine runs.
# @example
#   case "$(dybatpho::service_manager)" in
#     systemd) ... ;;
#   esac
#
# @noargs
# @env DYBATPHO_SERVICE_MANAGER string Force a manager instead of detecting one
# @stdout `systemd`, `openrc`, `runit` or `launchd`
# @exitcode 0 A manager was found
# @exitcode 1 None was found
#######################################
function dybatpho::service_manager {
  local manager
  __dybatpho_service_manager_into manager || return 1
  printf '%s\n' "${manager}"
}

#######################################
# @description Tell whether the service manager can act in a scope here: it is
#   installed, and running for that scope. systemd's user scope needs a user
#   manager answering `show-environment`; its system scope a system that is
#   not `offline` (a chroot) and not a container. OpenRC's user scope needs a
#   user instance, OpenRC 0.60 and later; launchd's, a GUI session.
# @example
#   dybatpho::service_manager_available --user || dybatpho::warn "No user services here"
#
# @arg $1 string [optional] `--user` for the user's own manager
# @exitcode 0 The manager can act in that scope
# @exitcode 1 It cannot, or there is none
#######################################
# dyshellint disable=BSG050 # its one argument is an optional flag, which expect_args cannot express
function dybatpho::service_manager_available {
  local scope=system manager state=""
  [[ "${1-}" != --user ]] || scope=user
  __dybatpho_service_manager_into manager || return 1
  case "${manager}:${scope}" in
    systemd:user) systemctl --user show-environment &> /dev/null ;;
    systemd:system)
      ! __dybatpho_service_in_container || return 1
      state="$(systemctl is-system-running 2> /dev/null)" || true
      [[ -n "${state}" && "${state}" != offline ]]
      ;;
    openrc:user) rc-update --user show &> /dev/null ;;
    openrc:system) ! __dybatpho_service_in_container ;;
    runit:*) dybatpho::is command sv-enable ;;
    launchd:user)
      local uid
      uid="$(id -u)"
      launchctl print "gui/${uid}" &> /dev/null
      ;;
    launchd:system) dybatpho::is command launchctl ;;
    *) return 1 ;;
  esac
}
