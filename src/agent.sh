# shellcheck shell=bash
# The library returns its values on stdout, so its own functions are called inside `$(...)` by design. Every call
# here that can stop the script was reviewed: it is fixed, or listed with its reason in test/die-in-substitution.allow,
# which test/conventions.bats enforces.
# dyshellint disable=BSG047 # reviewed in test/die-in-substitution.allow
# @file agent.sh
# @brief Utilities for making a script usable by an AI agent
# @namespace dybatpho
# @description
#   Where `ai.sh` lets a script call a model, this module points the other way:
#   it makes a script something a model can drive safely. A tool that an agent
#   invokes has different needs from one a person types — it must say what it
#   did in a form that parses, it must never block on a prompt nobody will
#   answer, it must refuse dangerous work it was not explicitly cleared for,
#   and it must leave a record of what an agent made it do.
#
#   The module provides six things:
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
#   - **An MCP server** – the same tools served over stdio, so `mytool mcp` can
#     be registered with Claude Code or Claude Desktop as it is
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
#   #### Serve the CLI to an MCP host
#
#   ```bash
#   [[ "${1:-}" == mcp ]] && { dybatpho::agent_mcp_serve _spec_root mytool "$0"; exit; }
#   ```
#
#   Register it with `claude mcp add mytool -- /usr/local/bin/mytool mcp`, or in
#   Claude Desktop's `claude_desktop_config.json`:
#
#   ```json
#   {"mcpServers": {"mytool": {"command": "/usr/local/bin/mytool", "args": ["mcp"]}}}
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
#   - `example/agent_mcp.sh`
#   - `docs/cli.md` for the option spec these tool definitions are generated from
# @tip Agent mode is detected automatically; force it either way with `DYBATPHO_AGENT_MODE`
# @tip Tool definitions are generated from the live option spec, so a new flag becomes a new tool parameter without a
#   second edit
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_AGENT_MODE string [default: auto] `auto`, `on`, or `off`
# @env DYBATPHO_AGENT_ALLOW string Space separated actions an agent may perform, or `all`
# @env DYBATPHO_AGENT_AUDIT_FILE string Path of the JSON Lines audit log
# @env DYBATPHO_AGENT_ENV string Extra environment variable names that mark an agent run
DYBATPHO_AGENT_MODE=${DYBATPHO_AGENT_MODE:-auto}
DYBATPHO_AGENT_ALLOW=${DYBATPHO_AGENT_ALLOW:-}
DYBATPHO_AGENT_AUDIT_FILE=${DYBATPHO_AGENT_AUDIT_FILE:-}
DYBATPHO_AGENT_ENV=${DYBATPHO_AGENT_ENV:-}
# @env DYBATPHO_AGENT_MCP_TIMEOUT number [default: 0] Seconds an MCP tool call may run, `0` for no limit
DYBATPHO_AGENT_MCP_TIMEOUT=${DYBATPHO_AGENT_MCP_TIMEOUT:-0}

# MCP protocol versions `dybatpho::agent_mcp_serve` speaks, newest first.
__DYBATPHO_AGENT_MCP_VERSIONS='"2025-06-18" "2025-03-26" "2024-11-05"'

# Environment variables set by the agent runtimes this module recognises. Any
# one of them being non-empty is taken as evidence that a model is driving.
DYBATPHO_AGENT_MARKERS="CLAUDECODE CLAUDE_CODE CLAUDE_AGENT ANTHROPIC_AGENT AI_AGENT"
DYBATPHO_AGENT_MARKERS+=" AIDER_ACTIVE CURSOR_AGENT OPENAI_AGENT MCP_SERVER"

