# Feature Specification: Process Lifecycle, Traps, Cleanup, and Dry Run

**Feature Branch**: `[reverse-spec-process]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/process.sh"

## Problem Statement *(mandatory)*

Operational shell scripts need predictable exit behavior, signal handling, composable traps, deferred cleanup, and safe dry-run execution. Without a shared module, these concerns are typically reimplemented poorly and inconsistently.

## Business Value *(mandatory)*

- Make destructive or long-running scripts safer to run.
- Standardize error and signal handling across dybatpho-based scripts.
- Allow scripts to preview side effects before execution.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Handle errors and signals consistently (Priority: P1)

As a script author, I want one-line registration of common handlers so that errors and interrupts are surfaced consistently without custom trap code.

**Why this priority**: Signal and error handling affect script safety and user trust.

**Independent Test**: Register common handlers, trigger a command failure or signal, and verify structured termination behavior.

**Acceptance Scenarios**:

1. **Given** a script opts into the common handlers, **When** a command fails under the ERR trap, **Then** the error handler reports the failure and exits non-zero
2. **Given** a script receives SIGINT or SIGTERM, **When** the signal handler
   runs, **Then** the script reports the interruption and exits with the
   signal-specific status

---

### User Story 2 - Clean up temporary resources automatically (Priority: P1)

As an operator, I want files and directories removed on shell exit so that temporary workspaces do not leak after the script finishes or aborts.

**Why this priority**: Deferred cleanup is a core safety feature used by the file module and many automation flows.

**Independent Test**: Register temporary paths for cleanup, exit the shell, and verify the paths are removed.

**Acceptance Scenarios**:

1. **Given** a script registers a temporary file for cleanup, **When** the shell exits normally, **Then** the temporary path is removed automatically
2. **Given** multiple cleanup actions already exist on a signal or exit trap, **When** a new cleanup action is added, **Then** existing trap behavior is preserved instead of overwritten

---

## Edge Cases

- A script already has an EXIT or signal trap when dybatpho trap composition is requested.
- `DRY_RUN` is unset, true-like, or false-like.
- A dry-run command is supplied as one shell string (evaluated) or multiple
  arguments (executed directly).
- Cleanup registration runs under normal scripts and Bats test environments.
- An existing trap must be preserved when cleanup or another handler is added.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a fatal exit helper with configurable exit code.
- **FR-002**: The module MUST provide helpers to register ERR and signal handlers, individually and together.
- **FR-003**: The module MUST provide a trap-composition helper that preserves existing trap commands.
- **FR-004**: The module MUST provide deferred cleanup registration for files and directories on shell exit.
- **FR-005**: The module MUST provide a dry-run helper that prints commands instead of executing them when dry-run mode is enabled.
- **FR-006**: Cleanup registration MUST be suitable for temporary resources created during script execution.
- **FR-007**: `DRY_RUN` MUST treat `0`, `true`, `yes`, and `on` as enabled
  values and execute commands otherwise.
- **FR-008**: `dry_run` MUST evaluate a single command string and execute
  multiple arguments directly when dry-run mode is disabled.
- **FR-009**: Signal handlers MUST return 130 for SIGINT and 143 for SIGTERM.
- **FR-010**: Cleanup registration MUST append to existing traps and remove
  registered files or directories on EXIT, HUP, INT, or TERM.

### Key Entities *(include if feature involves data)*

- **Registered Trap Action**: A command appended to one or more shell trap handlers.
- **Deferred Cleanup Target**: A file or directory scheduled for removal when the owning shell exits.
- **Dry-Run Command**: A command represented as a shell string or argument
  vector and optionally printed instead of run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can opt into consistent lifecycle handling with one or two helper calls.
- **SC-002**: Temporary resources do not leak after scripts exit under normal conditions.
- **SC-003**: Operators can preview command execution safely when dry-run mode is enabled.
- **SC-004**: Existing trap behavior is retained when dybatpho handlers and
  cleanup actions are registered.

## Integration Tests *(mandatory)*

- **IT-001**: Register common handlers and verify command failures trigger the shared error path.
- **IT-002**: Register cleanup for a file and directory, exit the shell, and verify both are removed.
- **IT-003**: Set `DRY_RUN=true` and verify the dry-run helper prints the command without executing it.
- **IT-004**: Verify false-like dry-run execution, signal-specific statuses,
  and trap composition with pre-existing handlers.

## Acceptance Criteria *(mandatory)*

1. The module provides the lifecycle guardrails required by file, network, and example scripts.
2. Trap composition and cleanup remain safe to reuse across multiple script layers.
