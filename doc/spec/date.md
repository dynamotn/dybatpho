# Feature Specification: Date and Timestamp Utilities

**Feature Branch**: `[reverse-spec-date]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/date.sh"

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

### Edge Cases

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
- **FR-009**: The module MUST respect a configurable timezone across its helpers.

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

## Acceptance Criteria *(mandatory)*

1. The module covers the common date/time workflows advertised in examples and docs.
2. Output-oriented helpers print focused results suitable for command substitution.
3. Validation helpers use shell success and failure semantics suitable for control flow.
