#!/usr/bin/env bash
# @file ai.sh
# @brief Utilities for calling large language models from shell scripts
# @description
#   This module turns an LLM into an ordinary shell dependency: one function
#   call in, text on stdout, a non-zero exit code when something fails. It
#   speaks four backends behind a single API:
#
#   - **anthropic** – Claude Messages API (`/v1/messages`)
#   - **openai** – any OpenAI-compatible `/v1/chat/completions` endpoint
#     (OpenAI, Groq, OpenRouter, vLLM, LM Studio, ...)
#   - **ollama** – a local Ollama daemon, no API key required
#   - **cli** – an already installed command line client (`claude`, `llm`,
#     `ollama`), for machines where the key never leaves the tool that owns it
#
#   On top of the transport it provides the things a script actually needs
#   around a model call: multi-turn conversations stored in a file, structured
#   JSON output validated against a schema, token streaming, a tool-use loop
#   that runs shell functions, response caching, redaction of secrets before
#   anything is sent, and a call budget that stops a runaway loop.
#
# @usage
#   ### When to use this module
#
#   Use `ai.sh` when you want to:
#
#   - summarize a log, a diff, or a test failure inside a pipeline
#   - classify or extract fields from unstructured text into JSON
#   - draft a release note or a commit message from real repository data
#   - give a maintenance script a natural language front end
#
#   ### Common patterns
#
#   #### Ask a one-shot question
#
#   ```bash
#   export ANTHROPIC_API_KEY="sk-ant-..."
#   dybatpho::ai_ask "Summarize this log in three bullets"
#   dybatpho::ai_ask "What broke?" "You are a terse SRE assistant"
#   ```
#
#   #### Get machine-readable output
#
#   ```bash
#   schema='{"type":"object","properties":{"severity":{"type":"string"}},
#            "required":["severity"],"additionalProperties":false}'
#   dybatpho::ai_json "Classify this alert: ${alert}" "${schema}" > /tmp/out.json
#   severity=$(dybatpho::json_query /tmp/out.json '.severity')
#   ```
#
#   #### Hold a conversation
#
#   ```bash
#   local CHAT
#   dybatpho::ai_conversation_new CHAT "You are a Bash tutor"
#   dybatpho::ai_chat "${CHAT}" "How do I trap SIGINT?"
#   dybatpho::ai_chat "${CHAT}" "And clean up a temp file too?"
#   ```
#
#   #### Let the model call your functions
#
#   ```bash
#   function disk_free { df -h / | tail -n 1; }
#   dybatpho::ai_tool_register disk_free "Report free disk space" \
#     '{"type":"object","properties":{}}' disk_free
#   dybatpho::ai_run "Are we about to run out of disk?"
#   ```
#
# @see
#   - `example/ai_ops.sh`
# @tip Set `DYBATPHO_AI_PROVIDER` to pin a backend; the default `auto` picks the first one whose credentials or command are present
# @tip Every prompt is passed through `dybatpho::secret_mask` first, so values registered with `dybatpho::secret_register` never reach the provider
# @note Payloads and responses go through the `json` module, so this needs `yq` or `jq` like the rest of the library; building them by string concatenation is too escaping-sensitive to be safe
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_AI_PROVIDER string Backend to use: `auto` (default), `anthropic`, `openai`, `ollama`, or `cli`
# @env DYBATPHO_AI_MODEL string Model identifier; defaults to the provider's recommended model
# @env DYBATPHO_AI_BASE_URL string Override the provider base URL, for proxies and compatible gateways
# @env DYBATPHO_AI_API_KEY string API key; `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` are used as fallbacks
# @env DYBATPHO_AI_MAX_TOKENS number Output token ceiling for one response (default `16000`)
# @env DYBATPHO_AI_EFFORT string Reasoning effort for Anthropic models: `low`, `medium`, `high`, `xhigh`, or `max`
# @env DYBATPHO_AI_TEMPERATURE string Sampling temperature; only sent to the `openai` and `ollama` backends
# @env DYBATPHO_AI_SYSTEM string Default system prompt used when a call does not pass one
# @env DYBATPHO_AI_TIMEOUT number Total curl timeout in seconds for one model call (default `300`)
# @env DYBATPHO_AI_CACHE bool Cache responses on disk keyed by request content (default `false`)
# @env DYBATPHO_AI_CACHE_DIR string Cache directory (default `${XDG_CACHE_HOME:-${HOME}/.cache}/dybatpho/ai`)
# @env DYBATPHO_AI_CACHE_TTL number Seconds a cached response stays valid (default `86400`)
# @env DYBATPHO_AI_REDACT bool Mask registered secrets in every prompt before sending (default `true`)
# @env DYBATPHO_AI_MAX_CALLS number Stop after this many model calls in one script; `0` means no limit
# @env DYBATPHO_AI_MAX_STEPS number Maximum tool-use rounds in `dybatpho::ai_run` (default `10`)
# @env DYBATPHO_AI_JSON_RETRIES number Attempts `dybatpho::ai_json` makes before failing (default `2`)
# @env DYBATPHO_AI_CLI string Command used by the `cli` backend: `claude`, `llm`, or `ollama`
# @env DYBATPHO_AI_ANTHROPIC_VERSION string Value of the `anthropic-version` header (default `2023-06-01`)
DYBATPHO_AI_PROVIDER=${DYBATPHO_AI_PROVIDER:-auto}
DYBATPHO_AI_MODEL=${DYBATPHO_AI_MODEL:-}
DYBATPHO_AI_BASE_URL=${DYBATPHO_AI_BASE_URL:-}
DYBATPHO_AI_API_KEY=${DYBATPHO_AI_API_KEY:-}
DYBATPHO_AI_MAX_TOKENS=${DYBATPHO_AI_MAX_TOKENS:-16000}
DYBATPHO_AI_EFFORT=${DYBATPHO_AI_EFFORT:-}
DYBATPHO_AI_TEMPERATURE=${DYBATPHO_AI_TEMPERATURE:-}
DYBATPHO_AI_SYSTEM=${DYBATPHO_AI_SYSTEM:-}
DYBATPHO_AI_TIMEOUT=${DYBATPHO_AI_TIMEOUT:-300}
DYBATPHO_AI_CACHE=${DYBATPHO_AI_CACHE:-false}
DYBATPHO_AI_CACHE_DIR=${DYBATPHO_AI_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/dybatpho/ai}
DYBATPHO_AI_CACHE_TTL=${DYBATPHO_AI_CACHE_TTL:-86400}
DYBATPHO_AI_REDACT=${DYBATPHO_AI_REDACT:-true}
DYBATPHO_AI_MAX_CALLS=${DYBATPHO_AI_MAX_CALLS:-0}
DYBATPHO_AI_MAX_STEPS=${DYBATPHO_AI_MAX_STEPS:-10}
DYBATPHO_AI_JSON_RETRIES=${DYBATPHO_AI_JSON_RETRIES:-2}
DYBATPHO_AI_CLI=${DYBATPHO_AI_CLI:-}
DYBATPHO_AI_ANTHROPIC_VERSION=${DYBATPHO_AI_ANTHROPIC_VERSION:-2023-06-01}

# Default models per backend. `claude-opus-5` is the current Anthropic
# flagship; the other two are the conventional defaults for their ecosystems.
DYBATPHO_AI_ANTHROPIC_MODEL=${DYBATPHO_AI_ANTHROPIC_MODEL:-claude-opus-5}
DYBATPHO_AI_OPENAI_MODEL=${DYBATPHO_AI_OPENAI_MODEL:-gpt-4o-mini}
DYBATPHO_AI_OLLAMA_MODEL=${DYBATPHO_AI_OLLAMA_MODEL:-llama3.2}

# Counters live in a file rather than in shell variables because model calls
# happen inside command substitutions, and a subshell cannot write back to its
# parent. `$$` stays the top-level shell's pid inside a subshell, so every part
# of one script run shares the same file.
#
# @env DYBATPHO_AI_STATE_FILE string File the call and token counters are kept in
DYBATPHO_AI_STATE_FILE=${DYBATPHO_AI_STATE_FILE:-${TMPDIR:-/tmp}/dybatpho_ai_state_$$}

