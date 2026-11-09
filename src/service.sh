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
__DYBATPHO_SERVICE_ACTIONS=(enable disable start stop restart is-active is-enabled)
# Ends one command in a list of commands, so an action can run several.
__DYBATPHO_SERVICE_SEP=$'\x1e'

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

#######################################
# @description Fill an array with the commands an action runs on a manager,
#   each ended by `__DYBATPHO_SERVICE_SEP`. This table is the module's contract
#   with each manager; see FR-006 of `docs/spec/service.md`.
# @arg $1 string Name of the array receiving the commands
# @arg $2 string Manager
# @arg $3 string Action
# @arg $4 string Service name; a launchd one loses a `.plist` suffix
# @arg $5 string Scope, `user` or `system`
# @set The named array
# @internal
#######################################
# `c` is a nameref to the caller's array; ShellCheck cannot see the reads.
# shellcheck disable=SC2034
function __dybatpho_service_commands_into {
  local -n __dybatpho_service_commands="$1"
  local manager="$2" action="$3" name="$4" scope="$5" s="${__DYBATPHO_SERVICE_SEP}"
  local -a user=()
  [[ "${scope}" != user ]] || user=(--user)
  # A short alias of the result, so each table row fits one line.
  local -n c=__dybatpho_service_commands
  c=()
  case "${manager}" in
    systemd)
      local -a systemctl=(systemctl ${user[@]+"${user[@]}"} "${action}")
      case "${action}" in
        enable | disable) c=("${systemctl[@]}" --now "${name}" "${s}") ;;
        *) c=("${systemctl[@]}" "${name}" "${s}") ;;
      esac
      ;;
    openrc)
      local -a rc_service=(rc-service ${user[@]+"${user[@]}"} "${name}")
      local -a rc_update=(rc-update ${user[@]+"${user[@]}"})
      case "${action}" in
        enable) c=("${rc_update[@]}" add "${name}" default "${s}" "${rc_service[@]}" start "${s}") ;;
        disable) c=("${rc_service[@]}" stop "${s}" "${rc_update[@]}" del "${name}" default "${s}") ;;
        is-active) c=("${rc_service[@]}" status "${s}") ;;
        is-enabled) c=("${rc_update[@]}" show default "${s}") ;;
        *) c=("${rc_service[@]}" "${action}" "${s}") ;;
      esac
      ;;
    runit)
      case "${action}" in
        enable) c=(sv-enable "${name}" "${s}" sv up "${name}" "${s}") ;;
        disable) c=(sv down "${name}" "${s}" sv-disable "${name}" "${s}") ;;
        start) c=(sv up "${name}" "${s}") ;;
        stop) c=(sv down "${name}" "${s}") ;;
        restart) c=(sv restart "${name}" "${s}") ;;
        is-active) c=(sv status "${name}" "${s}") ;;
        is-enabled) c=(test ! -e "${PREFIX-}/var/service/${name}/down" "${s}") ;;
        *) ;;
      esac
      ;;
    launchd)
      local domain=system
      if [[ "${scope}" == user ]]; then
        domain="gui/$(id -u)"
      fi
      local target="${domain}/${name%.plist}"
      case "${action}" in
        enable) c=(launchctl enable "${target}" "${s}" launchctl kickstart "${target}" "${s}") ;;
        # A `kill` would be undone by `KeepAlive`, and `disable` alone leaves the job running.
        disable) c=(launchctl disable "${target}" "${s}" launchctl bootout "${target}" "${s}") ;;
        start) c=(launchctl kickstart "${target}" "${s}") ;;
        stop) c=(launchctl bootout "${target}" "${s}") ;;
        restart) c=(launchctl kickstart -k "${target}" "${s}") ;;
        is-active) c=(launchctl print "${target}" "${s}") ;;
        is-enabled) c=(launchctl print-disabled "${domain}" "${s}") ;;
        *) ;;
      esac
      ;;
    *) ;;
  esac
}

#######################################
# @description Tell whether an action on a manager and scope runs elevated:
#   a change on the system scope does, except on runit, which Termux runs as
#   its one user; a question never does.
# @arg $1 string Manager
# @arg $2 string Action
# @arg $3 string Scope
# @exitcode 0 It does
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_service_elevated {
  [[ "$3" == system && "$1" != runit && "$2" != is-* ]]
}

