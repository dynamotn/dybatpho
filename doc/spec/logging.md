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

### User Story 4 - Correlate and time structured events (Priority: P2)

As a CI/CD engineer, I want every structured log event enriched with a
correlation ID, hostname, process ID, and elapsed duration so that I can
trace a single run across parallel workers and log aggregation systems
without adding custom instrumentation.

**Why this priority**: Distributed pipelines run many script instances
concurrently; without a correlation ID and process context, log lines from
different runs are indistinguishable once aggregated.

**Independent Test**: Emit two diagnostics from the same process with
`LOG_REQUEST_ID` unset and verify both events carry the same generated
`request_id`, plus non-empty `hostname`, `pid`, and `duration_ms` fields.

**Acceptance Scenarios**:

1. **Given** `LOG_REQUEST_ID` is unset, **When** the first structured event is
   emitted, **Then** a correlation ID is generated once and reused for every
   later event in the same process
2. **Given** `LOG_REQUEST_ID` is exported by the caller (for example a CI
   pipeline), **When** structured events are emitted, **Then** that ID is used
   verbatim instead of generating a new one
3. **Given** any structured event is emitted, **Then** it includes the current
   hostname, process ID, and milliseconds elapsed since the process started

---

### User Story 5 - Persist logs to a rotating file at independent verbosity (Priority: P2)

As an operator running long-lived or scheduled scripts, I want log output
written to a file with size-based rotation, independent of what is shown on
stdout/stderr, so that I can keep a durable audit trail without unbounded
disk growth or duplicating console noise.

**Why this priority**: Interactive verbosity and archival verbosity are
different concerns; forcing them to share one threshold either floods the
terminal or under-populates the audit log.

**Independent Test**: Set `LOG_FILE` to a path and `LOG_FILE_LEVEL` to a level
more verbose than `LOG_LEVEL`, emit events at multiple levels, and verify the
file captures more events than stdout while every file line is valid JSON.

**Acceptance Scenarios**:

1. **Given** `LOG_FILE` points to a path whose parent directory does not
   exist, **When** a log event is emitted, **Then** the directory is created
   and the event is appended as a JSON line
2. **Given** `LOG_FILE_LEVEL` is more permissive than `LOG_LEVEL`, **When**
   events at an intermediate severity are emitted, **Then** they appear in the
   file but not on stdout
3. **Given** the log file reaches `LOG_FILE_MAX_BYTES`, **When** another event
   is appended, **Then** the file is rotated into a numbered backup before the
   new event is written, and backups beyond `LOG_FILE_MAX_BACKUPS` are pruned
4. **Given** `LOG_FILE_MAX_BYTES=0`, **When** the file grows past what would
   normally trigger rotation, **Then** rotation is disabled and the file keeps
   growing
5. **Given** `LOG_FILE` is unset, **When** any log event is emitted, **Then**
   no file is created and no error is raised

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
- `hostname` and `uuidgen` binaries are unavailable on the host; hostname and
  correlation ID generation must fall back gracefully.
- `LOG_FILE`'s parent directory does not exist or is not writable.
- `LOG_FILE_MAX_BYTES` is `0` (rotation disabled) or `LOG_FILE_MAX_BACKUPS` is
  `0` or negative (truncate-only, no numbered backups retained).
- `LOG_FILE_LEVEL` is unset (defaults to `LOG_LEVEL`) or set independently
  more/less verbose than the stdout level.
- Concurrent processes append to the same `LOG_FILE` simultaneously.

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
- **FR-011**: Text and JSON log output MUST redact values registered with
  `src/secret.sh` whenever the masking registry is non-empty, without depending
  on that module being loaded.
- **FR-012**: Every structured (JSON) log event MUST include a correlation ID
  (`request_id`), generating and caching one for the process lifetime when
  `LOG_REQUEST_ID` is empty, and reusing a caller-supplied `LOG_REQUEST_ID`
  verbatim otherwise.
- **FR-013**: Every structured log event MUST include the current `hostname`,
  falling back through `hostname`, `/proc/sys/kernel/hostname`, `$HOSTNAME`,
  and finally the literal `unknown` when no source is available.
- **FR-014**: Every structured log event MUST include the emitting process's
  PID and the number of milliseconds elapsed since the process started
  (`duration_ms`).
- **FR-015**: The module MUST support writing structured JSON log events to a
  file when `LOG_FILE` is set, independent of the stdout `LOG_FORMAT`.
