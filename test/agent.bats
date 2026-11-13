setup() {
  load test_helper
  # The suite may itself be running under an agent, so clear every marker and
  # let each test opt in to the mode it is exercising.
  local marker
  for marker in ${DYBATPHO_AGENT_MARKERS}; do
    unset "${marker}"
  done
  DYBATPHO_AGENT_MODE=auto
  DYBATPHO_AGENT_ALLOW=""
  DYBATPHO_AGENT_AUDIT_FILE=""
  DYBATPHO_AGENT_ENV=""
}

_spec_test_root() {
  dybatpho::opts::setup "Manage the test service" ROOT_ARGS action:"_noop"
  dybatpho::opts::flag "Verbose output" VERBOSE --verbose alias:-v
  dybatpho::opts::param "Target environment" TARGET --target \
    choices:dev,prod required:true
  dybatpho::opts::param "Components" COMPONENT --component \
    choices:api,web multiple:true
  dybatpho::opts::param "Internal switch" INTERNAL --internal hidden:true
  dybatpho::opts::cmd deploy _spec_test_deploy
}

_spec_test_deploy() {
  dybatpho::opts::setup "Deploy a version" DEPLOY_ARGS action:"_noop"
  dybatpho::opts::param "Version tag" TAG --tag required:true
}

# ---------------------------------------------------------------------------
# dybatpho::agent_mode and dybatpho::agent_detect
# ---------------------------------------------------------------------------

@test "dybatpho::agent_mode is off with no marker present" {
  assert_equal "$(dybatpho::agent_mode)" "off"
}

@test "dybatpho::agent_mode is on when a runtime marker is set" {
  CLAUDECODE=1
  assert_equal "$(dybatpho::agent_mode)" "on"
}

@test "dybatpho::agent_mode honours an extra marker from DYBATPHO_AGENT_ENV" {
  DYBATPHO_AGENT_ENV="MY_OWN_AGENT"
  MY_OWN_AGENT=1
  assert_equal "$(dybatpho::agent_mode)" "on"
}

@test "dybatpho::agent_mode skips a DYBATPHO_AGENT_ENV word that is no variable name" {
  # The list was expanded unquoted and each word used as a name: `*` matched the
  # files here, and `MY-AGENT` stopped detection with a Bash error.
  cd "${BATS_TEST_TMPDIR}"
  touch AGENT.md
  MY_OWN_AGENT=1
  DYBATPHO_AGENT_ENV="MY-AGENT * MY_OWN_AGENT"
  run --separate-stderr dybatpho::agent_mode
  assert_success
  assert_output "on"
  refute_stderr
}

@test "dybatpho::agent_mode ignores an empty marker" {
  CLAUDECODE=""
  assert_equal "$(dybatpho::agent_mode)" "off"
}

@test "dybatpho::agent_mode can be forced on and off" {
  DYBATPHO_AGENT_MODE=on
  assert_equal "$(dybatpho::agent_mode)" "on"
  DYBATPHO_AGENT_MODE=off
  CLAUDECODE=1
  assert_equal "$(dybatpho::agent_mode)" "off"
}

@test "dybatpho::agent_mode rejects an unknown mode" {
  DYBATPHO_AGENT_MODE=maybe
  run --separate-stderr dybatpho::agent_mode
  assert_failure
  assert_stderr --partial "Unknown mode"
}

@test "dybatpho::agent_detect follows the mode" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_detect
  assert_success
  DYBATPHO_AGENT_MODE=off
  run_traced dybatpho::agent_detect
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::agent_result
# ---------------------------------------------------------------------------

@test "dybatpho::agent_result no arg" {
  run dybatpho::agent_result
  assert_failure
}

@test "dybatpho::agent_result prints text for a person" {
  DYBATPHO_AGENT_MODE=off
  run_traced dybatpho::agent_result ok service=api replicas=3
  assert_output "status=ok service=api replicas=3"
}

@test "dybatpho::agent_result prints JSON for an agent" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_result ok service=api replicas=3
  assert_equal "$(dybatpho::json_get "${output}" '.status')" "ok"
  assert_equal "$(dybatpho::json_get "${output}" '.service')" "api"
  assert_equal "$(dybatpho::json_get "${output}" '.replicas')" "3"
}

@test "dybatpho::agent_result accepts a status with no fields" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_result ok
  assert_output '{"status":"ok"}'
}

@test "dybatpho::agent_result keeps a value containing an equals sign" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_result ok query=a=b
  assert_equal "$(dybatpho::json_get "${output}" '.query')" "a=b"
}

@test "dybatpho::agent_result escapes characters that would break JSON" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_result ok reason='he said "no"'
  assert_equal "$(dybatpho::json_get "${output}" '.reason')" 'he said "no"'
}

