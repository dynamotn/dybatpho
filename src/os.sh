# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it keeps its declarations with the functions they
# describe.
# dyshellint disable=BSG050,BSG011,BSG033
# @file os.sh
# @brief Utilities for getting information of OS/distro
# @namespace dybatpho
# @description
#   This module contains functions to get information of OS/distro, such as platform, distribution and architecture,
#   plus the host facts other modules would otherwise each detect for themselves: host and user names, processor count,
#   terminal size, and whether the script runs as root, in a container, under WSL, or on CI. Package manager detection
#   and dependency installation live in `pkg.sh`.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# The host name cannot change under a running script, so it is resolved once.
# The cache is process-local on purpose: an exported value would follow a script
# into a container or an `ssh` command, where it would be wrong.
__dybatpho_os_hostname=""

#######################################
# @description Get $GOOS compilation environment
# @noargs
# @stdout Return $GOOS value https://go.dev/doc/install/source#environment
#######################################
function dybatpho::goos {
  local os
  local uname
  uname=$(uname -s)
  os="$(dybatpho::lower "${uname}")"
  local goos
  case "${os}" in
    cygwin_nt*) goos="windows" ;;
    linux)
      local variant
      variant="$(dybatpho::lower "$(uname -o 2> /dev/null || true)")"
      case "${variant}" in
        android) goos="android" ;;
        *) goos="linux" ;;
      esac
      ;;
    mingw*) goos="windows" ;;
    msys_nt*) goos="windows" ;;
    *) goos="${os}" ;;
  esac
  printf '%s' "${goos}"
}

#######################################
# @description Return the normalized host operating system name.
# @noargs
# @stdout `linux`, `darwin`, `windows`, `android`, or the normalized uname name
#######################################
function dybatpho::platform {
  dybatpho::goos
}

#######################################
# @description Return success when running on macOS.
#######################################
# @noargs
function dybatpho::is_macos {
  local platform
  platform=$(dybatpho::platform)
  [[ "${platform}" == "darwin" ]]
}

#######################################
# @description Return success when running on Linux.
#######################################
# @noargs
function dybatpho::is_linux {
  local platform
  platform=$(dybatpho::platform)
  [[ "${platform}" == "linux" ]]
}

#######################################
# @description Return success when running on a Windows-compatible environment
#   such as Cygwin, MSYS, or MinGW.
#######################################
# @noargs
function dybatpho::is_windows {
  local platform
  platform=$(dybatpho::platform)
  [[ "${platform}" == "windows" ]]
}

#######################################
# @description Return the path of the first installed command.
# @arg $@ string Commands to check
# @stdout Path of the first available command
# @exitcode 1 None of the commands is installed
#######################################
function dybatpho::command_path {
  (($# > 0)) || return 1
  local command_name path
  for command_name in "$@"; do
    path="$(command -v "${command_name}" 2> /dev/null || true)"
    if [[ -n "${path}" ]]; then
      printf '%s\n' "${path}"
      return 0
    fi
  done
  return 1
}

# Pattern that finds a version inside the noise a command prints when asked for
# one. It lives in this core module because `dybatpho::command_version` needs it
# and `semver.sh` reuses it: `semver` is optional, so the shared constant has to
# sit on the side of the registry that is always loaded.
#
# A candidate has to carry at least one dot. `zstd --version` opens with
# `*** zstd command line interface 64-bits v1.5.5`, and a pattern that accepted
# a bare run of digits would answer `64`. The leftmost dotted run is the version
# in every tool output this was checked against.
# @env DYBATPHO_VERSION_SCAN_REGEX string Pattern matching a version inside arbitrary text
export DYBATPHO_VERSION_SCAN_REGEX='v?([0-9]+\.[0-9]+(\.[0-9]+)*)(-([0-9A-Za-z.-]+))?'

#######################################
# @description Print the version a command reports.
#   The command is asked with `--version`, `-version`, `version`, and `-V`, in
#   that order, until one of them prints something a version can be read out of.
#   Both output streams are read, because a good number of tools answer on
#   standard error, and standard input is closed so that a command that would
#   otherwise wait for input cannot hang the script.
#
#   Detection is best effort: it reports what the command says about itself,
#   which is not always what a package manager calls the same build.
# @example
#   dybatpho::command_version git   # 2.43.0
#   dybatpho::command_version tar   # 1.35
#
# @arg $1 string Command to ask
# @stdout The version as the command writes it, without a leading `v`
# @exitcode 0 A version was found
# @exitcode 1 The command is not installed, or none of the probes revealed a version
# @see
#   - `dybatpho::semver_satisfies`
#   - `dybatpho::require`
#######################################
function dybatpho::command_version {
  local command_name
  dybatpho::expect_args command_name -- "$@"
  dybatpho::is command "${command_name}" || return 1
  local flag output
  for flag in --version -version version -V; do
    # A probe that fails is ordinary: only one of these flags is the right one,
    # and the rest usually exit non-zero after printing a usage message.
    output="$(command "${command_name}" "${flag}" 2>&1 < /dev/null || true)"
    [[ -n "${output}" ]] || continue
    if [[ "${output}" =~ ${DYBATPHO_VERSION_SCAN_REGEX} ]]; then
      printf '%s\n' "${BASH_REMATCH[0]#v}"
      return 0
    fi
  done
  return 1
}

#######################################
# @description Get $GOARCH compilation environment
# @noargs
# @stdout Return $GOOS value https://go.dev/docs/install/source#environment
#######################################
function dybatpho::goarch {
  local arch
  arch="$(uname -m)"
  local goarch
  case "${arch}" in
    aarch64) goarch="arm64" ;;
    armv*) goarch="arm" ;;
    i386) goarch="386" ;;
    i686) goarch="386" ;;
    i86pc) goarch="amd64" ;;
    x86) goarch="386" ;;
    x86_64) goarch="amd64" ;;
    *) goarch="${arch}" ;;
  esac
  printf '%s' "${goarch}"
}

