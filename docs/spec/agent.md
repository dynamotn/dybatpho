# Feature Specification: Agent-Facing Script Utilities

**Feature Branch**: `[feature-agent]`
**Status**: Implemented
**Input**: Existing source analysis: `src/agent.sh`, `docs/agent.md`, `test/agent.bats`, `example/agent_ops.sh`, and `example/agent_mcp.sh` (GitHub issue #45 for the MCP server)

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
- Let an MCP host such as Claude Code or Claude Desktop drive the script
  directly, with no server written outside the library.

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

### User Story 6 - Serve the CLI to an MCP host (Priority: P1)

As a script author, I want `mytool mcp` to be a complete MCP stdio server for
the script's own commands, so that registering it with a host is one line and
the arguments a model sends reach the parser exactly as it meant them.

**Independent Test**: Pipe a scripted sequence of JSON-RPC lines into the
server and check each reply line; build the command line for a set of tricky
arguments and parse it back with the same spec.

**Acceptance Scenarios**:

1. **Given** an `initialize` request, **When** it names a supported protocol
   version, **Then** that version is echoed, and the newest supported one is
   returned otherwise, with the `tools` capability and the server name
2. **Given** a notification, a blank line, or a response from the client,
   **When** it is read, **Then** nothing is written back
3. **Given** `tools/list`, **When** it is answered, **Then** the tools are
   those `dybatpho::agent_mcp` describes, without the internal command field
4. **Given** `tools/call` with valid arguments, **When** it is answered,
   **Then** the tool's recorded command runs in agent mode with no stdin, and
   the reply carries stdout, stderr as a separate item, `isError` from the
   exit status, and `structuredContent` when stdout is one JSON object
5. **Given** an unknown tool, an unknown argument, a missing required one, or
   a value of the wrong JSON type, **When** `tools/call` is answered, **Then**
   it is refused with `-32602` and nothing runs
6. **Given** arguments holding spaces, leading dashes, newlines, `=`, Unicode,
   or `--`, **When** the command line is built and parsed with the same spec,
   **Then** every parsed value equals the argument sent
7. **Given** malformed JSON, an invalid request, or an unknown method, **When**
   it is read, **Then** the reply is error `-32700` with a null id, `-32600`, or
   `-32601` respectively
8. **Given** `DYBATPHO_AGENT_MCP_TIMEOUT`, **When** a call runs longer, **Then**
   it is ended and reported as an error that says it timed out
9. **Given** stdin closes, **When** the loop reads it, **Then** the server ends
   with success

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
- `jq` is not installed (installing only `yq` is not enough).
- `DYBATPHO_AGENT_MODE` holds a value other than `auto`, `on` or `off` while a script asks whether an agent is driving.
- An option spec with display options such as `--help`, positional arguments
  (optional and variadic), negatable flags, or params with only a short switch.
- A `tools/call` argument starting with `-`, equal to `--`, holding a newline,
  `=` or a NUL byte; a JSON number for a string option; `null` for an optional
  argument; a later positional given while an earlier optional one is omitted.
- A tool name differing from a real one only in case or by a trailing space.
- Two commands whose names render to the same tool name.
- A batch (a JSON array), several JSON values on one line, a request whose id
  is `null`, or `params` that is neither an object nor an array.
- A tool that writes to stderr, exits non-zero, reads stdin, runs past the
  timeout, or leaves a background process running; a non-numeric `DYBATPHO_AGENT_MCP_TIMEOUT`.
- Logging by the script or the library while the server runs.

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
- **FR-016**: The module MUST fail with a clear message naming `jq` when `jq` is not installed.
- **FR-017**: Documents MUST be built and read through the `json` module, so the
  module works on whichever backend the rest of the library found rather than
  requiring a specific one.
- **FR-018**: `agent_detect`, and every helper that branches on it, MUST resolve the mode in the caller's shell, so an unknown `DYBATPHO_AGENT_MODE` stops the script instead of reading as a person driving.
- **FR-019**: A spec read by `agent_tools` or `agent_mcp` MUST see the caller's variables: both MUST keep the locals that are in scope while the spec runs under the library's prefix.
- **FR-020**: Showing the audit log MUST print every record, including a last one that ends without a newline.
- **FR-021**: Generated schemas MUST omit display options and MUST describe
  positional arguments as strings, or arrays of strings when variadic, listing
  the required ones.
- **FR-022**: `dybatpho::agent_mcp_serve` MUST read one JSON-RPC 2.0 message
  per line from stdin and write one reply per line to stdout, answering
  `initialize`, `ping`, `tools/list` and `tools/call`, never replying to a
  notification, and ending with success when stdin closes.
- **FR-023**: `initialize` MUST echo a requested protocol version among
  `2025-06-18`, `2025-03-26` and `2024-11-05`, fall back to `2025-06-18`
  otherwise, and report the `tools` capability and `serverInfo` (the prefix,
  and `DYBATPHO_AGENT_MCP_VERSION` or the dybatpho version).
- **FR-024**: `tools/list` MUST return the tools of `dybatpho::agent_mcp`
  without the `x-dybatpho-command` field.
- **FR-025**: `tools/call` MUST find the tool by its exact name and MUST run
  only that tool's recorded command, never a command or path from the request.
- **FR-026**: `tools/call` MUST refuse with `-32602`, before running anything,
  an unknown tool, arguments that are not an object, an unknown argument, a
  missing required argument (an empty string or an empty array counts as
  missing), a false negatable flag with no switch to turn it off, a value whose JSON type differs from the schema,
  a string holding a NUL byte, and a positional given after an omitted one.
- **FR-027**: The command line MUST be built without evaluation or word
  splitting: a true flag as its switch, a false one omitted or, when
  negatable, as its declared `--no-`/`--without-` switch, a param as one `--name=value` element (the short switch and
  a separate value when it has no long one), a `multiple:` param once per
  item, and positional arguments after `--` in declaration order, so the
  parser reads back exactly the values sent.
- **FR-028**: A tool call MUST run in a child process with
  `DYBATPHO_AGENT_MODE=on`, stdin from `/dev/null`, the protocol stream
  closed, and `DYBATPHO_AGENT_MCP_TIMEOUT` seconds as its limit when non-zero.
  It MUST lead its own process group, killed when the call returns, and write
  to output files of its own, so nothing it leaves running can outlive the
  call or reach a later call's result.
- **FR-029**: A tool result MUST carry stdout as the first text item, stderr
  as a second one prefixed `stderr:` when non-empty, a timeout note when the
  limit ended the call, `isError` true for a non-zero exit, and
  `structuredContent` when stdout is a single JSON object.
- **FR-030**: Malformed JSON MUST be answered with `-32700` and a null id, an
  invalid request (including a batch) with `-32600`, an unknown method with
  `-32601`.
- **FR-031**: While the server runs, everything but protocol messages MUST go
  to stderr.
- **FR-032**: The server MUST stop the script before serving when
  `DYBATPHO_AGENT_MCP_TIMEOUT` is not a number of seconds or when two commands
  share a tool name.

### Key Entities *(include if feature involves data)*

- **Agent Mode**: Whether a model or a person is driving this run.
- **Result**: A status word plus named fields, rendered per audience.
- **Structured Error**: A stable code, a message, and an optional recovery
  hint.
- **Allowlist**: The set of actions an agent has been cleared to perform.
- **Audit Record**: One JSON line describing an action and its outcome.
- **Tool Definition**: A command, its description, and its argument schema,
  derived from the CLI option spec.
- **Tool Table**: Each served tool joined with its command line and option
  metadata, the only source a `tools/call` is dispatched from.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One script serves people and agents without a second code path
  for reporting.
- **SC-002**: Adding or changing a CLI option changes the generated tool
  definitions with no other edit.
- **SC-003**: An agent cannot perform an action that was not named in advance.
- **SC-004**: Every agent-initiated action and refusal is recoverable from the
  audit log.
- **SC-005**: A script becomes an MCP server with one entry point and one host
  registration line, and no argument a model sends is read as anything other
  than the value of the parameter it named.

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
- **IT-009**: Verify the module behaves identically whether or not `yq` is
  installed, and that the command tree is flattened by one `jq` call.
- **IT-010**: From a script file with `DYBATPHO_AGENT_MODE=sometimes`, have `agent_detect` used as a condition stop the script before the branch for a person runs.
- **IT-011**: Generate tool and MCP definitions from a spec whose description reads variables named like their locals, and see the caller's values.
- **IT-012**: Append a record without a trailing newline to the audit log and find it printed.
- **IT-013**: Pipe a scripted session into a server script and check each
  reply: `initialize`, no reply to a notification, a blank line or a client
  response, `ping`, `tools/list` without internal fields, a successful call
  with `structuredContent` and agent mode, a failing call with stderr apart,
  and `-32602`, `-32601`, `-32700` and `-32600` errors; logging on stderr.
- **IT-014**: Check the fallback protocol version and `DYBATPHO_AGENT_MCP_VERSION`.
- **IT-015**: Check the refusal of a batch, a wrong `jsonrpc`, a null id,
  string `params`, two values on one line, non-object arguments and a
  missing tool name.
- **IT-016**: Check a call ended by `DYBATPHO_AGENT_MCP_TIMEOUT`, the refusal
  of an invalid timeout, an empty input ending with success, and the refusal
  of two commands with the same tool name.
- **IT-017**: Round-trip arguments with spaces, leading dashes, `--`,
  newlines, `=`, Unicode and a negatable flag set to false through the argv
  builder and the parser, and check the exact argv for a param, a short-only
  param and a positional.
- **IT-019**: A tool leaves a process running that writes after a delay; the
  next call's result stays clean and the process never gets to write.
- **IT-020**: Refuse a false short-only negatable flag, and an empty required
  param or variadic positional, as invalid params.
- **IT-018**: Check every refusal of the argv builder: unknown argument, wrong
  case, missing option and positional, each type mismatch, a NUL byte,
  non-object arguments, an unknown or near-miss tool name, a positional after
  an omitted one, and an unreadable table reported as a server fault.

## Acceptance Criteria *(mandatory)*

1. The same reporting calls serve both audiences, and their fields match.
2. Tool definitions always reflect the live option spec.
3. An agent never receives a silent yes; it is either allowlisted or refused
   with a reason.
4. Audit records are machine readable and cover refusals as well as approvals.
5. A script's `mcp` entry point serves its commands to an MCP host, and a
   `tools/call` can only run the tool's own command with the arguments as
   values.
