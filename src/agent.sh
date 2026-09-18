#!/usr/bin/env bash
# @file agent.sh
# @brief Utilities for making a script usable by an AI agent
# @description
#   Where `ai.sh` lets a script call a model, this module points the other way:
#   it makes a script something a model can drive safely. A tool that an agent
#   invokes has different needs from one a person types — it must say what it
#   did in a form that parses, it must never block on a prompt nobody will
#   answer, it must refuse dangerous work it was not explicitly cleared for,
#   and it must leave a record of what an agent made it do.
#
#   The module provides five things:
#
#   - **Detection** – is this run being driven by an agent, or by a person?
#   - **Structured results and errors** – JSON for agents, plain text for people,
#     from the same call site
#   - **Tool definitions** – Anthropic, OpenAI, and MCP tool schemas generated
#     from the same `cli.sh` option spec that drives the parser, so they cannot
#     drift apart
#   - **An allowlist gate** – interactive confirmation for people, an explicit
#     allowlist for agents, never a silent yes
#   - **An audit trail** – one JSON line per agent-initiated action
#
# @usage
#   ### When to use this module
#
#   Use `agent.sh` when you want to:
#
#   - expose an existing CLI to Claude, an MCP client, or a function-calling loop
#   - keep a script safe when something non-human is choosing its arguments
#   - return results an agent can branch on instead of prose it has to guess at
#   - know afterwards which actions an agent took, and which it was refused
#
#   ### Common patterns
#
#   #### Answer in the caller's language
#
#   ```bash
#   dybatpho::agent_result ok deployed=api version=1.4.2
#   # agent mode: {"status":"ok","deployed":"api","version":"1.4.2"}
#   # human mode: status=ok deployed=api version=1.4.2
#   ```
#
#   #### Publish the CLI as tools
#
#   ```bash
#   dybatpho::agent_tools _spec_root mytool anthropic  # Claude tool definitions
#   dybatpho::agent_tools _spec_root mytool openai     # function-calling schema
#   dybatpho::agent_mcp _spec_root mytool              # MCP tools/list payload
#   ```
#
#   #### Gate a dangerous action
#
#   ```bash
#   export DYBATPHO_AGENT_ALLOW="restart"
#   dybatpho::agent_confirm restart "Restart the API service" \
#     && systemctl restart api
#   ```
#
# @see
#   - `example/agent_ops.sh`
#   - `doc/cli.md` for the option spec these tool definitions are generated from
# @tip Agent mode is detected automatically; force it either way with `DYBATPHO_AGENT_MODE`
# @note Tool definitions are generated from the live option spec, so a new flag becomes a new tool parameter without a second edit
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_AGENT_MODE string `auto` (default), `on`, or `off`
# @env DYBATPHO_AGENT_ALLOW string Space separated actions an agent may perform, or `all`
# @env DYBATPHO_AGENT_AUDIT_FILE string Path of the JSON Lines audit log
# @env DYBATPHO_AGENT_ENV string Extra environment variable names that mark an agent run
DYBATPHO_AGENT_MODE=${DYBATPHO_AGENT_MODE:-auto}
DYBATPHO_AGENT_ALLOW=${DYBATPHO_AGENT_ALLOW:-}
DYBATPHO_AGENT_AUDIT_FILE=${DYBATPHO_AGENT_AUDIT_FILE:-}
DYBATPHO_AGENT_ENV=${DYBATPHO_AGENT_ENV:-}

# Environment variables set by the agent runtimes this module recognises. Any
# one of them being non-empty is taken as evidence that a model is driving.
DYBATPHO_AGENT_MARKERS="CLAUDECODE CLAUDE_CODE CLAUDE_AGENT ANTHROPIC_AGENT AI_AGENT AIDER_ACTIVE CURSOR_AGENT OPENAI_AGENT MCP_SERVER"

