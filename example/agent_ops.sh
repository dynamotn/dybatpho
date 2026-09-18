#!/usr/bin/env bash
# @file agent_ops.sh
# @brief Example showing how to make a script usable by an AI agent
# @description Demonstrates dybatpho::agent_mode, agent_detect, agent_result,
#   agent_error, agent_context, agent_confirm, agent_audit, agent_audit_show,
#   agent_tools and agent_mcp. The same calls are run twice, once as a person
#   and once as an agent, so the difference in output is visible side by side.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules agent json

dybatpho::register_common_handlers

#######################################
# @description Option spec for the imaginary tool this example exposes.
# @noargs
#######################################
function _spec_root {
  dybatpho::opts::setup "Manage the example service" ROOT_ARGS action:"_run_root"
  dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
  dybatpho::opts::param "Target environment" TARGET --target \
    choices:dev,staging,prod required:true
  dybatpho::opts::param "Components to act on" COMPONENT --component \
    choices:api,worker,web multiple:true
  dybatpho::opts::param "Internal switch" INTERNAL --internal hidden:true
  dybatpho::opts::cmd deploy _spec_deploy
  dybatpho::opts::cmd rollback _spec_rollback
}

#######################################
# @description Option spec for the `deploy` subcommand.
# @noargs
#######################################
function _spec_deploy {
  dybatpho::opts::setup "Deploy a version to the target environment" DEPLOY_ARGS action:"_run_deploy"
  dybatpho::opts::param "Version tag to deploy" TAG --tag required:true
}

#######################################
# @description Option spec for the `rollback` subcommand.
# @noargs
#######################################
function _spec_rollback {
  dybatpho::opts::setup "Roll back to the previous version" ROLLBACK_ARGS action:"_run_rollback"
  dybatpho::opts::flag "Skip the health check" FORCE --force
}

#######################################
# @description Run the same reporting calls in whichever mode is active.
# @noargs
#######################################
function _demo_reporting {
  dybatpho::print "Mode: $(dybatpho::agent_mode)"
  dybatpho::agent_result ok service=api version=1.4.2
  dybatpho::agent_result skipped reason="already up to date"
  dybatpho::agent_error missing_config "No config file at /etc/example.yaml" \
    "Run 'example init' to create one" || true
}

function _demo_human {
  dybatpho::header "AS A PERSON"
  DYBATPHO_AGENT_MODE=off _demo_reporting
  dybatpho::info "Plain text, meant to be read"
}

function _demo_agent {
  dybatpho::header "AS AN AGENT"
  DYBATPHO_AGENT_MODE=on _demo_reporting
  dybatpho::info "One JSON object per line, meant to be parsed"
}

function _demo_context {
  dybatpho::header "CONTEXT"
  DYBATPHO_AGENT_MODE=on dybatpho::agent_context
  dybatpho::info "An agent can read the environment before it acts"
}

function _demo_gate {
  dybatpho::header "ALLOWLIST GATE"
  export DYBATPHO_AGENT_MODE=on
  export DYBATPHO_AGENT_ALLOW="deploy"
  dybatpho::create_temp DYBATPHO_AGENT_AUDIT_FILE ".jsonl" "agent_audit"
  export DYBATPHO_AGENT_AUDIT_FILE

  if dybatpho::agent_confirm deploy "Deploy version 1.4.2 to staging"; then
    dybatpho::print "deploy was cleared in advance, so it runs"
  fi
  if ! dybatpho::agent_confirm wipe "Delete every volume"; then
    dybatpho::print "wipe was never cleared, so it is refused"
  fi

  dybatpho::header "AUDIT TRAIL"
  dybatpho::agent_audit_show
  unset DYBATPHO_AGENT_MODE DYBATPHO_AGENT_ALLOW
  dybatpho::info "Every decision is recorded, approvals and refusals alike"
}

function _demo_tools {
  dybatpho::header "TOOL DEFINITIONS"
  dybatpho::print "Anthropic tool names:"
  dybatpho::agent_tools _spec_root example anthropic \
    | dybatpho::json_query - '.[].name' -r
  dybatpho::print "OpenAI function names:"
  dybatpho::agent_tools _spec_root example openai \
    | dybatpho::json_query - '.[].function.name' -r
  dybatpho::print "MCP manifest:"
  dybatpho::agent_mcp _spec_root example /usr/local/bin/example \
    | dybatpho::json_pretty -
  dybatpho::info "All three come from the same option spec the parser uses"
}

function _main {
  _demo_human
  _demo_agent
  _demo_context
  _demo_gate
  _demo_tools
  dybatpho::success "Agent demo complete"
}

_main "$@"
