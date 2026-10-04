# shellcheck shell=bash
# This file lets its internal helpers take their arguments positionally, rather
# than adding a `dybatpho::expect_args` call to paths written to avoid one; it
# shares some variables with the caller or across calls on purpose, which is
# what `local` would break; it parses its own arguments, so the raw form is
# what the reader sees.
# dyshellint disable=BSG050,BSG011,BSG051
# @file ai.sh
# @brief Utilities for calling large language models from shell scripts
# @namespace dybatpho
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
# @tip Set `DYBATPHO_AI_PROVIDER` to pin a backend; the default `auto` picks the first one whose credentials or command
#   are
#   present
# @tip Every prompt is passed through `dybatpho::secret_mask` first, so values registered with
#   `dybatpho::secret_register`
#   never reach the provider
# @note Payloads and responses go through the `json` module, so this needs `yq` or `jq` like the rest of the library;
#   building them by string concatenation is too escaping-sensitive to be safe
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
# The default lives under the XDG state directory rather than in `/tmp`. The
# name is `dybatpho_ai_state_<pid>`, which is entirely predictable -- the pid is
# public through `ps` and comes from a small space -- and the counters are
# written with a plain `>`, which follows a symbolic link. In a world-writable
# `/tmp` that is an arbitrary-file-overwrite primitive: another account
# pre-creates that name as a link to a file of yours and the next run truncates
# it. A directory only you can write closes that off, and
# `__dybatpho_ai_state_prepare_into` refuses to follow a link even there.
#
# @env DYBATPHO_AI_STATE_FILE string File the call and token counters are kept in; resolved on first use
DYBATPHO_AI_STATE_FILE=${DYBATPHO_AI_STATE_FILE:-}

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
# @internal
#######################################
function __dybatpho_ai_require_json {
  # Only the refusal matters here: which backend answered does not.
  # shellcheck disable=SC2034 # out-param of the resolver; nothing reads it
  local backend
  __dybatpho_json_cmd_into backend
}

