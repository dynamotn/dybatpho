setup() {
  load test_helper
}

# A curl stub that records what a request sent: its arguments, then what went
# out of band, the `--config` file holding the URL and secret headers and the
# body read from standard input. Every notifier sends the URL and the body that
# way, so a test asserting on them reads the whole record.
stub_curl_recording() {
  local record="$1" status="${2:-200}"
  stub curl ": echo \"\$*\" > ${record}; prev=; for a in \"\$@\"; do [ \"\$prev\" = --config ] && cat \"\$a\" >> ${record}; [ \"\$a\" = @- ] && cat >> ${record}; prev=\$a; done; printf '${status}'"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_slack "hello slack"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '{"text":"hello slack"}' "${args_file}"
  grep -- '--header Content-Type: application/json' "${args_file}"
}

@test "a notification keeps its URL, token and message off curl's command line" {
  # Every account on the host can read a process's arguments, and a webhook URL
  # is the credential itself; Telegram's bot token sits in its path.
  local args_file="${BATS_TEST_TMPDIR}/argv" config_file="${BATS_TEST_TMPDIR}/out-of-band"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T0/B0/WebhookSecret"
  stub_curl_with_config "${args_file}" "${config_file}"
  run_traced dybatpho::notify_slack "private message"
  unstub curl
  assert_success
  run_traced grep -e "WebhookSecret" -e "private message" "${args_file}"
  assert_failure
  grep -- 'url = "https://hooks.slack.com/services/T0/B0/WebhookSecret"' "${config_file}"
  grep -- '{"text":"private message"}' "${config_file}"

  rm -f "${args_file}" "${config_file}"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:BotSecret" DYBATPHO_TELEGRAM_CHAT_ID="-1"
  stub_curl_with_config "${args_file}" "${config_file}"
  run_traced dybatpho::notify_telegram "private message"
  unstub curl
  assert_success
  run_traced grep -e "BotSecret" -e "private message" "${args_file}"
  assert_failure
  grep -- 'url = "https://api.telegram.org/bot123:BotSecret/sendMessage"' "${config_file}"
}

@test "dybatpho::notify_slack escapes special characters in message" {
  local args_file="${BATS_TEST_TMPDIR}/slack-escape-args"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_slack 'say "hi"'
  unstub curl
  assert_success
  grep -- '{"text":"say \\\"hi\\\""}' "${args_file}"
}

@test "dybatpho::notify_slack uses DYBATPHO_SLACK_WEBHOOK_URL as endpoint" {
  local args_file="${BATS_TEST_TMPDIR}/slack-url-args"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/MYTOKEN"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_slack "test"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_telegram "build done"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_telegram "test"
  unstub curl
  assert_success
  grep "api.telegram.org/bot123:TOKEN/sendMessage" "${args_file}"
}

@test "dybatpho::notify_telegram with parse_mode includes parse_mode field" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-parse-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_telegram "**bold**" "Markdown"
  unstub curl
  assert_success
  grep -- '"parse_mode":"Markdown"' "${args_file}"
}

@test "dybatpho::notify_telegram without parse_mode omits parse_mode field" {
  local args_file="${BATS_TEST_TMPDIR}/telegram-noparse-args"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123:TOKEN"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100999"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_telegram "plain text"
  unstub curl
  assert_success
  run_traced grep "parse_mode" "${args_file}"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_teams "deploy done"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- 'AdaptiveCard' "${args_file}"
  grep -- '"text":"deploy done"' "${args_file}"
}

@test "dybatpho::notify_teams with title includes title TextBlock" {
  local args_file="${BATS_TEST_TMPDIR}/teams-title-args"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/TEST"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_teams "all checks passed" "Deploy v2.0"
  unstub curl
  assert_success
  grep -- '"text":"Deploy v2.0"' "${args_file}"
  grep -- '"text":"all checks passed"' "${args_file}"
  grep -- '"weight":"bolder"' "${args_file}"
}

@test "dybatpho::notify_teams without title omits title TextBlock" {
  local args_file="${BATS_TEST_TMPDIR}/teams-notitle-args"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/TEST"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_teams "simple message"
  unstub curl
  assert_success
  run_traced grep '"weight":"bolder"' "${args_file}"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_google_chat "release live"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '{"text":"release live"}' "${args_file}"
}

@test "dybatpho::notify_google_chat uses DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL as endpoint" {
  local args_file="${BATS_TEST_TMPDIR}/gchat-url-args"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/MYSPACE"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_google_chat "test"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_discord "build passed"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '"content":"build passed"' "${args_file}"
}