- **FR-016**: File logging MUST support an independent verbosity threshold via
  `LOG_FILE_LEVEL`, defaulting to `LOG_LEVEL` when unset.
- **FR-017**: File logging MUST create missing parent directories before
  writing.
- **FR-018**: The module MUST rotate `LOG_FILE` once it reaches
  `LOG_FILE_MAX_BYTES`, keeping up to `LOG_FILE_MAX_BACKUPS` numbered backups
  and pruning older ones; `LOG_FILE_MAX_BYTES=0` MUST disable rotation.
- **FR-019**: File log lines MUST be redacted using the same masking registry
  as stdout/stderr output.

### Key Entities *(include if feature involves data)*

- **Log Event**: A user-visible message emitted with a severity level and optional formatting.
- **Runtime Log Level**: The active threshold that determines which log events are shown.
- **Log Format**: `text` human-readable output or `json` structured diagnostic
  output.
- **Progress Bar**: A carriage-return-updated percentage indicator.
- **Masking Registry**: The optional process-local secret registry consulted
  before a log line is written.
- **Correlation ID**: A per-process identifier (`request_id`) attached to
  every structured event so related log lines can be grouped across
  aggregation systems.
- **Log File**: The optional durable destination (`LOG_FILE`) that receives
  JSON events independent of stdout, subject to its own verbosity threshold
  and rotation policy.
- **Rotation Policy**: The size threshold (`LOG_FILE_MAX_BYTES`) and backup
  count (`LOG_FILE_MAX_BACKUPS`) governing when and how the log file is
  rotated.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can change verbosity by setting one environment variable.
- **SC-002**: Consumers can distinguish routine output from warnings and failures at a glance.
- **SC-003**: Trace-enabled sessions expose enough context to debug generated or dynamic shell behavior.
- **SC-004**: JSON-mode diagnostics can be consumed by standard JSON parsers
  without stripping terminal formatting.
- **SC-005**: Boxed progress and status output remains readable for long lines,
  narrow terminals, and wide Unicode text.
- **SC-006**: Log events from a single process can be correlated across
  aggregation systems using a stable `request_id`, `hostname`, and `pid`
  without any extra caller bookkeeping.
- **SC-007**: Long-running or scheduled scripts can persist an audit trail via
  `LOG_FILE` without unbounded disk growth, thanks to automatic rotation.
- **SC-008**: File and stdout verbosity can be tuned independently so
  operators get concise console output while retaining a fuller file record.

## Integration Tests *(mandatory)*

- **IT-001**: Set `LOG_LEVEL=debug` and verify debug-command output includes both message and command result.
- **IT-002**: Set `NO_COLOR` and verify messages are still readable without ANSI escapes.
- **IT-003**: Start and end trace mode around a command sequence and verify trace lifecycle output occurs at trace level.
- **IT-004**: Set `LOG_FORMAT=json` and verify a diagnostic with escaped
  characters parses as one JSON object.
- **IT-005**: Render progress, header, success, and progress-bar output with
  `NO_COLOR` and constrained `COLUMNS`.
- **IT-006**: Emit two events in the same process with `LOG_REQUEST_ID` unset
  and verify both carry an identical, non-empty `request_id`.
- **IT-007**: Export `LOG_REQUEST_ID` before emitting events and verify the
  supplied value is reused verbatim rather than regenerated.
- **IT-008**: Verify every structured event includes non-empty `hostname` and
  `pid` fields and a numeric, non-decreasing `duration_ms`.
- **IT-009**: Set `LOG_FILE` to a nested path that does not yet exist and
  verify the directory is created and the event is appended as JSON.
- **IT-010**: Set `LOG_FILE_LEVEL` more permissive than `LOG_LEVEL` and verify
  the file captures events suppressed on stdout.
- **IT-011**: Force `LOG_FILE` past `LOG_FILE_MAX_BYTES` and verify rotation
  creates a numbered backup while pruning backups beyond
  `LOG_FILE_MAX_BACKUPS`; verify `LOG_FILE_MAX_BYTES=0` disables rotation.

## Acceptance Criteria *(mandatory)*

1. The module gives dybatpho scripts a consistent logging vocabulary.
2. Operators can move from concise output to diagnostic output without changing script code.
3. Structured log events remain correlatable and auditable across processes
   and long-running sessions without requiring callers to manage IDs, file
   handles, or rotation themselves.
