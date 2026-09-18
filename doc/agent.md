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


The module provides five things:


- **Detection** – is this run being driven by an agent, or by a person?
- **Structured results and errors** – JSON for agents, plain text for people,
  from the same call site
- **Tool definitions** – Anthropic, OpenAI, and MCP tool schemas generated
  from the same `cli.sh` option spec that drives the parser, so they cannot
  drift apart
- **An allowlist gate** – interactive confirmation for people, an explicit
  allowlist for agents, never a silent yes
- **An audit trail** – one JSON line per agent-initiated action



### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_MODE`** | string | `auto` (default), `on`, or `off` |
| **`DYBATPHO_AGENT_ALLOW`** | string | Space separated actions an agent may perform, or `all` |
| **`DYBATPHO_AGENT_AUDIT_FILE`** | string | Path of the JSON Lines audit log |
| **`DYBATPHO_AGENT_ENV`** | string | Extra environment variable names that mark an agent run |

### 🚀 Highlights

- [`__agent_require_json`](#__agent_require_json) — Fail loudly when no JSON backend is installed.
- [`__agent_marker_present`](#__agent_marker_present) — Return success when an agent runtime marker is present.
- [`dybatpho::agent_mode`](#dybatphoagent_mode) — Print whether this run is being driven by an agent. `auto` looks for a known runtime marker; `on` and `off` skip detection.
- [`dybatpho::agent_detect`](#dybatphoagent_detect) — Return success when an agent is driving this run.
- [`dybatpho::agent_result`](#dybatphoagent_result) — Report the outcome of an operation in the caller's language. Agents get one JSON object on stdout; people get an aligned key/value line.
- [`dybatpho::agent_error`](#dybatphoagent_error) — Report a failure with a machine-readable code and a fix hint.
- [`dybatpho::agent_context`](#dybatphoagent_context) — Describe the environment an agent is operating in.
- [`__agent_allowed`](#__agent_allowed) — Return success when an action appears in the agent allowlist.
- [`dybatpho::agent_confirm`](#dybatphoagent_confirm) — Gate an action behind confirmation, or behind an allowlist. A person is asked; an agent is checked against `DYBATPHO_AGENT_ALLOW` and refused when the action was not cleared in advance. Either way the decision is written to the audit log.
- [`dybatpho::agent_audit`](#dybatphoagent_audit) — Append one action to the audit log. Records are JSON Lines so a later run, or a human, can replay what an agent did without parsing prose.
- [`dybatpho::agent_audit_show`](#dybatphoagent_audit_show) — Print the audit log as readable lines.
- [`__agent_flatten_schema`](#__agent_flatten_schema) — Turn a CLI schema into a flat list of callable commands. Each command carries the options it accepts, with hidden entries dropped. The tree is walked here rather than in a filter because only one of the two JSON backends supports user-defined functions, and a schema can nest.
- [`__agent_flatten_command`](#__agent_flatten_command) — Append one command and its subcommands to a flat list.
- [`__agent_options_schema`](#__agent_options_schema) — Build a JSON Schema object from a command's option list. Flags become booleans, parameters become strings, `choices:` becomes an `enum`, and `multiple:true` becomes an array of that item type.
- [`dybatpho::agent_tools`](#dybatphoagent_tools) — Generate tool definitions from a CLI option spec. The root command and every subcommand become one tool, named by joining the command path with underscores. Because the definitions come from the same spec the parser uses, a tool can never describe an option the CLI does not have.
- [`__agent_tool_name`](#__agent_tool_name) — Derive a callable tool name from a flattened command entry. The command path is joined with underscores and anything a tool name may not contain is replaced, so a prefix with a space still yields a valid name.
- [`dybatpho::agent_mcp`](#dybatphoagent_mcp) — Generate an MCP `tools/list` payload for a CLI option spec. Each tool carries the command line it maps to under `x-dybatpho-command`, so a thin MCP server can dispatch without a second source of truth.

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


#### Gate a dangerous action


```bash
export DYBATPHO_AGENT_ALLOW="restart"
dybatpho::agent_confirm restart "Restart the API service" \
  && systemctl restart api
```



<a id="see-also"></a>
## 🔗 See also

- [example/agent_ops.sh](../example/agent_ops.sh)
- [doc/cli.md` for the option spec these tool definitions are generated from](cli.md` for the option spec these tool definitions are generated from)

<a id="tips"></a>
## 💡 Tips

- Agent mode is detected automatically; force it either way with `DYBATPHO_AGENT_MODE` @note Tool definitions are generated from the live option spec, so a new flag becomes a new tool parameter without a second edit

### `dybatpho::agent_result`

- Keep status words to a small fixed set so an agent can branch on them

### `dybatpho::agent_error`

- Error codes are a contract; keep them stable across releases so an agent can branch on them

### `dybatpho::agent_context`

- Call this first in an agent-facing subcommand so the model knows what it is working with before it acts

### `dybatpho::agent_confirm`

- Never add `all` to the allowlist in a production runbook; list the actions you actually intend to delegate

### `dybatpho::agent_tools`

- Feed the result straight into the tool registry of the `ai` module, or into an API request; it needs no hand editing

<a id="reference"></a>
## 📚 Reference

### `__agent_require_json`

Fail loudly when no JSON backend is installed.

_Function has no arguments._

**🚦 Exit codes**

- `0`: `yq` or `jq` is available
- `127`: Stop the script because neither is installed

**🔗 See also**

- [dybatpho::json_object](#dybatphojson_object)


---

### `__agent_marker_present`

Return success when an agent runtime marker is present.

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_ENV`** | string | Additional variable names to treat as markers |

**🚦 Exit codes**

- `0`: At least one marker variable is set and non-empty
- `1`: No marker is present


---

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
dybatpho::agent_detect && export DRY_RUN=true

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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Stable error code, lowercase with underscores |
| `$2` | string | Human readable message |
| `$3` | string | Optional hint describing how to recover |

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

### `__agent_allowed`

Return success when an action appears in the agent allowlist.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Action name |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AGENT_ALLOW`** | string | Space separated action names, or `all` |

**🚦 Exit codes**

- `0`: The action is allowed
- `1`: The action is not allowed


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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Action name, matched against the allowlist |
| `$2` | string | Optional description shown to a human |

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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Action name |
| `$2` | string | Optional detail |

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

### `__agent_flatten_schema`

Turn a CLI schema into a flat list of callable commands.
Each command carries the options it accepts, with hidden entries dropped.
The tree is walked here rather than in a filter because only one of the two
JSON backends supports user-defined functions, and a schema can nest.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | CLI schema JSON from `dybatpho::generate_schema` |

**📤 Output on stdout**

- JSON array of `{path, description, options}` objects


---

### `__agent_flatten_command`

Append one command and its subcommands to a flat list.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Command node JSON |
| `$2` | string | Path of the parent command, as a JSON array |
| `$3` | string | Accumulated list JSON |

**📤 Output on stdout**

- The list with this command and its descendants appended


---

### `__agent_options_schema`

Build a JSON Schema object from a command's option list.
Flags become booleans, parameters become strings, `choices:` becomes an
`enum`, and `multiple:true` becomes an array of that item type.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Options array JSON |

**📤 Output on stdout**

- JSON Schema object


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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Spec function, the same one passed to `dybatpho::generate_from_spec` |
| `$2` | string | Tool name prefix, default is the script name |
| `$3` | string | Output shape, `anthropic` (default) or `openai` |

**📤 Output on stdout**

- JSON array of tool definitions

**🚦 Exit codes**

- `0`: The definitions were printed
- `1`: Missing arguments or an unknown output shape

**🔗 See also**

- [dybatpho::generate_schema](#dybatphogenerate_schema)


---

### `__agent_tool_name`

Derive a callable tool name from a flattened command entry.
The command path is joined with underscores and anything a tool name may not
contain is replaced, so a prefix with a space still yields a valid name.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Flattened command entry JSON |

**📤 Output on stdout**

- Tool name


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

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Spec function |
| `$2` | string | Server and tool name prefix, default is the script name |
| `$3` | string | Command an MCP server should execute, default is the script path |

**📝 Notes**

- This is the tool manifest, not a running server; point your MCP host at it and dispatch with the recorded command

**📤 Output on stdout**

- JSON object with `name`, `version`, and a `tools` array

**🚦 Exit codes**

- `0`: The payload was printed
- `1`: Missing arguments

**🔗 See also**

- [dybatpho::agent_tools](#dybatphoagent_tools)

