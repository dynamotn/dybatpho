setup() {
  load test_helper
}

# ---------------------------------------------------------------------------
# __notification_json_escape
# ---------------------------------------------------------------------------

@test "__notification_json_escape no arg" {
  run __notification_json_escape
  assert_failure
}

@test "__notification_json_escape plain string" {
  run __notification_json_escape "hello world"
  assert_success
  assert_output "hello world"
}

@test "__notification_json_escape escapes double quotes" {
  run __notification_json_escape 'say "hi"'
  assert_success
  assert_output 'say \"hi\"'
}

@test "__notification_json_escape escapes backslash" {
  run __notification_json_escape 'C:\path'
  assert_success
  assert_output 'C:\\path'
}

@test "__notification_json_escape escapes newline" {
  run __notification_json_escape $'line1\nline2'
  assert_success
  assert_output 'line1\nline2'
}

@test "__notification_json_escape escapes tab" {
  run __notification_json_escape $'col1\tcol2'
  assert_success
  assert_output 'col1\tcol2'
}

@test "__notification_json_escape escapes carriage return" {
  run __notification_json_escape $'text\rmore'
  assert_success
  assert_output 'text\rmore'
}

# ---------------------------------------------------------------------------
# dybatpho::notify_slack
# ---------------------------------------------------------------------------

@test "dybatpho::notify_slack no arg" {
  run dybatpho::notify_slack
  assert_failure
}

@test "dybatpho::notify_slack missing env" {
  unset DYBATPHO_SLACK_WEBHOOK_URL
  run --separate-stderr dybatpho::notify_slack "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_SLACK_WEBHOOK_URL"
}

@test "dybatpho::notify_slack sends POST with JSON payload" {
  local args_file="${BATS_TEST_TMPDIR}/slack-curl-args"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_slack "hello slack"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '--data {"text":"hello slack"}' "${args_file}"
  grep -- '--header Content-Type: application/json' "${args_file}"
}

@test "dybatpho::notify_slack escapes special characters in message" {
  local args_file="${BATS_TEST_TMPDIR}/slack-escape-args"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_slack 'say "hi"'
  unstub curl
  assert_success
  grep -- '--data {"text":"say \\\"hi\\\""}' "${args_file}"
}

@test "dybatpho::notify_slack uses DYBATPHO_SLACK_WEBHOOK_URL as endpoint" {
  local args_file="${BATS_TEST_TMPDIR}/slack-url-args"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/MYTOKEN"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_slack "test"
  unstub curl
  assert_success
  grep "https://hooks.slack.com/services/MYTOKEN" "${args_file}"
}

# ---------------------------------------------------------------------------
# dybatpho::notify_telegram
# ---------------------------------------------------------------------------

@test "dybatpho::notify_telegram no arg" {
  run dybatpho::notify_telegram
  assert_failure
}

@test "dybatpho::notify_telegram missing env" {
  unset DYBATPHO_TELEGRAM_BOT_TOKEN DYBATPHO_TELEGRAM_CHAT_ID
  run --separate-stderr dybatpho::notify_telegram "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_TELEGRAM_BOT_TOKEN"
}

@test "dybatpho::notify_telegram sends POST with chat_id and text" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-curl-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_telegram "build done"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '"chat_id":"-100999"' "${args_file}"
  grep -- '"text":"build done"' "${args_file}"
}

@test "dybatpho::notify_telegram uses bot token in URL" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-url-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_telegram "test"
  unstub curl
  assert_success
  grep "api.telegram.org/bot123:TOKEN/sendMessage" "${args_file}"
}

@test "dybatpho::notify_telegram with parse_mode includes parse_mode field" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-parse-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_telegram "**bold**" "Markdown"
  unstub curl
  assert_success
  grep -- '"parse_mode":"Markdown"' "${args_file}"
}

@test "dybatpho::notify_telegram without parse_mode omits parse_mode field" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-noparse-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_telegram "plain text"
  unstub curl
  assert_success
  run grep "parse_mode" "${args_file}"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::notify_teams
# ---------------------------------------------------------------------------

@test "dybatpho::notify_teams no arg" {
  run dybatpho::notify_teams
  assert_failure
}

@test "dybatpho::notify_teams missing env" {
  unset DYBATPHO_TEAMS_WEBHOOK_URL
  run --separate-stderr dybatpho::notify_teams "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_TEAMS_WEBHOOK_URL"
}