#######################################
# @description Mask registered secrets in text before it leaves the machine.
# @arg $1 string Text to redact
# @env DYBATPHO_AI_REDACT bool Return the text unchanged when not true
# @stdout Redacted text
# @see dybatpho::secret_mask
# @internal
#######################################
function __dybatpho_ai_redact {
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
# @internal
#######################################
function __dybatpho_ai_state_cleanup_once {
  [[ "${BASHPID}" == "$$" ]] || return 0
  [[ -n "${__dybatpho_ai_state_cleanup-}" ]] && return 0
  __dybatpho_ai_state_cleanup=1
  local ai_state_path
  __dybatpho_ai_state_path_into ai_state_path
  dybatpho::cleanup_file_on_exit "${ai_state_path}"
}

#######################################
# @description Resolve the counter file into a variable, defaulting to a
#   private directory under the XDG state home rather than to a predictable name
#   in a shared `/tmp`.
#
#   The directory is created 0700, so no other account can plant anything in it.
#   Resolution is lazy because working it out needs `HOME`, and a module must
#   not fail at source time on a host that has none. It runs in the caller's
#   shell, so the resolved path is remembered there: from inside `$(...)` the
#   answer was worked out, and the directory checked, on every call.
# @arg $1 string Name of the variable receiving the path of the counter file
# @env DYBATPHO_AI_STATE_FILE string Overrides the default when set
# @set DYBATPHO_AI_STATE_FILE
# @set The named variable
# @internal
#######################################
function __dybatpho_ai_state_path_into {
  local __dybatpho_ai_state_var
  dybatpho::expect_args __dybatpho_ai_state_var -- "$@"
  local -n __dybatpho_ai_state_out="${__dybatpho_ai_state_var}"
  if [[ -z "${DYBATPHO_AI_STATE_FILE}" ]]; then
    local __dybatpho_ai_state_dir
    __dybatpho_xdg_dir_into __dybatpho_ai_state_dir ai XDG_STATE_HOME ".local/state" dybatpho
    # The counters are bookkeeping, not an effect the caller asked for, so a dry
    # run still needs the directory: without it the first count aborts.
    DRY_RUN=false dybatpho::ensure_dir "${__dybatpho_ai_state_dir}" 700 > /dev/null
    DYBATPHO_AI_STATE_FILE="${__dybatpho_ai_state_dir}/ai_state_$$"
  fi
  __dybatpho_ai_state_out="${DYBATPHO_AI_STATE_FILE}"
}

#######################################
# @description Resolve the counter file into a variable, refusing to use it
#   through a symbolic link. Writing the counters is a plain redirection, which
#   follows a link and truncates whatever is on the other end, so a link here is
#   either an attack or a mistake; either way it is not something to write
#   through.
# @arg $1 string Name of the variable receiving the path of the counter file
# @set The named variable
# @exitcode 0 The path is safe to write
# @exitcode 1 Stop the script when the path is a symbolic link
# @internal
#######################################
function __dybatpho_ai_state_prepare_into {
  local __dybatpho_ai_prepare_var
  dybatpho::expect_args __dybatpho_ai_prepare_var -- "$@"
  local -n __dybatpho_ai_prepare_out="${__dybatpho_ai_prepare_var}"
  local __dybatpho_ai_prepare_path
  __dybatpho_ai_state_path_into __dybatpho_ai_prepare_path
  [[ -L "${__dybatpho_ai_prepare_path}" ]] \
    && dybatpho::die "ai: refusing to use ${__dybatpho_ai_prepare_path}, it is a symbolic link"
  __dybatpho_ai_prepare_out="${__dybatpho_ai_prepare_path}"
}

#######################################
# @description Read the counter document into a named variable, creating it
#   on first use.
#   It runs in the caller's shell, so a counter file that cannot be placed --
#   no HOME to put it under, or a symbolic link in its place -- stops the call
#   that needed it, rather than only the substitution reading it.
# @arg $1 string Name of the variable receiving the counter JSON
# @env DYBATPHO_AI_STATE_FILE string File the counters are kept in
# @set The named variable
# @internal
#######################################
function __dybatpho_ai_state_read_into {
  local -n __dybatpho_ai_read_ref="$1"
  local __dybatpho_ai_read_path
  __dybatpho_ai_state_prepare_into __dybatpho_ai_read_path
  if [[ ! -f "${__dybatpho_ai_read_path}" ]]; then
    local __dybatpho_ai_read_empty='{"calls":0,"total_input":0,"total_output":0,"last_input":0,"last_output":0,'
    __dybatpho_ai_read_empty+='"last_model":"","last_stop_reason":""}'
    printf '%s\n' "${__dybatpho_ai_read_empty}" > "${__dybatpho_ai_read_path}"
  fi
  __dybatpho_ai_read_ref="$(< "${__dybatpho_ai_read_path}")"
}

#######################################
# @description Replace the counter document.
# @arg $1 string Counter JSON
# @internal
#######################################
function __dybatpho_ai_state_write {
  local document path
  dybatpho::expect_args document -- "$@"
  __dybatpho_ai_state_prepare_into path
  printf '%s\n' "${document}" > "${path}"
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
# @internal
#######################################
function __dybatpho_ai_budget_check {
  local wanted="${1:-1}"
  # Every public entry point passes through here, which makes it the place to
  # arrange cleanup of the counter file in the caller's own shell.
  __dybatpho_ai_state_cleanup_once
  # The counters are read again deep inside command substitutions; reading them
  # here first places the file in this shell, so a refusal stops the call
  # rather than only a subshell.
  local state
  __dybatpho_ai_state_read_into state
  ((DYBATPHO_AI_MAX_CALLS > 0)) || return 0
  local calls
  calls=$(dybatpho::json_get "${state}" '.calls')
  if ((calls + wanted > DYBATPHO_AI_MAX_CALLS)); then
    dybatpho::die "ai: call budget of ${DYBATPHO_AI_MAX_CALLS} calls is exhausted"
  fi
}

#######################################
# @description Count one model call in the shared counter file.
# @noargs
# @exitcode 0 The counter was incremented
# @internal
#######################################
function __dybatpho_ai_count_call {
  local ai_state_read
  __dybatpho_ai_state_read_into ai_state_read
  local json_eval
  json_eval=$(dybatpho::json_eval "${ai_state_read}" '.calls += 1')
  __dybatpho_ai_state_write "${json_eval}"
}

#######################################
# @description Record the token usage a provider reported for one call.
# @arg $1 number Input tokens
# @arg $2 number Output tokens
# @arg $3 string Model that answered
# @arg $4 string Stop reason
# @internal
#######################################
function __dybatpho_ai_record_usage {
  local input_tokens="${1:-0}" output_tokens="${2:-0}" model="${3:-}" stop_reason="${4:-}"
  [[ "${input_tokens}" =~ ^[0-9]+$ ]] || input_tokens=0
  [[ "${output_tokens}" =~ ^[0-9]+$ ]] || output_tokens=0
  # The object is spelled here rather than built by a JSON backend: it is four
  # known fields, and a process per response to assemble them was half of what
  # recording usage cost.
  local model_json stop_json
  __dybatpho_log_json_escape_into model_json "${model}"
  __dybatpho_log_json_escape_into stop_json "${stop_reason}"
  local last
  printf -v last '{"last_input":%s,"last_output":%s,"last_model":"%s","last_stop_reason":"%s"}' \
    "${input_tokens}" "${output_tokens}" "${model_json}" "${stop_json}"
  local state
  __dybatpho_ai_state_read_into state
  __dybatpho_ai_state_write "$(dybatpho::json_eval "${state}" \
    ". + ${last} | .total_input += ${input_tokens} | .total_output += ${output_tokens}")"
}

#######################################
# @description Return success when an Ollama daemon answers on the base URL.
# @noargs
# @exitcode 0 Ollama is reachable
# @exitcode 1 Ollama is not reachable
# @internal
#######################################
function __dybatpho_ai_ollama_alive {
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
      dybatpho::die \
        "${FUNCNAME[0]}: Unknown provider '${DYBATPHO_AI_PROVIDER}'; expected auto, anthropic, openai, ollama or cli"
      ;;
  esac

  if dybatpho::is set "${DYBATPHO_AI_API_KEY}"; then
    printf 'anthropic\n'
  elif dybatpho::is set "${ANTHROPIC_API_KEY-}"; then
    printf 'anthropic\n'
  elif dybatpho::is set "${OPENAI_API_KEY-}"; then
    printf 'openai\n'
  elif __dybatpho_ai_ollama_alive; then
    printf 'ollama\n'
  elif dybatpho::coalesce_cmd claude llm ollama > /dev/null 2>&1; then
    printf 'cli\n'
  else
    dybatpho::die \
      "dybatpho::ai_provider: No AI backend. Set ANTHROPIC_API_KEY or OPENAI_API_KEY, run ollama, or install a CLI"
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
# @internal
#######################################
function __dybatpho_ai_api_key {
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
# @internal
#######################################
function __dybatpho_ai_base_url {
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
  __dybatpho_ai_require_json
  local provider
  provider=$(dybatpho::ai_provider)
  case "${provider}" in
    anthropic | openai | ollama)
      hash curl > /dev/null 2>&1 || dybatpho::die "ai: curl is required by the ${provider} backend" 127
      __dybatpho_ai_api_key "${provider}" > /dev/null
      ;;
    cli)
      __dybatpho_ai_cli_command > /dev/null
      ;;
    *) ;;
  esac
  local ai_model
  ai_model=$(dybatpho::ai_model "${provider}")
  dybatpho::debug "ai: provider=${provider} model=${ai_model}"
}

#######################################
# @description Resolve the command used by the `cli` backend.
# @noargs
# @env DYBATPHO_AI_CLI string Pin a command instead of probing
# @stdout `claude`, `llm`, or `ollama`
# @exitcode 0 A supported client exists
# @exitcode 127 Stop the script when no client is installed
# @internal
#######################################
function __dybatpho_ai_cli_command {
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
# @internal
#######################################
function __dybatpho_ai_conversation_build {
  local system
  dybatpho::expect_args system -- "$@"
  shift
  # Every value is a plain string, so the document is spelled here with the
  # library's one escaper: building it through a JSON backend cost two
  # processes per turn and one more for the envelope.
  local messages="" escaped_role escaped_content escaped_system
  while (($# >= 2)); do
    __dybatpho_log_json_escape_into escaped_role "$1"
    __dybatpho_log_json_escape_into escaped_content "$2"
    shift 2
    [[ -n "${messages}" ]] && messages+=","
    messages+="{\"role\":\"${escaped_role}\",\"content\":\"${escaped_content}\"}"
  done
  __dybatpho_log_json_escape_into escaped_system "${system}"
  printf '{"system":"%s","messages":[%s]}\n' "${escaped_system}" "${messages}"
}

#######################################
# @description Render a conversation document into an Anthropic request body.
# @arg $1 string Conversation JSON
# @arg $2 string Tools array JSON, or `[]`
# @arg $3 string Output schema JSON, or empty for free-form text
# @stdout Request payload
# @internal
#######################################
function __dybatpho_ai_payload_anthropic {
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
# @internal
#######################################
function __dybatpho_ai_payload_openai {
  local conversation tools schema
  dybatpho::expect_args conversation tools -- "$@"
  schema="${3:-}"

  local system messages
  system=$(dybatpho::json_get "${conversation}" '.system')
  messages=$(__dybatpho_ai_messages_with_system "${conversation}")

  local -a fields=(
    model "$(dybatpho::ai_model openai)"
    max_tokens:json "${DYBATPHO_AI_MAX_TOKENS}"
    messages:json "${messages}"
  )
  dybatpho::is set "${DYBATPHO_AI_TEMPERATURE}" \
    && fields+=(temperature:json "${DYBATPHO_AI_TEMPERATURE}")
  if [[ "${tools}" != "[]" ]]; then
    fields+=(tools:json "$(__dybatpho_ai_tools_as_functions "${tools}")")
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
# @internal
#######################################
function __dybatpho_ai_messages_with_system {
  local conversation
  dybatpho::expect_args conversation -- "$@"
  local system messages
  system=$(dybatpho::json_get "${conversation}" '.system')
  messages=$(dybatpho::json_eval "${conversation}" '.messages')
  if dybatpho::is set "${system}"; then
    local json_object
    json_object=$(dybatpho::json_object role system content "${system}")
    messages=$(dybatpho::json_eval "${messages}" \
      "[${json_object}] + .")
  fi
  printf '%s\n' "${messages}"
}

#######################################
# @description Convert the neutral tool list into the OpenAI function shape,
# which both OpenAI-compatible endpoints and Ollama accept.
# @arg $1 string Tools array JSON
# @stdout Converted tools array JSON
# @internal
#######################################
function __dybatpho_ai_tools_as_functions {
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
# @internal
#######################################
function __dybatpho_ai_payload_ollama {
  local conversation tools schema
  dybatpho::expect_args conversation tools -- "$@"
  schema="${3:-}"

  local -a fields=(
    model "$(dybatpho::ai_model ollama)"
    stream:json false
    messages:json "$(__dybatpho_ai_messages_with_system "${conversation}")"
  )
  if dybatpho::is set "${DYBATPHO_AI_TEMPERATURE}"; then
    fields+=(options:json "$(dybatpho::json_object temperature:json "${DYBATPHO_AI_TEMPERATURE}")")
  fi
  [[ "${tools}" != "[]" ]] && fields+=(tools:json "$(__dybatpho_ai_tools_as_functions "${tools}")")
  dybatpho::is set "${schema}" && fields+=(format:json "${schema}")

  dybatpho::json_object "${fields[@]}"
}

#######################################
# @description Compute the cache key of a request.
# @arg $1 string Backend name
# @arg $2 string Request payload
# @stdout Hexadecimal key
# @internal
#######################################
function __dybatpho_ai_cache_key {
  local provider payload
  dybatpho::expect_args provider payload -- "$@"
  dybatpho::cache_key "${provider}" "${payload}"
}

#######################################
# @description Run a cache helper against this module's own cache directory.
#   `DYBATPHO_AI_CACHE_DIR` names the directory outright rather than a namespace
#   below one, and it has been documented that way, so the namespace is emptied
#   for the call instead of the path being rebuilt.
# @arg $@ string A `dybatpho::cache_*` function and its arguments
# @internal
#######################################
function __dybatpho_ai_cache {
  DYBATPHO_CACHE_DIR="${DYBATPHO_AI_CACHE_DIR}" DYBATPHO_CACHE_NAMESPACE="" "$@"
}

#######################################
# @description Print a cached response when one is present and still fresh.
# @arg $1 string Cache key
# @env DYBATPHO_AI_CACHE_TTL number Maximum age in seconds
# @stdout Cached response body
# @exitcode 0 A fresh entry was printed
# @exitcode 1 No usable entry
# @internal
#######################################
function __dybatpho_ai_cache_read {
  local key
  dybatpho::expect_args key -- "$@"
  dybatpho::is true "${DYBATPHO_AI_CACHE}" || return 1
  __dybatpho_ai_cache dybatpho::cache_get "${key}" "${DYBATPHO_AI_CACHE_TTL}" || return 1
  dybatpho::debug "ai: cache hit ${key}"
}

#######################################
# @description Store a response body in the cache.
# @arg $1 string Cache key
# @arg $2 string Response body
# @exitcode 0 Stored, or caching is disabled
# @internal
#######################################
function __dybatpho_ai_cache_write {
  local key body
  dybatpho::expect_args key body -- "$@"
  dybatpho::is true "${DYBATPHO_AI_CACHE}" || return 0
  printf '%s\n' "${body}" | __dybatpho_ai_cache dybatpho::cache_set "${key}"
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
  dybatpho::is dir "${DYBATPHO_AI_CACHE_DIR}" || return 0
  dybatpho::debug "ai: clearing cache in ${DYBATPHO_AI_CACHE_DIR}"
  __dybatpho_ai_cache dybatpho::cache_clear
  # Entries this module wrote before it used the `cache` module carry a `.json`
  # suffix, and nothing else would ever come back for them.
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  dybatpho::is true "${DRY_RUN}" \
    || find "${DYBATPHO_AI_CACHE_DIR}" -maxdepth 1 -name '*.json' -type f -delete
}

#######################################
# @description Produce a provider-shaped placeholder response for `DRY_RUN`.
# Keeping the shape lets the rest of the pipeline run unchanged, so an example
# or a rehearsal exercises the real extraction and accounting code.
# @arg $1 string Backend name
# @arg $2 string Request payload, inspected for a structured output contract
# @stdout Response body in the provider's own shape
# @internal
#######################################
function __dybatpho_ai_dry_run_body {
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
      local usage
      usage=$(dybatpho::json_object input_tokens:json 0 output_tokens:json 0)
      local block
      block=$(dybatpho::json_object type text text "${text}")
      dybatpho::json_object \
        model "${model}" \
        stop_reason end_turn \
        content:json "[${block}]" \
        usage:json "${usage}"
      ;;
    openai)
      local choice
      local message
      message=$(dybatpho::json_object role assistant content "${text}")
      choice=$(dybatpho::json_object \
        finish_reason stop \
        message:json "${message}")
      local usage
      usage=$(dybatpho::json_object prompt_tokens:json 0 completion_tokens:json 0)
      dybatpho::json_object \
        model "${model}" \
        choices:json "[${choice}]" \
        usage:json "${usage}"
      ;;
    ollama)
      local json_object
      json_object=$(dybatpho::json_object role assistant content "${text}")
      dybatpho::json_object \
        model "${model}" \
        done_reason stop \
        message:json "${json_object}" \
        prompt_eval_count:json 0 \
        eval_count:json 0
      ;;
    *) ;;
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
# @internal
#######################################
function __dybatpho_ai_http {
  local provider payload
  dybatpho::expect_args provider payload -- "$@"

  # Hashing the payload costs a pipeline per request, so it is skipped unless
  # the cache is actually on.
  local cache_key="" body
  if dybatpho::is true "${DYBATPHO_AI_CACHE}"; then
    cache_key=$(__dybatpho_ai_cache_key "${provider}" "${payload}")
    if body=$(__dybatpho_ai_cache_read "${cache_key}"); then
      printf '%s\n' "${body}"
      return 0
    fi
  fi

  local url
  local -a headers=()
  # The API key and the prompt both go to curl out of band: an argument is
  # world-readable through `/proc/<pid>/cmdline` for the life of the request.
  local -a DYBATPHO_CURL_SECRET_HEADERS=()
  __dybatpho_ai_endpoint_into "${provider}" url headers

  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::info "🧪 DRY RUN: POST ${url} as ${provider}"
    __dybatpho_ai_dry_run_body "${provider}" "${payload}"
    return 0
  fi

  __dybatpho_ai_count_call
  local response_file
  dybatpho::create_temp response_file ".json" "ai_response"

  # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
  local DYBATPHO_CURL_SECRET_DATA="${payload}"
  dybatpho::debug "ai: POST ${url}"
  dybatpho::curl_json "${url}" "${response_file}" \
    --request POST \
    --max-time "${DYBATPHO_AI_TIMEOUT}" \
    ${headers[@]+"${headers[@]}"} || return $?

  body=$(cat "${response_file}")
  [[ -z "${cache_key}" ]] || __dybatpho_ai_cache_write "${cache_key}" "${body}"
  printf '%s\n' "${body}"
}

#######################################
# @description Resolve where a backend is reached and what it must be told.
#   The buffered and the streaming call both send to the same place, so the
#   choice is made once, here. The key goes into `DYBATPHO_CURL_SECRET_HEADERS`,
#   which the caller declares local, so it never becomes a curl argument.
# @arg $1 string Backend name, `anthropic`, `openai` or `ollama`
# @arg $2 string Name of the variable receiving the URL
# @arg $3 string Name of the array receiving extra curl header arguments
# @set The named variable and array, and the caller's `DYBATPHO_CURL_SECRET_HEADERS`
# @internal
#######################################
function __dybatpho_ai_endpoint_into {
  local __dybatpho_ai_ep_provider="$1"
  local -n __dybatpho_ai_ep_url="$2" __dybatpho_ai_ep_headers="$3"
  local __dybatpho_ai_ep_base
  __dybatpho_ai_ep_base=$(__dybatpho_ai_base_url "${__dybatpho_ai_ep_provider}")
  case "${__dybatpho_ai_ep_provider}" in
    anthropic)
      __dybatpho_ai_ep_url="${__dybatpho_ai_ep_base}/v1/messages"
      DYBATPHO_CURL_SECRET_HEADERS+=("x-api-key: $(__dybatpho_ai_api_key anthropic)")
      __dybatpho_ai_ep_headers+=(--header "anthropic-version: ${DYBATPHO_AI_ANTHROPIC_VERSION}")
      ;;
    openai)
      __dybatpho_ai_ep_url="${__dybatpho_ai_ep_base}/chat/completions"
      DYBATPHO_CURL_SECRET_HEADERS+=("Authorization: Bearer $(__dybatpho_ai_api_key openai)")
      ;;
    ollama)
      __dybatpho_ai_ep_url="${__dybatpho_ai_ep_base}/api/chat"
      ;;
    *) ;;
  esac
}

#######################################
# @description Stop the script when a provider response carries an error object.
# @arg $1 string Backend name
# @arg $2 string Response body
# @exitcode 0 The response has no error field
# @exitcode 1 Stop the script and report the provider message
# @internal
#######################################
function __dybatpho_ai_assert_no_error {
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
# @internal
#######################################
function __dybatpho_ai_extract_text {
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
    *) ;;
  esac
}

#######################################
# @description Read token usage out of a provider response into the module state.
# @arg $1 string Backend name
# @arg $2 string Response body
# @see dybatpho::ai_usage
# @internal
#######################################
function __dybatpho_ai_usage_from_response {
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
    *) ;;
  esac
  __dybatpho_ai_record_usage "${input_tokens}" "${output_tokens}" "${model}" "${stop_reason}"
}

