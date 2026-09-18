#!/usr/bin/env bash
# @file pkg.sh
# @brief Package manager detection and guarded dependency installation
# @description
#   This module answers three questions a portable installer script keeps
#   asking:
#
#   - which package manager does this machine use (`dybatpho::pkg_manager`);
#   - is a dependency already there (`dybatpho::pkg_installed`,
#     `dybatpho::pkg_missing`);
#   - how do I install it here without surprising the user
#     (`dybatpho::pkg_install`, `dybatpho::pkg_ensure`,
#     `dybatpho::pkg_require`).
#
#   Six managers are supported: `apt`, `brew`, `apk`, `dnf`, `pacman`, and
#   `emerge`. Detection prefers the platform's native manager, so a Linux box
#   with Homebrew installed still reports its distribution manager, and
#   `DYBATPHO_PKG_MANAGER` overrides the detection outright.
#
#   Because the same dependency is named differently on every distribution, the
#   install helpers accept `<manager>:<package>` overrides: `fd` is `fd-find` on
#   Debian, `fd` everywhere else, and `dybatpho::pkg_require fd apt:fd-find`
#   says exactly that.
#
#   Nothing here changes the system without saying so first. Every mutating
#   function asks for confirmation unless `--force`/`DYBATPHO_FORCE` is set,
#   refuses rather than guessing in a non-interactive shell, and prints the
#   command instead of running it under `--dry-run` or `DRY_RUN`.
# @usage
#   ### Report the machine's package manager
#
#   ```bash
#   dybatpho::pkg_manager   # apt, brew, apk, dnf, pacman or emerge
#   ```
#
#   ### Install only what is missing, unattended
#
#   ```bash
#   dybatpho::pkg_ensure --force curl jq
#   ```
#
#   ### Make sure a command exists, whatever the distribution calls it
#
#   ```bash
#   dybatpho::pkg_require fd apt:fd-find emerge:sys-apps/fd
#   ```
#
#   ### Show what would happen without touching the system
#
#   ```bash
#   dybatpho::pkg_install --dry-run ripgrep
#   ```
# @see
#   - `example/pkg_ops.sh`
# @tip Run an installer with `--dry-run` first, then with `--force` from CI, and the same script covers both the review and the unattended run.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_PKG_MANAGER string Force a package manager instead of detecting one
DYBATPHO_PKG_MANAGER="${DYBATPHO_PKG_MANAGER:-}"
# @env DYBATPHO_PKG_SUDO string `auto` elevates with sudo when not root, `true`/`false` override the detection
DYBATPHO_PKG_SUDO="${DYBATPHO_PKG_SUDO:-auto}"
# @env DYBATPHO_PKG_ASSUME_YES bool Set to `false` to drop the manager's non-interactive flags
DYBATPHO_PKG_ASSUME_YES="${DYBATPHO_PKG_ASSUME_YES:-true}"

# Supported managers, and the command whose presence proves the manager is
# usable. `apt` is driven through `apt-get`: the `apt` binary prints a warning
# about its unstable CLI whenever its output is not a terminal.
declare -gA __dybatpho_pkg_binary=(
  [apt]="apt-get"
  [brew]="brew"
  [apk]="apk"
  [dnf]="dnf"
  [pacman]="pacman"
  [emerge]="emerge"
)

#######################################
# @description Print the managers to probe, most specific to this platform first.
# @stdout One manager name per line
#######################################
function __dybatpho_pkg_detection_order {
  local platform
  platform="$(dybatpho::platform)"
  case "${platform}" in
    # Homebrew is the only one of the six that is at home on macOS.
    darwin) printf '%s\n' brew ;;
    # A Linux box may also carry Homebrew, but the distribution manager owns the
    # system packages, so it is probed first.
    linux) printf '%s\n' apt dnf pacman apk emerge brew ;;
    *) printf '%s\n' brew apt dnf pacman apk emerge ;;
  esac
}

#######################################
# @description Fail unless a name is one of the supported package managers.
# @arg $1 string Manager name
# @arg $2 string Function name used in the failure message
# @exitcode 1 Stop the script when the manager is unknown
#######################################
function __dybatpho_pkg_assert_manager {
  local manager caller
  dybatpho::expect_args manager caller -- "$@"
  [[ -n "${__dybatpho_pkg_binary[${manager}]-}" ]] \
    || dybatpho::die "${caller}: unsupported package manager '${manager}', expected one of $(dybatpho::pkg_supported | tr '\n' ' ')"
}

