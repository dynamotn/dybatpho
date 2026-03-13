# Feature Specification: Validation, Predicates, Retry, and Breakpoint Helpers

**Feature Branch**: `[reverse-spec-helpers]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/helpers.sh"

## Problem Statement *(mandatory)*

Shell scripts frequently repeat argument checks, environment guards, command presence checks, generic predicates, fallback-value selection, env defaults, retry loops, assertions, and ad hoc interactive debugging hooks. Re-implementing these primitives in every script increases inconsistency and failure risk.

## Business Value *(mandatory)*

- Standardize fail-fast validation at script boundaries.
- Reduce duplication of shell condition checks and retry loops.
- Provide a simple escape hatch for interactive debugging in complex scripts.
- Make fallback configuration selection consistent across scripts.
- Cover more of the small guardrails that shell scripts usually re-implement locally.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fail fast on bad input (Priority: P1)

As a function author, I want reusable argument and environment validation so that scripts stop immediately when required inputs are missing.

**Why this priority**: Bad input validation is one of the most common shell failure points and should be solved centrally.

**Independent Test**: Use the expectation helpers with valid and invalid inputs and verify assignment, success, and failure behavior.

**Acceptance Scenarios**:

1. **Given** a reusable function expects named arguments, **When** the argument helper runs with complete input, **Then** the requested local variables are assigned in order
2. **Given** a required environment variable is empty or missing, **When** the environment helper runs, **Then** execution stops with a clear failure

---

### User Story 2 - Retry transient operations safely (Priority: P1)

As an operator, I want retry logic with progress messages so that flaky commands such as network requests can recover without custom loops in every script.

**Why this priority**: Retries are a cross-cutting operational concern and a frequent source of duplicated code.

**Independent Test**: Run a command that succeeds after one or more failures and verify retries, delay progression, and final outcomes.

**Acceptance Scenarios**:

1. **Given** a command fails initially but later succeeds, **When** the retry helper wraps it, **Then** the command is retried until it succeeds or retries are exhausted
2. **Given** a command never succeeds, **When** the retry budget is consumed, **Then** the helper returns the final failure and warns that retries are exhausted

---

### User Story 3 - Choose the first usable fallback value (Priority: P2)

As a script author, I want a coalesce helper so that environment variables, arguments, and defaults can be checked in priority order without hand-written branching.

**Why this priority**: Fallback selection is a small but common helper pattern across shell entrypoints.

**Independent Test**: Pass empty and non-empty values to the coalesce helper and verify it prints the first non-empty value or fails when none exist.

**Acceptance Scenarios**:

1. **Given** several candidate values and only one early value is non-empty, **When** the coalesce helper runs, **Then** it prints that first non-empty value
2. **Given** all candidate values are empty, **When** the coalesce helper runs, **Then** it fails without printing output

---

### Edge Cases

- A variable name passed to the argument helper is invalid.
- A predicate is asked to evaluate an unsupported condition.
- Coalesce receives no candidate values or only empty values.
- Retry is used with a noisy shell command string that needs a shorter description.
- The caller wants fixed-delay retries instead of escalating delays.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST assign positional inputs into named variables through a reusable expectation helper.
- **FR-002**: The module MUST verify that required environment variables are set.
- **FR-003**: The module MUST verify that external commands are installed before work proceeds.
- **FR-004**: The module MUST provide a generic predicate helper for file-system, command, numeric, boolean, and variable-state checks.
- **FR-005**: The module MUST provide a coalesce helper that prints the first non-empty value from a prioritized list of candidates.
- **FR-006**: The coalesce helper MUST fail when no candidate values are provided or all candidates are empty.
- **FR-007**: The module MUST provide a retry helper that retries shell command strings with delays and user-visible progress messages.
- **FR-008**: The module MUST provide an interactive breakpoint helper suitable for optional debugging workflows.
- **FR-009**: The module MUST provide a helper that verifies all listed commands exist.
- **FR-010**: The module MUST provide a helper that prints the first available command from a prioritized list.
- **FR-011**: The module MUST provide a helper that assigns and exports default values for empty environment variables.
- **FR-012**: The module MUST provide a helper that succeeds when any listed environment variable is set.
- **FR-013**: The module MUST provide an assertion helper that fails loudly when a shell condition is false.
- **FR-014**: The module MUST provide a fixed-delay retry helper in addition to the escalating retry helper.

### Key Entities *(include if feature involves data)*

- **Expectation Contract**: The named-variable input contract declared by a reusable shell function.
- **Predicate Condition**: A supported condition type evaluated by the generic `dybatpho::is` helper.
- **Fallback Candidate**: One possible value considered by the coalesce helper in priority order.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Reusable functions can validate their inputs with one call instead of hand-written parsing.
- **SC-002**: Callers can select the first usable configuration value with one helper call instead of hand-written branching.
- **SC-003**: Transient command retries become consistent across network and process workflows.
- **SC-004**: Callers can express common shell predicates with readable code instead of low-level test syntax.

## Integration Tests *(mandatory)*

- **IT-001**: Use the argument helper to populate locals in a function and verify failure on missing values.
- **IT-002**: Evaluate representative predicate types such as `file`, `dir`, `command`, `true`, and `int` to verify behavior.
- **IT-003**: Pass empty and non-empty fallback candidates to coalesce and verify first-match and no-match behavior.
- **IT-004**: Run retry around a flaky command and verify escalating delays and final success.

## Acceptance Criteria *(mandatory)*

1. The module centralizes the defensive-programming patterns required by the rest of the library.
2. The helper contracts are easy to compose at the top of reusable shell functions and scripts.
3. Fallback value selection is available without open-coded `if`/`elif` chains in callers.