#######################################
# @description Check a provider response, record its usage and take its text,
#   reading the document once.
#   Asking for the error, the four usage fields and the text separately started
#   a JSON backend six times per response. One filter answers all of them as
#   lines, the text last because it is the only field that can hold a newline,
#   and a trailing marker keeps the text's own trailing newlines from being
#   eaten by the command substitution. A body the filter cannot read falls back
#   to the separate questions, which is how such a body was always handled.
# @arg $1 string Name of the variable receiving the assistant text
# @arg $2 string Backend name
# @arg $3 string Response body
# @set The named variable
# @exitcode 1 Stop the script when the response carries an error object
# @internal
#######################################
function __dybatpho_ai_response_into {
  local -n __dybatpho_ai_resp_text="$1"
  local __dybatpho_ai_resp_provider="$2" __dybatpho_ai_resp_body="$3"
  local __dybatpho_ai_resp_fields
  case "${__dybatpho_ai_resp_provider}" in
    anthropic)
      __dybatpho_ai_resp_fields='(.usage.input_tokens // 0), (.usage.output_tokens // 0),
        (.stop_reason // ""), ([.content[]? | select(.type == "text") | .text] | join(""))'
      ;;
    openai)
      __dybatpho_ai_resp_fields='(.usage.prompt_tokens // 0), (.usage.completion_tokens // 0),
        (.choices[0].finish_reason // ""), (.choices[0].message.content // "")'
      ;;
    ollama)
      __dybatpho_ai_resp_fields='(.prompt_eval_count // 0), (.eval_count // 0),
        (.done_reason // ""), (.message.content // "")'
      ;;
    *) ;;
  esac

  local __dybatpho_ai_resp_digest
  if ! __dybatpho_ai_resp_digest=$(dybatpho::json_get "${__dybatpho_ai_resp_body}" \
    "[([.error? | select(. != null)] | length), (.model // \"\"), ${__dybatpho_ai_resp_fields}]
      | map(tostring) | join(\"\\n\") + \"#\"" 2> /dev/null); then
    __dybatpho_ai_assert_no_error "${__dybatpho_ai_resp_provider}" "${__dybatpho_ai_resp_body}"
    __dybatpho_ai_usage_from_response "${__dybatpho_ai_resp_provider}" "${__dybatpho_ai_resp_body}"
    __dybatpho_ai_resp_text=$(__dybatpho_ai_extract_text \
      "${__dybatpho_ai_resp_provider}" "${__dybatpho_ai_resp_body}")
    return 0
  fi
  __dybatpho_ai_resp_digest="${__dybatpho_ai_resp_digest%#}"

  local -a __dybatpho_ai_resp_head=()
  local __dybatpho_ai_resp_index
  for __dybatpho_ai_resp_index in 0 1 2 3 4; do
    __dybatpho_ai_resp_head+=("${__dybatpho_ai_resp_digest%%$'\n'*}")
    __dybatpho_ai_resp_digest="${__dybatpho_ai_resp_digest#*$'\n'}"
  done
  if [[ "${__dybatpho_ai_resp_head[0]}" != "0" ]]; then
    __dybatpho_ai_assert_no_error "${__dybatpho_ai_resp_provider}" "${__dybatpho_ai_resp_body}"
  fi
  __dybatpho_ai_record_usage "${__dybatpho_ai_resp_head[2]}" "${__dybatpho_ai_resp_head[3]}" \
    "${__dybatpho_ai_resp_head[1]}" "${__dybatpho_ai_resp_head[4]}"
  __dybatpho_ai_resp_text="${__dybatpho_ai_resp_digest}"
}