#######################################
# @description Stop the script unless an action is one the module knows.
# @arg $1 string Action
# @internal
#######################################
function __dybatpho_service_check_action {
  local known
  for known in "${__DYBATPHO_SERVICE_ACTIONS[@]}"; do
    [[ "${known}" != "$1" ]] || return 0
  done
  dybatpho::die "${FUNCNAME[1]}: Unknown action: $1"
}

#######################################
# @description Print the commands an action would run, one shell-quoted
#   command per line, with the elevation prefix where the action is elevated.
#   Nothing is run.
# @example
#   dybatpho::service_command enable sshd
#   # sudo -- systemctl enable --now sshd
#
# @arg $1 string Action: `enable`, `disable`, `start`, `stop`, `restart`,
#   `is-active` or `is-enabled`
# @arg $2 string Service name
# @arg $3 string [optional] `--user` for the user's own manager
# @stdout The commands, one per line
# @exitcode 0 The commands were printed
# @exitcode 1 No service manager was found
#######################################
function dybatpho::service_command {
  local action
  dybatpho::expect_args action -- "$@"
  shift
  __dybatpho_service_check_action "${action}"
  local name scope manager
  __dybatpho_service_parse_into name scope -- "$@"
  if ! __dybatpho_service_manager_into manager; then
    dybatpho::error "No service manager found"
    return 1
  fi
  local -a commands=() command=() prefix=()
  if __dybatpho_service_elevated "${manager}" "${action}" "${scope}" && dybatpho::privilege_needed; then
    prefix=("$(dybatpho::privilege_command)" --)
  fi
  __dybatpho_service_commands_into commands "${manager}" "${action}" "${name}" "${scope}"
  local word line
  for word in ${commands[@]+"${commands[@]}"}; do
    if [[ "${word}" != "${__DYBATPHO_SERVICE_SEP}" ]]; then
      command+=("${word}")
      continue
    fi
    printf -v line '%q ' ${prefix[@]+"${prefix[@]}"} ${command[@]+"${command[@]}"}
    printf '%s\n' "${line% }"
    command=()
  done
}

#######################################
# @description Run an action: check a manager can act in the scope, then run
#   its commands in order, elevated on the system scope, stopping at the first
#   that fails.
# @arg $1 string Action
# @arg $@ string Service name and optional `--user`
# @exitcode 0 The action ran, or was skipped with a warning
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
# @internal
#######################################
function __dybatpho_service_act {
  local action="$1" name scope manager
  shift
  __dybatpho_service_parse_into name scope -- "$@"
  local -a flag=()
  [[ "${scope}" != user ]] || flag=(--user)
  if ! __dybatpho_service_manager_into manager \
    || ! dybatpho::service_manager_available ${flag[@]+"${flag[@]}"}; then
    dybatpho::warn "No service manager can act on the ${scope} scope here; skipping ${action} ${name}"
    dybatpho::is true "${DYBATPHO_SERVICE_STRICT}" && return 1
    return 0
  fi
  local -a commands=() command=()
  __dybatpho_service_commands_into commands "${manager}" "${action}" "${name}" "${scope}"
  local word
  for word in ${commands[@]+"${commands[@]}"}; do
    if [[ "${word}" != "${__DYBATPHO_SERVICE_SEP}" ]]; then
      command+=("${word}")
      continue
    fi
    if __dybatpho_service_elevated "${manager}" "${action}" "${scope}"; then
      dybatpho::privilege_run -- ${command[@]+"${command[@]}"} || return
    else
      dybatpho::dry_run -- ${command[@]+"${command[@]}"} || return
    fi
    command=()
  done
}

#######################################
# @description Enable a service so it starts at boot or login, and start it now.
# @example
#   dybatpho::service_enable sshd
#   dybatpho::service_enable syncthing --user
#
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @env DYBATPHO_DRY_RUN string When true-like, print the commands instead of running them
# @exitcode 0 Enabled, or skipped with a warning where no manager can act
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
# @tip On launchd the job must already be loaded; `dybatpho::service_install` loads it
#######################################
function dybatpho::service_enable {
  __dybatpho_service_act enable "$@"
}