# Tool registry used by `dybatpho::ai_run`, keyed by tool name.
declare -gA DYBATPHO_AI_TOOL_DESCRIPTION=()
declare -gA DYBATPHO_AI_TOOL_SCHEMA=()
declare -gA DYBATPHO_AI_TOOL_HANDLER=()

#######################################
# @description Fail loudly when no JSON backend is installed.
# @noargs
# @exitcode 0 `yq` or `jq` is available
# @exitcode 127 Stop the script because neither is installed
# @see dybatpho::json_object
#######################################
function __ai_require_json {
  __dybatpho_json_cmd > /dev/null
}

#######################################
# @description Mask registered secrets in text before it leaves the machine.
# @arg $1 string Text to redact
# @env DYBATPHO_AI_REDACT bool Return the text unchanged when not true
# @stdout Redacted text
# @see dybatpho::secret_mask
#######################################
function __ai_redact {
  local text
  dybatpho::expect_args text -- "$@"
  if dybatpho::is true "${DYBATPHO_AI_REDACT}"; then
    dybatpho::secret_mask "${text}"
  else
    printf '%s\n' "${text}"
  fi
}

#######################################
# @description Arrange for the counter file to be removed when the script ends.
# Sourcing a module must not touch the host script's traps, so this runs on
# first use rather than at load time. A command substitution gets its own
# process, and a handler registered there would delete the counters the moment
# that subshell returned, so only the top-level shell registers one.
# @noargs
# @exitcode 0 A handler is registered, or this is not the shell that should
#   register one
# @see dybatpho::cleanup_file_on_exit
#######################################
function __ai_state_cleanup_once {
  [[ "${BASHPID}" == "$$" ]] || return 0
  [[ -n "${__dybatpho_ai_state_cleanup-}" ]] && return 0
  __dybatpho_ai_state_cleanup=1
  dybatpho::cleanup_file_on_exit "${DYBATPHO_AI_STATE_FILE}"
}

#######################################
# @description Print the counter document, creating it on first use.
# @env DYBATPHO_AI_STATE_FILE string File the counters are kept in
# @stdout Counter JSON
#######################################
function __ai_state_read {
  if [[ ! -f "${DYBATPHO_AI_STATE_FILE}" ]]; then
    printf '%s\n' '{"calls":0,"total_input":0,"total_output":0,"last_input":0,"last_output":0,"last_model":"","last_stop_reason":""}' \
      > "${DYBATPHO_AI_STATE_FILE}"
  fi
  cat "${DYBATPHO_AI_STATE_FILE}"
}

#######################################
# @description Replace the counter document.
# @arg $1 string Counter JSON
#######################################
function __ai_state_write {
  local document
  dybatpho::expect_args document -- "$@"
  printf '%s\n' "${document}" > "${DYBATPHO_AI_STATE_FILE}"
}

#######################################
# @description Stop the script when the call budget is already used up.
# This is deliberately separate from counting: the count happens deep inside a
# command substitution, where an `exit` would only leave that subshell, so the
# refusal has to be raised by the public function the caller invoked.
# @env DYBATPHO_AI_MAX_CALLS number Budget; `0` disables the check
# @arg $1 number Calls this operation is about to make, default `1`
# @exitcode 0 There is budget left
# @exitcode 1 Stop the script when the budget is exhausted
#######################################
function __ai_budget_check {
  local wanted="${1:-1}"
  # Every public entry point passes through here, which makes it the place to
  # arrange cleanup of the counter file in the caller's own shell.
  __ai_state_cleanup_once
  ((DYBATPHO_AI_MAX_CALLS > 0)) || return 0
  local calls
  calls=$(dybatpho::json_get "$(__ai_state_read)" '.calls')
  if ((calls + wanted > DYBATPHO_AI_MAX_CALLS)); then
    dybatpho::die "ai: call budget of ${DYBATPHO_AI_MAX_CALLS} calls is exhausted"
  fi
}

#######################################
# @description Count one model call in the shared counter file.
# @exitcode 0 The counter was incremented
#######################################
function __ai_count_call {
  __ai_state_write "$(dybatpho::json_eval "$(__ai_state_read)" '.calls += 1')"
}

#######################################
# @description Record the token usage a provider reported for one call.
# @arg $1 number Input tokens
# @arg $2 number Output tokens
# @arg $3 string Model that answered
# @arg $4 string Stop reason
#######################################
function __ai_record_usage {
  local input_tokens="${1:-0}" output_tokens="${2:-0}" model="${3:-}" stop_reason="${4:-}"
  [[ "${input_tokens}" =~ ^[0-9]+$ ]] || input_tokens=0
  [[ "${output_tokens}" =~ ^[0-9]+$ ]] || output_tokens=0
  local last
  last=$(dybatpho::json_object \
    last_input:json "${input_tokens}" \
    last_output:json "${output_tokens}" \
    last_model "${model}" \
    last_stop_reason "${stop_reason}")
  __ai_state_write "$(dybatpho::json_eval "$(__ai_state_read)" \
    ". + ${last} | .total_input += ${input_tokens} | .total_output += ${output_tokens}")"
}

#######################################
# @description Return success when an Ollama daemon answers on the base URL.
# @noargs
# @exitcode 0 Ollama is reachable
# @exitcode 1 Ollama is not reachable
#######################################
function __ai_ollama_alive {
  hash curl > /dev/null 2>&1 || return 1
  local base="${DYBATPHO_AI_BASE_URL:-http://localhost:11434}"
  curl --silent --fail --max-time 2 "${base}/api/tags" > /dev/null 2>&1
}

#######################################
# @description Resolve which backend a call will use.
# Detection order for `auto`: an Anthropic key, an OpenAI key, a live local
# Ollama daemon, then any supported command line client.
# @example
#   case "$(dybatpho::ai_provider)" in
#     anthropic) dybatpho::info "Using Claude" ;;
#     ollama) dybatpho::info "Running locally" ;;
#   esac
#
# @noargs
# @env DYBATPHO_AI_PROVIDER string Pin the backend instead of detecting one
# @stdout One of `anthropic`, `openai`, `ollama`, or `cli`
# @exitcode 0 A backend was resolved
# @exitcode 1 Stop the script when the pinned name is unknown, or nothing is configured
#######################################
function dybatpho::ai_provider {
  case "${DYBATPHO_AI_PROVIDER}" in
    anthropic | openai | ollama | cli)
      printf '%s\n' "${DYBATPHO_AI_PROVIDER}"
      return 0
      ;;
    auto) ;;
    *)
      dybatpho::die "dybatpho::ai_provider: Unknown provider '${DYBATPHO_AI_PROVIDER}', expected auto, anthropic, openai, ollama or cli"
      ;;
  esac

  if dybatpho::is set "${DYBATPHO_AI_API_KEY}"; then
    printf 'anthropic\n'
  elif dybatpho::is set "${ANTHROPIC_API_KEY-}"; then
    printf 'anthropic\n'
  elif dybatpho::is set "${OPENAI_API_KEY-}"; then
    printf 'openai\n'
  elif __ai_ollama_alive; then
    printf 'ollama\n'
  elif dybatpho::coalesce_cmd claude llm ollama > /dev/null 2>&1; then
    printf 'cli\n'
  else
    dybatpho::die "dybatpho::ai_provider: No AI backend configured. Set ANTHROPIC_API_KEY, OPENAI_API_KEY, run ollama, or install a supported CLI"
  fi
}