@test "dybatpho::agent_result rejects a field that is not key=value" {
  DYBATPHO_AGENT_MODE=on
  run --separate-stderr dybatpho::agent_result ok bare-field
  assert_failure
  assert_stderr --partial "Expected key=value"
}

# ---------------------------------------------------------------------------
# dybatpho::agent_error
# ---------------------------------------------------------------------------

@test "dybatpho::agent_error no arg" {
  run dybatpho::agent_error
  assert_failure
}

@test "dybatpho::agent_error always reports failure" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_error bad_input "wrong"
  assert_failure
}

@test "dybatpho::agent_error prints a structured object for an agent" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_error missing_config "No config" "Run init"
  assert_equal "$(dybatpho::json_get "${output}" '.status')" "error"
  assert_equal "$(dybatpho::json_get "${output}" '.code')" "missing_config"
  assert_equal "$(dybatpho::json_get "${output}" '.message')" "No config"
  assert_equal "$(dybatpho::json_get "${output}" '.hint')" "Run init"
}

@test "dybatpho::agent_error omits an absent hint" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_error bad_input "wrong"
  assert_equal "$(dybatpho::json_get "${output}" 'has("hint")')" "false"
}

@test "dybatpho::agent_error logs for a person instead of printing JSON" {
  DYBATPHO_AGENT_MODE=off
  run_traced --separate-stderr dybatpho::agent_error missing_config "No config" "Run init"
  assert_failure
  assert_stderr --partial "No config"
  assert_output --partial "Hint: Run init"
}

# ---------------------------------------------------------------------------
# dybatpho::agent_context
# ---------------------------------------------------------------------------

@test "dybatpho::agent_context reports the environment as JSON" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_context
  assert_equal "$(dybatpho::json_get "${output}" '.os')" "$(uname -s)"
  assert_equal "$(dybatpho::json_get "${output}" '.cwd')" "${PWD}"
  assert_equal "$(dybatpho::json_get "${output}" '.agent_mode')" "true"
  # The shape is checked by what the array contains rather than by its exact
  # contents, which depend on the modules this suite loads.
  assert_equal "$(dybatpho::json_get "${output}" '.modules[0]')" "string"
  assert_equal "$(dybatpho::json_get "${output}" '[.modules[] | select(. == "agent")] | length')" "1"
}

@test "dybatpho::agent_context reports the dry run flag" {
  DRY_RUN=true
  run_traced dybatpho::agent_context
  assert_equal "$(dybatpho::json_get "${output}" '.dry_run')" "true"
  DRY_RUN=false
}

@test "dybatpho::agent_context lists the loaded modules" {
  run_traced dybatpho::agent_context
  assert_output --partial '"agent"'
}

# ---------------------------------------------------------------------------
# dybatpho::agent_confirm
# ---------------------------------------------------------------------------

@test "dybatpho::agent_confirm no arg" {
  run dybatpho::agent_confirm
  assert_failure
}

@test "dybatpho::agent_confirm allows an action on the allowlist" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deploy restart"
  run_traced dybatpho::agent_confirm restart "Restart the API"
  assert_success
}

@test "dybatpho::agent_confirm refuses an action that is not listed" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deploy"
  run_traced dybatpho::agent_confirm wipe "Delete everything"
  assert_failure
  assert_equal "$(dybatpho::json_get "${output}" '.status')" "refused"
  assert_equal "$(dybatpho::json_get "${output}" '.code')" "action_not_allowed"
  assert_equal "$(dybatpho::json_get "${output}" '.action')" "wipe"
}

@test "dybatpho::agent_confirm refuses everything with an empty allowlist" {
  DYBATPHO_AGENT_MODE=on
  run_traced dybatpho::agent_confirm deploy
  assert_failure
}

@test "dybatpho::agent_confirm honours the all wildcard" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="all"
  run_traced dybatpho::agent_confirm anything
  assert_success
}

@test "dybatpho::agent_confirm does not match a partial action name" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deployment"
  run_traced dybatpho::agent_confirm deploy
  assert_failure
}

@test "dybatpho::agent_confirm asks a person instead of reading the allowlist" {
  DYBATPHO_AGENT_MODE=off
  DYBATPHO_AGENT_ALLOW="all"
  DYBATPHO_FORCE=true
  run_traced dybatpho::agent_confirm deploy "Ship it"
  assert_success
  # Nobody is there to answer, and the allowlist is not consulted for a person.
  DYBATPHO_FORCE=false
  DYBATPHO_INTERACTIVE=false
  run_traced --separate-stderr dybatpho::agent_confirm deploy "Ship it"
  assert_failure
  assert_stderr --partial "Ship it?"
  assert_output ""
}

