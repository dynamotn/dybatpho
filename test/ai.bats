setup() {
  load test_helper
  DYBATPHO_AI_PROVIDER=anthropic
  DYBATPHO_AI_MODEL=""
  DYBATPHO_AI_BASE_URL=""
  DYBATPHO_AI_API_KEY="test-key"
  DYBATPHO_AI_SYSTEM=""
  DYBATPHO_AI_EFFORT=""
  DYBATPHO_AI_TEMPERATURE=""
  DYBATPHO_AI_CACHE=false
  DYBATPHO_AI_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  DYBATPHO_AI_MAX_CALLS=0
  DYBATPHO_AI_MAX_STEPS=10
  DYBATPHO_AI_JSON_RETRIES=2
  DYBATPHO_AI_REDACT=true
  DYBATPHO_AI_STATE_FILE="${BATS_TEST_TMPDIR}/ai-state.json"
  DRY_RUN=false
  dybatpho::ai_usage_reset
  dybatpho::ai_tool_clear
  dybatpho::secret_forget
}

# Stub curl so it writes a canned body to whatever path follows `-o`, which is
# how `dybatpho::curl_do` asks curl for the response body.
stub_curl_body() {
  local body="$1"
  local body_file="${BATS_TEST_TMPDIR}/curl-body.json"
  printf '%s' "${body}" > "${body_file}"
  stub_repeated curl ": out=\"\"; prev=\"\"; for a in \"\$@\"; do if [ \"\${prev}\" = -o ]; then out=\"\${a}\"; fi; prev=\"\${a}\"; done; if [ -n \"\${out}\" ]; then cat '${body_file}' > \"\${out}\"; fi; echo 200"
}

