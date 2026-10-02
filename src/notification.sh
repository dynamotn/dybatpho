# shellcheck shell=bash
# @file notification.sh
# @brief Utilities for sending messages to chat and notification providers
# @namespace dybatpho
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
#   - **ntfy** – Publish to a topic on ntfy.sh or a self-hosted server
#   - **Gotify** – Push a message to a self-hosted Gotify server
#   - **Desktop** – `notify-send` on Linux and the BSDs, `osascript` on macOS
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
#   #### Publish to an ntfy topic
#
#   ```bash
#   export DYBATPHO_NTFY_TOPIC="backups-7f3a"
#   dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent "warning"
#   ```
#
#   #### Push to a Gotify server
#
#   ```bash
#   export DYBATPHO_GOTIFY_URL="https://gotify.example.com"
#   export DYBATPHO_GOTIFY_TOKEN="AbCdEf123456"
#   dybatpho::notify_gotify "Disk /var at 97%" "Disk almost full" 8
#   ```
#
#   #### Show a desktop notification
#
#   ```bash
#   dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
#   dybatpho::notify_desktop "Disk almost full" "/var is at 97%" critical
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
# @tip Most providers require a webhook URL or API token set via environment variables. The functions validate these
#   before
#   making requests.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

#######################################
# @description Escape a string for safe embedding inside a JSON string value.
#   The rule is the same one the log events follow, and `logging` is a core
#   module, so the escaping lives there rather than in a second copy that can
#   drift. That matters here: a notification often carries the output of a
#   command that failed, ANSI colour sequences and all, and a control character
#   left raw makes the payload something the webhook refuses.
# @arg $1 string Input string
# @stdout JSON-safe escaped string (without surrounding quotes)
# @internal
#######################################
function __dybatpho_notification_json_escape {
  local input
  dybatpho::expect_args input -- "$@"
  __dybatpho_log_json_escape "${input}"
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
  local notification_json_escape
  notification_json_escape=$(__dybatpho_notification_json_escape "${message}")
  payload=$(printf '{"text":"%s"}' "${notification_json_escape}")

  dybatpho::debug "Sending Slack notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
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

  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  local url="https://api.telegram.org/bot${DYBATPHO_TELEGRAM_BOT_TOKEN}/sendMessage"
  local escaped_message escaped_chat_id
  escaped_message=$(__dybatpho_notification_json_escape "${message}")
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  escaped_chat_id=$(__dybatpho_notification_json_escape "${DYBATPHO_TELEGRAM_CHAT_ID}")

  local payload
  if [[ -n "${parse_mode}" ]]; then
    local escaped_parse_mode
    escaped_parse_mode=$(__dybatpho_notification_json_escape "${parse_mode}")
    printf -v payload '{"chat_id":"%s","text":"%s","parse_mode":"%s"}' "${escaped_chat_id}" "${escaped_message}" \
      "${escaped_parse_mode}"
  else
    printf -v payload '{"chat_id":"%s","text":"%s"}' "${escaped_chat_id}" "${escaped_message}"
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
  escaped_message=$(__dybatpho_notification_json_escape "${message}")

  local body_blocks
  if [[ -n "${title}" ]]; then
    local escaped_title
    escaped_title=$(__dybatpho_notification_json_escape "${title}")
    local blocks_format='[{"type":"TextBlock","text":"%s","weight":"bolder","size":"medium"},'
    blocks_format+='{"type":"TextBlock","text":"%s","wrap":true}]'
    # shellcheck disable=SC2059 # the format is built above, not taken from input
    printf -v body_blocks "${blocks_format}" "${escaped_title}" "${escaped_message}"
  else
    printf -v body_blocks '[{"type":"TextBlock","text":"%s","wrap":true}]' "${escaped_message}"
  fi

  local payload
  # shellcheck disable=SC2016
  local payload_format='{"type":"message","attachments":[{"contentType":'
  # shellcheck disable=SC2016 # `$schema` is a key of the card, not an expansion
  payload_format+='"application/vnd.microsoft.card.adaptive","content":{"$schema":'
  payload_format+='"http://adaptivecards.io/schemas/adaptive-card.json","type":"AdaptiveCard",'
  payload_format+='"version":"1.2","body":%s}}]}'
  # shellcheck disable=SC2059 # the format is built above, not taken from input
  printf -v payload "${payload_format}" "${body_blocks}"

  dybatpho::debug "Sending Teams notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
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
  local notification_json_escape
  notification_json_escape=$(__dybatpho_notification_json_escape "${message}")
  payload=$(printf '{"text":"%s"}' "${notification_json_escape}")

  dybatpho::debug "Sending Google Chat notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
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
  escaped_message=$(__dybatpho_notification_json_escape "${message}")

  local payload
  if [[ -n "${username}" ]]; then
    local escaped_username
    escaped_username=$(__dybatpho_notification_json_escape "${username}")
    printf -v payload '{"content":"%s","username":"%s"}' "${escaped_message}" "${escaped_username}"
  else
    printf -v payload '{"content":"%s"}' "${escaped_message}"
  fi

  dybatpho::debug "Sending Discord notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
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

#######################################
# @description Show a notification on the local desktop.
#   `notify-send` (libnotify, on Linux and the BSDs) is used when it is
#   installed, and `osascript` (macOS) otherwise. The title and the body reach
#   either one as separate arguments, never spliced into a command or a script,
#   so quotes, a leading `-` or AppleScript syntax in them are shown as written.
#   macOS has no urgency for a notification, so it is accepted there and has no
#   effect.
# @example
#   dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
#   dybatpho::notify_desktop "Disk almost full" "/var is at 97%" critical
#
# @arg $1 string Title
# @arg $2 string Body, default is empty
# @arg $3 string Urgency: `low`, `normal` or `critical`, default is `normal`
# @env DRY_RUN string Print the command instead of showing the notification; with no backend installed, the
#   `notify-send` form is printed
# @exitcode 0 The notification was handed to the desktop
# @exitcode 1 Missing or empty title, or an unknown urgency
# @exitcode 127 Neither `notify-send` nor `osascript` is installed
# @exitcode other The backend's own exit code, such as `notify-send` finding no desktop session
#######################################
function dybatpho::notify_desktop {
  local title
  dybatpho::expect_args title -- "$@"
  local body="${2-}" urgency="${3:-normal}"
  # The `die` lines below are tested under `run`, which kcov cannot observe.
  dybatpho::is empty "${title}" && dybatpho::die "${FUNCNAME[0]}: title must not be empty" # kcov(skip)
  case "${urgency}" in
    low | normal | critical) ;; # kcov(skip)
    *) dybatpho::die "${FUNCNAME[0]}: urgency must be low, normal or critical, not '${urgency}'" ;; # kcov(skip)
  esac

  local backend
  # shellcheck disable=SC2154 # `DRY_RUN` is declared by `src/process.sh`, a core module
  if dybatpho::is command notify-send; then
    backend="notify-send"
  elif dybatpho::is command osascript; then
    backend="osascript"
  elif dybatpho::is true "${DRY_RUN}"; then
    # Nothing would run anyway, so show the command most hosts would use.
    backend="notify-send"
  else
    dybatpho::die "No desktop notification backend: install notify-send (libnotify) or osascript" 127 # kcov(skip)
  fi

  local -a command=()
  if [[ "${backend}" == "notify-send" ]]; then
    # `--` ends the options, so a title such as `-u` is a title.
    command=(notify-send "--urgency=${urgency}" -- "${title}")
    [[ -n "${body}" ]] && command+=("${body}")
  else
    # The words go to the script as `argv` rather than into its text. The
    # leading `dybatpho` is the first operand, which ends osascript's option
    # parsing, so a title that starts with `-` is not read as a flag.
    command=(osascript -e 'on run argv')
    command+=(-e 'display notification (item 3 of argv) with title (item 2 of argv)')
    command+=(-e 'end run' dybatpho "${title}" "${body}")
  fi

  dybatpho::debug "Sending desktop notification through ${command[0]}"
  dybatpho::dry_run "${command[@]}"
}

