# Feature Specification: Date and Timestamp Utilities

**Feature Branch**: `[reverse-spec-date]`
**Status**: Implemented
**Input**: Existing source analysis: `src/date.sh`, `docs/date.md`, `test/date.bats`, and `example/date_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts frequently need to read the current time, validate date strings, convert between human-readable values and Unix timestamps, shift dates by day offsets, and calculate day differences, but open-coded `date` usage quickly becomes repetitive and inconsistent.

## Business Value *(mandatory)*

- Centralize common date/time workflows behind small reusable helpers.
- Keep scripts readable when they need parsing, formatting, or simple date math.
- Make UTC-oriented automation behavior predictable across docs, tests, and examples.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read current time in scripts (Priority: P1)

As a script author, I want helpers for the current timestamp and current date so that I can stamp logs, files, and generated values without repeating `date` flags everywhere.

**Why this priority**: Reading the current time is the most common date/time operation in shell scripts.

**Independent Test**: Call the current-time helpers with default and custom formats and verify the returned strings match the requested formatting contract.

**Acceptance Scenarios**:

1. **Given** no explicit format is provided, **When** the current-time helper runs, **Then** it prints the current Unix timestamp
2. **Given** a custom format string, **When** the current-date helper runs, **Then** the output follows that format

---

### User Story 2 - Parse and format timestamps (Priority: P1)

As a script author, I want helpers that convert dates to Unix timestamps and back so that storage and display formats can be handled cleanly.

**Why this priority**: Parsing and formatting are foundational for date persistence and display.

**Independent Test**: Parse a fixed date string into a Unix timestamp, then format that timestamp back into one or more known output formats.

**Acceptance Scenarios**:

1. **Given** a valid date string, **When** the parse helper runs, **Then** it prints the matching Unix timestamp
2. **Given** a Unix timestamp, **When** the format helper runs, **Then** it prints the requested formatted date string

---

### User Story 3 - Validate and shift dates (Priority: P2)

As a maintainer, I want validation and day-offset helpers so that shell scripts can reject bad inputs and perform simple calendar math without inline `date -d` expressions.

**Why this priority**: Validation and date shifting are common operational workflows around retention, scheduling, and reporting.

**Independent Test**: Validate both valid and invalid dates, then shift a fixed base date forward and backward by whole-day offsets.

**Acceptance Scenarios**:

1. **Given** a valid or invalid date string, **When** the validation helper runs, **Then** it returns success only for valid input
2. **Given** a base date and signed day offset, **When** the add-days helper runs, **Then** it prints the shifted date

---

### User Story 4 - Measure day differences (Priority: P2)

As a script author, I want a helper that prints the signed difference in days between two dates so that expiry checks and reporting windows stay readable.

**Why this priority**: Scripts often need simple day comparisons without extra arithmetic boilerplate.

**Independent Test**: Compare two known dates in both directions and verify the reported day difference is signed correctly.

**Acceptance Scenarios**:

1. **Given** an earlier date and a later date, **When** the difference helper runs, **Then** it prints a positive whole-day difference
2. **Given** the same dates in reverse order, **When** the difference helper runs, **Then** it prints the same difference with a negative sign

---

### Example Workflow

```bash
started_at="$(dybatpho::date_now)"

if dybatpho::date_is_valid "2026-01-15"; then
  expires_at="$(dybatpho::date_add_days "2026-01-15" 30)"
  dybatpho::info "Certificate expires on ${expires_at}"
  dybatpho::info "Valid for $(dybatpho::date_diff_days "2026-01-15" "${expires_at}") days"
fi