#######################################
# @description Print the host name of the machine.
#   The answer is resolved once and cached for the lifetime of the shell,
#   because it cannot change under a running script and every structured log
#   event asks for it.
# @noargs
# @example
#   dybatpho::info "Deploying from $(dybatpho::hostname)"
#
# @stdout Host name, or `unknown` when nothing can answer
# @env DYBATPHO_HOSTNAME string Host name to use instead of detecting one
#######################################
function dybatpho::hostname {
  if [[ -z "${__dybatpho_os_hostname}" ]]; then
    local name="${DYBATPHO_HOSTNAME:-}"
    if [[ -z "${name}" ]] && dybatpho::is command hostname; then
      name="$(hostname 2> /dev/null || true)"
    fi
    if [[ -z "${name}" ]]; then
      name="$(uname -n 2> /dev/null || true)"
    fi
    # A container image often carries neither `hostname` nor a `uname` that
    # answers `-n`, but the kernel always publishes the name on Linux.
    if [[ -z "${name}" && -r /proc/sys/kernel/hostname ]]; then
      name="$(cat /proc/sys/kernel/hostname 2> /dev/null || true)" # kcov(skip) - needs a host without hostname(1)
    fi
    __dybatpho_os_hostname="${name:-${HOSTNAME:-unknown}}"
  fi
  printf '%s\n' "${__dybatpho_os_hostname}"
}

#######################################
# @description Print the name of the user the script runs as.
#   This is the effective user, so a script under `sudo` reports `root` rather
#   than the account that called it.
# @noargs
# @stdout User name, or `unknown` when nothing can answer
#######################################
function dybatpho::user {
  local name
  name="$(id -un 2> /dev/null || true)"
  [[ -n "${name}" ]] || name="${USER:-${LOGNAME:-unknown}}" # kcov(skip) - needs a host without id(1)
  printf '%s\n' "${name}"
}

#######################################
# @description Return success when the script runs as the superuser.
# @noargs
# @example
#   dybatpho::is_root || dybatpho::die "Run this with sudo"
#
# @exitcode 0 The effective user is root
# @exitcode 1 The effective user is anybody else
#######################################
function dybatpho::is_root {
  local id
  id=$(id -u)
  [[ "${EUID:-${id}}" -eq 0 ]]
}

#######################################
# @description Print the kernel release of the host.
# @noargs
# @stdout Kernel release, such as `6.12.4-arch1-1`
# @exitcode 1 The kernel release cannot be determined
#######################################
function dybatpho::kernel_version {
  local release
  release="$(uname -r 2> /dev/null || true)"
  [[ -n "${release}" ]] || return 1
  printf '%s\n' "${release}"
}

#######################################
# @description Print how many processors the host can run work on.
#   The count is reported rather than defaulted, so that a caller decides for
#   itself what to do on a host that cannot answer.
# @noargs
# @example
#   jobs="$(dybatpho::cpu_count || printf '4')"
#
# @stdout Number of online processors
# @exitcode 1 No available command reports a usable count
#######################################
function dybatpho::cpu_count {
  local count=""
  local -a probes=(
    "nproc"
    # BSD and macOS.
    "sysctl -n hw.ncpu"
    # The POSIX spelling, which BusyBox and Solaris answer.
    "getconf _NPROCESSORS_ONLN"
  )
  local probe
  for probe in "${probes[@]}"; do
    dybatpho::is command "${probe%% *}" || continue
    count="$(${probe} 2> /dev/null || true)"
    [[ "${count}" =~ ^[1-9][0-9]*$ ]] && break
    count=""
  done
  [[ -n "${count}" ]] || return 1
  printf '%s\n' "${count}"
}