#######################################
# @description Complete a conversation through the `cli` backend.
# @arg $1 string Conversation JSON
# @stdout Assistant text
# @exitcode 0 The client answered
# @internal
#######################################
function __dybatpho_ai_cli_complete {
  local conversation
  dybatpho::expect_args conversation -- "$@"
  local command system prompt model
  command=$(__dybatpho_ai_cli_command)
  model=$(dybatpho::ai_model cli)
  system=$(dybatpho::json_get "${conversation}" '.system // ""')
  # Command line clients are single-shot, so the history is flattened into one
  # prompt with explicit speaker labels rather than a structured message list.
  # The labels are built here rather than in a filter because the two JSON
  # backends spell their case conversion differently.
  # The roles are fixed words, so all of them come back in one read; only the
  # contents, which can hold anything, are read one at a time.
  local count index=0 role content
  local -a roles=()
  local role_lines
  role_lines=$(dybatpho::json_get "${conversation}" '.messages[].role')
  [[ -z "${role_lines}" ]] || mapfile -t roles <<< "${role_lines}"
  count="${#roles[@]}"
  prompt=""
  while ((index < count)); do
    role="${roles[index]}"
    content=$(dybatpho::json_get "${conversation}" ".messages[${index}].content")
    prompt+="${role^^}: ${content}"
    ((index + 1 < count)) && prompt+=$'\n\n'
    index=$((index + 1))
  done

  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::info "🧪 DRY RUN: ${command} would answer this prompt"
    printf '[dry run] no request was sent\n'
    return 0
  fi

  __dybatpho_ai_count_call
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
    *) ;;
  esac
}

