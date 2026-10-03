# Feature Specification: HTTP Request and Download Utilities

**Feature Branch**: `[reverse-spec-network]`
**Status**: Implemented
**Input**: Existing source analysis: `src/network.sh`, `docs/network.md`, `test/network.bats`, and `example/network_ops.sh`

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
- Keep a script inside the call budget an API publishes, instead of discovering it through `429` responses.
- Walk a paginated collection the way the server describes it, through the `Link` header.
- Authenticate with a bearer token without publishing it in `curl`'s command line.
- Treat a GraphQL response that answers `200 OK` with an `errors` array as the failure it is.

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

### User Story 7 - Stay inside an API's call budget (Priority: P3)

As a script author, I want to cap how often a keyed operation runs so that a loop over many items does not spend an API's published rate limit and start collecting `429` responses.

**Why this priority**: Rate limiting is the counterpart to the circuit breaker: the breaker stops calling a service that is failing, and the limiter stops calling one faster than it agreed to be called.

**Independent Test**: Spend a small budget, then confirm that the next call waits for the window to slide, and that it is refused with a dedicated exit code when waiting is disabled or would exceed the configured maximum.

**Acceptance Scenarios**:

1. **Given** a key's budget still has room, **When** a command is run under the limiter, **Then** it runs immediately and the slot is recorded
2. **Given** a key's budget is spent, **When** another call is made, **Then** the limiter waits exactly until the oldest call leaves the window and then runs the command
3. **Given** waiting is disabled or the required wait exceeds the configured maximum, **When** the budget is spent, **Then** the command is not run and a dedicated exit code is returned

---

### User Story 8 - Read a paginated collection and authenticate for it (Priority: P3)

As a script author, I want to fetch every page of a collection, send a bearer token safely, and see GraphQL errors as failures so that an API client does not have to be rebuilt in each script.

**Why this priority**: These are the helpers every API client needs once the transport works, and each has a failure mode that is silent when hand-written: the loop that misses the last page, the token visible in `ps`, the GraphQL error inside a `200 OK`.

**Independent Test**: Serve two pages linked by a `Link` header and confirm both bodies are printed and the walk stops; confirm a bearer token reaches the request but not the argument vector; confirm a `200` response carrying an `errors` array is reported as a failure.

**Acceptance Scenarios**:

1. **Given** a response carries `Link: <...>; rel="next"`, **When** pagination runs, **Then** every page's body is printed in order and the walk stops when no next relation is offered
2. **Given** a page budget or a repeated URL, **When** pagination runs, **Then** the walk stops rather than continuing forever
3. **Given** a bearer token, **When** an authenticated request is made, **Then** the token is sent out of band and does not appear among curl's arguments
4. **Given** a GraphQL endpoint answers `200` with a non-empty `errors` array, **When** the query runs, **Then** the helper reports a client-error exit code and logs the first message

---

### Example Workflow

```bash
# Fetch, parse, and act on a response without hand-rolled curl pipelines.
dybatpho::create_temp headers_file ".txt"
dybatpho::create_temp body_file ".json"

dybatpho::curl_request "https://api.example.test/status" "${body_file}" -D "${headers_file}"
dybatpho::curl_parse_response "${headers_file}" "${body_file}"

if ((DYBATPHO_HTTP_STATUS == 200)); then
  dybatpho::info "content-type: $(dybatpho::curl_response_header content-type "unknown")"
fi

# Download with resume plus integrity check, guarded by a circuit breaker.
dybatpho::circuit_breaker api.example.test \
  "dybatpho::curl_resume_download https://api.example.test/app.tgz /tmp/app.tgz sha256:${EXPECTED_SHA256}"
```

## Edge Cases