#######################################
# @description Print the privilege escalation prefix for a manager, one word per line.
# @arg $1 string Manager name
# @stdout `sudo` when elevation is needed, nothing otherwise
# @env DYBATPHO_PKG_SUDO string `auto` elevates when not root, `true`/`false` override the detection
#######################################
function __dybatpho_pkg_privilege {
  local manager
  dybatpho::expect_args manager -- "$@"
  # Homebrew refuses to run under sudo, so it never gets a prefix.
  [[ "${manager}" != "brew" ]] || return 0
  case "${DYBATPHO_PKG_SUDO}" in
    auto | '')
      [[ "${EUID:-$(id -u)}" -ne 0 ]] || return 0
      dybatpho::is command sudo || return 0
      printf '%s\n' sudo
      ;;
    *)
      dybatpho::is true "${DYBATPHO_PKG_SUDO}" && printf '%s\n' sudo
      ;;
  esac
  return 0
}

#######################################
# @description Print the non-interactive flags a manager needs, one word per line.
# @arg $1 string Manager name
# @stdout Zero or more flags
# @env DYBATPHO_PKG_ASSUME_YES bool Set to `false` to print nothing
#######################################
function __dybatpho_pkg_assume_yes_flags {
  local manager
  dybatpho::expect_args manager -- "$@"
  dybatpho::is true "${DYBATPHO_PKG_ASSUME_YES}" || return 0
  case "${manager}" in
    apt | dnf) printf '%s\n' -y ;;
    pacman) printf '%s\n' --noconfirm ;;
    emerge) printf '%s\n' --ask=n ;;
    # `apk add` and `brew install` never prompt.
    *) ;;
  esac
  return 0
}

#######################################
# @description Print the command for an action, one word per line.
# @arg $1 string Manager name
# @arg $2 string Action, `install` or `update`
# @arg $@ string Packages, for the `install` action
# @stdout The command and its arguments, one word per line
#######################################
function __dybatpho_pkg_action_command {
  local manager action
  dybatpho::expect_args manager action -- "$@"
  shift 2
  local -a command_parts=()
  mapfile -t command_parts < <(__dybatpho_pkg_privilege "${manager}")
  local -a assume_yes=()
  mapfile -t assume_yes < <(__dybatpho_pkg_assume_yes_flags "${manager}")

  case "${action}" in
    install)
      case "${manager}" in
        # `apt-get` drives debconf, which opens a dialog on some packages unless
        # the frontend is told that nobody is watching.
        apt) command_parts+=(env DEBIAN_FRONTEND=noninteractive apt-get install "${assume_yes[@]}") ;;
        brew) command_parts+=(brew install) ;;
        apk) command_parts+=(apk add) ;;
        dnf) command_parts+=(dnf install "${assume_yes[@]}") ;;
        # `--needed` keeps an already installed package from being reinstalled.
        pacman) command_parts+=(pacman -S --needed "${assume_yes[@]}") ;;
        emerge) command_parts+=(emerge --noreplace "${assume_yes[@]}") ;;
      esac
      command_parts+=("$@")
      ;;
    update)
      # Only `pacman -Sy` prompts while refreshing an index, so it is the one
      # refresh that carries the non-interactive flag.
      case "${manager}" in
        apt) command_parts+=(apt-get update) ;;
        brew) command_parts+=(brew update) ;;
        apk) command_parts+=(apk update) ;;
        dnf) command_parts+=(dnf makecache) ;;
        pacman) command_parts+=(pacman -Sy "${assume_yes[@]}") ;;
        emerge) command_parts+=(emerge --sync) ;;
      esac
      ;;
    *) dybatpho::die "__dybatpho_pkg_action_command: unknown action '${action}'" ;;
  esac
  printf '%s\n' "${command_parts[@]}"
}

#######################################
# @description Approve a system change from a force flag, otherwise ask for confirmation.
# @arg $1 bool Force flag value
# @arg $2 string Question shown when confirmation is needed
# @exitcode 0 The change is approved
# @exitcode 1 The change is declined or can't be confirmed
#######################################
function __dybatpho_pkg_approve {
  local force question
  dybatpho::expect_args force question -- "$@"
  if dybatpho::is true "${force}"; then
    dybatpho::debug "Forced without confirmation: ${question}"
    return 0
  fi
  dybatpho::confirm "${question}"
}

