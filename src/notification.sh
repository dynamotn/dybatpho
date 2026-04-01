#!/usr/bin/env bash
# @file notification.sh
# @brief Utilities for sending messages to chat and notification providers
# @description
#   This module contains functions to send messages to popular messaging and
#   notification platforms through their webhook or bot APIs:
#
#   - **Slack** – Incoming Webhooks
#   - **Telegram** – Bot API `sendMessage`
#   - **Microsoft Teams** – Incoming Webhook (Adaptive Card)
#   - **Google Chat** – Incoming Webhook
#   - **Discord** – Incoming Webhook
#   - **Generic** – Any webhook that accepts a raw JSON POST body
#
# @usage
#   ### When to use this module
#
#   Use `notification.sh` when you want to:
#
#   - notify a team channel about CI/CD events
#   - alert on-call engineers from a cron job or monitoring script
#   - post deployment summaries from a release pipeline
#   - broadcast build results to a shared chat room
#
#   ### Common patterns
#
#   #### Send a Slack message
#
#   ```bash
#   export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
#   dybatpho::notify_slack "Deployment *v1.2.3* succeeded :rocket:"
#   ```
#
#   #### Send a Telegram message
#
#   ```bash
#   export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
#   export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
#   dybatpho::notify_telegram "Build #42 passed"
#   # With Markdown formatting:
#   dybatpho::notify_telegram "Build #42 passed" "Markdown"
#   ```
#
#   #### Send a Teams message with a title
#
#   ```bash
#   export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/..."
#   dybatpho::notify_teams "All checks passed" "Deploy complete"
#   ```
#
#   #### Send to any webhook
#
#   ```bash
#   dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
#   ```
#
# @see
#   - `example/notification_ops.sh`
# @tip Most providers require a webhook URL or API token set via environment variables. The functions validate these before making requests.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Escape a string for safe embedding inside a JSON string value.
# Escapes: backslash, double-quote, newline, carriage-return, and tab.
# @arg $1 string Input string
# @stdout JSON-safe escaped string (without surrounding quotes)
#######################################
function __notification_json_escape {
  local input
  dybatpho::expect_args input -- "$@"
  local output="${input}"
  output="${output//\\/\\\\}"
  output="${output//\"/\\\"}"
  output="${output//$'\n'/\\n}"
  output="${output//$'\r'/\\r}"
  output="${output//$'\t'/\\t}"
  printf '%s' "${output}"
}