#######################################
# @description Return success when an agent runtime marker is present.
# @noargs
# @env DYBATPHO_AGENT_ENV string Additional variable names to treat as markers
# @exitcode 0 At least one marker variable is set and non-empty
# @exitcode 1 No marker is present
# @internal
#######################################
function __dybatpho_agent_marker_present {
  # Split without globbing, and a word that is not a variable name skipped: a
  # `*` matched file names, and one bad name ended detection with a Bash error.
  local name
  local -a names=()
  read -r -a names <<< "${DYBATPHO_AGENT_MARKERS} ${DYBATPHO_AGENT_ENV}"
  for name in ${names[@]+"${names[@]}"}; do
    [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
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
  local mode
  __dybatpho_agent_mode_into mode
  printf '%s\n' "${mode}"
}

#######################################
# @description Work out the agent mode into a variable.
#   The callers that branch on the mode use this rather than
#   `$(dybatpho::agent_mode)`: an unknown `DYBATPHO_AGENT_MODE` has to stop the
#   script, and from inside a command substitution the stop would end only the
#   subshell while the caller carried on as though a person were driving.
# @arg $1 string Name of the variable receiving `on` or `off`
# @set The named variable
# @exitcode 1 Stop the script when the configured mode is unknown
# @internal
#######################################
function __dybatpho_agent_mode_into {
  local __dybatpho_agent_mode_var
  dybatpho::expect_args __dybatpho_agent_mode_var -- "$@"
  local -n __dybatpho_agent_mode_out="${__dybatpho_agent_mode_var}"
  case "${DYBATPHO_AGENT_MODE}" in
    on) __dybatpho_agent_mode_out=on ;;
    off) __dybatpho_agent_mode_out=off ;;
    auto)
      if __dybatpho_agent_marker_present; then
        __dybatpho_agent_mode_out=on
      else
        __dybatpho_agent_mode_out=off
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
#   dybatpho::agent_detect && DYBATPHO_DRY_RUN=true
#
# @noargs
# @exitcode 0 An agent is driving
# @exitcode 1 A person is driving
# @see dybatpho::agent_mode
#######################################
function dybatpho::agent_detect {
  local mode
  __dybatpho_agent_mode_into mode
  [[ "${mode}" == "on" ]]
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

  # Expanded with `+`: a bare `"${pairs[@]}"` of an empty array is an unbound
  # variable to Bash 4.3 under `set -u`, so a result with no fields stopped it.
  local -a pairs=("$@")
  local field key value
  for field in ${pairs[@]+"${pairs[@]}"}; do
    [[ "${field}" == *=* ]] \
      || dybatpho::die "dybatpho::agent_result: Expected key=value, got '${field}'"
  done

  if ! dybatpho::agent_detect; then
    printf 'status=%s' "${status}"
    for field in ${pairs[@]+"${pairs[@]}"}; do
      printf ' %s' "${field}"
    done
    printf '\n'
    return 0
  fi

  local -a fields=(status "${status}")
  for field in ${pairs[@]+"${pairs[@]}"}; do
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
# @arg $3 string? Hint describing how to recover
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
  if git rev-parse --is-inside-work-tree &> /dev/null; then
    repository=true
    branch=$(git rev-parse --abbrev-ref HEAD 2> /dev/null || printf '')
  fi
  local interactive=false
  dybatpho::is_interactive && interactive=true
  local dry_run=false
  dybatpho::is true "${DYBATPHO_DRY_RUN:-${DRY_RUN:-}}" && dry_run=true

  local agent=false
  dybatpho::agent_detect && agent=true

  local modules git loaded
  # shellcheck disable=SC2154 # declared by `init.sh`
  loaded=$(dybatpho::json_string "${DYBATPHO_LOADED_MODULES}")
  modules=$(dybatpho::json_eval "${loaded}" 'split(" ") | map(select(length > 0))')
  git=$(dybatpho::json_object repository:json "${repository}" branch "${branch}")

  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  dybatpho::json_object os "${os}" \
    arch "${arch}" \
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
# @internal
#######################################
function __dybatpho_agent_allowed {
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
# @arg $2 string? Description shown to a human
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

  if __dybatpho_agent_allowed "${action}"; then
    dybatpho::agent_audit "${action}" "allowed: ${description}"
    return 0
  fi
  dybatpho::agent_audit "${action}" "refused: not in DYBATPHO_AGENT_ALLOW"
  dybatpho::json_object status refused \
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
# @arg $2 string? Detail
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
  local agent_mode
  __dybatpho_agent_mode_into agent_mode
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  dybatpho::json_object timestamp "${timestamp}" \
    script "${0##*/}" \
    mode "${agent_mode}" \
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
  # handing the whole file to a filter that expects one document.
  # A log trimmed or written by another tool can end without a newline, and
  # `read` fails on that last line even though it filled the variable.
  while IFS= read -r record || [[ -n "${record}" ]]; do
    dybatpho::is empty "${record}" && continue
    dybatpho::json_get "${record}" '[.timestamp, .action, .detail] | join(" ")'
  done < "${DYBATPHO_AGENT_AUDIT_FILE}" # kcov(skip) - a loop's `done` is never traced
}

#######################################
# @description Turn a CLI schema into a flat list of callable commands.
# Each command carries the options it accepts, with hidden entries dropped.
# The whole tree is walked by one recursive `jq` filter, depth first, so a
# command is listed before its subcommands.
# @arg $1 string CLI schema JSON from `dybatpho::generate_schema`
# Display options such as `--help` are dropped too: they print and exit, so
# they are no parameter a tool can be called with.
# @stdout JSON array of `{path, description, options, arguments}` objects
# @internal
#######################################
function __dybatpho_agent_flatten_schema {
  local schema
  dybatpho::expect_args schema -- "$@"
  # `$parent` and `$path` are variables of the filter, not of the shell.
  # kcov(disabled) - a jq program spread over lines: data, not Bash commands
  # shellcheck disable=SC2016
  local program='
    def flat($parent):
      ($parent + [(.name | tostring)]) as $path
      | {"path": $path, "description": (.description | tostring),
         "options": [.options[]? | select(.hidden != true and .type != "disp")],
         "arguments": [.arguments[]?]},
        (.commands[]? | flat($path));
    [flat([])]'
  # kcov(enabled)
  dybatpho::json_eval "${schema}" "${program}"
}

#######################################
# @description Build the filter that renders a command entry's options and
#   positional arguments as a JSON Schema object, in one pass over the entry.
#   A positional argument is a string, or an array of strings when variadic.
#   Each option became a property through several reads and a growing document
#   rewritten per option, around ten processes each. A `jq` filter does it in
#   the one read that renders the whole tool.
# @arg $1 string Name of the variable receiving the filter
# @set The named variable, an expression over one entry
# @internal
#######################################
function __dybatpho_agent_options_filter_into {
  local __dybatpho_agent_opts_var
  dybatpho::expect_args __dybatpho_agent_opts_var -- "$@"
  local -n __dybatpho_agent_opts_out="${__dybatpho_agent_opts_var}"
  local enum='((select(((.choices // "") | tostring) != "") | {"enum": (.choices | split(","))}) // {})'
  local description='"description": (.description | tostring)'
  # kcov(disabled) - jq filters spread over lines: data, not Bash commands
  local property="(\$opt | (select(.type == \"flag\") | {\"type\": \"boolean\", ${description}})
    // (select(.multiple == true)
      | {\"type\": \"array\", ${description}, \"items\": ({\"type\": \"string\"} + ${enum})})
    // ({\"type\": \"string\", ${description}} + ${enum}))"
  local argument="(\$arg | (select(.variadic == true)
      | {\"type\": \"array\", ${description}, \"items\": {\"type\": \"string\"}})
    // {\"type\": \"string\", ${description}})"
  __dybatpho_agent_opts_out="{\"type\": \"object\",
    \"properties\": (reduce .options[] as \$opt ({};
      . + {((\$opt | .name | tostring) | ascii_downcase): ${property}})
      + reduce .arguments[]? as \$arg ({};
      . + {((\$arg | .name | tostring) | ascii_downcase): ${argument}})),
    \"required\": [.options[], .arguments[]? | select(.required == true)
      | (.name | tostring | ascii_downcase)],
    \"additionalProperties\": false}"
  # kcov(enabled)
}