#######################################
# @description Run a command through `dybatpho::dry_run` with `DRY_RUN` overridden for this call only.
# @arg $1 string Dry-run flag value
# @arg $@ string The command and its arguments
# @exitcode The exit code of the command, or 0 when it is only printed
#######################################
function __dybatpho_pkg_run {
  local dry_run
  dybatpho::expect_args dry_run -- "$@"
  shift
  local previous_dry_run="${DRY_RUN}"
  local status=0
  DRY_RUN="${dry_run}"
  dybatpho::dry_run "$@" || status=$?
  DRY_RUN="${previous_dry_run}"
  return "${status}"
}

#######################################
# @description Print every package manager this module supports.
# @stdout One manager name per line, alphabetically
#######################################
function dybatpho::pkg_supported {
  printf '%s\n' apk apt brew dnf emerge pacman
}

#######################################
# @description Report the package manager of the current machine.
# @example
#   manager="$(dybatpho::pkg_manager)" || dybatpho::die "No supported package manager"
#
# @stdout `apt`, `brew`, `apk`, `dnf`, `pacman`, or `emerge`
# @exitcode 0 A supported manager is installed
# @exitcode 1 None of the supported managers is installed
# @env DYBATPHO_PKG_MANAGER string When set, this manager is reported without probing
#######################################
function dybatpho::pkg_manager {
  if [[ -n "${DYBATPHO_PKG_MANAGER}" ]]; then
    __dybatpho_pkg_assert_manager "${DYBATPHO_PKG_MANAGER}" "dybatpho::pkg_manager"
    printf '%s\n' "${DYBATPHO_PKG_MANAGER}"
    return 0
  fi
  local manager
  while IFS= read -r manager; do
    if dybatpho::is command "${__dybatpho_pkg_binary[${manager}]}"; then
      printf '%s\n' "${manager}"
      return 0
    fi
  done < <(__dybatpho_pkg_detection_order)
  dybatpho::debug "No supported package manager found on this machine"
  return 1
}

#######################################
# @description Return success when a package manager is usable on this machine.
# @arg $1 string Optional manager name, default is the detected one
# @exitcode 0 The manager is installed
# @exitcode 1 The manager is not installed, or nothing was detected
#######################################
function dybatpho::pkg_manager_available {
  local manager="${1:-}"
  if [[ -z "${manager}" ]]; then
    manager="$(dybatpho::pkg_manager)" || return 1
  fi
  __dybatpho_pkg_assert_manager "${manager}" "dybatpho::pkg_manager_available"
  dybatpho::is command "${__dybatpho_pkg_binary[${manager}]}"
}

#######################################
# @description Resolve a package name for the current manager from `<manager>:<package>` overrides.
# @example
#   dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd   # fd-find on Debian
#
# @arg $1 string Default package name, used when no override matches
# @arg $@ string Optional `<manager>:<package>` overrides
# @stdout The package name to install on this machine
# @exitcode 0 A name is printed
# @exitcode 1 No package manager was detected
#######################################
function dybatpho::pkg_name {
  local default_name
  dybatpho::expect_args default_name -- "$@"
  shift
  local manager
  manager="$(dybatpho::pkg_manager)" || return 1
  local override
  for override in "$@"; do
    [[ "${override}" == *:* ]] \
      || dybatpho::die "dybatpho::pkg_name: expected <manager>:<package>, got '${override}'"
    __dybatpho_pkg_assert_manager "${override%%:*}" "dybatpho::pkg_name"
    if [[ "${override%%:*}" == "${manager}" ]]; then
      printf '%s\n' "${override#*:}"
      return 0
    fi
  done
  printf '%s\n' "${default_name}"
}

#######################################
# @description Return success when a package is installed, according to the detected manager.
# @arg $1 string Package name
# @exitcode 0 The package is installed
# @exitcode 1 The package is missing, or no package manager was detected
#######################################
function dybatpho::pkg_installed {
  local package
  dybatpho::expect_args package -- "$@"
  local manager
  manager="$(dybatpho::pkg_manager)" || return 1
  local query=""
  case "${manager}" in
    # `dpkg-query` also knows removed packages whose configuration is still
    # there, so the status has to say `installed` rather than merely be known.
    apt) dpkg-query -W -f='${Status}' -- "${package}" 2> /dev/null | grep -q "ok installed" ;;
    brew) brew list --versions -- "${package}" > /dev/null 2>&1 ;;
    # `apk info -e` succeeds for a missing package and prints nothing instead.
    apk)
      query="$(apk info -e -- "${package}" 2> /dev/null)" || return 1
      [[ -n "${query}" ]]
      ;;
    dnf) rpm -q -- "${package}" > /dev/null 2>&1 ;;
    pacman) pacman -Q -- "${package}" > /dev/null 2>&1 ;;
    emerge)
      if dybatpho::is command qlist; then
        query="$(qlist -I -C -- "${package}" 2> /dev/null)" || return 1
      elif dybatpho::is command equery; then
        query="$(equery --quiet list -- "${package}" 2> /dev/null)" || return 1
      else
        dybatpho::warn "Can't query installed packages on emerge without qlist or equery"
        return 1
      fi
      [[ -n "${query}" ]]
      ;;
  esac
}

