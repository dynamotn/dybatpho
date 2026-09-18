# Feature Specification: Language Model Utilities

**Feature Branch**: `[feature-ai]`
**Status**: Implemented
**Input**: Existing source analysis: `src/ai.sh`, `doc/ai.md`, `test/ai.bats`, and `example/ai_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts increasingly need a language model in the middle of a pipeline:
to summarize a log, classify an alert, or draft a message from real data.
Doing it by hand means rebuilding the same scaffolding in every script —
provider-specific JSON payloads, response shapes that differ per vendor,
escaping that breaks on the first quotation mark, retries, and no way to tell
how much the run cost. Worse, a prompt assembled by string concatenation
routinely carries credentials and personal data to a third party without the
author noticing, and a loop that calls a model has no natural stopping point.

## Business Value *(mandatory)*

- Give scripts one small API for four different model backends, so the choice
  of provider is a configuration decision rather than a rewrite.
- Remove the escaping and payload-shaping work that makes hand-rolled model
  calls fragile.
- Make the expensive and risky parts explicit: a call budget, usage counters,
  and redaction that runs before anything leaves the machine.
- Keep the result usable by the rest of the library: text on stdout, a
  documented exit code, and JSON that the `json` module can query.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask a model a question from a script (Priority: P1)

As a script author, I want to send one prompt and read the answer on stdout,
so that a model call composes with the rest of my pipeline like any other
command.

**Independent Test**: Stub the HTTP transport for each backend, call
`dybatpho::ai_ask`, and verify the assistant text is printed and the token
counters are updated.

**Acceptance Scenarios**:

1. **Given** a configured backend, **When** `dybatpho::ai_ask` runs, **Then**
   the assistant text is printed on stdout and nothing else is
2. **Given** an Anthropic, OpenAI-compatible, or Ollama response, **When** the
   answer is extracted, **Then** the same text is produced from each of the
   three different response shapes
3. **Given** a provider that answers with an error object, **When** the
   response is parsed, **Then** the script stops and the provider message is
   reported
4. **Given** no backend is configured, **When** a call is attempted, **Then**
   it fails before making a request and names the environment variable to set

### User Story 2 - Hold a multi-turn conversation (Priority: P2)

As a script author, I want the model to remember earlier turns, so that a
follow-up question does not have to repeat the whole context.

**Independent Test**: Create a conversation, send two turns, and verify both
questions and both answers are present in the file in order.

**Acceptance Scenarios**:

1. **Given** a new conversation, **When** it is created, **Then** it holds the
   system prompt and no turns, and its file is cleaned up when the script exits
2. **Given** an existing conversation, **When** `dybatpho::ai_chat` runs,
   **Then** both the question and the answer are appended to the file
3. **Given** content containing quotes, backslashes, or newlines, **When** a
   turn is appended, **Then** the stored content round-trips unchanged
4. **Given** an unknown role or a missing file, **When** a turn is appended,
   **Then** the call fails and says which input was wrong

### User Story 3 - Get an answer a script can branch on (Priority: P1)

As a script author, I want the answer to match a JSON schema, so that I can
read a field instead of parsing prose.

**Independent Test**: Request a schema-constrained answer, verify the output
parses as JSON, and verify the call is retried and then fails when the model
never returns a usable document.

**Acceptance Scenarios**:

1. **Given** a schema and a backend with native structured output, **When**
   the request is built, **Then** the schema is sent as the provider's own
   output contract
2. **Given** a backend without structured output, **When** the request is
   built, **Then** the contract is stated in the prompt and enforced locally
3. **Given** an answer wrapped in a Markdown fence, **When** it is parsed,
   **Then** the fence is stripped and the document is returned
4. **Given** answers that never parse, **When** the retry budget is spent,
   **Then** the call fails rather than returning prose

### User Story 4 - Let the model call shell functions (Priority: P2)

As a script author, I want the model to gather facts by running my functions,
so that its answer is grounded in the real system rather than guessed.

**Independent Test**: Register a tool, drive the loop with a stubbed response
containing a tool call, and verify the handler runs and its output is fed back.

**Acceptance Scenarios**:

1. **Given** a registered tool, **When** the model requests it, **Then** the
   handler runs and its output is returned as the tool result
2. **Given** a handler that fails or a tool that is not registered, **When**
   it is invoked, **Then** an error result is returned to the model instead of
   stopping the script
3. **Given** a model that keeps requesting tools, **When** the step limit is
   reached, **Then** the loop stops and reports how many rounds it ran
4. **Given** a backend without tool support, **When** the loop is entered,
   **Then** the question is answered directly instead

### User Story 5 - Stay inside a known cost and safety envelope (Priority: P1)

As an operator, I want to know what a script sent and what it spent, and to
cap both, so that an automated run cannot leak data or bill without limit.

**Independent Test**: Register a secret, make a call, and verify the secret
never appears in the request; set a budget of one call and verify the second
call is refused.

**Acceptance Scenarios**:

1. **Given** a registered secret, **When** a prompt containing it is sent,
   **Then** the value is masked before the request is built
2. **Given** a call budget, **When** it is exhausted, **Then** the next call
   fails before a request is made
3. **Given** completed calls, **When** usage is read, **Then** the call count
   and token totals for the run are reported
4. **Given** `DRY_RUN` is enabled, **When** any call is made, **Then** no
   request is sent, no budget is consumed, and a placeholder of the right shape
   is returned

### Example Workflow

```bash
. dybatpho/init.sh --modules ai json