#######################################
# @description Render every flattened command as a tool definition.
#   The tool names are read for all commands at once and made safe here, a byte
#   at a time as `tr` did; each definition is then one read of its entry.
# @arg $1 string Name of the array receiving one compact definition per command
# @arg $2 string Flattened command list JSON
# @arg $3 string Template of the definition, with `@NAME@` and `@SCHEMA@`
#   standing for the tool name literal and the input schema expression
# @set The named array
# @internal
#######################################
function __dybatpho_agent_each_tool_into {
  local __dybatpho_agent_each_var __dybatpho_agent_each_commands __dybatpho_agent_each_template
  dybatpho::expect_args __dybatpho_agent_each_var __dybatpho_agent_each_commands \
    __dybatpho_agent_each_template -- "$@"
  local -n __dybatpho_agent_each_out="${__dybatpho_agent_each_var}"
  local __dybatpho_agent_each_schema
  __dybatpho_agent_options_filter_into __dybatpho_agent_each_schema

  local __dybatpho_agent_each_names
  __dybatpho_agent_each_names=$(dybatpho::json_get "${__dybatpho_agent_each_commands}" '.[] | .path | join("_")')
  local -a __dybatpho_agent_each_list=()
  [[ -z "${__dybatpho_agent_each_names}" ]] \
    || mapfile -t __dybatpho_agent_each_list <<< "${__dybatpho_agent_each_names}"

  local __dybatpho_agent_each_index=0 __dybatpho_agent_each_name __dybatpho_agent_each_filter
  local __dybatpho_agent_each_jq __dybatpho_agent_each_def
  for __dybatpho_agent_each_name in ${__dybatpho_agent_each_list[@]+"${__dybatpho_agent_each_list[@]}"}; do
    __dybatpho_agent_tool_name_into __dybatpho_agent_each_name "${__dybatpho_agent_each_name}"
    __dybatpho_agent_each_filter="${__dybatpho_agent_each_template//@NAME@/"\"${__dybatpho_agent_each_name}\""}"
    __dybatpho_agent_each_filter="${__dybatpho_agent_each_filter//@SCHEMA@/"${__dybatpho_agent_each_schema}"}"
    __dybatpho_agent_each_jq=".[${__dybatpho_agent_each_index}] | (${__dybatpho_agent_each_filter}) | @json"
    __dybatpho_agent_each_def=$(dybatpho::json_get "${__dybatpho_agent_each_commands}" "${__dybatpho_agent_each_jq}")
    __dybatpho_agent_each_out+=("${__dybatpho_agent_each_def}")
    __dybatpho_agent_each_index=$((__dybatpho_agent_each_index + 1))
  done
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
# @arg $2 string? Tool name prefix, default is the script name
# @arg $3 string [default: anthropic] Output shape, `anthropic` or `openai`
# @stdout JSON array of tool definitions
# @exitcode 0 The definitions were printed
# @exitcode 1 Missing arguments or an unknown output shape
# @see dybatpho::generate_schema
# @tip Feed the result straight into the tool registry of the `ai` module, or into an API request; it needs no hand
#   editing
#######################################
function dybatpho::agent_tools {
  local __dybatpho_agent_tools_spec __dybatpho_agent_tools_name __dybatpho_agent_tools_format
  dybatpho::expect_args __dybatpho_agent_tools_spec -- "$@"
  __dybatpho_agent_tools_name="${2:-${0##*/}}"
  __dybatpho_agent_tools_format="${3:-anthropic}"
  case "${__dybatpho_agent_tools_format}" in
    anthropic | openai) ;; # kcov(skip) - a case arm has no command to fire on
    *)
      # `dybatpho::die` exits, so "dybatpho::agent_tools rejects an unknown
      # format" runs these under `run`.
      local expected="expected anthropic or openai"                                                         # kcov(skip)
      dybatpho::die "dybatpho::agent_tools: Unknown format '${__dybatpho_agent_tools_format}', ${expected}" # kcov(skip)
      ;;
  esac
  local __dybatpho_agent_tools_schema __dybatpho_agent_tools_commands
  local -a __dybatpho_agent_tools_args=("${__dybatpho_agent_tools_spec}" "${__dybatpho_agent_tools_name}")
  __dybatpho_agent_tools_schema=$(dybatpho::generate_schema "${__dybatpho_agent_tools_args[@]}")
  __dybatpho_agent_tools_commands=$(__dybatpho_agent_flatten_schema "${__dybatpho_agent_tools_schema}")

  local __dybatpho_agent_tools_template
  if [[ "${__dybatpho_agent_tools_format}" == "anthropic" ]]; then
    # kcov(disabled) - a jq template spread over lines: data, not Bash commands
    __dybatpho_agent_tools_template='{"name": @NAME@, "description": (.description | tostring),
      "input_schema": (@SCHEMA@)}'
    # kcov(enabled)
  else
    # kcov(disabled) - a jq template spread over lines: data, not Bash commands
    __dybatpho_agent_tools_template='{"type": "function", "function": {"name": @NAME@,
      "description": (.description | tostring), "parameters": (@SCHEMA@)}}'
    # kcov(enabled)
  fi
  local -a __dybatpho_agent_tools_definitions=()
  __dybatpho_agent_each_tool_into __dybatpho_agent_tools_definitions "${__dybatpho_agent_tools_commands}" \
    "${__dybatpho_agent_tools_template}"
  (
    IFS=,
    printf '[%s]\n' "${__dybatpho_agent_tools_definitions[*]-}"
  )
}

#######################################
# @description Derive a callable tool name from a flattened command entry.
# The command path is joined with underscores and anything a tool name may not
# contain is replaced, so a prefix with a space still yields a valid name.
# @arg $1 string Name of the variable receiving the tool name
# @arg $2 string Command path joined with underscores
# @set The named variable
# @internal
#######################################
function __dybatpho_agent_tool_name_into {
  local __dybatpho_agent_tool_name_var __dybatpho_agent_tool_name_path
  dybatpho::expect_args __dybatpho_agent_tool_name_var __dybatpho_agent_tool_name_path -- "$@"
  local -n __dybatpho_agent_tool_name_out="${__dybatpho_agent_tool_name_var}"
  # Byte by byte, as `tr` replaced them: a character outside ASCII becomes one
  # underscore per byte it takes, whatever the locale.
  local LC_ALL=C
  __dybatpho_agent_tool_name_out="${__dybatpho_agent_tool_name_path//[^a-zA-Z0-9_]/_}"
}