#######################################
# @description Resolve the model identifier for the active backend.
# @example
#   dybatpho::info "Asking $(dybatpho::ai_model)"
#
# @arg $1 string Optional backend name; detected when omitted
# @env DYBATPHO_AI_MODEL string Wins over every per-backend default
# @stdout Model identifier
# @exitcode 0 A model name was resolved
#######################################
function dybatpho::ai_model {
  if dybatpho::is set "${DYBATPHO_AI_MODEL}"; then
    printf '%s\n' "${DYBATPHO_AI_MODEL}"
    return 0
  fi
  local provider="${1:-}"
  dybatpho::is empty "${provider}" && provider=$(dybatpho::ai_provider)
  case "${provider}" in
    anthropic | cli) printf '%s\n' "${DYBATPHO_AI_ANTHROPIC_MODEL}" ;;
    openai) printf '%s\n' "${DYBATPHO_AI_OPENAI_MODEL}" ;;
    ollama) printf '%s\n' "${DYBATPHO_AI_OLLAMA_MODEL}" ;;
    *) dybatpho::die "dybatpho::ai_model: Unknown provider '${provider}'" ;;
  esac
}

#######################################
# @description Resolve the API key for an HTTP backend.
# @arg $1 string Backend name
# @stdout API key, empty for `ollama`
# @exitcode 0 A key was found, or the backend needs none
# @exitcode 1 Stop the script when a required key is missing
#######################################
function __ai_api_key {
  local provider
  dybatpho::expect_args provider -- "$@"
  if dybatpho::is set "${DYBATPHO_AI_API_KEY}"; then
    printf '%s\n' "${DYBATPHO_AI_API_KEY}"
    return 0
  fi
  case "${provider}" in
    anthropic)
      dybatpho::is set "${ANTHROPIC_API_KEY-}" \
        || dybatpho::die "ai: ANTHROPIC_API_KEY or DYBATPHO_AI_API_KEY must be set for the anthropic backend"
      printf '%s\n' "${ANTHROPIC_API_KEY}"
      ;;
    openai)
      dybatpho::is set "${OPENAI_API_KEY-}" \
        || dybatpho::die "ai: OPENAI_API_KEY or DYBATPHO_AI_API_KEY must be set for the openai backend"
      printf '%s\n' "${OPENAI_API_KEY}"
      ;;
    ollama) printf '\n' ;;
    *) dybatpho::die "ai: Backend '${provider}' has no API key concept" ;;
  esac
}

#######################################
# @description Resolve the base URL of an HTTP backend.
# @arg $1 string Backend name
# @stdout Base URL without a trailing slash
#######################################
function __ai_base_url {
  local provider
  dybatpho::expect_args provider -- "$@"
  if dybatpho::is set "${DYBATPHO_AI_BASE_URL}"; then
    printf '%s\n' "${DYBATPHO_AI_BASE_URL%/}"
    return 0
  fi
  case "${provider}" in
    anthropic) printf 'https://api.anthropic.com\n' ;;
    openai) printf 'https://api.openai.com/v1\n' ;;
    ollama) printf 'http://localhost:11434\n' ;;
    *) dybatpho::die "ai: Backend '${provider}' has no base URL" ;;
  esac
}

#######################################
# @description Report whether the module can run, without making a request.
# Checks the JSON backend, the transport command, and the credentials of the
# active backend.
# @example
#   dybatpho::ai_check || dybatpho::die "Configure an AI backend first"
#
# @noargs
# @stdout Nothing on success; a diagnostic on stderr otherwise
# @exitcode 0 The active backend is usable
# @exitcode 1 Stop the script when a dependency or credential is missing
#######################################
function dybatpho::ai_check {
  __ai_require_json
  local provider
  provider=$(dybatpho::ai_provider)
  case "${provider}" in
    anthropic | openai | ollama)
      hash curl > /dev/null 2>&1 || dybatpho::die "ai: curl is required by the ${provider} backend" 127
      __ai_api_key "${provider}" > /dev/null
      ;;
    cli)
      __ai_cli_command > /dev/null
      ;;
  esac
  dybatpho::debug "ai: provider=${provider} model=$(dybatpho::ai_model "${provider}")"
}

#######################################
# @description Resolve the command used by the `cli` backend.
# @env DYBATPHO_AI_CLI string Pin a command instead of probing
# @stdout `claude`, `llm`, or `ollama`
# @exitcode 0 A supported client exists
# @exitcode 127 Stop the script when no client is installed
#######################################
function __ai_cli_command {
  if dybatpho::is set "${DYBATPHO_AI_CLI}"; then
    hash "${DYBATPHO_AI_CLI}" > /dev/null 2>&1 \
      || dybatpho::die "ai: DYBATPHO_AI_CLI is '${DYBATPHO_AI_CLI}' but that command is not installed" 127
    printf '%s\n' "${DYBATPHO_AI_CLI}"
    return 0
  fi
  dybatpho::coalesce_cmd claude llm ollama \
    || dybatpho::die "ai: no supported CLI found, install claude, llm or ollama" 127
}