- Curl is not installed.
- The URL is itself a credential: a webhook whose path is the secret, a signed
  download with a token in its query, or a password in the authority.
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
- A rate limit spec names a window in milliseconds, seconds, minutes, or hours, or is not `count/window` at all.
- A rate limit key's window empties while the script is doing something else, so the budget is whole again.
- A paginated collection's last page offers no `next` relation, one entry names several relations at once, or the pages form a cycle.
- A GraphQL response answers `200 OK` while carrying an `errors` array, or the caller passes variables that are not a JSON object.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST expose a helper that performs HTTP requests via curl.
- **FR-002**: The request helper MUST retry failures according to the configured retry budget.
- **FR-003**: The request helper MUST map final HTTP classes into consistent shell exit codes for success, 3xx, 4xx, 5xx, and unknown failures.
- **FR-004**: The request helper MUST write the response body to the caller-specified destination or a safe default sink.
- **FR-005**: The module MUST expose a download helper that creates the destination directory automatically.
- **FR-006**: The request helper MUST log a human-readable description of the
  received HTTP status at debug level; the description table itself is
  internal and is not part of the public API.
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

- **FR-027**: The module MUST expose an in-memory sliding window rate limiter keyed by name,
  taking a `count/window` spec whose window is read in seconds unless it carries an `ms`, `s`,
  `m`, or `h` suffix, and MUST run the given command as an argument vector once a slot is free.
- **FR-027a**: When the budget is spent the limiter MUST wait exactly until the oldest call
  leaves the window, and MUST instead return a dedicated exit code without running the command
  when waiting is disabled or the wait would exceed the configured maximum.
- **FR-027b**: The module MUST expose helpers to report a key's remaining calls and to reset it.
- **FR-028**: The module MUST expose a reader for one relation of the last response's `Link`
  header, matching `rel` as a whole word so that an entry naming several relations is read
  correctly and a prefix of a relation is not mistaken for it.
- **FR-029**: The module MUST expose a pagination helper that follows the `next` relation,
  prints each page's body to standard output separated by a newline, stops when no next
  relation is offered, and refuses to visit the same URL twice or to exceed a configurable
  page budget; under dry-run it MUST rehearse only the first page.
- **FR-030**: The module MUST expose a bearer-authenticated request helper that passes the
  token through `DYBATPHO_CURL_SECRET_HEADERS`, preserving any secret headers the caller
  already set, and MUST refuse an empty token.
- **FR-031**: The module MUST expose a GraphQL helper that builds the `query`/`variables`
  envelope, sends it on standard input, refuses variables that are not a JSON object, and
  reports a non-empty `errors` array in an otherwise successful response as a client error
  with the first message logged.
- **FR-032**: Every URL the module writes to a log, an error, a warning or a
  progress line MUST be reduced to its scheme, host and port, with any user
  information, path, query or fragment replaced by `/[redacted]`, and a value
  that is not a URL replaced by `[redacted URL]`.

- **FR-020**: The module MUST split a URL into scheme, user, password, host, port, path,
  query, and fragment, requiring a scheme and `://`, and MUST present every component,
  leaving one the URL omits empty rather than unset.
- **FR-020a**: URL splitting MUST take the credentials at the last `@` of the authority, and
  MUST read a bracketed IPv6 literal as the host without treating its colons as a port
  separator.
- **FR-020b**: URL splitting MUST lower-case the scheme, leave every other component exactly as
  written including percent-escapes, and MUST clear the components of a previous URL.
- **FR-020c**: URL splitting MUST fail on a URL with no scheme, no host, or a port that is not a
  number from 1 to 65535, and MUST expose a reader for one component that accepts a default.
- **FR-021**: The module MUST decide whether a value is an IPv4 address, an IPv6 address, or
  neither, and MUST report which version an address is.
- **FR-021a**: IPv4 validation MUST refuse an octet written with a leading zero, because
  `inet_aton` reads it as octal and the address would name a different host to the resolver
  than to a reader.
- **FR-021b**: IPv6 validation MUST accept `::` standing for a run of zero groups, at most once
  per address, and a dotted IPv4 tail occupying the last two groups; it MUST refuse a zone
  index, which names an interface rather than part of the address.
