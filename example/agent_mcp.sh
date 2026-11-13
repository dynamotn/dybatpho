#!/usr/bin/env bash
# @file agent_mcp.sh
# @brief Example showing a script served as MCP tools over stdio
# @description Demonstrates dybatpho::agent_mcp_serve. `agent_mcp.sh mcp` is a
#   complete MCP server: register it with Claude Code as
#   `claude mcp add example -- /path/to/agent_mcp.sh mcp`. Run without
#   arguments, the example plays a host itself: it pipes a scripted session
#   into its own server and prints each reply.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules agent json

dybatpho::register_common_handlers

#######################################
# @description Option spec of the tool this example serves.
# @noargs
#######################################
function _spec_root {
  dybatpho::opts::setup "Manage the example service" - action:"dybatpho::generate_help _spec_root"
  dybatpho::opts::cmd greet _spec_greet
  dybatpho::opts::cmd restart _spec_restart
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_root"
}

#######################################
# @description Option spec for the `greet` subcommand.
# @noargs
#######################################
function _spec_greet {
  dybatpho::opts::setup "Greet someone by name" GREET_ARGS action:"_run_greet"
  dybatpho::opts::flag "Shout the greeting" SHOUT --shout
  dybatpho::opts::param "Greeting word" GREETING --greeting
  dybatpho::opts::arg "Who to greet" WHO
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_greet"
}

#######################################
# @description Option spec for the `restart` subcommand.
# @noargs
#######################################
function _spec_restart {
  dybatpho::opts::setup "Restart a service" RESTART_ARGS action:"_run_restart"
  dybatpho::opts::param "Service to restart" SERVICE --service choices:api,worker required:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_restart"
}

# @description Action of `greet`: reply with a structured result.
# @noargs
function _run_greet {
  local text="${GREETING:-Hello}, ${WHO}"
  dybatpho::is true "${SHOUT}" && text="${text^^}!"
  dybatpho::agent_result ok greeting="${text}"
}

# @description Action of `restart`: refused unless an agent was cleared for it.
# @noargs
function _run_restart {
  dybatpho::agent_confirm restart "Restart ${SERVICE}" || return 1
  dybatpho::agent_result ok restarted="${SERVICE}"
}

# @description Play an MCP host: send a scripted session to the server, one
#   request per line, and print each reply. The notification gets no reply.
# @noargs
function _demo_session {
  dybatpho::header "MCP SESSION"
  local requests replies reply
  dybatpho::create_temp requests ".jsonl" "agent_mcp"
  local init='"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"demo","version":"1"}'
  local call='"method":"tools/call","params":{"name"'
  {
    printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{%s}}\n' "${init}"
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    printf '{"jsonrpc":"2.0","id":3,%s:"example_greet","arguments":{"who":"-the world","shout":true}}}\n' "${call}"
    printf '{"jsonrpc":"2.0","id":4,%s:"example_restart","arguments":{"service":"api"}}}\n' "${call}"
    printf '{"jsonrpc":"2.0","id":5,%s:"example_greet","arguments":{"who":"x","loud":true}}}\n' "${call}"
    printf '{"jsonrpc":"2.0","id":6,%s:"example","arguments":{}}}\n' "${call}"
  } > "${requests}"
  replies=$("$0" mcp < "${requests}")
  while IFS= read -r reply; do
    dybatpho::json_query - '{id, result, error}' -c <<< "${reply}"
  done <<< "${replies}"
  # The root tool runs this script with no arguments; it must print help, not
  # start this demo again inside the server.
  [[ "${replies}" != *"MCP SESSION"* ]] || dybatpho::die "The root tool ran the demo"
  dybatpho::info "The restart was refused: DYBATPHO_AGENT_ALLOW does not list it"
}

# @description Run the demo session.
# @noargs
function _main {
  unset DYBATPHO_AGENT_ALLOW
  _demo_session
  dybatpho::success "MCP demo complete"
}

# `mcp` serves the tools; any other command line is the tool itself. The entry
# point stays out of the spec, so the server does not list itself as a tool.
case "${1:-}" in
  mcp)
    dybatpho::agent_mcp_serve _spec_root example "$0"
    exit 0
    ;;
  "")
    # A tool call always runs with DYBATPHO_AGENT_MODE=on: that is the root
    # tool, which gets help. A person running the file gets the demo.
    if [[ "${DYBATPHO_AGENT_MODE:-}" == on ]]; then
      dybatpho::generate_help _spec_root
    else
      _main
    fi
    ;;
  *) dybatpho::generate_from_spec _spec_root "$@" ;;
esac