@test "dybatpho::agent_confirm records both decisions in the audit log" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deploy"
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl"
  dybatpho::agent_confirm deploy "Ship it" || true
  dybatpho::agent_confirm wipe "Delete it" > /dev/null || true
  assert_file_exist "${DYBATPHO_AGENT_AUDIT_FILE}"
  assert_equal "$(wc -l < "${DYBATPHO_AGENT_AUDIT_FILE}" | tr -d ' ')" "2"
  assert_equal "$(dybatpho::json_get "$(head -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.detail')" "allowed: Ship it"
  assert_equal "$(dybatpho::json_get "$(tail -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.detail')" "refused: not in DYBATPHO_AGENT_ALLOW"
}

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------

@test "dybatpho::agent_audit no arg" {
  run dybatpho::agent_audit
  assert_failure
}

@test "dybatpho::agent_audit does nothing without a destination" {
  run_traced dybatpho::agent_audit deploy "detail"
  assert_success
  assert_output ""
}

@test "dybatpho::agent_audit writes one JSON object per record" {
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/nested/audit.jsonl"
  dybatpho::agent_audit deploy "version 1.0"
  dybatpho::agent_audit rollback
  assert_file_exist "${DYBATPHO_AGENT_AUDIT_FILE}"
  assert_equal "$(wc -l < "${DYBATPHO_AGENT_AUDIT_FILE}" | tr -d ' ')" "2"
  assert_equal "$(dybatpho::json_get "$(head -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.action')" "deploy"
  assert_equal "$(dybatpho::json_get "$(head -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.detail')" "version 1.0"
}

@test "dybatpho::agent_audit_show prints the recorded actions" {
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl"
  dybatpho::agent_audit deploy "version 1.0"
  run_traced dybatpho::agent_audit_show
  assert_output --partial "deploy version 1.0"
}

@test "dybatpho::agent_audit_show prints a last record that has no newline" {
  # `read` fails on a final line without a newline, so the loop dropped the
  # last record of a log that had been trimmed or written by another tool.
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl"
  dybatpho::agent_audit deploy "version 1.0"
  printf '%s' "$(dybatpho::json_object timestamp t action rollback detail "version 0.9")" \
    >> "${DYBATPHO_AGENT_AUDIT_FILE}"
  run_traced dybatpho::agent_audit_show
  assert_line --index 0 --partial "deploy version 1.0"
  assert_line --index 1 "t rollback version 0.9"
}

@test "dybatpho::agent_audit_show is silent when nothing was recorded" {
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/absent.jsonl"
  run_traced dybatpho::agent_audit_show
  assert_output ""
}

# ---------------------------------------------------------------------------
# dybatpho::agent_tools
# ---------------------------------------------------------------------------

@test "dybatpho::agent_tools no arg" {
  run dybatpho::agent_tools
  assert_failure
}

@test "dybatpho::agent_tools rejects an unknown format" {
  run --separate-stderr dybatpho::agent_tools _spec_test_root tool yaml
  assert_failure
  assert_stderr --partial "Unknown format"
}

@test "dybatpho::agent_tools emits one tool per command" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" 'length')" "2"
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].name')" "mytool"
  assert_equal "$(dybatpho::json_get "${tools}" '.[1].name')" "mytool_deploy"
}

@test "dybatpho::agent_tools carries each command description" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].description')" "Manage the test service"
  assert_equal "$(dybatpho::json_get "${tools}" '.[1].description')" "Deploy a version"
}

@test "dybatpho::agent_tools maps a flag to a boolean" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].input_schema.properties.verbose.type')" "boolean"
}

@test "dybatpho::agent_tools turns choices into an enum" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.properties.target.enum')" '["dev","prod"]'
}

@test "dybatpho::agent_tools turns a repeatable option into an array" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].input_schema.properties.component.type')" "array"
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.properties.component.items.enum')" '["api","web"]'
}

@test "dybatpho::agent_tools carries the required list" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.required')" '["target"]'
  assert_equal "$(dybatpho::json_eval "${tools}" '.[1].input_schema.required')" '["tag"]'
}

@test "dybatpho::agent_tools omits hidden options" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].input_schema.properties | has("internal")')" "false"
}

@test "dybatpho::agent_tools closes the schema to unknown properties" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].input_schema.additionalProperties')" "false"
}

@test "dybatpho::agent_tools emits the openai function shape" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root mytool openai)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].type')" "function"
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].function.name')" "mytool"
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].function.parameters.properties.verbose.type')" "boolean"
}