#######################################
# @description Return success when a standard stream is attached to a terminal.
# @example
#   dybatpho::is_tty stdout && printf 'Colors are worth rendering\n'
#
# @arg $1 string Stream to test, `stdin`, `stdout`, `stderr`, or `0`/`1`/`2`, default is `stdout`
# @exitcode 0 The stream is a terminal
# @exitcode 1 The stream is a file, a pipe, or anything else
#######################################
function dybatpho::is_tty {
  local stream="${1:-stdout}"
  case "${stream}" in
    stdin | 0) [[ -t 0 ]] ;;
    stdout | 1) [[ -t 1 ]] ;;
    stderr | 2) [[ -t 2 ]] ;;
    *) dybatpho::die "${FUNCNAME[0]}: Stream must be stdin, stdout, or stderr, got '${stream}'" ;;
  esac
}

#######################################
# @description Print the width of the terminal in columns.
#   `COLUMNS` is trusted first, because a caller that sets it is deliberately
#   asking for a width, and `tput` is only asked when a terminal is actually
#   attached.
# @arg $1 number Optional width to use when there is no terminal, default is `80`
# @stdout Terminal width in columns
# @exitcode 1 The fallback is not a positive integer
#######################################
function dybatpho::terminal_width {
  __dybatpho_os_terminal_size cols "${COLUMNS:-}" "${1:-80}"
}

#######################################
# @description Print the height of the terminal in lines.
# @arg $1 number Optional height to use when there is no terminal, default is `24`
# @stdout Terminal height in lines
# @exitcode 1 The fallback is not a positive integer
#######################################
function dybatpho::terminal_height {
  __dybatpho_os_terminal_size lines "${LINES:-}" "${1:-24}"
}

#######################################
# @description Resolve one terminal dimension from the environment, `tput`, or a
#   fallback, in that order.
# @arg $1 string `tput` capability, `cols` or `lines`
# @arg $2 string Value of the environment variable that describes the dimension
# @arg $3 number Fallback used when neither answers
# @stdout The dimension
# @exitcode 1 The fallback is not a positive integer
#######################################
function __dybatpho_os_terminal_size {
  local capability="$1" size="$2" fallback="$3"
  [[ "${fallback}" =~ ^[1-9][0-9]*$ ]] \
    || dybatpho::die "${FUNCNAME[1]}: Fallback must be a positive integer, got '${fallback}'"
  if ! [[ "${size}" =~ ^[1-9][0-9]*$ ]]; then
    size=""
    if dybatpho::is command tput && { dybatpho::is_tty stdout || dybatpho::is_tty stderr; }; then
      size="$(tput "${capability}" 2> /dev/null || true)" # kcov(skip) - needs a terminal
    fi
  fi
  [[ "${size}" =~ ^[1-9][0-9]*$ ]] || size="${fallback}"
  printf '%s\n' "${size}"
}

#######################################
# @description Print one field of the host's `os-release` file.
# @example
#   dybatpho::os_release PRETTY_NAME
#
# @arg $1 string Field name, such as `ID`, `ID_LIKE`, or `VERSION_ID`
# @stdout Field value, with the quoting of the file removed
# @exitcode 1 There is no `os-release` file, or it has no such field
# @env DYBATPHO_OS_RELEASE string Path of the `os-release` file to read instead of the standard locations
#######################################
function dybatpho::os_release {
  local key
  dybatpho::expect_args key -- "$@"
  local -a files=("${DYBATPHO_OS_RELEASE:-}")
  [[ -n "${files[0]}" ]] || files=(/etc/os-release /usr/lib/os-release)
  local file line value
  for file in "${files[@]}"; do
    [[ -r "${file}" ]] || continue
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ "${line}" == "${key}="* ]] || continue
      value="${line#*=}"
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      printf '%s\n' "${value}"
      return 0
    done < "${file}"
  done
  return 1
}

#######################################
# @description Print the distribution the host runs.
#   macOS has no `os-release`, so it answers `macos`; a Linux host answers with
#   the `ID` field, such as `ubuntu`, `debian`, `arch`, or `alpine`.
# @noargs
# @example
#   case "$(dybatpho::distro)" in
#     ubuntu | debian) dybatpho::info "Using apt" ;;
#   esac
#
# @stdout Distribution identifier, falling back to the normalized platform name
# @tip Match on `ID_LIKE` through `dybatpho::os_release` when a whole family
#   should be treated alike, because a derivative such as Linux Mint reports its
#   own `ID`
#######################################
function dybatpho::distro {
  local platform
  platform="$(dybatpho::platform)"
  if [[ "${platform}" == "darwin" ]]; then
    printf '%s\n' "macos"
    return 0
  fi
  local id
  if id="$(dybatpho::os_release ID)" && [[ -n "${id}" ]]; then
    dybatpho::lower "${id}"
    return 0
  fi
  printf '%s\n' "${platform}"
}

