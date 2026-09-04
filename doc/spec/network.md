# Feature Specification: HTTP Request and Download Utilities

**Feature Branch**: `[reverse-spec-network]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/network.sh"

## Problem Statement *(mandatory)*

Shell scripts frequently need resilient HTTP access, file downloads, JSON-friendly requests, and lightweight HEAD requests, but raw curl usage alone does not provide consistent retry behavior, status interpretation, or user-facing progress semantics. Scripts also often need multipart uploads, resumable downloads with integrity verification, normalized access to response status/headers/body, per-request timeout overrides, and protection against repeatedly calling a failing endpoint.

## Business Value *(mandatory)*

- Standardize HTTP request handling around curl.
- Give scripts a consistent retry and status-code contract for remote calls.
- Simplify file downloads by managing destination preparation automatically.
- Provide higher-level entry points for common JSON and metadata request patterns.
- Support multipart uploads without hand-building `-F` flags.
- Allow large downloads to resume from where they stopped and verify integrity via checksum.
- Expose response status, headers, and body through a normalized, script-friendly contract.
- Let callers override connect/total timeouts for a single request without touching global configuration.
- Protect scripts and downstream services from repeatedly calling a failing endpoint via a circuit breaker.

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

---

### User Story 3 - Upload multipart form data (Priority: P2)

As a script author, I want a helper that builds `-F` flags from simple `name=value`/`name=@path` pairs so that I can upload files and fields without hand-writing curl multipart syntax.

**Why this priority**: Multipart uploads are a common integration need (artifact publishing, webhook attachments) that benefit from validated, readable syntax.

**Independent Test**: Upload a mix of value and file fields and verify the resulting curl invocation contains the expected `-F` flags, and that referencing a missing file fails clearly.

**Acceptance Scenarios**:

1. **Given** a mix of `name=value` and `name=@path` fields, **When** the upload helper runs, **Then** curl receives one `-F` flag per field and the request defaults to `POST`
2. **Given** a `name=@path` field references a file that does not exist, **When** the upload helper runs, **Then** the helper fails with a dedicated exit code before invoking curl

---

### User Story 4 - Resume downloads and verify integrity (Priority: P2)

As an operator, I want downloads to resume partial transfers and optionally verify a checksum so that large or unreliable downloads can complete without corruption.

**Why this priority**: Large artifact downloads are prone to interruption; resuming avoids wasted bandwidth and checksum verification catches corruption.

**Independent Test**: Interrupt and resume a download and verify the resume flag is passed to curl; verify checksum success and mismatch paths.

**Acceptance Scenarios**:

1. **Given** a destination file already has partial content, **When** the resume download helper runs, **Then** curl is invoked with the resume flag
2. **Given** an expected checksum is supplied, **When** the download completes, **Then** the helper verifies the checksum and reports a dedicated failure code on mismatch

---

### User Story 5 - Parse normalized response status/headers/body (Priority: P2)

As a script author, I want response status, headers, and body location normalized into predictable variables so that I can branch on response metadata without re-parsing raw curl header dumps.

**Why this priority**: Consistent, script-friendly access to response metadata reduces ad hoc header parsing scattered across calling scripts.

**Independent Test**: Parse a captured header dump (including one with a redirect) and verify the exposed status, header map, and body path reflect only the final response block.

**Acceptance Scenarios**:

1. **Given** a header dump with a single response block, **When** the response is parsed, **Then** the status code and headers are available through normalized state and a header getter
2. **Given** a header dump containing a redirect followed by a final response, **When** the response is parsed, **Then** only the final block's status and headers are retained

---

### User Story 6 - Apply per-request timeouts and a circuit breaker (Priority: P3)

As an operator, I want to override connect/total timeouts for a single request and guard repeated failing calls with a circuit breaker so that one slow or failing endpoint does not stall or overwhelm a script.

**Why this priority**: Per-request timeout overrides and circuit breaking are resiliency conveniences layered on top of the core request helper.

**Independent Test**: Override timeouts for a single call and confirm global defaults are unaffected; drive a circuit breaker past its failure threshold and confirm it short-circuits further attempts until the cooldown elapses.

**Acceptance Scenarios**:

1. **Given** a connect and/or total timeout is supplied for one request, **When** the request runs, **Then** curl receives the scoped timeout flags and global timeout configuration is left untouched afterward
2. **Given** consecutive failures reach the configured threshold, **When** a circuit-breaker-guarded command is invoked again before the cooldown elapses, **Then** the command is not attempted and a dedicated exit code is returned

---

## Edge Cases

- Curl is not installed.
- The request returns a 3xx, 4xx, or 5xx status.
- The request output is omitted, in which case it is discarded to `/dev/null`.
- The caller wants JSON headers or HEAD-only metadata without rebuilding curl flags manually.
- Retry configuration is overridden through base/max delay, jitter, connect
  timeout, or total timeout environment variables.
- A response includes a numeric `Retry-After` header.
- An upload field references a file path that does not exist.
- A checksum spec uses an unsupported algorithm or the checksum tool isn't installed.
- A header dump contains multiple response blocks from one or more redirects.
- A header dump has no status line at all.
- A requested response header is missing and no default is supplied.
- Per-request timeout overrides are partially supplied (only connect, only total, or neither).
- A circuit breaker's cooldown elapses, allowing a half-open trial request.

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
- **FR-009**: Requests MUST retry server errors, transport failures, and
  transient 408/425/429 responses, while completing non-transient 4xx
  responses without retrying.
- **FR-010**: Retry delays MUST support configurable base and maximum values,
  optional jitter, and numeric `Retry-After` response headers.
- **FR-011**: Requests MUST honor optional connect and total curl timeouts.
- **FR-012**: Dry-run mode MUST print the planned curl command without making a
  network request.
- **FR-013**: The module MUST expose an upload helper that converts `name=value`/`name=@path`
  pairs into curl `-F` flags, validates that referenced files exist, and defaults to `POST`
  while allowing the method to be overridden.
- **FR-014**: The module MUST expose a resumable download helper that adds curl's resume flag
  and creates the destination directory automatically, reusing the request helper's retry
  and status contract.
- **FR-015**: The module MUST expose a checksum verification helper supporting `sha256`,
  `sha1`, and `md5`, usable standalone or as part of a resumable download.
- **FR-016**: The module MUST expose a response parser that normalizes the last status line,
  a lower-cased header map, and the body file path from a captured header dump, and a getter
  for individual headers with an optional default.
- **FR-017**: The module MUST expose a request helper that combines the core request helper
  with response parsing, skipping parsing while dry-run is enabled.
- **FR-018**: The module MUST expose a helper to scope connect/total timeout overrides to a
  single request without mutating global timeout configuration.
- **FR-019**: The module MUST expose an in-memory circuit breaker keyed by name that opens
  after a configurable consecutive-failure threshold, rejects calls while open, and allows a
  trial request after a configurable cooldown, along with helpers to inspect and reset state.

### Key Entities *(include if feature involves data)*

- **HTTP Attempt**: One curl execution performed within a request workflow.
- **Download Target**: The destination file path prepared and populated by the download helper.
- **Retry Policy**: Retry budget, exponential delay bounds, optional jitter,
  and server-provided retry delay.
- **Upload Field**: A `name=value` or `name=@path` pair converted into a curl `-F` flag.
- **Checksum Spec**: An `algorithm:hexdigest` pair used to verify downloaded file integrity.
- **Normalized Response**: The parsed status code, lower-cased header map, and body file path
  exposed after a request.
- **Circuit Breaker State**: Per-key consecutive failure count and open timestamp used to decide
  whether a guarded command may run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Callers can perform remote requests without hand-writing curl retry loops.
- **SC-002**: Download workflows succeed with minimal setup code when the destination path is valid.
- **SC-003**: Remote failures can be distinguished by status class through the helper return code contract.
- **SC-004**: Transient failures recover according to bounded, configurable
  retry behavior without retrying ordinary client errors.
- **SC-005**: Multipart uploads and resumable, checksum-verified downloads can be performed
  without callers hand-building curl flags or checksum commands.
- **SC-006**: Response status, headers, and body location are accessible through normalized
  state rather than ad hoc parsing of raw curl output.
- **SC-007**: A single request's timeout can be adjusted without affecting global retry/timeout
  configuration used by other requests.
- **SC-008**: A repeatedly failing endpoint stops receiving new attempts once its circuit opens,
  and recovers automatically once the cooldown elapses and a trial request succeeds.

## Integration Tests *(mandatory)*

- **IT-001**: Run a successful request and verify the body is written and exit status is zero.
- **IT-002**: Run a request that returns a 4xx response and verify the helper returns the mapped client-error code after request completion.
- **IT-003**: Run a download to a nested path and verify directory creation plus fetched file content.
- **IT-004**: Verify transient status retries, `Retry-After`, jitter/timeout
  settings, and final status mapping.
- **IT-005**: Verify JSON and HEAD wrappers add their documented curl options,
  and dry-run avoids network access.
- **IT-006**: Verify the upload helper emits one `-F` flag per field, defaults to `POST`,
  allows the method to be overridden, and fails when a referenced file is missing.
- **IT-007**: Verify the resumable download helper passes curl's resume flag and both verifies
  a matching checksum and fails a mismatched one with a dedicated exit code.
- **IT-008**: Verify the response parser extracts status/headers/body from a single-block
  dump, retains only the last block after a redirect, and fails without a status line; verify
  the header getter returns a value, a default, or fails when both are absent.
- **IT-009**: Verify the combined request helper populates normalized state on success and
  skips parsing while dry-run is enabled.
- **IT-010**: Verify scoped timeout overrides reach curl for a single call while leaving global
  timeout environment variables unchanged afterward, and that non-numeric overrides are rejected.
- **IT-011**: Verify a circuit breaker stays closed under the failure threshold, opens and
  short-circuits calls once the threshold is reached, and closes again after a successful call.

## Acceptance Criteria *(mandatory)*

1. The module turns raw curl usage into a higher-level, testable contract for automation scripts.
2. Request and download behavior remain predictable enough for use in CI and scripted environments.
3. Multipart uploads, resumable/checksum-verified downloads, normalized response parsing,
   per-request timeout overrides, and the circuit breaker are covered by the same testable
   contract as the existing request helpers.