# Build a well-formed Anthropic response around arbitrary assistant text.
anthropic_body() {
  local block usage
  block=$(dybatpho::json_object type text text "${1:-hello}")
  usage=$(dybatpho::json_object input_tokens:json 11 output_tokens:json 7)
  dybatpho::json_object \
    model claude-opus-5 \
    stop_reason end_turn \
    content:json "[${block}]" \
    usage:json "${usage}"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_provider
# ---------------------------------------------------------------------------

@test "dybatpho::ai_provider honours a pinned provider" {
  DYBATPHO_AI_PROVIDER=ollama
  assert_equal "$(dybatpho::ai_provider)" "ollama"
}

@test "dybatpho::ai_provider rejects an unknown provider" {
  DYBATPHO_AI_PROVIDER=gemini
  run --separate-stderr dybatpho::ai_provider
  assert_failure
  assert_stderr --partial "Unknown provider"
}

@test "dybatpho::ai_provider detects anthropic from DYBATPHO_AI_API_KEY" {
  DYBATPHO_AI_PROVIDER=auto
  assert_equal "$(dybatpho::ai_provider)" "anthropic"
}

@test "dybatpho::ai_provider detects anthropic from ANTHROPIC_API_KEY" {
  DYBATPHO_AI_PROVIDER=auto
  DYBATPHO_AI_API_KEY=""
  ANTHROPIC_API_KEY="from-env"
  assert_equal "$(dybatpho::ai_provider)" "anthropic"
}

@test "dybatpho::ai_provider prefers anthropic over openai" {
  DYBATPHO_AI_PROVIDER=auto
  DYBATPHO_AI_API_KEY=""
  ANTHROPIC_API_KEY="a"
  OPENAI_API_KEY="b"
  assert_equal "$(dybatpho::ai_provider)" "anthropic"
}

@test "dybatpho::ai_provider detects openai when only its key is present" {
  DYBATPHO_AI_PROVIDER=auto
  DYBATPHO_AI_API_KEY=""
  unset ANTHROPIC_API_KEY
  OPENAI_API_KEY="only-openai"
  assert_equal "$(dybatpho::ai_provider)" "openai"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_model
# ---------------------------------------------------------------------------

@test "dybatpho::ai_model defaults per provider" {
  assert_equal "$(dybatpho::ai_model anthropic)" "${DYBATPHO_AI_ANTHROPIC_MODEL}"
  assert_equal "$(dybatpho::ai_model openai)" "${DYBATPHO_AI_OPENAI_MODEL}"
  assert_equal "$(dybatpho::ai_model ollama)" "${DYBATPHO_AI_OLLAMA_MODEL}"
}

@test "dybatpho::ai_model prefers an explicit model over every default" {
  DYBATPHO_AI_MODEL="my-model"
  assert_equal "$(dybatpho::ai_model ollama)" "my-model"
}

@test "dybatpho::ai_model rejects an unknown provider" {
  run --separate-stderr dybatpho::ai_model nowhere
  assert_failure
  assert_stderr --partial "Unknown provider"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_check
# ---------------------------------------------------------------------------

@test "dybatpho::ai_check fails when the anthropic key is missing" {
  DYBATPHO_AI_API_KEY=""
  unset ANTHROPIC_API_KEY
  run --separate-stderr dybatpho::ai_check
  assert_failure
  assert_stderr --partial "ANTHROPIC_API_KEY"
}

@test "dybatpho::ai_check passes when a key is present" {
  run_traced dybatpho::ai_check
  assert_success
}

@test "dybatpho::ai_check needs no key for ollama" {
  DYBATPHO_AI_PROVIDER=ollama
  DYBATPHO_AI_API_KEY=""
  run_traced dybatpho::ai_check
  assert_success
}

# ---------------------------------------------------------------------------
# Conversations
# ---------------------------------------------------------------------------

@test "dybatpho::ai_conversation_new no arg" {
  run dybatpho::ai_conversation_new
  assert_failure
}

@test "dybatpho::ai_conversation_new stores the system prompt" {
  local chat
  dybatpho::ai_conversation_new chat "Be terse"
  assert_file_exist "${chat}"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.system')" "Be terse"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages | length')" "0"
}

@test "dybatpho::ai_conversation_add appends a turn" {
  local chat
  dybatpho::ai_conversation_new chat ""
  dybatpho::ai_conversation_add "${chat}" user "first"
  dybatpho::ai_conversation_add "${chat}" assistant "second"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages | length')" "2"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages[1].role')" "assistant"
}

@test "dybatpho::ai_conversation_add rejects an unknown role" {
  local chat
  dybatpho::ai_conversation_new chat ""
  run --separate-stderr dybatpho::ai_conversation_add "${chat}" system "nope"
  assert_failure
  assert_stderr --partial "Unknown role"
}

@test "dybatpho::ai_conversation_add rejects a missing file" {
  run --separate-stderr dybatpho::ai_conversation_add "${BATS_TEST_TMPDIR}/absent.json" user "x"
  assert_failure
  assert_stderr --partial "is not a conversation file"
}

@test "dybatpho::ai_conversation_add preserves special characters" {
  local chat
  dybatpho::ai_conversation_new chat ""
  dybatpho::ai_conversation_add "${chat}" user 'quote " backslash \ newline'
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages[0].content')" 'quote " backslash \ newline'
}

@test "dybatpho::ai_conversation_show prints the transcript" {
  local chat
  dybatpho::ai_conversation_new chat "sys"
  dybatpho::ai_conversation_add "${chat}" user "hi"
  run_traced dybatpho::ai_conversation_show "${chat}"
  assert_success
  assert_line "system: sys"
  assert_line "user: hi"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_ask
# ---------------------------------------------------------------------------

@test "dybatpho::ai_ask no arg" {
  run dybatpho::ai_ask
  assert_failure
}

@test "dybatpho::ai_ask returns the assistant text" {
  stub_curl_body "$(anthropic_body 'the answer')"
  run_traced dybatpho::ai_ask "the question"
  unstub curl
  assert_success
  assert_output "the answer"
}

@test "dybatpho::ai_ask records token usage" {
  stub_curl_body "$(anthropic_body)"
  run_traced dybatpho::ai_ask "q"
  unstub curl
  assert_equal "$(dybatpho::ai_usage_field last_input)" "11"
  assert_equal "$(dybatpho::ai_usage_field last_output)" "7"
  assert_equal "$(dybatpho::ai_usage_field last_stop_reason)" "end_turn"
}

@test "dybatpho::ai_ask fails when the provider returns an error object" {
  stub_curl_body '{"error":{"type":"invalid_request_error","message":"bad model"}}'
  run --separate-stderr dybatpho::ai_ask "q"
  unstub curl
  assert_failure
  assert_stderr --partial "bad model"
}

@test "dybatpho::ai_ask extracts text from an openai response" {
  DYBATPHO_AI_PROVIDER=openai
  OPENAI_API_KEY="k"
  stub_curl_body '{"model":"gpt","choices":[{"finish_reason":"stop","message":{"content":"openai text"}}],"usage":{"prompt_tokens":3,"completion_tokens":4}}'
  run_traced dybatpho::ai_ask "q"
  unstub curl
  assert_output "openai text"
  assert_equal "$(dybatpho::ai_usage_field last_input)" "3"
}

@test "dybatpho::ai_ask extracts text from an ollama response" {
  DYBATPHO_AI_PROVIDER=ollama
  stub_curl_body '{"model":"llama","done_reason":"stop","message":{"content":"local text"},"prompt_eval_count":5,"eval_count":6}'
  run_traced dybatpho::ai_ask "q"
  unstub curl
  assert_output "local text"
  assert_equal "$(dybatpho::ai_usage_field last_output)" "6"
}

@test "dybatpho::ai_ask masks registered secrets before sending" {
  local args_file="${BATS_TEST_TMPDIR}/curl-args"
  dybatpho::secret_register "swordfish-token"
  printf '%s' "$(anthropic_body)" > "${BATS_TEST_TMPDIR}/body.json"
  stub_repeated curl ": echo \"\$*\" >> ${args_file}; out=\"\"; prev=\"\"; for a in \"\$@\"; do if [ \"\${prev}\" = -o ]; then out=\"\${a}\"; fi; prev=\"\${a}\"; done; cat ${BATS_TEST_TMPDIR}/body.json > \"\${out}\"; echo 200"
  run_traced dybatpho::ai_ask "my key is swordfish-token"
  unstub curl
  assert_success
  run grep -c "swordfish-token" "${args_file}"
  assert_failure
}

@test "dybatpho::ai_ask stops when the call budget is exhausted" {
  dybatpho::ai_budget 1
  stub_curl_body "$(anthropic_body)"
  run_traced dybatpho::ai_ask "first"
  assert_success
  run --separate-stderr dybatpho::ai_ask "second"
  unstub curl
  assert_failure
  assert_stderr --partial "budget"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_chat
# ---------------------------------------------------------------------------

@test "dybatpho::ai_chat appends both turns to the conversation" {
  local chat
  dybatpho::ai_conversation_new chat "sys"
  stub_curl_body "$(anthropic_body 'a reply')"
  run_traced dybatpho::ai_chat "${chat}" "a question"
  unstub curl
  assert_output "a reply"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages | length')" "2"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages[0].content')" "a question"
  assert_equal "$(dybatpho::json_get "$(cat "${chat}")" '.messages[1].content')" "a reply"
}

@test "dybatpho::ai_chat rejects a missing conversation file" {
  run --separate-stderr dybatpho::ai_chat "${BATS_TEST_TMPDIR}/absent.json" "q"
  assert_failure
  assert_stderr --partial "is not a conversation file"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_json
# ---------------------------------------------------------------------------

@test "dybatpho::ai_json rejects an invalid schema" {
  run --separate-stderr dybatpho::ai_json "q" "not json"
  assert_failure
  assert_stderr --partial "not valid JSON"
}

@test "dybatpho::ai_json returns a parsed document" {
  stub_curl_body "$(anthropic_body '{"severity":"high"}')"
  run_traced dybatpho::ai_json "classify" '{"type":"object"}'
  unstub curl
  assert_success
  assert_output '{"severity":"high"}'
}

@test "dybatpho::ai_json strips a Markdown fence around the document" {
  local fenced
  fenced=$(printf '```json\n{"ok":true}\n```')
  stub_curl_body "$(anthropic_body "${fenced}")"
  run_traced dybatpho::ai_json "q" '{"type":"object"}'
  unstub curl
  assert_success
  assert_output '{"ok":true}'
}

@test "dybatpho::ai_json fails after exhausting its retries" {
  DYBATPHO_AI_JSON_RETRIES=2
  stub_curl_body "$(anthropic_body 'definitely not json')"
  run --separate-stderr dybatpho::ai_json "q" '{"type":"object"}'
  unstub curl
  assert_failure
  assert_stderr --partial "No valid JSON"
}

# ---------------------------------------------------------------------------
# Tool registry
# ---------------------------------------------------------------------------

_test_tool() { printf 'tool output\n'; }

@test "dybatpho::ai_tool_register no arg" {
  run dybatpho::ai_tool_register
  assert_failure
}

@test "dybatpho::ai_tool_register rejects an invalid schema" {
  run --separate-stderr dybatpho::ai_tool_register t "desc" "nope" _test_tool
  assert_failure
  assert_stderr --partial "not valid JSON"
}

@test "dybatpho::ai_tool_register rejects an undefined handler" {
  run --separate-stderr dybatpho::ai_tool_register t "desc" '{"type":"object"}' _absent_handler
  assert_failure
  assert_stderr --partial "not a defined function"
}

@test "dybatpho::ai_tool_list prints registered names in order" {
  dybatpho::ai_tool_register zulu "z" '{"type":"object"}' _test_tool
  dybatpho::ai_tool_register alpha "a" '{"type":"object"}' _test_tool
  run_traced dybatpho::ai_tool_list
  assert_line --index 0 "alpha"
  assert_line --index 1 "zulu"
}

@test "dybatpho::ai_tool_clear empties the registry" {
  dybatpho::ai_tool_register t "desc" '{"type":"object"}' _test_tool
  dybatpho::ai_tool_clear
  run_traced dybatpho::ai_tool_list
  assert_output ""
}

@test "__ai_tools_json renders the registry as tool definitions" {
  dybatpho::ai_tool_register lookup "Look something up" \
    '{"type":"object","properties":{"q":{"type":"string"}}}' _test_tool
  local tools
  tools=$(__ai_tools_json)
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].name')" "lookup"
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].description')" "Look something up"
  assert_equal "$(dybatpho::json_get "${tools}" '.[0].input_schema.properties.q.type')" "string"
}

@test "__ai_tool_invoke reports an unknown tool instead of failing" {
  run_traced __ai_tool_invoke ghost '{}'
  assert_success
  assert_output --partial "no tool named ghost"
}

@test "__ai_tool_invoke returns a failing handler as an error result" {
  _failing_tool() { echo "boom"; return 3; }
  dybatpho::ai_tool_register failing "fails" '{"type":"object"}' _failing_tool
  run_traced __ai_tool_invoke failing '{}'
  assert_success
  assert_output --partial "exited with status 3"
}

# ---------------------------------------------------------------------------
# dybatpho::ai_run
# ---------------------------------------------------------------------------

@test "dybatpho::ai_run fails when no tool is registered" {
  run --separate-stderr dybatpho::ai_run "do something"
  assert_failure
  assert_stderr --partial "No tools registered"
}

@test "dybatpho::ai_run answers directly when the model calls no tool" {
  dybatpho::ai_tool_register t "desc" '{"type":"object"}' _test_tool
  stub_curl_body "$(anthropic_body 'no tools needed')"
  run_traced dybatpho::ai_run "question"
  unstub curl
  assert_success
  assert_output "no tools needed"
}

@test "dybatpho::ai_run behaves like ai_ask on a backend without tool use" {
  DYBATPHO_AI_PROVIDER=ollama
  stub_curl_body '{"message":{"content":"plain"},"prompt_eval_count":1,"eval_count":1}'
  run_traced dybatpho::ai_run "question"
  unstub curl
  assert_output "plain"
}

@test "dybatpho::ai_run runs the tool and feeds its output back" {
  local first="${BATS_TEST_TMPDIR}/round-1.json"
  local second="${BATS_TEST_TMPDIR}/round-2.json"
  local args_file="${BATS_TEST_TMPDIR}/round-args"
  local call usage
  call=$(dybatpho::json_object type tool_use id toolu_1 name t input:json '{}')
  usage=$(dybatpho::json_object input_tokens:json 1 output_tokens:json 1)
  dybatpho::json_object \
    content:json "[${call}]" \
    stop_reason tool_use \
    usage:json "${usage}" > "${first}"
  anthropic_body 'the tool said tool output' > "${second}"
  dybatpho::ai_tool_register t "desc" '{"type":"object"}' _test_tool
  # One plan entry per round, so the second request sees the tool result.
  stub curl \
    ": out=\"\"; prev=\"\"; for a in \"\$@\"; do if [ \"\${prev}\" = -o ]; then out=\"\${a}\"; fi; prev=\"\${a}\"; done; echo \"\$*\" >> ${args_file}; cat ${first} > \"\${out}\"; echo 200" \
    ": out=\"\"; prev=\"\"; for a in \"\$@\"; do if [ \"\${prev}\" = -o ]; then out=\"\${a}\"; fi; prev=\"\${a}\"; done; echo \"\$*\" >> ${args_file}; cat ${second} > \"\${out}\"; echo 200"
  run_traced dybatpho::ai_run "question"
  unstub curl
  assert_success
  assert_output "the tool said tool output"
  # The second request must carry the tool result the handler produced.
  run grep -c "tool output" "${args_file}"
  assert_success
}

@test "dybatpho::ai_run gives up after the step limit" {
  DYBATPHO_AI_MAX_STEPS=2
  dybatpho::ai_tool_register t "desc" '{"type":"object"}' _test_tool
  stub_curl_body '{"content":[{"type":"tool_use","id":"toolu_1","name":"t","input":{}}],"usage":{"input_tokens":1,"output_tokens":1}}'
  run --separate-stderr dybatpho::ai_run "question"
  unstub curl
  assert_failure
  assert_stderr --partial "Gave up after 2 tool rounds"
}

# ---------------------------------------------------------------------------
# Payload builders
# ---------------------------------------------------------------------------

@test "__ai_payload_anthropic carries the system prompt and messages" {
  local conversation payload
  conversation=$(__ai_conversation_build "be terse" user "hello")
  payload=$(__ai_payload_anthropic "${conversation}" '[]')
  assert_equal "$(dybatpho::json_get "${payload}" '.system')" "be terse"
  assert_equal "$(dybatpho::json_get "${payload}" '.messages[0].content')" "hello"
  assert_equal "$(dybatpho::json_get "${payload}" '.max_tokens')" "${DYBATPHO_AI_MAX_TOKENS}"
}

@test "__ai_payload_anthropic omits an empty system prompt" {
  local payload
  payload=$(__ai_payload_anthropic "$(__ai_conversation_build "" user "hi")" '[]')
  assert_equal "$(dybatpho::json_get "${payload}" 'has("system")')" "false"
}

@test "__ai_payload_anthropic adds effort when it is configured" {
  DYBATPHO_AI_EFFORT=high
  local payload
  payload=$(__ai_payload_anthropic "$(__ai_conversation_build "" user "hi")" '[]')
  assert_equal "$(dybatpho::json_get "${payload}" '.output_config.effort')" "high"
}

@test "__ai_payload_anthropic adds a json schema output contract" {
  local payload
  payload=$(__ai_payload_anthropic "$(__ai_conversation_build "" user "hi")" '[]' '{"type":"object"}')
  assert_equal "$(dybatpho::json_get "${payload}" '.output_config.format.type')" "json_schema"
}

@test "__ai_payload_openai folds the system prompt into the message list" {
  local payload
  payload=$(__ai_payload_openai "$(__ai_conversation_build "sys" user "hi")" '[]')
  assert_equal "$(dybatpho::json_get "${payload}" '.messages[0].role')" "system"
  assert_equal "$(dybatpho::json_get "${payload}" '.messages[1].content')" "hi"
}

@test "__ai_payload_openai converts tools to the function shape" {
  local tools payload
  tools='[{"name":"t","description":"d","input_schema":{"type":"object"}}]'
  payload=$(__ai_payload_openai "$(__ai_conversation_build "" user "hi")" "${tools}")
  assert_equal "$(dybatpho::json_get "${payload}" '.tools[0].type')" "function"
  assert_equal "$(dybatpho::json_get "${payload}" '.tools[0].function.name')" "t"
}

@test "__ai_payload_ollama disables streaming and keeps the model" {
  local payload
  payload=$(__ai_payload_ollama "$(__ai_conversation_build "" user "hi")" '[]')
  assert_equal "$(dybatpho::json_get "${payload}" '.stream')" "false"
  assert_equal "$(dybatpho::json_get "${payload}" '.model')" "${DYBATPHO_AI_OLLAMA_MODEL}"
}

# ---------------------------------------------------------------------------
# Caching
# ---------------------------------------------------------------------------

@test "ai caching serves the second identical request from disk" {
  DYBATPHO_AI_CACHE=true
  stub_curl_body "$(anthropic_body 'cached answer')"
  run_traced dybatpho::ai_ask "same question"
  assert_output "cached answer"
  unstub curl
  # With no stub in place a real request would fail, so a hit proves the cache.
  run_traced dybatpho::ai_ask "same question"
  assert_success
  assert_output "cached answer"
  assert_equal "$(dybatpho::ai_usage_field calls)" "1"
}

@test "dybatpho::ai_cache_clear empties the cache directory" {
  DYBATPHO_AI_CACHE=true
  stub_curl_body "$(anthropic_body)"
  run_traced dybatpho::ai_ask "q"
  unstub curl
  dybatpho::ai_cache_clear
  run find "${DYBATPHO_AI_CACHE_DIR}" -name '*.json'
  assert_output ""
}

# ---------------------------------------------------------------------------
# Accounting and helpers
# ---------------------------------------------------------------------------

@test "dybatpho::ai_tokens_estimate rounds up to whole tokens" {
  assert_equal "$(dybatpho::ai_tokens_estimate "abcd")" "1"
  assert_equal "$(dybatpho::ai_tokens_estimate "abcde")" "2"
  assert_equal "$(dybatpho::ai_tokens_estimate "")" "0"
}

@test "dybatpho::ai_tokens_estimate reads stdin when no argument is given" {
  run bash -c 'printf "abcdefgh" | dybatpho::ai_tokens_estimate'
  assert_output "2"
}

@test "dybatpho::ai_usage prints last and total scopes" {
  __ai_record_usage 10 20 "m" "end_turn"
  __ai_record_usage 1 2 "m" "end_turn"
  run_traced dybatpho::ai_usage last
  assert_output --partial "input=1 output=2"
  run_traced dybatpho::ai_usage total
  assert_output --partial "input=11 output=22"
}

@test "dybatpho::ai_usage rejects an unknown scope" {
  run --separate-stderr dybatpho::ai_usage everything
  assert_failure
  assert_stderr --partial "Unknown scope"
}

@test "dybatpho::ai_usage_reset zeroes the counters" {
  __ai_record_usage 10 20 "m" "end_turn"
  dybatpho::ai_usage_reset
  run_traced dybatpho::ai_usage total
  assert_output "calls=0 input=0 output=0"
}

@test "dybatpho::ai_budget rejects a non-numeric limit" {
  run --separate-stderr dybatpho::ai_budget many
  assert_failure
  assert_stderr --partial "Expected a number"
}

@test "dybatpho::ai_redact replaces emails, addresses and long numbers" {
  run_traced dybatpho::ai_redact "mail a@b.com from 10.0.0.1 id 123456789012"
  assert_output "mail <email> from <ip> id <number>"
}

@test "dybatpho::ai_redact masks registered secrets" {
  dybatpho::secret_register "hunter2-is-a-secret"
  run_traced dybatpho::ai_redact "token hunter2-is-a-secret here"
  refute_output --partial "hunter2-is-a-secret"
}

@test "dybatpho::ai_redact reads stdin when no argument is given" {
  run bash -c 'printf "reach me at a@b.com" | dybatpho::ai_redact'
  assert_output "reach me at <email>"
}

@test "__ai_redact passes text through when redaction is disabled" {
  DYBATPHO_AI_REDACT=false
  dybatpho::secret_register "plain-secret"
  assert_equal "$(__ai_redact "plain-secret stays")" "plain-secret stays"
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------

@test "ai calls make no request under DRY_RUN" {
  DRY_RUN=true
  run_traced dybatpho::ai_ask "q"
  assert_success
  assert_output --partial "dry run"
  assert_equal "$(dybatpho::ai_usage_field calls)" "0"
}

@test "ai_json returns a parseable placeholder under DRY_RUN" {
  DRY_RUN=true
  run_traced dybatpho::ai_json "q" '{"type":"object"}'
  assert_success
  assert_output "{}"
}