@test "dybatpho::notify_discord with username includes username field" {
  local args_file="${BATS_TEST_TMPDIR}/discord-user-args"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_discord "deploy done" "CI Bot"
  unstub curl
  assert_success
  grep -- '"username":"CI Bot"' "${args_file}"
}

@test "dybatpho::notify_discord without username omits username field" {
  local args_file="${BATS_TEST_TMPDIR}/discord-nouser-args"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_discord "simple"
  unstub curl
  assert_success
  run_traced grep '"username"' "${args_file}"
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
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy"}'
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '{"event":"deploy"}' "${args_file}"
  grep "https://my.service/hook" "${args_file}"
}

@test "dybatpho::notify_webhook keeps the webhook URL out of its debug line" {
  stub curl ": echo '200'"
  LOG_LEVEL=debug run_traced --separate-stderr dybatpho::notify_webhook \
    "https://hooks.example.test/services/T000/B000/XXXXSECRET?token=abc" '{}'
  unstub curl
  assert_success
  assert_stderr --partial "Sending webhook notification to https://hooks.example.test/[redacted]"
  refute_stderr --partial "XXXXSECRET"
  refute_stderr --partial "token=abc"
}

@test "dybatpho::notify_webhook forwards extra curl arguments" {
  local args_file="${BATS_TEST_TMPDIR}/webhook-extra-args"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_webhook "https://my.service/hook" '{"event":"test"}' \
    --header "Authorization: Bearer SECRET"
  unstub curl
  assert_success
  grep -- '--header Authorization: Bearer SECRET' "${args_file}"
}

@test "notification helpers return HTTP client status codes" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  export DYBATPHO_CURL_MAX_RETRIES=0
  stub curl ": printf '404'"
  run_traced dybatpho::notify_slack "not found"
  assert_failure 4
  unstub curl

  stub curl ": printf '503'"
  run_traced dybatpho::notify_slack "unavailable"
  assert_failure 5
  unstub curl
}

@test "notification helpers escape all JSON control characters" {
  local args_file="${BATS_TEST_TMPDIR}/notification-escape-args"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/TEST"
  stub_curl_recording "${args_file}"
  dybatpho::notify_google_chat $'slash\\quote"\nreturn\rtab\t'
  unstub curl
  run_traced cat "${args_file}"
  assert_success
  assert_output --partial 'slash\\quote\"'
  assert_output --partial '\nreturn'
  assert_output --partial '\rtab\t'
}

@test "a notification payload spells out every control character" {
  # A notification usually carries the output of the command that failed,
  # colour codes and all. Left raw, a control character makes the payload
  # something the webhook refuses, so the message never arrives.
  local message
  message="$(printf 'build \033[31mFAILED\033[0m\a on nhánh "main"')"
  local payload
  payload="$(printf '{"text":"%s"}' "$(__dybatpho_log_json_escape "${message}")")"
  run_traced jq -e . <<< "${payload}"
  assert_success
  assert_equal "$(jq -r '.text' <<< "${payload}")" "${message}"
}

# ---------------------------------------------------------------------------
# dybatpho::notify_desktop
# ---------------------------------------------------------------------------

# A PATH holding only the named fake backends, plus the `date` the logger reads,
# so the real `notify-send` of the host is never reached and "installed" means
# exactly what the test says. Each fake writes its arguments one per line.
desktop_path() {
  local bin="${BATS_TEST_TMPDIR}/desktop-bin" name
  mkdir -p "${bin}"
  ln -sf "$(command -v date)" "${bin}/date"
  for name in "$@"; do
    printf '#!/bin/sh\nfor arg in "$@"; do printf "%%s\\n" "$arg"; done > %q\n' \
      "${BATS_TEST_TMPDIR}/${name}.args" > "${bin}/${name}"
    chmod +x "${bin}/${name}"
  done
  printf '%s' "${bin}"
}

@test "dybatpho::notify_desktop no arg" {
  run dybatpho::notify_desktop
  assert_failure
}

@test "dybatpho::notify_desktop rejects an empty title" {
  local bin
  bin="$(desktop_path notify-send)"
  PATH="${bin}" run -1 dybatpho::notify_desktop ""
  assert_output --partial "title must not be empty"
  [ ! -e "${BATS_TEST_TMPDIR}/notify-send.args" ]
}

