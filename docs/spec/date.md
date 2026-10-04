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

### User Story 5 - Read a length of time from configuration (Priority: P2)

As a script author, I want to turn a timeout, interval, or retention period written as `90s`, `1h30m`, `1:01:01`, or `PT1H30M` into a number of seconds so that options and configuration values can be written the way people say them.

**Why this priority**: Timeouts, cache lifetimes, and schedule intervals are all lengths of time, and every script that reads one otherwise grows its own parser.

**Independent Test**: Parse each spelling into a known number of seconds, round-trip the clock spelling through the clock helper, and verify malformed, calendar-unit, and overflowing values are refused without touching the target variable.

**Acceptance Scenarios**:

1. **Given** a duration made of parts with units, **When** the parser runs, **Then** the target variable holds the total number of seconds
2. **Given** the clock spelling written by the clock helper, **When** the parser runs, **Then** it recovers the original number of seconds
3. **Given** a duration that names months or years, is malformed, or is too large to count, **When** the parser runs, **Then** it fails with a message and leaves the target unchanged

---

### User Story 6 - Order two dates (Priority: P2)

As a script author, I want predicates that say whether one date comes before or after another so that expiry and freshness checks read as conditions.

**Why this priority**: Comparing two timestamps by hand means parsing both and remembering which way round the subtraction goes.

**Independent Test**: Compare earlier, later, and identical moments written in different spellings, and verify an unreadable date stops the script instead of answering.

**Acceptance Scenarios**:

1. **Given** an earlier and a later date, **When** the before predicate runs, **Then** it succeeds, and the after predicate fails
2. **Given** two spellings of the same moment, **When** either predicate runs, **Then** it fails
3. **Given** a date that cannot be parsed, **When** either predicate runs, **Then** the script stops with a message naming the date

---

### User Story 7 - Week numbers and other timezones (Priority: P3)

As a script author, I want the ISO 8601 week a date falls in and the same date as another timezone reads it so that weekly reports and messages to people elsewhere are correct.

**Why this priority**: ISO weeks and zone conversions are where hand-written arithmetic is most often wrong, but fewer scripts need them.

**Independent Test**: Compute the week of dates around year boundaries, including 53-week years, and convert a date into a zone with and without daylight saving; verify an unknown zone is refused.

**Acceptance Scenarios**:

1. **Given** a date in the first days of January, **When** the week helper runs, **Then** it can report the last week of the previous week-year
2. **Given** a known timezone, **When** the conversion helper runs, **Then** it prints the date as that zone reads it
3. **Given** a timezone that is not in the zone database, **When** the conversion helper runs, **Then** the script stops instead of answering in UTC

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