#######################################
# @description Generate an MCP `tools/list` payload for a CLI option spec.
# Each tool carries the command line it maps to under `x-dybatpho-command`, so
# a thin MCP server can dispatch without a second source of truth.
# @example
#   dybatpho::agent_mcp _spec_root mytool > mytool-mcp.json
#
# @arg $1 string Spec function
# @arg $2 string? Server and tool name prefix, default is the script name
# @arg $3 string? Command an MCP server should execute, default is the script path
# @stdout JSON object with `name`, `version`, and a `tools` array
# @exitcode 0 The payload was printed
# @exitcode 1 Missing arguments
# @see dybatpho::agent_tools
# @see dybatpho::agent_mcp_serve
# @note This is the tool manifest; `dybatpho::agent_mcp_serve` serves the same tools to an MCP host
#######################################
function dybatpho::agent_mcp {
  local __dybatpho_agent_mcp_spec __dybatpho_agent_mcp_name __dybatpho_agent_mcp_command
  dybatpho::expect_args __dybatpho_agent_mcp_spec -- "$@"
  __dybatpho_agent_mcp_name="${2:-${0##*/}}"
  __dybatpho_agent_mcp_command="${3:-$0}"
  local __dybatpho_agent_mcp_schema __dybatpho_agent_mcp_commands
  __dybatpho_agent_mcp_schema=$(dybatpho::generate_schema "${__dybatpho_agent_mcp_spec}" "${__dybatpho_agent_mcp_name}")
  __dybatpho_agent_mcp_commands=$(__dybatpho_agent_flatten_schema "${__dybatpho_agent_mcp_schema}")

  # The first path element is the root name, which the command already names.
  local __dybatpho_agent_mcp_command_json
  __dybatpho_agent_mcp_command_json=$(dybatpho::json_string "${__dybatpho_agent_mcp_command}")
  # kcov(disabled) - a jq template spread over lines: data, not Bash commands
  local __dybatpho_agent_mcp_template='{"name": @NAME@, "description": (.description | tostring),
    "inputSchema": (@SCHEMA@), "x-dybatpho-command": (['"${__dybatpho_agent_mcp_command_json}"'] + (.path | .[1:]))}'
  # kcov(enabled)
  local -a __dybatpho_agent_mcp_definitions=()
  __dybatpho_agent_each_tool_into __dybatpho_agent_mcp_definitions "${__dybatpho_agent_mcp_commands}" \
    "${__dybatpho_agent_mcp_template}"
  local __dybatpho_agent_mcp_tools
  __dybatpho_agent_mcp_tools="[$(
    IFS=,
    printf '%s' "${__dybatpho_agent_mcp_definitions[*]-}"
  )]"
  dybatpho::json_object name "${__dybatpho_agent_mcp_name}" version 1.0.0 tools:json "${__dybatpho_agent_mcp_tools}"
}

#######################################
# @description Build the table a server dispatches from: every tool of the MCP
#   manifest, joined with the flattened command entry it was rendered from, so
#   one lookup by name yields both the command line and the option metadata.
# @arg $1 string Name of the variable receiving the table, a compact JSON array
# @arg $2 string Spec function
# @arg $3 string Tool name prefix
# @arg $4 string Command the tools run
# @set The named variable
# @exitcode 1 Stop the script when two commands render to the same tool name
# @internal
#######################################
function __dybatpho_agent_mcp_table_into {
  local __dybatpho_agent_mcp_table_var __dybatpho_agent_mcp_table_spec __dybatpho_agent_mcp_table_prefix
  local __dybatpho_agent_mcp_table_command
  dybatpho::expect_args __dybatpho_agent_mcp_table_var __dybatpho_agent_mcp_table_spec \
    __dybatpho_agent_mcp_table_prefix __dybatpho_agent_mcp_table_command -- "$@"
  local -n __dybatpho_agent_mcp_table_out="${__dybatpho_agent_mcp_table_var}"
  local __dybatpho_agent_mcp_table_manifest __dybatpho_agent_mcp_table_schema __dybatpho_agent_mcp_table_entries
  __dybatpho_agent_mcp_table_manifest=$(dybatpho::agent_mcp "${__dybatpho_agent_mcp_table_spec}" \
    "${__dybatpho_agent_mcp_table_prefix}" "${__dybatpho_agent_mcp_table_command}")
  __dybatpho_agent_mcp_table_schema=$(dybatpho::generate_schema "${__dybatpho_agent_mcp_table_spec}" \
    "${__dybatpho_agent_mcp_table_prefix}")
  __dybatpho_agent_mcp_table_entries=$(__dybatpho_agent_flatten_schema "${__dybatpho_agent_mcp_table_schema}")
  # Both lists come from the same walk of the same schema, so they are in step.
  __dybatpho_agent_mcp_table_out=$(jq -c -n --argjson m "${__dybatpho_agent_mcp_table_manifest}" \
    --argjson c "${__dybatpho_agent_mcp_table_entries}" \
    '[$m.tools, $c] | transpose | map(.[0] + {"x-dybatpho-entry": .[1]})')
  # A name must lead to exactly one command, or a call could run the wrong one.
  local __dybatpho_agent_mcp_table_dup
  __dybatpho_agent_mcp_table_dup=$(dybatpho::json_get "${__dybatpho_agent_mcp_table_out}" \
    '[.[].name] | group_by(.) | map(select(length > 1) | .[0]) | first // ""')
  [[ -z "${__dybatpho_agent_mcp_table_dup}" ]] \
    || dybatpho::die "dybatpho::agent_mcp_serve: Two commands share the tool name '${__dybatpho_agent_mcp_table_dup}'"
}