#######################################
# @description Build a conversation document from a system prompt and turns.
# The document is the provider-neutral shape the payload builders consume.
# @arg $1 string System prompt, may be empty
# @arg $@ string Alternating role and content pairs
# @stdout Conversation JSON
#######################################
function __ai_conversation_build {
  local system
  dybatpho::expect_args system -- "$@"
  shift
  local messages='[]' turn
  while (($# >= 2)); do
    turn=$(dybatpho::json_object role "$1" content "$2")
    shift 2
    messages=$(dybatpho::json_eval "${messages}" ". + [${turn}]")
  done
  dybatpho::json_object system "${system}" messages:json "${messages}"
}

#######################################
# @description Render a conversation document into an Anthropic request body.
# @arg $1 string Conversation JSON
# @arg $2 string Tools array JSON, or `[]`
# @arg $3 string Output schema JSON, or empty for free-form text
# @stdout Request payload
#######################################
function __ai_payload_anthropic {
  local conversation tools schema
  dybatpho::expect_args conversation tools -- "$@"
  schema="${3:-}"

  local system messages
  system=$(dybatpho::json_get "${conversation}" '.system')
  messages=$(dybatpho::json_eval "${conversation}" '.messages')

  local -a fields=(
    model "$(dybatpho::ai_model anthropic)"
    max_tokens:json "${DYBATPHO_AI_MAX_TOKENS}"
    messages:json "${messages}"
  )
  dybatpho::is set "${system}" && fields+=(system "${system}")
  [[ "${tools}" != "[]" ]] && fields+=(tools:json "${tools}")

  # `effort` and the output contract share one object, so they are collected
  # before the payload is built rather than patched in afterwards.
  local -a output_config=()
  dybatpho::is set "${DYBATPHO_AI_EFFORT}" && output_config+=(effort "${DYBATPHO_AI_EFFORT}")
  if dybatpho::is set "${schema}"; then
    output_config+=(format:json "$(dybatpho::json_object type json_schema schema:json "${schema}")")
  fi
  ((${#output_config[@]} > 0)) \
    && fields+=(output_config:json "$(dybatpho::json_object "${output_config[@]}")")

  dybatpho::json_object "${fields[@]}"
}

#######################################
# @description Render a conversation document into an OpenAI-compatible body.
# @arg $1 string Conversation JSON
# @arg $2 string Tools array JSON, or `[]`
# @arg $3 string Output schema JSON, or empty for free-form text
# @stdout Request payload
#######################################
function __ai_payload_openai {
  local conversation tools schema
  dybatpho::expect_args conversation tools -- "$@"
  schema="${3:-}"

  local system messages
  system=$(dybatpho::json_get "${conversation}" '.system')
  messages=$(__ai_messages_with_system "${conversation}")

  local -a fields=(
    model "$(dybatpho::ai_model openai)"
    max_tokens:json "${DYBATPHO_AI_MAX_TOKENS}"
    messages:json "${messages}"
  )
  dybatpho::is set "${DYBATPHO_AI_TEMPERATURE}" \
    && fields+=(temperature:json "${DYBATPHO_AI_TEMPERATURE}")
  if [[ "${tools}" != "[]" ]]; then
    fields+=(tools:json "$(__ai_tools_as_functions "${tools}")")
  fi
  if dybatpho::is set "${schema}"; then
    local contract
    contract=$(dybatpho::json_object name dybatpho_output strict:json true schema:json "${schema}")
    fields+=(response_format:json "$(dybatpho::json_object type json_schema json_schema:json "${contract}")")
  fi

  dybatpho::json_object "${fields[@]}"
}

#######################################
# @description Prepend the system prompt as a message, the way the
# OpenAI-compatible and Ollama APIs expect it.
# @arg $1 string Conversation JSON
# @stdout Message array JSON
#######################################
function __ai_messages_with_system {
  local conversation
  dybatpho::expect_args conversation -- "$@"
  local system messages
  system=$(dybatpho::json_get "${conversation}" '.system')
  messages=$(dybatpho::json_eval "${conversation}" '.messages')
  if dybatpho::is set "${system}"; then
    messages=$(dybatpho::json_eval "${messages}" \
      "[$(dybatpho::json_object role system content "${system}")] + .")
  fi
  printf '%s\n' "${messages}"
}

#######################################
# @description Convert the neutral tool list into the OpenAI function shape,
# which both OpenAI-compatible endpoints and Ollama accept.
# @arg $1 string Tools array JSON
# @stdout Converted tools array JSON
#######################################
function __ai_tools_as_functions {
  local tools
  dybatpho::expect_args tools -- "$@"
  dybatpho::json_eval "${tools}" \
    'map({"type": "function",
          "function": {"name": .name,
                       "description": .description,
                       "parameters": .input_schema}})'
}

#######################################
# @description Render a conversation document into an Ollama chat body.
# @arg $1 string Conversation JSON
# @arg $2 string Tools array JSON, or `[]`
# @arg $3 string Output schema JSON, or empty for free-form text
# @stdout Request payload
#######################################
function __ai_payload_ollama {
  local conversation tools schema
  dybatpho::expect_args conversation tools -- "$@"
  schema="${3:-}"

  local -a fields=(
    model "$(dybatpho::ai_model ollama)"
    stream:json false
    messages:json "$(__ai_messages_with_system "${conversation}")"
  )
  if dybatpho::is set "${DYBATPHO_AI_TEMPERATURE}"; then
    fields+=(options:json "$(dybatpho::json_object temperature:json "${DYBATPHO_AI_TEMPERATURE}")")
  fi
  [[ "${tools}" != "[]" ]] && fields+=(tools:json "$(__ai_tools_as_functions "${tools}")")
  dybatpho::is set "${schema}" && fields+=(format:json "${schema}")

  dybatpho::json_object "${fields[@]}"
}

#######################################
# @description Compute the cache key of a request.
# @arg $1 string Backend name
# @arg $2 string Request payload
# @stdout Hexadecimal key
#######################################
function __ai_cache_key {
  local provider payload
  dybatpho::expect_args provider payload -- "$@"
  local hasher
  hasher=$(dybatpho::coalesce_cmd sha256sum shasum cksum)
  printf '%s\n%s\n' "${provider}" "${payload}" | "${hasher}" | cut -d' ' -f1
}

#######################################
# @description Print a cached response when one is present and still fresh.
# @arg $1 string Cache key
# @env DYBATPHO_AI_CACHE_TTL number Maximum age in seconds
# @stdout Cached response body
# @exitcode 0 A fresh entry was printed
# @exitcode 1 No usable entry
#######################################
function __ai_cache_read {
  local key
  dybatpho::expect_args key -- "$@"
  dybatpho::is true "${DYBATPHO_AI_CACHE}" || return 1
  local entry="${DYBATPHO_AI_CACHE_DIR}/${key}.json"
  dybatpho::is file "${entry}" || return 1
  local now modified age
  now=$(date +%s)
  modified=$(date -r "${entry}" +%s 2> /dev/null) || return 1
  age=$((now - modified))
  ((age <= DYBATPHO_AI_CACHE_TTL)) || return 1
  dybatpho::debug "ai: cache hit ${key}"
  cat "${entry}"
}

#######################################
# @description Store a response body in the cache.
# @arg $1 string Cache key
# @arg $2 string Response body
# @exitcode 0 Stored, or caching is disabled
#######################################
function __ai_cache_write {
  local key body
  dybatpho::expect_args key body -- "$@"
  dybatpho::is true "${DYBATPHO_AI_CACHE}" || return 0
  mkdir -p "${DYBATPHO_AI_CACHE_DIR}"
  printf '%s\n' "${body}" > "${DYBATPHO_AI_CACHE_DIR}/${key}.json"
}

#######################################
# @description Forget every cached response.
# @example
#   dybatpho::ai_cache_clear
#
# @noargs
# @env DYBATPHO_AI_CACHE_DIR string Directory that is emptied
# @exitcode 0 The cache directory is empty or absent
#######################################
function dybatpho::ai_cache_clear {
  if dybatpho::is dir "${DYBATPHO_AI_CACHE_DIR}"; then
    dybatpho::debug "ai: clearing cache in ${DYBATPHO_AI_CACHE_DIR}"
    find "${DYBATPHO_AI_CACHE_DIR}" -maxdepth 1 -name '*.json' -type f -delete
  fi
}

#######################################
# @description Produce a provider-shaped placeholder response for `DRY_RUN`.
# Keeping the shape lets the rest of the pipeline run unchanged, so an example
# or a rehearsal exercises the real extraction and accounting code.
# @arg $1 string Backend name
# @arg $2 string Request payload, inspected for a structured output contract
# @stdout Response body in the provider's own shape
#######################################
function __ai_dry_run_body {
  local provider payload
  dybatpho::expect_args provider payload -- "$@"
  local text="[dry run] no request was sent"
  # A caller that asked for structured output still needs parseable output, so
  # the placeholder becomes an empty document rather than a sentence.
  local has_contract
  has_contract=$(dybatpho::json_get "${payload}" \
    '[.output_config.format?, .response_format?, .format?] | map(select(. != null)) | length')
  ((has_contract > 0)) && text="{}"

  local model
  model=$(dybatpho::ai_model "${provider}")
  case "${provider}" in
    anthropic)
      dybatpho::json_object \
        model "${model}" \
        stop_reason end_turn \
        content:json "[$(dybatpho::json_object type text text "${text}")]" \
        usage:json "$(dybatpho::json_object input_tokens:json 0 output_tokens:json 0)"
      ;;
    openai)
      local choice
      choice=$(dybatpho::json_object \
        finish_reason stop \
        message:json "$(dybatpho::json_object role assistant content "${text}")")
      dybatpho::json_object \
        model "${model}" \
        choices:json "[${choice}]" \
        usage:json "$(dybatpho::json_object prompt_tokens:json 0 completion_tokens:json 0)"
      ;;
    ollama)
      dybatpho::json_object \
        model "${model}" \
        done_reason stop \
        message:json "$(dybatpho::json_object role assistant content "${text}")" \
        prompt_eval_count:json 0 \
        eval_count:json 0
      ;;
  esac
}

#######################################
# @description Send one request to an HTTP backend and print the raw response.
# @arg $1 string Backend name
# @arg $2 string Request payload
# @stdout Raw JSON response body
# @exitcode 0 The provider answered with 2xx
# @exitcode 4 HTTP 4xx from the provider
# @exitcode 5 HTTP 5xx from the provider
# @see dybatpho::curl_do
#######################################
function __ai_http {
  local provider payload
  dybatpho::expect_args provider payload -- "$@"

  local cache_key body
  cache_key=$(__ai_cache_key "${provider}" "${payload}")
  if body=$(__ai_cache_read "${cache_key}"); then
    printf '%s\n' "${body}"
    return 0
  fi

  local url base
  base=$(__ai_base_url "${provider}")
  local -a headers=()
  case "${provider}" in
    anthropic)
      url="${base}/v1/messages"
      headers+=(--header "x-api-key: $(__ai_api_key anthropic)")
      headers+=(--header "anthropic-version: ${DYBATPHO_AI_ANTHROPIC_VERSION}")
      ;;
    openai)
      url="${base}/chat/completions"
      headers+=(--header "Authorization: Bearer $(__ai_api_key openai)")
      ;;
    ollama)
      url="${base}/api/chat"
      ;;
  esac

  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::info "🧪 DRY RUN: POST ${url} as ${provider}"
    __ai_dry_run_body "${provider}" "${payload}"
    return 0
  fi

  __ai_count_call
  local response_file
  dybatpho::create_temp response_file ".json" "ai_response"

  dybatpho::debug "ai: POST ${url}"
  dybatpho::curl_json "${url}" "${response_file}" \
    --request POST \
    --max-time "${DYBATPHO_AI_TIMEOUT}" \
    "${headers[@]}" \
    --data-binary "${payload}" || return $?

  body=$(cat "${response_file}")
  __ai_cache_write "${cache_key}" "${body}"
  printf '%s\n' "${body}"
}

