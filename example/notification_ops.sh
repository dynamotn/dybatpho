#!/usr/bin/env bash
# @file notification_ops.sh
# @brief Example showing notification utilities
# @description Demonstrates dybatpho::notify_slack, notify_telegram, notify_teams,
#   notify_google_chat, notify_discord, notify_webhook, notify_ntfy,
#   notify_gotify, notify_desktop, and notify_email using DRY_RUN mode so no real
#   HTTP request is made, no notification is shown, and no email is sent when
#   running this example.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules notification validate

dybatpho::register_common_handlers

# Run in dry-run mode so no actual requests are sent
export DRY_RUN=true

# @description Run the `SLACK` section of this example.
# @noargs
function _demo_slack {
  dybatpho::header "SLACK"
  export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T000/B000/xxxx"
  dybatpho::notify_slack "Deployment *v1.2.3* succeeded :rocket:"
  dybatpho::info "Slack notification dispatched"
}

# @description Run the `TELEGRAM` section of this example.
# @noargs
function _demo_telegram {
  dybatpho::header "TELEGRAM"
  export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234"
  export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
  dybatpho::notify_telegram "Build #42 passed"
  dybatpho::notify_telegram "*Build #43* passed" "Markdown"
  dybatpho::info "Telegram notifications dispatched"
}

# @description Run the `MICROSOFT TEAMS` section of this example.
# @noargs
function _demo_teams {
  dybatpho::header "MICROSOFT TEAMS"
  export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/xxx"
  dybatpho::notify_teams "All checks passed"
  dybatpho::notify_teams "All checks passed" "Deploy v2.0"
  dybatpho::info "Teams notifications dispatched"
}

# @description Run the `GOOGLE CHAT` section of this example.
# @noargs
function _demo_google_chat {
  dybatpho::header "GOOGLE CHAT"
  export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/xxx/messages?key=yyy&token=zzz"
  dybatpho::notify_google_chat "Release v2.0 is live"
  dybatpho::info "Google Chat notification dispatched"
}

# @description Run the `DISCORD` section of this example.
# @noargs
function _demo_discord {
  dybatpho::header "DISCORD"
  export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/000/xxx"
  dybatpho::notify_discord "Build #99 succeeded"
  dybatpho::notify_discord "Deploy done" "CI Bot"
  dybatpho::info "Discord notifications dispatched"
}

# @description Run the `GENERIC WEBHOOK` section of this example.
# @noargs
function _demo_webhook {
  dybatpho::header "GENERIC WEBHOOK"
  dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
  dybatpho::info "Generic webhook notification dispatched"
}

# @description Run the `NTFY` section of this example.
# @noargs
function _demo_ntfy {
  dybatpho::header "NTFY"
  export DYBATPHO_NTFY_TOPIC="backups-7f3a"
  dybatpho::notify_ntfy "Backup finished"
  # A self-hosted server, a priority name and emoji tags.
  DYBATPHO_NTFY_URL="https://ntfy.example.test" \
    dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent "warning,floppy_disk"
  dybatpho::info "ntfy notifications dispatched"
}

# @description Run the `GOTIFY` section of this example.
# @noargs
function _demo_gotify {
  dybatpho::header "GOTIFY"
  export DYBATPHO_GOTIFY_URL="https://gotify.example.test"
  export DYBATPHO_GOTIFY_TOKEN="AbCdEf123456"
  # The token goes in a header outside the command line, so DRY_RUN does not
  # print it either.
  dybatpho::notify_gotify "Disk /var at 97%" "Disk almost full" 8
  dybatpho::info "Gotify notification dispatched"
}

# @description Run the `DESKTOP` section of this example.
# @noargs
function _demo_desktop {
  dybatpho::header "DESKTOP"
  # notify-send on Linux, osascript on macOS; DRY_RUN prints the command.
  dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
  dybatpho::notify_desktop "Disk almost full" "/var is at 97%" critical
  # An unknown urgency is refused before anything runs.
  if ! (dybatpho::notify_desktop "Title" "Body" urgent 2> /dev/null); then
    dybatpho::info "Rejected an unknown urgency"
  fi
  dybatpho::info "Desktop notifications dispatched"
}

# @description Run the `EMAIL` section of this example.
# @noargs
function _demo_email {
  dybatpho::header "EMAIL"
  export DYBATPHO_EMAIL_FROM="cron@example.com"
  dybatpho::notify_email "ops@example.com, lead@example.com" "Backup failed" \
    $'The nightly backup stopped at 02:14.\nSee backup.log for details.'
  # A line break in the subject could add a header, so it is refused.
  if ! (dybatpho::notify_email ops@example.com $'Hi\nBcc: x@example.com' "Body" 2> /dev/null); then
    dybatpho::info "Rejected a subject carrying a header"
  fi
  dybatpho::info "Email dispatched"
}

# @description Run the `DELIVERY POLICY` section of this example.
#   DRY_RUN is turned off here, and `curl` is replaced by a stub on PATH that
#   answers 503, so the circuit breaker can be seen opening without any request
#   leaving the machine.
# @noargs
function _demo_delivery_policy {
  dybatpho::header "DELIVERY POLICY"
  local bin
  dybatpho::create_temp_dir bin
  printf '#!/bin/sh\nprintf 503\n' > "${bin}/curl"
  chmod +x "${bin}/curl"

  local status
  (
    export PATH="${bin}:${PATH}" DRY_RUN=false
    export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T000/B000/xxxx"
    export DYBATPHO_NOTIFY_MAX_RETRIES=0 DYBATPHO_NOTIFY_CIRCUIT=true
    export DYBATPHO_CIRCUIT_THRESHOLD=2
    for attempt in 1 2 3; do
      status=0
      dybatpho::notify_slack "Attempt ${attempt}" 2> /dev/null || status=$?
      dybatpho::info "Attempt ${attempt} returned ${status}"
    done
  )
  dybatpho::info "The third attempt was skipped: 9 means the circuit is open"
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_slack
  _demo_telegram
  _demo_teams
  _demo_google_chat
  _demo_discord
  _demo_webhook
  _demo_ntfy
  _demo_gotify
  _demo_desktop
  _demo_email
  _demo_delivery_policy
  dybatpho::success "Notification demo complete"
}

_main "$@"