#######################################
# @description Turn a `tools/call` request into the command line to run.
#   This is the trust boundary of the server: the name and the arguments come
#   from a model. The tool is looked up by its exact name and only its recorded
#   command is ever run; every argument must be a property of the tool's input
#   schema, with the JSON type the schema states, and becomes argv elements
#   that the parser can only read back as that value:
#
#   - a flag is its switch when `true`; when `false` it is left out, or given
#     as `--no-<name>` when the flag is negatable;
#   - a param is `--name=value` as one element when it has a long switch, so a
#     value starting with `-` stays a value, and the short switch followed by
#     the value as a separate element otherwise;
#   - a `multiple:` param repeats that once per array item;
#   - positional arguments follow a `--`, in the order the spec declares them.
#
#   Nothing is evaluated or split: the elements are handed back NUL-separated
#   and read into an array. A `null` argument counts as omitted.
# @arg $1 string Name of the array receiving the command and its arguments
# @arg $2 string Name of the variable receiving the reason a call is refused
# @arg $3 string Path of the tool table written by the server
# @arg $4 string The request's `params`, as JSON
# @set The named array, or the named reason
# @exitcode 0 The command line was built
# @exitcode 1 The call is invalid; the reason says why
# @exitcode 2 The params could not be checked at all, a fault of the server
# @internal
#######################################
function __dybatpho_agent_mcp_argv_into {
  local __dybatpho_agent_mcp_argv_var __dybatpho_agent_mcp_argv_err __dybatpho_agent_mcp_argv_table
  local __dybatpho_agent_mcp_argv_params
  dybatpho::expect_args __dybatpho_agent_mcp_argv_var __dybatpho_agent_mcp_argv_err \
    __dybatpho_agent_mcp_argv_table __dybatpho_agent_mcp_argv_params -- "$@"
  local -n __dybatpho_agent_mcp_argv_out="${__dybatpho_agent_mcp_argv_var}"
  local -n __dybatpho_agent_mcp_argv_reason="${__dybatpho_agent_mcp_argv_err}"
  # kcov(disabled) - a jq program spread over lines: data, not Bash commands
  # shellcheck disable=SC2016 # `$p`, `$a` and friends are jq variables
  local __dybatpho_agent_mcp_argv_program='
    def lname: .name | tostring | ascii_downcase;
    def str($k): if type != "string" then error("Argument \($k) must be a string")
      elif test("\u0000") then error("Argument \($k) must not contain a NUL byte") else . end;
    def strs($k): if type == "array" then map(str($k)) else error("Argument \($k) must be an array of strings") end;
    def negative: startswith("--no-") or startswith("--without-");
    def sw: first(.switches[]? | select(startswith("--") and (negative | not))) // .switches[0]?;
    def off($k): first(.switches[]? | select(negative)) // error("Option \($k) has no switch to turn it off");
    def empty_value: . == null or . == "" or . == [];
    def value($s): if $s | startswith("--") then $s + "=" + . else ($s, .) end;
    . as $p
    | try (
      (if ($p | type) == "object" and ($p.name | type) == "string" then .
        else error("tools/call needs a tool name") end)
      | (first($tools[0][] | select(.name == $p.name)) // error("Unknown tool \($p.name)")) as $tool
      | (if $p.arguments == null then {} else $p.arguments end) as $a
      | def val($k): if $a | has($k) then $a[$k] else null end;
      (if ($a | type) == "object" then . else error("Arguments must be an object") end)
      | $tool["x-dybatpho-entry"] as $e
      | (($a | keys_unsorted) - [$e.options[], $e.arguments[] | lname]) as $unknown
      | (if ($unknown | length) > 0 then error("Unknown argument \($unknown[0])") else . end)
      | ([$e.options[], $e.arguments[] | select(.required == true) | lname | select(val(.) | empty_value)])
        as $missing
      | (if ($missing | length) > 0 then error("Missing required argument \($missing[0])") else . end)
      | [$e.options[] | lname as $k | val($k) as $v | select($v != null)
          | (sw // error("Option \($k) has no switch to pass it with")) as $s
          | if .type == "flag" then
              if ($v | type) != "boolean" then error("Argument \($k) must be a boolean")
              elif $v then $s
              elif .negatable == true then off($k)
              else empty end
            elif .multiple == true then ($v | strs($k))[] | value($s)
            else $v | str($k) | value($s) end] as $options
      | (reduce $e.arguments[] as $arg ({"gap": null, "out": []};
          ($arg | lname) as $k | val($k) as $v
          | if $v == null then .gap = (.gap // $k)
            elif .gap != null then error("Argument \($k) needs \(.gap) before it")
            elif $arg.variadic == true then .out += ($v | strs($k))
            else .out += [$v | str($k)] end) | .out) as $positional
      | ["ok"] + $tool["x-dybatpho-command"] + $options
        + (if ($positional | length) > 0 then ["--"] + $positional else [] end)
    ) catch ["error", (. | tostring)]
    | .[] | . + "\u0000"'
  # kcov(enabled)
  local -a __dybatpho_agent_mcp_argv_words=()
  local __dybatpho_agent_mcp_argv_word
  # A failed `jq` leaves the list empty, which is answered below as a server fault.
  # shellcheck disable=SC2312
  while IFS= read -r -d '' __dybatpho_agent_mcp_argv_word; do
    __dybatpho_agent_mcp_argv_words+=("${__dybatpho_agent_mcp_argv_word}")
  done < <(jq -j --slurpfile tools "${__dybatpho_agent_mcp_argv_table}" "${__dybatpho_agent_mcp_argv_program}" \
    <<< "${__dybatpho_agent_mcp_argv_params}") # kcov(skip) - a loop's `done` is never traced
  if [[ "${__dybatpho_agent_mcp_argv_words[0]-}" == ok ]]; then
    __dybatpho_agent_mcp_argv_out=("${__dybatpho_agent_mcp_argv_words[@]:1}")
    return 0
  fi
  if [[ "${__dybatpho_agent_mcp_argv_words[0]-}" == error ]]; then
    __dybatpho_agent_mcp_argv_reason="${__dybatpho_agent_mcp_argv_words[1]-}"
    return 1
  fi
  __dybatpho_agent_mcp_argv_reason="Could not read the tools/call params"
  return 2
}

#######################################
# @description Write one JSON-RPC message to the protocol stream.
# @arg $1 string Compact JSON message, on one line
# @internal
#######################################
function __dybatpho_agent_mcp_send {
  printf '%s\n' "$1" >&"${__dybatpho_agent_mcp_fd}"
}

#######################################
# @description Write a JSON-RPC error response.
# @arg $1 string Request id as JSON, `null` when it could not be read
# @arg $2 number JSON-RPC error code
# @arg $3 string Message
# @internal
#######################################
function __dybatpho_agent_mcp_send_error {
  local __dybatpho_agent_mcp_error_message __dybatpho_agent_mcp_error
  __dybatpho_json_escape_into __dybatpho_agent_mcp_error_message "$3"
  __dybatpho_agent_mcp_error="{\"code\":$2,\"message\":${__dybatpho_agent_mcp_error_message}}"
  __dybatpho_agent_mcp_send "{\"jsonrpc\":\"2.0\",\"id\":$1,\"error\":${__dybatpho_agent_mcp_error}}"
}

#######################################
# @description Run a tool's command and render its outcome as a `tools/call`
#   result: stdout as the first text item, stderr as a second one when there
#   is any, `isError` from the exit status, and `structuredContent` when stdout
#   is a single JSON object, such as `dybatpho::agent_result` prints.
#   The command runs in a child process in agent mode, reading nothing, with
#   the protocol stream closed and `DYBATPHO_AGENT_MCP_TIMEOUT` as its limit.
#   It leads a process group of its own, which is killed when it returns, so
#   nothing it left running outlives the call; its output goes to files of its
#   own, removed once read.
# @arg $1 string Name of the variable receiving the result, compact JSON
# @arg $@ string The command and its arguments
# @set The named variable
# @exitcode 1 The result could not be rendered
# @internal
#######################################
function __dybatpho_agent_mcp_run_into {
  local -n __dybatpho_agent_mcp_run_out="$1"
  shift
  local __dybatpho_agent_mcp_run_status=0 __dybatpho_agent_mcp_run_pid __dybatpho_agent_mcp_run_monitor=off
  # Fresh files for every call: a process an earlier call left behind still
  # holds that call's files, and must not write into this result.
  # dyshellint disable=BSG011 # the call counter is a local of __dybatpho_agent_mcp_loop, the only caller
  __dybatpho_agent_mcp_calls=$((__dybatpho_agent_mcp_calls + 1))
  local __dybatpho_agent_mcp_stdout="${__dybatpho_agent_mcp_dir}/${__dybatpho_agent_mcp_calls}.out"
  local __dybatpho_agent_mcp_stderr="${__dybatpho_agent_mcp_dir}/${__dybatpho_agent_mcp_calls}.err"
  # Under job control the call leads a process group of its own, so whatever
  # it starts can be ended with it once it returns.
  [[ "$-" == *m* ]] && __dybatpho_agent_mcp_run_monitor=on
  set -m
  (
    set +m
    exec {__dybatpho_agent_mcp_fd}>&-
    export DYBATPHO_AGENT_MODE=on
    dybatpho::run_with_timeout "${__dybatpho_agent_mcp_limit}" "$@" || exit $?
  ) < /dev/null > "${__dybatpho_agent_mcp_stdout}" 2> "${__dybatpho_agent_mcp_stderr}" &
  __dybatpho_agent_mcp_run_pid=$!
  [[ "${__dybatpho_agent_mcp_run_monitor}" == on ]] || set +m
  wait "${__dybatpho_agent_mcp_run_pid}" || __dybatpho_agent_mcp_run_status=$?
  kill -KILL -- "-${__dybatpho_agent_mcp_run_pid}" 2> /dev/null || true
  # kcov(disabled) - a jq program spread over lines: data, not Bash commands
  # shellcheck disable=SC2016 # `$out`, `$err` and friends are jq variables
  local __dybatpho_agent_mcp_run_program='
    $out as $o | $err as $e
    | {"content": ([{"type": "text", "text": $o}]
        + (if $e != "" then [{"type": "text", "text": ("stderr:\n" + $e)}] else [] end)
        + (if $status == 124 and $limit > 0
            then [{"type": "text", "text": "Timed out after \($limit) seconds"}] else [] end)),
       "isError": ($status != 0)}
    + ((try ($o | fromjson) catch null) as $j
       | if ($j | type) == "object" then {"structuredContent": $j} else {} end)'
  # kcov(enabled)
  __dybatpho_agent_mcp_run_out=$(jq -c -n --rawfile out "${__dybatpho_agent_mcp_stdout}" \
    --rawfile err "${__dybatpho_agent_mcp_stderr}" --argjson status "${__dybatpho_agent_mcp_run_status}" \
    --argjson limit "${__dybatpho_agent_mcp_limit}" "${__dybatpho_agent_mcp_run_program}") \
    || __dybatpho_agent_mcp_run_status=-1
  rm -f -- "${__dybatpho_agent_mcp_stdout}" "${__dybatpho_agent_mcp_stderr}"
  ((__dybatpho_agent_mcp_run_status != -1))
}

#######################################
# @description Answer one line read from the client.
#   The line is read by one `jq` call into its kind, method, id and params,
#   each printed as JSON on a line of its own, so nothing a client sends is
#   ever split or evaluated by the shell. Notifications and responses get no
#   reply.
# @arg $1 string The line
# @internal
#######################################
function __dybatpho_agent_mcp_handle {
  local __dybatpho_agent_mcp_parsed
  # kcov(disabled) - a jq program spread over lines: data, not Bash commands
  # shellcheck disable=SC2016 # `$k`, `$id` and friends are jq variables
  local __dybatpho_agent_mcp_classify='
    def out($k; $m; $i; $p): $k, ($m | @json), ($i | @json), ($p | @json);
    if length != 1 or (.[0] | type) != "object" then out("invalid"; null; null; null)
    else .[0]
      | (has("id") and ((.id | type) == "string" or (.id | type) == "number")) as $ok
      | (if $ok then .id else null end) as $id
      | if (has("method") | not) and (has("result") or has("error")) then out("response"; null; null; null)
        elif .jsonrpc != "2.0" or (.method | type) != "string" then out("invalid"; null; $id; null)
        elif (has("id") | not) then out("notification"; .method; null; null)
        elif ($ok | not) then out("invalid"; null; null; null)
        elif has("params") and ((.params | type) != "object" and (.params | type) != "array")
          then out("invalid"; null; $id; null)
        else out("request"; .method; $id; (.params // {})) end
    end'
  # kcov(enabled)
  if ! __dybatpho_agent_mcp_parsed=$(jq -r -s "${__dybatpho_agent_mcp_classify}" <<< "$1" 2> /dev/null); then
    __dybatpho_agent_mcp_send_error null -32700 "Parse error"
    return 0
  fi
  local __dybatpho_agent_mcp_kind __dybatpho_agent_mcp_method __dybatpho_agent_mcp_id __dybatpho_agent_mcp_params
  {
    IFS= read -r __dybatpho_agent_mcp_kind
    IFS= read -r __dybatpho_agent_mcp_method
    IFS= read -r __dybatpho_agent_mcp_id
    IFS= read -r __dybatpho_agent_mcp_params
  } <<< "${__dybatpho_agent_mcp_parsed}"
  case "${__dybatpho_agent_mcp_kind}" in
    request) ;; # kcov(skip) - a case arm has no command to fire on
    invalid)
      __dybatpho_agent_mcp_send_error "${__dybatpho_agent_mcp_id}" -32600 "Invalid Request"
      return 0
      ;;
    *) return 0 ;;
  esac

  local __dybatpho_agent_mcp_result __dybatpho_agent_mcp_reason
  case "${__dybatpho_agent_mcp_method}" in
    '"initialize"')
      local __dybatpho_agent_mcp_version
      __dybatpho_agent_mcp_version=$(jq -c 'if type == "object" then .protocolVersion else null end' \
        <<< "${__dybatpho_agent_mcp_params}")
      case " ${__DYBATPHO_AGENT_MCP_VERSIONS} " in
        *" ${__dybatpho_agent_mcp_version} "*) ;; # kcov(skip) - a case arm has no command to fire on
        *) __dybatpho_agent_mcp_version="${__DYBATPHO_AGENT_MCP_VERSIONS%% *}" ;;
      esac
      __dybatpho_agent_mcp_result="{\"protocolVersion\":${__dybatpho_agent_mcp_version},"
      __dybatpho_agent_mcp_result+="\"capabilities\":{\"tools\":{}},\"serverInfo\":${__dybatpho_agent_mcp_info}}"
      ;;
    '"ping"') __dybatpho_agent_mcp_result="{}" ;;
    '"tools/list"') __dybatpho_agent_mcp_result="${__dybatpho_agent_mcp_list}" ;;
    '"tools/call"')
      local -a __dybatpho_agent_mcp_argv=()
      local __dybatpho_agent_mcp_status=0
      __dybatpho_agent_mcp_argv_into __dybatpho_agent_mcp_argv __dybatpho_agent_mcp_reason \
        "${__dybatpho_agent_mcp_table}" "${__dybatpho_agent_mcp_params}" || __dybatpho_agent_mcp_status=$?
      if ((__dybatpho_agent_mcp_status != 0)); then
        local __dybatpho_agent_mcp_code=-32602
        ((__dybatpho_agent_mcp_status == 1)) || __dybatpho_agent_mcp_code=-32603
        __dybatpho_agent_mcp_send_error "${__dybatpho_agent_mcp_id}" "${__dybatpho_agent_mcp_code}" \
          "${__dybatpho_agent_mcp_reason}"
        return 0
      fi
      # The list always holds the command, at least.
      if ! __dybatpho_agent_mcp_run_into __dybatpho_agent_mcp_result \
        ${__dybatpho_agent_mcp_argv[@]+"${__dybatpho_agent_mcp_argv[@]}"}; then
        __dybatpho_agent_mcp_send_error "${__dybatpho_agent_mcp_id}" -32603 "Could not render the tool result"
        return 0
      fi
      ;;
    *)
      __dybatpho_agent_mcp_send_error "${__dybatpho_agent_mcp_id}" -32601 "Method not found"
      return 0
      ;;
  esac
  local __dybatpho_agent_mcp_reply="{\"jsonrpc\":\"2.0\",\"id\":${__dybatpho_agent_mcp_id},"
  __dybatpho_agent_mcp_send "${__dybatpho_agent_mcp_reply}\"result\":${__dybatpho_agent_mcp_result}}"
}