#######################################
# @description Stop the script when a provider response carries an error object.
# @arg $1 string Backend name
# @arg $2 string Response body
# @exitcode 0 The response has no error field
# @exitcode 1 Stop the script and report the provider message
#######################################
function __ai_assert_no_error {
  local provider body
  dybatpho::expect_args provider body -- "$@"
  local present
  present=$(dybatpho::json_get "${body}" '[.error? | select(. != null)] | length') || return 0
  [[ "${present}" == "0" ]] && return 0

  # `.error` is an object for some providers and a bare string for others, so
  # the message is read optionally and the whole value is used as a fallback.
  local message
  message=$(dybatpho::json_get "${body}" '[.error.message?] | .[0] // ""')
  if dybatpho::is empty "${message}"; then
    message=$(dybatpho::json_get "${body}" '.error | @json')
    message="${message#\"}"
    message="${message%\"}"
  fi
  dybatpho::die "ai: ${provider} returned an error: ${message}"
}

#######################################
# @description Extract the assistant text from a provider response.
# @arg $1 string Backend name
# @arg $2 string Response body
# @stdout Assistant text, empty when the turn produced only tool calls
#######################################
function __ai_extract_text {
  local provider body
  dybatpho::expect_args provider body -- "$@"
  case "${provider}" in
    anthropic)
      dybatpho::json_get "${body}" \
        '[.content[]? | select(.type == "text") | .text] | join("")'
      ;;
    openai)
      dybatpho::json_get "${body}" '.choices[0].message.content // ""'
      ;;
    ollama)
      dybatpho::json_get "${body}" '.message.content // ""'
      ;;
  esac
}

#######################################
# @description Read token usage out of a provider response into the module state.
# @arg $1 string Backend name
# @arg $2 string Response body
# @see dybatpho::ai_usage
#######################################
function __ai_usage_from_response {
  local provider body
  dybatpho::expect_args provider body -- "$@"
  local input_tokens output_tokens model stop_reason
  model=$(dybatpho::json_get "${body}" '.model // ""')
  case "${provider}" in
    anthropic)
      input_tokens=$(dybatpho::json_get "${body}" '.usage.input_tokens // 0')
      output_tokens=$(dybatpho::json_get "${body}" '.usage.output_tokens // 0')
      stop_reason=$(dybatpho::json_get "${body}" '.stop_reason // ""')
      ;;
    openai)
      input_tokens=$(dybatpho::json_get "${body}" '.usage.prompt_tokens // 0')
      output_tokens=$(dybatpho::json_get "${body}" '.usage.completion_tokens // 0')
      stop_reason=$(dybatpho::json_get "${body}" '.choices[0].finish_reason // ""')
      ;;
    ollama)
      input_tokens=$(dybatpho::json_get "${body}" '.prompt_eval_count // 0')
      output_tokens=$(dybatpho::json_get "${body}" '.eval_count // 0')
      stop_reason=$(dybatpho::json_get "${body}" '.done_reason // ""')
      ;;
  esac
  __ai_record_usage "${input_tokens}" "${output_tokens}" "${model}" "${stop_reason}"
}

#######################################
# @description Complete a conversation through the `cli` backend.
# @arg $1 string Conversation JSON
# @stdout Assistant text
# @exitcode 0 The client answered
#######################################
function __ai_cli_complete {
  local conversation
  dybatpho::expect_args conversation -- "$@"
  local command system prompt model
  command=$(__ai_cli_command)
  model=$(dybatpho::ai_model cli)
  system=$(dybatpho::json_get "${conversation}" '.system // ""')
  # Command line clients are single-shot, so the history is flattened into one
  # prompt with explicit speaker labels rather than a structured message list.
  # The labels are built here rather than in a filter because the two JSON
  # backends spell their case conversion differently.
  local count index=0 role content
  count=$(dybatpho::json_get "${conversation}" '.messages | length')
  prompt=""
  while ((index < count)); do
    role=$(dybatpho::json_get "${conversation}" ".messages[${index}].role")
    content=$(dybatpho::json_get "${conversation}" ".messages[${index}].content")
    prompt+="$(dybatpho::upper "${role}"): ${content}"
    ((index + 1 < count)) && prompt+=$'\n\n'
    index=$((index + 1))
  done

  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::info "🧪 DRY RUN: ${command} would answer this prompt"
    printf '[dry run] no request was sent\n'
    return 0
  fi

  __ai_count_call
  dybatpho::debug "ai: running ${command}"
  case "${command}" in
    claude)
      if dybatpho::is set "${system}"; then
        printf '%s\n' "${prompt}" | claude --print --append-system-prompt "${system}"
      else
        printf '%s\n' "${prompt}" | claude --print
      fi
      ;;
    llm)
      if dybatpho::is set "${system}"; then
        printf '%s\n' "${prompt}" | llm --model "${model}" --system "${system}"
      else
        printf '%s\n' "${prompt}" | llm --model "${model}"
      fi
      ;;
    ollama)
      if dybatpho::is set "${system}"; then
        printf '%s\n\n%s\n' "${system}" "${prompt}" | ollama run "${model}"
      else
        printf '%s\n' "${prompt}" | ollama run "${model}"
      fi
      ;;
  esac
}

#######################################
# @description Complete a conversation and print the assistant text.
# This is the single funnel every public helper goes through.
# @arg $1 string Conversation JSON
# @arg $2 string Output schema JSON, or empty
# @stdout Assistant text
# @exitcode 0 The provider answered
#######################################
function __ai_complete {
  local conversation schema
  dybatpho::expect_args conversation -- "$@"
  schema="${2:-}"
  local provider
  provider=$(dybatpho::ai_provider)

  if [[ "${provider}" == "cli" ]]; then
    __ai_cli_complete "${conversation}"
    return 0
  fi

  local payload body
  payload=$("__ai_payload_${provider}" "${conversation}" '[]' "${schema}")
  body=$(__ai_http "${provider}" "${payload}")
  __ai_assert_no_error "${provider}" "${body}"
  __ai_usage_from_response "${provider}" "${body}"
  __ai_extract_text "${provider}" "${body}"
}

#######################################
# @description Ask the model a single question and print its answer.
# @example
#   dybatpho::ai_ask "Write a one line summary of this commit: ${subject}"
#   dybatpho::ai_ask "Is this config safe?" "You are a security reviewer"
#
# @arg $1 string Prompt
# @arg $2 string Optional system prompt; `DYBATPHO_AI_SYSTEM` is used when omitted
# @env DYBATPHO_AI_SYSTEM string Default system prompt
# @stdout Assistant answer
# @exitcode 0 The provider answered
# @exitcode 1 Missing arguments, exhausted budget, or a provider error
# @exitcode 4 HTTP 4xx from the provider
# @exitcode 5 HTTP 5xx from the provider
# @tip Pipe long inputs into the prompt with a command substitution rather than as a second argument
#######################################
function dybatpho::ai_ask {
  local prompt system
  dybatpho::expect_args prompt -- "$@"
  system="${2:-${DYBATPHO_AI_SYSTEM}}"
  __ai_budget_check
  prompt=$(__ai_redact "${prompt}")
  local conversation
  conversation=$(__ai_conversation_build "${system}" user "${prompt}")
  __ai_complete "${conversation}"
}