#######################################
# @description Disable a service so it no longer starts, and stop it now. On
#   launchd the job is also unloaded.
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 Disabled, or skipped with a warning
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
#######################################
function dybatpho::service_disable {
  __dybatpho_service_act disable "$@"
}

#######################################
# @description Start a service now, without enabling it.
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 Started, or skipped with a warning
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
#######################################
function dybatpho::service_start {
  __dybatpho_service_act start "$@"
}

#######################################
# @description Stop a service now, without disabling it. On launchd the job is
#   unloaded, since a stopped job with `KeepAlive` would be started again.
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 Stopped, or skipped with a warning
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
#######################################
function dybatpho::service_stop {
  __dybatpho_service_act stop "$@"
}

#######################################
# @description Restart a service.
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 Restarted, or skipped with a warning
# @exitcode 1 No manager can act and `DYBATPHO_SERVICE_STRICT` is set
# @exitcode other Exit code of the command that failed
#######################################
function dybatpho::service_restart {
  __dybatpho_service_act restart "$@"
}

#######################################
# @description Ask a manager a question about a service and read its answer.
#   The question runs even under `DYBATPHO_DRY_RUN`, since it changes nothing.
# @arg $1 string `is-active` or `is-enabled`
# @arg $@ string Service name and optional `--user`
# @exitcode 0 The answer is yes
# @exitcode 1 It is no, or no manager can answer
# @internal
#######################################
function __dybatpho_service_ask {
  local question="$1" name scope manager
  shift
  __dybatpho_service_parse_into name scope -- "$@"
  local -a flag=()
  [[ "${scope}" != user ]] || flag=(--user)
  __dybatpho_service_manager_into manager || return 1
  dybatpho::service_manager_available ${flag[@]+"${flag[@]}"} || return 1
  if [[ "${manager}:${question}" == runit:is-enabled ]]; then
    [[ -d "${PREFIX-}/var/service/${name}" && ! -e "${PREFIX-}/var/service/${name}/down" ]]
    return
  fi
  local -a commands=()
  __dybatpho_service_commands_into commands "${manager}" "${question}" "${name}" "${scope}"
  local answer status=0
  answer="$("${commands[@]:0:${#commands[@]}-1}" 2> /dev/null)" || status=$?
  local label="${name%.plist}" line
  case "${manager}:${question}" in
    systemd:* | openrc:is-active) return "${status}" ;;
    openrc:is-enabled)
      while IFS= read -r line; do
        [[ ! "${line}" =~ ^[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]] \
          || [[ "${BASH_REMATCH[1]}" != "${name}" ]] || return 0
      done <<< "${answer}"
      return 1
      ;;
    runit:is-active) [[ "${answer}" == "run: "* ]] ;;
    launchd:is-active)
      ((status == 0)) || return 1
      [[ "${answer}" =~ (^|$'\n')[[:space:]]*(state[[:space:]]*=[[:space:]]*running|pid[[:space:]]*=) ]]
      ;;
    launchd:is-enabled)
      ((status == 0)) || return 1
      while IFS= read -r line; do
        [[ ! "${line}" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*=\>[[:space:]]*(disabled|true) ]] \
          || [[ "${BASH_REMATCH[1]}" != "${label}" ]] || return 1
      done <<< "${answer}"
      return 0
      ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Tell whether a service is running now. On launchd a loaded job
#   that is not running counts as not active.
# @example
#   dybatpho::service_is_active rclone --user && dybatpho::info "rclone is running"
#
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 It is running
# @exitcode 1 It is not, or no manager can answer
#######################################
function dybatpho::service_is_active {
  __dybatpho_service_ask is-active "$@"
}

#######################################
# @description Tell whether a service is enabled, so it starts at boot or login.
# @arg $1 string Service name
# @arg $2 string [optional] `--user` for the user's own manager
# @exitcode 0 It is enabled
# @exitcode 1 It is not, or no manager can answer
#######################################
function dybatpho::service_is_enabled {
  __dybatpho_service_ask is-enabled "$@"
}
