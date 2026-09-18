# Feature Specification: JSON and YAML Utilities

**Feature Branch**: `[reverse-spec-json]`
**Status**: Implemented
**Input**: Existing source analysis: `src/json.sh`, `doc/json.md`, `test/json.bats`, and `example/json_ops.sh`

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

### User Story 1b - Assemble a JSON document safely (Priority: P1)

As a script author, I want to build a JSON document from shell values without
thinking about escaping, so that a quotation mark in a log line or a newline in
a commit message cannot corrupt the payload I am about to send.

**Why this priority**: hand-built JSON is the most common way a shell script
silently produces invalid output.

**Independent Test**: Build an object from values containing quotes,
backslashes, and newlines, then read each value back and compare it with the
original.

**Acceptance Scenarios**:

1. **Given** values containing JSON-sensitive characters, **When** an object is
   built, **Then** every value round-trips unchanged
2. **Given** a name carrying the `:json` suffix, **When** an object is built,
   **Then** the value is nested as a document rather than quoted as a string
3. **Given** a document held in a variable, **When** a filter is evaluated,
   **Then** the result is available either as compact JSON or as a bare scalar
4. **Given** either backend, **When** the same helpers run, **Then** they
   produce the same result

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

### Example Workflow

```bash
# Read a value, guard on a filter, and convert between formats.
version="$(dybatpho::json_query package.json '.version')"

if dybatpho::json_has package.json '.scripts.test'; then
  dybatpho::info "package.json ${version} defines a test script"
fi

dybatpho::json_to_yaml package.json package.yaml
dybatpho::yaml_query package.yaml '.name'
curl -sSf https://api.example.test/status | dybatpho::json_pretty -
```

## Edge Cases

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
- **FR-010**: The module MUST provide a helper that encodes an arbitrary string
  as a JSON string value, escaping quotes, backslashes, and control characters.
- **FR-011**: The module MUST provide a helper that builds a JSON object from
  name and value pairs, escaping every value, and MUST insert a value as-is when
  its name carries the `:json` suffix.
- **FR-012**: The object helper MUST reject an odd number of arguments.
- **FR-013**: The module MUST provide helpers that evaluate a filter against a
  document held in a shell variable, one returning compact JSON and one
  returning a bare scalar.
- **FR-014**: The module MUST provide a predicate that reports whether a string
  held in a shell variable is valid JSON.
- **FR-015**: The in-memory helpers MUST behave identically on both backends,
  which means filters written for them stay inside the subset the two share.

### Key Entities *(include if feature involves data)*

- **JSON Filter**: A caller-provided expression used to query or validate JSON input.
- **YAML Expression**: A caller-provided `yq` expression used to query or validate YAML input.
- **Structured Document**: An input JSON or YAML file path, or `-` for stdin.
- **In-Memory Document**: A JSON string a script is still assembling, held in a
  shell variable rather than written to a file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can express common JSON and YAML queries without repeating raw `yq` and `jq` command lines.
- **SC-002**: Predicate-style helpers are easy to use in shell control flow.
- **SC-003**: Conversion between JSON and YAML is available through a small reusable API.
- **SC-004**: A script can assemble a JSON document containing arbitrary text
  without thinking about escaping, and without depending on one specific backend.

## Integration Tests *(mandatory)*

- **IT-001**: Query a JSON document and verify the expected value is printed.
- **IT-002**: Check JSON existence semantics and verify success/failure behavior.
- **IT-003**: Query a YAML document and verify the expected value is printed.
- **IT-004**: Check YAML existence semantics and verify success/failure behavior.
- **IT-005**: Convert JSON to YAML and YAML to JSON with both stdout and output-file workflows.
- **IT-006**: Encode strings containing quotes, backslashes, newlines, and
  nothing at all, and verify the result is a valid JSON string value.
- **IT-007**: Build objects with escaped values, nested `:json` documents, and
  awkward names, and verify an odd argument count is rejected.
- **IT-008**: Evaluate filters against in-memory documents and verify compact
  JSON, bare scalars, and the alternative operator.
- **IT-009**: Verify the JSON predicate separates documents from prose and from
  truncated input.
- **IT-010**: Verify the in-memory helpers produce the same results under both
  the `yq` and the `jq` backend.

## Acceptance Criteria *(mandatory)*

1. The module provides practical wrappers around both `yq` and `jq`, with `yq` preferred for JSON and YAML workflows.
2. Structured-data helpers remain composable in command substitution and shell conditionals.
3. JSON and YAML workflows are documented consistently with the rest of the project.