#######################################
# @description Create a conversation file and store its path in a variable.
# The file is registered for cleanup when the script exits.
# @example
#   local CHAT
#   dybatpho::ai_conversation_new CHAT "You are a release manager"
#
# @arg $1 string Variable name that receives the file path
# @arg $2 string Optional system prompt
# @set The named variable
# @exitcode 0 The conversation file exists
# @exitcode 1 Missing arguments
# @see dybatpho::create_temp
#######################################
function dybatpho::ai_conversation_new {
  local path_var system
  dybatpho::expect_args path_var -- "$@"
  system="${2:-${DYBATPHO_AI_SYSTEM}}"
  local file
  dybatpho::create_temp file ".json" "ai_chat"
  __ai_conversation_build "${system}" > "${file}"
  local -n conversation_path="${path_var}"
  # shellcheck disable=SC2034 # The caller reads the value through the nameref.
  conversation_path="${file}"
}

#######################################
# @description Append a turn to a conversation file.
# @example
#   dybatpho::ai_conversation_add "${CHAT}" assistant "Noted."
#
# @arg $1 string Conversation file path
# @arg $2 string Role, `user` or `assistant`
# @arg $3 string Message content
# @exitcode 0 The turn was appended
# @exitcode 1 Missing arguments, unknown role, or unreadable file
#######################################
function dybatpho::ai_conversation_add {
  local file role content
  dybatpho::expect_args file role content -- "$@"
  dybatpho::is file "${file}" || dybatpho::die "dybatpho::ai_conversation_add: '${file}' is not a conversation file"
  case "${role}" in
    user | assistant) ;;
    *) dybatpho::die "dybatpho::ai_conversation_add: Unknown role '${role}', expected user or assistant" ;;
  esac
  local turn updated
  turn=$(dybatpho::json_object role "${role}" content "${content}")
  updated=$(dybatpho::json_eval "$(cat "${file}")" ".messages += [${turn}]")
  printf '%s\n' "${updated}" > "${file}"
}

#######################################
# @description Print a conversation as readable transcript lines.
# @example
#   dybatpho::ai_conversation_show "${CHAT}"
#
# @arg $1 string Conversation file path
# @stdout One `role: content` block per turn
# @exitcode 0 The transcript was printed
# @exitcode 1 Missing argument or unreadable file
#######################################
function dybatpho::ai_conversation_show {
  local file
  dybatpho::expect_args file -- "$@"
  dybatpho::is file "${file}" || dybatpho::die "dybatpho::ai_conversation_show: '${file}' is not a conversation file"
  dybatpho::json_get "$(cat "${file}")" \
    '[(select((.system | length) > 0) | "system: " + .system),
      (.messages[] | .role + ": " + .content)] | join("\n")'
}

#######################################
# @description Send the next turn of a stored conversation and record the reply.
# Both the question and the answer are appended to the file, so the next call
# carries the full history.
# @example
#   dybatpho::ai_chat "${CHAT}" "What changed since v1.2.0?"
#   dybatpho::ai_chat "${CHAT}" "Now write it as release notes"
#
# @arg $1 string Conversation file path
# @arg $2 string User message
# @stdout Assistant answer
# @exitcode 0 The provider answered
# @exitcode 1 Missing arguments, unreadable file, or a provider error
# @see dybatpho::ai_conversation_new
#######################################
function dybatpho::ai_chat {
  local file prompt
  dybatpho::expect_args file prompt -- "$@"
  dybatpho::is file "${file}" || dybatpho::die "dybatpho::ai_chat: '${file}' is not a conversation file"
  __ai_budget_check
  prompt=$(__ai_redact "${prompt}")
  dybatpho::ai_conversation_add "${file}" user "${prompt}"
  local answer
  answer=$(__ai_complete "$(cat "${file}")")
  dybatpho::ai_conversation_add "${file}" assistant "${answer}"
  printf '%s\n' "${answer}"
}

#######################################
# @description Ask for an answer that matches a JSON schema, and validate it.
# Backends with native structured output are told about the schema; the rest
# are asked in the prompt. Either way the answer is parsed and re-checked
# locally, and the call is retried when the model returns something unusable.
# @example
#   schema='{"type":"object","properties":{"ok":{"type":"boolean"}},
#            "required":["ok"],"additionalProperties":false}'
#   dybatpho::ai_json "Did this deploy succeed? ${log}" "${schema}"
#
# @arg $1 string Prompt
# @arg $2 string JSON schema describing the answer
# @arg $3 string Optional system prompt
# @env DYBATPHO_AI_JSON_RETRIES number Attempts before giving up
# @stdout Compact JSON answer
# @exitcode 0 A valid JSON answer was produced
# @exitcode 1 Missing arguments, an invalid schema, or no valid answer after every attempt
# @tip Keep schemas flat; `additionalProperties: false` plus a `required` list gives the most reliable results
#######################################
function dybatpho::ai_json {
  local prompt schema system
  dybatpho::expect_args prompt schema -- "$@"
  system="${3:-${DYBATPHO_AI_SYSTEM}}"
  dybatpho::json_valid "${schema}" \
    || dybatpho::die "dybatpho::ai_json: The schema argument is not valid JSON"

  prompt=$(__ai_redact "${prompt}")
  local provider
  provider=$(dybatpho::ai_provider)

  local effective_prompt="${prompt}"
  local native_schema="${schema}"
  # The `cli` backend has no structured output switch, so the contract moves
  # into the prompt and is enforced by the local parse below.
  if [[ "${provider}" == "cli" ]]; then
    native_schema=""
    effective_prompt="${prompt}

Answer with a single JSON document and nothing else. No prose, no Markdown code fence. It must validate against this JSON schema:
${schema}"
  fi

  local attempt=1 answer candidate
  while ((attempt <= DYBATPHO_AI_JSON_RETRIES)); do
    __ai_budget_check
    local conversation
    conversation=$(__ai_conversation_build "${system}" user "${effective_prompt}")
    answer=$(__ai_complete "${conversation}" "${native_schema}")
    # Models sometimes wrap JSON in a fence even when told not to; strip it
    # before parsing rather than failing a well-formed answer on packaging.
    candidate=$(printf '%s\n' "${answer}" | sed -e 's/^[[:space:]]*```[a-zA-Z]*[[:space:]]*$//' -e 's/^[[:space:]]*```[[:space:]]*$//')
    if dybatpho::json_valid "${candidate}"; then
      dybatpho::json_eval "${candidate}" '.'
      return 0
    fi
    dybatpho::debug "ai: attempt ${attempt} did not return valid JSON"
    attempt=$((attempt + 1))
  done
  dybatpho::die "dybatpho::ai_json: No valid JSON after ${DYBATPHO_AI_JSON_RETRIES} attempts"
}