dybatpho::info "Run started at $(dybatpho::date_format "${started_at}" "%F %T")"
```

## Edge Cases

- A date string cannot be parsed by the underlying `date` command.
- A timestamp is formatted with a custom output format.
- A day offset is negative.
- The configured timezone changes formatting or parsing behavior.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a helper that prints the current time using a configurable `date` format string.
- **FR-002**: The current-time helper MUST default to a Unix timestamp when no format is provided.
- **FR-003**: The module MUST provide a helper that prints today's date using a configurable format string.
- **FR-004**: The module MUST provide a helper that returns success only when a date string is valid.
- **FR-005**: The module MUST provide a helper that parses a date string into a Unix timestamp.
- **FR-006**: The module MUST provide a helper that formats a Unix timestamp into a date string.
- **FR-007**: The module MUST provide a helper that adds or subtracts whole days from a date string.
- **FR-008**: The module MUST provide a helper that prints the signed whole-day difference between two date strings.
- **FR-008a**: The module MUST work on GNU, BSD and BusyBox `date`. It MUST
  detect which is present rather than assuming that anything without
  `--version` is BSD: BusyBox parses with `-D` instead of `-j -f`, and reads
  `-r` as a reference file rather than a timestamp, so a two-way guess made
  every helper in the module fail there.
- **FR-008b**: Parsing MUST reject a date that the platform would roll over
  (`2024-02-30` becoming `2024-03-01`) on every platform that rolls it over,
  which is both BSD and BusyBox.
- **FR-009**: The module MUST respect the timezone configured through
  `DYBATPHO_DATE_TIMEZONE` across every parsing and formatting helper.

- **FR-010**: The module MUST report whether a year is a leap year, applying the century and four-century rules, and MUST report how many days a given month has.
- **FR-011**: The module MUST print the first and the last day of the month a date falls in, working the last day out from the calendar rather than by adding a month and stepping back.
- **FR-012**: The module MUST shift a date by a signed amount of a named unit, and MUST measure the distance between two dates in a named unit, truncating toward zero and keeping the sign.
- **FR-012a**: The units MUST be those that are a fixed number of seconds: seconds, minutes, hours, days, and weeks, named in the singular or the plural. Months and years MUST be refused, because their length depends on the calendar and the supported `date` implementations shift by them differently.
- **FR-012b**: A rejected unit MUST stop the caller even when the caller has switched `errexit` off, so that a validation helper failing inside a command substitution can never leave the caller with an answer computed from unvalidated input.
- **FR-013**: The day-offset and day-difference helpers MUST keep their existing behaviour while being expressed in terms of the general helpers.
- **FR-014**: The module MUST print a number of seconds as `H:MM:SS`, without wrapping the hours at a day and keeping the sign of a negative span.

### Key Entities *(include if feature involves data)*

- **Date String**: A caller-provided textual date or datetime value parsed by the underlying `date` command.
- **Unix Timestamp**: A seconds-since-epoch integer used for storage and arithmetic.
- **Day Offset**: A signed whole-number amount of days applied to a base date.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can express common date/time workflows without repeating raw `date` command lines.
- **SC-002**: Parsing and formatting behavior is deterministic enough for docs and automated tests.
- **SC-003**: Simple date arithmetic remains readable in shell automation.

## Integration Tests *(mandatory)*

- **IT-001**: Print the current time with default and custom output formats.
- **IT-002**: Parse a fixed date string into a Unix timestamp and format it back into a known string.
- **IT-003**: Validate good and bad date strings.
- **IT-004**: Shift a fixed date forward and backward by signed day offsets.
- **IT-005**: Calculate the signed day difference between two known dates.
- **IT-006**: Verify the leap-year predicate for a leap year, a century that is not one, a four-century that is, and a common year, and that a non-numeric year stops the script.
- **IT-007**: Verify the month-length helper for 31-day, 30-day, leap and non-leap February, and a month written with a leading zero; and that a month outside 1-12 stops the script.
- **IT-008**: Verify the month bounds for a leap February, a non-leap February, a 30-day month, and December, with the default and a custom format.
- **IT-009**: Shift a date by each supported unit, forward and backward, across a month and a leap day, using both the singular and plural unit names.
- **IT-010**: Verify a calendar-dependent unit and a non-numeric amount are refused, and that the refusal still stops a caller that has switched `errexit` off.
- **IT-011**: Measure a distance in each unit, verify truncation toward zero in both directions, and verify the day-offset and day-difference helpers answer as they did before delegating.
- **IT-012**: Verify the clock helper for a span under an hour, over a day, and negative, and that a fractional value stops the script.
- **IT-013**: Parse, format and shift dates on a BusyBox userland, where `-D`
  replaces `-j -f` and `-r` means something else entirely.

## Acceptance Criteria *(mandatory)*

1. The module covers the common date/time workflows advertised in examples and docs.
2. Output-oriented helpers print focused results suitable for command substitution.
3. Validation helpers use shell success and failure semantics suitable for control flow.
