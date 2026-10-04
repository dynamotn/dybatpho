# Feature Specification: Structured Logging and Trace Output

**Feature Branch**: `[reverse-spec-logging]`
**Status**: Implemented
**Input**: Existing source analysis: `src/logging.sh`, `docs/logging.md`, `test/logging.bats`, and `example/logging_demo.sh`

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

### User Story 6 - Turn on the file sink in one call (Priority: P2)

As a script author, I want to name the log file, its rotation threshold and
its verbosity in a single call so that enabling a durable log does not mean
exporting four environment variables correctly and hoping the path is
writable.

**Why this priority**: The sink already exists; what makes it usable is a
front door that validates its settings and fails where they are set rather
than silently dropping every later event.

**Independent Test**: Call the helper with a nested path and a `rotate:10M`
setting, then verify the file exists, its mode is `600`, and the rotation
threshold is the byte count that size stands for.

**Acceptance Scenarios**:

1. **Given** a path whose parent directory does not exist, **When** the helper
   is called, **Then** the directory and the file are created up front and the
   `LOG_FILE*` variables are set accordingly
2. **Given** a rotation size written as `10M`, **When** the helper is called,
   **Then** the threshold is stored as the equivalent number of bytes
3. **Given** a setting that cannot be honored -- an unparseable size, a
   non-numeric backup count, an unknown level, an unknown setting name --
   **When** the helper is called, **Then** it fails with a message naming the
   setting instead of configuring a sink that silently drops events
4. **Given** file logging is on, **When** the helper is called with `off`,
   **Then** later events go to stderr only
5. **Given** the helper creates the log file, **Then** the file is created
   with mode `600`, and a file that already exists keeps the mode it has

---

### User Story 7 - Carry run-wide fields on every event (Priority: P2)

As an operator aggregating logs, I want a run identifier and a stage name
attached to every structured event so that I can filter one run or one phase
without every call site repeating the same values in its message.

**Why this priority**: A correlation ID answers "which run"; the caller's own
fields answer "which customer, which stage, which attempt", which is what
turns an aggregated log into something queryable.

**Independent Test**: Register two fields, emit a JSON event, and verify both
appear as fields of their own after the built-in ones.

**Acceptance Scenarios**:

1. **Given** fields are registered, **When** a structured event is emitted,
   **Then** each field appears as a JSON field of its own, after the built-in
   fields, in the order the fields were registered
2. **Given** fields are registered, **When** a text diagnostic is emitted,
   **Then** the same fields follow the message as `name=value` pairs
3. **Given** a field is registered again with a new value, **When** an event
   is emitted, **Then** the new value is used and the field keeps its original
   position
4. **Given** a field name that a log event already uses, or a name that is not
   a valid identifier, **When** it is registered, **Then** the call fails
   rather than producing a duplicated or malformed event
5. **Given** a field value holds a registered secret, or a quote or newline,
   **When** an event is emitted, **Then** the value is redacted and escaped
   exactly as a message is

---

### User Story 8 - Time a step and log how long it took (Priority: P2)

As a script author, I want to bracket a step with a timer so that the log says
how long it took, in a field a log aggregator can chart, without hand-rolling
epoch arithmetic at every call site.

**Why this priority**: "Where did the twenty minutes go" is the first question
asked of a slow pipeline, and answering it should not require adding the
metrics module and a Prometheus endpoint.

**Independent Test**: Start a timer, wait, end it, and verify the message
names the timer and its elapsed milliseconds, and that the structured event
carries both as fields.

**Acceptance Scenarios**:

1. **Given** a timer was started, **When** it is ended, **Then** a message
   naming the timer and its elapsed milliseconds is logged at `info` by
   default, and the structured event carries `timer` and `elapsed_ms` fields
2. **Given** a timer is ended with an explicit level, **When** that level is
   filtered out by `LOG_LEVEL`, **Then** nothing is shown
3. **Given** a timer was never started, **When** it is ended, **Then** the
   call fails rather than reporting a meaningless duration
4. **Given** a timer has been ended, **Then** its elapsed milliseconds remain
   readable in `DYBATPHO_TIMER_LAST_MS`

---

### User Story 9 - Show that a long command is still running (Priority: P3)

As a user waiting on a script, I want a spinner beside a message while a slow
command runs so that I can tell the difference between working and hung,
without losing the command's output or its exit code.

**Why this priority**: Presentation, not correctness -- but a script that
looks hung gets killed.

**Independent Test**: Run a failing command behind the spinner and verify the
exit code is passed through unchanged and the command's output is untouched.

**Acceptance Scenarios**:

1. **Given** a command is run behind the spinner, **When** it finishes,
   **Then** its exit code is returned unchanged and its output is not captured
   or reordered
2. **Given** stderr is not a terminal, **When** the spinner runs, **Then** the
   message is logged once at `info` and nothing is animated