@test "dybatpho::agent_tools omits display options and describes positional arguments" {
  # `--help` became a string property named `-`, and positionals were missing.
  local tools
  tools=$(dybatpho::agent_tools _spec_test_rt rt)
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.properties | keys')" \
    '["color","extra","item","need","short","src","tag","verbose"]'
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.properties.src.type')" '"string"'
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.properties.extra.items')" '{"type":"string"}'
  assert_equal "$(dybatpho::json_eval "${tools}" '.[0].input_schema.required')" '["need","src"]'
}

@test "dybatpho::agent_tools produces tool names that are safe to call" {
  local tools
  tools=$(dybatpho::agent_tools _spec_test_root "my tool")
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].name')" "my_tool"
}

# ---------------------------------------------------------------------------
# dybatpho::agent_mcp
# ---------------------------------------------------------------------------

@test "dybatpho::agent_mcp no arg" {
  run dybatpho::agent_mcp
  assert_failure
}

@test "dybatpho::agent_mcp emits a named manifest" {
  local manifest
  manifest=$(dybatpho::agent_mcp _spec_test_root mytool /usr/bin/mytool)
  assert_equal "$(dybatpho::json_get "${manifest}" '.name')" "mytool"
  assert_equal "$(dybatpho::json_get "${manifest}" '.tools | length')" "2"
}

@test "dybatpho::agent_mcp uses the MCP inputSchema key" {
  local manifest
  manifest=$(dybatpho::agent_mcp _spec_test_root mytool /usr/bin/mytool)
  assert_equal "$(dybatpho::json_get "${manifest}" '.tools[0].inputSchema.type')" "object"
  assert_equal "$(dybatpho::json_get "${manifest}" '.tools[0] | has("input_schema")')" "false"
}

@test "dybatpho::agent_mcp records the command each tool maps to" {
  local manifest
  manifest=$(dybatpho::agent_mcp _spec_test_root mytool /usr/bin/mytool)
  assert_equal "$(dybatpho::json_eval "${manifest}" '.tools[0]."x-dybatpho-command"')" '["/usr/bin/mytool"]'
  assert_equal "$(dybatpho::json_eval "${manifest}" '.tools[1]."x-dybatpho-command"')" '["/usr/bin/mytool","deploy"]'
}

# ---------------------------------------------------------------------------
# dybatpho::agent_mcp_serve
# ---------------------------------------------------------------------------

_spec_test_rt() {
  dybatpho::opts::setup "Round trip" RT_ARGS action:":"
  dybatpho::opts::flag "Verbose" VERBOSE --verbose alias:-v
  dybatpho::opts::flag "Color" COLOR --{no-}color negatable:true init:@on
  dybatpho::opts::param "Tag" TAG --tag
  dybatpho::opts::param "Short only" SHORT -s
  dybatpho::opts::param "Items" ITEM --item multiple:true
  dybatpho::opts::param "Needed" NEED --need required:true
  dybatpho::opts::arg "Source" SRC
  dybatpho::opts::arg "Extra" EXTRA required:false variadic:true
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec_test_rt"
}

# Writes the tool table of `_spec_test_rt` to `${table}`.
_rt_table() {
  local tools
  __dybatpho_agent_mcp_table_into tools _spec_test_rt rt /bin/rt
  table="${BATS_TEST_TMPDIR}/table.json"
  printf '%s\n' "${tools}" > "${table}"
}

# Writes an executable MCP server script to `${server}`, with a `mcp` entry point.
_mcp_server_fixture() {
  server="${BATS_TEST_TMPDIR}/mytool"
  {
    printf '#!/usr/bin/env bash\n'
    printf '. %q --modules agent json\n' "${DYBATPHO_DIR}/init.sh"
    cat << 'EOF'
_spec() {
  dybatpho::opts::setup "Greet someone" ARGS action:"_greet"
  dybatpho::opts::flag "Shout" SHOUT --shout
  dybatpho::opts::param "Greeting" GREETING --greeting
  dybatpho::opts::arg "Who to greet" WHO
  dybatpho::opts::cmd fail _spec_fail
  dybatpho::opts::cmd slow _spec_slow
  dybatpho::opts::cmd leave _spec_leave
  dybatpho::opts::cmd wait _spec_wait
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}
_spec_leave() { dybatpho::opts::setup "Leave a process behind" LARGS action:"_leave"; }
_spec_wait() { dybatpho::opts::setup "Wait a while" WARGS action:"sleep 2; printf 'second\\n'; exit 0"; }
_leave() {
  (
    sleep 1
    printf '{"injected":true}'
    printf x > "${MCP_MARK}"
  ) &
  disown
  printf 'first\n'
  # The root action would run next and ask for its positional.
  exit 0
}
_spec_fail() { dybatpho::opts::setup "Always fail" FARGS action:"_fail"; }
_spec_slow() { dybatpho::opts::setup "Sleep" SARGS action:"sleep 5"; }
_greet() {
  dybatpho::agent_result ok greeting="${GREETING:-hello} ${WHO}" shout="${SHOUT}" \
    mode="${DYBATPHO_AGENT_MODE}" stdin="$(cat)"
}
_fail() { printf 'partial\n'; printf 'went wrong\n' >&2; exit 3; }
dybatpho::register_common_handlers
if [[ "${1:-}" == mcp ]]; then
  dybatpho::info "serving"
  dybatpho::agent_mcp_serve _spec mytool "$0"
  exit
fi
dybatpho::generate_from_spec _spec "$@"
EOF
  } > "${server}"
  chmod +x "${server}"
}

