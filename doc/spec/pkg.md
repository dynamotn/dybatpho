# Feature Specification: Package Manager Detection and Guarded Dependency Installation

**Feature Branch**: `[feature-pkg]`
**Status**: Implemented
**Input**: Existing source analysis: `src/pkg.sh`, `doc/pkg.md`, `test/pkg.bats`, and `example/pkg_ops.sh`

## Problem Statement *(mandatory)*

A bootstrap or installer script has to work on whatever machine it lands on. Today every such script reimplements the same three steps: probe for `apt-get`, `brew`, `apk`, `dnf`, `pacman`, or `emerge`; translate a dependency into whatever that manager calls it; then run an install command with the right elevation and non-interactive flags. The reimplementations disagree, and the risky part — changing system state — is usually the least reviewed: scripts install without asking, without a way to preview the command, and fail in confusing ways when neither `sudo` nor a supported manager is present.

## Business Value *(mandatory)*

- One detection contract instead of a hand-rolled `command -v` chain per script.
- Portable dependency installation across Debian, Fedora, Arch, Alpine, Gentoo, and macOS.
- A reviewable change: the exact command is printable before anything runs.
- No unattended system change by accident; an unattended run must say so explicitly.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Detect the machine's package manager (Priority: P1)

As a script author, I want to know which package manager this machine uses so that I can act on it without probing binaries myself.

**Why this priority**: Every other function in the module depends on this answer.

**Independent Test**: Stub `uname` and the manager binaries, then verify the reported manager for a Linux and a macOS machine, and the failure when nothing is installed.

**Acceptance Scenarios**:

1. **Given** a Linux machine with both `apt-get` and `brew` installed, **When** detection runs, **Then** the distribution manager `apt` is reported rather than `brew`
2. **Given** a macOS machine with `brew` installed, **When** detection runs, **Then** `brew` is reported
3. **Given** no supported manager is installed, **When** detection runs, **Then** the function fails instead of printing a guess
4. **Given** `DYBATPHO_PKG_MANAGER` names a supported manager, **When** detection runs, **Then** that manager is reported without probing
5. **Given** `DYBATPHO_PKG_MANAGER` names an unsupported manager, **When** detection runs, **Then** the script stops with a message listing the supported managers

---

### User Story 2 - Check whether a dependency is already there (Priority: P1)

As a script author, I want to ask whether a package is installed, and which of a list is missing, so that I do not reinstall what is already present.

**Why this priority**: Skipping work that is already done is what makes a bootstrap script re-runnable.

**Independent Test**: Stub each manager's query command and verify the installed/missing verdicts, including the managers whose query command succeeds for a missing package.

**Acceptance Scenarios**:

1. **Given** `apt` reports a package status of `install ok installed`, **When** the check runs, **Then** the package counts as installed
2. **Given** `apt` reports a removed package whose configuration files remain, **When** the check runs, **Then** the package counts as missing
3. **Given** `apk info -e` succeeds but prints nothing, **When** the check runs, **Then** the package counts as missing
4. **Given** a list of packages of which one is installed, **When** the missing check runs, **Then** only the absent packages are printed, in the order they were given

---

### User Story 3 - Install a dependency under the right name for this machine (Priority: P1)

As a script author, I want to name a dependency once, with per-manager exceptions, so that the same script installs it on any distribution.

**Why this priority**: Package names are the part that differs most between distributions, and hard-coding one name is what makes a script single-platform.

**Independent Test**: Set each manager in turn and verify the resolved package name and the rendered install command.

**Acceptance Scenarios**:

1. **Given** the overrides `apt:fd-find emerge:sys-apps/fd` and a default of `fd`, **When** the manager is `apt`, **Then** the resolved name is `fd-find`
2. **Given** the same overrides, **When** the manager is `pacman`, **Then** the resolved name falls back to `fd`
3. **Given** an override that is not in `<manager>:<package>` form, **When** resolution runs, **Then** the script stops with a message naming the expected form
4. **Given** a required command that is already available, **When** the require helper runs, **Then** nothing is installed
5. **Given** a required command that is missing, **When** the require helper runs, **Then** the package resolved for this manager is installed

---

### User Story 4 - Preview and confirm before the system changes (Priority: P1)

As an operator, I want to see the exact command first and be asked before it runs, so that an installer cannot change my machine behind my back.

**Why this priority**: These functions are the module's only destructive surface, and an unreviewed `sudo` install is the failure this module exists to prevent.

**Independent Test**: Run an install in dry-run mode and in an unattended shell with a stubbed manager, and verify the manager is never executed in either case.

**Acceptance Scenarios**:

1. **Given** dry-run mode is on through `--dry-run` or `DRY_RUN`, **When** an install runs, **Then** the command is printed and the package manager is not executed
2. **Given** dry-run mode is on, **When** an install runs, **Then** no confirmation is requested, because nothing changes
3. **Given** a non-interactive shell without `--force`, **When** an install runs, **Then** the install is refused and reported as skipped
4. **Given** `--force` or `DYBATPHO_FORCE`, **When** an install runs, **Then** the package manager runs without a prompt
5. **Given** the package manager exits non-zero, **When** an install runs, **Then** the same exit code reaches the caller

---

### Example Workflow

```bash
. dybatpho/init.sh --modules pkg

# What would this do on this machine?
dybatpho::pkg_install_command ripgrep jq

# Review it interactively, then run the same script unattended in CI.
dybatpho::pkg_ensure --update curl jq
dybatpho::pkg_require fd apt:fd-find emerge:sys-apps/fd
```

## Edge Cases

