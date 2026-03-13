# Feature Specification: Bootstrap and Module Loading

**Feature Branch**: `[reverse-spec-init]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "init.sh"

## Problem Statement *(mandatory)*

Consumers need a safe, predictable way to bootstrap the full dybatpho library. Manually sourcing individual modules would force every script to duplicate runtime checks, shell options, and load order concerns.

## Business Value *(mandatory)*

- Enable one-step adoption of the library in new scripts.
- Prevent invalid execution modes such as direct execution or unsupported Bash versions.
- Standardize module load order and exported runtime context.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Source the library once (Priority: P1)

As a script author, I want one bootstrap file so that I can enable the entire library with a single source statement.

**Why this priority**: Every consuming script depends on reliable initialization before any helper can work.

**Independent Test**: Source `init.sh` and verify `DYBATPHO_DIR` plus exported `dybatpho::` functions are available.

**Acceptance Scenarios**:

1. **Given** a Bash v4+ shell is running, **When** the script sources `init.sh`, **Then** the bootstrap exports the project root and loads all modules in order
2. **Given** the consumer expects child shells to reuse dybatpho functions, **When** a child shell inherits the environment, **Then** exported `dybatpho::` functions remain callable

---

### User Story 2 - Reject unsupported startup modes (Priority: P1)

As a maintainer, I want invalid startup modes rejected so that downstream behavior is never undefined.

**Why this priority**: Fail-fast bootstrap errors prevent harder-to-debug runtime breakage later.

**Independent Test**: Attempt direct execution and unsupported Bash usage, then verify bootstrap stops with a clear failure.

**Acceptance Scenarios**:

1. **Given** the file is executed directly, **When** the shell runs `init.sh` as a program, **Then** bootstrap exits instead of pretending to work
2. **Given** the shell version is below the supported minimum, **When** the file is sourced or executed, **Then** bootstrap reports that the Bash version is unsupported

---

### Edge Cases

- The current shell is not Bash v4+.
- The consumer runs the file directly instead of sourcing it.
- Bootstrap runs under strict mode and must still load all modules safely.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bootstrap MUST require Bash v4 or newer before loading library code.
- **FR-002**: The bootstrap MUST refuse direct execution and require sourcing.
- **FR-003**: The bootstrap MUST enable the default strict and globbing shell options expected by the library.
- **FR-004**: The bootstrap MUST set and export `DYBATPHO_DIR` to the repository root path.
- **FR-005**: The bootstrap MUST source all shipped modules in a deterministic order.
- **FR-006**: The bootstrap MUST re-export the public `dybatpho::` functions for downstream shells.

### Key Entities *(include if feature involves data)*

- **Bootstrap Session**: The runtime state created by sourcing `init.sh`.
- **Public Function Export**: A `dybatpho::` function made available to subshells after bootstrap.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Consumers can enable the full toolkit with one source statement.
- **SC-002**: Unsupported execution modes fail before any partial initialization leaks into the session.
- **SC-003**: All public modules are available immediately after bootstrap.

## Integration Tests *(mandatory)*

- **IT-001**: Source `init.sh` and call one representative function from each module.
- **IT-002**: Execute `init.sh` directly and verify the session is rejected.
- **IT-003**: Run under Bash v4+ strict mode and verify bootstrap completes without manual overrides.

## Acceptance Criteria *(mandatory)*

1. `init.sh` is the single supported entrypoint for loading dybatpho.
2. Bootstrap behavior is explicit, deterministic, and fail-fast.