#######################################
# @description Complete a conversation and print the assistant text.
# This is the single funnel every public helper goes through.
# @arg $1 string Conversation JSON
# @arg $2 string Output schema JSON, or empty
# @stdout Assistant text
# @exitcode 0 The provider answered
# @internal
#######################################
function __dybatpho_ai_complete {
  local conversation schema
  dybatpho::expect_args conversation -- "$@"
  schema="${2:-}"
  local provider
  provider=$(dybatpho::ai_provider)

  if [[ "${provider}" == "cli" ]]; then
    __dybatpho_ai_cli_complete "${conversation}"
    return 0
  fi

  local payload body text
  payload=$("__dybatpho_ai_payload_${provider}" "${conversation}" '[]' "${schema}")
  body=$(__dybatpho_ai_http "${provider}" "${payload}")
  __dybatpho_ai_response_into text "${provider}" "${body}"
  printf '%s\n' "${text}"
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
  __dybatpho_ai_budget_check
  prompt=$(__dybatpho_ai_redact "${prompt}")
  local conversation
  conversation=$(__dybatpho_ai_conversation_build "${system}" user "${prompt}")
  __dybatpho_ai_complete "${conversation}"
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
  dybatpho::expect_ref "${1-}"
  # The file is made in a helper of its own scope: the path is written through
  # the name the caller passes, and a plain local here of the same name
  # (`file`, `system`) would receive it instead.
  local __dybatpho_ai_conversation_file
  __dybatpho_ai_conversation_file_into __dybatpho_ai_conversation_file "${2:-${DYBATPHO_AI_SYSTEM}}"
  local -n __dybatpho_ai_conversation_path="$1"
  # shellcheck disable=SC2034 # The caller reads the value through the nameref.
  __dybatpho_ai_conversation_path="${__dybatpho_ai_conversation_file}"
}