3. **Given** the spinner animated, **When** the command finishes, **Then** the
   animation is torn down and its line erased, whether the command succeeded
   or failed
4. **Given** any spinner run, **When** it finishes, **Then** a `debug` event
   records the elapsed milliseconds and the exit code
5. **Given** the message holds a registered secret, **When** the spinner draws
   it, **Then** the secret is redacted first

---

### Example Workflow

```bash
# Text on the terminal, JSON in a rotating file, at independent verbosity.
export LOG_LEVEL="info"
export LOG_FORMAT="text"
export LOG_FILE="/var/log/deploy.log"
export LOG_FILE_LEVEL="debug"
export LOG_FILE_MAX_BYTES=$((1024 * 1024))
export LOG_FILE_MAX_BACKUPS=5
export LOG_REQUEST_ID="deploy-42"

dybatpho::header "DEPLOY"
dybatpho::info "Starting deployment"
dybatpho::debug "Only the log file records this line"
dybatpho::progress_bar 50
dybatpho::success "Deployment finished"
```

```bash
# The same run, configured through the helpers instead of the variables.
dybatpho::log_to_file /var/log/deploy.log rotate:10M keep:5 level:debug
dybatpho::log_context add run_id=deploy-42 stage=build

dybatpho::timer_start build
dybatpho::spinner "Building the image" -- docker build -t app .
dybatpho::timer_end build

dybatpho::log_context add stage=publish
dybatpho::spinner "Pushing the image" -- docker push app
dybatpho::log_context clear
```

## Edge Cases

- `NO_COLOR` is set and ANSI color must be suppressed.
- `NO_COLOR` is unset after the library loads, in a script running under `set -u`.
- A boxed line holds CJK text or emoji and the locale is C, so Bash indexes it
  by byte.
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
- A rotation size is given in a form the parser does not accept (`1.5M`,
  `ten megabytes`, a negative number), or as `0` to disable rotation.
- The configured log path exists but is not writable, or its parent directory
  cannot be created.
- A context field name collides with a field every event already carries, is
  not a valid identifier, or is registered without a value.
- A context field value holds a quote, a newline, or a registered secret.
- A timer is ended without being started, ended twice, or ended at a level
  that is filtered out or is not a level at all.
- The spinner runs without a terminal on stderr, is disabled with
  `DYBATPHO_SPINNER=never`, or is forced with `always`.
- `sleep` on the host understands whole seconds only, so the spinner interval
  cannot be honored exactly.
- The command run behind the spinner fails, reads stdin, or writes to the same
  terminal the spinner draws on.

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
- **FR-009**: Boxed banners MUST wrap content to terminal width, measured in
  display columns, so wide Unicode glyphs count for two columns and combining
  marks for none, under any locale and with no external program.
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
- **FR-020**: The module MUST provide `dybatpho::log_to_file`, configuring the
  file sink from one path plus optional `rotate:SIZE`, `keep:COUNT` and
  `level:LEVEL` settings, and `off` MUST turn the sink back off.
- **FR-021**: `dybatpho::log_to_file` MUST accept a rotation size as a byte
  count or with a `K`, `M`, `G` or `T` suffix (optionally `B`/`iB`),
  interpreted as 1024-based, and MUST fail on a size, backup count, level or
  setting name it cannot honor.
- **FR-022**: `dybatpho::log_to_file` MUST create the parent directory and the
  log file before returning, MUST create a new log file with mode `600`, MUST
  leave the mode of an existing file untouched, and MUST fail when the file
  cannot be written.
- **FR-023**: The module MUST provide `dybatpho::log_context` with `add`,
  `remove`, `clear`, `list` and `get` actions, maintaining fields that are
  attached to every later log event.
- **FR-024**: Context fields MUST appear in every structured event as fields of
  their own, after the built-in fields, in registration order, and MUST follow
  the message as `name=value` pairs in text output.
- **FR-025**: `dybatpho::log_context` MUST reject a field name that a log event
  already uses (`timestamp`, `level`, `source`, `message`, `request_id`,
  `hostname`, `pid`, `duration_ms`) and a name that is not a valid identifier.
- **FR-026**: Context field values MUST be JSON-escaped and redacted through
  the masking registry exactly as messages are.
- **FR-027**: The module MUST provide `dybatpho::timer_start` and
  `dybatpho::timer_end`, logging the elapsed milliseconds of a named timer at
  `info` or at a level given by the caller, and MUST fail when the timer was
  never started.
- **FR-028**: A timer's structured event MUST carry `timer` and `elapsed_ms`
  fields, and the elapsed milliseconds MUST also be published in
  `DYBATPHO_TIMER_LAST_MS`.
- **FR-029**: The module MUST provide `dybatpho::spinner MESSAGE -- COMMAND`,
  running the command in the calling shell's foreground and returning its exit
  code unchanged, and MUST fail when the `--` separator or the command is
  missing.