#######################################
# @description Fail loudly when no JSON backend is installed.
# @noargs
# @exitcode 0 `yq` or `jq` is available
# @exitcode 127 Stop the script because neither is installed
# @see dybatpho::json_object
#######################################
function __agent_require_json {
  __dybatpho_json_cmd > /dev/null
}

#######################################
# @description Return success when an agent runtime marker is present.
# @noargs
# @env DYBATPHO_AGENT_ENV string Additional variable names to treat as markers
# @exitcode 0 At least one marker variable is set and non-empty
# @exitcode 1 No marker is present
#######################################
function __agent_marker_present {
  local name
  for name in ${DYBATPHO_AGENT_MARKERS} ${DYBATPHO_AGENT_ENV}; do
    [[ -n "${!name-}" ]] && return 0
  done
  return 1
}

#######################################
# @description Print whether this run is being driven by an agent.
# `auto` looks for a known runtime marker; `on` and `off` skip detection.
# @example
#   if [[ "$(dybatpho::agent_mode)" == on ]]; then
#     dybatpho::agent_result ok
#   else
#     dybatpho::success "Done"
#   fi
#
# @noargs
# @env DYBATPHO_AGENT_MODE string Force the answer with `on` or `off`
# @stdout `on` or `off`
# @exitcode 0 The mode was printed
# @exitcode 1 Stop the script when the configured mode is unknown
#######################################
function dybatpho::agent_mode {
  case "${DYBATPHO_AGENT_MODE}" in
    on) printf 'on\n' ;;
    off) printf 'off\n' ;;
    auto)
      if __agent_marker_present; then
        printf 'on\n'
      else
        printf 'off\n'
      fi
      ;;
    *)
      dybatpho::die "dybatpho::agent_mode: Unknown mode '${DYBATPHO_AGENT_MODE}', expected auto, on or off"
      ;;
  esac
}

#######################################
# @description Return success when an agent is driving this run.
# @example
#   dybatpho::agent_detect && export DRY_RUN=true
#
# @noargs
# @exitcode 0 An agent is driving
# @exitcode 1 A person is driving
# @see dybatpho::agent_mode
#######################################
function dybatpho::agent_detect {
  [[ "$(dybatpho::agent_mode)" == "on" ]]
}

#######################################
# @description Report the outcome of an operation in the caller's language.
# Agents get one JSON object on stdout; people get an aligned key/value line.
# @example
#   dybatpho::agent_result ok service=api replicas=3
#   dybatpho::agent_result skipped reason="already up to date"
#
# @arg $1 string Status word, such as `ok`, `skipped`, or `failed`
# @arg $@ string Additional `key=value` pairs
# @stdout A JSON object in agent mode, `key=value` text otherwise
# @exitcode 0 The result was printed
# @exitcode 1 Missing status, or a field that is not `key=value`
# @tip Keep status words to a small fixed set so an agent can branch on them
#######################################
function dybatpho::agent_result {
  local status
  dybatpho::expect_args status -- "$@"
  shift

  local -a pairs=("$@")
  local field key value
  for field in "${pairs[@]}"; do
    [[ "${field}" == *=* ]] \
      || dybatpho::die "dybatpho::agent_result: Expected key=value, got '${field}'"
  done

  if ! dybatpho::agent_detect; then
    printf 'status=%s' "${status}"
    for field in "${pairs[@]}"; do
      printf ' %s' "${field}"
    done
    printf '\n'
    return 0
  fi

  local -a fields=(status "${status}")
  for field in "${pairs[@]}"; do
    key="${field%%=*}"
    value="${field#*=}"
    fields+=("${key}" "${value}")
  done
  dybatpho::json_object "${fields[@]}"
}

