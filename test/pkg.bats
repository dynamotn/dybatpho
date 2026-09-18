setup() {
  load test_helper
  export DYBATPHO_PKG_MANAGER=""
  export DYBATPHO_PKG_SUDO=false
  export DYBATPHO_PKG_ASSUME_YES=true
  export DYBATPHO_FORCE=false
  export DYBATPHO_INTERACTIVE=false
  export DRY_RUN=""
}

@test "dybatpho::pkg_supported lists every supported manager" {
  run -0 dybatpho::pkg_supported
  assert_line "apt"
  assert_line "brew"
  assert_line "apk"
  assert_line "dnf"
  assert_line "pacman"
  assert_line "emerge"
  assert_equal "${#lines[@]}" 6
}

@test "dybatpho::pkg_manager honors the DYBATPHO_PKG_MANAGER override" {
  DYBATPHO_PKG_MANAGER=pacman
  assert_equal "$(dybatpho::pkg_manager)" "pacman"
}

@test "dybatpho::pkg_manager rejects an unsupported override" {
  DYBATPHO_PKG_MANAGER=yum
  run ! dybatpho::pkg_manager
  assert_output --partial "unsupported package manager 'yum'"
}

@test "dybatpho::pkg_manager prefers the distribution manager over brew on Linux" {
  stub_repeated uname ": echo 'Linux'"
  stub_repeated apt-get ": true"
  stub_repeated brew ": true"
  assert_equal "$(dybatpho::pkg_manager)" "apt"
  unstub uname
}

@test "dybatpho::pkg_manager detects brew on macOS" {
  stub_repeated uname ": echo 'Darwin'"
  stub_repeated brew ": true"
  assert_equal "$(dybatpho::pkg_manager)" "brew"
  unstub uname
}

@test "dybatpho::pkg_manager fails when no supported manager is installed" {
  stub_repeated uname ": echo 'Linux'"
  PATH="${BATS_MOCK_BINDIR}" run ! dybatpho::pkg_manager
}

@test "dybatpho::pkg_manager_available reports a missing manager" {
  PATH="${BATS_MOCK_BINDIR}" run ! dybatpho::pkg_manager_available emerge
  stub_repeated emerge ": true"
  dybatpho::pkg_manager_available emerge
}

@test "dybatpho::pkg_install_command renders apt with a non-interactive frontend" {
  DYBATPHO_PKG_MANAGER=apt
  assert_equal "$(dybatpho::pkg_install_command ripgrep fd-find)" \
    "env DEBIAN_FRONTEND=noninteractive apt-get install -y ripgrep fd-find"
}

@test "dybatpho::pkg_install_command renders every supported manager" {
  DYBATPHO_PKG_MANAGER=brew
  assert_equal "$(dybatpho::pkg_install_command jq)" "brew install jq"
  DYBATPHO_PKG_MANAGER=apk
  assert_equal "$(dybatpho::pkg_install_command jq)" "apk add jq"
  DYBATPHO_PKG_MANAGER=dnf
  assert_equal "$(dybatpho::pkg_install_command jq)" "dnf install -y jq"
  DYBATPHO_PKG_MANAGER=pacman
  assert_equal "$(dybatpho::pkg_install_command jq)" "pacman -S --needed --noconfirm jq"
  DYBATPHO_PKG_MANAGER=emerge
  assert_equal "$(dybatpho::pkg_install_command jq)" "emerge --noreplace --ask=n jq"
}

@test "dybatpho::pkg_install_command drops the assume-yes flags on request" {
  DYBATPHO_PKG_MANAGER=dnf
  DYBATPHO_PKG_ASSUME_YES=false
  assert_equal "$(dybatpho::pkg_install_command jq)" "dnf install jq"
}

