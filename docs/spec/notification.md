# Feature Specification: Notification and Webhook Utilities

**Feature Branch**: `[reverse-spec-notification]`
**Status**: Implemented
**Input**: Existing source analysis: `src/notification.sh`, `docs/notification.md`, `test/notification.bats`, and `example/notification_ops.sh`

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

### User Story 4 - Notify the person at the desktop (Priority: P2)

As someone running a long job on my own machine, I want a desktop notification
when it ends so that I do not have to watch the terminal.

**Independent Test**: Put fake `notify-send` and `osascript` commands on a PATH
that holds nothing else and verify which one runs and the arguments it gets.

**Acceptance Scenarios**:

1. **Given** `notify-send` is installed, **When** `notify_desktop` runs with a
   title, body and urgency, **Then** `notify-send` receives the urgency, `--`,
   the title and the body as separate arguments
2. **Given** only `osascript` is installed, **When** `notify_desktop` runs,
   **Then** the title and body reach the AppleScript as `argv`, not as script
   text
3. **Given** neither backend is installed, **When** `notify_desktop` runs,
   **Then** it fails with exit code `127` and names both backends
4. **Given** `DRY_RUN` is enabled, **When** `notify_desktop` runs, **Then** it
   prints the command it would run and shows nothing

### User Story 5 - Push to a phone through ntfy (Priority: P2)

As an operator without a team chat, I want to publish to an ntfy topic, on
ntfy.sh or my own server, so that an alert reaches my phone.

**Independent Test**: Stub `curl` and verify the JSON body, the server URL, the
priority mapping, and that a token travels outside the argument vector.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_NTFY_TOPIC` and a message, **When** `notify_ntfy` runs,
   **Then** it posts `{"topic":...,"message":...}` to `https://ntfy.sh`
2. **Given** a title, a priority name and comma-separated tags, **When**
   `notify_ntfy` runs, **Then** the body carries the title, the priority number
   and the trimmed, non-empty tags
3. **Given** `DYBATPHO_NTFY_TOKEN`, **When** `notify_ntfy` runs, **Then** the
   token is sent as a bearer header and never appears on curl's command line
4. **Given** an invalid topic, server URL or priority, **When** `notify_ntfy`
   runs, **Then** it fails before making a request

### User Story 6 - Push to a self-hosted Gotify server (Priority: P2)

As an operator who runs Gotify, I want to push a message with a title and a
priority so that alerts stay on infrastructure I control.

**Independent Test**: Stub `curl` and verify the endpoint, the JSON body, and
that the application token is sent outside the argument vector.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_GOTIFY_URL`, `DYBATPHO_GOTIFY_TOKEN` and a message,
   **When** `notify_gotify` runs, **Then** it posts `{"message":...}` to
   `<server>/message` with the token in an `X-Gotify-Key` header
2. **Given** a title and a priority, **When** `notify_gotify` runs, **Then** the
   body carries both
3. **Given** a priority outside `0`-`10` or a server URL without a scheme,
   **When** `notify_gotify` runs, **Then** it fails before making a request

### User Story 7 - Email an alert through the local MTA (Priority: P2)

As an administrator of a server with a mail transfer agent, I want to send a
plain-text email from a cron job so that an alert reaches people who are not on
any chat platform.

**Independent Test**: Point `DYBATPHO_SENDMAIL` at a fake that records its
arguments and the message, and verify both, along with every refusal.

**Acceptance Scenarios**:

1. **Given** recipients, a subject and a body, **When** `notify_email` runs,
   **Then** `sendmail -i --` receives each recipient as an argument and the
   message carries `To`, `Subject`, MIME headers, a blank line and the body
2. **Given** a sender argument or `DYBATPHO_EMAIL_FROM`, **When**
   `notify_email` runs, **Then** the message carries a `From` header
3. **Given** a subject that is not ASCII, **When** `notify_email` runs, **Then**
   the subject is RFC 2047 encoded without splitting a character
4. **Given** a line break in the recipients, sender or subject, or an address
   that is not an email address or starts with `-`, **When** `notify_email`
   runs, **Then** it fails before running `sendmail`
5. **Given** no sendmail command is found, **When** `notify_email` runs,
   **Then** it fails with exit code `127`

### User Story 8 - Keep a dead provider from stalling the script (Priority: P2)

As the author of a cron job that alerts on every run, I want a smaller retry
budget for notifications and a provider that keeps failing to be skipped for a
while, so that an outage at the chat provider does not stretch every run.

**Independent Test**: Stub `curl` with failing answers, enable the policy
variables, and count how many requests reach it and which exit code each call
returns.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_NOTIFY_MAX_RETRIES`, **When** an HTTP notifier runs,
   **Then** that budget replaces `DYBATPHO_CURL_MAX_RETRIES` for the request,
   and the script's own value is unchanged afterwards