@test "dybatpho::notify_desktop rejects an unknown urgency" {
  local bin
  bin="$(desktop_path notify-send)"
  PATH="${bin}" run -1 dybatpho::notify_desktop "Title" "Body" urgent
  assert_output --partial "urgency must be low, normal or critical, not 'urgent'"
  [ ! -e "${BATS_TEST_TMPDIR}/notify-send.args" ]
}

@test "dybatpho::notify_desktop passes title, body and urgency to notify-send" {
  local bin
  bin="$(desktop_path notify-send osascript)"
  PATH="${bin}" run_traced -0 dybatpho::notify_desktop "Backup done" "42 files" critical
  run_traced cat "${BATS_TEST_TMPDIR}/notify-send.args"
  assert_line --index 0 "--urgency=critical"
  assert_equal "${lines[1]}" "--"
  assert_line --index 2 "Backup done"
  assert_line --index 3 "42 files"
  [ ! -e "${BATS_TEST_TMPDIR}/osascript.args" ]
}

@test "dybatpho::notify_desktop defaults to normal urgency and omits an empty body" {
  local bin
  bin="$(desktop_path notify-send)"
  PATH="${bin}" run_traced -0 dybatpho::notify_desktop "Only a title"
  run_traced cat "${BATS_TEST_TMPDIR}/notify-send.args"
  assert_output $'--urgency=normal\n--\nOnly a title'
}

@test "dybatpho::notify_desktop passes a title that looks like a flag verbatim" {
  local bin
  bin="$(desktop_path notify-send)"
  PATH="${bin}" run_traced -0 dybatpho::notify_desktop "-u low" 'say "hi" $(id)'
  run_traced cat "${BATS_TEST_TMPDIR}/notify-send.args"
  assert_equal "${lines[2]}" "-u low"
  assert_line --index 3 'say "hi" $(id)'
}

@test "dybatpho::notify_desktop falls back to osascript with the words as argv" {
  local bin
  bin="$(desktop_path osascript)"
  PATH="${bin}" run_traced -0 dybatpho::notify_desktop '-Deploy "v2"' 'end tell' low
  run_traced cat "${BATS_TEST_TMPDIR}/osascript.args"
  assert_equal "${lines[0]}" "-e"
  assert_line --index 1 "on run argv"
  assert_line --index 3 "display notification (item 3 of argv) with title (item 2 of argv)"
  assert_line --index 6 "dybatpho"
  assert_equal "${lines[7]}" '-Deploy "v2"'
  assert_line --index 8 "end tell"
}

@test "dybatpho::notify_desktop fails with 127 when no backend is installed" {
  local bin
  bin="$(desktop_path)"
  PATH="${bin}" run -127 dybatpho::notify_desktop "Title"
  assert_output --partial "No desktop notification backend"
}

@test "dybatpho::notify_desktop returns the backend's exit code" {
  local bin
  bin="$(desktop_path)"
  printf '#!/bin/sh\nexit 3\n' > "${bin}/notify-send"
  chmod +x "${bin}/notify-send"
  PATH="${bin}" run_traced -3 dybatpho::notify_desktop "No session"
}

@test "dybatpho::notify_desktop prints the command under DRY_RUN" {
  local bin
  bin="$(desktop_path notify-send)"
  DRY_RUN=true PATH="${bin}" run_traced -0 dybatpho::notify_desktop "Title" "Body"
  assert_output --partial "DRY RUN: notify-send --urgency=normal -- Title Body"
  [ ! -e "${BATS_TEST_TMPDIR}/notify-send.args" ]
}

@test "dybatpho::notify_desktop prints the notify-send form under DRY_RUN with no backend" {
  local bin
  bin="$(desktop_path)"
  DRY_RUN=true PATH="${bin}" run_traced -0 dybatpho::notify_desktop "Title"
  assert_output --partial "DRY RUN: notify-send --urgency=normal -- Title"
}

# ---------------------------------------------------------------------------
# dybatpho::notify_ntfy
# ---------------------------------------------------------------------------

# A curl stub that keeps the arguments apart from what went out of band: the
# `--config` file, with the URL and the secret headers, and the body on
# standard input are recorded in the second file.
stub_curl_with_config() {
  local args_file="$1" config_file="$2"
  stub curl ": echo \"\$*\" > ${args_file}; prev=; for a in \"\$@\"; do [ \"\$prev\" = --config ] && cat \"\$a\" >> ${config_file}; [ \"\$a\" = @- ] && cat >> ${config_file}; prev=\$a; done; echo '200'"
}

@test "dybatpho::notify_ntfy no arg" {
  run dybatpho::notify_ntfy
  assert_failure
}