@test "dybatpho::pkg_install_command elevates with sudo but never for brew" {
  DYBATPHO_PKG_SUDO=true
  DYBATPHO_PKG_MANAGER=pacman
  assert_equal "$(dybatpho::pkg_install_command jq)" "sudo pacman -S --needed --noconfirm jq"
  DYBATPHO_PKG_MANAGER=brew
  assert_equal "$(dybatpho::pkg_install_command jq)" "brew install jq"
}

@test "dybatpho::pkg_install_command needs at least one package" {
  DYBATPHO_PKG_MANAGER=apk
  run ! dybatpho::pkg_install_command
  assert_output --partial "expected at least one package"
}

@test "dybatpho::pkg_name resolves a per-manager override" {
  DYBATPHO_PKG_MANAGER=apt
  assert_equal "$(dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd)" "fd-find"
  DYBATPHO_PKG_MANAGER=pacman
  assert_equal "$(dybatpho::pkg_name fd apt:fd-find emerge:sys-apps/fd)" "fd"
}

@test "dybatpho::pkg_name rejects a malformed override" {
  DYBATPHO_PKG_MANAGER=apt
  run ! dybatpho::pkg_name fd fd-find
  assert_output --partial "expected <manager>:<package>"
}

@test "dybatpho::pkg_installed reads dpkg-query status on apt" {
  DYBATPHO_PKG_MANAGER=apt
  stub dpkg-query ": echo 'install ok installed'"
  dybatpho::pkg_installed curl
  unstub dpkg-query
  stub dpkg-query ": echo 'deinstall ok config-files'"
  run ! dybatpho::pkg_installed curl
  unstub dpkg-query
}

@test "dybatpho::pkg_installed treats empty apk output as missing" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk ": echo 'curl-8.5.0-r0'"
  dybatpho::pkg_installed curl
  unstub apk
  stub apk ": true"
  run ! dybatpho::pkg_installed curl
  unstub apk
}

@test "dybatpho::pkg_installed queries rpm on dnf and pacman on pacman" {
  DYBATPHO_PKG_MANAGER=dnf
  stub rpm ": true"
  dybatpho::pkg_installed curl
  unstub rpm
  DYBATPHO_PKG_MANAGER=pacman
  stub pacman ": exit 1"
  run ! dybatpho::pkg_installed curl
  unstub pacman
}

@test "dybatpho::pkg_installed uses qlist on emerge" {
  DYBATPHO_PKG_MANAGER=emerge
  stub_repeated qlist ": echo 'net-misc/curl-8.5.0'"
  dybatpho::pkg_installed net-misc/curl
}

@test "dybatpho::pkg_missing prints only the packages that are absent" {
  DYBATPHO_PKG_MANAGER=pacman
  stub_repeated pacman ": [ \"\${3:-}\" = curl ]"
  run -0 dybatpho::pkg_missing curl jq
  assert_output "jq"
}

@test "dybatpho::pkg_install prints the command under --dry-run without touching the system" {
  DYBATPHO_PKG_MANAGER=apk
  run -0 dybatpho::pkg_install --dry-run ripgrep
  assert_output --partial "DRY RUN: apk add ripgrep"
}

@test "dybatpho::pkg_install honors the DRY_RUN environment variable" {
  DYBATPHO_PKG_MANAGER=apk
  DRY_RUN=true run -0 dybatpho::pkg_install ripgrep
  assert_output --partial "DRY RUN: apk add ripgrep"
}

@test "dybatpho::pkg_install refuses without --force in a non-interactive shell" {
  DYBATPHO_PKG_MANAGER=apk
  stub_repeated apk ": echo 'apk should not run'"
  run ! dybatpho::pkg_install ripgrep
  assert_output --partial "Skipped install of: ripgrep"
  refute_output --partial "apk should not run"
}

@test "dybatpho::pkg_install runs the manager with --force" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk "add ripgrep : echo 'installed ripgrep'"
  run -0 dybatpho::pkg_install --force ripgrep
  assert_output --partial "installed ripgrep"
  unstub apk
}