2. **Given** `DYBATPHO_NOTIFY_CIRCUIT=true` and a provider that has failed
   `DYBATPHO_CIRCUIT_THRESHOLD` times in a row, **When** it is called again
   before the cooldown, **Then** nothing is sent and the call returns `9`
3. **Given** one provider's circuit is open, **When** another provider is
   called, **Then** it is sent normally
4. **Given** the circuit is off, **When** a provider keeps failing, **Then**
   every call still reaches it

### Example Workflow

```bash
export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.test/services/T/B/X"

if ./deploy.sh; then
  dybatpho::notify_slack ":white_check_mark: *Deploy succeeded* for \`${BUILD_TAG}\`"
else
  dybatpho::notify_slack ":x: Deploy failed, see the build log"
  dybatpho::notify_webhook "https://alerts.example.test/hook" \
    "$(printf '{"severity":"high","build":"%s"}' "${BUILD_TAG}")"
fi
```

## Edge Cases

- Missing message, URL, payload, webhook URL, token, or chat ID.
- The webhook URL is the secret itself, so it must not reach a debug line.
- Message text contains quotes, backslashes, newlines, carriage returns, or
  tabs.
- Optional provider metadata is omitted or empty.
- HTTP 4xx, 5xx, transport failures, or retries occur.
- `notify_webhook` receives additional curl options.
- A desktop title starts with `-`, or a title or body contains quotes or
  AppleScript syntax.
- No desktop backend is installed, or `notify-send` finds no desktop session.
- An ntfy topic with characters ntfy refuses, a server URL with no scheme or a
  trailing slash, a priority outside 1-5, or tags with spaces and empty items.
- A Gotify priority outside 0-10, or a Gotify server URL with a trailing slash.
- An email recipient list with spaces and empty items, an address that starts
  with `-`, a line break meant to add a header, a body line holding only `.`,
  a long subject in a non-Latin script, or `sendmail` outside the user's PATH.
- A non-numeric `DYBATPHO_NOTIFY_MAX_RETRIES`, or a generic webhook URL that
  carries `user:password@` or a token in its query, which must not reach the
  circuit's name.

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
- **FR-011**: `notify_desktop` MUST show a notification through `notify-send`
  when it is installed and through `osascript` otherwise, passing the title and
  body as separate arguments and never as part of a command or script text.
- **FR-012**: `notify_desktop` MUST accept the urgencies `low`, `normal`
  (default) and `critical`, and MUST reject an empty title or any other urgency
  before running a backend.
- **FR-013**: `notify_desktop` MUST fail with exit code `127` when no backend is
  installed, MUST return a backend's own non-zero exit code, and under
  `DRY_RUN` MUST print the command instead of running it.
- **FR-014**: `notify_ntfy` MUST publish a JSON body holding the topic from
  `DYBATPHO_NTFY_TOPIC`, the message, and the optional title, priority and tags
  to `DYBATPHO_NTFY_URL` (default `https://ntfy.sh`, trailing slashes removed).
- **FR-015**: `notify_ntfy` MUST accept priorities `1`-`5` and the names `min`,
  `low`, `default`, `high`, `max` and `urgent`, and MUST reject a topic outside
  ntfy's 1-64 letters, digits, `-` and `_`, a server URL that is not `http(s)`,
  or any other priority before making a request.
- **FR-016**: `notify_ntfy` MUST send `DYBATPHO_NTFY_TOKEN`, when set, as a
  bearer header through the network module's out-of-band headers, never as a
  curl argument.
- **FR-017**: `notify_gotify` MUST post a JSON body holding the message and the
  optional title and priority to `<DYBATPHO_GOTIFY_URL>/message`, with
  `DYBATPHO_GOTIFY_TOKEN` sent as an out-of-band `X-Gotify-Key` header.