@test "dybatpho::notify_ntfy missing env" {
  unset DYBATPHO_NTFY_TOPIC
  run --separate-stderr dybatpho::notify_ntfy "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_NTFY_TOPIC"
}

@test "dybatpho::notify_ntfy posts topic and message to ntfy.sh by default" {
  local args_file="${BATS_TEST_TMPDIR}/ntfy-args"
  export DYBATPHO_NTFY_TOPIC="backups-7f3a"
  unset DYBATPHO_NTFY_URL DYBATPHO_NTFY_TOKEN
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_ntfy "Backup finished"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '{"topic":"backups-7f3a","message":"Backup finished"}' "${args_file}"
  grep -- 'url = "https://ntfy.sh"' "${args_file}"
  run_traced grep -- 'Authorization' "${args_file}"
  assert_failure
}

@test "dybatpho::notify_ntfy adds title, named priority and trimmed tags" {
  local args_file="${BATS_TEST_TMPDIR}/ntfy-full-args"
  export DYBATPHO_NTFY_TOPIC="ops"
  export DYBATPHO_NTFY_URL="https://ntfy.example.test///"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_ntfy 'Disk "/var" at 97%' "Disk almost full" urgent " warning, ,floppy_disk "
  unstub curl
  assert_success
  grep -- '"message":"Disk \\"/var\\" at 97%"' "${args_file}"
  grep -- '"title":"Disk almost full"' "${args_file}"
  grep -- '"priority":5' "${args_file}"
  grep -- '"tags":\["warning","floppy_disk"\]' "${args_file}"
  grep -- 'url = "https://ntfy.example.test"' "${args_file}"
}

@test "dybatpho::notify_ntfy refuses tags holding a line break" {
  # Read from one line, the tags after a break were dropped without a word.
  export DYBATPHO_NTFY_TOPIC="ops"
  local tags
  for tags in $'warning\nfloppy_disk' $'warning\rfloppy_disk'; do
    run --separate-stderr dybatpho::notify_ntfy "m" "" "" "${tags}"
    assert_failure
    assert_stderr --partial "tags must not contain a line break"
  done
}

@test "dybatpho::notify_ntfy keeps a line break in the title" {
  local args_file="${BATS_TEST_TMPDIR}/ntfy-title-args"
  export DYBATPHO_NTFY_TOPIC="ops"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_ntfy "m" $'two\nlines'
  unstub curl
  assert_success
  grep -- '"title":"two\\nlines"' "${args_file}"
}

@test "dybatpho::notify_ntfy maps every priority name to its number" {
  local args_file="${BATS_TEST_TMPDIR}/ntfy-priority-args" name expected
  export DYBATPHO_NTFY_TOPIC="ops"
  for name in min:1 low:2 default:3 high:4 max:5 2:2; do
    expected="${name#*:}"
    stub_curl_recording "${args_file}"
    run_traced dybatpho::notify_ntfy "m" "" "${name%%:*}"
    unstub curl
    assert_success
    grep -- "\"priority\":${expected}}" "${args_file}"
  done
}

@test "dybatpho::notify_ntfy sends the token out of band" {
  local args_file="${BATS_TEST_TMPDIR}/ntfy-token-args"
  local config_file="${BATS_TEST_TMPDIR}/ntfy-token-config"
  export DYBATPHO_NTFY_TOPIC="private"
  export DYBATPHO_NTFY_TOKEN="tk_not_on_the_command_line"
  stub_curl_with_config "${args_file}" "${config_file}"
  run_traced dybatpho::notify_ntfy "secret topic"
  unstub curl
  assert_success
  run_traced grep -- "tk_not_on_the_command_line" "${args_file}"
  assert_failure
  grep -- "Authorization: Bearer tk_not_on_the_command_line" "${config_file}"
}

@test "dybatpho::notify_ntfy rejects an invalid topic" {
  export DYBATPHO_NTFY_TOPIC="has space"
  run -1 dybatpho::notify_ntfy "hello"
  assert_output --partial "topic must be 1-64 letters"
}

@test "dybatpho::notify_ntfy rejects a server URL without a scheme" {
  export DYBATPHO_NTFY_TOPIC="ops"
  export DYBATPHO_NTFY_URL="ntfy.example.test"
  run -1 dybatpho::notify_ntfy "hello"
  assert_output --partial "server URL must start with http:// or https://"
}

@test "dybatpho::notify_ntfy rejects an unknown priority" {
  export DYBATPHO_NTFY_TOPIC="ops"
  run -1 dybatpho::notify_ntfy "hello" "" 6
  assert_output --partial "priority must be 1-5"
}

