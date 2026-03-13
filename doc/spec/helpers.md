# Feature Specification: Validation, Predicates, Retry, and Breakpoint Helpers

**Feature Branch**: `[reverse-spec-helpers]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/helpers.sh"

## Problem Statement *(mandatory)*

Shell scripts frequently repeat argument checks, environment guards, command presence checks, generic predicates, retry loops, and ad hoc interactive debugging hooks. Re-implementing these primitives in every script increases inconsistency and failure risk.

## Business Value *(mandatory)*

- Standardize fail-fast validation at script boundaries.
- Reduce duplication of shell condition checks and retry loops.
- Provide a simple escape hatch for interactive debugging in complex scripts.

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

### Edge Cases

- A variable name passed to the argument helper is invalid.
- A predicate is asked to evaluate an unsupported condition.
- Retry is used with a noisy shell command string that needs a shorter description.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST assign positional inputs into named variables through a reusable expectation helper.
- **FR-002**: The module MUST verify that required environment variables are set.
- **FR-003**: The module MUST verify that external commands are installed before work proceeds.
- **FR-004**: The module MUST provide a generic predicate helper for file-system, command, numeric, boolean, and variable-state checks.
- **FR-005**: The module MUST provide a retry helper that retries shell command strings with delays and user-visible progress messages.
- **FR-006**: The module MUST provide an interactive breakpoint helper suitable for optional debugging workflows.

### Key Entities *(include if feature involves data)*

- **Expectation Contract**: The named-variable input contract declared by a reusable shell function.
- **Predicate Condition**: A supported condition type evaluated by the generic `dybatpho::is` helper.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Reusable functions can validate their inputs with one call instead of hand-written parsing.
- **SC-002**: Transient command retries become consistent across network and process workflows.
- **SC-003**: Callers can express common shell predicates with readable code instead of low-level test syntax.

## Integration Tests *(mandatory)*

- **IT-001**: Use the argument helper to populate locals in a function and verify failure on missing values.
- **IT-002**: Run retry around a flaky command and verify escalating delays and final success.
- **IT-003**: Evaluate representative predicate types such as `file`, `dir`, `command`, `true`, and `int` to verify behavior.

## Acceptance Criteria *(mandatory)*

1. The module centralizes the defensive-programming patterns required by the rest of the library.
2. The helper contracts are easy to compose at the top of reusable shell functions and scripts.
