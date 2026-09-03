# Feature Specification: Notification and Webhook Utilities

**Feature Branch**: `[reverse-spec-notification]`
**Status**: Implemented
**Input**: Existing source analysis: `src/notification.sh`, `doc/notification.md`, and `example/notification_ops.sh`

## Problem Statement *(mandatory)*

CI, deployment, cron, and monitoring scripts need to send status messages to
chat providers, but hand-building JSON payloads and provider-specific curl
requests creates duplicated escaping, authentication, and error handling.

## Business Value *(mandatory)*

- Provide one small API for common chat and webhook notifications.
- Prevent malformed JSON when messages contain quotes or control characters.
- Reuse the network module's HTTP status and retry behavior.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Notify team chat providers (Priority: P1)

As an operator, I want to send a message to Slack, Telegram, Microsoft Teams,
Google Chat, or Discord using provider-specific configuration so that pipeline
events reach the right team channel.

**Independent Test**: Stub HTTP requests for each provider and verify required
environment variables, payload fields, optional title/mode values, and return
codes.

**Acceptance Scenarios**:

1. **Given** valid provider credentials and a message, **When** the provider
   helper runs, **Then** it posts the provider-specific JSON payload
2. **Given** Telegram parse mode, a Teams title, or a Discord username,
   **When** the optional argument is supplied, **Then** it is included in the
   generated payload
3. **Given** required provider configuration is missing, **When** a helper
   runs, **Then** it fails before making a request

### User Story 2 - Send arbitrary webhook payloads (Priority: P1)

As a script author, I want to post raw JSON to any webhook and forward extra
curl options so that integrations not built into the module remain possible.

**Independent Test**: Invoke `notify_webhook` with a URL, JSON body, and extra
curl arguments and verify they are forwarded.

**Acceptance Scenarios**:

1. **Given** a webhook URL and JSON payload, **When** the generic helper runs,
   **Then** it performs an HTTP POST with JSON headers
2. **Given** additional curl flags, **When** the generic helper runs, **Then**
   those flags are passed through after the required POST arguments
3. **Given** the server returns 4xx or 5xx, **When** the request completes,
   **Then** the network status code is returned through the documented exit
   contract

### User Story 3 - Escape notification content safely (Priority: P1)

As a maintainer, I want message text escaped before JSON interpolation so that
quotes, backslashes, and control characters do not corrupt payloads.

**Independent Test**: Escape text containing quotes, backslashes, newlines,
carriage returns, and tabs and inspect the generated value.

**Acceptance Scenarios**:

1. **Given** message text containing JSON-sensitive characters, **When** a
   provider helper builds its payload, **Then** those characters are escaped
   as JSON string content

## Edge Cases

- Missing message, URL, payload, webhook URL, token, or chat ID.
- Message text contains quotes, backslashes, newlines, carriage returns, or
  tabs.
- Optional provider metadata is omitted or empty.
- HTTP 4xx, 5xx, transport failures, or retries occur.
- `notify_webhook` receives additional curl options.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide Slack Incoming Webhook notifications
  using `DYBATPHO_SLACK_WEBHOOK_URL`.
- **FR-002**: The module MUST provide Telegram Bot API `sendMessage`
  notifications using `DYBATPHO_TELEGRAM_BOT_TOKEN` and
  `DYBATPHO_TELEGRAM_CHAT_ID`.
- **FR-003**: Telegram notifications MUST accept an optional `HTML`,
  `Markdown`, or `MarkdownV2` parse mode.
- **FR-004**: The module MUST provide Microsoft Teams Incoming Webhook
  notifications using the documented Adaptive Card payload and optional title.
- **FR-005**: The module MUST provide Google Chat Incoming Webhook
  notifications using `DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL`.
- **FR-006**: The module MUST provide Discord Incoming Webhook notifications
  using `DYBATPHO_DISCORD_WEBHOOK_URL` and an optional username.
- **FR-007**: The module MUST provide a generic JSON webhook POST helper that
  accepts extra curl arguments.
- **FR-008**: Provider helpers MUST validate required arguments and environment
  variables before making requests.
- **FR-009**: JSON string content MUST escape backslashes, quotes, newlines,
  carriage returns, and tabs.
- **FR-010**: Provider requests MUST use the network module's JSON request
  behavior and status exit codes.

### Key Entities *(include if feature involves data)*

- **Notification Message**: Text sent to a provider, optionally with provider
  formatting.
- **Provider Configuration**: Webhook URL or bot credentials read from
  environment variables.
- **JSON Payload**: Provider-specific or caller-supplied request body.
- **Webhook Request**: HTTP POST routed through `dybatpho::curl_json`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script can notify each supported provider with one helper call.
- **SC-002**: Provider payloads remain valid for messages containing common
  JSON-sensitive characters.
- **SC-003**: Notification failures remain distinguishable by missing
  configuration, transport, and HTTP status.

## Integration Tests *(mandatory)*

- **IT-001**: Stub and verify Slack, Telegram, Teams, Google Chat, and Discord
  payloads and required environment variables.
- **IT-002**: Verify Telegram parse mode, Teams title, and Discord username
  options.
- **IT-003**: Verify generic webhook POST and forwarding of extra curl flags.
- **IT-004**: Verify JSON escaping for quotes, backslashes, and control
  characters.
- **IT-005**: Verify missing configuration and HTTP 4xx/5xx failures.

## Acceptance Criteria *(mandatory)*

1. Supported provider helpers use documented environment variables and payload
   shapes without exposing credentials in output.
2. Generic webhook calls remain extensible through additional curl arguments.
3. All notification requests share the network module's error contract.