@test "dybatpho::notify_ntfy returns the HTTP client status" {
  export DYBATPHO_NTFY_TOPIC="ops"
  export DYBATPHO_CURL_MAX_RETRIES=0
  stub curl ": printf '403'"
  run_traced -4 dybatpho::notify_ntfy "refused"
  unstub curl
}

# ---------------------------------------------------------------------------
# dybatpho::notify_gotify
# ---------------------------------------------------------------------------

@test "dybatpho::notify_gotify no arg" {
  run dybatpho::notify_gotify
  assert_failure
}

@test "dybatpho::notify_gotify missing env" {
  unset DYBATPHO_GOTIFY_URL DYBATPHO_GOTIFY_TOKEN
  run --separate-stderr dybatpho::notify_gotify "hello"
  assert_failure
  assert_stderr --partial "DYBATPHO_GOTIFY_URL"
}

@test "dybatpho::notify_gotify posts the message to /message with the key out of band" {
  local args_file="${BATS_TEST_TMPDIR}/gotify-args"
  local config_file="${BATS_TEST_TMPDIR}/gotify-config"
  export DYBATPHO_GOTIFY_URL="https://gotify.example.test/"
  export DYBATPHO_GOTIFY_TOKEN="AppTokenNotInArgv"
  stub_curl_with_config "${args_file}" "${config_file}"
  run_traced dybatpho::notify_gotify "Backup finished"
  unstub curl
  assert_success
  grep -- '--request POST' "${args_file}"
  grep -- '{"message":"Backup finished"}' "${config_file}"
  grep -- 'url = "https://gotify.example.test/message"' "${config_file}"
  run_traced grep -- "AppTokenNotInArgv" "${args_file}"
  assert_failure
  grep -- "X-Gotify-Key: AppTokenNotInArgv" "${config_file}"
}

@test "dybatpho::notify_gotify adds an escaped title and a priority" {
  local args_file="${BATS_TEST_TMPDIR}/gotify-full-args"
  export DYBATPHO_GOTIFY_URL="http://gotify.local"
  export DYBATPHO_GOTIFY_TOKEN="tok"
  stub_curl_recording "${args_file}"
  run_traced dybatpho::notify_gotify $'line1\nline2' 'Disk "full"' 10
  unstub curl
  assert_success
  grep -- '{"message":"line1\\nline2","title":"Disk \\"full\\"","priority":10}' "${args_file}"
}

@test "dybatpho::notify_gotify rejects a priority outside 0-10" {
  export DYBATPHO_GOTIFY_URL="https://gotify.example.test"
  export DYBATPHO_GOTIFY_TOKEN="tok"
  run -1 dybatpho::notify_gotify "hello" "" 11
  assert_output --partial "priority must be a number from 0 to 10"
}

@test "dybatpho::notify_gotify rejects a server URL without a scheme" {
  export DYBATPHO_GOTIFY_URL="gotify.example.test"
  export DYBATPHO_GOTIFY_TOKEN="tok"
  run -1 dybatpho::notify_gotify "hello"
  assert_output --partial "server URL must start with http:// or https://"
}

@test "dybatpho::notify_gotify returns the HTTP client status" {
  export DYBATPHO_GOTIFY_URL="https://gotify.example.test"
  export DYBATPHO_GOTIFY_TOKEN="wrong"
  export DYBATPHO_CURL_MAX_RETRIES=0
  stub curl ": printf '401'"
  run_traced -4 dybatpho::notify_gotify "refused"
  unstub curl
}

# ---------------------------------------------------------------------------
# dybatpho::notify_email
# ---------------------------------------------------------------------------

# A sendmail that records its arguments one per line and the message it reads.
# Every test that can reach the send step points DYBATPHO_SENDMAIL here, so the
# host's own MTA is never run.
fake_sendmail() {
  local fake="${BATS_TEST_TMPDIR}/sendmail"
  printf '#!/bin/sh\nfor arg in "$@"; do printf "%%s\\n" "$arg"; done > %q\ncat > %q\nexit %s\n' \
    "${BATS_TEST_TMPDIR}/sendmail.args" "${BATS_TEST_TMPDIR}/sendmail.message" "${1:-0}" > "${fake}"
  chmod +x "${fake}"
  export DYBATPHO_SENDMAIL="${fake}"
}

@test "dybatpho::notify_email no arg" {
  run dybatpho::notify_email
  assert_failure
}

