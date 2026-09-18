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
  run dybatpho::agent_detect
  assert_success
  DYBATPHO_AGENT_MODE=off
  run dybatpho::agent_detect
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
  run dybatpho::agent_error bad_input "wrong"
  assert_failure
}

@test "dybatpho::agent_error prints a structured object for an agent" {
  DYBATPHO_AGENT_MODE=on
  run dybatpho::agent_error missing_config "No config" "Run init"
  assert_equal "$(dybatpho::json_get "${output}" '.status')" "error"
  assert_equal "$(dybatpho::json_get "${output}" '.code')" "missing_config"
  assert_equal "$(dybatpho::json_get "${output}" '.message')" "No config"
  assert_equal "$(dybatpho::json_get "${output}" '.hint')" "Run init"
}

@test "dybatpho::agent_error omits an absent hint" {
  DYBATPHO_AGENT_MODE=on
  run dybatpho::agent_error bad_input "wrong"
  assert_equal "$(dybatpho::json_get "${output}" 'has("hint")')" "false"
}

@test "dybatpho::agent_error logs for a person instead of printing JSON" {
  DYBATPHO_AGENT_MODE=off
  run --separate-stderr dybatpho::agent_error missing_config "No config" "Run init"
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
  # `type` names differ between the two JSON backends, so the shape is checked
  # by what the array contains instead.
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
  run dybatpho::agent_confirm restart "Restart the API"
  assert_success
}

@test "dybatpho::agent_confirm refuses an action that is not listed" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deploy"
  run dybatpho::agent_confirm wipe "Delete everything"
  assert_failure
  assert_equal "$(dybatpho::json_get "${output}" '.status')" "refused"
  assert_equal "$(dybatpho::json_get "${output}" '.code')" "action_not_allowed"
  assert_equal "$(dybatpho::json_get "${output}" '.action')" "wipe"
}

@test "dybatpho::agent_confirm refuses everything with an empty allowlist" {
  DYBATPHO_AGENT_MODE=on
  run dybatpho::agent_confirm deploy
  assert_failure
}

@test "dybatpho::agent_confirm honours the all wildcard" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="all"
  run dybatpho::agent_confirm anything
  assert_success
}

@test "dybatpho::agent_confirm does not match a partial action name" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deployment"
  run dybatpho::agent_confirm deploy
  assert_failure
}

@test "dybatpho::agent_confirm records both decisions in the audit log" {
  DYBATPHO_AGENT_MODE=on
  DYBATPHO_AGENT_ALLOW="deploy"
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl"
  dybatpho::agent_confirm deploy "Ship it" || true
  dybatpho::agent_confirm wipe "Delete it" > /dev/null || true
  assert_file_exist "${DYBATPHO_AGENT_AUDIT_FILE}"
  assert_equal "$(wc -l < "${DYBATPHO_AGENT_AUDIT_FILE}")" "2"
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
  run dybatpho::agent_audit deploy "detail"
  assert_success
  assert_output ""
}

@test "dybatpho::agent_audit writes one JSON object per record" {
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/nested/audit.jsonl"
  dybatpho::agent_audit deploy "version 1.0"
  dybatpho::agent_audit rollback
  assert_file_exist "${DYBATPHO_AGENT_AUDIT_FILE}"
  assert_equal "$(wc -l < "${DYBATPHO_AGENT_AUDIT_FILE}")" "2"
  assert_equal "$(dybatpho::json_get "$(head -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.action')" "deploy"
  assert_equal "$(dybatpho::json_get "$(head -n 1 "${DYBATPHO_AGENT_AUDIT_FILE}")" '.detail')" "version 1.0"
}

@test "dybatpho::agent_audit_show prints the recorded actions" {
  DYBATPHO_AGENT_AUDIT_FILE="${BATS_TEST_TMPDIR}/audit.jsonl"
  dybatpho::agent_audit deploy "version 1.0"
  run_traced dybatpho::agent_audit_show
  assert_output --partial "deploy version 1.0"
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
# Internal helpers
# ---------------------------------------------------------------------------

@test "__agent_flatten_schema walks into subcommands" {
  local flattened
  flattened=$(__agent_flatten_schema "$(dybatpho::generate_schema _spec_test_root mytool)")
  assert_equal "$(dybatpho::json_get "${flattened}" 'length')" "2"
  assert_equal "$(dybatpho::json_eval "${flattened}" '.[1].path')" '["mytool","deploy"]'
}

@test "__agent_options_schema handles an empty option list" {
  local schema
  schema=$(__agent_options_schema '[]')
  assert_equal "$(dybatpho::json_get "${schema}" '.type')" "object"
  assert_equal "$(dybatpho::json_eval "${schema}" '.properties')" "{}"
  assert_equal "$(dybatpho::json_eval "${schema}" '.required')" "[]"
}

@test "__agent_allowed matches whole words only" {
  DYBATPHO_AGENT_ALLOW="deploy rollback"
  run __agent_allowed deploy
  assert_success
  run __agent_allowed rollback
  assert_success
  run __agent_allowed deplo
  assert_failure
}
