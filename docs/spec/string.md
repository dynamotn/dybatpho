# Feature Specification: String Utilities

**Feature Branch**: `[reverse-spec-string]`
**Status**: Implemented
**Input**: Existing source analysis: `src/string.sh`, `docs/string.md`, `test/string.bats`, and `example/string_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts repeatedly need trimming, splitting, exact prefix/suffix/substring checks, exact text replacement, exact prefix/suffix removal, character trimming, line counting, truncation, wrapping, blank checks, slug creation, URL-safe transformations, case normalization, regular expression captures, and "did you mean" suggestions, but native shell syntax for these tasks is terse and inconsistent.

## Business Value *(mandatory)*

- Give script authors predictable string primitives.
- Reduce custom parameter-expansion logic in consumer scripts.
- Make shell output normalization and URL handling easier to reuse.
- Make common exact-match string checks and replacements more readable in calling scripts.
- Keep exact affix-removal workflows inside reusable helpers instead of inline parameter expansion.
- Make shell-safe identifiers and filenames easier to derive from free-form labels.
- Cover more day-to-day formatting workflows such as truncating labels, wrapping output, and checking blank values.
- Let any script, not only the CLI parser, extract fields with a regular expression and suggest the word a user probably meant.

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

### User Story 7 - Extract fields with a regular expression (Priority: P2)

As a script author, I want a regex helper that hands back its capture groups so that I can pull a version, key, or identifier apart without reaching into `BASH_REMATCH` by hand.

**Why this priority**: Parsing structured strings is common, and the raw `[[ =~ ]]` form is easy to get wrong when the pattern is quoted.

**Independent Test**: Match strings with and without optional groups, a miss, and an invalid pattern, then verify the array contents and exit status.

**Acceptance Scenarios**:

1. **Given** a string matching a pattern with three groups, **When** the match helper runs, **Then** the array holds the whole match at index 0 and each group after it
2. **Given** an optional group that does not participate, **When** the match helper runs, **Then** that group is an empty element and later groups keep their indexes
3. **Given** a string that does not match, **When** the match helper runs, **Then** it returns 1 and the array is empty
4. **Given** an invalid pattern, **When** the match helper runs, **Then** it returns 2 and the array is empty

---

### User Story 8 - Suggest the closest word (Priority: P3)

As a script author, I want an edit-distance helper and a ranking helper so that I can answer a mistyped word with "did you mean" in any script.

**Why this priority**: The CLI parser already does this for its own options; other scripts accept words too (subcommands dispatched by hand, environment names, profile names).

**Independent Test**: Measure distances for known pairs, then rank candidate lists with ties, duplicates, empty entries, and nothing close.

**Acceptance Scenarios**:

1. **Given** `kitten` and `sitting`, **When** the distance helper runs, **Then** it prints `3`
2. **Given** a typo and a candidate list, **When** the closest helper runs, **Then** the array holds every candidate sharing the smallest distance within the maximum, in input order
3. **Given** no candidate within the maximum distance, **When** the closest helper runs, **Then** it returns 1 and the array is empty

---

### Example Workflow

```bash
raw="  Release Notes: v1.5.0 (Beta)  "
title="$(dybatpho::trim "${raw}")"

slug="$(dybatpho::string_slugify "${title}")"        # release-notes-v1-5-0-beta
dybatpho::info "writing ${slug}.md"

if dybatpho::string_starts_with "${title}" "Release"; then
  body="$(dybatpho::string_trim_prefix "${title}" "Release Notes: ")"
  dybatpho::info "$(dybatpho::string_truncate "${body}" 10)"
fi

query="q=$(dybatpho::url_encode "${title}")"
printf '%s\n' "$(dybatpho::string_pad "name" 12)|$(dybatpho::upper "${slug}")"

local -a parts=() guesses=()
dybatpho::string_match parts "v1.24.3" '^v([0-9]+)\.([0-9]+)\.([0-9]+)$' \
  && dybatpho::info "major ${parts[1]}"
dybatpho::string_closest guesses "staus" 2 status start stash \
  && dybatpho::warn "Did you mean ${guesses[0]}?"