#######################################
# @description Report a failure with a machine-readable code and a fix hint.
# @example
#   dybatpho::agent_error missing_config "No config file at ${path}" \
#     "Run 'mytool init' first" || exit $?
#
# @arg $1 string Stable error code, lowercase with underscores
# @arg $2 string Human readable message
# @arg $3 string Optional hint describing how to recover
# @stdout A JSON object in agent mode; nothing otherwise
# @exitcode 1 Always, so the call can be chained with `||`
# @tip Error codes are a contract; keep them stable across releases so an agent can branch on them
#######################################
function dybatpho::agent_error {
  local code message hint
  dybatpho::expect_args code message -- "$@"
  hint="${3:-}"

  if dybatpho::agent_detect; then
    local -a fields=(status error code "${code}" message "${message}")
    dybatpho::is set "${hint}" && fields+=(hint "${hint}")
    dybatpho::json_object "${fields[@]}"
  else
    dybatpho::error "${message}"
    if dybatpho::is set "${hint}"; then
      dybatpho::print "Hint: ${hint}"
    fi
  fi
  return 1
}

#######################################
# @description Describe the environment an agent is operating in.
# @example
#   dybatpho::agent_context
#
# @noargs
# @stdout JSON object with platform, working directory, git state, loaded modules, and run flags
# @exitcode 0 The context was printed
# @tip Call this first in an agent-facing subcommand so the model knows what it is working with before it acts
#######################################
function dybatpho::agent_context {
  local branch="" repository=false
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    repository=true
    branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  fi
  local interactive=false
  dybatpho::is_interactive && interactive=true
  local dry_run=false
  dybatpho::is true "${DRY_RUN-}" && dry_run=true

  local agent=false
  dybatpho::agent_detect && agent=true

  local modules git
  modules=$(dybatpho::json_eval "$(dybatpho::json_string "${DYBATPHO_LOADED_MODULES}")" \
    'split(" ") | map(select(length > 0))')
  git=$(dybatpho::json_object repository:json "${repository}" branch "${branch}")

  dybatpho::json_object \
    os "$(uname -s)" \
    arch "$(uname -m)" \
    bash "${BASH_VERSION}" \
    cwd "${PWD}" \
    git:json "${git}" \
    modules:json "${modules}" \
    interactive:json "${interactive}" \
    dry_run:json "${dry_run}" \
    agent_mode:json "${agent}"
}

#######################################
# @description Return success when an action appears in the agent allowlist.
# @arg $1 string Action name
# @env DYBATPHO_AGENT_ALLOW string Space separated action names, or `all`
# @exitcode 0 The action is allowed
# @exitcode 1 The action is not allowed
#######################################
function __agent_allowed {
  local action
  dybatpho::expect_args action -- "$@"
  [[ " ${DYBATPHO_AGENT_ALLOW} " == *" all "* ]] && return 0
  [[ " ${DYBATPHO_AGENT_ALLOW} " == *" ${action} "* ]]
}

#######################################
# @description Gate an action behind confirmation, or behind an allowlist.
# A person is asked; an agent is checked against `DYBATPHO_AGENT_ALLOW` and
# refused when the action was not cleared in advance. Either way the decision
# is written to the audit log.
# @example
#   export DYBATPHO_AGENT_ALLOW="restart rollback"
#   dybatpho::agent_confirm restart "Restart the API service" || exit 0
#
# @arg $1 string Action name, matched against the allowlist
# @arg $2 string Optional description shown to a human
# @env DYBATPHO_AGENT_ALLOW string Actions an agent may perform
# @stdout A refusal object in agent mode when the action is not allowed
# @exitcode 0 The action is approved
# @exitcode 1 The action is refused
# @see dybatpho::confirm
# @tip Never add `all` to the allowlist in a production runbook; list the actions you actually intend to delegate
#######################################
function dybatpho::agent_confirm {
  local action description
  dybatpho::expect_args action -- "$@"
  description="${2:-Perform the ${action} action}"

  if ! dybatpho::agent_detect; then
    dybatpho::confirm "${description}?"
    return $?
  fi

  if __agent_allowed "${action}"; then
    dybatpho::agent_audit "${action}" "allowed: ${description}"
    return 0
  fi
  dybatpho::agent_audit "${action}" "refused: not in DYBATPHO_AGENT_ALLOW"
  dybatpho::json_object \
    status refused \
    code action_not_allowed \
    action "${action}" \
    message "Action ${action} is not permitted for an agent" \
    hint "Add ${action} to DYBATPHO_AGENT_ALLOW to permit it"
  return 1
}

