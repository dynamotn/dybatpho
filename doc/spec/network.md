# Feature Specification: HTTP Request and Download Utilities

**Feature Branch**: `[reverse-spec-network]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/network.sh"

## Problem Statement *(mandatory)*

Shell scripts frequently need resilient HTTP access, file downloads, JSON-friendly requests, and lightweight HEAD requests, but raw curl usage alone does not provide consistent retry behavior, status interpretation, or user-facing progress semantics.

## Business Value *(mandatory)*

- Standardize HTTP request handling around curl.
- Give scripts a consistent retry and status-code contract for remote calls.
- Simplify file downloads by managing destination preparation automatically.
- Provide higher-level entry points for common JSON and metadata request patterns.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Perform resilient HTTP requests (Priority: P1)

As a script author, I want a request helper that wraps curl with retries and normalized exit codes so that remote calls are easier to reason about.

**Why this priority**: Remote requests are a critical integration point and benefit from uniform behavior.

**Independent Test**: Invoke the request helper against successful, client-error, server-error, and curl-failure cases and verify output, retries, and return codes.

**Acceptance Scenarios**:

1. **Given** a URL responds with a success status, **When** the request helper runs, **Then** the response body is written and the helper returns success
2. **Given** a URL responds with a server error or curl fails, **When** the request helper runs, **Then** the helper retries according to policy and reports the final status as a non-zero result

---

### User Story 2 - Download files into prepared destinations (Priority: P2)

As an operator, I want downloads to create their destination directories automatically so that scripts can fetch artifacts without extra setup code.

**Why this priority**: File downloads are a common convenience workflow built on top of the lower-level request helper.

**Independent Test**: Download to a nested path and verify the destination directory is created before the transfer occurs.

**Acceptance Scenarios**:

1. **Given** the destination directory does not exist, **When** the download helper runs, **Then** the directory is created before the request is made
2. **Given** the destination cannot be prepared, **When** the download helper runs, **Then** the helper returns the dedicated directory-preparation failure

---

### Edge Cases

- Curl is not installed.
- The request returns a 3xx, 4xx, or 5xx status.
- The caller omits an output file and expects a safe default destination.
- The caller wants JSON headers or HEAD-only metadata without rebuilding curl flags manually.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST expose a helper that performs HTTP requests via curl.
- **FR-002**: The request helper MUST retry failures according to the configured retry budget.
- **FR-003**: The request helper MUST map final HTTP classes into consistent shell exit codes for success, 3xx, 4xx, 5xx, and unknown failures.
- **FR-004**: The request helper MUST write the response body to the caller-specified destination or a safe default sink.
- **FR-005**: The module MUST expose a download helper that creates the destination directory automatically.
- **FR-006**: The module MUST expose an HTTP status-description helper suitable for diagnostics.
- **FR-007**: The module MUST expose a JSON-oriented curl helper that adds standard JSON headers.
- **FR-008**: The module MUST expose a HEAD-oriented curl helper that retrieves response headers without downloading a body.

### Key Entities *(include if feature involves data)*

- **HTTP Attempt**: One curl execution performed within a request workflow.
- **Download Target**: The destination file path prepared and populated by the download helper.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Callers can perform remote requests without hand-writing curl retry loops.
- **SC-002**: Download workflows succeed with minimal setup code when the destination path is valid.
- **SC-003**: Remote failures can be distinguished by status class through the helper return code contract.

## Integration Tests *(mandatory)*

- **IT-001**: Run a successful request and verify the body is written and exit status is zero.
- **IT-002**: Run a request that returns a 4xx response and verify the helper returns the mapped client-error code after request completion.
- **IT-003**: Run a download to a nested path and verify directory creation plus fetched file content.

## Acceptance Criteria *(mandatory)*

1. The module turns raw curl usage into a higher-level, testable contract for automation scripts.
2. Request and download behavior remain predictable enough for use in CI and scripted environments.