#######################################
# @description Ask a question and print the answer as it is generated.
# Falls back to a normal buffered call on backends without a token stream.
# @example
#   dybatpho::ai_stream "Explain this stack trace" | tee /tmp/answer.txt
#
# @arg $1 string Prompt
# @arg $2 string Optional system prompt
# @stdout Assistant answer, written incrementally
# @exitcode 0 The stream completed
# @exitcode 1 Missing arguments or a provider error
# @note Usage counters are not updated for streamed Anthropic calls because the totals arrive in a trailing event this helper does not buffer
#######################################
function dybatpho::ai_stream {
  local prompt system
  dybatpho::expect_args prompt -- "$@"
  system="${2:-${DYBATPHO_AI_SYSTEM}}"
  prompt=$(__ai_redact "${prompt}")

  local provider
  provider=$(dybatpho::ai_provider)
  case "${provider}" in
    anthropic | openai | ollama) ;;
    *)
      dybatpho::debug "ai: ${provider} does not stream, falling back to a buffered call"
      dybatpho::ai_ask "${prompt}" "${system}"
      return $?
      ;;
  esac

  __ai_budget_check

  local conversation payload url base
  conversation=$(__ai_conversation_build "${system}" user "${prompt}")
  payload=$("__ai_payload_${provider}" "${conversation}" '[]' "")
  base=$(__ai_base_url "${provider}")

  local -a headers=()
  case "${provider}" in
    anthropic)
      url="${base}/v1/messages"
      headers+=(--header "x-api-key: $(__ai_api_key anthropic)")
      headers+=(--header "anthropic-version: ${DYBATPHO_AI_ANTHROPIC_VERSION}")
      payload=$(dybatpho::json_eval "${payload}" '.stream = true')
      ;;
    openai)
      url="${base}/chat/completions"
      headers+=(--header "Authorization: Bearer $(__ai_api_key openai)")
      payload=$(dybatpho::json_eval "${payload}" '.stream = true')
      ;;
    ollama)
      url="${base}/api/chat"
      payload=$(dybatpho::json_eval "${payload}" '.stream = true')
      ;;
  esac

  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::dry_run "curl --no-buffer ${url}"
    return 0
  fi

  __ai_count_call
  dybatpho::debug "ai: streaming from ${url}"
  local filter
  case "${provider}" in
    anthropic)
      filter='select(.type == "content_block_delta") | .delta.text // ""'
      ;;
    openai)
      filter='.choices[0].delta.content // ""'
      ;;
    ollama)
      filter='.message.content // ""'
      ;;
  esac

  local line data
  # Server-sent events prefix every payload with `data: `; Ollama streams bare
  # JSON objects. Both are handled by stripping an optional prefix per line.
  curl --silent --no-buffer --show-error \
    --request POST \
    --max-time "${DYBATPHO_AI_TIMEOUT}" \
    --header "Content-Type: application/json" \
    --header "Accept: text/event-stream" \
    "${headers[@]}" \
    --data-binary "${payload}" \
    "${url}" \
    | while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      data="${line#data: }"
      [[ "${data}" == "[DONE]" ]] && break
      [[ "${data}" == event:* ]] && continue
      __ai_stream_chunk "${data}" "${filter}"
    done
  printf '\n'
}

#######################################
# @description Print one streamed delta without adding a line break.
# The JSON backends both terminate their output with a newline, which would
# turn a stream of fragments into a column of them, so exactly one trailing
# newline is removed while any the model actually produced are kept.
# @arg $1 string One event payload
# @arg $2 string Filter selecting the text fragment
# @stdout The fragment, with no added newline
#######################################
function __ai_stream_chunk {
  local event filter
  dybatpho::expect_args event filter -- "$@"
  local chunk
  chunk=$(
    dybatpho::json_get "${event}" "${filter}" 2> /dev/null
    printf 'x'
  ) || return 0
  chunk="${chunk%x}"
  printf '%s' "${chunk%$'\n'}"
}

#######################################
# @description Register a shell function the model may call during `ai_run`.
# @example
#   function service_status { systemctl is-active "$1"; }
#   dybatpho::ai_tool_register service_status "Check whether a systemd unit is active" \
#     '{"type":"object","properties":{"unit":{"type":"string"}},"required":["unit"]}' \
#     service_status
#
# @arg $1 string Tool name the model will use
# @arg $2 string Description telling the model when to call it
# @arg $3 string JSON schema for the tool arguments
# @arg $4 string Shell function that implements the tool
# @set DYBATPHO_AI_TOOL_HANDLER
# @exitcode 0 The tool is registered
# @exitcode 1 Missing arguments, an invalid schema, or an undefined handler
# @tip Write the description prescriptively: say when to call the tool, not only what it does
#######################################
function dybatpho::ai_tool_register {
  local name description schema handler
  dybatpho::expect_args name description schema handler -- "$@"
  dybatpho::json_valid "${schema}" \
    || dybatpho::die "dybatpho::ai_tool_register: The schema for '${name}' is not valid JSON"
  declare -F "${handler}" > /dev/null \
    || dybatpho::die "dybatpho::ai_tool_register: Handler '${handler}' is not a defined function"
  DYBATPHO_AI_TOOL_DESCRIPTION["${name}"]="${description}"
  DYBATPHO_AI_TOOL_SCHEMA["${name}"]="${schema}"
  DYBATPHO_AI_TOOL_HANDLER["${name}"]="${handler}"
}

#######################################
# @description Print the names of registered tools, one per line.
# @example
#   dybatpho::ai_tool_list
#
# @noargs
# @stdout Tool names in alphabetical order
# @exitcode 0 The list was printed, empty when nothing is registered
#######################################
function dybatpho::ai_tool_list {
  local name
  for name in "${!DYBATPHO_AI_TOOL_HANDLER[@]}"; do
    printf '%s\n' "${name}"
  done | sort
}

#######################################
# @description Unregister every tool.
# @noargs
# @set DYBATPHO_AI_TOOL_HANDLER
# @exitcode 0 The registry is empty
#######################################
function dybatpho::ai_tool_clear {
  DYBATPHO_AI_TOOL_DESCRIPTION=()
  DYBATPHO_AI_TOOL_SCHEMA=()
  DYBATPHO_AI_TOOL_HANDLER=()
}

#######################################
# @description Render the tool registry as a provider-neutral tools array.
# @stdout JSON array, `[]` when nothing is registered
#######################################
function __ai_tools_json {
  local tools='[]' name definition
  for name in $(dybatpho::ai_tool_list); do
    definition=$(dybatpho::json_object \
      name "${name}" \
      description "${DYBATPHO_AI_TOOL_DESCRIPTION[${name}]}" \
      input_schema:json "${DYBATPHO_AI_TOOL_SCHEMA[${name}]}")
    tools=$(dybatpho::json_eval "${tools}" ". + [${definition}]")
  done
  printf '%s\n' "${tools}"
}

#######################################
# @description Run one registered tool and print what it wrote.
# A failing handler is not fatal: its output is returned to the model as an
# error result so the model can adapt, which is the documented contract for
# tool results.
# @arg $1 string Tool name
# @arg $2 string Tool arguments as JSON
# @stdout Tool output
#######################################
function __ai_tool_invoke {
  local name arguments
  dybatpho::expect_args name arguments -- "$@"
  local handler="${DYBATPHO_AI_TOOL_HANDLER[${name}]-}"
  if dybatpho::is empty "${handler}"; then
    printf 'Error: no tool named %s is registered\n' "${name}"
    return 0
  fi
  dybatpho::debug "ai: invoking tool ${name}"
  local output status=0
  output=$("${handler}" "${arguments}" 2>&1) || status=$?
  if ((status != 0)); then
    printf 'Error: tool %s exited with status %d\n%s\n' "${name}" "${status}" "${output}"
  else
    printf '%s\n' "${output}"
  fi
}