#######################################
# @description Append one action to the audit log.
# Records are JSON Lines so a later run, or a human, can replay what an agent
# did without parsing prose.
# @example
#   export DYBATPHO_AGENT_AUDIT_FILE=/var/log/mytool-agent.jsonl
#   dybatpho::agent_audit deploy "version 1.4.2 to staging"
#
# @arg $1 string Action name
# @arg $2 string Optional detail
# @env DYBATPHO_AGENT_AUDIT_FILE string Destination path; nothing is written when empty
# @exitcode 0 The record was appended, or auditing is disabled
# @exitcode 1 Missing arguments
#######################################
function dybatpho::agent_audit {
  local action detail
  dybatpho::expect_args action -- "$@"
  detail="${2:-}"
  dybatpho::is set "${DYBATPHO_AGENT_AUDIT_FILE}" || return 0

  local directory
  directory=$(dirname "${DYBATPHO_AGENT_AUDIT_FILE}")
  mkdir -p "${directory}"
  dybatpho::json_object \
    timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    script "${0##*/}" \
    mode "$(dybatpho::agent_mode)" \
    action "${action}" \
    detail "${detail}" \
    >> "${DYBATPHO_AGENT_AUDIT_FILE}"
}

#######################################
# @description Print the audit log as readable lines.
# @example
#   dybatpho::agent_audit_show
#
# @noargs
# @env DYBATPHO_AGENT_AUDIT_FILE string Log to read
# @stdout One `timestamp action detail` line per record
# @exitcode 0 The log was printed, or there is nothing to print
#######################################
function dybatpho::agent_audit_show {
  dybatpho::is set "${DYBATPHO_AGENT_AUDIT_FILE}" || return 0
  dybatpho::is file "${DYBATPHO_AGENT_AUDIT_FILE}" || return 0
  local record
  # The log is JSON Lines, so each record is rendered on its own rather than
  # handing the whole file to a backend that expects one document.
  while IFS= read -r record; do
    dybatpho::is empty "${record}" && continue
    dybatpho::json_get "${record}" '[.timestamp, .action, .detail] | join(" ")'
  done < "${DYBATPHO_AGENT_AUDIT_FILE}"
}

#######################################
# @description Turn a CLI schema into a flat list of callable commands.
# Each command carries the options it accepts, with hidden entries dropped.
# The tree is walked here rather than in a filter because only one of the two
# JSON backends supports user-defined functions, and a schema can nest.
# @arg $1 string CLI schema JSON from `dybatpho::generate_schema`
# @stdout JSON array of `{path, description, options}` objects
#######################################
function __agent_flatten_schema {
  local schema
  dybatpho::expect_args schema -- "$@"
  __agent_flatten_command "${schema}" '[]' '[]'
}

#######################################
# @description Append one command and its subcommands to a flat list.
# @arg $1 string Command node JSON
# @arg $2 string Path of the parent command, as a JSON array
# @arg $3 string Accumulated list JSON
# @stdout The list with this command and its descendants appended
#######################################
function __agent_flatten_command {
  local node parent flattened
  dybatpho::expect_args node parent flattened -- "$@"

  local name path description options entry
  name=$(dybatpho::json_get "${node}" '.name')
  path=$(dybatpho::json_eval "${parent}" ". + [$(dybatpho::json_string "${name}")]")
  description=$(dybatpho::json_get "${node}" '.description')
  options=$(dybatpho::json_eval "${node}" '[.options[]? | select(.hidden != true)]')
  entry=$(dybatpho::json_object \
    path:json "${path}" description "${description}" options:json "${options}")
  flattened=$(dybatpho::json_eval "${flattened}" ". + [${entry}]")

  local total index=0
  total=$(dybatpho::json_get "${node}" '[.commands[]?] | length')
  while ((index < total)); do
    flattened=$(__agent_flatten_command \
      "$(dybatpho::json_eval "${node}" ".commands[${index}]")" \
      "${path}" "${flattened}")
    index=$((index + 1))
  done
  printf '%s\n' "${flattened}"
}