#######################################
# @description Create a conversation file holding an optional system prompt.
# @arg $1 string Name of the variable receiving the file path
# @arg $2 string System prompt, or empty for none
# @set The named variable
# @internal
#######################################
function __dybatpho_ai_conversation_file_into {
  local -n __dybatpho_ai_conversation_ref="$1"
  local file
  dybatpho::create_temp file ".json" "ai_chat"
  __dybatpho_ai_conversation_build "$2" > "${file}"
  __dybatpho_ai_conversation_ref="${file}"
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
  local cat
  cat=$(cat "${file}")
  updated=$(dybatpho::json_eval "${cat}" ".messages += [${turn}]")
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
  __dybatpho_ai_budget_check
  prompt=$(__dybatpho_ai_redact "${prompt}")
  dybatpho::ai_conversation_add "${file}" user "${prompt}"
  local answer
  local cat
  cat=$(cat "${file}")
  answer=$(__dybatpho_ai_complete "${cat}")
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

  prompt=$(__dybatpho_ai_redact "${prompt}")
  local provider
  provider=$(dybatpho::ai_provider)

  local effective_prompt="${prompt}"
  local native_schema="${schema}"
  # The `cli` backend has no structured output switch, so the contract moves
  # into the prompt and is enforced by the local parse below.
  if [[ "${provider}" == "cli" ]]; then
    native_schema=""
    effective_prompt="${prompt}

Answer with a single JSON document and nothing else. No prose, no Markdown
code fence. It must validate against this JSON schema:
${schema}"
  fi

  local attempt=1 answer candidate
  while ((attempt <= DYBATPHO_AI_JSON_RETRIES)); do
    __dybatpho_ai_budget_check
    local conversation
    conversation=$(__dybatpho_ai_conversation_build "${system}" user "${effective_prompt}")
    answer=$(__dybatpho_ai_complete "${conversation}" "${native_schema}")
    # Models sometimes wrap JSON in a fence even when told not to; strip it
    # before parsing rather than failing a well-formed answer on packaging.
    candidate=$(printf '%s\n' "${answer}" \
      | sed -e 's/^[[:space:]]*```[a-zA-Z]*[[:space:]]*$//' -e 's/^[[:space:]]*```[[:space:]]*$//')
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
# @exitcode 1 Missing arguments, or the request never reached the provider or broke off
# @exitcode 3 The provider answered with HTTP 3xx
# @exitcode 4 The provider answered with HTTP 4xx, such as a rejected key or a rate limit
# @exitcode 5 The provider answered with HTTP 5xx
# @note Usage counters are not updated for streamed Anthropic calls because the totals arrive in a trailing event this
#   helper does not buffer
#######################################
function dybatpho::ai_stream {
  local prompt system
  dybatpho::expect_args prompt -- "$@"
  system="${2:-${DYBATPHO_AI_SYSTEM}}"
  prompt=$(__dybatpho_ai_redact "${prompt}")

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

  __dybatpho_ai_budget_check

  local conversation payload url
  conversation=$(__dybatpho_ai_conversation_build "${system}" user "${prompt}")
  payload=$("__dybatpho_ai_payload_${provider}" "${conversation}" '[]' "")
  payload=$(dybatpho::json_eval "${payload}" '.stream = true')

  local -a headers=()
  # Streaming talks to curl directly rather than through `dybatpho::curl_do`, so
  # it builds the same private config file itself: the key must not become an
  # argument, where `/proc/<pid>/cmdline` publishes it to the whole host.
  local -a DYBATPHO_CURL_SECRET_HEADERS=()
  __dybatpho_ai_endpoint_into "${provider}" url headers

  # A self-hosted base URL can hold credentials or a key in its path, so the
  # rehearsal and the debug line show it redacted, like every network log line.
  local shown_url
  __dybatpho_network_redact_url_into shown_url "${url}"
  if dybatpho::is true "${DRY_RUN-}"; then
    dybatpho::dry_run curl --no-buffer "${shown_url}"
    return 0
  fi

  __dybatpho_ai_count_call
  dybatpho::debug "ai: streaming from ${shown_url}"
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
    *) ;;
  esac

  local stream_config=""
  __dybatpho_network_secret_config stream_config
  # The status comes from the response headers and curl's own exit code from a
  # file: both are lost otherwise, because the body is read through a process
  # substitution. Without them a refused request -- whose error object matches
  # no delta filter -- printed an empty answer and returned 0.
  local header_file curl_status_file
  dybatpho::create_temp header_file ".headers" "ai_stream"
  dybatpho::create_temp curl_status_file ".status" "ai_stream"
  local -a stream_args=(--silent --no-buffer --show-error --request POST -D "${header_file}")
  # The same timeouts `dybatpho::curl_do` honours, then the per-call limit,
  # which wins as it does for a buffered call.
  [[ -n "${DYBATPHO_CURL_CONNECT_TIMEOUT}" ]] \
    && stream_args+=(--connect-timeout "${DYBATPHO_CURL_CONNECT_TIMEOUT}")
  [[ -n "${DYBATPHO_CURL_TIMEOUT}" ]] && stream_args+=(--max-time "${DYBATPHO_CURL_TIMEOUT}")
  stream_args+=(--max-time "${DYBATPHO_AI_TIMEOUT}")
  [[ -n "${stream_config}" ]] && stream_args+=(--config "${stream_config}")

  local line data body=""
  # Server-sent events prefix every payload with `data: `; Ollama streams bare
  # JSON objects. Both are handled by stripping an optional prefix per line.
  # The payload arrives on stdin, so it is not an argument either. Each payload
  # is also kept, so an error response can be reported by its message.
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    data="${line#data: }"
    [[ "${data}" == "[DONE]" ]] && break
    [[ "${data}" == event:* ]] && continue
    body+="${data}"$'\n'
    __dybatpho_ai_stream_chunk "${data}" "${filter}"
  done < <(
    local curl_status=0
    command curl "${stream_args[@]}" \
      --header "Content-Type: application/json" \
      --header "Accept: text/event-stream" \
      ${headers[@]+"${headers[@]}"} \
      --data-binary @- \
      "${url}" <<< "${payload}" || curl_status=$?
    printf '%s' "${curl_status}" > "${curl_status_file}"
  )
  [[ -n "${stream_config}" ]] && rm -f "${stream_config}"

  local code="" protocol status rest curl_status
  while IFS=' ' read -r protocol status rest; do
    [[ "${protocol}" == HTTP/* ]] && code="${status%$'\r'}"
  done < "${header_file}"
  curl_status="$(< "${curl_status_file}")"
  rm -f "${header_file}" "${curl_status_file}"

  if [[ ! "${code}" =~ ^[0-9]{3}$ ]] || [[ "${curl_status:-1}" != 0 && "${code}" == 2* ]]; then
    local shown_url
    __dybatpho_network_redact_url_into shown_url "${url}"
    dybatpho::error "Error when access ${shown_url}"
    return 1
  fi
  if [[ "${code}" != 2* ]]; then
    local description message=""
    description=$(__dybatpho_network_get_http_code "${code}")
    # The message is best effort: an error body that is not JSON still gets
    # its status reported.
    message=$(dybatpho::json_get "${body}" '.error.message // ""' 2> /dev/null) || message=""
    dybatpho::error "ai: ${provider} answered ${description}${message:+: ${message}}"
    case "${code}" in
      3*) return 3 ;;
      4*) return 4 ;;
      *) return 5 ;;
    esac
  fi
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
# @internal
#######################################
function __dybatpho_ai_stream_chunk {
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
# @noargs
# @stdout JSON array, `[]` when nothing is registered
# @internal
#######################################
function __dybatpho_ai_tools_json {
  local tools='[]' name definition
  local -a tool_names=()
  readarray -t tool_names < <(dybatpho::ai_tool_list)
  for name in ${tool_names[@]+"${tool_names[@]}"}; do
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
# @internal
#######################################
function __dybatpho_ai_tool_invoke {
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
  prompt=$(__dybatpho_ai_redact "${prompt}")

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

  __dybatpho_ai_require_json
  local tools messages payload body step=1
  tools=$(__dybatpho_ai_tools_json)
  messages="[$(dybatpho::json_object role user content "${prompt}")]"

  while ((step <= DYBATPHO_AI_MAX_STEPS)); do
    __dybatpho_ai_budget_check
    local conversation
    conversation=$(dybatpho::json_object system "${system}" messages:json "${messages}")
    payload=$("__dybatpho_ai_payload_${provider}" "${conversation}" "${tools}" "")
    body=$(__dybatpho_ai_http "${provider}" "${payload}")
    local text
    __dybatpho_ai_response_into text "${provider}" "${body}"

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
      *) ;;
    esac

    local total
    total=$(dybatpho::json_get "${calls}" 'length')
    if [[ "${total}" == "0" ]]; then
      printf '%s\n' "${text}"
      return 0
    fi

    # Echo the assistant turn back verbatim so tool results line up with the
    # call ids the provider issued, then append one result per call.
    local assistant
    case "${provider}" in
      anthropic)
        local json_eval
        json_eval=$(dybatpho::json_eval "${body}" '.content')
        assistant=$(dybatpho::json_object \
          role assistant content:json "${json_eval}")
        ;;
      openai)
        assistant=$(dybatpho::json_eval "${body}" '.choices[0].message')
        ;;
      *) ;;
    esac
    messages=$(dybatpho::json_eval "${messages}" ". + [${assistant}]")

    local index=0 call_id call_name call_arguments result entry call
    local results='[]'
    while ((index < total)); do
      # One read per call rather than one per field. The arguments come last
      # because they are the only field that can span lines, and the marker
      # keeps their trailing newlines out of reach of the substitution.
      call=$(dybatpho::json_get "${calls}" \
        ".[${index}] | [.id, .name, .arguments] | map(tostring) | join(\"\\n\") + \"#\"")
      call="${call%#}"
      call_id="${call%%$'\n'*}"
      call="${call#*$'\n'}"
      call_name="${call%%$'\n'*}"
      call_arguments="${call#*$'\n'}"
      result=$(__dybatpho_ai_tool_invoke "${call_name}" "${call_arguments}")
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
        *) ;;
      esac
      index=$((index + 1))
    done

    if [[ "${provider}" == "anthropic" ]]; then
      local json_object
      json_object=$(dybatpho::json_object role user content:json "${results}")
      messages=$(dybatpho::json_eval "${messages}" \
        ". + [${json_object}]")
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
  __dybatpho_ai_state_cleanup_once
  local state
  __dybatpho_ai_state_read_into state
  case "${scope}" in
    last)
      local last_filter='"calls=\(.calls) input=\(.last_input) output=\(.last_output) '
      last_filter+='model=\(.last_model) stop_reason=\(.last_stop_reason)"'
      dybatpho::json_get "${state}" "${last_filter}"
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
# @arg $1 string Field name: `calls`, `total_input`, `total_output`, `last_input`, `last_output`, `last_model`, or
#   `last_stop_reason`
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
  __dybatpho_ai_state_cleanup_once
  local ai_state_read
  __dybatpho_ai_state_read_into ai_state_read
  dybatpho::json_get "${ai_state_read}" ".${field}"
}

#######################################
# @description Reset every usage counter and the call budget consumption.
# @noargs
# @exitcode 0 The counters are back to zero
#######################################
function dybatpho::ai_usage_reset {
  __dybatpho_ai_state_cleanup_once
  __dybatpho_ai_state_write \
    '{"calls":0,"total_input":0,"total_output":0,"last_input":0,"last_output":0,"last_model":"","last_stop_reason":""}'
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
# @tip This is a coarse net, not a compliance control; do not send regulated data to a third party provider on the
#   strength
#   of it
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
  # `\b` is a GNU extension that BSD sed rejects, so the word boundaries are
  # spelled out and captured. A captured boundary is consumed, which would skip
  # a match right after another one, so each rule loops until nothing changes.
  printf '%s\n' "${text}" | sed -E \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e ':ip' \
    -e 's/(^|[^[:alnum:]_])([0-9]{1,3}\.){3}[0-9]{1,3}($|[^[:alnum:]_])/\1<ip>\3/' \
    -e 't ip' \
    -e ':number' \
    -e 's/(^|[^[:alnum:]_])[0-9]{9,}($|[^[:alnum:]_])/\1<number>\2/' \
    -e 't number'
}