- **FR-030**: The spinner MUST animate only when stderr is a terminal and the
  `info` level passes filtering, MUST log the message once at `info` instead
  when it cannot animate, and MUST honor `DYBATPHO_SPINNER` set to `never` or
  `always`.
- **FR-031**: The spinner MUST erase its line and stop its animation before
  returning, and MUST record the elapsed milliseconds and the command's exit
  code as a `debug` event.
- **FR-032**: The spinner MUST redact registered secrets in its message before
  drawing it.
- **FR-033**: Measuring display width and building padding MUST be available
  in a form that writes into a caller-named variable, so boxed output does not
  fork once per line to ask how wide a line is.
- **FR-034**: Writing a log line MUST NOT fail when `NO_COLOR` is unset, even
  under `set -u`; an unset `NO_COLOR` means colour, as an empty one does.
- **FR-035**: The module MUST provide the library's one display-width measure,
  built on embedded Unicode tables: nonspacing and enclosing marks, format
  characters other than the soft hyphen, and the Hangul medial and final jamo
  take no column; characters of East Asian Width Wide or Fullwidth take two;
  everything else takes one. It MUST give the same answer whether Bash indexes
  strings by byte or by character, and MUST NOT start another process.
- **FR-036**: The display-width string cache MUST be bounded, so a long run
  measuring endless distinct strings does not grow without limit.
- **FR-037**: A command run by `spinner` MUST see the caller's variables: the spinner MUST keep its state in prefixed locals.

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
- **Context Field**: A `name=value` pair registered once and attached to every
  later log event, held in the current shell.
- **Timer**: A named start time, turned into an elapsed duration and a log
  event when the step it brackets finishes.
- **Spinner**: A background animation shown beside a message while a
  foreground command runs.

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
- **SC-009**: A durable, rotating, secret-masked log is turned on with one
  call, and a path or setting that would not work is reported where it is
  configured rather than by an empty log file afterwards.
- **SC-010**: Log events from one run can be filtered by the caller's own
  fields, such as a run identifier or a stage, without those values being
  repeated in every message.
- **SC-011**: A script can report how long each step took, and show that a
  slow step is still alive, without hand-rolled timing or output handling and
  without changing the exit code that reaches the caller.

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
- **IT-012**: Call `dybatpho::log_to_file` with a nested path and
  `rotate:10M keep:3 level:debug`, and verify the file is created with mode
  `600`, the threshold is `10485760`, and a debug event reaches the file while
  stdout stays at `info`.
- **IT-013**: Call `dybatpho::log_to_file` with an unparseable size, a
  non-numeric backup count, an unknown level and an unknown setting, and
  verify each fails; then call it with `off` and verify later events reach no
  file.
- **IT-014**: Register context fields, emit a JSON event and a text event, and
  verify both carry the fields in registration order; update one field and
  verify its position is kept.
- **IT-015**: Register a context field holding a registered secret and one
  holding a quote, and verify the file line is redacted and still parses as
  JSON.
- **IT-016**: Bracket a `sleep` with `dybatpho::timer_start` and
  `dybatpho::timer_end`, and verify the message names the timer, the event
  carries `timer` and `elapsed_ms`, and `DYBATPHO_TIMER_LAST_MS` is numeric;
  verify ending an unstarted timer fails.
- **IT-017**: Run a failing command behind `dybatpho::spinner` with the
  animation disabled and verify the exit code and the command's output survive
  intact, and that a `debug` event records the elapsed time and exit code.
- **IT-018**: Force the animation with `DYBATPHO_SPINNER=always` and verify
  frames are drawn on stderr and the line is erased when the command finishes.
- **IT-019**: Verify boxed output is unchanged for ASCII, wide and combining
  characters after the width helpers stopped going through `$( )`.
- **IT-020**: Unset `NO_COLOR` after loading the library, turn on `set -u`, and
  verify a log line is still written.
- **IT-021**: Measure ASCII, CJK, Hangul, fullwidth letters, emoji, a combining
  accent, a mark with no combining class, zero-width space, joiner and VS16, a
  soft hyphen, both ends of the wide table, and all of it with an empty `PATH`.
- **IT-022**: Measure the same mixed string under the C locale and under UTF-8,
  and get the same width.
- **IT-023**: Lower the string-cache limit, measure more distinct strings than
  it allows, and find the cache within the limit.
- **IT-024**: Wrap a line that fits in columns but not in bytes under the C
  locale, and get it on one line; wrap a longer one at its space.
- **IT-025**: Run a command under a spinner that reads variables named like the spinner's locals, and see the caller's values.

## Acceptance Criteria *(mandatory)*

1. The module gives dybatpho scripts a consistent logging vocabulary.
2. Operators can move from concise output to diagnostic output without changing script code.
3. Structured log events remain correlatable and auditable across processes
   and long-running sessions without requiring callers to manage IDs, file
   handles, or rotation themselves.