@test "dybatpho::notify_teams sends POST with Adaptive Card payload" {
  local args_file="${BATS_TEST_TMPDIR}/teams-curl-args"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_teams "deploy done"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- 'AdaptiveCard' "${args_file}"
  grep -- '"text":"deploy done"' "${args_file}"
}

@test "dybatpho::notify_teams with title includes title TextBlock" {
  local args_file="${BATS_TEST_TMPDIR}/teams-title-args"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_teams "all checks passed" "Deploy v2.0"
  unstub curl
  assert_success
  grep -- '"text":"Deploy v2.0"' "${args_file}"
  grep -- '"text":"all checks passed"' "${args_file}"
  grep -- '"weight":"bolder"' "${args_file}"
}

@test "dybatpho::notify_teams without title omits title TextBlock" {
  local args_file="${BATS_TEST_TMPDIR}/teams-notitle-args"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_teams "simple message"
  unstub curl
  assert_success
  run grep '"weight":"bolder"' "${args_file}"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::notify_google_chat
# ---------------------------------------------------------------------------

@test "dybatpho::notify_google_chat no arg" {
  run dybatpho::notify_google_chat
  assert_failure
}

@test "dybatpho::notify_google_chat missing env" {
  unset DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL
  run --separate-stderr dybatpho::notify_google_chat "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL"
}

@test "dybatpho::notify_google_chat sends POST with text payload" {
  local args_file="${BATS_TEST_TMPDIR}/gchat-curl-args"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_google_chat "release live"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '--data {"text":"release live"}' "${args_file}"
}

@test "dybatpho::notify_google_chat uses DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL as endpoint" {
  local args_file="${BATS_TEST_TMPDIR}/gchat-url-args"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/MYSPACE"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_google_chat "test"
  unstub curl
  assert_success
  grep "https://chat.googleapis.com/v1/spaces/MYSPACE" "${args_file}"
}

# ---------------------------------------------------------------------------
# dybatpho::notify_discord
# ---------------------------------------------------------------------------

@test "dybatpho::notify_discord no arg" {
  run dybatpho::notify_discord
  assert_failure
}

@test "dybatpho::notify_discord missing env" {
  unset DYBATPHO_DISCORD_WEBHOOK_URL
  run --separate-stderr dybatpho::notify_discord "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_DISCORD_WEBHOOK_URL"
}

@test "dybatpho::notify_discord sends POST with content payload" {
  local args_file="${BATS_TEST_TMPDIR}/discord-curl-args"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_discord "build passed"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '"content":"build passed"' "${args_file}"
}

@test "dybatpho::notify_discord with username includes username field" {
  local args_file="${BATS_TEST_TMPDIR}/discord-user-args"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_discord "deploy done" "CI Bot"
  unstub curl
  assert_success
  grep -- '"username":"CI Bot"' "${args_file}"
}

@test "dybatpho::notify_discord without username omits username field" {
  local args_file="${BATS_TEST_TMPDIR}/discord-nouser-args"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_discord "simple"
  unstub curl
  assert_success
  run grep '"username"' "${args_file}"
  assert_failure
}

# ---------------------------------------------------------------------------
# dybatpho::notify_webhook
# ---------------------------------------------------------------------------

@test "dybatpho::notify_webhook no arg" {
  run dybatpho::notify_webhook
  assert_failure
}

@test "dybatpho::notify_webhook only url" {
  run dybatpho::notify_webhook "https://my.service/hook"
  assert_failure
}

@test "dybatpho::notify_webhook sends POST to given URL with payload" {
  local args_file="${BATS_TEST_TMPDIR}/webhook-curl-args"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy"}'
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '--data {"event":"deploy"}' "${args_file}"
  grep "https://my.service/hook" "${args_file}"
}

@test "dybatpho::notify_webhook forwards extra curl arguments" {
  local args_file="${BATS_TEST_TMPDIR}/webhook-extra-args"
  stub curl ": echo \"\$*\" > ${args_file}; echo '200'"
  run dybatpho::notify_webhook "https://my.service/hook" '{"event":"test"}' \
    --header "Authorization: Bearer SECRET"
  unstub curl
  assert_success
  grep -- '--header Authorization: Bearer SECRET' "${args_file}"
}
