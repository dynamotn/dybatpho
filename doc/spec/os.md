# Feature Specification: Operating System and Architecture Normalization

**Feature Branch**: `[reverse-spec-os]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/os.sh"

## Problem Statement *(mandatory)*

Shell scripts that fetch platform-specific binaries or compose platform-aware paths need normalized OS and architecture identifiers, but raw `uname` output varies across platforms and is not always aligned with common distribution targets such as Go toolchain naming.

## Business Value *(mandatory)*

- Normalize platform detection for cross-platform scripts.
- Reduce repeated `uname` case analysis in consumer scripts.
- Make binary-selection logic more portable and predictable.

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

### Edge Cases

- Linux reports the Android userspace variant.
- The architecture is unknown and must pass through unchanged.
- Different Windows-compatible environments report distinct `uname` strings that should normalize to one target name.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST normalize runtime operating system names into distribution-oriented target values.
- **FR-002**: The OS helper MUST distinguish Android from generic Linux when the runtime exposes that variant.
- **FR-003**: The module MUST normalize common CPU architectures into target values suitable for cross-platform artifact selection.
- **FR-004**: Unknown architecture strings MUST remain available to callers instead of being silently discarded.

### Key Entities *(include if feature involves data)*

- **Normalized GOOS**: The platform name returned by the OS helper for downstream artifact selection.
- **Normalized GOARCH**: The architecture name returned by the architecture helper for downstream artifact selection.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Consumers can reuse one OS helper and one architecture helper instead of maintaining custom mapping tables.
- **SC-002**: Normalized outputs are suitable for common binary-distribution workflows.
- **SC-003**: Unknown values remain inspectable when no known mapping exists.

## Integration Tests *(mandatory)*

- **IT-001**: Stub Linux, Android, and Windows-like `uname` outputs and verify normalized OS values.
- **IT-002**: Stub amd64, 386, arm, and arm64 architectures and verify normalized architecture values.
- **IT-003**: Pass through an unknown architecture string and verify the helper preserves it.

## Acceptance Criteria *(mandatory)*

1. The module provides a small but complete normalization contract for platform-aware scripts.
2. OS and architecture naming remains predictable enough for download and packaging workflows.