# Runs the fixture server on the request file given.
_mcp_serve() {
  run --separate-stderr env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES "${server}" mcp < "$1"
}

@test "dybatpho::agent_mcp_serve no arg" {
  run dybatpho::agent_mcp_serve
  assert_failure
}

@test "dybatpho::agent_mcp_serve answers a scripted session line by line" {
  _mcp_server_fixture
  local requests="${BATS_TEST_TMPDIR}/requests"
  cat > "${requests}" << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"bats","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}

{"jsonrpc":"2.0","id":"p","method":"ping"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"mytool","arguments":{"who":"-world","greeting":"hi there"}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"mytool_fail","arguments":{}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"mytool","arguments":{"bogus":1}}}
{"jsonrpc":"2.0","id":6,"method":"resources/list"}
not json
{"jsonrpc":"2.0","id":7}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"mytool_nope"}}
{"jsonrpc":"2.0","id":9,"result":{}}
EOF
  _mcp_serve "${requests}"
  assert_success
  # The notification, the blank line and the client's response get no reply.
  assert_equal "${#lines[@]}" 10
  local line
  for line in "${lines[@]}"; do
    assert_equal "$(jq -r '.jsonrpc' <<< "${line}")" "2.0"
  done
  assert_equal "$(jq -c '[.id, .result.protocolVersion, .result.capabilities, .result.serverInfo.name]' \
    <<< "${lines[0]}")" '[1,"2025-03-26",{"tools":{}},"mytool"]'
  assert_equal "$(jq -c '[.id, .result]' <<< "${lines[1]}")" '["p",{}]'
  assert_equal "$(jq -c '[.result.tools[].name]' <<< "${lines[2]}")" \
    '["mytool","mytool_fail","mytool_slow","mytool_leave","mytool_wait"]'
  assert_equal "$(jq -c '[.result.tools[] | keys[]] | unique' <<< "${lines[2]}")" \
    '["description","inputSchema","name"]'
  assert_equal "$(jq -c '.result.tools[0].inputSchema.required' <<< "${lines[2]}")" '["who"]'
  assert_equal "$(jq -c '.result | [.isError, .structuredContent.greeting, .structuredContent.mode,
    .structuredContent.stdin, (.content | length)]' <<< "${lines[3]}")" '[false,"hi there -world","on","",1]'
  assert_equal "$(jq -c '.result | [.isError, .content[].text, has("structuredContent")]' <<< "${lines[4]}")" \
    '[true,"partial\n","stderr:\nwent wrong\n",false]'
  assert_equal "$(jq -c '[.id, .error.code, .error.message]' <<< "${lines[5]}")" '[5,-32602,"Unknown argument bogus"]'
  assert_equal "$(jq -c '[.id, .error.code]' <<< "${lines[6]}")" '[6,-32601]'
  assert_equal "$(jq -c '[.id, .error.code]' <<< "${lines[7]}")" '[null,-32700]'
  assert_equal "$(jq -c '[.id, .error.code]' <<< "${lines[8]}")" '[7,-32600]'
  assert_equal "$(jq -c '[.id, .error.code, .error.message]' <<< "${lines[9]}")" \
    '[8,-32602,"Unknown tool mytool_nope"]'
  # The script's logging went to stderr, leaving stdout to the protocol.
  assert_stderr --partial "serving"
}

@test "dybatpho::agent_mcp_serve falls back to its newest protocol version" {
  _mcp_server_fixture
  local requests="${BATS_TEST_TMPDIR}/requests"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' > "${requests}"
  DYBATPHO_AGENT_MCP_VERSION=3.2.1 _mcp_serve "${requests}"
  assert_success
  assert_equal "$(jq -c '[.result.protocolVersion, .result.serverInfo.version]' <<< "${lines[0]}")" \
    '["2025-06-18","3.2.1"]'
  assert_equal "$(jq -r '.result.protocolVersion' <<< "${lines[1]}")" "2024-11-05"
}

