# ai.sh

Utilities for calling large language models from shell scripts

> 🧭 Source: [src/ai.sh](../src/ai.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module turns an LLM into an ordinary shell dependency: one function
call in, text on stdout, a non-zero exit code when something fails. It
speaks four backends behind a single API:


- **anthropic** – Claude Messages API (`/v1/messages`)
- **openai** – any OpenAI-compatible `/v1/chat/completions` endpoint
  (OpenAI, Groq, OpenRouter, vLLM, LM Studio, ...)
- **ollama** – a local Ollama daemon, no API key required
- **cli** – an already installed command line client (`claude`, `llm`,
  `ollama`), for machines where the key never leaves the tool that owns it


On top of the transport it provides the things a script actually needs
around a model call: multi-turn conversations stored in a file, structured
JSON output validated against a schema, token streaming, a tool-use loop
that runs shell functions, response caching, redaction of secrets before
anything is sent, and a call budget that stops a runaway loop.



### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_PROVIDER`** | string | Backend to use: `auto` (default), `anthropic`, `openai`, `ollama`, or `cli` |
| **`DYBATPHO_AI_MODEL`** | string | Model identifier; defaults to the provider's recommended model |
| **`DYBATPHO_AI_BASE_URL`** | string | Override the provider base URL, for proxies and compatible gateways |
| **`DYBATPHO_AI_API_KEY`** | string | API key; `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` are used as fallbacks |
| **`DYBATPHO_AI_MAX_TOKENS`** | number | Output token ceiling for one response (default `16000`) |
| **`DYBATPHO_AI_EFFORT`** | string | Reasoning effort for Anthropic models: `low`, `medium`, `high`, `xhigh`, or `max` |
| **`DYBATPHO_AI_TEMPERATURE`** | string | Sampling temperature; only sent to the `openai` and `ollama` backends |
| **`DYBATPHO_AI_SYSTEM`** | string | Default system prompt used when a call does not pass one |
| **`DYBATPHO_AI_TIMEOUT`** | number | Total curl timeout in seconds for one model call (default `300`) |
| **`DYBATPHO_AI_CACHE`** | bool | Cache responses on disk keyed by request content (default `false`) |
| **`DYBATPHO_AI_CACHE_DIR`** | string | Cache directory (default `${XDG_CACHE_HOME:-${HOME}/.cache}/dybatpho/ai`) |
| **`DYBATPHO_AI_CACHE_TTL`** | number | Seconds a cached response stays valid (default `86400`) |
| **`DYBATPHO_AI_REDACT`** | bool | Mask registered secrets in every prompt before sending (default `true`) |
| **`DYBATPHO_AI_MAX_CALLS`** | number | Stop after this many model calls in one script; `0` means no limit |
| **`DYBATPHO_AI_MAX_STEPS`** | number | Maximum tool-use rounds in `dybatpho::ai_run` (default `10`) |
| **`DYBATPHO_AI_JSON_RETRIES`** | number | Attempts `dybatpho::ai_json` makes before failing (default `2`) |
| **`DYBATPHO_AI_CLI`** | string | Command used by the `cli` backend: `claude`, `llm`, or `ollama` |
| **`DYBATPHO_AI_ANTHROPIC_VERSION`** | string | Value of the `anthropic-version` header (default `2023-06-01`) |
| **`DYBATPHO_AI_STATE_FILE`** | string | File the call and token counters are kept in |

### 🚀 Highlights

- [`__ai_require_json`](#__ai_require_json) — Fail loudly when no JSON backend is installed.
- [`__ai_redact`](#__ai_redact) — Mask registered secrets in text before it leaves the machine.
- [`__ai_state_cleanup_once`](#__ai_state_cleanup_once) — Arrange for the counter file to be removed when the script ends. Sourcing a module must not touch the host script's traps, so this runs on first use rather than at load time. A command substitution gets its own process, and a handler registered there would delete the counters the moment that subshell returned, so only the top-level shell registers one.
- [`__ai_state_read`](#__ai_state_read) — Print the counter document, creating it on first use.
- [`__ai_state_write`](#__ai_state_write) — Replace the counter document.
- [`__ai_budget_check`](#__ai_budget_check) — Stop the script when the call budget is already used up. This is deliberately separate from counting: the count happens deep inside a command substitution, where an `exit` would only leave that subshell, so the refusal has to be raised by the public function the caller invoked.
- [`__ai_count_call`](#__ai_count_call) — Count one model call in the shared counter file.
- [`__ai_record_usage`](#__ai_record_usage) — Record the token usage a provider reported for one call.
- [`__ai_ollama_alive`](#__ai_ollama_alive) — Return success when an Ollama daemon answers on the base URL.
- [`dybatpho::ai_provider`](#dybatphoai_provider) — Resolve which backend a call will use. Detection order for `auto`: an Anthropic key, an OpenAI key, a live local Ollama daemon, then any supported command line client.
- [`dybatpho::ai_model`](#dybatphoai_model) — Resolve the model identifier for the active backend.
- [`__ai_api_key`](#__ai_api_key) — Resolve the API key for an HTTP backend.
- [`__ai_base_url`](#__ai_base_url) — Resolve the base URL of an HTTP backend.
- [`dybatpho::ai_check`](#dybatphoai_check) — Report whether the module can run, without making a request. Checks the JSON backend, the transport command, and the credentials of the active backend.
- [`__ai_cli_command`](#__ai_cli_command) — Resolve the command used by the `cli` backend.
- [`__ai_conversation_build`](#__ai_conversation_build) — Build a conversation document from a system prompt and turns. The document is the provider-neutral shape the payload builders consume.
- [`__ai_payload_anthropic`](#__ai_payload_anthropic) — Render a conversation document into an Anthropic request body.
- [`__ai_payload_openai`](#__ai_payload_openai) — Render a conversation document into an OpenAI-compatible body.
- [`__ai_messages_with_system`](#__ai_messages_with_system) — Prepend the system prompt as a message, the way the OpenAI-compatible and Ollama APIs expect it.
- [`__ai_tools_as_functions`](#__ai_tools_as_functions) — Convert the neutral tool list into the OpenAI function shape, which both OpenAI-compatible endpoints and Ollama accept.
- [`__ai_payload_ollama`](#__ai_payload_ollama) — Render a conversation document into an Ollama chat body.
- [`__ai_cache_key`](#__ai_cache_key) — Compute the cache key of a request.
- [`__ai_cache_read`](#__ai_cache_read) — Print a cached response when one is present and still fresh.
- [`__ai_cache_write`](#__ai_cache_write) — Store a response body in the cache.
- [`dybatpho::ai_cache_clear`](#dybatphoai_cache_clear) — Forget every cached response.
- [`__ai_dry_run_body`](#__ai_dry_run_body) — Produce a provider-shaped placeholder response for `DRY_RUN`. Keeping the shape lets the rest of the pipeline run unchanged, so an example or a rehearsal exercises the real extraction and accounting code.
- [`__ai_http`](#__ai_http) — Send one request to an HTTP backend and print the raw response.
- [`__ai_assert_no_error`](#__ai_assert_no_error) — Stop the script when a provider response carries an error object.
- [`__ai_extract_text`](#__ai_extract_text) — Extract the assistant text from a provider response.
- [`__ai_usage_from_response`](#__ai_usage_from_response) — Read token usage out of a provider response into the module state.
- [`__ai_cli_complete`](#__ai_cli_complete) — Complete a conversation through the `cli` backend.
- [`__ai_complete`](#__ai_complete) — Complete a conversation and print the assistant text. This is the single funnel every public helper goes through.
- [`dybatpho::ai_ask`](#dybatphoai_ask) — Ask the model a single question and print its answer.
- [`dybatpho::ai_conversation_new`](#dybatphoai_conversation_new) — Create a conversation file and store its path in a variable. The file is registered for cleanup when the script exits.
- [`dybatpho::ai_conversation_add`](#dybatphoai_conversation_add) — Append a turn to a conversation file.
- [`dybatpho::ai_conversation_show`](#dybatphoai_conversation_show) — Print a conversation as readable transcript lines.
- [`dybatpho::ai_chat`](#dybatphoai_chat) — Send the next turn of a stored conversation and record the reply. Both the question and the answer are appended to the file, so the next call carries the full history.
- [`dybatpho::ai_json`](#dybatphoai_json) — Ask for an answer that matches a JSON schema, and validate it. Backends with native structured output are told about the schema; the rest are asked in the prompt. Either way the answer is parsed and re-checked locally, and the call is retried when the model returns something unusable.
- [`dybatpho::ai_stream`](#dybatphoai_stream) — Ask a question and print the answer as it is generated. Falls back to a normal buffered call on backends without a token stream.
- [`__ai_stream_chunk`](#__ai_stream_chunk) — Print one streamed delta without adding a line break. The JSON backends both terminate their output with a newline, which would turn a stream of fragments into a column of them, so exactly one trailing newline is removed while any the model actually produced are kept.
- [`dybatpho::ai_tool_register`](#dybatphoai_tool_register) — Register a shell function the model may call during `ai_run`.
- [`dybatpho::ai_tool_list`](#dybatphoai_tool_list) — Print the names of registered tools, one per line.
- [`dybatpho::ai_tool_clear`](#dybatphoai_tool_clear) — Unregister every tool.
- [`__ai_tools_json`](#__ai_tools_json) — Render the tool registry as a provider-neutral tools array.
- [`__ai_tool_invoke`](#__ai_tool_invoke) — Run one registered tool and print what it wrote. A failing handler is not fatal: its output is returned to the model as an error result so the model can adapt, which is the documented contract for tool results.
- [`dybatpho::ai_run`](#dybatphoai_run) — Answer a prompt, letting the model call registered tools first. The loop sends the prompt, runs whatever tools the model asks for, feeds the results back, and repeats until the model answers in text or the step limit is reached.
- [`dybatpho::ai_tokens_estimate`](#dybatphoai_tokens_estimate) — Estimate how many tokens a piece of text costs. The estimate is four characters per token, which is close enough to size a prompt or decide whether to truncate before a call; it is not a billing figure.
- [`dybatpho::ai_usage`](#dybatphoai_usage) — Print the token usage recorded so far.
- [`dybatpho::ai_usage_field`](#dybatphoai_usage_field) — Read one usage counter as a bare value.
- [`dybatpho::ai_usage_reset`](#dybatphoai_usage_reset) — Reset every usage counter and the call budget consumption.
- [`dybatpho::ai_budget`](#dybatphoai_budget) — Cap how many model calls the rest of the script may make.
- [`dybatpho::ai_redact`](#dybatphoai_redact) — Redact secrets and common personal identifiers in text. Registered secrets are masked first, then email addresses, IPv4 addresses, and long digit runs are replaced with placeholders.

<a id="usage"></a>
## 🚀 Usage

### When to use this module


Use `ai.sh` when you want to:


- summarize a log, a diff, or a test failure inside a pipeline
- classify or extract fields from unstructured text into JSON
- draft a release note or a commit message from real repository data
- give a maintenance script a natural language front end


### Common patterns


#### Ask a one-shot question


```bash
export ANTHROPIC_API_KEY="sk-ant-..."
dybatpho::ai_ask "Summarize this log in three bullets"
dybatpho::ai_ask "What broke?" "You are a terse SRE assistant"
```


#### Get machine-readable output


```bash
schema='{"type":"object","properties":{"severity":{"type":"string"}},
         "required":["severity"],"additionalProperties":false}'
dybatpho::ai_json "Classify this alert: ${alert}" "${schema}" > /tmp/out.json
severity=$(dybatpho::json_query /tmp/out.json '.severity')
```


#### Hold a conversation


```bash
local CHAT
dybatpho::ai_conversation_new CHAT "You are a Bash tutor"
dybatpho::ai_chat "${CHAT}" "How do I trap SIGINT?"
dybatpho::ai_chat "${CHAT}" "And clean up a temp file too?"
```


#### Let the model call your functions


```bash
function disk_free { df -h / | tail -n 1; }
dybatpho::ai_tool_register disk_free "Report free disk space" \
  '{"type":"object","properties":{}}' disk_free
dybatpho::ai_run "Are we about to run out of disk?"
```



<a id="see-also"></a>
## 🔗 See also

- [example/ai_ops.sh](../example/ai_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Set `DYBATPHO_AI_PROVIDER` to pin a backend; the default `auto` picks the first one whose credentials or command are present
- Every prompt is passed through `dybatpho::secret_mask` first, so values registered with `dybatpho::secret_register` never reach the provider @note Payloads and responses go through the `json` module, so this needs `yq` or `jq` like the rest of the library; building them by string concatenation is too escaping-sensitive to be safe

### `dybatpho::ai_ask`

- Pipe long inputs into the prompt with a command substitution rather than as a second argument

### `dybatpho::ai_json`

- Keep schemas flat; `additionalProperties: false` plus a `required` list gives the most reliable results

### `dybatpho::ai_tool_register`

- Write the description prescriptively: say when to call the tool, not only what it does

### `dybatpho::ai_run`

- Handlers receive their arguments as one JSON string; parse it with `dybatpho::json_query`

### `dybatpho::ai_redact`

- This is a coarse net, not a compliance control; do not send regulated data to a third party provider on the strength of it

<a id="reference"></a>
## 📚 Reference

### `__ai_require_json`

Fail loudly when no JSON backend is installed.

_Function has no arguments._

**🚦 Exit codes**

- `0`: `yq` or `jq` is available
- `127`: Stop the script because neither is installed

**🔗 See also**

- [dybatpho::json_object](#dybatphojson_object)


---

### `__ai_redact`

Mask registered secrets in text before it leaves the machine.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to redact |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_REDACT`** | bool | Return the text unchanged when not true |

**📤 Output on stdout**

- Redacted text

**🔗 See also**

- [dybatpho::secret_mask](#dybatphosecret_mask)


---

### `__ai_state_cleanup_once`

Arrange for the counter file to be removed when the script ends.
Sourcing a module must not touch the host script's traps, so this runs on
first use rather than at load time. A command substitution gets its own
process, and a handler registered there would delete the counters the moment
that subshell returned, so only the top-level shell registers one.

_Function has no arguments._

**🚦 Exit codes**

- `0`: A handler is registered, or this is not the shell that should register one

**🔗 See also**

- [dybatpho::cleanup_file_on_exit](#dybatphocleanup_file_on_exit)


---

### `__ai_state_read`

Print the counter document, creating it on first use.

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_STATE_FILE`** | string | File the counters are kept in |

**📤 Output on stdout**

- Counter JSON


---

### `__ai_state_write`

Replace the counter document.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Counter JSON |


---

### `__ai_budget_check`

Stop the script when the call budget is already used up.
This is deliberately separate from counting: the count happens deep inside a
command substitution, where an `exit` would only leave that subshell, so the
refusal has to be raised by the public function the caller invoked.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Calls this operation is about to make, default `1` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_MAX_CALLS`** | number | Budget; `0` disables the check |

**🚦 Exit codes**

- `0`: There is budget left
- `1`: Stop the script when the budget is exhausted


---

### `__ai_count_call`

Count one model call in the shared counter file.

**🚦 Exit codes**

- `0`: The counter was incremented


---

### `__ai_record_usage`

Record the token usage a provider reported for one call.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Input tokens |
| `$2` | number | Output tokens |
| `$3` | string | Model that answered |
| `$4` | string | Stop reason |


---

### `__ai_ollama_alive`

Return success when an Ollama daemon answers on the base URL.

_Function has no arguments._

**🚦 Exit codes**

- `0`: Ollama is reachable
- `1`: Ollama is not reachable


---

### `dybatpho::ai_provider`

Resolve which backend a call will use.
Detection order for `auto`: an Anthropic key, an OpenAI key, a live local
Ollama daemon, then any supported command line client.

**🧪 Example**

```bash
case "$(dybatpho::ai_provider)" in
  anthropic) dybatpho::info "Using Claude" ;;
  ollama) dybatpho::info "Running locally" ;;
esac

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_PROVIDER`** | string | Pin the backend instead of detecting one |

**📤 Output on stdout**

- One of `anthropic`, `openai`, `ollama`, or `cli`

**🚦 Exit codes**

- `0`: A backend was resolved
- `1`: Stop the script when the pinned name is unknown, or nothing is configured


---

### `dybatpho::ai_model`

Resolve the model identifier for the active backend.

**🧪 Example**

```bash
dybatpho::info "Asking $(dybatpho::ai_model)"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Optional backend name; detected when omitted |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_MODEL`** | string | Wins over every per-backend default |

**📤 Output on stdout**

- Model identifier

**🚦 Exit codes**

- `0`: A model name was resolved


---

### `__ai_api_key`

Resolve the API key for an HTTP backend.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |

**📤 Output on stdout**

- API key, empty for `ollama`

**🚦 Exit codes**

- `0`: A key was found, or the backend needs none
- `1`: Stop the script when a required key is missing


---

### `__ai_base_url`

Resolve the base URL of an HTTP backend.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |

**📤 Output on stdout**

- Base URL without a trailing slash


---

### `dybatpho::ai_check`

Report whether the module can run, without making a request.
Checks the JSON backend, the transport command, and the credentials of the
active backend.

**🧪 Example**

```bash
dybatpho::ai_check || dybatpho::die "Configure an AI backend first"

```

_Function has no arguments._

**📤 Output on stdout**

- Nothing on success; a diagnostic on stderr otherwise

**🚦 Exit codes**

- `0`: The active backend is usable
- `1`: Stop the script when a dependency or credential is missing


---

### `__ai_cli_command`

Resolve the command used by the `cli` backend.

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_CLI`** | string | Pin a command instead of probing |

**📤 Output on stdout**

- `claude`, `llm`, or `ollama`

**🚦 Exit codes**

- `0`: A supported client exists
- `127`: Stop the script when no client is installed


---

### `__ai_conversation_build`

Build a conversation document from a system prompt and turns.
The document is the provider-neutral shape the payload builders consume.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | System prompt, may be empty |
| `$@` | string | Alternating role and content pairs |

**📤 Output on stdout**

- Conversation JSON


---

### `__ai_payload_anthropic`

Render a conversation document into an Anthropic request body.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |
| `$2` | string | Tools array JSON, or `[]` |
| `$3` | string | Output schema JSON, or empty for free-form text |

**📤 Output on stdout**

- Request payload


---

### `__ai_payload_openai`

Render a conversation document into an OpenAI-compatible body.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |
| `$2` | string | Tools array JSON, or `[]` |
| `$3` | string | Output schema JSON, or empty for free-form text |

**📤 Output on stdout**

- Request payload


---

### `__ai_messages_with_system`

Prepend the system prompt as a message, the way the
OpenAI-compatible and Ollama APIs expect it.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |

**📤 Output on stdout**

- Message array JSON


---

### `__ai_tools_as_functions`

Convert the neutral tool list into the OpenAI function shape,
which both OpenAI-compatible endpoints and Ollama accept.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tools array JSON |

**📤 Output on stdout**

- Converted tools array JSON


---

### `__ai_payload_ollama`

Render a conversation document into an Ollama chat body.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |
| `$2` | string | Tools array JSON, or `[]` |
| `$3` | string | Output schema JSON, or empty for free-form text |

**📤 Output on stdout**

- Request payload


---

### `__ai_cache_key`

Compute the cache key of a request.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Request payload |

**📤 Output on stdout**

- Hexadecimal key


---

### `__ai_cache_read`

Print a cached response when one is present and still fresh.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cache key |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_CACHE_TTL`** | number | Maximum age in seconds |

**📤 Output on stdout**

- Cached response body

**🚦 Exit codes**

- `0`: A fresh entry was printed
- `1`: No usable entry


---

### `__ai_cache_write`

Store a response body in the cache.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Cache key |
| `$2` | string | Response body |

**🚦 Exit codes**

- `0`: Stored, or caching is disabled


---

### `dybatpho::ai_cache_clear`

Forget every cached response.

**🧪 Example**

```bash
dybatpho::ai_cache_clear

```

_Function has no arguments._

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_CACHE_DIR`** | string | Directory that is emptied |

**🚦 Exit codes**

- `0`: The cache directory is empty or absent


---

### `__ai_dry_run_body`

Produce a provider-shaped placeholder response for `DRY_RUN`.
Keeping the shape lets the rest of the pipeline run unchanged, so an example
or a rehearsal exercises the real extraction and accounting code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Request payload, inspected for a structured output contract |

**📤 Output on stdout**

- Response body in the provider's own shape


---

### `__ai_http`

Send one request to an HTTP backend and print the raw response.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Request payload |

**📤 Output on stdout**

- Raw JSON response body

**🚦 Exit codes**

- `0`: The provider answered with 2xx
- `4`: HTTP 4xx from the provider
- `5`: HTTP 5xx from the provider

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)


---

### `__ai_assert_no_error`

Stop the script when a provider response carries an error object.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Response body |

**🚦 Exit codes**

- `0`: The response has no error field
- `1`: Stop the script and report the provider message


---

### `__ai_extract_text`

Extract the assistant text from a provider response.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Response body |

**📤 Output on stdout**

- Assistant text, empty when the turn produced only tool calls


---

### `__ai_usage_from_response`

Read token usage out of a provider response into the module state.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backend name |
| `$2` | string | Response body |

**🔗 See also**

- [dybatpho::ai_usage](#dybatphoai_usage)


---

### `__ai_cli_complete`

Complete a conversation through the `cli` backend.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |

**📤 Output on stdout**

- Assistant text

**🚦 Exit codes**

- `0`: The client answered


---

### `__ai_complete`

Complete a conversation and print the assistant text.
This is the single funnel every public helper goes through.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation JSON |
| `$2` | string | Output schema JSON, or empty |

**📤 Output on stdout**

- Assistant text

**🚦 Exit codes**

- `0`: The provider answered


---

### `dybatpho::ai_ask`

Ask the model a single question and print its answer.

**🧪 Example**

```bash
dybatpho::ai_ask "Write a one line summary of this commit: ${subject}"
dybatpho::ai_ask "Is this config safe?" "You are a security reviewer"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt |
| `$2` | string | Optional system prompt; `DYBATPHO_AI_SYSTEM` is used when omitted |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_SYSTEM`** | string | Default system prompt |

**📤 Output on stdout**

- Assistant answer

**🚦 Exit codes**

- `0`: The provider answered
- `1`: Missing arguments, exhausted budget, or a provider error
- `4`: HTTP 4xx from the provider
- `5`: HTTP 5xx from the provider


---

### `dybatpho::ai_conversation_new`

Create a conversation file and store its path in a variable.
The file is registered for cleanup when the script exits.

**🧪 Example**

```bash
local CHAT
dybatpho::ai_conversation_new CHAT "You are a release manager"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Variable name that receives the file path |
| `$2` | string | Optional system prompt |

**🧩 Variable sets**

- **`The`**: named variable

**🚦 Exit codes**

- `0`: The conversation file exists
- `1`: Missing arguments

**🔗 See also**

- [dybatpho::create_temp](#dybatphocreate_temp)


---

### `dybatpho::ai_conversation_add`

Append a turn to a conversation file.

**🧪 Example**

```bash
dybatpho::ai_conversation_add "${CHAT}" assistant "Noted."

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation file path |
| `$2` | string | Role, `user` or `assistant` |
| `$3` | string | Message content |

**🚦 Exit codes**

- `0`: The turn was appended
- `1`: Missing arguments, unknown role, or unreadable file


---

### `dybatpho::ai_conversation_show`

Print a conversation as readable transcript lines.

**🧪 Example**

```bash
dybatpho::ai_conversation_show "${CHAT}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation file path |

**📤 Output on stdout**

- One `role: content` block per turn

**🚦 Exit codes**

- `0`: The transcript was printed
- `1`: Missing argument or unreadable file


---

### `dybatpho::ai_chat`

Send the next turn of a stored conversation and record the reply.
Both the question and the answer are appended to the file, so the next call
carries the full history.

**🧪 Example**

```bash
dybatpho::ai_chat "${CHAT}" "What changed since v1.2.0?"
dybatpho::ai_chat "${CHAT}" "Now write it as release notes"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Conversation file path |
| `$2` | string | User message |

**📤 Output on stdout**

- Assistant answer

**🚦 Exit codes**

- `0`: The provider answered
- `1`: Missing arguments, unreadable file, or a provider error

**🔗 See also**

- [dybatpho::ai_conversation_new](#dybatphoai_conversation_new)


---

### `dybatpho::ai_json`

Ask for an answer that matches a JSON schema, and validate it.
Backends with native structured output are told about the schema; the rest
are asked in the prompt. Either way the answer is parsed and re-checked
locally, and the call is retried when the model returns something unusable.

**🧪 Example**

```bash
schema='{"type":"object","properties":{"ok":{"type":"boolean"}},
         "required":["ok"],"additionalProperties":false}'
dybatpho::ai_json "Did this deploy succeed? ${log}" "${schema}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt |
| `$2` | string | JSON schema describing the answer |
| `$3` | string | Optional system prompt |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_JSON_RETRIES`** | number | Attempts before giving up |

**📤 Output on stdout**

- Compact JSON answer

**🚦 Exit codes**

- `0`: A valid JSON answer was produced
- `1`: Missing arguments, an invalid schema, or no valid answer after every attempt


---

### `dybatpho::ai_stream`

Ask a question and print the answer as it is generated.
Falls back to a normal buffered call on backends without a token stream.

**🧪 Example**

```bash
dybatpho::ai_stream "Explain this stack trace" | tee /tmp/answer.txt

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt |
| `$2` | string | Optional system prompt |

**📝 Notes**

- Usage counters are not updated for streamed Anthropic calls because the totals arrive in a trailing event this helper does not buffer

**📤 Output on stdout**

- Assistant answer, written incrementally

**🚦 Exit codes**

- `0`: The stream completed
- `1`: Missing arguments or a provider error


---

### `__ai_stream_chunk`

Print one streamed delta without adding a line break.
The JSON backends both terminate their output with a newline, which would
turn a stream of fragments into a column of them, so exactly one trailing
newline is removed while any the model actually produced are kept.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | One event payload |
| `$2` | string | Filter selecting the text fragment |

**📤 Output on stdout**

- The fragment, with no added newline


---

### `dybatpho::ai_tool_register`

Register a shell function the model may call during `ai_run`.

**🧪 Example**

```bash
function service_status { systemctl is-active "$1"; }
dybatpho::ai_tool_register service_status "Check whether a systemd unit is active" \
  '{"type":"object","properties":{"unit":{"type":"string"}},"required":["unit"]}' \
  service_status

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tool name the model will use |
| `$2` | string | Description telling the model when to call it |
| `$3` | string | JSON schema for the tool arguments |
| `$4` | string | Shell function that implements the tool |

**🧩 Variable sets**

- DYBATPHO_AI_TOOL_HANDLER

**🚦 Exit codes**

- `0`: The tool is registered
- `1`: Missing arguments, an invalid schema, or an undefined handler


---

### `dybatpho::ai_tool_list`

Print the names of registered tools, one per line.

**🧪 Example**

```bash
dybatpho::ai_tool_list

```

_Function has no arguments._

**📤 Output on stdout**

- Tool names in alphabetical order

**🚦 Exit codes**

- `0`: The list was printed, empty when nothing is registered


---

### `dybatpho::ai_tool_clear`

Unregister every tool.

_Function has no arguments._

**🧩 Variable sets**

- DYBATPHO_AI_TOOL_HANDLER

**🚦 Exit codes**

- `0`: The registry is empty


---

### `__ai_tools_json`

Render the tool registry as a provider-neutral tools array.

**📤 Output on stdout**

- JSON array, `[]` when nothing is registered


---

### `__ai_tool_invoke`

Run one registered tool and print what it wrote.
A failing handler is not fatal: its output is returned to the model as an
error result so the model can adapt, which is the documented contract for
tool results.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Tool name |
| `$2` | string | Tool arguments as JSON |

**📤 Output on stdout**

- Tool output


---

### `dybatpho::ai_run`

Answer a prompt, letting the model call registered tools first.
The loop sends the prompt, runs whatever tools the model asks for, feeds the
results back, and repeats until the model answers in text or the step limit
is reached.

**🧪 Example**

```bash
dybatpho::ai_tool_register disk_free "Report free disk space" \
  '{"type":"object","properties":{}}' disk_free
dybatpho::ai_run "Do we need to clean up the build cache?"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Prompt |
| `$2` | string | Optional system prompt |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_AI_MAX_STEPS`** | number | Maximum tool rounds before giving up |

**📝 Notes**

- Only the `anthropic` and `openai` backends carry tool calls; on the others this behaves like `dybatpho::ai_ask`

**📤 Output on stdout**

- Final assistant answer

**🚦 Exit codes**

- `0`: The model produced a final answer
- `1`: Missing arguments, no tools registered, a provider error, or the step limit was hit


---

### `dybatpho::ai_tokens_estimate`

Estimate how many tokens a piece of text costs.
The estimate is four characters per token, which is close enough to size a
prompt or decide whether to truncate before a call; it is not a billing figure.

**🧪 Example**

```bash
if (($(dybatpho::ai_tokens_estimate "$(cat build.log)") > 100000)); then
  dybatpho::warn "Log is too large, summarizing in chunks"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to measure, stdin is read when omitted |

**📝 Notes**

- Use the provider's own token counting endpoint when an exact number matters

**📤 Output on stdout**

- Estimated token count

**🚦 Exit codes**

- `0`: An estimate was printed


---

### `dybatpho::ai_usage`

Print the token usage recorded so far.

**🧪 Example**

```bash
dybatpho::ai_ask "Hello"
dybatpho::ai_usage
dybatpho::ai_usage total

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Scope, `last` (default) or `total` |

**📤 Output on stdout**

- `calls=N input=N output=N`, plus the model and stop reason for `last`

**🚦 Exit codes**

- `0`: The counters were printed
- `1`: Stop the script when the scope is unknown


---

### `dybatpho::ai_usage_field`

Read one usage counter as a bare value.

**🧪 Example**

```bash
if (($(dybatpho::ai_usage_field total_output) > 50000)); then
  dybatpho::warn "This run is getting expensive"
fi

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Field name: `calls`, `total_input`, `total_output`, `last_input`, `last_output`, `last_model`, or `last_stop_reason` |

**📤 Output on stdout**

- The counter value

**🚦 Exit codes**

- `0`: The value was printed
- `1`: Missing argument or an unknown field


---

### `dybatpho::ai_usage_reset`

Reset every usage counter and the call budget consumption.

_Function has no arguments._

**🚦 Exit codes**

- `0`: The counters are back to zero


---

### `dybatpho::ai_budget`

Cap how many model calls the rest of the script may make.

**🧪 Example**

```bash
dybatpho::ai_budget 5 # a runaway loop stops instead of billing forever

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | number | Maximum number of calls; `0` removes the cap |

**🧩 Variable sets**

- DYBATPHO_AI_MAX_CALLS

**🚦 Exit codes**

- `0`: The budget is set
- `1`: Missing or non-numeric argument


---

### `dybatpho::ai_redact`

Redact secrets and common personal identifiers in text.
Registered secrets are masked first, then email addresses, IPv4 addresses,
and long digit runs are replaced with placeholders.

**🧪 Example**

```bash
dybatpho::ai_ask "Explain this error: $(dybatpho::ai_redact "${line}")"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Text to redact, stdin is read when omitted |

**📤 Output on stdout**

- Redacted text

**🚦 Exit codes**

- `0`: The text was printed

**🔗 See also**

- [dybatpho::secret_register](#dybatphosecret_register)