#######################################
# @description Build a JSON Schema object from a command's option list.
# Flags become booleans, parameters become strings, `choices:` becomes an
# `enum`, and `multiple:true` becomes an array of that item type.
# @arg $1 string Options array JSON
# @stdout JSON Schema object
#######################################
function __agent_options_schema {
  local options
  dybatpho::expect_args options -- "$@"

  local total index=0
  total=$(dybatpho::json_get "${options}" 'length')
  local properties='{}' required='[]'
  local option name key type description choices multiple property

  while ((index < total)); do
    option=$(dybatpho::json_eval "${options}" ".[${index}]")
    name=$(dybatpho::json_get "${option}" '.name')
    # The option name is lowercased here because the two JSON backends spell
    # their case conversion differently.
    key=$(dybatpho::lower "${name}")
    type=$(dybatpho::json_get "${option}" '.type')
    description=$(dybatpho::json_get "${option}" '.description')
    choices=$(dybatpho::json_get "${option}" '.choices // ""')
    multiple=$(dybatpho::json_get "${option}" '.multiple')

    local -a enum=()
    if dybatpho::is set "${choices}"; then
      enum=(enum:json "$(dybatpho::json_eval \
        "$(dybatpho::json_string "${choices}")" 'split(",")')")
    fi

    if [[ "${type}" == "flag" ]]; then
      property=$(dybatpho::json_object type boolean description "${description}")
    elif [[ "${multiple}" == "true" ]]; then
      local items
      if ((${#enum[@]} > 0)); then
        items=$(dybatpho::json_object type string "${enum[@]}")
      else
        items=$(dybatpho::json_object type string)
      fi
      property=$(dybatpho::json_object \
        type array description "${description}" items:json "${items}")
    else
      property=$(dybatpho::json_object \
        type string description "${description}" "${enum[@]}")
    fi

    properties=$(dybatpho::json_eval "${properties}" \
      ". + $(dybatpho::json_object "${key}:json" "${property}")")
    if [[ "$(dybatpho::json_get "${option}" '.required')" == "true" ]]; then
      required=$(dybatpho::json_eval "${required}" \
        ". + [$(dybatpho::json_string "${key}")]")
    fi
    index=$((index + 1))
  done

  dybatpho::json_object \
    type object \
    properties:json "${properties}" \
    required:json "${required}" \
    additionalProperties:json false
}

#######################################
# @description Generate tool definitions from a CLI option spec.
# The root command and every subcommand become one tool, named by joining the
# command path with underscores. Because the definitions come from the same
# spec the parser uses, a tool can never describe an option the CLI does not
# have.
# @example
#   dybatpho::agent_tools _spec_root mytool            # Anthropic shape
#   dybatpho::agent_tools _spec_root mytool openai     # function-calling shape
#
# @arg $1 string Spec function, the same one passed to `dybatpho::generate_from_spec`
# @arg $2 string Tool name prefix, default is the script name
# @arg $3 string Output shape, `anthropic` (default) or `openai`
# @stdout JSON array of tool definitions
# @exitcode 0 The definitions were printed
# @exitcode 1 Missing arguments or an unknown output shape
# @see dybatpho::generate_schema
# @tip Feed the result straight into the tool registry of the `ai` module, or into an API request; it needs no hand editing
#######################################
function dybatpho::agent_tools {
  local spec name format
  dybatpho::expect_args spec -- "$@"
  name="${2:-${0##*/}}"
  format="${3:-anthropic}"
  case "${format}" in
    anthropic | openai) ;;
    *) dybatpho::die "dybatpho::agent_tools: Unknown format '${format}', expected anthropic or openai" ;;
  esac
  local schema commands tools='[]' entry description input_schema tool_name definition
  schema=$(dybatpho::generate_schema "${spec}" "${name}")
  commands=$(__agent_flatten_schema "${schema}")

  local index=0 total
  total=$(dybatpho::json_get "${commands}" 'length')
  while ((index < total)); do
    entry=$(dybatpho::json_eval "${commands}" ".[${index}]")
    description=$(dybatpho::json_get "${entry}" '.description')
    tool_name=$(__agent_tool_name "${entry}")
    input_schema=$(__agent_options_schema "$(dybatpho::json_eval "${entry}" '.options')")
    if [[ "${format}" == "anthropic" ]]; then
      definition=$(dybatpho::json_object \
        name "${tool_name}" description "${description}" input_schema:json "${input_schema}")
    else
      local function_definition
      function_definition=$(dybatpho::json_object \
        name "${tool_name}" description "${description}" parameters:json "${input_schema}")
      definition=$(dybatpho::json_object type function function:json "${function_definition}")
    fi
    tools=$(dybatpho::json_eval "${tools}" ". + [${definition}]")
    index=$((index + 1))
  done
  printf '%s\n' "${tools}"
}

#######################################
# @description Derive a callable tool name from a flattened command entry.
# The command path is joined with underscores and anything a tool name may not
# contain is replaced, so a prefix with a space still yields a valid name.
# @arg $1 string Flattened command entry JSON
# @stdout Tool name
#######################################
function __agent_tool_name {
  local entry
  dybatpho::expect_args entry -- "$@"
  local path
  path=$(dybatpho::json_get "${entry}" '.path | join("_")')
  printf '%s' "${path}" | tr -c 'a-zA-Z0-9_' '_'
}

#######################################
# @description Generate an MCP `tools/list` payload for a CLI option spec.
# Each tool carries the command line it maps to under `x-dybatpho-command`, so
# a thin MCP server can dispatch without a second source of truth.
# @example
#   dybatpho::agent_mcp _spec_root mytool > mytool-mcp.json
#
# @arg $1 string Spec function
# @arg $2 string Server and tool name prefix, default is the script name
# @arg $3 string Command an MCP server should execute, default is the script path
# @stdout JSON object with `name`, `version`, and a `tools` array
# @exitcode 0 The payload was printed
# @exitcode 1 Missing arguments
# @see dybatpho::agent_tools
# @note This is the tool manifest, not a running server; point your MCP host at it and dispatch with the recorded command
#######################################
function dybatpho::agent_mcp {
  local spec name command
  dybatpho::expect_args spec -- "$@"
  name="${2:-${0##*/}}"
  command="${3:-$0}"
  local schema commands tools='[]' entry description input_schema tool_name argv definition
  schema=$(dybatpho::generate_schema "${spec}" "${name}")
  commands=$(__agent_flatten_schema "${schema}")

  local index=0 total
  total=$(dybatpho::json_get "${commands}" 'length')
  while ((index < total)); do
    entry=$(dybatpho::json_eval "${commands}" ".[${index}]")
    description=$(dybatpho::json_get "${entry}" '.description')
    tool_name=$(__agent_tool_name "${entry}")
    input_schema=$(__agent_options_schema "$(dybatpho::json_eval "${entry}" '.options')")
    # The first path element is the root name, which the command already names.
    argv=$(dybatpho::json_eval "${entry}" \
      "[$(dybatpho::json_string "${command}")] + (.path[1:])")
    definition=$(dybatpho::json_object \
      name "${tool_name}" \
      description "${description}" \
      inputSchema:json "${input_schema}" \
      x-dybatpho-command:json "${argv}")
    tools=$(dybatpho::json_eval "${tools}" ". + [${definition}]")
    index=$((index + 1))
  done

  dybatpho::json_object name "${name}" version 1.0.0 tools:json "${tools}"
}