#######################################
# @description Read JSON-RPC messages from stdin and answer them until stdin
#   closes. The body of `dybatpho::agent_mcp_serve`, run with stdout already
#   pointed at stderr.
# @arg $1 string Spec function
# @arg $2 string Server and tool name prefix
# @arg $3 string Command the tools run
# @internal
#######################################
function __dybatpho_agent_mcp_loop {
  local __dybatpho_agent_mcp_tools __dybatpho_agent_mcp_dir __dybatpho_agent_mcp_calls=0
  __dybatpho_agent_mcp_table_into __dybatpho_agent_mcp_tools "$1" "$2" "$3"
  __dybatpho_create_temp_into __dybatpho_agent_mcp_dir "/" "agent_mcp"
  local __dybatpho_agent_mcp_table="${__dybatpho_agent_mcp_dir}/tools.json"
  printf '%s\n' "${__dybatpho_agent_mcp_tools}" > "${__dybatpho_agent_mcp_table}"

  # The command each tool maps to is the server's own business, and the entry
  # is metadata it dispatches with; a client is shown plain MCP tools.
  local __dybatpho_agent_mcp_list __dybatpho_agent_mcp_info __dybatpho_agent_mcp_name __dybatpho_agent_mcp_version
  __dybatpho_agent_mcp_list=$(dybatpho::json_eval "${__dybatpho_agent_mcp_tools}" \
    '{"tools": map(del(."x-dybatpho-command", ."x-dybatpho-entry"))}')
  __dybatpho_json_escape_into __dybatpho_agent_mcp_name "$2"
  __dybatpho_agent_mcp_version="${DYBATPHO_AGENT_MCP_VERSION:-}"
  [[ -n "${__dybatpho_agent_mcp_version}" ]] || __dybatpho_agent_mcp_version=$(dybatpho::version)
  __dybatpho_json_escape_into __dybatpho_agent_mcp_version "${__dybatpho_agent_mcp_version}"
  __dybatpho_agent_mcp_info="{\"name\":${__dybatpho_agent_mcp_name},\"version\":${__dybatpho_agent_mcp_version}}"

  local __dybatpho_agent_mcp_line
  while IFS= read -r __dybatpho_agent_mcp_line || [[ -n "${__dybatpho_agent_mcp_line}" ]]; do
    [[ -n "${__dybatpho_agent_mcp_line//[[:space:]]/}" ]] || continue
    __dybatpho_agent_mcp_handle "${__dybatpho_agent_mcp_line}"
  done # kcov(skip) - a loop's `done` is never traced
  rm -f -- "${__dybatpho_agent_mcp_table}"
  rmdir -- "${__dybatpho_agent_mcp_dir}" 2> /dev/null || true
  return 0
}

