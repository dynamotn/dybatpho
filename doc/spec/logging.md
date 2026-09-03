# Feature Specification: Structured Logging and Trace Output

**Feature Branch**: `[reverse-spec-logging]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/logging.sh"

## Problem Statement *(mandatory)*

Shell automation needs consistent human-readable logging with level filtering, diagnostics, banners, and optional trace output. Ad hoc `echo` usage makes scripts noisy, inconsistent, and hard to debug.

## Business Value *(mandatory)*

- Standardize log output across scripts and examples.
- Allow scripts to tune verbosity without rewriting call sites.
- Provide rich diagnostic and trace helpers for debugging shell behavior.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Emit logs at controlled verbosity (Priority: P1)

As a script author, I want level-aware logging so that users can see concise output by default and richer diagnostics when needed.

**Why this priority**: Log filtering determines day-to-day usability for every script built on the library.

**Independent Test**: Set different `LOG_LEVEL` values and verify only messages at or above the configured threshold are emitted.

**Acceptance Scenarios**:

1. **Given** the runtime log level is `info`, **When** debug and info helpers are called, **Then** info logs are shown and debug logs are suppressed
2. **Given** the runtime log level is `trace`, **When** trace-capable flows run, **Then** trace, debug, and normal messages become visible

---

### User Story 2 - Render status banners and diagnostics (Priority: P1)

As an operator, I want progress, success, warning, and error messages rendered consistently so that long-running scripts are easier to follow.

**Why this priority**: Structured presentation is a core usability benefit of the module.

**Independent Test**: Call the banner-style helpers and verify the expected channel, formatting, and level behavior.

**Acceptance Scenarios**:

1. **Given** a script starts a major step, **When** the progress helper runs, **Then** a highlighted progress banner is printed
2. **Given** a script hits a failure path, **When** the fatal or error helper runs, **Then** a diagnostic message is rendered to stderr with context
3. **Given** a task reports a percentage, **When** the progress-bar helper runs,
   **Then** it renders an in-place bar with the requested width

---

### User Story 3 - Emit machine-readable diagnostics (Priority: P2)

As a CI operator, I want structured JSON logging so that automated systems can
parse timestamps, levels, source locations, and messages without ANSI cleanup.

**Independent Test**: Set `LOG_FORMAT=json`, emit a diagnostic containing
quotes and newlines, and parse the resulting JSON record.

**Acceptance Scenarios**:

1. **Given** `LOG_FORMAT=json`, **When** a diagnostic helper emits a message,
   **Then** stderr contains one JSON object with timestamp, level, source, and
   escaped message fields
2. **Given** the default text format, **When** a diagnostic helper emits a
   message, **Then** the output remains human-readable and includes source
   context

---

## Edge Cases

- `NO_COLOR` is set and ANSI color must be suppressed.
- `LOG_LEVEL` is invalid.
- `LOG_FORMAT` is set to a value other than `json` (the implementation uses
  text output).
- A message contains quotes, backslashes, or control characters in JSON mode.
- `COLUMNS` or terminal detection is unavailable while rendering a box.
- A progress percentage is zero, 100, or outside the usual range.
- Trace helpers run in environments that use traps or child shells.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide log-level comparison and validation helpers.
- **FR-002**: The module MUST support debug, info, normal print, progress,
  warning, error, and fatal output paths with their documented stdout/stderr
  channels.
- **FR-003**: The module MUST support optional color suppression through `NO_COLOR`.
- **FR-004**: The module MUST include banner-style helpers for progress, headers, and success states.
- **FR-005**: The module MUST support trace start/end helpers for shell debugging workflows.
- **FR-006**: Diagnostic log output MUST include enough call-site context to help locate the emitting code.
- **FR-007**: The module MUST support `LOG_FORMAT=json` records containing
  timestamp, level, source, and message fields.
- **FR-008**: JSON log messages MUST escape backslashes, quotes, newlines,
  carriage returns, and tabs.
- **FR-009**: Boxed banners MUST wrap content to terminal width and account for
  wide Unicode glyphs when `python3` is available.
- **FR-010**: The module MUST provide a percentage progress-bar helper with a
  configurable width.

### Key Entities *(include if feature involves data)*

- **Log Event**: A user-visible message emitted with a severity level and optional formatting.
- **Runtime Log Level**: The active threshold that determines which log events are shown.
- **Log Format**: `text` human-readable output or `json` structured diagnostic
  output.
- **Progress Bar**: A carriage-return-updated percentage indicator.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can change verbosity by setting one environment variable.
- **SC-002**: Consumers can distinguish routine output from warnings and failures at a glance.
- **SC-003**: Trace-enabled sessions expose enough context to debug generated or dynamic shell behavior.
- **SC-004**: JSON-mode diagnostics can be consumed by standard JSON parsers
  without stripping terminal formatting.
- **SC-005**: Boxed progress and status output remains readable for long lines,
  narrow terminals, and wide Unicode text.

## Integration Tests *(mandatory)*

- **IT-001**: Set `LOG_LEVEL=debug` and verify debug-command output includes both message and command result.
- **IT-002**: Set `NO_COLOR` and verify messages are still readable without ANSI escapes.
- **IT-003**: Start and end trace mode around a command sequence and verify trace lifecycle output occurs at trace level.
- **IT-004**: Set `LOG_FORMAT=json` and verify a diagnostic with escaped
  characters parses as one JSON object.
- **IT-005**: Render progress, header, success, and progress-bar output with
  `NO_COLOR` and constrained `COLUMNS`.

## Acceptance Criteria *(mandatory)*

1. The module gives dybatpho scripts a consistent logging vocabulary.
2. Operators can move from concise output to diagnostic output without changing script code.
