setup() {
  load test_helper
}

@test "dybatpho::goos linux" {
  stub uname ": echo 'Linux'" ": echo 'GNU/Linux'"
  assert_equal "$(dybatpho::goos)" "linux"
  unstub uname
}

@test "dybatpho::goos android" {
  stub uname ": echo 'Linux'" ": echo 'Android'"
  assert_equal "$(dybatpho::goos)" "android"
  unstub uname
}

@test "dybatpho::goos cygwin" {
  stub uname ": echo 'CYGWIN_NT-6.1-WOW64'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos mingw" {
  stub uname ": echo 'MINGW64_NT-10.0-22631'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos msys" {
  stub uname ": echo 'MSYS_NT-6.1'"
  assert_equal "$(dybatpho::goos)" "windows"
  unstub uname
}

@test "dybatpho::goos macos" {
  stub uname ": echo 'Darwin'"
  assert_equal "$(dybatpho::goos)" "darwin"
  unstub uname
}

@test "dybatpho::platform aliases normalized operating system" {
  stub uname ": echo 'Darwin'"
  assert_equal "$(dybatpho::platform)" "darwin"
  unstub uname
}

@test "dybatpho::command_path returns the first available command" {
  assert_equal "$(dybatpho::command_path command-that-does-not-exist sh)" "$(command -v sh)"
}

@test "dybatpho::command_path fails without arguments or matches" {
  run_traced ! dybatpho::command_path
  run_traced ! dybatpho::command_path command-that-does-not-exist another-missing-command
}

@test "dybatpho::is_linux detects a Linux platform" {
  stub_repeated uname ": echo 'Linux'"
  dybatpho::is_linux
  run_traced ! dybatpho::is_macos
}

@test "dybatpho::is_macos detects a macOS platform" {
  stub_repeated uname ": echo 'Darwin'"
  dybatpho::is_macos
  run_traced ! dybatpho::is_linux
}

@test "dybatpho::goarch arm64" {
  stub uname ": echo 'aarch64'"
  assert_equal "$(dybatpho::goarch)" "arm64"
  unstub uname
}

@test "dybatpho::goarch armv7" {
  stub uname ": echo 'armv7'"
  assert_equal "$(dybatpho::goarch)" "arm"
  unstub uname
}

@test "dybatpho::goarch i386" {
  stub uname ": echo 'i386'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch i686" {
  stub uname ": echo 'i686'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch x86" {
  stub uname ": echo 'x86'"
  assert_equal "$(dybatpho::goarch)" "386"
  unstub uname
}

@test "dybatpho::goarch i86pc" {
  stub uname ": echo 'i86pc'"
  assert_equal "$(dybatpho::goarch)" "amd64"
  unstub uname
}

@test "dybatpho::goarch x86_64" {
  stub uname ": echo 'x86_64'"
  assert_equal "$(dybatpho::goarch)" "amd64"
  unstub uname
}

@test "dybatpho::goarch mips64" {
  stub uname ": echo 'mips64'"
  assert_equal "$(dybatpho::goarch)" "mips64"
  unstub uname
}

@test "dybatpho::goarch unknown arch falls back to uname" {
  stub uname ": echo 'riscv64'"
  assert_equal "$(dybatpho::goarch)" "riscv64"
  unstub uname
}

@test "dybatpho::is_windows detects a Windows-compatible platform" {
  stub_repeated uname ": echo 'MINGW64_NT-10.0-22631'"
  dybatpho::is_windows
  run_traced ! dybatpho::is_linux
}

# ---------------------------------------------------------------------------
# host identity
# ---------------------------------------------------------------------------

# Run statements in a fresh shell. The child is written to a file and run from
# it rather than through `bash -c`, because a `-c` shell has an empty
# BASH_SOURCE, which the coverage hook expands on every command and strict mode
# then turns into a failure that only shows up under scripts/test.sh.
_child() {
  local script="${BATS_TEST_TMPDIR}/child.sh"
  {
    printf '. "%s/init.sh"\n' "${DYBATPHO_DIR}"
    printf '%s\n' "$@"
  } > "${script}"
  bash "${script}"
}

@test "dybatpho::hostname prefers an explicit host name and caches it" {
  __dybatpho_os_hostname=""
  DYBATPHO_HOSTNAME="build-box" run -0 dybatpho::hostname
  assert_output "build-box"
  # Once resolved, the answer is the cached one: the override is no longer read.
  DYBATPHO_HOSTNAME="build-box" dybatpho::hostname > /dev/null
  assert_equal "$(dybatpho::hostname)" "build-box"
  __dybatpho_os_hostname=""
}

@test "dybatpho::hostname falls back to uname when hostname is missing" {
  local bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin}"
  # `/bin/sh` rather than `env bash`, because the narrowed PATH below cannot
  # find `bash` for `env` to run.
  printf '#!/bin/sh\nprintf "from-uname\\n"\n' > "${bin}/uname"
  chmod +x "${bin}/uname"
  # A PATH with neither `hostname` nor anything else on it, set after the
  # library is loaded so that only the detection sees it.
  # `hash -r` drops the paths bash remembered while the library loaded, so the
  # narrowed PATH is what the detection actually sees.
  run_traced -0 _child "unset DYBATPHO_HOSTNAME" "PATH='${bin}'" "hash -r" "dybatpho::hostname"
  assert_output "from-uname"
}

@test "dybatpho::hostname returns a non-empty name on this host" {
  __dybatpho_os_hostname=""
  run_traced -0 dybatpho::hostname
  refute_output ""
  __dybatpho_os_hostname=""
}

@test "dybatpho::user reports the effective user" {
  run_traced -0 dybatpho::user
  assert_output "$(id -un)"
}

@test "dybatpho::is_root follows the effective user id" {
  if [[ "${EUID}" -eq 0 ]]; then
    dybatpho::is_root
  else
    run_traced ! dybatpho::is_root
  fi
}

@test "dybatpho::kernel_version reports the kernel release" {
  stub uname ": echo '6.12.4-arch1-1'"
  assert_equal "$(dybatpho::kernel_version)" "6.12.4-arch1-1"
  unstub uname
}

# ---------------------------------------------------------------------------
# processors and terminal
# ---------------------------------------------------------------------------

@test "dybatpho::cpu_count reports a positive number of processors" {
  run_traced -0 dybatpho::cpu_count
  assert_equal "${output}" "$(printf '%s' "${output}")"
  [[ "${output}" =~ ^[1-9][0-9]*$ ]]
}

@test "dybatpho::cpu_count prefers nproc and validates what it reports" {
  stub_repeated nproc ": echo 7"
  assert_equal "$(dybatpho::cpu_count)" 7
}

@test "dybatpho::cpu_count fails when no probe can answer" {
  PATH="" run ! dybatpho::cpu_count
  assert_output ""
}

@test "dybatpho::is_tty is false for the captured streams of a test" {
  run_traced ! dybatpho::is_tty stdin
  run_traced ! dybatpho::is_tty stdout
  run_traced ! dybatpho::is_tty stderr
  run_traced ! dybatpho::is_tty 1
}

@test "dybatpho::is_tty rejects a stream it does not know" {
  run ! dybatpho::is_tty sideways
  assert_output --partial "Stream must be stdin, stdout, or stderr"
}

@test "dybatpho::terminal_width trusts COLUMNS" {
  COLUMNS=120 run -0 dybatpho::terminal_width
  assert_output "120"
}

@test "dybatpho::terminal_width falls back when COLUMNS is unusable" {
  COLUMNS=not-a-number run -0 dybatpho::terminal_width
  assert_output "80"
  COLUMNS=0 run -0 dybatpho::terminal_width 100
  assert_output "100"
}

@test "dybatpho::terminal_width rejects a fallback that is not a count" {
  COLUMNS="" run ! dybatpho::terminal_width wide
  assert_output --partial "Fallback must be a positive integer"
}

@test "dybatpho::terminal_height trusts LINES and falls back to 24" {
  LINES=48 run -0 dybatpho::terminal_height
  assert_output "48"
  LINES="" run -0 dybatpho::terminal_height
  assert_output "24"
}

# ---------------------------------------------------------------------------
# distribution
# ---------------------------------------------------------------------------

_os_release() {
  local file="${BATS_TEST_TMPDIR}/os-release"
  printf '%s\n' "$@" > "${file}"
  export DYBATPHO_OS_RELEASE="${file}"
}

@test "dybatpho::os_release reads a field and strips its quoting" {
  _os_release 'ID=ubuntu' 'VERSION_ID="24.04"' "PRETTY_NAME='Ubuntu 24.04 LTS'"
  assert_equal "$(dybatpho::os_release ID)" "ubuntu"
  assert_equal "$(dybatpho::os_release VERSION_ID)" "24.04"
  assert_equal "$(dybatpho::os_release PRETTY_NAME)" "Ubuntu 24.04 LTS"
}

@test "dybatpho::os_release fails for a field the file does not carry" {
  _os_release 'ID=ubuntu'
  run_traced ! dybatpho::os_release VARIANT_ID
  assert_output ""
}

@test "dybatpho::os_release fails when there is no os-release file" {
  DYBATPHO_OS_RELEASE="${BATS_TEST_TMPDIR}/absent" run ! dybatpho::os_release ID
}

@test "dybatpho::distro reports the distribution of a Linux host" {
  _os_release 'ID=Debian' 'VERSION_ID="12"'
  stub_repeated uname ": echo 'Linux'"
  assert_equal "$(dybatpho::distro)" "debian"
  assert_equal "$(dybatpho::distro_version)" "12"
}

@test "dybatpho::distro falls back to the platform without an os-release file" {
  export DYBATPHO_OS_RELEASE="${BATS_TEST_TMPDIR}/absent"
  stub_repeated uname ": echo 'Linux'"
  assert_equal "$(dybatpho::distro)" "linux"
  run_traced ! dybatpho::distro_version
}

@test "dybatpho::distro_version accepts a rolling release with only a build id" {
  _os_release 'ID=arch' 'BUILD_ID=rolling'
  stub_repeated uname ": echo 'Linux'"
  assert_equal "$(dybatpho::distro_version)" "rolling"
}

@test "dybatpho::distro answers macos on Darwin" {
  stub_repeated uname ": echo 'Darwin'"
  stub_repeated sw_vers ": echo '15.1'"
  assert_equal "$(dybatpho::distro)" "macos"
  assert_equal "$(dybatpho::distro_version)" "15.1"
}

# ---------------------------------------------------------------------------
# environment predicates
# ---------------------------------------------------------------------------

@test "dybatpho::is_container detects a runtime that exports its name" {
  container=podman run -0 dybatpho::is_container
  KUBERNETES_SERVICE_HOST=10.0.0.1 run -0 dybatpho::is_container
}

@test "dybatpho::is_wsl reads the interop variables of the subsystem" {
  WSL_DISTRO_NAME=Ubuntu run -0 dybatpho::is_wsl
  WSL_INTEROP=/run/WSL/1 run -0 dybatpho::is_wsl
}

# Put a command on PATH that answers a version probe however the test wants.
# `$1` is the command, `$2` the flag it answers to, `$3` what it prints; any
# other flag exits non-zero without output, the way a real tool does.
fake_tool() {
  local dir="${BATS_TEST_TMPDIR}/probe_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\n[[ "$1" == %q ]] || exit 1\nprintf "%%s\\n" %q\n' "$2" "$3" \
    > "${dir}/$1"
  chmod +x "${dir}/$1"
  PATH="${dir}:${PATH}"
}

@test "dybatpho::command_version reads the version a command prints" {
  fake_tool faketool --version "faketool 2.4.1"
  assert_equal "$(dybatpho::command_version faketool)" "2.4.1"
}

@test "dybatpho::command_version finds the version among the rest of the output" {
  fake_tool faketool --version "yq (https://github.com/mikefarah/yq/) version v4.53.3"
  assert_equal "$(dybatpho::command_version faketool)" "4.53.3"
}

@test "dybatpho::command_version falls back to the other probes" {
  # Go and Docker style tools answer a `version` subcommand, not a flag.
  fake_tool faketool version "faketool version 1.21.5"
  assert_equal "$(dybatpho::command_version faketool)" "1.21.5"
}

@test "dybatpho::command_version reads a version printed on standard error" {
  local dir="${BATS_TEST_TMPDIR}/probe_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\nprintf "noisy 3.2.1\\n" >&2\n' > "${dir}/faketool"
  chmod +x "${dir}/faketool"
  PATH="${dir}:${PATH}"
  assert_equal "$(dybatpho::command_version faketool)" "3.2.1"
}

@test "dybatpho::command_version fails on a command that reveals no version" {
  local dir="${BATS_TEST_TMPDIR}/probe_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${dir}/faketool"
  chmod +x "${dir}/faketool"
  PATH="${dir}:${PATH}"
  run_traced ! dybatpho::command_version faketool
  assert_output ""
}

@test "dybatpho::command_version fails on a command that is not installed" {
  run_traced ! dybatpho::command_version dyfoooo
  assert_output ""
}

@test "dybatpho::command_version does not hang on a command that reads stdin" {
  # Standard input is closed for the probe, so a tool that would otherwise wait
  # for input returns instead of stalling the script.
  local dir="${BATS_TEST_TMPDIR}/probe_bin"
  mkdir -p "${dir}"
  printf '#!/usr/bin/env bash\ncat\n' > "${dir}/faketool"
  chmod +x "${dir}/faketool"
  PATH="${dir}:${PATH}"
  run_traced ! dybatpho::command_version faketool
}

@test "dybatpho::command_version reads the version of a real command" {
  # `BASH_VERSION` is `5.2.21(1)-release`, and the version is what comes before
  # the patch-level parenthesis.
  assert_equal "$(dybatpho::command_version bash)" "${BASH_VERSION%%(*}"
}

@test "dybatpho::is_ci lets CI overrule a service that names itself" {
  # The case that turned CI red: a runner sets both `CI` and its own name, so
  # reading `CI=false` as merely "skip to the next variable" left the detection
  # on. The environment here is pinned rather than inherited, so this says the
  # same thing whether the suite runs on a workstation or on a runner.
  CI=false GITHUB_ACTIONS=true run ! dybatpho::is_ci
  CI=0 GITHUB_ACTIONS=true run ! dybatpho::is_ci
  CI=no GITHUB_ACTIONS=true run ! dybatpho::is_ci
  CI=FALSE GITHUB_ACTIONS=true run ! dybatpho::is_ci
  CI=true GITHUB_ACTIONS=false run -0 dybatpho::is_ci
}

@test "dybatpho::is_ci falls back to a service name only when CI says nothing" {
  # `_child` inherits this shell's environment, and the suite itself may be
  # running on a service, so every marker is cleared before one is set back.
  local clean="unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILDKITE CIRCLECI TRAVIS TEAMCITY_VERSION TF_BUILD"
  run_traced ! _child "${clean}" "export GITHUB_ACTIONS=false" "dybatpho::is_ci"
  run_traced -0 _child "${clean}" "export GITHUB_ACTIONS=true" "dybatpho::is_ci"
  run_traced -0 _child "${clean}" "export GITLAB_CI=true" "dybatpho::is_ci"
  # An empty `CI` is not an answer either way, so the fallback still applies.
  run_traced -0 _child "${clean}" "export CI=''; export GITLAB_CI=true" "dybatpho::is_ci"
  run_traced ! _child "${clean}" "export CI=''; export GITLAB_CI=false" "dybatpho::is_ci"
}

@test "dybatpho::is_ci recognizes a service and honors a disabled one" {
  CI=true run -0 dybatpho::is_ci
  GITHUB_ACTIONS=true run -0 dybatpho::is_ci
  # A service that sets `CI=false` means it, and nothing else is consulted for
  # it -- the suite itself runs on CI, so the negative case needs a clean shell.
  CI=false run ! dybatpho::is_ci
  run_traced ! _child \
    "unset CI GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILDKITE CIRCLECI TRAVIS TEAMCITY_VERSION TF_BUILD" \
    "dybatpho::is_ci"
}