@test "dybatpho::agent_mcp_serve refuses malformed requests" {
  _mcp_server_fixture
  local requests="${BATS_TEST_TMPDIR}/requests"
  cat > "${requests}" << 'EOF'
[{"jsonrpc":"2.0","id":1,"method":"ping"}]
{"jsonrpc":"1.0","id":2,"method":"ping"}
{"jsonrpc":"2.0","id":null,"method":"ping"}
{"jsonrpc":"2.0","id":3,"method":"ping","params":"x"}
{"jsonrpc":"2.0","id":4,"method":"ping"} {"jsonrpc":"2.0","id":5,"method":"ping"}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"mytool","arguments":[]}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{}}
EOF
  _mcp_serve "${requests}"
  assert_success
  assert_equal "$(printf '%s\n' "${lines[@]}" | jq -c -s 'map([.id, .error.code])')" \
    '[[null,-32600],[2,-32600],[null,-32600],[3,-32600],[null,-32600],[6,-32602],[7,-32602]]'
}

@test "dybatpho::agent_mcp_serve ends a tool call at DYBATPHO_AGENT_MCP_TIMEOUT" {
  _mcp_server_fixture
  local requests="${BATS_TEST_TMPDIR}/requests"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mytool_slow"}}' > "${requests}"
  DYBATPHO_AGENT_MCP_TIMEOUT=1 _mcp_serve "${requests}"
  assert_success
  assert_equal "$(jq -c '[.result.isError, .result.content[-1].text]' <<< "${lines[0]}")" \
    '[true,"Timed out after 1 seconds"]'
}

@test "dybatpho::agent_mcp_serve ends what a tool left running when the call returns" {
  # The temporary files were shared by every call, so a process a tool left
  # behind wrote into a later call's result, even as its structuredContent.
  _mcp_server_fixture
  local requests="${BATS_TEST_TMPDIR}/requests"
  export MCP_MARK="${BATS_TEST_TMPDIR}/straggler"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mytool_leave"}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mytool_wait"}}' > "${requests}"
  _mcp_serve "${requests}"
  assert_success
  assert_equal "$(jq -c '.result.content' <<< "${lines[0]}")" '[{"type":"text","text":"first\n"}]'
  assert_equal "$(jq -c '.result' <<< "${lines[1]}")" '{"content":[{"type":"text","text":"second\n"}],"isError":false}'
  sleep 1
  assert_file_not_exist "${MCP_MARK}"
}

@test "dybatpho::agent_mcp_serve rejects an invalid timeout" {
  _mcp_server_fixture
  DYBATPHO_AGENT_MCP_TIMEOUT=soon _mcp_serve /dev/null
  assert_failure
  assert_stderr --partial "DYBATPHO_AGENT_MCP_TIMEOUT must be a number of seconds"
  assert_output ""
}

@test "dybatpho::agent_mcp_serve ends with success at end of input" {
  _mcp_server_fixture
  _mcp_serve /dev/null
  assert_success
  assert_output ""
}

@test "dybatpho::agent_mcp_serve refuses two commands with the same tool name" {
  _spec_test_clash() {
    dybatpho::opts::setup "Clash" ARGS action:":"
    dybatpho::opts::cmd a-b _spec_test_deploy
    dybatpho::opts::cmd a_b _spec_test_deploy
  }
  run dybatpho::agent_mcp_serve _spec_test_clash tool /bin/tool < /dev/null
  assert_failure
  assert_output --partial "Two commands share the tool name 'tool_a_b'"
}

@test "the MCP argv builder round-trips arguments through the parser" {
  _rt_table
  local args nl=$'\n'
  args=$(jq -c -n --arg nl "${nl}" '{"verbose": true, "color": false, "tag": ("-x y=z" + $nl + "line 日本 $(id)"),
    "short": "--verbose", "item": ["-a", "b=c", "--"], "need": "-", "src": "--", "extra": ["a b", "-e", "--help"]}')
  local -a argv=()
  local reason
  run_traced __dybatpho_agent_mcp_argv_into argv reason "${table}" "{\"name\":\"rt\",\"arguments\":${args}}"
  assert_success
  __dybatpho_agent_mcp_argv_into argv reason "${table}" "{\"name\":\"rt\",\"arguments\":${args}}"
  assert_equal "${argv[0]}" "/bin/rt"
  # A value starting with `-` stays glued to its switch, in one element.
  assert_equal "${argv[3]}" "--tag=-x y=z${nl}line 日本 \$(id)"
  dybatpho::generate_from_spec _spec_test_rt "${argv[@]:1}"
  local parsed
  # A `multiple:` param is stored by the parser as one space-joined string.
  parsed=$(jq -c -n --arg verbose "${VERBOSE}" --arg color "${COLOR}" --arg tag "${TAG}" --arg short "${SHORT}" \
    --arg item "${ITEM}" --arg need "${NEED}" --arg src "${SRC}" --args \
    '{"verbose": ($verbose == "true"), "color": ($color == "true"), "tag": $tag, "short": $short,
      "item": ($item | split(" ")), "need": $need, "src": $src, "extra": $ARGS.positional}' -- "${EXTRA[@]}")
  assert_equal "${parsed}" "$(jq -c '.' <<< "${args}")"
}

