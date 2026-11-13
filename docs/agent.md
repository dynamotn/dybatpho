# agent.sh

Utilities for making a script usable by an AI agent

> 🧭 Source: [src/agent.sh](../src/agent.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

Where `ai.sh` lets a script call a model, this module points the other way:
it makes a script something a model can drive safely. A tool that an agent
invokes has different needs from one a person types — it must say what it
did in a form that parses, it must never block on a prompt nobody will
answer, it must refuse dangerous work it was not explicitly cleared for,
and it must leave a record of what an agent made it do.

The module provides six things:

- **Detection** – is this run being driven by an agent, or by a person?
- **Structured results and errors** – JSON for agents, plain text for people,
  from the same call site
- **Tool definitions** – Anthropic, OpenAI, and MCP tool schemas generated
  from the same `cli.sh` option spec that drives the parser, so they cannot
  drift apart
- **An allowlist gate** – interactive confirmation for people, an explicit
  allowlist for agents, never a silent yes
- **An audit trail** – one JSON line per agent-initiated action
- **An MCP server** – the same tools served over stdio, so `mytool mcp` can
  be registered with Claude Code or Claude Desktop as it is

### 🌍 Environment

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_AGENT_MODE`** | string | no | `auto` | `auto`, `on`, or `off` |
| **`DYBATPHO_AGENT_ALLOW`** | string | yes |  | Space separated actions an agent may perform, or `all` |
| **`DYBATPHO_AGENT_AUDIT_FILE`** | string | yes |  | Path of the JSON Lines audit log |
| **`DYBATPHO_AGENT_ENV`** | string | yes |  | Extra environment variable names that mark an agent run |
| **`DYBATPHO_AGENT_MCP_TIMEOUT`** | number | no | `0` | Seconds an MCP tool call may run, `0` for no limit |

### 🚀 Highlights

- [`dybatpho::agent_mode`](#dybatphoagent_mode) — Print whether this run is being driven by an agent. `auto` looks for a known runtime marker; `on` and `off` skip detection.
- [`dybatpho::agent_detect`](#dybatphoagent_detect) — Return success when an agent is driving this run.
- [`dybatpho::agent_result`](#dybatphoagent_result) — Report the outcome of an operation in the caller's language. Agents get one JSON object on stdout; people get an aligned key/value line.
- [`dybatpho::agent_error`](#dybatphoagent_error) — Report a failure with a machine-readable code and a fix hint.
- [`dybatpho::agent_context`](#dybatphoagent_context) — Describe the environment an agent is operating in.
- [`dybatpho::agent_confirm`](#dybatphoagent_confirm) — Gate an action behind confirmation, or behind an allowlist. A person is asked; an agent is checked against `DYBATPHO_AGENT_ALLOW` and refused when the action was not cleared in advance. Either way the decision is written to the audit log.
- [`dybatpho::agent_audit`](#dybatphoagent_audit) — Append one action to the audit log. Records are JSON Lines so a later run, or a human, can replay what an agent did without parsing prose.
- [`dybatpho::agent_audit_show`](#dybatphoagent_audit_show) — Print the audit log as readable lines.
- [`dybatpho::agent_tools`](#dybatphoagent_tools) — Generate tool definitions from a CLI option spec. The root command and every subcommand become one tool, named by joining the command path with underscores. Because the definitions come from the same spec the parser uses, a tool can never describe an option the CLI does not have.
- [`dybatpho::agent_mcp`](#dybatphoagent_mcp) — Generate an MCP `tools/list` payload for a CLI option spec. Each tool carries the command line it maps to under `x-dybatpho-command`, so a thin MCP server can dispatch without a second source of truth.
- [`dybatpho::agent_mcp_serve`](#dybatphoagent_mcp_serve) — Serve a script's commands as MCP tools over stdio. A JSON-RPC 2.0 loop answers `initialize`, `ping`, `tools/list` and `tools/call`, one message per line, until stdin closes. The tools are those `dybatpho::agent_mcp` lists, and each call runs the tool's recorded command in agent mode, so `dybatpho::agent_confirm` and `dybatpho::agent_audit` apply unchanged.

<a id="usage"></a>

## 🚀 Usage

### When to use this module

Use `agent.sh` when you want to:

- expose an existing CLI to Claude, an MCP client, or a function-calling loop
- keep a script safe when something non-human is choosing its arguments
- return results an agent can branch on instead of prose it has to guess at
- know afterwards which actions an agent took, and which it was refused

### Common patterns

#### Answer in the caller's language

```bash
dybatpho::agent_result ok deployed=api version=1.4.2
# agent mode: {"status":"ok","deployed":"api","version":"1.4.2"}
# human mode: status=ok deployed=api version=1.4.2
```

#### Publish the CLI as tools

```bash
dybatpho::agent_tools _spec_root mytool anthropic  # Claude tool definitions
dybatpho::agent_tools _spec_root mytool openai     # function-calling schema
dybatpho::agent_mcp _spec_root mytool              # MCP tools/list payload
```

#### Serve the CLI to an MCP host

```bash
[[ "${1:-}" == mcp ]] && { dybatpho::agent_mcp_serve _spec_root mytool "$0"; exit; }
```

Register it with `claude mcp add mytool -- /usr/local/bin/mytool mcp`, or in
Claude Desktop's `claude_desktop_config.json`:

```json
{"mcpServers": {"mytool": {"command": "/usr/local/bin/mytool", "args": ["mcp"]}}}
```

#### Gate a dangerous action

```bash
export DYBATPHO_AGENT_ALLOW="restart"
dybatpho::agent_confirm restart "Restart the API service" \
  && systemctl restart api
```

<a id="see-also"></a>

## 🔗 See also

- [example/agent_ops.sh](../example/agent_ops.sh)
- [example/agent_mcp.sh](../example/agent_mcp.sh)
- [docs/cli.md` for the option spec these tool definitions are generated from](cli.md` for the option spec these tool definitions are generated from)

<a id="tips"></a>

## 💡 Tips

- Agent mode is detected automatically; force it either way with `DYBATPHO_AGENT_MODE`
- Tool definitions are generated from the live option spec, so a new flag becomes a new tool parameter without a second edit

**[`dybatpho::agent_result`](#dybatphoagent_result)**

- Keep status words to a small fixed set so an agent can branch on them

**[`dybatpho::agent_error`](#dybatphoagent_error)**

- Error codes are a contract; keep them stable across releases so an agent can branch on them

**[`dybatpho::agent_context`](#dybatphoagent_context)**

- Call this first in an agent-facing subcommand so the model knows what it is working with before it acts

**[`dybatpho::agent_confirm`](#dybatphoagent_confirm)**

- Never add `all` to the allowlist in a production runbook; list the actions you actually intend to delegate

**[`dybatpho::agent_tools`](#dybatphoagent_tools)**

- Feed the result straight into the tool registry of the `ai` module, or into an API request; it needs no hand editing

**[`dybatpho::agent_mcp_serve`](#dybatphoagent_mcp_serve)**

- Keep the `mcp` entry point out of the spec, as the example does, so the server does not list itself as a tool

<a id="reference"></a>

## 📚 Reference

### `dybatpho::agent_mode`

Print whether this run is being driven by an agent.
`auto` looks for a known runtime marker; `on` and `off` skip detection.

**🧪 Example**

```bash
if [[ "$(dybatpho::agent_mode)" == on ]]; then
  dybatpho::agent_result ok
else
  dybatpho::success "Done"
fi

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_MODE`** | string | Force the answer with `on` or `off` |

**📤 Output on stdout**

- `on` or `off`

**🚦 Exit codes**

- `0`: The mode was printed
- `1`: Stop the script when the configured mode is unknown

---

### `dybatpho::agent_detect`

Return success when an agent is driving this run.

**🧪 Example**

```bash
dybatpho::agent_detect && DYBATPHO_DRY_RUN=true

```

_Function has no arguments._

**🚦 Exit codes**

- `0`: An agent is driving
- `1`: A person is driving

**🔗 See also**

- [dybatpho::agent_mode](#dybatphoagent_mode)

---

### `dybatpho::agent_result`

Report the outcome of an operation in the caller's language.
Agents get one JSON object on stdout; people get an aligned key/value line.

**🧪 Example**

```bash
dybatpho::agent_result ok service=api replicas=3
dybatpho::agent_result skipped reason="already up to date"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Status word, such as `ok`, `skipped`, or `failed` |
| `$@` | string | Additional `key=value` pairs |

**📤 Output on stdout**

- A JSON object in agent mode, `key=value` text otherwise

**🚦 Exit codes**

- `0`: The result was printed
- `1`: Missing status, or a field that is not `key=value`

---

### `dybatpho::agent_error`

Report a failure with a machine-readable code and a fix hint.

**🧪 Example**

```bash
dybatpho::agent_error missing_config "No config file at ${path}" \
  "Run 'mytool init' first" || exit $?

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Stable error code, lowercase with underscores |
| `$2` | string | yes |  | Human readable message |
| `$3` | string | no |  | Hint describing how to recover |

**📤 Output on stdout**

- A JSON object in agent mode; nothing otherwise

**🚦 Exit codes**

- `1`: Always, so the call can be chained with `||`

---

### `dybatpho::agent_context`

Describe the environment an agent is operating in.

**🧪 Example**

```bash
dybatpho::agent_context

```

_Function has no arguments._

**📤 Output on stdout**

- JSON object with platform, working directory, git state, loaded modules, and run flags

**🚦 Exit codes**

- `0`: The context was printed

---

### `dybatpho::agent_confirm`

Gate an action behind confirmation, or behind an allowlist.
A person is asked; an agent is checked against `DYBATPHO_AGENT_ALLOW` and
refused when the action was not cleared in advance. Either way the decision
is written to the audit log.

**🧪 Example**

```bash
export DYBATPHO_AGENT_ALLOW="restart rollback"
dybatpho::agent_confirm restart "Restart the API service" || exit 0

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Action name, matched against the allowlist |
| `$2` | string | no |  | Description shown to a human |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_ALLOW`** | string | Actions an agent may perform |

**📤 Output on stdout**

- A refusal object in agent mode when the action is not allowed

**🚦 Exit codes**

- `0`: The action is approved
- `1`: The action is refused

**🔗 See also**

- [dybatpho::confirm](#dybatphoconfirm)

---

### `dybatpho::agent_audit`

Append one action to the audit log.
Records are JSON Lines so a later run, or a human, can replay what an agent
did without parsing prose.

**🧪 Example**

```bash
export DYBATPHO_AGENT_AUDIT_FILE=/var/log/mytool-agent.jsonl
dybatpho::agent_audit deploy "version 1.4.2 to staging"

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Action name |
| `$2` | string | no |  | Detail |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_AUDIT_FILE`** | string | Destination path; nothing is written when empty |

**🚦 Exit codes**

- `0`: The record was appended, or auditing is disabled
- `1`: Missing arguments

---

### `dybatpho::agent_audit_show`

Print the audit log as readable lines.

**🧪 Example**

```bash
dybatpho::agent_audit_show

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_AUDIT_FILE`** | string | Log to read |

**📤 Output on stdout**

- One `timestamp action detail` line per record

**🚦 Exit codes**

- `0`: The log was printed, or there is nothing to print

---

### `dybatpho::agent_tools`

Generate tool definitions from a CLI option spec.
The root command and every subcommand become one tool, named by joining the
command path with underscores. Because the definitions come from the same
spec the parser uses, a tool can never describe an option the CLI does not
have.

**🧪 Example**

```bash
dybatpho::agent_tools _spec_root mytool            # Anthropic shape
dybatpho::agent_tools _spec_root mytool openai     # function-calling shape

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Spec function, the same one passed to `dybatpho::generate_from_spec` |
| `$2` | string | no |  | Tool name prefix, default is the script name |
| `$3` | string | no | `anthropic` | Output shape, `anthropic` or `openai` |

**📤 Output on stdout**

- JSON array of tool definitions

**🚦 Exit codes**

- `0`: The definitions were printed
- `1`: Missing arguments or an unknown output shape

**🔗 See also**

- [dybatpho::generate_schema](#dybatphogenerate_schema)

---

### `dybatpho::agent_mcp`

Generate an MCP `tools/list` payload for a CLI option spec.
Each tool carries the command line it maps to under `x-dybatpho-command`, so
a thin MCP server can dispatch without a second source of truth.

**🧪 Example**

```bash
dybatpho::agent_mcp _spec_root mytool > mytool-mcp.json

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Spec function |
| `$2` | string | no |  | Server and tool name prefix, default is the script name |
| `$3` | string | no |  | Command an MCP server should execute, default is the script path |

**📝 Notes**

- This is the tool manifest; `dybatpho::agent_mcp_serve` serves the same tools to an MCP host

**📤 Output on stdout**

- JSON object with `name`, `version`, and a `tools` array

**🚦 Exit codes**

- `0`: The payload was printed
- `1`: Missing arguments

**🔗 See also**

- [dybatpho::agent_tools](#dybatphoagent_tools)
- [dybatpho::agent_mcp_serve](#dybatphoagent_mcp_serve)

---

### `dybatpho::agent_mcp_serve`

Serve a script's commands as MCP tools over stdio.
A JSON-RPC 2.0 loop answers `initialize`, `ping`, `tools/list` and
`tools/call`, one message per line, until stdin closes. The tools are those
`dybatpho::agent_mcp` lists, and each call runs the tool's recorded command
in agent mode, so `dybatpho::agent_confirm` and `dybatpho::agent_audit`
apply unchanged.

> ⚠️ **Warning**
>
> Tools, not resources or prompts; a call returns one result, with no progress notifications

**🧪 Examples**

```bash
# mytool: `mytool mcp` serves every other command as a tool.
if [[ "${1:-}" == mcp ]]; then
  dybatpho::agent_mcp_serve _spec_root mytool "$0"
  exit
fi
dybatpho::generate_from_spec _spec_root "$@"

```

```bash
claude mcp add mytool -- /usr/local/bin/mytool mcp

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Spec function |
| `$2` | string | no |  | Server and tool name prefix, default is the script name |
| `$3` | string | no |  | Command the tools run, default is the script path; it must be executable |

**🌍 Environment variables**

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_AGENT_MCP_TIMEOUT`** | number | no | `0` | Seconds a tool call may run, `0` for no limit |
| **`DYBATPHO_AGENT_MCP_VERSION`** | string | yes |  | Version reported in `serverInfo`, default is the dybatpho version |

**📝 Notes**

- Arguments are checked before anything runs: an unknown tool, an unknown argument, a missing required one or a value of the wrong JSON type is refused with error `-32602`. A flag is passed as its switch (`--no-<name>` when negatable and false), a param as one `--name=value` element, a `multiple:` param once per item, and positional arguments after `--`, so a value is never read as an option. A `null` argument counts as omitted.
- A call runs in a child process with `DYBATPHO_AGENT_MODE=on` and stdin from `/dev/null`. Its result carries stdout as the first text item and stderr, when there is any, as a second one starting `stderr:`; `isError` is set from the exit status, and stdout that is a single JSON object, such as `dybatpho::agent_result` prints, is also returned as `structuredContent`.
- stdout is the protocol stream: for the whole loop, everything else the script or the library prints goes to stderr. Notifications get no reply.
- The protocol version is the one the client asks for when it is `2025-06-18`, `2025-03-26` or `2024-11-05`, and `2025-06-18` otherwise. A batch (a JSON array) is refused as an invalid request.

**📤 Output on stdout**

- JSON-RPC responses, one per line

**🚦 Exit codes**

- `0`: stdin closed
- `1`: Stop the script on missing arguments, an invalid timeout, or two commands with the same tool name

**🔗 See also**

- [dybatpho::agent_mcp](#dybatphoagent_mcp)