- No supported package manager is installed: detection fails, and the mutating functions stop with a message rather than running an empty command.
- `DYBATPHO_PKG_MANAGER` names a manager that is not installed: the override is honored, so a script can render a command for another distribution without having it.
- Homebrew is installed next to a distribution manager on Linux: the distribution manager wins.
- Homebrew refuses to run under `sudo`, so no elevation prefix is ever added for `brew`.
- The script already runs as root, or `sudo` is not installed: no elevation prefix is added.
- `apt-get` can open a debconf dialog: the install command sets a non-interactive frontend.
- A package name begins with `-`: everything after `--` is treated as a package.
- `emerge` has no built-in installed-package query: `qlist` is used, then `equery`, and the check reports a warning when neither is present.
- Every package in the list is already installed: the ensure helper installs nothing and succeeds.
- A dry-run require leaves the command missing on purpose, which is not reported as a failure.

## Requirements *(mandatory)*

- **FR-001**: The module MUST support exactly `apt`, `brew`, `apk`, `dnf`, `pacman`, and `emerge`, and MUST print that list on request.
- **FR-002**: Detection MUST probe the platform's native managers first, MUST report the distribution manager ahead of `brew` on Linux, and MUST fail rather than guess when none is installed.
- **FR-003**: `DYBATPHO_PKG_MANAGER` MUST override detection, and MUST be rejected when it names an unsupported manager.
- **FR-004**: The installed check MUST use each manager's own query command, and MUST treat a query that succeeds with empty output as "not installed".
- **FR-005**: The missing check MUST print only the absent packages, preserving the order of its arguments.
- **FR-006**: Package name resolution MUST accept `<manager>:<package>` overrides, MUST fall back to the default name when no override matches, and MUST reject a malformed override.
- **FR-007**: The rendered install command MUST include the manager's non-interactive flags unless `DYBATPHO_PKG_ASSUME_YES` is false.
- **FR-008**: The rendered command MUST be prefixed with `sudo` when elevation is needed, MUST never prefix `brew`, and MUST honor `DYBATPHO_PKG_SUDO`.
- **FR-009**: Every mutating function MUST ask for confirmation unless `--force` or `DYBATPHO_FORCE` approves it, and MUST refuse rather than guess in a non-interactive shell.
- **FR-010**: Every mutating function MUST print the command instead of running it under `--dry-run` or `DRY_RUN`, and MUST NOT ask for confirmation in that mode.
- **FR-011**: A declined change MUST report what was skipped and fail, without running the package manager.
- **FR-012**: The exit code of the package manager MUST reach the caller unchanged.
- **FR-013**: The ensure helper MUST install only the packages that are missing, and MUST succeed without installing anything when they are all present.
- **FR-014**: The require helper MUST do nothing when the command is available, MUST install the package resolved for this manager otherwise, and MUST fail when the command is still missing after a real install.
- **FR-015**: Every mutating function MUST treat arguments after `--` as packages, and MUST reject an unknown option and an empty package list.

### Key Entities

- **Package manager**: one of the six supported names, each bound to the binary that proves it is usable (`apt` is driven through `apt-get`).
- **Package name override**: a `<manager>:<package>` pair that redirects one logical dependency to the name a given manager uses.
- **Action command**: the fully rendered command for an `install` or `update` action, including elevation prefix and non-interactive flags.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One script installs the same dependency on Debian, Fedora, Arch, Alpine, Gentoo, and macOS without per-platform branches.
- **SC-002**: The exact command a run would execute is printable before anything changes.
- **SC-003**: No unattended run changes the system unless it asked for `--force`.
- **SC-004**: Re-running a bootstrap script installs nothing when every dependency is already present.

## Integration Tests *(mandatory)*

- **IT-001**: Verify the supported list contains exactly the six managers.
- **IT-002**: Stub `uname` and manager binaries to verify `apt` wins over `brew` on Linux and `brew` is detected on macOS.
- **IT-003**: Verify detection fails when no manager binary is on `PATH`.
- **IT-004**: Verify `DYBATPHO_PKG_MANAGER` is honored, and that an unsupported value stops the script.
- **IT-005**: Verify the rendered install command for each of the six managers, including the non-interactive `apt` frontend.
- **IT-006**: Verify `DYBATPHO_PKG_ASSUME_YES=false` drops the assume-yes flags and `DYBATPHO_PKG_SUDO=true` adds `sudo` for every manager except `brew`.
- **IT-007**: Verify package name resolution for a matching override, a fallback, and a malformed override.
- **IT-008**: Stub each manager's query command to verify installed and missing verdicts, including `apt` config-files status and empty `apk` output.
- **IT-009**: Verify the missing check prints only the absent packages.
- **IT-010**: Verify that `--dry-run` and `DRY_RUN` print the command and never execute the stubbed manager.
- **IT-011**: Verify a non-interactive run without `--force` is skipped, and that `--force` or `DYBATPHO_FORCE` runs the manager.
- **IT-012**: Verify `--update` refreshes the index before installing, and that the index refresh asks for confirmation on its own.
- **IT-013**: Verify a non-zero exit code from the package manager reaches the caller.
- **IT-014**: Verify an unknown option and an empty package list stop the script, and that a package after `--` is passed through.
- **IT-015**: Verify the ensure helper installs only the missing packages and does nothing when they are all present.
- **IT-016**: Verify the require helper skips an available command, installs the resolved package name, and fails when the command is still missing.

## Acceptance Criteria *(mandatory)*

1. A script can detect the machine's package manager, check dependencies, and install the missing ones without knowing which distribution it runs on.
2. No function in the module changes system state without either an explicit `--force`/`DYBATPHO_FORCE` or an answered confirmation.
3. Dry-run mode renders the exact command that a real run would execute.