#######################################
# @description Print the version of the distribution the host runs.
# @noargs
# @stdout Distribution version, such as `24.04` or `15.1`
# @exitcode 1 The version cannot be determined, as on a rolling release that publishes none
#######################################
function dybatpho::distro_version {
  local platform
  platform=$(dybatpho::platform)
  if [[ "${platform}" == "darwin" ]]; then
    local product
    product="$(sw_vers -productVersion 2> /dev/null || true)"
    [[ -n "${product}" ]] || return 1
    printf '%s\n' "${product}"
    return 0
  fi
  local version
  version="$(dybatpho::os_release VERSION_ID)" || version="$(dybatpho::os_release BUILD_ID)" || return 1
  [[ -n "${version}" ]] || return 1
  printf '%s\n' "${version}"
}

#######################################
# @description Return success when the script runs inside a container.
# @noargs
# @exitcode 0 Docker, Podman, Kubernetes, or LXC owns this process
# @exitcode 1 The script runs on the host
#######################################
function dybatpho::is_container {
  # Docker and Podman both drop a marker file, and a runtime started by systemd
  # exports `container`. Kubernetes injects its service host into every pod.
  [[ -f /.dockerenv || -f /run/.containerenv ]] && return 0
  [[ -n "${container:-}" || -n "${KUBERNETES_SERVICE_HOST:-}" ]] && return 0
  # Nothing above is guaranteed, so the control groups of PID 1 are the last
  # word: in a container they name the runtime that created them.
  local line
  if [[ -r /proc/1/cgroup ]]; then
    while IFS= read -r line; do
      case "${line}" in
        *docker* | *containerd* | *kubepods* | *libpod* | *lxc*) return 0 ;;
        *) ;;
      esac
    done < /proc/1/cgroup
  fi
  return 1
}

#######################################
# @description Return success when the script runs under the Windows Subsystem
#   for Linux.
# @noargs
# @exitcode 0 The host is WSL
# @exitcode 1 The host is anything else
#######################################
function dybatpho::is_wsl {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  local release=""
  [[ ! -r /proc/sys/kernel/osrelease ]] || release="$(cat /proc/sys/kernel/osrelease 2> /dev/null || true)"
  local lower
  lower=$(dybatpho::lower "${release}")
  [[ "${lower}" == *microsoft* ]]
}

#######################################
# @description Return success when the script runs on a continuous integration
#   service.
#   `CI` decides whenever it is set, in either direction. Every service sets it,
#   and it is also the one variable a caller can set themselves, so `CI=false`
#   turns the detection off even on a runner that advertises itself by name.
#   The service-specific variables are consulted only when `CI` is unset or
#   empty, which is the case they are there for.
# @noargs
# @example
#   dybatpho::is_ci && export DYBATPHO_FORCE=true
#
# @example
#   # Run a CI-aware script as if it were a workstation.
#   CI=false ./deploy.sh
#
# @env CI string Set to a false value to say the script is not on CI, whatever else the environment advertises
# @exitcode 0 `CI` holds a value other than `false`, `0`, or `no`; or `CI` is unset and a service names itself
# @exitcode 1 `CI` holds a false value, or nothing in the environment names a CI service
#######################################
function dybatpho::is_ci {
  # `CI` is the convention every service follows, so when it says anything at
  # all it is the answer. Reading it as just another entry in the list below
  # meant a false value only skipped to the next name: on a runner that also
  # sets `GITHUB_ACTIONS`, `CI=false` still detected CI, and the one way a
  # caller had to turn the detection off did nothing.
  if [[ -n "${CI:-}" ]]; then
    case "$(dybatpho::lower "${CI}")" in
      false | 0 | no) return 1 ;;
      *) return 0 ;;
    esac
  fi

  # The rest of the list exists only for services that set their own name and
  # never set `CI`, so it is consulted only once `CI` has said nothing.
  local variable value
  for variable in GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILDKITE CIRCLECI TRAVIS TEAMCITY_VERSION TF_BUILD; do
    value="${!variable:-}"
    [[ -n "${value}" ]] || continue
    case "$(dybatpho::lower "${value}")" in
      false | 0 | no) continue ;;
      *) return 0 ;;
    esac
  done
  return 1
}
