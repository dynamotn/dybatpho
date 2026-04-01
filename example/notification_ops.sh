#!/usr/bin/env bash
# @file notification_ops.sh
# @brief Example showing notification utilities
# @description Demonstrates dybatpho::notify_slack, notify_telegram, notify_teams,
#   notify_google_chat, notify_discord, and notify_webhook using DRY_RUN mode so
#   no real HTTP requests are made when running this example.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

# Run in dry-run mode so no actual requests are sent
export DRY_RUN=true

function _demo_slack {
  dybatpho::header "SLACK"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T000/B000/xxxx"
  dybatpho::notify_slack "Deployment *v1.2.3* succeeded :rocket:"
  dybatpho::info "Slack notification dispatched"
}

function _demo_telegram {
  dybatpho::header "TELEGRAM"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
  dybatpho::notify_telegram "Build #42 passed"
  dybatpho::notify_telegram "*Build #43* passed" "Markdown"
  dybatpho::info "Telegram notifications dispatched"
}

function _demo_teams {
  dybatpho::header "MICROSOFT TEAMS"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/xxx"
  dybatpho::notify_teams "All checks passed"
  dybatpho::notify_teams "All checks passed" "Deploy v2.0"
  dybatpho::info "Teams notifications dispatched"
}

function _demo_google_chat {
  dybatpho::header "GOOGLE CHAT"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/xxx/messages?key=yyy&token=zzz"
  dybatpho::notify_google_chat "Release v2.0 is live"
  dybatpho::info "Google Chat notification dispatched"
}

function _demo_discord {
  dybatpho::header "DISCORD"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/000/xxx"
  dybatpho::notify_discord "Build #99 succeeded"
  dybatpho::notify_discord "Deploy done" "CI Bot"
  dybatpho::info "Discord notifications dispatched"
}

function _demo_webhook {
  dybatpho::header "GENERIC WEBHOOK"
  dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
  dybatpho::info "Generic webhook notification dispatched"
}

function _main {
  _demo_slack
  _demo_telegram
  _demo_teams
  _demo_google_chat
  _demo_discord
  _demo_webhook
  dybatpho::success "Notification demo complete"
}

_main "$@"
