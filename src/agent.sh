# shellcheck shell=bash
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
#   - `docs/cli.md` for the option spec these tool definitions are generated from
# @tip Agent mode is detected automatically; force it either way with `DYBATPHO_AGENT_MODE`
# @note Tool definitions are generated from the live option spec, so a new flag becomes a new tool parameter without a
#   second edit
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
#   dybatpho::agent_detect && export DRY_RUN=true
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
  # shellcheck disable=SC2154 # declared by `init.sh`
  modules=$(dybatpho::json_eval "$(dybatpho::json_string "${DYBATPHO_LOADED_MODULES}")" \
    'split(" ") | map(select(length > 0))')
  git=$(dybatpho::json_object repository:json "${repository}" branch "${branch}")

  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  dybatpho::json_object \
    os "${os}" \
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

  if __dybatpho_agent_allowed "${action}"; then
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
  local agent_mode
  __dybatpho_agent_mode_into agent_mode
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  dybatpho::json_object \
    timestamp "${timestamp}" \
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
# @internal
#######################################
function __dybatpho_agent_flatten_schema {
  local schema
  dybatpho::expect_args schema -- "$@"
  local -a entries=()
  __dybatpho_agent_flatten_into entries "${schema}" '[]'
  local IFS=,
  printf '[%s]\n' "${entries[*]}"
}