#######################################
# @description Send a message to a Slack channel via Incoming Webhook.
# @example
#   export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
#   dybatpho::notify_slack "Hello from dybatpho"
#
# @arg $1 string Message text (supports Slack mrkdwn formatting)
# @env DYBATPHO_SLACK_WEBHOOK_URL string Slack Incoming Webhook URL
# @exitcode 0 Message sent successfully
# @exitcode 1 Missing arguments or environment variables
# @exitcode 4 HTTP 4xx from Slack
# @exitcode 5 HTTP 5xx from Slack
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_slack {
  local message
  dybatpho::expect_args message -- "$@"
  dybatpho::expect_envs DYBATPHO_SLACK_WEBHOOK_URL

  local payload
  payload=$(printf '{"text":"%s"}' "$(__notification_json_escape "${message}")")

  dybatpho::debug "Sending Slack notification"
  dybatpho::curl_json "${DYBATPHO_SLACK_WEBHOOK_URL}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Send a message to a Telegram chat via Bot API.
# @example
#   export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
#   export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
#   dybatpho::notify_telegram "Build passed"
#   dybatpho::notify_telegram "*Build* passed" "Markdown"
#
# @arg $1 string Message text (supports HTML or Markdown when parse mode is set)
# @arg $2 string Parse mode: `HTML`, `Markdown`, or `MarkdownV2`. Default is empty (plain text)
# @env DYBATPHO_TELEGRAM_BOT_TOKEN string Telegram Bot API token
# @env DYBATPHO_TELEGRAM_CHAT_ID string Target chat, group, or channel ID
# @exitcode 0 Message sent successfully
# @exitcode 1 Missing arguments or environment variables
# @exitcode 4 HTTP 4xx from Telegram
# @exitcode 5 HTTP 5xx from Telegram
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_telegram {
  local message
  dybatpho::expect_args message -- "$@"
  local parse_mode="${2:-}"
  dybatpho::expect_envs DYBATPHO_TELEGRAM_BOT_TOKEN DYBATPHO_TELEGRAM_CHAT_ID

  local url="https://api.telegram.org/bot${DYBATPHO_TELEGRAM_BOT_TOKEN}/sendMessage"
  local escaped_message escaped_chat_id
  escaped_message=$(__notification_json_escape "${message}")
  escaped_chat_id=$(__notification_json_escape "${DYBATPHO_TELEGRAM_CHAT_ID}")

  local payload
  if [[ -n "${parse_mode}" ]]; then
    local escaped_parse_mode
    escaped_parse_mode=$(__notification_json_escape "${parse_mode}")
    payload=$(printf '{"chat_id":"%s","text":"%s","parse_mode":"%s"}' \
      "${escaped_chat_id}" \
      "${escaped_message}" \
      "${escaped_parse_mode}")
  else
    payload=$(printf '{"chat_id":"%s","text":"%s"}' \
      "${escaped_chat_id}" \
      "${escaped_message}")
  fi

  dybatpho::debug "Sending Telegram notification"
  dybatpho::curl_json "${url}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Send a message to a Microsoft Teams channel via Incoming Webhook.
# Uses the Adaptive Card format required by the current Teams webhook API.
# @example
#   export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/..."
#   dybatpho::notify_teams "Deployment complete"
#   dybatpho::notify_teams "All checks passed" "Deploy v2.0"
#
# @arg $1 string Message body text
# @arg $2 string Optional card title shown above the message body
# @env DYBATPHO_TEAMS_WEBHOOK_URL string Microsoft Teams Incoming Webhook URL
# @exitcode 0 Message sent successfully
# @exitcode 1 Missing arguments or environment variables
# @exitcode 4 HTTP 4xx from Teams
# @exitcode 5 HTTP 5xx from Teams
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_teams {
  local message
  dybatpho::expect_args message -- "$@"
  local title="${2:-}"
  dybatpho::expect_envs DYBATPHO_TEAMS_WEBHOOK_URL

  local escaped_message
  escaped_message=$(__notification_json_escape "${message}")

  local body_blocks
  if [[ -n "${title}" ]]; then
    local escaped_title
    escaped_title=$(__notification_json_escape "${title}")
    body_blocks=$(printf '[{"type":"TextBlock","text":"%s","weight":"bolder","size":"medium"},{"type":"TextBlock","text":"%s","wrap":true}]' \
      "${escaped_title}" \
      "${escaped_message}")
  else
    body_blocks=$(printf '[{"type":"TextBlock","text":"%s","wrap":true}]' \
      "${escaped_message}")
  fi

  local payload
  # shellcheck disable=SC2016
  payload=$(printf '{"type":"message","attachments":[{"contentType":"application/vnd.microsoft.card.adaptive","content":{"$schema":"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard","version":"1.2","body":%s}}]}' \
    "${body_blocks}")

  dybatpho::debug "Sending Teams notification"
  dybatpho::curl_json "${DYBATPHO_TEAMS_WEBHOOK_URL}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Send a message to a Google Chat space via Incoming Webhook.
# @example
#   export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/.../messages?key=...&token=..."
#   dybatpho::notify_google_chat "Release v2.0 is live"
#
# @arg $1 string Message text (supports Google Chat formatting with asterisks and underscores)
# @env DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL string Google Chat Incoming Webhook URL
# @exitcode 0 Message sent successfully
# @exitcode 1 Missing arguments or environment variables
# @exitcode 4 HTTP 4xx from Google Chat
# @exitcode 5 HTTP 5xx from Google Chat
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_google_chat {
  local message
  dybatpho::expect_args message -- "$@"
  dybatpho::expect_envs DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL

  local payload
  payload=$(printf '{"text":"%s"}' "$(__notification_json_escape "${message}")")

  dybatpho::debug "Sending Google Chat notification"
  dybatpho::curl_json "${DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Send a message to a Discord channel via Incoming Webhook.
# @example
#   export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
#   dybatpho::notify_discord "Build #99 succeeded"
#   dybatpho::notify_discord "Deploy done" "CI Bot"
#
# @arg $1 string Message content (supports Discord Markdown)
# @arg $2 string Optional display name override for the webhook bot
# @env DYBATPHO_DISCORD_WEBHOOK_URL string Discord Incoming Webhook URL
# @exitcode 0 Message sent successfully
# @exitcode 1 Missing arguments or environment variables
# @exitcode 4 HTTP 4xx from Discord
# @exitcode 5 HTTP 5xx from Discord
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_discord {
  local message
  dybatpho::expect_args message -- "$@"
  local username="${2:-}"
  dybatpho::expect_envs DYBATPHO_DISCORD_WEBHOOK_URL

  local escaped_message
  escaped_message=$(__notification_json_escape "${message}")

  local payload
  if [[ -n "${username}" ]]; then
    local escaped_username
    escaped_username=$(__notification_json_escape "${username}")
    payload=$(printf '{"content":"%s","username":"%s"}' \
      "${escaped_message}" \
      "${escaped_username}")
  else
    payload=$(printf '{"content":"%s"}' "${escaped_message}")
  fi

  dybatpho::debug "Sending Discord notification"
  dybatpho::curl_json "${DYBATPHO_DISCORD_WEBHOOK_URL}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Send a raw JSON payload to an arbitrary webhook URL via HTTP POST.
# @example
#   dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
#   # With extra curl flags:
#   dybatpho::notify_webhook "https://my.service/hook" '{"text":"hi"}' \
#     --header "Authorization: Bearer ${TOKEN}"
#
# @arg $1 string Webhook URL
# @arg $2 string JSON payload body
# @arg $@ string Extra arguments forwarded to curl
# @exitcode 0 Webhook accepted the payload
# @exitcode 1 Missing arguments
# @exitcode 4 HTTP 4xx from webhook
# @exitcode 5 HTTP 5xx from webhook
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_webhook {
  local url payload
  dybatpho::expect_args url payload -- "$@"
  shift 2

  dybatpho::debug "Sending webhook notification to ${url}"
  dybatpho::curl_json "${url}" /dev/null \
    --request POST \
    --data "${payload}" \
    "$@"
}
