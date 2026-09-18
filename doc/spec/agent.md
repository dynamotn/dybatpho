# Feature Specification: Agent-Facing Script Utilities

**Feature Branch**: `[feature-agent]`
**Status**: Implemented
**Input**: Existing source analysis: `src/agent.sh`, `doc/agent.md`, `test/agent.bats`, and `example/agent_ops.sh`

## Problem Statement *(mandatory)*

A command line tool written for people breaks in specific ways when a model
starts driving it. It answers in prose an agent has to guess at, it blocks on
a confirmation prompt nobody will ever answer, it performs a destructive
action because the agent passed a plausible-looking flag, and afterwards
nobody can tell which actions were the agent's. Teams work around this by
maintaining a second, hand-written tool schema beside the real CLI, which
drifts from the parser the first time an option changes.

## Business Value *(mandatory)*

- Let one script serve both audiences without a fork: readable output for
  people, parseable output for agents.
- Generate tool definitions from the option spec that already drives the
  parser, so a schema cannot describe an option the CLI does not have.
- Replace an unanswerable confirmation prompt with an explicit allowlist, so
  automation is deliberate rather than accidental.
- Leave a record of what an agent made the script do.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Answer in the caller's language (Priority: P1)

As a script author, I want one reporting call that prints text for a person
and JSON for an agent, so that I do not branch on the audience everywhere.

**Independent Test**: Call the reporting helpers in both modes and verify the
text form and the JSON form carry the same fields.

**Acceptance Scenarios**:

1. **Given** a person is running the script, **When** a result is reported,
   **Then** it is printed as readable `key=value` text
2. **Given** an agent is running the script, **When** a result is reported,
   **Then** it is printed as one JSON object
3. **Given** a value containing quotes or an equals sign, **When** it is
   reported, **Then** it survives into the JSON object unchanged
4. **Given** a field that is not `key=value`, **When** it is reported, **Then**
   the call fails and says what was expected

### User Story 2 - Fail in a way an agent can act on (Priority: P1)

As a script author, I want failures to carry a stable code and a hint, so that
an agent can recover instead of retrying the same mistake.

**Independent Test**: Trigger an error in both modes and verify the code,
message, and optional hint are present, and that the call always reports
failure.

**Acceptance Scenarios**:

1. **Given** an agent is running the script, **When** an error is reported,
   **Then** a JSON object carrying a status, code, message, and optional hint
   is printed
2. **Given** a person is running the script, **When** an error is reported,
   **Then** the message is logged and the hint is shown instead of JSON
3. **Given** no hint is supplied, **When** an error is reported, **Then** the
   hint field is absent rather than empty
4. **Given** any mode, **When** an error is reported, **Then** the call returns
   failure so it can be chained

### User Story 3 - Publish the CLI as tools (Priority: P1)

As a maintainer, I want tool definitions generated from my option spec, so
that adding a flag cannot leave the agent-facing schema behind.

**Independent Test**: Generate definitions from a spec with a flag, a choice
list, a repeatable option, a required option, a hidden option, and a
subcommand, and verify each is reflected correctly.

**Acceptance Scenarios**:

1. **Given** an option spec, **When** definitions are generated, **Then** the
   root command and every subcommand become one tool each
2. **Given** a flag, a choice list, or a repeatable option, **When** the schema
   is built, **Then** it becomes a boolean, an enum, or an array respectively
3. **Given** a hidden option, **When** the schema is built, **Then** it is
   omitted
4. **Given** a required option, **When** the schema is built, **Then** it
   appears in the required list
5. **Given** a requested format, **When** definitions are generated, **Then**
   the Anthropic, OpenAI, or MCP shape is produced, and an unknown format is
   rejected
6. **Given** an MCP manifest, **When** it is generated, **Then** each tool
   records the command line it maps to

### User Story 4 - Refuse work that was not cleared (Priority: P1)

As an operator, I want an agent to be able to perform only the actions I named
in advance, so that an automated run cannot escalate into something
destructive.

**Independent Test**: Run the gate in both modes with an allowlist and verify
the approval, the refusal, and the audit records that result.

**Acceptance Scenarios**:

1. **Given** a person is running the script, **When** the gate is reached,
   **Then** the usual interactive confirmation is used
2. **Given** an agent and an allowlisted action, **When** the gate is reached,
   **Then** the action is approved without a prompt
3. **Given** an agent and an action that was not listed, **When** the gate is
   reached, **Then** it is refused with a structured reason and a hint
4. **Given** an allowlist entry that merely shares a prefix with the action,
   **When** the gate is reached, **Then** it does not count as a match
5. **Given** any decision, **When** the gate resolves, **Then** it is written
   to the audit log

### User Story 5 - Know what the environment looks like and what happened (Priority: P2)

As an agent, I want to read the environment before acting and leave a record
after, so that decisions are informed and reviewable.

**Independent Test**: Read the context document and verify it reports the
platform, working directory, repository state, loaded modules, and run flags;
write audit records and verify they are one JSON object per line.

**Acceptance Scenarios**:

1. **Given** any run, **When** the context is requested, **Then** platform,
   working directory, git state, loaded modules, interactivity, dry run, and
   agent mode are reported as JSON
2. **Given** an audit destination, **When** an action is recorded, **Then** one
   JSON object carrying a timestamp, script, mode, action, and detail is
   appended
3. **Given** no audit destination, **When** an action is recorded, **Then**
   nothing is written and the call still succeeds
4. **Given** an audit log, **When** it is shown, **Then** each record is
   printed as a readable line

### Example Workflow