#######################################
# @description Print the packages that are not installed yet.
# @example
#   mapfile -t missing < <(dybatpho::pkg_missing curl jq)
#
# @arg $@ string Package names
# @stdout One missing package per line, in the order they were given
# @exitcode 0 The check ran; empty output means nothing is missing
# @exitcode 1 No package manager was detected
#######################################
function dybatpho::pkg_missing {
  (($#)) || dybatpho::die "dybatpho::pkg_missing: expected at least one package"
  dybatpho::pkg_manager > /dev/null || return 1
  local package
  for package in "$@"; do
    dybatpho::pkg_installed "${package}" || printf '%s\n' "${package}"
  done
}

#######################################
# @description Print the command that would install the given packages, without running it.
# @example
#   dybatpho::pkg_install_command ripgrep   # sudo apt-get install -y ripgrep
#
# @arg $@ string Package names
# @stdout The install command as a single quoted line
# @exitcode 1 No package manager was detected
#######################################
function dybatpho::pkg_install_command {
  (($#)) || dybatpho::die "dybatpho::pkg_install_command: expected at least one package"
  local manager
  manager="$(dybatpho::pkg_manager)" || return 1
  local -a command_parts=()
  mapfile -t command_parts < <(__dybatpho_pkg_action_command "${manager}" install "$@")
  printf '%s' "${command_parts[0]}"
  printf ' %s' "${command_parts[@]:1}"
  printf '\n'
}

#######################################
# @description Refresh the package index, after confirming the change.
# @arg $1 string Option `--force`/`-f` to skip confirmation, `--dry-run`/`-n` to print the command instead
# @exitcode 0 The index was refreshed, or the command was printed
# @exitcode 1 The refresh is declined, the command failed, or no manager was detected
# @env DRY_RUN string When true-like, print the command instead of running it
#######################################
function dybatpho::pkg_update {
  local force="${DYBATPHO_FORCE}" dry_run="${DRY_RUN}"
  while (($#)); do
    case "$1" in
      -f | --force) force=true ;;
      -n | --dry-run) dry_run=true ;;
      *) dybatpho::die "dybatpho::pkg_update: unknown option: $1" ;;
    esac
    shift
  done
  local manager
  manager="$(dybatpho::pkg_manager)" \
    || dybatpho::die "dybatpho::pkg_update: no supported package manager found"
  local -a command_parts=()
  mapfile -t command_parts < <(__dybatpho_pkg_action_command "${manager}" update)

  # A dry run changes nothing, so there is nothing to confirm.
  if ! dybatpho::is true "${dry_run}" \
    && ! __dybatpho_pkg_approve "${force}" "Refresh the ${manager} package index?"; then
    dybatpho::warn "Skipped package index refresh"
    return 1
  fi
  dybatpho::info "Refreshing the ${manager} package index"
  __dybatpho_pkg_run "${dry_run}" "${command_parts[@]}"
}

#######################################
# @description Install packages with the detected manager, after confirming the change.
# @example
#   dybatpho::pkg_install --force curl jq
#
# @example
#   dybatpho::pkg_install --dry-run -- ripgrep
#
# @arg $1 string Option `--force`/`-f` to skip confirmation, `--dry-run`/`-n` to print the command instead, `--update`/`-u` to refresh the index first
# @arg $@ string Packages, optionally after a `--` separator
# @exitcode 0 The packages were installed, or the command was printed
# @exitcode 1 The install is declined, the command failed, or no manager was detected
# @env DRY_RUN string When true-like, print the command instead of running it
# @env DYBATPHO_FORCE bool Approve the change without prompting
#######################################
function dybatpho::pkg_install {
  local force="${DYBATPHO_FORCE}" dry_run="${DRY_RUN}" refresh=false
  local -a packages=()
  while (($#)); do
    case "$1" in
      -f | --force) force=true ;;
      -n | --dry-run) dry_run=true ;;
      -u | --update) refresh=true ;;
      --)
        shift
        packages+=("$@")
        break
        ;;
      -*) dybatpho::die "dybatpho::pkg_install: unknown option: $1" ;;
      *) packages+=("$1") ;;
    esac
    shift
  done
  ((${#packages[@]})) || dybatpho::die "dybatpho::pkg_install: expected at least one package"
  local manager
  manager="$(dybatpho::pkg_manager)" \
    || dybatpho::die "dybatpho::pkg_install: no supported package manager found"
  local -a command_parts=()
  mapfile -t command_parts < <(__dybatpho_pkg_action_command "${manager}" install "${packages[@]}")

  # A dry run changes nothing, so there is nothing to confirm.
  if ! dybatpho::is true "${dry_run}" \
    && ! __dybatpho_pkg_approve "${force}" "Install with ${manager}: ${packages[*]}?"; then
    dybatpho::warn "Skipped install of: ${packages[*]}"
    return 1
  fi
  if dybatpho::is true "${refresh}"; then
    local -a update_args=(--force)
    dybatpho::is true "${dry_run}" && update_args+=(--dry-run)
    dybatpho::pkg_update "${update_args[@]}" || return 1
  fi
  dybatpho::info "Installing with ${manager}: ${packages[*]}"
  __dybatpho_pkg_run "${dry_run}" "${command_parts[@]}"
}

#######################################
# @description Install only the packages that are missing, and do nothing when they are all there.
# @example
#   dybatpho::pkg_ensure --force curl jq
#
# @arg $1 string The options of `dybatpho::pkg_install`
# @arg $@ string Packages, optionally after a `--` separator
# @exitcode 0 Every package is installed, was already installed, or the command was printed
# @exitcode 1 The install is declined, the command failed, or no manager was detected
#######################################
function dybatpho::pkg_ensure {
  local -a options=() packages=()
  while (($#)); do
    case "$1" in
      -f | --force | -n | --dry-run | -u | --update) options+=("$1") ;;
      --)
        shift
        packages+=("$@")
        break
        ;;
      -*) dybatpho::die "dybatpho::pkg_ensure: unknown option: $1" ;;
      *) packages+=("$1") ;;
    esac
    shift
  done
  ((${#packages[@]})) || dybatpho::die "dybatpho::pkg_ensure: expected at least one package"
  dybatpho::pkg_manager > /dev/null \
    || dybatpho::die "dybatpho::pkg_ensure: no supported package manager found"
  local -a missing=()
  mapfile -t missing < <(dybatpho::pkg_missing "${packages[@]}")
  if ((${#missing[@]} == 0)); then
    dybatpho::debug "Already installed: ${packages[*]}"
    return 0
  fi
  dybatpho::pkg_install "${options[@]}" -- "${missing[@]}"
}

#######################################
# @description Make sure a command is available, installing the package that provides it on this machine.
# @example
#   dybatpho::pkg_require --force fd apt:fd-find emerge:sys-apps/fd
#
# @arg $1 string The options of `dybatpho::pkg_install`
# @arg $2 string Command that must be available, also the default package name
# @arg $@ string Optional `<manager>:<package>` overrides
# @exitcode 0 The command is available, or its package was installed
# @exitcode 1 The install is declined, the command failed, or the command is still missing afterwards
#######################################
function dybatpho::pkg_require {
  local dry_run="${DRY_RUN}"
  local -a options=() arguments=()
  while (($#)); do
    case "$1" in
      -n | --dry-run)
        dry_run=true
        options+=("$1")
        ;;
      -f | --force | -u | --update) options+=("$1") ;;
      --)
        shift
        arguments+=("$@")
        break
        ;;
      -*) dybatpho::die "dybatpho::pkg_require: unknown option: $1" ;;
      *) arguments+=("$1") ;;
    esac
    shift
  done
  ((${#arguments[@]})) || dybatpho::die "dybatpho::pkg_require: expected a command name"
  local command_name="${arguments[0]}"
  if dybatpho::is command "${command_name}"; then
    dybatpho::debug "Already available: ${command_name}"
    return 0
  fi
  local package
  package="$(dybatpho::pkg_name "${arguments[@]}")" \
    || dybatpho::die "dybatpho::pkg_require: no supported package manager found for '${command_name}'"
  dybatpho::pkg_install "${options[@]}" -- "${package}" || return 1
  # A dry run installs nothing, so the command being missing is the expected
  # outcome rather than a failure.
  dybatpho::is true "${dry_run}" && return 0
  if ! dybatpho::is command "${command_name}"; then
    dybatpho::error "Installed ${package} but ${command_name} is still not available"
    return 1
  fi
}