timeout=""
dybatpho::date_parse_duration timeout "${TIMEOUT:-5m}" || dybatpho::die "Bad timeout"
dybatpho::date_is_before "$(dybatpho::date_today)" "${expires_at}" || dybatpho::warn "Expired"
dybatpho::info "Report for $(dybatpho::date_iso_week "$(dybatpho::date_today)")"
dybatpho::info "Tokyo time: $(dybatpho::date_in_tz "$(dybatpho::date_now '%F %T')" Asia/Tokyo)"
```

## Edge Cases

- A date string cannot be parsed by the underlying `date` command.
- A timestamp is formatted with a custom output format.
- A day offset is negative.
- The configured timezone changes formatting or parsing behavior.
- A duration is empty, has a trailing space, repeats a unit, puts a smaller unit before a larger one, or names months or years.
- A duration's total does not fit in a Bash integer, which would otherwise wrap around to a negative number.
- A duration is negative, or negative zero.
- Two dates compared are the same moment written differently.
- A date compared cannot be parsed, which must not read as a "no".
- A date in the first days of January belongs to the previous ISO week-year, or one in the last days of December to the next.
- A year has 53 ISO weeks.
- A timezone name is misspelled, is a path, or is a POSIX rule string, any of which `date` would quietly treat as UTC.

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
  every helper in the module fail there. It MUST detect each one by the flag
  the module uses with it, `-D` for BusyBox and `-d @<seconds>` for GNU, not
  by `--version`, so a GNU-compatible `date` without that option is still
  driven with `-d`.
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
- **FR-015**: The module MUST parse a duration into a number of seconds, accepting a bare number of seconds; parts with the units `w`, `d`, `h`, `m`, and `s`, largest first, each at most once, optionally separated by single runs of spaces; the `H:MM:SS` clock the clock helper writes; and an ISO 8601 duration of weeks, days, hours, minutes, and seconds. A leading `-` MUST make the result negative, and negative zero MUST be reported as `0`.
- **FR-015a**: The duration parser MUST return its result through a named variable, MUST leave that variable unchanged and fail with a message on stderr when it refuses the input, and MUST refuse months and years in every spelling.
- **FR-015b**: The duration parser MUST refuse a duration whose total exceeds the largest Bash integer rather than returning a wrapped value.
- **FR-016**: The module MUST provide predicates reporting whether one date comes strictly before, or strictly after, another, both parsed in the configured timezone, and MUST stop the script when either date cannot be parsed.
- **FR-017**: The module MUST print the ISO 8601 week a date falls in together with its week-year, default `%G-W%V`, accepting `%G`, `%V`, `%u`, and `%%` in the format and copying anything else, and computing the week from the day of the year and the day of the week so that the answer does not depend on the platform's `date`.
- **FR-018**: The module MUST print a date, parsed in the configured timezone, as it reads in a named target timezone, default format `%F %T %z`. It MUST accept `UTC`, `GMT`, and any path-shaped name that exists under `TZDIR` or `/usr/share/zoneinfo`, and MUST stop the script for any other zone rather than letting `date` fall back to UTC.

### Key Entities *(include if feature involves data)*

- **Date String**: A caller-provided textual date or datetime value parsed by the underlying `date` command.
- **Unix Timestamp**: A seconds-since-epoch integer used for storage and arithmetic.
- **Day Offset**: A signed whole-number amount of days applied to a base date.
- **Duration**: A written length of time, in seconds, parts with units, a clock, or ISO 8601, measured in fixed-length units only.
- **ISO Week**: A Monday-based week number paired with the week-year it belongs to, which differs from the calendar year around January 1.

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
- **IT-014**: Parse bare seconds, every unit, spaced and zero-padded parts, zero, and negative values into seconds.
- **IT-015**: Round-trip the clock helper's output through the duration parser, and refuse a clock with out-of-range or unpadded minutes.
- **IT-016**: Parse ISO 8601 durations of weeks, days, hours, minutes, and seconds, and refuse months, years, and empty designators.
- **IT-017**: Refuse malformed durations with a message, leave the target variable unchanged, and refuse an invalid variable name.
- **IT-018**: Accept the largest Bash integer and refuse every duration whose total would exceed it.
- **IT-019**: Order earlier, later, and identical moments with both predicates.
- **IT-020**: Stop the script when either compared date cannot be parsed.
- **IT-021**: Compute ISO weeks across year boundaries and in 53-week and 52-week years.
- **IT-022**: Write an ISO week with each format placeholder, a literal percent, and an unknown placeholder, and fail on an unparseable date.
- **IT-023**: Convert a date into another zone, into UTC, and across a daylight-saving offset from a non-UTC source zone.
- **IT-024**: Refuse an unknown zone, a path, an absolute zone file, and a POSIX rule string, and follow a zone database moved through `TZDIR`.
- **IT-025**: Detect a `date` that accepts `-d` but has no `--version` as GNU, and one that takes `-D` as BusyBox.

## Acceptance Criteria *(mandatory)*

1. The module covers the common date/time workflows advertised in examples and docs.
2. Output-oriented helpers print focused results suitable for command substitution.
3. Validation helpers use shell success and failure semantics suitable for control flow.