```bash
. dybatpho/init.sh --modules agent

if [[ "${1-}" == "--tools" ]]; then
  dybatpho::agent_tools _spec_root mytool anthropic
  exit 0
fi

if ! dybatpho::agent_confirm deploy "Deploy ${VERSION} to ${TARGET}"; then
  exit 1
fi

if deploy "${VERSION}"; then
  dybatpho::agent_result ok version="${VERSION}" target="${TARGET}"
else
  dybatpho::agent_error deploy_failed "Deployment of ${VERSION} failed" \
    "Check the rollout log, then retry or roll back"
fi
```

## Edge Cases

- The script is run by a person, by an agent, or by an agent whose runtime
  this module does not recognise.
- A result field that is not `key=value`, or a value containing an equals sign
  or a quotation mark.
- An error reported with no hint.
- An allowlist that is empty, that names every action, or that contains an
  entry sharing a prefix with the requested action.
- An audit destination whose parent directory does not exist, or none at all.
- An option spec containing hidden options, repeatable options, choice lists,
  and nested subcommands.
- A tool name prefix containing characters that are not valid in a tool name.
- Neither `yq` nor `jq` is installed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST report whether a run is agent-driven, detecting
  known agent runtime markers and honoring an explicit `DYBATPHO_AGENT_MODE`.
- **FR-002**: The module MUST allow additional marker variable names through
  `DYBATPHO_AGENT_ENV`.
- **FR-003**: `dybatpho::agent_result` MUST print readable text for a person
  and one JSON object for an agent, and MUST reject a field that is not
  `key=value`.
- **FR-004**: `dybatpho::agent_error` MUST print a structured error for an
  agent, log it for a person, omit an absent hint, and always report failure.
- **FR-005**: `dybatpho::agent_context` MUST report platform, working
  directory, git repository state, loaded modules, interactivity, dry run
  state, and agent mode as JSON.
- **FR-006**: `dybatpho::agent_confirm` MUST use interactive confirmation for
  a person and an allowlist for an agent, and MUST match allowlist entries as
  whole words.
- **FR-007**: `dybatpho::agent_confirm` MUST record both approvals and
  refusals in the audit log.
- **FR-008**: `dybatpho::agent_audit` MUST append one JSON object per action
  when a destination is configured, creating the parent directory, and MUST do
  nothing when no destination is set.
- **FR-009**: `dybatpho::agent_tools` MUST generate one tool per command from a
  CLI option spec, in either the Anthropic or the OpenAI shape, and MUST reject
  an unknown shape.
- **FR-010**: Generated schemas MUST map flags to booleans, choice lists to
  enums, and repeatable options to arrays of their item type.
- **FR-011**: Generated schemas MUST carry the required option list and MUST
  close the object to unknown properties.
- **FR-012**: Hidden options MUST be omitted from every generated schema.
- **FR-013**: Generated tool names MUST join the command path and MUST contain
  only characters valid in a tool name.
- **FR-014**: `dybatpho::agent_mcp` MUST emit an MCP tools payload using the
  `inputSchema` key and MUST record the command line each tool maps to.
- **FR-015**: Tool definitions MUST be derived from `dybatpho::generate_schema`
  rather than from a separate list.
- **FR-016**: The module MUST fail with a clear message when neither `yq` nor `jq` is installed.
- **FR-017**: Documents MUST be built and read through the `json` module, so the
  module works on whichever backend the rest of the library found rather than
  requiring a specific one.

### Key Entities *(include if feature involves data)*

- **Agent Mode**: Whether a model or a person is driving this run.
- **Result**: A status word plus named fields, rendered per audience.
- **Structured Error**: A stable code, a message, and an optional recovery
  hint.
- **Allowlist**: The set of actions an agent has been cleared to perform.
- **Audit Record**: One JSON line describing an action and its outcome.
- **Tool Definition**: A command, its description, and its argument schema,
  derived from the CLI option spec.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One script serves people and agents without a second code path
  for reporting.
- **SC-002**: Adding or changing a CLI option changes the generated tool
  definitions with no other edit.
- **SC-003**: An agent cannot perform an action that was not named in advance.
- **SC-004**: Every agent-initiated action and refusal is recoverable from the
  audit log.

## Integration Tests *(mandatory)*

- **IT-001**: Verify mode detection from markers, from an extra marker name,
  from an explicit setting, and the rejection of an unknown mode.
- **IT-002**: Verify result rendering in both modes, including values with
  quotes and equals signs, and the rejection of a malformed field.
- **IT-003**: Verify error rendering in both modes, hint omission, and the
  failure exit code.
- **IT-004**: Verify the context document reports the expected fields,
  including the dry run flag and the loaded module list.
- **IT-005**: Verify the gate approves allowlisted actions, refuses others,
  honors the wildcard, rejects prefix matches, and audits both outcomes.
- **IT-006**: Verify audit records are written as JSON Lines, that the parent
  directory is created, and that no destination is a silent no-op.
- **IT-007**: Verify generated tool definitions for flags, choice lists,
  repeatable options, required options, hidden options, and subcommands.
- **IT-008**: Verify the Anthropic, OpenAI, and MCP output shapes, tool name
  sanitisation, and the recorded command line.
- **IT-009**: Verify the module behaves identically under both the `yq` and the
  `jq` backend.

## Acceptance Criteria *(mandatory)*

1. The same reporting calls serve both audiences, and their fields match.
2. Tool definitions always reflect the live option spec.
3. An agent never receives a silent yes; it is either allowlisted or refused
   with a reason.
4. Audit records are machine readable and cover refusals as well as approvals.