@test "the MCP argv builder passes a param as one element and positionals after --" {
  _rt_table
  local -a argv=()
  local reason
  __dybatpho_agent_mcp_argv_into argv reason "${table}" \
    '{"name":"rt","arguments":{"need":"-n","short":"-x","color":true,"verbose":false,"src":"s","item":null}}'
  assert_equal "$(printf '<%s>' "${argv[@]}")" "</bin/rt><--color><-s><-x><--need=-n><--><s>"
}

@test "the MCP argv builder refuses what the schema does not allow" {
  _rt_table
  local -a argv=()
  local reason call
  local -a calls=(
    '{"name":"rt","arguments":{"need":"x","src":"s","help":true}}|Unknown argument help'
    '{"name":"rt","arguments":{"need":"x","src":"s","VERBOSE":true}}|Unknown argument VERBOSE'
    '{"name":"rt","arguments":{"src":"s"}}|Missing required argument need'
    '{"name":"rt","arguments":{"need":"x"}}|Missing required argument src'
    '{"name":"rt","arguments":{"need":"x","src":"s","verbose":"yes"}}|Argument verbose must be a boolean'
    '{"name":"rt","arguments":{"need":8080,"src":"s"}}|Argument need must be a string'
    '{"name":"rt","arguments":{"need":"x","src":"s","item":"a"}}|Argument item must be an array of strings'
    '{"name":"rt","arguments":{"need":"x","src":"s","extra":[1]}}|Argument extra must be a string'
    '{"name":"rt","arguments":{"need":"a\u0000b","src":"s"}}|Argument need must not contain a NUL byte'
    '{"name":"rt","arguments":"--need x"}|Arguments must be an object'
    '{"name":"RT","arguments":{}}|Unknown tool RT'
    '{"name":"rt ","arguments":{}}|Unknown tool rt '
    '{"arguments":{}}|tools/call needs a tool name'
  )
  for call in "${calls[@]}"; do
    run_traced __dybatpho_agent_mcp_argv_into argv reason "${table}" "${call%|*}"
    assert_failure 1
    __dybatpho_agent_mcp_argv_into argv reason "${table}" "${call%|*}" || true
    assert_equal "${reason}" "${call##*|}"
  done
}

@test "the MCP argv builder refuses to turn off a negatable flag with no switch for it" {
  # A short-only negatable flag set to false built `--no--n`.
  _spec_test_short_neg() {
    dybatpho::opts::setup "Short" ARGS action:":"
    dybatpho::opts::flag "Lines" NL -n negatable:true
  }
  local tools table="${BATS_TEST_TMPDIR}/neg.json" reason
  local -a argv=()
  __dybatpho_agent_mcp_table_into tools _spec_test_short_neg neg /bin/neg
  printf '%s\n' "${tools}" > "${table}"
  run_traced __dybatpho_agent_mcp_argv_into argv reason "${table}" '{"name":"neg","arguments":{"nl":false}}'
  assert_failure 1
  __dybatpho_agent_mcp_argv_into argv reason "${table}" '{"name":"neg","arguments":{"nl":false}}' || true
  assert_equal "${reason}" "Option nl has no switch to turn it off"
  __dybatpho_agent_mcp_argv_into argv reason "${table}" '{"name":"neg","arguments":{"nl":true}}'
  assert_equal "$(printf '<%s>' "${argv[@]}")" "</bin/neg><-n>"
}

@test "the MCP argv builder counts an empty required value as missing" {
  _spec_test_empty() {
    dybatpho::opts::setup "Empty" ARGS action:":"
    dybatpho::opts::param "Needed" NEED --need required:true
    dybatpho::opts::arg "Files" FILES variadic:true
  }
  local tools table="${BATS_TEST_TMPDIR}/empty.json" reason call
  local -a argv=()
  __dybatpho_agent_mcp_table_into tools _spec_test_empty empty /bin/empty
  printf '%s\n' "${tools}" > "${table}"
  for call in '{"need":"","files":["a"]}|need' '{"need":"x","files":[]}|files'; do
    run_traced __dybatpho_agent_mcp_argv_into argv reason "${table}" "{\"name\":\"empty\",\"arguments\":${call%|*}}"
    assert_failure 1
    __dybatpho_agent_mcp_argv_into argv reason "${table}" "{\"name\":\"empty\",\"arguments\":${call%|*}}" || true
    assert_equal "${reason}" "Missing required argument ${call##*|}"
  done
}