- **FR-022**: The module MUST decide whether a value is a CIDR block of either version, with a
  prefix length within the range its version allows.
- **FR-022a**: The module MUST convert an IPv4 prefix length to a dotted-decimal subnet mask.
  This is IPv4 only because IPv6 has no dotted form.
- **FR-022b**: The module MUST decide whether an address falls inside a CIDR block of either
  version, comparing the prefix bit for bit including a prefix that ends inside a group, and
  MUST never report an address of one version as inside a block of the other.
- **FR-023**: The module MUST report whether a TCP port accepts a connection, using Bash's own
  network redirections so that nothing has to be installed, and MUST bound the attempt with a
  configurable timeout when the `timeout` command is available.
- **FR-023a**: Port probing MUST pass the host and port to any timed-out shell as arguments
  rather than as text spliced into the script it runs.
- **FR-024**: The module MUST expose a wait that retries a port probe until it succeeds or a
  configurable budget runs out, giving no single attempt more time than the budget has left.
- **FR-025**: Credentials MUST NOT be passed to `curl` as command-line
  arguments. A process's arguments are readable by every account on the host
  through `/proc/<pid>/cmdline`, so the module MUST accept them through
  `DYBATPHO_CURL_SECRET_HEADERS` and hand them over in a `--config` file.
- **FR-025a**: That config file MUST be created under `umask 077`, so the
  credential is never on disk in a mode another account can read, and MUST be
  removed once the request is over.
- **FR-026**: A request body given through `DYBATPHO_CURL_SECRET_DATA` MUST
  reach `curl` on standard input rather than as an argument, for the same
  reason.
- **FR-027**: An HTTP error response MUST keep its body. `curl`'s `--fail`
  discards it, so the reason a request was refused never reached the caller.
- **FR-028**: The exit code MUST reflect the class of the HTTP status that
  came back — 3, 4 or 5 — and MUST be reserved for a transport failure, where no
  response was received at all.

### Key Entities *(include if feature involves data)*

- **HTTP Attempt**: One curl execution performed within a request workflow.
- **URL Components**: The parts of the last parsed URL, one entry per component.
- **CIDR Block**: An address together with a prefix length, naming a range of addresses.
- **Download Target**: The destination file path prepared and populated by the download helper.
- **Retry Policy**: Retry budget, exponential delay bounds, optional jitter,
  and server-provided retry delay.
- **Upload Field**: A `name=value` or `name=@path` pair converted into a curl `-F` flag.
- **Checksum Spec**: An `algorithm:hexdigest` pair used to verify downloaded file integrity.
- **Normalized Response**: The parsed status code, lower-cased header map, and body file path
  exposed after a request.
- **Circuit Breaker State**: Per-key consecutive failure count and open timestamp used to decide
  whether a guarded command may run.
- **Rate Limit Window**: Per-key timestamps of the calls made inside the current window, oldest
  first, together with the `count/window` spec they are judged against.
- **Link Relation**: A URL and the relation names it carries in the response's `Link` header.
- **GraphQL Envelope**: The `query` document and its `variables` object, plus the `errors` array
  a response may carry alongside `data`.

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
- **SC-009**: A script reads a host, port, or path out of a URL without writing a regex of its
  own, and one that only nearly works cannot pass a malformed address as a valid one.
- **SC-010**: A script waits for a service to start listening with one call rather than a
  hand-written retry loop, and the wait keeps to the budget it was given.
- **SC-008**: A repeatedly failing endpoint stops receiving new attempts once its circuit opens,
  and recovers automatically once the cooldown elapses and a trial request succeeds.
- **SC-011**: A loop over many items keeps to an API's published rate without the script author
  writing a sleep, and no call is silently dropped to achieve it.
- **SC-012**: A paginated collection is read in one call, and a token used to read it never
  appears in the process table.
- **SC-013**: A GraphQL failure that arrives with a `200` status is reported as a failure rather
  than read as a successful request.

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
- **IT-012**: Verify a URL using every component is split correctly, that an absent component is
  empty, and that the components of a previous URL are cleared.