#######################################
# @description Publish a message to an [ntfy](https://ntfy.sh) topic, on
#   ntfy.sh or a server of your own.
#   The message is published as JSON to the server root, so the title, the
#   priority and the tags travel in the body and keep any character they hold.
#   An access token is sent as a bearer header through the network module's
#   out-of-band channel, so it never appears on curl's command line.
# @example
#   export DYBATPHO_NTFY_TOPIC="backups-7f3a"
#   dybatpho::notify_ntfy "Backup finished"
#   dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent "warning,floppy_disk"
#
# @arg $1 string Message text
# @arg $2 string Optional title
# @arg $3 string Optional priority: `1`-`5`, or `min`, `low`, `default`, `high`, `max` or `urgent`
# @arg $4 string Optional comma-separated tags; a tag that names an emoji is shown as one
# @env DYBATPHO_NTFY_TOPIC string Topic to publish to: letters, digits, `-` and `_`, at most 64 characters
# @env DYBATPHO_NTFY_URL string Server URL, default is `https://ntfy.sh`
# @env DYBATPHO_NTFY_TOKEN string Optional access token for a protected topic
# @exitcode 0 Message published
# @exitcode 1 Missing arguments or environment variables, or an invalid topic, server URL or priority
# @exitcode 4 HTTP 4xx from the server, such as a refused token
# @exitcode 5 HTTP 5xx from the server
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_ntfy {
  local message
  dybatpho::expect_args message -- "$@"
  local title="${2-}" priority="${3-}" tags="${4-}"
  dybatpho::expect_envs DYBATPHO_NTFY_TOPIC
  local url="${DYBATPHO_NTFY_URL:-https://ntfy.sh}"
  local token="${DYBATPHO_NTFY_TOKEN-}"

  # The `die` lines below are tested under `run`, which kcov cannot observe.
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  [[ "${DYBATPHO_NTFY_TOPIC}" =~ ^[-_A-Za-z0-9]{1,64}$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: topic must be 1-64 letters, digits, '-' or '_'" # kcov(skip)
  [[ "${url}" =~ ^https?://[^[:space:]]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: server URL must start with http:// or https://" # kcov(skip)
  while [[ "${url}" == */ ]]; do url="${url%/}"; done

  case "${priority}" in
    '' | [1-5]) ;; # kcov(skip)
    min) priority=1 ;;
    low) priority=2 ;;
    default) priority=3 ;;
    high) priority=4 ;;
    max | urgent) priority=5 ;;
    *) dybatpho::die "${FUNCNAME[0]}: priority must be 1-5, min, low, default, high, max or urgent" ;; # kcov(skip)
  esac

  local payload escaped
  escaped=$(__dybatpho_notification_json_escape "${DYBATPHO_NTFY_TOPIC}")
  payload="{\"topic\":\"${escaped}\""
  escaped=$(__dybatpho_notification_json_escape "${message}")
  payload+=",\"message\":\"${escaped}\""
  if [[ -n "${title}" ]]; then
    escaped=$(__dybatpho_notification_json_escape "${title}")
    payload+=",\"title\":\"${escaped}\""
  fi
  [[ -n "${priority}" ]] && payload+=",\"priority\":${priority}"
  if [[ -n "${tags}" ]]; then
    local tag list=""
    local -a tag_list=()
    IFS=',' read -r -a tag_list <<< "${tags}"
    for tag in ${tag_list[@]+"${tag_list[@]}"}; do
      tag="$(dybatpho::trim "${tag}")"
      [[ -n "${tag}" ]] || continue
      escaped=$(__dybatpho_notification_json_escape "${tag}")
      list+="${list:+,}\"${escaped}\""
    done
    [[ -n "${list}" ]] && payload+=",\"tags\":[${list}]"
  fi
  payload+="}"

  local -a headers=(${DYBATPHO_CURL_SECRET_HEADERS[@]+"${DYBATPHO_CURL_SECRET_HEADERS[@]}"})
  [[ -n "${token}" ]] && headers+=("Authorization: Bearer ${token}")
  # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
  local -a DYBATPHO_CURL_SECRET_HEADERS=(${headers[@]+"${headers[@]}"})

  dybatpho::debug "Sending ntfy notification"
  dybatpho::curl_json "${url}" /dev/null \
    --request POST \
    --data "${payload}"
}

