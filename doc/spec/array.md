# Feature Specification: Array Utilities

**Feature Branch**: `[reverse-spec-array]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/array.sh"

## Problem Statement *(mandatory)*

Bash scripts often need simple array operations such as printing, reversing, deduplicating, and joining, but built-in shell syntax is verbose and easy to misuse.

## Business Value *(mandatory)*

- Reduce repeated array-manipulation boilerplate.
- Keep array workflows readable in scripts and examples.
- Provide predictable by-name array operations for callers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Inspect array content quickly (Priority: P1)

As a script author, I want to print an array one element per line so that I can debug or stream its values into other tools.

**Why this priority**: Printing is the simplest and most common array inspection workflow.

**Independent Test**: Pass an array name to the print helper and verify each element is emitted on its own line in the original order.

**Acceptance Scenarios**:

1. **Given** an array contains multiple values, **When** the print helper is called by name, **Then** each element is printed on a separate line
2. **Given** an element contains spaces, **When** the print helper runs, **Then** the full element is preserved as one logical value

---

### User Story 2 - Transform arrays in place (Priority: P1)

As a maintainer, I want reverse and unique operations to modify arrays by name so that calling code stays concise.

**Why this priority**: In-place transformations remove extra copying code from shell scripts.

**Independent Test**: Apply reverse and unique helpers to named arrays and verify the target arrays are updated correctly.

**Acceptance Scenarios**:

1. **Given** an array has ordered values, **When** the reverse helper runs, **Then** the target array order is inverted
2. **Given** an array contains duplicate values, **When** the unique helper runs, **Then** duplicate entries are removed from the target array

---

### Edge Cases

- The input array is empty.
- The array contains sparse indexes.
- Elements contain spaces or repeated values.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST print array elements by array name.
- **FR-002**: The module MUST support in-place reversal of a named array.
- **FR-003**: The module MUST support in-place duplicate removal of a named array.
- **FR-004**: The module MUST support joining array elements with an arbitrary separator.
- **FR-005**: Reverse and unique operations MUST optionally print their resulting values when explicitly requested.

### Key Entities *(include if feature involves data)*

- **Named Array**: A Bash array referenced by variable name rather than copied by value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Common array tasks can be expressed with one helper call instead of custom shell loops.
- **SC-002**: Array helpers preserve element boundaries when values contain spaces.
- **SC-003**: Consumers can both mutate arrays and emit their results when needed.

## Integration Tests *(mandatory)*

- **IT-001**: Reverse a sparse array and verify the resulting order is correct.
- **IT-002**: Deduplicate an array with repeated string values and verify only unique values remain.
- **IT-003**: Join an array with multi-character separators and verify the exact output string.

## Acceptance Criteria *(mandatory)*

1. The module covers the core array workflows advertised in the library README and docs.
2. All array operations are invoked by array name so callers can compose them naturally in Bash.
