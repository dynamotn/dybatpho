# Feature Specification: Operating System, Architecture, and Host Facts

**Feature Branch**: `[reverse-spec-os]`
**Status**: Implemented
**Input**: Existing source analysis: `src/os.sh`, `docs/os.md`, `test/os.bats`, and `example/os_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts that fetch platform-specific binaries or compose platform-aware paths need normalized OS and architecture identifiers, but raw `uname` output varies across platforms and is not always aligned with common distribution targets such as Go toolchain naming.

The same scripts need a handful of other facts about the host they run on — its name, the user behind the process, how many processors are available, how wide the terminal is, which distribution is installed, and whether the run is privileged, containerized, or on CI. Each of those is a short portability puzzle of its own, and when every module solves it privately the answers drift apart: two modules resolved the host name through different chains, and a worker pool and a log banner each carried their own probe.

## Business Value *(mandatory)*

- Normalize platform detection for cross-platform scripts.
- Reduce repeated `uname` case analysis in consumer scripts.
- Make binary-selection logic more portable and predictable.
- Keep one answer per host fact, so that every module and every consumer script reports the same host name, processor count, and terminal size.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Map runtime OS to a normalized target name (Priority: P1)

As a script author, I want a helper that translates local operating system information into normalized names so that I can choose the correct platform artifacts.

**Why this priority**: OS normalization is the primary reason this module exists.

**Independent Test**: Stub representative `uname` outputs and verify the OS helper returns the expected normalized result.

**Acceptance Scenarios**:

1. **Given** the runtime is Linux on a standard distribution, **When** the OS helper runs, **Then** the helper returns `linux`
2. **Given** the runtime is a Windows-compatible environment such as Cygwin, MSYS, or MinGW, **When** the OS helper runs, **Then** the helper returns the normalized Windows target name

---

### User Story 2 - Map runtime CPU architecture to a normalized target name (Priority: P1)

As a maintainer, I want architecture normalization so that downloads and packaging steps can target the right binary variant.

**Why this priority**: Architecture mismatch directly breaks installation and distribution flows.

**Independent Test**: Stub representative machine architectures and verify the architecture helper returns the expected normalized value.

**Acceptance Scenarios**:

1. **Given** the runtime reports common 64-bit x86 architecture, **When** the architecture helper runs, **Then** the helper returns the normalized amd64 target name
2. **Given** the runtime reports an ARM or 32-bit architecture, **When** the architecture helper runs, **Then** the helper returns the corresponding normalized target name

---

### User Story 3 - Identify the host and the user behind the process (Priority: P2)

As a script author, I want the host name and the effective user so that logs, lock files, and audit trails say where and as whom a run happened.

**Why this priority**: Two modules resolved the host name independently before this, which is exactly the duplication the module exists to absorb.

**Independent Test**: Read the host name on a host without `hostname(1)` and verify the fallback chain answers, and verify a caller-supplied host name wins over detection.

**Acceptance Scenarios**:

1. **Given** the host has no `hostname` command, **When** the host name helper runs, **Then** it answers from `uname -n`, the kernel, or the environment instead of failing
2. **Given** a run under `sudo`, **When** the user helper runs, **Then** it reports the effective user and the root predicate returns success

---

### User Story 4 - Size the work to the machine and its terminal (Priority: P2)

As a script author, I want the processor count and the terminal size so that a worker pool and rendered output both fit the machine they run on.

**Why this priority**: A pool that guesses its own bound and a banner that guesses its own width are the two places the library had to measure the host before this.

**Independent Test**: Read the processor count on a host with and without a probe available, and read the terminal width with a valid, an invalid, and an absent `COLUMNS`.

**Acceptance Scenarios**:

1. **Given** no available command reports a processor count, **When** the count helper runs, **Then** it fails rather than inventing a number, and the caller supplies its own default
2. **Given** `COLUMNS` is unset and there is no terminal, **When** the width helper runs, **Then** it answers with the caller's fallback

---

### User Story 5 - Recognize the distribution and the kind of environment (Priority: P2)

As a script author, I want the distribution, its version, and whether the run is privileged, containerized, under WSL, or on CI, so that a script can adapt without reimplementing the probes.

**Why this priority**: Installation and guard logic branches on these facts, and each probe is easy to get subtly wrong on one platform.

**Independent Test**: Point the `os-release` reader at a fixture and verify the identifier, the version, and a field the file does not carry; set the environment variables of a container and a CI service and verify the predicates.

**Acceptance Scenarios**:

1. **Given** a Linux host with an `os-release` file, **When** the distribution helper runs, **Then** it answers with the lowercase `ID` and the version helper answers with `VERSION_ID`
2. **Given** a rolling release that publishes no `VERSION_ID`, **When** the version helper runs, **Then** it answers from `BUILD_ID` instead
3. **Given** a CI service that sets `CI=false`, **When** the CI predicate runs, **Then** it returns failure

---

### Example Workflow

```bash
# Select the right release artifact for the current host.
asset="mytool_$(dybatpho::goos)_$(dybatpho::goarch).tar.gz"
dybatpho::info "Downloading ${asset}"

