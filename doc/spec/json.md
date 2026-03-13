# Feature Specification: JSON and YAML Utilities

**Feature Branch**: `[reverse-spec-json]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/json.sh"

## Problem Statement *(mandatory)*

Shell scripts often need to query, validate, pretty-print, and convert JSON or YAML documents, but direct `jq` and `yq` usage quickly becomes repetitive and inconsistent across scripts.

## Business Value *(mandatory)*

- Standardize common structured-data workflows around `yq`, while keeping `jq` available as a JSON fallback.
- Keep shell scripts readable when querying JSON or YAML.
- Provide one module for both machine-friendly JSON and operator-friendly YAML tasks.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Query JSON data cleanly (Priority: P1)

As a script author, I want helpers that wrap `yq` for common JSON queries and checks so that structured-data lookups stay readable in shell scripts while still remaining compatible with `jq` where needed.

**Why this priority**: JSON is a common interchange format in APIs and CLI tools.

**Independent Test**: Query a JSON document, check for a field with predicate semantics, and verify pretty-print output.

**Acceptance Scenarios**:

1. **Given** a JSON document and query filter, **When** the query helper runs, **Then** it prints the matching result
2. **Given** a JSON document and existence filter, **When** the check helper runs, **Then** it returns success only when the filter succeeds

---

### User Story 2 - Query YAML data cleanly (Priority: P1)

As a script author, I want helpers that wrap `yq` for YAML queries and checks so that configuration-file lookups stay readable in shell scripts.

**Why this priority**: YAML is common in CI, deployment, and config workflows.

**Independent Test**: Query a YAML document, check for a field, and verify pretty-print output.

**Acceptance Scenarios**:

1. **Given** a YAML document and yq expression, **When** the query helper runs, **Then** it prints the matching result
2. **Given** a YAML document and existence expression, **When** the check helper runs, **Then** it returns success only when the expression succeeds

---

### User Story 3 - Convert between JSON and YAML (Priority: P2)

As a maintainer, I want conversion helpers between JSON and YAML so that scripts can bridge API payloads and config files without custom command lines.

**Why this priority**: Conversion is a practical follow-up once both formats are supported in one module.

**Independent Test**: Convert JSON to YAML and YAML to JSON, then verify both stdout and output-file workflows.

**Acceptance Scenarios**:

1. **Given** a JSON document, **When** the conversion helper runs, **Then** it prints or writes YAML output
2. **Given** a YAML document, **When** the conversion helper runs, **Then** it prints or writes JSON output

---

### Edge Cases

- `yq` or `jq` is not installed.
- The input document path is `-` for stdin.
- The caller wants output on stdout or in a destination file.
- The YAML helpers rely on the Mike Farah `yq eval` CLI shape.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a JSON query helper that prefers `yq` and may fall back to `jq`.
- **FR-002**: The module MUST provide a JSON predicate helper that returns success when a JSON filter succeeds.
- **FR-003**: The module MUST provide a JSON pretty-print helper that prefers `yq` and may fall back to `jq`.
- **FR-004**: The module MUST provide a JSON-to-YAML conversion helper.
- **FR-005**: The module MUST provide a YAML query helper built on `yq eval`.
- **FR-006**: The module MUST provide a YAML predicate helper that returns success when a `yq` expression succeeds.
- **FR-007**: The module MUST provide a YAML pretty-print helper.
- **FR-008**: The module MUST provide a YAML-to-JSON conversion helper.
- **FR-009**: The output-oriented helpers MUST support stdout output and optional destination files where applicable.

### Key Entities *(include if feature involves data)*

- **JSON Filter**: A caller-provided expression used to query or validate JSON input.
- **YAML Expression**: A caller-provided `yq` expression used to query or validate YAML input.
- **Structured Document**: An input JSON or YAML file path, or `-` for stdin.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can express common JSON and YAML queries without repeating raw `yq` and `jq` command lines.
- **SC-002**: Predicate-style helpers are easy to use in shell control flow.
- **SC-003**: Conversion between JSON and YAML is available through a small reusable API.

## Integration Tests *(mandatory)*

- **IT-001**: Query a JSON document and verify the expected value is printed.
- **IT-002**: Check JSON existence semantics and verify success/failure behavior.
- **IT-003**: Query a YAML document and verify the expected value is printed.
- **IT-004**: Check YAML existence semantics and verify success/failure behavior.
- **IT-005**: Convert JSON to YAML and YAML to JSON with both stdout and output-file workflows.

## Acceptance Criteria *(mandatory)*

1. The module provides practical wrappers around both `yq` and `jq`, with `yq` preferred for JSON and YAML workflows.
2. Structured-data helpers remain composable in command substitution and shell conditionals.
3. JSON and YAML workflows are documented consistently with the rest of the project.
