# Feature Specification: Array Utilities

**Feature Branch**: `[reverse-spec-array]`
**Status**: Implemented
**Input**: Existing source analysis: `src/array.sh`, `docs/array.md`, `test/array.bats`, and `example/array_ops.sh`

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
3. **Given** an array contains empty-string values, **When** the unique helper
   runs, **Then** those empty values are omitted along with duplicates

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

### Example Workflow

```bash
services=(api worker "" api frontend)

function _is_backend { [[ "$1" == api || "$1" == worker ]]; }
function _to_unit { printf '%s.service' "$1"; }

dybatpho::array_compact services            # drop the empty placeholder
dybatpho::array_unique services             # drop the duplicate api
dybatpho::array_filter services _is_backend # keep only backend services
dybatpho::array_map services _to_unit --    # rewrite and print the result

if dybatpho::array_contains services "api.service"; then
  dybatpho::info "deploying: $(dybatpho::array_join services ", ")"
fi
```

## Edge Cases

- The input array is empty.
- The array contains sparse indexes.
- Elements contain spaces or repeated values.
- Unique operation does not promise the original order because it rebuilds the
  result through an associative array.
- The array contains empty-string placeholder elements that should be removed during compaction.
- The predicate function is missing or rejects all elements.
- The mapper function is missing or fails for one of the values.
- The find predicate matches nothing in a dense or sparse array.
- The caller asks for the first or last value of an empty array.
- An array is sparse, so its indexes do not run from 0 to its length minus one; or a helper is given, or produces, an empty array under `nounset` on Bash 4.3.
- A set operation receives an empty element in either array.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST print array elements by array name.
- **FR-002**: The module MUST support in-place reversal of a named array.
- **FR-003**: The module MUST support in-place duplicate removal of a named
  array; the helper MUST remove empty-string values and does not
  guarantee the original ordering of retained values.
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
- **FR-018**: Predicate helpers MUST treat an empty array as matching `every`
  and not matching `some` or `find`.

- **FR-019**: The module MUST sort an array in place, ordering text by the current locale's collation and, on request, comparing values as numbers so that `10` follows `9`.
- **FR-019a**: The numeric sort MUST accept whole numbers including negative ones and MUST stop the script on any other value, rather than falling back to ordering it as text.
- **FR-019b**: The sort MUST NOT depend on an external command, and MUST leave an element containing a newline intact.
- **FR-019c**: The sort MUST accept a reversing option, and MUST stop the script on an option it does not recognise.
- **FR-020**: The module MUST keep a run of an array in place, taking a start index and an optional count, where a negative start counts back from the end and a run lying outside the array leaves it empty rather than failing.
- **FR-021**: The module MUST provide union, intersection, and difference between two arrays, replacing the first in place.
- **FR-021a**: Each set operation MUST produce a set, with every value appearing once, in the order the first array had them. Difference MUST be one-sided: values only the second array holds are not added.
- **FR-022**: The helpers added here MUST NOT shadow a caller's array that happens to share a name with one of their own local variables.

- **FR-023**: The module MUST order a dependency graph given as an associative array mapping an entry to the entries it depends on, so every dependency comes before what names it.
- **FR-024**: An entry named only as a dependency MUST appear in the order, because a leaf is still something that has to come first.
- **FR-025**: Ordering MUST be deterministic across runs, which means starting from the graph's keys in a sorted order rather than the order Bash hashes them into.
- **FR-026**: Given roots, ordering MUST cover only what those roots reach.
- **FR-027**: A cycle MUST be reported through the exit code while an order is still produced, because a cycle is legitimate in some graphs and refusing to order one would refuse the graph.
- **FR-028**: The module MUST collect the entries reachable from some roots, the roots included, as a sorted set, and MUST reject a call with no root.
- **FR-029**: `array_join` MUST join the elements a sparse array holds, in index order, and every helper MUST accept and produce an empty array under `nounset` on Bash 4.3, where `"${empty[@]}"` counts as unset.
- **FR-030**: Union, intersection and difference MUST drop empty elements, as deduplication does, rather than fail on them.
- **FR-031**: Every function that takes an array by name MUST read and write the array the caller named whatever that name is, including a name the function uses for a local of its own.
- **FR-032**: The module MUST be a core module, loaded with every module set, and MUST therefore call only other core modules; `docs/spec/init.md` (FR-020, IT-019) pins it, and `doctor` builds its module-graph check on the graph helpers.

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
- **IT-009**: Sort text ascending and reversed, and verify the same values sort differently with and without the numeric option.
- **IT-010**: Verify the sort leaves an empty array, a single element, and duplicate values alone, and keeps an element containing a newline whole.
- **IT-011**: Verify the sort rejects an unknown option and a non-numeric value under the numeric option, and prints with `--`.
- **IT-012**: Sort arrays named after the helper's own locals and verify the caller's values are the ones sorted.
- **IT-013**: Slice from an index, with a count, and from a negative start; verify a start or count outside the array leaves it empty or clamps, and that `--` prints in either argument position.
- **IT-014**: Verify union, intersection, and difference against overlapping, disjoint, and empty arrays, that duplicates collapse, and that difference adds nothing from the second array.

- **IT-015**: Order a chain so each dependency precedes what needs it.
- **IT-016**: Order only what the given roots reach.
- **IT-017**: Produce the same order on two runs over the same graph.
- **IT-018**: Include an entry named only as a dependency.
- **IT-019**: Report a cycle through the exit code and still return an order.
- **IT-020**: Order the library's own module graph, with every non-cyclic edge respected.
- **IT-021**: Collect the reachable set from a root, walk a cycle without looping, and reject a call with no root.
- **IT-022**: Join a sparse array with indexes 2, 5 and 9 and verify only its three elements are joined; on Bash 4.3 run each helper on an empty array, and each filter down to an empty result, under `nounset`.
- **IT-023**: Verify union, intersection, and difference drop empty elements from either array instead of stopping.
- **IT-024**: Map an array named `status`, the name of a local `dybatpho::array_map` used, and get the mapped values back.

## Acceptance Criteria *(mandatory)*

1. The module covers the core array workflows advertised in the library README, docs, and examples.
2. All array operations are invoked by array name so callers can compose them naturally in Bash.
3. Lookup, compaction, predicate-based filtering, mapping, and first-match value workflows are available without requiring custom shell loops.
