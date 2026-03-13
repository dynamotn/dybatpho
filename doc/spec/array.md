# Feature Specification: Array Utilities

**Feature Branch**: `[reverse-spec-array]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/array.sh"

## Problem Statement *(mandatory)*

Bash scripts often need simple array operations such as printing, reversing, deduplicating, membership checks, index lookup, compaction, filtering, rejecting, mapping, finding values, checking every or some values, retrieving first or last elements, and joining, but built-in shell syntax is verbose and easy to misuse.

## Business Value *(mandatory)*

- Reduce repeated array-manipulation boilerplate.
- Keep array workflows readable in scripts and examples.
- Provide predictable by-name array operations for callers.
- Support common community-style lookup and cleanup workflows without custom loops.
- Allow callers to keep only values accepted by reusable predicate functions.
- Allow callers to transform array values in place with reusable mapper functions.
- Allow callers to retrieve the first value accepted by a reusable predicate without writing loops.
- Allow callers to express common quantifier and edge-value queries without open-coded loops.

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

### User Story 3 - Query and compact arrays (Priority: P2)

As a script author, I want membership, index lookup, and compaction helpers so that I can inspect and normalize arrays without hand-written loops.

**Why this priority**: Lookup and empty-value cleanup are common continuations of the existing by-name array workflow.

**Independent Test**: Query dense and sparse arrays for present and missing values, then compact arrays containing empty strings and spaced values.

**Acceptance Scenarios**:

1. **Given** an array contains a target value, **When** the membership helper runs, **Then** it returns success
2. **Given** an array contains empty-string placeholders, **When** the compaction helper runs, **Then** empty elements are removed while non-empty values remain

---

### User Story 4 - Filter arrays with predicate functions (Priority: P2)

As a script author, I want a filtering helper that reuses a predicate function so that I can keep only relevant array items without open-coded loops.

**Why this priority**: Predicate-based filtering is a common extension once arrays already support lookup and compaction.

**Independent Test**: Filter dense and sparse arrays with working predicates, then verify invalid predicates fail loudly.

**Acceptance Scenarios**:

1. **Given** an array and a predicate that accepts only some values, **When** the filter helper runs, **Then** only accepted values remain
2. **Given** an invalid predicate name, **When** the filter helper runs, **Then** execution fails with a clear error

---

### User Story 5 - Map arrays with transformer functions (Priority: P2)

As a script author, I want a mapping helper that rewrites each array element with a reusable function so that simple value transformations do not require custom loops.

**Why this priority**: Predicate-based filtering naturally pairs with reusable array transformations.

**Independent Test**: Map dense and sparse arrays with a working mapper, then verify mapper failures and invalid mapper names surface cleanly.

**Acceptance Scenarios**:

1. **Given** an array and a mapper that transforms each value, **When** the map helper runs, **Then** the array is replaced with transformed values in order
2. **Given** an invalid mapper name or a failing mapper, **When** the map helper runs, **Then** the failure is surfaced to the caller

---

### User Story 6 - Find the first matching array value (Priority: P2)

As a script author, I want a helper that returns the first array value accepted by a predicate so that simple searches do not require open-coded loops.

**Why this priority**: After filtering and mapping exist, finding the first matching value is a natural query primitive.

**Independent Test**: Search dense and sparse arrays with working predicates, then verify missing matches fail without output.

**Acceptance Scenarios**:

1. **Given** an array and a predicate that accepts one or more values, **When** the find helper runs, **Then** it prints the first accepted value
2. **Given** no array values satisfy the predicate, **When** the find helper runs, **Then** it fails without printing output

---

### Edge Cases

- The input array is empty.
- The array contains sparse indexes.
- Elements contain spaces or repeated values.
- The array contains empty-string placeholder elements that should be removed during compaction.
- The predicate function is missing or rejects all elements.
- The mapper function is missing or fails for one of the values.
- The find predicate matches nothing in a dense or sparse array.
- The caller asks for the first or last value of an empty array.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST print array elements by array name.
- **FR-002**: The module MUST support in-place reversal of a named array.
- **FR-003**: The module MUST support in-place duplicate removal of a named array.
- **FR-004**: The module MUST provide a membership helper that returns success when an element exists in the named array.
- **FR-005**: The module MUST provide an index lookup helper that prints the first exact-match index.
- **FR-006**: The module MUST provide a compaction helper that removes empty-string elements in place.
- **FR-007**: The module MUST provide a filtering helper that keeps only values accepted by a predicate function.
- **FR-008**: The filtering helper MUST fail with a clear error when the predicate function does not exist.
- **FR-009**: The module MUST provide a mapping helper that replaces each value with the stdout of a mapper function.
- **FR-010**: The mapping helper MUST fail with a clear error when the mapper function does not exist and MUST propagate mapper failures.
- **FR-011**: The module MUST provide a find helper that prints the first value accepted by a predicate function.
- **FR-012**: The find helper MUST fail without output when no values match.
- **FR-013**: The module MUST support joining array elements with an arbitrary separator.
- **FR-014**: Reverse, unique, compact, filter, and map operations MUST optionally print their resulting values when explicitly requested.
- **FR-015**: The module MUST provide helpers that return success when every or at least one element satisfies a predicate function.
- **FR-016**: The module MUST provide a reject helper that removes elements accepted by a predicate function.
- **FR-017**: The module MUST provide helpers that print the first and last array elements and fail for empty arrays.

### Key Entities *(include if feature involves data)*

- **Named Array**: A Bash array referenced by variable name rather than copied by value.
- **Target Element**: A caller-provided value searched for or retained during array processing.
- **Predicate Function**: A caller-visible function that decides whether a given array element should be kept.
- **Mapper Function**: A caller-visible function that transforms one array element into another printed value.
- **Matched Value**: The first array element printed by the find helper when a predicate succeeds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Common array tasks can be expressed with one helper call instead of custom shell loops.
- **SC-002**: Array helpers preserve element boundaries when values contain spaces.
- **SC-003**: Consumers can query array membership and first-match positions without custom loops.
- **SC-004**: Consumers can filter arrays by reusable predicate functions instead of writing open-coded loops.
- **SC-005**: Consumers can transform arrays with reusable mapper functions instead of writing open-coded loops.
- **SC-006**: Consumers can print the first matching array value with one helper call instead of writing open-coded loops.
- **SC-007**: Consumers can both mutate arrays and emit their results when needed.

## Integration Tests *(mandatory)*

- **IT-001**: Reverse a sparse array and verify the resulting order is correct.
- **IT-002**: Deduplicate an array with repeated string values and verify only unique values remain.
- **IT-003**: Validate membership and first-match index lookup on dense and sparse arrays.
- **IT-004**: Compact arrays containing empty strings and spaced values while preserving remaining order.
- **IT-005**: Filter arrays with valid predicates and verify invalid predicates fail loudly.
- **IT-006**: Map arrays with valid mappers and verify invalid or failing mappers surface errors.
- **IT-007**: Find the first matching value in dense and sparse arrays and verify missing matches fail without output.
- **IT-008**: Join an array with multi-character separators and verify the exact output string.

## Acceptance Criteria *(mandatory)*

1. The module covers the core array workflows advertised in the library README, docs, and examples.
2. All array operations are invoked by array name so callers can compose them naturally in Bash.
3. Lookup, compaction, predicate-based filtering, mapping, and first-match value workflows are available without requiring custom shell loops.