@test "dybatpho::notify_email hands recipients to sendmail after --" {
  fake_sendmail
  unset DYBATPHO_EMAIL_FROM
  run_traced -0 dybatpho::notify_email " ops@example.com, ,lead@example.com " "Backup failed" "see log"
  run_traced cat "${BATS_TEST_TMPDIR}/sendmail.args"
  assert_equal "${lines[0]}" "-i"
  assert_equal "${lines[1]}" "--"
  assert_line --index 2 "ops@example.com"
  assert_line --index 3 "lead@example.com"
  assert_equal "${#lines[@]}" 4
}

@test "dybatpho::notify_email writes the headers and the body" {
  fake_sendmail
  run_traced -0 dybatpho::notify_email "ops@example.com,lead@example.com" "Backup failed" \
    $'line one\n.\nline three' bot@example.com
  run_traced cat "${BATS_TEST_TMPDIR}/sendmail.message"
  assert_line --index 0 "From: bot@example.com"
  assert_line --index 1 "To: ops@example.com, lead@example.com"
  assert_line --index 2 "Subject: Backup failed"
  assert_line --index 3 "MIME-Version: 1.0"
  assert_line --index 4 "Content-Type: text/plain; charset=UTF-8"
  assert_line --index 5 "Content-Transfer-Encoding: 8bit"
  assert_equal "${lines[6]}" ""
  assert_line --index 7 "line one"
  assert_line --index 8 "."
  assert_line --index 9 "line three"
}

@test "dybatpho::notify_email takes the sender from DYBATPHO_EMAIL_FROM" {
  fake_sendmail
  export DYBATPHO_EMAIL_FROM="cron@example.com"
  run_traced -0 dybatpho::notify_email ops@example.com "Hi" "Body"
  run_traced cat "${BATS_TEST_TMPDIR}/sendmail.message"
  assert_line --index 0 "From: cron@example.com"
}

@test "dybatpho::notify_email leaves the sender to the MTA when none is set" {
  fake_sendmail
  unset DYBATPHO_EMAIL_FROM
  run_traced -0 dybatpho::notify_email ops@example.com "Hi" "Body"
  run_traced cat "${BATS_TEST_TMPDIR}/sendmail.message"
  assert_line --index 0 "To: ops@example.com"
  refute_output --partial "From:"
}

@test "dybatpho::notify_email encodes a subject that is not ASCII" {
  fake_sendmail
  run_traced -0 dybatpho::notify_email ops@example.com "Sao lưu xong" "Body"
  run_traced cat "${BATS_TEST_TMPDIR}/sendmail.message"
  assert_line --index 1 "Subject: =?UTF-8?Q?Sao_l=C6=B0u_xong?="
}

@test "dybatpho::notify_email splits a long subject without breaking a character" {
  local subject="" encoded word
  local i
  for ((i = 0; i < 30; i++)); do subject+="ư"; done
  __dybatpho_notification_mime_header encoded "${subject}"
  # Each character is two bytes, `=C6=B0`, six columns; a word takes nine of
  # them, so thirty need four words, and no word ends inside a character.
  assert_equal "$(grep -c '=?UTF-8?Q?' <<< "${encoded}")" 4
  while read -r word; do
    (("${#word}" <= 75))
    [[ "${word}" =~ ^=\?UTF-8\?Q\?(=C6=B0)+\?=$ ]]
  done <<< "${encoded}"
}

@test "__dybatpho_notification_mime_header leaves printable ASCII alone" {
  local encoded
  __dybatpho_notification_mime_header encoded 'Deploy "v2" = done?'
  assert_equal "${encoded}" 'Deploy "v2" = done?'
}

@test "dybatpho::notify_email rejects a line break in the subject" {
  fake_sendmail
  run -1 dybatpho::notify_email ops@example.com $'Hi\nBcc: victim@example.com' "Body"
  assert_output --partial "subject must not contain a line break"
  [ ! -e "${BATS_TEST_TMPDIR}/sendmail.args" ]
}

@test "dybatpho::notify_email rejects a recipient carrying a header" {
  fake_sendmail
  run -1 dybatpho::notify_email $'ops@example.com\nBcc: victim@example.com' "Hi" "Body"
  assert_output --partial "recipients must not contain a line break"
  [ ! -e "${BATS_TEST_TMPDIR}/sendmail.args" ]
}

@test "dybatpho::notify_email rejects a recipient that looks like an option" {
  fake_sendmail
  run -1 dybatpho::notify_email "-oi@example.com" "Hi" "Body"
  assert_output --partial "is not an email address"
}

