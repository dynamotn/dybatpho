# Feature Specification: String Utilities

**Feature Branch**: `[reverse-spec-string]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/string.sh"

## Problem Statement *(mandatory)*

Shell scripts repeatedly need trimming, splitting, exact prefix/suffix/substring checks, exact text replacement, exact prefix/suffix removal, character trimming, line counting, truncation, wrapping, blank checks, slug creation, URL-safe transformations, and case normalization, but native shell syntax for these tasks is terse and inconsistent.

## Business Value *(mandatory)*

- Give script authors predictable string primitives.
- Reduce custom parameter-expansion logic in consumer scripts.
- Make shell output normalization and URL handling easier to reuse.
- Make common exact-match string checks and replacements more readable in calling scripts.
- Keep exact affix-removal workflows inside reusable helpers instead of inline parameter expansion.
- Make shell-safe identifiers and filenames easier to derive from free-form labels.
- Cover more day-to-day formatting workflows such as truncating labels, wrapping output, and checking blank values.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Normalize user or script input (Priority: P1)

As a script author, I want to trim and case-convert values so that downstream validation and comparisons are simpler.

**Why this priority**: Normalization is a prerequisite for many other shell workflows.

**Independent Test**: Call trim, lower, and upper helpers on representative inputs and verify the returned text matches the expected normalization.

**Acceptance Scenarios**:

1. **Given** input contains surrounding whitespace, **When** the trim helper runs, **Then** leading and trailing whitespace are removed
2. **Given** input uses mixed case, **When** the lower or upper helper runs, **Then** the output is normalized to the requested case

---

### User Story 2 - Match and replace exact string fragments (Priority: P2)

As a script author, I want exact-match helpers for checking and replacing string fragments so that common string conditions do not require inline parameter expansion in every caller.

**Why this priority**: Prefix, suffix, substring, and exact replacement logic are common shell tasks that fit naturally beside trim and split.

**Independent Test**: Call the matching helpers with positive, negative, and empty-pattern inputs, then verify replacement behavior for repeated matches and empty needles.

**Acceptance Scenarios**:

1. **Given** an input string and a matching prefix, suffix, or substring, **When** the corresponding exact-match helper runs, **Then** it returns success
2. **Given** a string with repeated exact matches, **When** the replacement helper runs, **Then** every exact match is replaced in the output

---

### User Story 3 - Trim exact prefixes and suffixes (Priority: P2)

As a script author, I want helpers that remove exact prefixes or suffixes when present so that ref names, archive names, and similar values can be normalized without repeating parameter expansion.

**Why this priority**: Exact affix trimming is a common follow-up once exact matching and replacement helpers exist.

**Independent Test**: Remove matching and non-matching prefixes and suffixes, then verify non-matching patterns leave the original string intact.

**Acceptance Scenarios**:

1. **Given** an input string with a matching exact prefix, **When** the trim-prefix helper runs, **Then** the prefix is removed
2. **Given** an input string without a matching suffix, **When** the trim-suffix helper runs, **Then** the original string is returned unchanged

---

### User Story 4 - Create shell-friendly slugs (Priority: P2)

As a script author, I want a slugify helper so that titles, labels, and names can be turned into predictable lowercase identifiers for files, URLs, or tags.

**Why this priority**: Slug creation is a common string cleanup workflow that complements trim and case-conversion helpers.

**Independent Test**: Slugify strings containing punctuation, spaces, underscores, and mixed case, then verify separators collapse and digits remain.

**Acceptance Scenarios**:

1. **Given** an input string with spaces and punctuation, **When** the slugify helper runs, **Then** the output is lowercase and separated with single hyphens
2. **Given** an input string made only of separator characters, **When** the slugify helper runs, **Then** the output is empty

---

### User Story 5 - Repeat and pad shell strings (Priority: P2)

As a script author, I want helpers to repeat text and pad strings to a minimum width so that I can generate simple banners, separators, and aligned output without manual loops.

**Why this priority**: Repeat and pad are small but common presentation helpers that complement the rest of the string module.

**Independent Test**: Repeat short text for positive and zero counts, then pad strings with default and custom pad tokens.

**Acceptance Scenarios**:

1. **Given** an input string and a positive repeat count, **When** the repeat helper runs, **Then** the output contains the input repeated exactly that many times
2. **Given** an input string shorter than the requested width, **When** the pad helper runs, **Then** the output is extended on the right to the requested width

---

### User Story 6 - Encode and decode URL-safe values (Priority: P2)

As a maintainer, I want URL encode/decode helpers so that scripts can safely pass query or path values across HTTP boundaries.

**Why this priority**: Network-facing scripts frequently need portable encoding behavior.

**Independent Test**: Encode and decode strings containing spaces, reserved characters, and plus signs, then verify round-trip behavior where applicable.

**Acceptance Scenarios**:

1. **Given** a string contains reserved URL characters, **When** the encode helper runs, **Then** reserved characters are percent-encoded
2. **Given** an encoded string contains `%` sequences and plus signs, **When** the decode helper runs, **Then** the caller receives a decoded value with spaces handled correctly

---

### Edge Cases

- The input string is empty.
- The delimiter used for splitting is multi-character or empty.
- Exact-match helpers receive empty prefixes, suffixes, substrings, or replacement needles.
- Exact affix trimming receives matching, non-matching, or empty prefixes and suffixes.
- Slug creation receives punctuation-heavy or separator-only input.
- Repeat counts may be zero or negative.
- Padding tokens may be omitted, empty, or longer than one character.
- Wrapping may receive blank input or a width smaller than one word.
- Encoding input contains reserved or unreserved URL characters.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST trim leading and trailing whitespace from a string input.
- **FR-002**: The module MUST split a string using an exact delimiter and print each segment separately.
- **FR-003**: The module MUST provide helpers for exact prefix, suffix, and substring checks.
- **FR-004**: The module MUST provide an exact substring replacement helper that prints the transformed string.
- **FR-005**: The replacement helper MUST leave the original string unchanged when the search substring is empty.
- **FR-006**: The module MUST provide exact prefix- and suffix-trimming helpers that print transformed strings.
- **FR-007**: The trim helpers MUST leave the original string unchanged when the target affix does not match.
- **FR-008**: The module MUST provide a slugify helper that converts free-form strings into lowercase hyphen-separated output.
- **FR-009**: The slugify helper MUST collapse repeated separators and trim separator-only prefixes or suffixes.
- **FR-010**: The module MUST provide a repeat helper that prints a string repeated a fixed number of times.
- **FR-011**: The module MUST provide a right-padding helper that expands a string to a minimum width.
- **FR-012**: The repeat helper MUST return an empty string when the repeat count is zero or negative.
- **FR-013**: The pad helper MUST default to space padding when no pad token is provided.
- **FR-014**: The module MUST URL-encode non-unreserved characters.
- **FR-015**: The module MUST URL-decode percent-encoded values and `+` space notation.
- **FR-016**: The module MUST provide lowercase and uppercase conversion helpers.
- **FR-017**: The module MUST provide a blank-check helper that returns success only for whitespace-only strings.
- **FR-018**: The module MUST provide a helper that trims an exact set of boundary characters from both ends of a string.
- **FR-019**: The module MUST provide a truncation helper that limits output width and appends a configurable suffix when truncation occurs.
- **FR-020**: The module MUST provide a helper that counts logical lines in a string.
- **FR-021**: The module MUST provide a wrapping helper for width-limited output.

### Key Entities *(include if feature involves data)*

- **Input String**: The caller-provided text value to normalize, split, match, replace, repeat, pad, encode, decode, or case-convert.
- **Search Fragment**: The prefix, suffix, substring, or replacement target used by exact-match string helpers.
- **Affix Fragment**: A caller-provided exact prefix or suffix that may be removed from the input.
- **Slug Separator**: The normalized `-` separator inserted between slug tokens.
- **Padding Token**: The character or token appended repeatedly to extend a string to a requested width.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Callers can express common string transformations with single-purpose helpers.
- **SC-002**: Callers can express common exact-match conditions and replacements without inline parameter expansion.
- **SC-003**: Callers can trim exact prefixes and suffixes without repeating parameter expansion in consumer scripts.
- **SC-004**: Callers can derive shell-friendly slugs from human-readable labels with one helper call.
- **SC-005**: Callers can generate simple repeated and padded output without manual shell loops.
- **SC-006**: Encoding and decoding behavior is predictable for common HTTP use cases.
- **SC-007**: String utilities remain safe to chain in pipes or command substitutions.

## Integration Tests *(mandatory)*

- **IT-001**: Trim an input with surrounding spaces and verify only interior text remains.
- **IT-002**: Split a string using a multi-character delimiter and verify each segment is printed once.
- **IT-003**: Validate exact prefix, suffix, and substring checks using positive, negative, and empty-pattern cases.
- **IT-004**: Validate exact replacement behavior for repeated matches, missing matches, and empty search needles.
- **IT-005**: Validate exact prefix/suffix trimming with matching and non-matching affixes.
- **IT-006**: Validate slugify behavior for punctuation-heavy, mixed-case, and separator-only inputs.
- **IT-007**: Validate repeat behavior for positive and zero counts plus padding behavior for default and custom pad tokens.
- **IT-008**: Encode and decode values containing spaces, `+`, and `%` sequences to verify expected behavior.

## Acceptance Criteria *(mandatory)*

1. The module covers the major string transformations, exact-match checks, affix trimming, slug creation, replacement workflows, and output-formatting helpers advertised in examples and tests.
2. Predicate-style helpers use shell success and failure semantics suitable for control flow.
3. Output-oriented helpers keep a focused stdout contract for easy shell composition.