if dybatpho::is_macos; then
  brew_prefix="$(dybatpho::command_path brew)"
  dybatpho::info "Using Homebrew at ${brew_prefix}"
elif dybatpho::is_linux; then
  dybatpho::info "Using $(dybatpho::command_path apt-get dnf apk)"
fi
```

## Edge Cases

- Linux reports the Android userspace variant.
- The architecture is unknown and must pass through unchanged.
- Different Windows-compatible environments report distinct `uname` strings that should normalize to one target name.
- The host has neither `hostname(1)` nor a `uname` that answers `-n`, as in a minimal container image.
- No processor-count probe is installed, so there is no count to report.
- `COLUMNS` is set to something that is not a positive number, or the output is a pipe rather than a terminal.
- macOS has no `os-release` file, and a rolling release has no `VERSION_ID`.
- A CI service sets `CI=false`, which means the run is not on CI.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST normalize runtime operating system names into distribution-oriented target values.
- **FR-002**: The OS helper MUST distinguish Android from generic Linux when the runtime exposes that variant.
- **FR-003**: The module MUST normalize common CPU architectures into target values suitable for cross-platform artifact selection.
- **FR-004**: Unknown architecture strings MUST remain available to callers instead of being silently discarded.
- **FR-005**: The module MUST expose normalized platform predicates for common host systems, covering Linux, macOS, and Windows-compatible environments.
- **FR-006**: The module MUST provide command capability lookup without requiring platform-specific paths.
- **FR-006a**: The module MUST report the version a command states about itself, probing `--version`, `-version`, `version`, and `-V` in that order until one reveals a version.
- **FR-006b**: The probe MUST read both output streams, because a good number of tools answer on standard error, and MUST close standard input so that a command which would otherwise wait for input cannot hang the caller.
- **FR-006c**: The probe MUST fail without output when the command is not installed or when no probe reveals a version, so that the caller can tell "no version" apart from a version.
- **FR-006d**: The module MUST expose the pattern used to find a version inside arbitrary text, so that the optional `semver` module can reuse it rather than carry a second copy.
- **FR-007**: The module MUST resolve the host name through `hostname`, `uname -n`, the kernel, and the environment, in that order, MUST let a caller override the answer, and MUST resolve it only once per shell.
- **FR-008**: The module MUST report the effective user name and MUST expose a predicate for the superuser that works whether or not `EUID` is set.
- **FR-009**: The module MUST report the number of online processors, and MUST fail rather than substitute a number when no probe answers.
- **FR-010**: The module MUST report the terminal width and height, preferring `COLUMNS`/`LINES`, then `tput` when a terminal is attached, and finally a caller-supplied fallback, and MUST reject a fallback that is not a positive integer.
- **FR-011**: The module MUST expose a predicate for whether a given standard stream is attached to a terminal, and MUST reject a stream name it does not know.
- **FR-012**: The module MUST read arbitrary fields from the host's `os-release` file with the file's quoting removed, and MUST allow the file's location to be overridden.
- **FR-013**: The module MUST report the distribution identifier and version, answering `macos` on Darwin and falling back to the normalized platform name when there is no `os-release` file.
- **FR-014**: The module MUST report the kernel release of the host.
- **FR-015**: The module MUST expose predicates for running inside a container, under the Windows Subsystem for Linux, and on a continuous integration service, and the CI predicate MUST treat a false value as not being on CI.
- **FR-015a**: The CI predicate MUST let `CI` decide whenever it holds a value, in either direction, so that `CI=false` reports not-CI even on a service that also advertises itself by name. Every service sets `CI`, and it is the one variable a caller can set themselves, so anything else overriding it would leave no way to turn the detection off.
- **FR-015b**: The CI predicate MUST consult the service-specific variables only when `CI` is unset or empty, and MUST treat a false value in one of them as that service saying nothing rather than as an answer for the whole environment.

- **FR-016**: The module MUST provide one answer for whether a stream's output should carry ANSI colour, so the library does not decide it differently per module.
- **FR-017**: `NO_COLOR` MUST turn colour off whatever else is set, `FORCE_COLOR` MUST turn it on regardless of the stream, `TERM=dumb` MUST turn it off, and otherwise the named stream MUST have to be a terminal.
- **FR-018**: The colour answer MUST be given per stream, so a module writing diagnostics to stderr and data to stdout can ask about each.

### Key Entities *(include if feature involves data)*

- **Normalized GOOS**: The platform name returned by the OS helper for downstream artifact selection.
- **Normalized GOARCH**: The architecture name returned by the architecture helper for downstream artifact selection.
- **Host Fact**: A single property of the machine the script runs on — host name, user, processor count, terminal size, distribution, or environment kind — resolved in one place and reused by every module.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Consumers can reuse one OS helper and one architecture helper instead of maintaining custom mapping tables.
- **SC-002**: Normalized outputs are suitable for common binary-distribution workflows.
- **SC-003**: Unknown values remain inspectable when no known mapping exists.
- **SC-004**: No other module detects a host fact for itself: the worker pool, the log banner, the lock file, the package manager, and the confirmation guard all read their answer from this module.

## Integration Tests *(mandatory)*

- **IT-001**: Stub Linux, Android, and Windows-like `uname` outputs and verify normalized OS values.
- **IT-002**: Stub amd64, 386, arm, and arm64 architectures and verify normalized architecture values.
- **IT-003**: Pass through an unknown architecture string and verify the helper preserves it.
- **IT-004**: Verify `platform`, `is_macos`, and `is_linux` use the normalized OS value.
- **IT-005**: Verify command lookup returns the first available command.
- **IT-005a**: Verify the version probe reads a version from a flag, from a `version` subcommand, from standard error, and from the surrounding text of a real command.
- **IT-005b**: Verify the probe fails without output for a command that is not installed and for one that reveals no version, and returns rather than hanging on a command that reads standard input.
- **IT-006**: Verify the host name is answered from an override, is cached afterwards, and falls back to `uname -n` in a shell whose PATH has no `hostname`.
- **IT-007**: Verify the user helper matches `id -un` and that the root predicate agrees with the effective user id.
- **IT-008**: Verify the processor count is a positive integer, comes from `nproc` when it is installed, and fails when no probe can be found.
- **IT-009**: Verify the terminal helpers trust `COLUMNS`/`LINES`, fall back when the value is unusable, and reject a fallback that is not a positive integer.
- **IT-010**: Verify the terminal-stream predicate is false for the captured streams of a test and rejects an unknown stream name.
- **IT-011**: Verify `os-release` fields are read with quoting removed, that a missing field and a missing file both fail, and that the distribution and version helpers answer from the fixture, from `BUILD_ID`, and as `macos` on Darwin.
- **IT-012**: Verify the container, WSL, and CI predicates from the environment variables each of them defines, including `CI=false`.
- **IT-012a**: Verify `CI` set to each of its false spellings reports not-CI while a service variable is also set to true, and that `CI=true` reports CI while a service variable is set to false. The environment must be pinned in the test rather than inherited, so the result is the same on a workstation and on a runner.
- **IT-012b**: Verify that with every marker cleared, a service variable alone decides, and that an empty `CI` leaves the fallback in effect.

- **IT-013**: `NO_COLOR` wins over `FORCE_COLOR` and over an attached terminal.
- **IT-014**: `FORCE_COLOR` turns colour on for a stream that is not a terminal.
- **IT-015**: `TERM=dumb` turns colour off.
- **IT-016**: With nothing overriding it, the stream decides, and an unknown stream is rejected.

## Acceptance Criteria *(mandatory)*

1. The module provides a small but complete normalization contract for platform-aware scripts.
2. OS and architecture naming remains predictable enough for download and packaging workflows.
3. Every host fact a script needs is available from this module, with one documented answer and one documented failure mode each.