@test "dybatpho::notify_email rejects an invalid sender" {
  fake_sendmail
  run -1 dybatpho::notify_email ops@example.com "Hi" "Body" $'bot@example.com\r\nX: y'
  assert_output --partial "sender"
}

@test "dybatpho::notify_email needs at least one recipient" {
  fake_sendmail
  run -1 dybatpho::notify_email " , " "Hi" "Body"
  assert_output --partial "no recipient given"
}

@test "dybatpho::notify_email returns the sendmail exit code" {
  fake_sendmail 75
  run_traced -75 dybatpho::notify_email ops@example.com "Hi" "Body"
}

@test "dybatpho::notify_email finds sendmail in the traditional locations" {
  local bin="${BATS_TEST_TMPDIR}/sbin"
  mkdir -p "${bin}"
  fake_sendmail
  mv "${DYBATPHO_SENDMAIL}" "${bin}/sendmail"
  unset DYBATPHO_SENDMAIL
  __DYBATPHO_NOTIFICATION_SENDMAILS=(no-such-sendmail "${bin}/sendmail")
  run_traced -0 dybatpho::notify_email ops@example.com "Hi" "Body"
  [ -s "${BATS_TEST_TMPDIR}/sendmail.message" ]
}

@test "dybatpho::notify_email fails with 127 when no sendmail is found" {
  unset DYBATPHO_SENDMAIL
  __DYBATPHO_NOTIFICATION_SENDMAILS=(no-such-sendmail "${BATS_TEST_TMPDIR}/none/sendmail")
  run -127 dybatpho::notify_email ops@example.com "Hi" "Body"
  assert_output --partial "No sendmail command found"
}

@test "dybatpho::notify_email fails with 127 when DYBATPHO_SENDMAIL is missing" {
  export DYBATPHO_SENDMAIL="${BATS_TEST_TMPDIR}/none/sendmail"
  run -127 dybatpho::notify_email ops@example.com "Hi" "Body"
  assert_output --partial "isn't installed"
}

@test "dybatpho::notify_email prints the command under DRY_RUN and sends nothing" {
  fake_sendmail
  DRY_RUN=true run_traced -0 dybatpho::notify_email ops@example.com "Hi" "Body"
  assert_output --partial "DRY RUN: ${DYBATPHO_SENDMAIL} -i -- ops@example.com"
  [ ! -e "${BATS_TEST_TMPDIR}/sendmail.args" ]
}

# ---------------------------------------------------------------------------
# Delivery policy: DYBATPHO_NOTIFY_MAX_RETRIES and DYBATPHO_NOTIFY_CIRCUIT
# ---------------------------------------------------------------------------

@test "DYBATPHO_NOTIFY_MAX_RETRIES replaces the retry budget for notifications" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  export DYBATPHO_CURL_MAX_RETRIES=5 DYBATPHO_CURL_RETRY_BASE_DELAY=0
  export DYBATPHO_NOTIFY_MAX_RETRIES=0
  # One answer only: a second attempt would find no plan and fail the stub.
  stub curl ": printf '503'"
  run_traced -5 dybatpho::notify_slack "down"
  unstub curl
  assert_equal "${DYBATPHO_CURL_MAX_RETRIES}" 5
}

@test "DYBATPHO_NOTIFY_MAX_RETRIES still lets a retry succeed" {
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  export DYBATPHO_CURL_MAX_RETRIES=0 DYBATPHO_CURL_RETRY_BASE_DELAY=0
  export DYBATPHO_NOTIFY_MAX_RETRIES=1
  stub curl ": printf '503'" ": printf '200'"
  run_traced -0 dybatpho::notify_discord "flaky"
  unstub curl
}

@test "DYBATPHO_NOTIFY_MAX_RETRIES must be a non-negative integer" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  export DYBATPHO_NOTIFY_MAX_RETRIES=many
  run -1 dybatpho::notify_slack "hello"
  assert_output --partial "DYBATPHO_NOTIFY_MAX_RETRIES must be a non-negative integer"
}

@test "DYBATPHO_NOTIFY_CIRCUIT fails fast once a provider keeps failing" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  export DYBATPHO_NOTIFY_CIRCUIT=true DYBATPHO_NOTIFY_MAX_RETRIES=0
  export DYBATPHO_CIRCUIT_THRESHOLD=2 DYBATPHO_CIRCUIT_COOLDOWN=300
  # Two failures open the circuit; the third call never reaches curl.
  stub curl ": printf '503'" ": printf '503'"
  run_traced -5 dybatpho::notify_slack "one"
  run_traced -5 dybatpho::notify_slack "two"
  run_traced --separate-stderr -9 dybatpho::notify_slack "three"
  unstub curl
  assert_stderr --partial "Circuit 'notify:slack' is open"
  assert_equal "$(dybatpho::circuit_state notify:slack)" open
}