#######################################
# @description Push a message to a [Gotify](https://gotify.net) server.
#   The application token is sent as the `X-Gotify-Key` header through the
#   network module's out-of-band channel, so it never appears on curl's command
#   line, where every user of the host could read it from the process list.
# @example
#   export DYBATPHO_GOTIFY_URL="https://gotify.example.com"
#   export DYBATPHO_GOTIFY_TOKEN="AbCdEf123456"
#   dybatpho::notify_gotify "Backup finished"
#   dybatpho::notify_gotify "Disk /var at 97%" "Disk almost full" 8
#
# @arg $1 string Message text
# @arg $2 string Optional title; Gotify shows the application name without one
# @arg $3 string Optional priority from `0` to `10`
# @env DYBATPHO_GOTIFY_URL string Server URL, such as `https://gotify.example.com`
# @env DYBATPHO_GOTIFY_TOKEN string Application token the message is posted as
# @exitcode 0 Message pushed
# @exitcode 1 Missing arguments or environment variables, or an invalid server URL or priority
# @exitcode 4 HTTP 4xx from the server, such as an unknown token
# @exitcode 5 HTTP 5xx from the server
# @see dybatpho::curl_json
#######################################
function dybatpho::notify_gotify {
  local message
  dybatpho::expect_args message -- "$@"
  local title="${2-}" priority="${3-}"
  dybatpho::expect_envs DYBATPHO_GOTIFY_URL DYBATPHO_GOTIFY_TOKEN

  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  local url="${DYBATPHO_GOTIFY_URL}"
  # The `die` lines below are tested under `run`, which kcov cannot observe.
  [[ "${url}" =~ ^https?://[^[:space:]]+$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: server URL must start with http:// or https://" # kcov(skip)
  [[ -z "${priority}" || "${priority}" =~ ^([0-9]|10)$ ]] \
    || dybatpho::die "${FUNCNAME[0]}: priority must be a number from 0 to 10" # kcov(skip)
  while [[ "${url}" == */ ]]; do url="${url%/}"; done

  local payload escaped
  escaped=$(__dybatpho_notification_json_escape "${message}")
  payload="{\"message\":\"${escaped}\""
  if [[ -n "${title}" ]]; then
    escaped=$(__dybatpho_notification_json_escape "${title}")
    payload+=",\"title\":\"${escaped}\""
  fi
  [[ -n "${priority}" ]] && payload+=",\"priority\":${priority}"
  payload+="}"

  local -a headers=(${DYBATPHO_CURL_SECRET_HEADERS[@]+"${DYBATPHO_CURL_SECRET_HEADERS[@]}"})
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  headers+=("X-Gotify-Key: ${DYBATPHO_GOTIFY_TOKEN}")
  # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
  local -a DYBATPHO_CURL_SECRET_HEADERS=("${headers[@]}")

  dybatpho::debug "Sending Gotify notification"
  dybatpho::curl_json "${url}/message" /dev/null \
    --request POST \
    --data "${payload}"
}