#######################################
# @description Serve a script's commands as MCP tools over stdio.
#   A JSON-RPC 2.0 loop answers `initialize`, `ping`, `tools/list` and
#   `tools/call`, one message per line, until stdin closes. The tools are those
#   `dybatpho::agent_mcp` lists, and each call runs the tool's recorded command
#   in agent mode, so `dybatpho::agent_confirm` and `dybatpho::agent_audit`
#   apply unchanged.
# @note Arguments are checked before anything runs: an unknown tool, an unknown argument, a missing required one or a
#   value of the wrong JSON type is refused with error `-32602`. A flag is passed as its switch (`--no-<name>` when
#   negatable and false), a param as one `--name=value` element, a `multiple:` param once per item, and positional
#   arguments after `--`, so a value is never read as an option. A `null` argument counts as omitted.
# @note A call runs in a child process with `DYBATPHO_AGENT_MODE=on` and stdin from `/dev/null`. Its result carries
#   stdout as the first text item and stderr, when there is any, as a second one starting `stderr:`; `isError` is set
#   from the exit status, and stdout that is a single JSON object, such as `dybatpho::agent_result` prints, is also
#   returned as `structuredContent`.
# @note stdout is the protocol stream: for the whole loop, everything else the script or the library prints goes to
#   stderr. Notifications get no reply.
# @note The protocol version is the one the client asks for when it is `2025-06-18`, `2025-03-26` or `2024-11-05`, and
#   `2025-06-18` otherwise. A batch (a JSON array) is refused as an invalid request.
# @example
#   # mytool: `mytool mcp` serves every other command as a tool.
#   if [[ "${1:-}" == mcp ]]; then
#     dybatpho::agent_mcp_serve _spec_root mytool "$0"
#     exit
#   fi
#   dybatpho::generate_from_spec _spec_root "$@"
#
# @example
#   claude mcp add mytool -- /usr/local/bin/mytool mcp
#
# @arg $1 string Spec function
# @arg $2 string? Server and tool name prefix, default is the script name
# @arg $3 string? Command the tools run, default is the script path; it must be executable
# @env DYBATPHO_AGENT_MCP_TIMEOUT number [default: 0] Seconds a tool call may run, `0` for no limit
# @env DYBATPHO_AGENT_MCP_VERSION string Version reported in `serverInfo`, default is the dybatpho version
# @stdout JSON-RPC responses, one per line
# @exitcode 0 stdin closed
# @exitcode 1 Stop the script on missing arguments, an invalid timeout, or two commands with the same tool name
# @see dybatpho::agent_mcp
# @tip Keep the `mcp` entry point out of the spec, as the example does, so the server does not list itself as a tool
# @warning Tools, not resources or prompts; a call returns one result, with no progress notifications
#######################################
function dybatpho::agent_mcp_serve {
  local __dybatpho_agent_mcp_spec __dybatpho_agent_mcp_prefix __dybatpho_agent_mcp_command
  dybatpho::expect_args __dybatpho_agent_mcp_spec -- "$@"
  __dybatpho_agent_mcp_prefix="${2:-${0##*/}}"
  __dybatpho_agent_mcp_command="${3:-$0}"
  local __dybatpho_agent_mcp_limit="${DYBATPHO_AGENT_MCP_TIMEOUT}"
  local __dybatpho_agent_mcp_why="DYBATPHO_AGENT_MCP_TIMEOUT must be a number of seconds"
  [[ "${__dybatpho_agent_mcp_limit}" =~ ^[0-9]{1,18}$ ]] \
    || dybatpho::die "dybatpho::agent_mcp_serve: ${__dybatpho_agent_mcp_why}, got '${__dybatpho_agent_mcp_limit}'"
  __dybatpho_agent_mcp_limit=$((10#${__dybatpho_agent_mcp_limit}))

  local __dybatpho_agent_mcp_fd
  exec {__dybatpho_agent_mcp_fd}>&1
  __dybatpho_agent_mcp_loop "${__dybatpho_agent_mcp_spec}" "${__dybatpho_agent_mcp_prefix}" \
    "${__dybatpho_agent_mcp_command}" >&2
  exec {__dybatpho_agent_mcp_fd}>&-
}