@test "DYBATPHO_NOTIFY_CIRCUIT keeps one circuit per provider" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/TEST"
  export DYBATPHO_NOTIFY_CIRCUIT=true DYBATPHO_NOTIFY_MAX_RETRIES=0
  export DYBATPHO_CIRCUIT_THRESHOLD=1 DYBATPHO_CIRCUIT_COOLDOWN=300
  stub curl ": printf '503'" ": printf '200'"
  run_traced -5 dybatpho::notify_slack "slack is down"
  run_traced -0 dybatpho::notify_discord "discord is fine"
  unstub curl
  assert_equal "$(dybatpho::circuit_state notify:discord)" closed
}

@test "DYBATPHO_NOTIFY_CIRCUIT names a webhook circuit by host, without credentials" {
  export DYBATPHO_NOTIFY_CIRCUIT=true DYBATPHO_NOTIFY_MAX_RETRIES=0
  export DYBATPHO_CIRCUIT_THRESHOLD=1 DYBATPHO_CIRCUIT_COOLDOWN=300
  stub curl ": printf '500'"
  run_traced -5 dybatpho::notify_webhook "https://bot:hunter2@hooks.example.test/x?token=abc" '{}'
  run_traced --separate-stderr -9 dybatpho::notify_webhook "https://bot:hunter2@hooks.example.test/y" '{}'
  unstub curl
  assert_stderr --partial "Circuit 'notify:webhook:hooks.example.test' is open"
  refute_output --partial "hunter2"
  [[ "${stderr}" != *hunter2* && "${stderr}" != *token=abc* ]]
}

@test "the circuit keeps sending the token out of band" {
  local args_file="${BATS_TEST_TMPDIR}/circuit-gotify-args"
  local config_file="${BATS_TEST_TMPDIR}/circuit-gotify-config"
  export DYBATPHO_GOTIFY_URL="https://gotify.example.test"
  export DYBATPHO_GOTIFY_TOKEN="CircuitToken"
  export DYBATPHO_NOTIFY_CIRCUIT=true
  stub_curl_with_config "${args_file}" "${config_file}"
  run_traced -0 dybatpho::notify_gotify "through the breaker"
  unstub curl
  run_traced grep -- "CircuitToken" "${args_file}"
  assert_failure
  grep -- "X-Gotify-Key: CircuitToken" "${config_file}"
}

@test "without DYBATPHO_NOTIFY_CIRCUIT every call reaches the provider" {
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/TEST"
  unset DYBATPHO_NOTIFY_CIRCUIT
  export DYBATPHO_NOTIFY_MAX_RETRIES=0 DYBATPHO_CIRCUIT_THRESHOLD=1
  stub curl ": printf '503'" ": printf '503'"
  run_traced -5 dybatpho::notify_slack "one"
  run_traced -5 dybatpho::notify_slack "two"
  unstub curl
}

@test "dybatpho::notify_email asks for the validate module when it is not loaded" {
  # `notification` does not load `validate`, so a script that only posts to
  # webhooks does not pay for it. A child shell started from a file, without
  # the functions this process exports, shows what such a script sees.
  local script="${BATS_TEST_TMPDIR}/narrow.sh"
  {
    printf '%s\n' 'while read -r __fn; do unset -f "${__fn}"; done < <(compgen -A function "dybatpho::" || true)'
    printf '. %q --modules notification\n' "${DYBATPHO_DIR}/init.sh"
    printf '%s\n' 'export DRY_RUN=true DYBATPHO_SENDMAIL=sendmail'
    printf '%s\n' 'dybatpho::notify_email ops@example.com "Subject" "Body"'
  } > "${script}"

  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_failure
  assert_output --partial "dybatpho::notify_email needs the validate module, load it with: dybatpho::load validate"
  refute_output --partial "sendmail -i"

  # Once the script loads it, the same call goes as far as the dry run.
  sed_in_place 's/--modules notification$/--modules notification validate/' "${script}"
  run env -u DYBATPHO_MODULES -u DYBATPHO_LOADED_MODULES bash "${script}"
  assert_success
  assert_output --partial "sendmail -i -- ops@example.com"
}