- **FR-018**: `notify_gotify` MUST reject a priority outside `0`-`10` and a
  server URL that is not `http(s)` before making a request.
- **FR-019**: `notify_email` MUST run `sendmail -i --` with every trimmed,
  non-empty recipient as an argument, and write a message of `From` (when a
  sender is given or `DYBATPHO_EMAIL_FROM` is set), `To`, `Subject`,
  `MIME-Version`, a UTF-8 plain-text `Content-Type`, `8bit` transfer encoding,
  a blank line and the body to its standard input.
- **FR-020**: `notify_email` MUST refuse a line break in the recipients, the
  sender or the subject, and any recipient or sender that is not an email
  address or starts with `-`, before running `sendmail`.
- **FR-021**: `notify_email` MUST RFC 2047 encode a subject that is not
  printable ASCII, in encoded words of at most 75 columns that never split a
  UTF-8 character.
- **FR-022**: `notify_email` MUST use `DYBATPHO_SENDMAIL` when it is set, and
  otherwise the first of `sendmail` on PATH, `/usr/sbin/sendmail` and
  `/usr/lib/sendmail`; it MUST fail with exit code `127` when none exists,
  return `sendmail`'s own exit code, and under `DRY_RUN` print the command
  instead of sending.
- **FR-023**: Every HTTP notifier MUST use `DYBATPHO_NOTIFY_MAX_RETRIES`, when
  it is set, as the retry budget of its request only, and MUST reject a value
  that is not a non-negative integer.
- **FR-024**: When `DYBATPHO_NOTIFY_CIRCUIT` is true, every HTTP notifier MUST
  run its request through `dybatpho::circuit_breaker` under the key
  `notify:<provider>` (`notify:webhook:<host>` for the generic webhook), so an
  open circuit returns `9` without sending; the key MUST NOT contain the URL's
  path, query or credentials. When it is not true, requests MUST be sent as
  before.
- **FR-025**: A notifier MUST NOT write a webhook URL to a log line in full; it
  MUST show only the scheme, host and port, the way the network module redacts
  every URL it logs.

### Key Entities *(include if feature involves data)*

- **Notification Message**: Text sent to a provider, optionally with provider
  formatting.
- **Provider Configuration**: Webhook URL or bot credentials read from
  environment variables.
- **JSON Payload**: Provider-specific or caller-supplied request body.
- **Webhook Request**: HTTP POST routed through `dybatpho::curl_json`.
- **Desktop Backend**: `notify-send` or `osascript`, chosen by what is
  installed.
- **Mail Message**: Headers and a plain-text body handed to `sendmail`, with
  the recipients given as arguments.

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
- **IT-006**: Verify `notify_desktop` arguments for `notify-send` and the
  `osascript` fallback, verbatim titles that look like flags, the urgency
  rules, the missing-backend exit code, a backend's exit code, and `DRY_RUN`.
- **IT-007**: Verify the `notify_ntfy` body, default and custom server URLs,
  every priority name, tag trimming, the out-of-band token, rejection of a bad
  topic, URL or priority, and HTTP status exit codes.
- **IT-008**: Verify the `notify_gotify` endpoint, body, escaping, out-of-band
  token, rejection of a bad priority or URL, and HTTP status exit codes.
- **IT-009**: Verify `notify_email` arguments and message, the sender sources,
  subject encoding and splitting, every refusal, the sendmail lookup, exit
  code `127`, the sendmail exit code, and `DRY_RUN`.
- **IT-010**: Verify the notification retry budget and that it does not leak,
  its validation, a circuit opening and returning `9`, one circuit per
  provider, a webhook circuit named by host without credentials, the token
  staying out of band through the breaker, and the circuit being off by
  default.
- **IT-011**: Verify the webhook debug line names only the host of a URL whose
  path and query carry the secret.

## Acceptance Criteria *(mandatory)*

1. Supported provider helpers use documented environment variables and payload
   shapes without exposing credentials in output.
2. Generic webhook calls remain extensible through additional curl arguments.
3. Desktop notifications pass user text to the backend as data, never as code.
4. Access tokens never reach a process's command line.
5. Text from a variable cannot add an email header or recipient.
6. A failing provider can be made to cost a script one fast failure instead of
   a full retry cycle, without changing the default behavior.
3. All notification requests share the network module's error contract.