dybatpho::secret_register "${DEPLOY_TOKEN}"
dybatpho::ai_budget 5

schema='{"type":"object","properties":{"risk":{"type":"string","enum":["low","high"]},
         "reason":{"type":"string"}},"required":["risk","reason"],
         "additionalProperties":false}'

assessment=$(dybatpho::ai_json "Assess this diff: $(git diff --stat)" "${schema}")
if [[ "$(dybatpho::json_get "${assessment}" '.risk')" == "high" ]]; then
  dybatpho::warn "$(dybatpho::json_get "${assessment}" '.reason')"
fi
dybatpho::info "Model usage: $(dybatpho::ai_usage total)"
```

## Edge Cases

- No backend configured, or a pinned backend whose credentials are missing.
- Neither `yq` nor `jq` is installed.
- Prompts containing quotes, backslashes, newlines, or non-ASCII text.
- A provider answering with an error object rather than an HTTP error status.
- A model returning prose where a JSON document was required, or wrapping the
  document in a Markdown fence.
- A tool handler that fails, writes to stderr, or does not exist.
- A tool-use loop that never converges.
- Counters updated inside a command substitution, where a subshell cannot
  write back to its parent.
- A cached entry that has outlived its time to live.
- `DRY_RUN` enabled for a rehearsal.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST support the `anthropic`, `openai`, `ollama`, and
  `cli` backends behind one function set.
- **FR-002**: The module MUST resolve the backend automatically when
  `DYBATPHO_AI_PROVIDER` is `auto`, preferring an Anthropic key, then an
  OpenAI key, then a reachable local Ollama daemon, then an installed client.
- **FR-003**: The module MUST resolve a model per backend, with an explicit
  `DYBATPHO_AI_MODEL` taking precedence over every default.
- **FR-004**: `dybatpho::ai_check` MUST verify dependencies and credentials
  without making a request.
- **FR-005**: `dybatpho::ai_ask` MUST print the assistant text on stdout.
- **FR-006**: The module MUST store conversations in a file that survives
  across calls and is cleaned up when the script exits.
- **FR-007**: `dybatpho::ai_chat` MUST append both the question and the answer
  to the conversation.
- **FR-008**: `dybatpho::ai_json` MUST use the provider's structured output
  contract where one exists, MUST validate the answer locally in every case,
  and MUST retry before failing.
- **FR-009**: `dybatpho::ai_stream` MUST write tokens as they arrive on
  backends that stream, and MUST fall back to a buffered call on those that do
  not.
- **FR-010**: The module MUST let a caller register shell functions as tools
  and MUST run them when the model asks, returning failures as tool results
  rather than stopping the script.
- **FR-011**: `dybatpho::ai_run` MUST stop after `DYBATPHO_AI_MAX_STEPS` tool
  rounds.
- **FR-012**: Every prompt MUST be passed through secret masking before a
  request is built, unless `DYBATPHO_AI_REDACT` is disabled.
- **FR-013**: The module MUST count calls and tokens in a file shared by every
  subshell of one script run, and MUST expose them through `dybatpho::ai_usage`
  and `dybatpho::ai_usage_field`.
- **FR-014**: The module MUST refuse a call once `DYBATPHO_AI_MAX_CALLS` is
  reached, raising the refusal from the public function the caller invoked.
- **FR-015**: The module MUST optionally cache responses on disk keyed by the
  request content, and MUST ignore entries older than the configured lifetime.
- **FR-016**: The module MUST make no request when `DRY_RUN` is enabled, and
  MUST return a placeholder in the provider's own response shape.
- **FR-017**: Provider errors MUST be surfaced with the provider's own message.
- **FR-018**: HTTP requests MUST go through the network module, inheriting its
  retry behavior and status exit codes.
- **FR-019**: The module MUST fail with a clear message when neither `yq` nor `jq` is installed.
- **FR-020**: Payloads and responses MUST be built and read through the `json`
  module, so the module works on whichever backend the rest of the library
  found rather than requiring a specific one.

### Key Entities *(include if feature involves data)*

- **Backend**: One of four transports, each with its own payload shape,
  response shape, and credential rules.
- **Conversation**: A provider-neutral document holding a system prompt and an
  ordered list of turns.
- **Tool**: A registered name, description, argument schema, and shell handler
  the model may call.
- **Counter File**: The shared record of calls and token totals for one script
  run.
- **Cache Entry**: A stored response keyed by a hash of the request.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script can ask a question, hold a conversation, and request a
  validated JSON answer without writing any provider-specific code.
- **SC-002**: Switching backend is a configuration change, with no edit to the
  calling script.
- **SC-003**: A value registered as a secret never appears in a request.
- **SC-004**: A run cannot exceed its configured call budget.
- **SC-005**: A rehearsal with `DRY_RUN` exercises the whole path without
  sending anything or consuming budget.

## Integration Tests *(mandatory)*

- **IT-001**: Verify backend detection order, pinned backends, and the
  rejection of an unknown backend name.
- **IT-002**: Verify model resolution per backend and the precedence of an
  explicit model.
- **IT-003**: Verify `ai_check` passes with credentials, fails without them,
  and needs none for Ollama.
- **IT-004**: Verify text extraction and usage accounting for Anthropic,
  OpenAI, and Ollama response shapes.
- **IT-005**: Verify conversation creation, appending, content round-tripping,
  role validation, and transcript rendering.
- **IT-006**: Verify structured output: native contract, local validation,
  fence stripping, and failure after the retry budget.
- **IT-007**: Verify tool registration validation, invocation, failing
  handlers, unknown tools, and the step limit.
- **IT-008**: Verify secret masking, the call budget, usage counters and their
  reset.
- **IT-009**: Verify caching serves a repeated request without a second call,
  and that the cache can be cleared.
- **IT-010**: Verify `DRY_RUN` makes no request, consumes no budget, and still
  yields a parseable answer for schema-constrained calls.
- **IT-011**: Verify payload construction for each backend: system prompt
  placement, effort, tools, and output schema.
- **IT-012**: Verify the module behaves identically under both the `yq` and the
  `jq` backend.

## Acceptance Criteria *(mandatory)*

1. One API covers four backends, and the calling script contains no
   provider-specific code.
2. Prompts and responses survive quotes, backslashes, newlines, and non-ASCII
   text intact.
3. Secrets are masked, budgets are enforced, and usage is reportable at any
   point in a run.
4. Structured answers either validate or the call fails; prose is never
   returned where JSON was required.
5. Every documented exit code matches the behavior of the network module it
   builds on.