#######################################
# @description Answer a prompt, letting the model call registered tools first.
# The loop sends the prompt, runs whatever tools the model asks for, feeds the
# results back, and repeats until the model answers in text or the step limit
# is reached.
# @example
#   dybatpho::ai_tool_register disk_free "Report free disk space" \
#     '{"type":"object","properties":{}}' disk_free
#   dybatpho::ai_run "Do we need to clean up the build cache?"
#
# @arg $1 string Prompt
# @arg $2 string Optional system prompt
# @env DYBATPHO_AI_MAX_STEPS number Maximum tool rounds before giving up
# @stdout Final assistant answer
# @exitcode 0 The model produced a final answer
# @exitcode 1 Missing arguments, no tools registered, a provider error, or the step limit was hit
# @note Only the `anthropic` and `openai` backends carry tool calls; on the others this behaves like `dybatpho::ai_ask`
# @tip Handlers receive their arguments as one JSON string; parse it with `dybatpho::json_query`
#######################################
function dybatpho::ai_run {
  local prompt system
  dybatpho::expect_args prompt -- "$@"
  system="${2:-${DYBATPHO_AI_SYSTEM}}"
  prompt=$(__ai_redact "${prompt}")

  local provider
  provider=$(dybatpho::ai_provider)
  case "${provider}" in
    anthropic | openai) ;;
    *)
      dybatpho::debug "ai: ${provider} has no tool-use loop, answering directly"
      dybatpho::ai_ask "${prompt}" "${system}"
      return $?
      ;;
  esac

  ((${#DYBATPHO_AI_TOOL_HANDLER[@]} > 0)) \
    || dybatpho::die "dybatpho::ai_run: No tools registered, use dybatpho::ai_tool_register first"

  __ai_require_json
  local tools messages payload body step=1
  tools=$(__ai_tools_json)
  messages="[$(dybatpho::json_object role user content "${prompt}")]"

  while ((step <= DYBATPHO_AI_MAX_STEPS)); do
    __ai_budget_check
    local conversation
    conversation=$(dybatpho::json_object system "${system}" messages:json "${messages}")
    payload=$("__ai_payload_${provider}" "${conversation}" "${tools}" "")
    body=$(__ai_http "${provider}" "${payload}")
    __ai_assert_no_error "${provider}" "${body}"
    __ai_usage_from_response "${provider}" "${body}"

    # `@json` renders the tool arguments as text both backends spell the same
    # way, so a handler always receives one JSON string.
    local calls
    case "${provider}" in
      anthropic)
        calls=$(dybatpho::json_eval "${body}" \
          '[.content[]? | select(.type == "tool_use")
            | {"id": .id, "name": .name, "arguments": (.input | @json)}]')
        ;;
      openai)
        calls=$(dybatpho::json_eval "${body}" \
          '[.choices[0].message.tool_calls[]?
            | {"id": .id, "name": .function.name, "arguments": .function.arguments}]')
        ;;
    esac

    local total
    total=$(dybatpho::json_get "${calls}" 'length')
    if [[ "${total}" == "0" ]]; then
      __ai_extract_text "${provider}" "${body}"
      return 0
    fi

    # Echo the assistant turn back verbatim so tool results line up with the
    # call ids the provider issued, then append one result per call.
    local assistant
    case "${provider}" in
      anthropic)
        assistant=$(dybatpho::json_object \
          role assistant content:json "$(dybatpho::json_eval "${body}" '.content')")
        ;;
      openai)
        assistant=$(dybatpho::json_eval "${body}" '.choices[0].message')
        ;;
    esac
    messages=$(dybatpho::json_eval "${messages}" ". + [${assistant}]")

    local index=0 call_id call_name call_arguments result entry
    local results='[]'
    while ((index < total)); do
      call_id=$(dybatpho::json_get "${calls}" ".[${index}].id")
      call_name=$(dybatpho::json_get "${calls}" ".[${index}].name")
      call_arguments=$(dybatpho::json_get "${calls}" ".[${index}].arguments")
      result=$(__ai_tool_invoke "${call_name}" "${call_arguments}")
      case "${provider}" in
        anthropic)
          entry=$(dybatpho::json_object \
            type tool_result tool_use_id "${call_id}" content "${result}")
          results=$(dybatpho::json_eval "${results}" ". + [${entry}]")
          ;;
        openai)
          entry=$(dybatpho::json_object \
            role tool tool_call_id "${call_id}" content "${result}")
          messages=$(dybatpho::json_eval "${messages}" ". + [${entry}]")
          ;;
      esac
      index=$((index + 1))
    done

    if [[ "${provider}" == "anthropic" ]]; then
      messages=$(dybatpho::json_eval "${messages}" \
        ". + [$(dybatpho::json_object role user content:json "${results}")]")
    fi
    step=$((step + 1))
  done
  dybatpho::die "dybatpho::ai_run: Gave up after ${DYBATPHO_AI_MAX_STEPS} tool rounds"
}

#######################################
# @description Estimate how many tokens a piece of text costs.
# The estimate is four characters per token, which is close enough to size a
# prompt or decide whether to truncate before a call; it is not a billing figure.
# @example
#   if (($(dybatpho::ai_tokens_estimate "$(cat build.log)") > 100000)); then
#     dybatpho::warn "Log is too large, summarizing in chunks"
#   fi
#
# @arg $1 string Text to measure, stdin is read when omitted
# @stdout Estimated token count
# @exitcode 0 An estimate was printed
# @note Use the provider's own token counting endpoint when an exact number matters
#######################################
# shellcheck disable=SC2120 # The argument is optional; stdin is used without it.
function dybatpho::ai_tokens_estimate {
  local text
  if (($# > 0)); then
    text="$1"
  else
    text=$(cat)
  fi
  local characters=${#text}
  printf '%d\n' $(((characters + 3) / 4))
}

#######################################
# @description Print the token usage recorded so far.
# @example
#   dybatpho::ai_ask "Hello"
#   dybatpho::ai_usage
#   dybatpho::ai_usage total
#
# @arg $1 string Scope, `last` (default) or `total`
# @stdout `calls=N input=N output=N`, plus the model and stop reason for `last`
# @exitcode 0 The counters were printed
# @exitcode 1 Stop the script when the scope is unknown
#######################################
function dybatpho::ai_usage {
  local scope="${1:-last}"
  __ai_state_cleanup_once
  local state
  state=$(__ai_state_read)
  case "${scope}" in
    last)
      dybatpho::json_get "${state}" \
        '"calls=\(.calls) input=\(.last_input) output=\(.last_output) model=\(.last_model) stop_reason=\(.last_stop_reason)"'
      ;;
    total)
      dybatpho::json_get "${state}" \
        '"calls=\(.calls) input=\(.total_input) output=\(.total_output)"'
      ;;
    *) dybatpho::die "dybatpho::ai_usage: Unknown scope '${scope}', expected last or total" ;;
  esac
}

#######################################
# @description Read one usage counter as a bare value.
# @example
#   if (($(dybatpho::ai_usage_field total_output) > 50000)); then
#     dybatpho::warn "This run is getting expensive"
#   fi
#
# @arg $1 string Field name: `calls`, `total_input`, `total_output`, `last_input`, `last_output`, `last_model`, or `last_stop_reason`
# @stdout The counter value
# @exitcode 0 The value was printed
# @exitcode 1 Missing argument or an unknown field
#######################################
function dybatpho::ai_usage_field {
  local field
  dybatpho::expect_args field -- "$@"
  case "${field}" in
    calls | total_input | total_output | last_input | last_output | last_model | last_stop_reason) ;;
    *) dybatpho::die "dybatpho::ai_usage_field: Unknown field '${field}'" ;;
  esac
  __ai_state_cleanup_once
  dybatpho::json_get "$(__ai_state_read)" ".${field}"
}

#######################################
# @description Reset every usage counter and the call budget consumption.
# @noargs
# @exitcode 0 The counters are back to zero
#######################################
function dybatpho::ai_usage_reset {
  __ai_state_cleanup_once
  __ai_state_write '{"calls":0,"total_input":0,"total_output":0,"last_input":0,"last_output":0,"last_model":"","last_stop_reason":""}'
}

#######################################
# @description Cap how many model calls the rest of the script may make.
# @example
#   dybatpho::ai_budget 5 # a runaway loop stops instead of billing forever
#
# @arg $1 number Maximum number of calls; `0` removes the cap
# @set DYBATPHO_AI_MAX_CALLS
# @exitcode 0 The budget is set
# @exitcode 1 Missing or non-numeric argument
#######################################
function dybatpho::ai_budget {
  local limit
  dybatpho::expect_args limit -- "$@"
  [[ "${limit}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "dybatpho::ai_budget: Expected a number, got '${limit}'"
  DYBATPHO_AI_MAX_CALLS=${limit}
}

#######################################
# @description Redact secrets and common personal identifiers in text.
# Registered secrets are masked first, then email addresses, IPv4 addresses,
# and long digit runs are replaced with placeholders.
# @example
#   dybatpho::ai_ask "Explain this error: $(dybatpho::ai_redact "${line}")"
#
# @arg $1 string Text to redact, stdin is read when omitted
# @stdout Redacted text
# @exitcode 0 The text was printed
# @tip This is a coarse net, not a compliance control; do not send regulated data to a third party provider on the strength of it
# @see dybatpho::secret_register
#######################################
# shellcheck disable=SC2120 # The argument is optional; stdin is used without it.
function dybatpho::ai_redact {
  local text
  if (($# > 0)); then
    text="$1"
  else
    text=$(cat)
  fi
  text=$(dybatpho::secret_mask "${text}")
  printf '%s\n' "${text}" | sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
    -e 's/\b[0-9]{9,}\b/<number>/g'
}