#######################################
# @description Append one command and its subcommands to a list of entries.
#   One read per command answers the entry, its name and its subcommands, each
#   as a line of compact JSON, where reading them field by field and appending
#   to a growing document took around eight processes per command.
# @arg $1 string Name of the array the compact entries are appended to
# @arg $2 string Command node JSON
# @arg $3 string Path of the parent command, as a JSON array
# @set The named array
# @internal
#######################################
function __dybatpho_agent_flatten_into {
  local __dybatpho_agent_flat_var __dybatpho_agent_flat_node __dybatpho_agent_flat_parent
  dybatpho::expect_args __dybatpho_agent_flat_var __dybatpho_agent_flat_node \
    __dybatpho_agent_flat_parent -- "$@"
  local -n __dybatpho_agent_flat_out="${__dybatpho_agent_flat_var}"
  local __dybatpho_agent_flat_lines
  __dybatpho_agent_flat_lines=$(dybatpho::json_get "${__dybatpho_agent_flat_node}" \
    "(${__dybatpho_agent_flat_parent} + [(.name | tostring)]) as \$path
      | ({\"path\": \$path, \"description\": (.description | tostring),
          \"options\": [.options[]? | select(.hidden != true)]} | @json),
        (.name | tostring | @json),
        (.commands[]? | @json)")
  local -a __dybatpho_agent_flat_parts=()
  mapfile -t __dybatpho_agent_flat_parts <<< "${__dybatpho_agent_flat_lines}"
  __dybatpho_agent_flat_out+=("${__dybatpho_agent_flat_parts[0]}")
  # The children's parent path is this one with the name appended, spelled
  # here from the backend's own rendering of the name: `yq` drops an output
  # that depends only on a variable, so the path can't come back as a line.
  local __dybatpho_agent_flat_path="${__dybatpho_agent_flat_parent%]}"
  [[ "${__dybatpho_agent_flat_path}" == "[" ]] || __dybatpho_agent_flat_path+=","
  __dybatpho_agent_flat_path+="${__dybatpho_agent_flat_parts[1]}]"
  local __dybatpho_agent_flat_index
  for ((__dybatpho_agent_flat_index = 2; __dybatpho_agent_flat_index < ${#__dybatpho_agent_flat_parts[@]};  \
  __dybatpho_agent_flat_index++)); do
    __dybatpho_agent_flatten_into "${__dybatpho_agent_flat_var}" \
      "${__dybatpho_agent_flat_parts[__dybatpho_agent_flat_index]}" "${__dybatpho_agent_flat_path}"
  done
}

#######################################
# @description Build the filter that renders a command entry's options as a
#   JSON Schema object, in one pass over the entry.
#   Each option became a property through several reads and a growing document
#   rewritten per option, around ten processes each. A filter does it in the
#   one read that renders the whole tool. The two backends differ in exactly
#   two words, the reduction and the lower-casing, so those are chosen here;
#   and every branch reads its own input, because a `yq` literal ignores an
#   empty input and would answer even where `select` matched nothing.
# @arg $1 string Name of the variable receiving the filter
# @set The named variable, an expression over one entry
# @internal
#######################################
function __dybatpho_agent_options_filter_into {
  local __dybatpho_agent_opts_var
  dybatpho::expect_args __dybatpho_agent_opts_var -- "$@"
  local -n __dybatpho_agent_opts_out="${__dybatpho_agent_opts_var}"
  local __dybatpho_agent_opts_cmd __dybatpho_agent_opts_down __dybatpho_agent_opts_reduce
  __dybatpho_json_cmd_into __dybatpho_agent_opts_cmd
  # `$opt` is a variable of the filter, not of the shell.
  # shellcheck disable=SC2016
  if [[ "${__dybatpho_agent_opts_cmd}" == "yq" ]]; then
    __dybatpho_agent_opts_down=downcase
    __dybatpho_agent_opts_reduce='.options[] as $opt ireduce'
  else
    __dybatpho_agent_opts_down=ascii_downcase
    __dybatpho_agent_opts_reduce='reduce .options[] as $opt'
  fi
  local enum='((select(((.choices // "") | tostring) != "") | {"enum": (.choices | split(","))}) // {})'
  local description='"description": (.description | tostring)'
  local property="(\$opt | (select(.type == \"flag\") | {\"type\": \"boolean\", ${description}})
    // (select(.multiple == true)
      | {\"type\": \"array\", ${description}, \"items\": ({\"type\": \"string\"} + ${enum})})
    // ({\"type\": \"string\", ${description}} + ${enum}))"
  __dybatpho_agent_opts_out="{\"type\": \"object\",
    \"properties\": (${__dybatpho_agent_opts_reduce} ({};
      . + {((\$opt | .name | tostring) | ${__dybatpho_agent_opts_down}): ${property}})),
    \"required\": [.options[] | select(.required == true)
      | (.name | tostring | ${__dybatpho_agent_opts_down})],
    \"additionalProperties\": false}"
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
  __dybatpho_agent_each_names=$(dybatpho::json_get "${__dybatpho_agent_each_commands}" \
    '.[] | .path | join("_")')
  local -a __dybatpho_agent_each_list=()
  [[ -z "${__dybatpho_agent_each_names}" ]] \
    || mapfile -t __dybatpho_agent_each_list <<< "${__dybatpho_agent_each_names}"

  local __dybatpho_agent_each_index=0 __dybatpho_agent_each_name __dybatpho_agent_each_filter
  for __dybatpho_agent_each_name in ${__dybatpho_agent_each_list[@]+"${__dybatpho_agent_each_list[@]}"}; do
    __dybatpho_agent_tool_name_into __dybatpho_agent_each_name "${__dybatpho_agent_each_name}"
    __dybatpho_agent_each_filter="${__dybatpho_agent_each_template//@NAME@/\"${__dybatpho_agent_each_name}\"}"
    __dybatpho_agent_each_filter="${__dybatpho_agent_each_filter//@SCHEMA@/${__dybatpho_agent_each_schema}}"
    __dybatpho_agent_each_out+=("$(dybatpho::json_get "${__dybatpho_agent_each_commands}" \
      ".[${__dybatpho_agent_each_index}] | (${__dybatpho_agent_each_filter}) | @json")")
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
# @arg $2 string Tool name prefix, default is the script name
# @arg $3 string Output shape, `anthropic` (default) or `openai`
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
    anthropic | openai) ;;
    *)
      dybatpho::die \
        "dybatpho::agent_tools: Unknown format '${__dybatpho_agent_tools_format}', expected anthropic or openai"
      ;;
  esac
  local __dybatpho_agent_tools_schema __dybatpho_agent_tools_commands
  __dybatpho_agent_tools_schema=$(dybatpho::generate_schema "${__dybatpho_agent_tools_spec}" \
    "${__dybatpho_agent_tools_name}")
  __dybatpho_agent_tools_commands=$(__dybatpho_agent_flatten_schema "${__dybatpho_agent_tools_schema}")

  local __dybatpho_agent_tools_template
  if [[ "${__dybatpho_agent_tools_format}" == "anthropic" ]]; then
    __dybatpho_agent_tools_template='{"name": @NAME@, "description": (.description | tostring),
      "input_schema": (@SCHEMA@)}'
  else
    __dybatpho_agent_tools_template='{"type": "function", "function": {"name": @NAME@,
      "description": (.description | tostring), "parameters": (@SCHEMA@)}}'
  fi
  local -a __dybatpho_agent_tools_definitions=()
  __dybatpho_agent_each_tool_into __dybatpho_agent_tools_definitions "${__dybatpho_agent_tools_commands}" \
    "${__dybatpho_agent_tools_template}"
  (
    IFS=,
    printf '[%s]\n' "${__dybatpho_agent_tools_definitions[*]}"
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
# @arg $2 string Server and tool name prefix, default is the script name
# @arg $3 string Command an MCP server should execute, default is the script path
# @stdout JSON object with `name`, `version`, and a `tools` array
# @exitcode 0 The payload was printed
# @exitcode 1 Missing arguments
# @see dybatpho::agent_tools
# @note This is the tool manifest, not a running server; point your MCP host at it and dispatch with the recorded
#   command
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
  # `.path | .[1:]` rather than `.path[1:]`: yq 4.52 applies the latter slice to
  # the enclosing object, not to `.path`.
  local __dybatpho_agent_mcp_command_json
  __dybatpho_agent_mcp_command_json=$(dybatpho::json_string "${__dybatpho_agent_mcp_command}")
  local __dybatpho_agent_mcp_template='{"name": @NAME@, "description": (.description | tostring),
    "inputSchema": (@SCHEMA@), "x-dybatpho-command": (['"${__dybatpho_agent_mcp_command_json}"'] + (.path | .[1:]))}'
  local -a __dybatpho_agent_mcp_definitions=()
  __dybatpho_agent_each_tool_into __dybatpho_agent_mcp_definitions "${__dybatpho_agent_mcp_commands}" \
    "${__dybatpho_agent_mcp_template}"
  local __dybatpho_agent_mcp_tools
  __dybatpho_agent_mcp_tools="[$(
    IFS=,
    printf '%s' "${__dybatpho_agent_mcp_definitions[*]}"
  )]"
  dybatpho::json_object name "${__dybatpho_agent_mcp_name}" version 1.0.0 tools:json "${__dybatpho_agent_mcp_tools}"
}