```

## Edge Cases

- The input string is empty.
- The delimiter used for splitting is multi-character or empty.
- Exact-match helpers receive empty prefixes, suffixes, substrings, or replacement needles.
- Exact affix trimming receives matching, non-matching, or empty prefixes and suffixes.
- Slug creation receives punctuation-heavy or separator-only input.
- Repeat counts may be zero or negative.
- Padding tokens may be omitted, empty, or longer than one character.
- Wrapping may receive blank input or a width smaller than one word.
- Encoding input contains reserved or unreserved URL characters.
- A regular expression is invalid, has groups that do not participate, or is matched against empty or special-character text.
- The receiving array already holds an earlier result.
- Edit distance is measured against an empty string, between strings differing only in case, or on multibyte characters.
- A candidate list is empty, contains duplicates or empty entries, or has several candidates tied at the best distance.
- The maximum distance is zero, negative, or not a number.

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

- **FR-022**: The module MUST convert a string to `snake_case`, `kebab-case`, `camelCase`, and `PascalCase`, accepting input written in any of those conventions or separated by whitespace or punctuation.
- **FR-022a**: Word splitting MUST break before a capital that follows a lowercase letter or a digit, and at the end of a run of capitals followed by a lowercase letter, so that `XMLHttpRequest` reads as three words.
- **FR-022b**: Word splitting MUST keep a digit attached to the word before it, and MUST return nothing for input holding no letters or digits.
- **FR-023**: The module MUST provide a helper that quotes a value so the shell reads it back as one literal, including the empty string, for use in shell code that will be evaluated later.
- **FR-024**: The module MUST provide a regular expression helper that writes the whole match and every capture group into a caller-named array, with a non-participating group as an empty element.
- **FR-024a**: The regular expression helper MUST return 1 and empty the array when the string does not match, and MUST return 2 and empty the array when the pattern is invalid.
- **FR-024b**: The array name MUST be validated before it is written, and a name reserved for the library MUST be refused.
- **FR-025**: The module MUST provide a helper that prints the Levenshtein edit distance between two strings, counted in characters under the active locale and case-sensitive.
- **FR-026**: The module MUST provide a helper that writes into a caller-named array every candidate sharing the smallest edit distance from the input, within a caller-given maximum, in input order, without duplicates, and skipping empty candidates.
- **FR-026a**: The closest-candidate helper MUST return 1 and empty the array when no candidate is close enough, and MUST stop the script when the maximum distance is not a non-negative integer.
- **FR-027**: `dybatpho::cli_levenshtein` MUST keep answering exactly as the distance helper.

### Key Entities *(include if feature involves data)*

- **Input String**: The caller-provided text value to normalize, split, match, replace, repeat, pad, encode, decode, or case-convert.
- **Search Fragment**: The prefix, suffix, substring, or replacement target used by exact-match string helpers.
- **Affix Fragment**: A caller-provided exact prefix or suffix that may be removed from the input.
- **Slug Separator**: The normalized `-` separator inserted between slug tokens.
- **Padding Token**: The character or token appended repeatedly to extend a string to a requested width.
- **Match Array**: The caller-named array receiving the whole match at index 0 and each capture group after it.
- **Candidate List**: The words an input is compared against when ranking by edit distance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Callers can express common string transformations with single-purpose helpers.
- **SC-002**: Callers can express common exact-match conditions and replacements without inline parameter expansion.
- **SC-003**: Callers can trim exact prefixes and suffixes without repeating parameter expansion in consumer scripts.
- **SC-004**: Callers can derive shell-friendly slugs from human-readable labels with one helper call.
- **SC-005**: Callers can generate simple repeated and padded output without manual shell loops.
- **SC-006**: Encoding and decoding behavior is predictable for common HTTP use cases.
- **SC-007**: String utilities remain safe to chain in pipes or command substitutions.
- **SC-008**: Callers can extract capture groups and build "did you mean" suggestions with one helper call each.

## Integration Tests *(mandatory)*

- **IT-001**: Trim an input with surrounding spaces and verify only interior text remains.
- **IT-002**: Split a string using a multi-character delimiter and verify each segment is printed once.
- **IT-003**: Validate exact prefix, suffix, and substring checks using positive, negative, and empty-pattern cases.
- **IT-004**: Validate exact replacement behavior for repeated matches, missing matches, and empty search needles.
- **IT-005**: Validate exact prefix/suffix trimming with matching and non-matching affixes.
- **IT-006**: Validate slugify behavior for punctuation-heavy, mixed-case, and separator-only inputs.
- **IT-007**: Validate repeat behavior for positive and zero counts plus padding behavior for default and custom pad tokens.
- **IT-008**: Encode and decode values containing spaces, `+`, and `%` sequences to verify expected behavior.
- **IT-009**: Convert names written in each convention, and separated by spaces and punctuation, and verify all four outputs agree on the word boundaries.
- **IT-010**: Verify a run of capitals breaks where the word ends, that a digit stays attached to the word before it, and that input with no letters or digits returns nothing.
- **IT-011**: Verify the kebab helper and the slug helper differ on a name whose word boundaries are implied by its case.
- **IT-012**: Verify the quoting helper round-trips through `eval` for values containing spaces, quotes, `$`, a semicolon, a tab, a glob, and the empty string.
- **IT-013**: Match a version against a three-group pattern and verify the whole match and each group, and verify a non-participating group is an empty element.
- **IT-014**: Verify a miss returns 1 and an invalid pattern returns 2, each leaving the array empty, and that an invalid array name is refused.
- **IT-015**: Verify edit distances for known pairs, empty strings, case differences, and multibyte characters, and that `dybatpho::cli_levenshtein` agrees with the distance helper.
- **IT-016**: Rank candidate lists with ties, duplicates, empty entries, a zero maximum, and nothing close, and verify an invalid maximum or array name is refused.

## Acceptance Criteria *(mandatory)*

1. The module covers the major string transformations, exact-match checks, affix trimming, slug creation, replacement workflows, and output-formatting helpers advertised in examples and tests.
2. Predicate-style helpers use shell success and failure semantics suitable for control flow.
3. Output-oriented helpers keep a focused stdout contract for easy shell composition.
4. Helpers that return several values write them into a caller-named array and validate that name first.
