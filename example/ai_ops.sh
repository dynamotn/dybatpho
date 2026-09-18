#!/usr/bin/env bash
# @file ai_ops.sh
# @brief Example showing the AI model utilities
# @description Demonstrates dybatpho::ai_provider, ai_model, ai_check, ai_ask,
#   ai_conversation_new/add/show, ai_chat, ai_json, ai_stream, the tool registry
#   with ai_run, plus ai_tokens_estimate, ai_budget, ai_usage and ai_redact.
#   DRY_RUN is on, so no request leaves the machine and no API key is needed.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules ai

dybatpho::register_common_handlers

# Nothing is sent anywhere; every call returns a placeholder response.
export DRY_RUN=true
export DYBATPHO_AI_PROVIDER=anthropic
export DYBATPHO_AI_API_KEY="example-key-not-used-in-dry-run"

function _demo_backend {
  dybatpho::header "BACKEND"
  dybatpho::print "Provider: $(dybatpho::ai_provider)"
  dybatpho::print "Model:    $(dybatpho::ai_model)"
  dybatpho::ai_check
  dybatpho::info "Backend is usable"
}

function _demo_ask {
  dybatpho::header "ONE-SHOT QUESTION"
  dybatpho::ai_ask "Summarize this deploy log in one line"
  dybatpho::ai_ask "Is this change risky?" "You are a terse release reviewer"
  dybatpho::info "Two questions answered"
}

function _demo_conversation {
  dybatpho::header "CONVERSATION"
  local chat
  dybatpho::ai_conversation_new chat "You are a Bash tutor"
  dybatpho::ai_chat "${chat}" "How do I trap SIGINT?" > /dev/null
  dybatpho::ai_chat "${chat}" "And clean up a temp file too?" > /dev/null
  dybatpho::ai_conversation_add "${chat}" user "Thanks"
  dybatpho::ai_conversation_show "${chat}"
  dybatpho::info "Conversation kept in ${chat}"
}

function _demo_structured {
  dybatpho::header "STRUCTURED OUTPUT"
  local schema
  schema='{"type":"object","properties":{"severity":{"type":"string","enum":["low","high"]}},"required":["severity"],"additionalProperties":false}'
  dybatpho::ai_json "Classify this alert: disk at 91 percent" "${schema}"
  dybatpho::info "Answer is valid JSON, so a script can branch on it"
}

function _demo_stream {
  dybatpho::header "STREAMING"
  dybatpho::ai_stream "Explain this stack trace"
  dybatpho::info "Streaming falls back to a buffered call when a backend cannot stream"
}

#######################################
# @description Example tool: report free space on the root filesystem.
# @arg $1 string Tool arguments as JSON, unused here
# @stdout Free space summary
#######################################
function _tool_disk_free {
  df -h / | tail -n 1
}

#######################################
# @description Example tool: report whether a path exists.
# @arg $1 string Tool arguments as JSON with a `path` field
# @stdout `exists` or `missing`
#######################################
function _tool_path_exists {
  local arguments="${1:-{\}}" path
  path=$(printf '%s' "${arguments}" | dybatpho::json_query - '.path // ""' -r)
  if dybatpho::is exist "${path}"; then
    printf 'exists\n'
  else
    printf 'missing\n'
  fi
}

function _demo_tools {
  dybatpho::header "TOOL USE"
  dybatpho::ai_tool_register disk_free \
    "Report free space on the root filesystem. Call this when asked about capacity." \
    '{"type":"object","properties":{},"additionalProperties":false}' \
    _tool_disk_free
  dybatpho::ai_tool_register path_exists \
    "Check whether a path exists. Call this before suggesting a file operation." \
    '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}' \
    _tool_path_exists
  dybatpho::print "Registered tools:"
  dybatpho::ai_tool_list
  dybatpho::ai_run "Are we about to run out of disk?"
  dybatpho::ai_tool_clear
  dybatpho::info "Tool registry cleared"
}

function _demo_guardrails {
  dybatpho::header "GUARDRAILS"
  dybatpho::print "Estimated tokens: $(dybatpho::ai_tokens_estimate 'a prompt of some length')"
  dybatpho::print "Redacted: $(dybatpho::ai_redact 'ping ops@example.com from 10.1.2.3 ticket 998877665544')"
  dybatpho::secret_register "super-secret-token"
  dybatpho::print "Masked secret: $(dybatpho::ai_redact 'token is super-secret-token')"
  dybatpho::ai_budget 100
  dybatpho::print "Usage: $(dybatpho::ai_usage total)"
  dybatpho::info "A budget stops a runaway loop before it bills"
}

function _main {
  _demo_backend
  _demo_ask
  _demo_conversation
  _demo_structured
  _demo_stream
  _demo_tools
  _demo_guardrails
  dybatpho::success "AI demo complete"
}

_main "$@"