- **IT-013**: Verify the credentials are taken at the last `@`, that a bracketed IPv6 host is
  read apart from its port, that the scheme is lower-cased while the rest is left as written,
  and that percent-escapes survive.
- **IT-014**: Verify a URL with no scheme, no host, or a port outside 1-65535 is refused, and
  that the component reader honors a default and rejects a name that is not a component.
- **IT-015**: Verify IPv4 validation accepts addresses, rejects out-of-range octets and wrong
  shapes, and refuses an octet with a leading zero.
- **IT-016**: Verify IPv6 validation accepts `::`, a compressed address, a full eight-group
  address, and a mapped IPv4 tail both with and without `::`; and rejects a second `::`, wrong
  group counts, a trailing or leading single colon, an over-long group, and a zone index.
- **IT-017**: Verify the version reporter names 4 and 6 and fails on anything else.
- **IT-018**: Verify CIDR validation accepts blocks of both versions and rejects a prefix
  length its version does not have, a block with no prefix, and a prefix with a leading zero.
- **IT-019**: Verify prefix lengths 0, 1, 16, 24, and 32 convert to the right dotted mask, with
  or without a leading slash, and that a length outside IPv4's range stops the script.
- **IT-020**: Verify IPv4 membership at the edges of `/8`, `/12`, `/24`, `/32`, and `/0`.
- **IT-021**: Verify IPv6 membership including a `/33` prefix that ends inside a group, and that
  an address of one version is never inside a block of the other, including a mapped address.
- **IT-022**: Verify a port nothing listens on reads as closed, and a real listening socket reads
  as open.
- **IT-023**: Verify the wait returns as soon as a listening port answers, gives up within its
  budget, and that both helpers reject a port or a timeout that is not a number.
- **IT-011**: Verify a circuit breaker stays closed under the failure threshold, opens and
  short-circuits calls once the threshold is reached, and closes again after a successful call.
- **IT-025**: Verify the limiter runs a command and returns its exit code, takes a slot with no
  command at all, reads every window unit, refuses a spec that is not `count/window`, waits for
  the window to slide rather than dropping a call, forgets calls that have left the window, and
  returns the dedicated exit code when waiting is disabled or capped.
- **IT-026**: Verify the `Link` reader finds a relation among several entries, matches an entry
  that carries several relations, and fails on a missing relation or a missing header.
- **IT-027**: Verify pagination prints both pages of a two-page collection, stops at the page
  budget, stops when the pages form a cycle, and returns the failing page's exit code.
- **IT-028**: Verify a bearer token reaches the request through the config file and not through
  curl's arguments, that secret headers already set by the caller survive, and that an empty
  token is refused.
- **IT-029**: Verify the GraphQL helper sends the query and variables, reports an `errors` array
  in a `200` response as exit code 4 with the message logged, passes a clean response through,
  and refuses variables that are not a JSON object.
- **IT-030**: Verify a failing request to a URL carrying a password, a secret
  path, a query token and a fragment logs only `scheme://host:port/[redacted]`,
  and that the redaction keeps the scheme, host and port of plain, IPv6 and
  path-less URLs.
- **IT-024**: Verify a request carrying `DYBATPHO_CURL_SECRET_HEADERS` and
  `DYBATPHO_CURL_SECRET_DATA` sends both, while neither appears among the
  arguments the mocked `curl` was called with.
- **IT-025**: Verify a 422 and a 503 both return their status class and leave
  their body in the output file, and that a transport failure is reported
  separately.

## Acceptance Criteria *(mandatory)*

1. The module turns raw curl usage into a higher-level, testable contract for automation scripts.
2. Request and download behavior remain predictable enough for use in CI and scripted environments.
3. Multipart uploads, resumable/checksum-verified downloads, normalized response parsing,
   per-request timeout overrides, the circuit breaker, the rate limiter, pagination, bearer
   authentication, and GraphQL requests are covered by the same testable contract as the
   existing request helpers.