@test "the MCP argv builder refuses a positional after an omitted one" {
  _spec_test_gap() {
    dybatpho::opts::setup "Gap" ARGS action:":"
    dybatpho::opts::arg "First" FIRST required:false
    dybatpho::opts::arg "Second" SECOND required:false
  }
  local tools table="${BATS_TEST_TMPDIR}/gap.json" reason
  local -a argv=()
  __dybatpho_agent_mcp_table_into tools _spec_test_gap gap /bin/gap
  printf '%s\n' "${tools}" > "${table}"
  run_traced __dybatpho_agent_mcp_argv_into argv reason "${table}" '{"name":"gap","arguments":{"second":"x"}}'
  assert_failure 1
  __dybatpho_agent_mcp_argv_into argv reason "${table}" '{"name":"gap","arguments":{"second":"x"}}' || true
  assert_equal "${reason}" "Argument second needs first before it"
}

@test "the MCP argv builder reports a table it cannot read as a server fault" {
  local -a argv=()
  local reason
  printf 'not json\n' > "${BATS_TEST_TMPDIR}/broken.json"
  run_traced __dybatpho_agent_mcp_argv_into argv reason "${BATS_TEST_TMPDIR}/broken.json" '{"name":"x"}'
  assert_failure 2
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

@test "__dybatpho_agent_flatten_schema walks into subcommands" {
  local flattened
  flattened=$(__dybatpho_agent_flatten_schema "$(dybatpho::generate_schema _spec_test_root mytool)")
  assert_equal "$(dybatpho::json_get "${flattened}" 'length')" "2"
  assert_equal "$(dybatpho::json_eval "${flattened}" '.[1].path')" '["mytool","deploy"]'
}

@test "__dybatpho_agent_options_filter_into handles an empty option list" {
  local filter schema
  __dybatpho_agent_options_filter_into filter
  schema=$(dybatpho::json_eval '{"options":[]}' "${filter}")
  assert_equal "${schema}" '{"type":"object","properties":{},"required":[],"additionalProperties":false}'
}

@test "__dybatpho_agent_flatten_schema walks the whole tree in one jq call" {
  # Walking the tree took around eight processes per command, plus a rewrite of
  # the growing list for each one, and later one read per command.
  local schema real_jq count="${BATS_TEST_TMPDIR}/jq-calls"
  schema="$(dybatpho::generate_schema _spec_test_root mytool)"
  real_jq="$(command -v jq)"
  dybatpho::mock_command_script jq "printf x >> '${count}'; exec '${real_jq}' \"\$@\""
  : > "${count}"
  __dybatpho_agent_flatten_schema "${schema}" > /dev/null
  assert_equal "$(< "${count}")" "x"
  dybatpho::unmock_all
}

@test "a tool name replaces every byte a tool name can't hold" {
  local name
  __dybatpho_agent_tool_name_into name "my tool_é-1"
  assert_equal "${name}" "my_tool____1"
}

@test "__dybatpho_agent_allowed matches whole words only" {
  DYBATPHO_AGENT_ALLOW="deploy rollback"
  run_traced __dybatpho_agent_allowed deploy
  assert_success
  run_traced __dybatpho_agent_allowed rollback
  assert_success
  run_traced __dybatpho_agent_allowed deplo
  assert_failure
}

@test "dybatpho::agent_detect stops the script on an unknown mode" {
  # It used to read the mode through `$(...)`, so an unknown mode ended only
  # that subshell and the caller carried on as though a person were driving.
  local script="${BATS_TEST_TMPDIR}/detect.sh"
  {
    printf '. %q --modules agent\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'if ! dybatpho::agent_detect; then printf "carried on as a person\n"; fi'
  } > "${script}"
  DYBATPHO_AGENT_MODE=sometimes \
    run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_output --partial "Unknown mode 'sometimes'"
  refute_output --partial "carried on"
}

@test "a spec read by agent_tools or agent_mcp sees the caller's variables" {
  # The spec runs while the schema is generated, inside these functions' scope,
  # where `spec`, `name`, `format` and `command` hid the caller's variables.
  local spec="caller" name="caller" format="caller" command="caller"
  _scoped_spec() { dybatpho::opts::setup "seen ${spec} ${name} ${format} ${command}" ARGS action:":"; }
  run_traced dybatpho::agent_tools _scoped_spec tool anthropic
  assert_output --partial "seen caller caller caller caller"
  run_traced dybatpho::agent_mcp _scoped_spec tool ./tool.sh
  assert_output --partial "seen caller caller caller caller"
}