@test "dybatpho::pkg_install accepts DYBATPHO_FORCE instead of the flag" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk "add ripgrep : echo 'installed ripgrep'"
  DYBATPHO_FORCE=true run -0 dybatpho::pkg_install ripgrep
  assert_output --partial "installed ripgrep"
  unstub apk
}

@test "dybatpho::pkg_install refreshes the index first with --update" {
  DYBATPHO_PKG_MANAGER=apk
  run -0 dybatpho::pkg_install --dry-run --update -- ripgrep
  assert_output --partial "DRY RUN: apk update"
  assert_output --partial "DRY RUN: apk add ripgrep"
}

@test "dybatpho::pkg_install reports the failure of the package manager" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk "add ripgrep : exit 3"
  run -3 dybatpho::pkg_install --force ripgrep
  unstub apk
}

@test "dybatpho::pkg_install rejects an unknown option and an empty package list" {
  DYBATPHO_PKG_MANAGER=apk
  run ! dybatpho::pkg_install --nope ripgrep
  assert_output --partial "unknown option: --nope"
  run ! dybatpho::pkg_install --force
  assert_output --partial "expected at least one package"
}

@test "dybatpho::pkg_install passes a package that looks like an option after --" {
  DYBATPHO_PKG_MANAGER=apk
  run -0 dybatpho::pkg_install --dry-run -- --weird-name
  assert_output --partial "DRY RUN: apk add --weird-name"
}

@test "dybatpho::pkg_update asks before refreshing the index" {
  DYBATPHO_PKG_MANAGER=apk
  stub_repeated apk ": echo 'apk should not run'"
  run ! dybatpho::pkg_update
  assert_output --partial "Skipped package index refresh"
  refute_output --partial "apk should not run"
}

@test "dybatpho::pkg_update refreshes with --force" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk "update : echo 'index refreshed'"
  run -0 dybatpho::pkg_update --force
  assert_output --partial "index refreshed"
  unstub apk
}

@test "dybatpho::pkg_ensure skips packages that are already installed" {
  DYBATPHO_PKG_MANAGER=pacman
  stub_repeated pacman ": [ \"\${1:-}\" = -Q ]"
  run -0 dybatpho::pkg_ensure --force curl jq
  refute_output --partial "Installing with"
}

@test "dybatpho::pkg_ensure installs only the missing packages" {
  DYBATPHO_PKG_MANAGER=pacman
  stub_repeated pacman ": if [ \"\${1:-}\" = -Q ]; then [ \"\${3:-}\" = curl ]; else echo \"pacman \$*\"; fi"
  run -0 dybatpho::pkg_ensure --force curl jq
  assert_output --partial "pacman -S --needed --noconfirm jq"
  refute_output --partial "curl"
}

@test "dybatpho::pkg_require does nothing when the command is already available" {
  DYBATPHO_PKG_MANAGER=apk
  stub_repeated apk ": echo 'apk should not run'"
  run -0 dybatpho::pkg_require sh
  refute_output --partial "apk should not run"
}

@test "dybatpho::pkg_require installs the per-manager package name" {
  DYBATPHO_PKG_MANAGER=apt
  run -0 dybatpho::pkg_require --dry-run dybatpho-missing-command \
    apt:dybatpho-debian emerge:app-misc/dybatpho
  assert_output --partial "DRY RUN: env DEBIAN_FRONTEND=noninteractive apt-get install -y dybatpho-debian"
}

@test "dybatpho::pkg_require fails when the command is still missing after the install" {
  DYBATPHO_PKG_MANAGER=apk
  stub apk "add dybatpho-missing-command : true"
  run ! dybatpho::pkg_require --force dybatpho-missing-command
  assert_output --partial "still not available"
  unstub apk
}

@test "dybatpho::pkg_require rejects a call without a command name" {
  DYBATPHO_PKG_MANAGER=apk
  run ! dybatpho::pkg_require --force
  assert_output --partial "expected a command name"
}
