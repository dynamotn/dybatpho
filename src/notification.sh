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
#   - **Email** – A plain-text message through the local `sendmail`
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
#   #### Send an email
#
#   ```bash
#   export DYBATPHO_EMAIL_FROM="cron@example.com"
#   dybatpho::notify_email "ops@example.com" "Backup failed" "$(tail -n 20 backup.log)"
#   ```
#
#   #### Send to any webhook
#
#   ```bash
#   dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
#   ```
#
#   ### Delivery policy
#
#   Every HTTP notifier retries through `dybatpho::curl_do`. A script that
#   alerts from a cron job usually wants that shorter, and wants a provider that
#   is down to stop costing time on every call:
#
#   ```bash
#   export DYBATPHO_NOTIFY_MAX_RETRIES=1   # notifications only
#   export DYBATPHO_NOTIFY_CIRCUIT=true    # skip a failing provider for a while
#   dybatpho::notify_slack "Job finished" || [[ $? -eq 9 ]]
#   ```
#
# @see
#   - `example/notification_ops.sh`
# @tip Most providers require a webhook URL or API token set via environment variables. The functions validate these
#   before
#   making requests.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_NOTIFY_MAX_RETRIES number Retry budget for notification requests only, replacing
#   `DYBATPHO_CURL_MAX_RETRIES` for them; unset keeps the network module's budget
# @env DYBATPHO_NOTIFY_CIRCUIT bool Guard each HTTP notifier with a circuit breaker, so a provider that keeps failing
#   is skipped with exit code `9` until its cooldown passes (default `false`)

# Where `dybatpho::notify_email` looks for a sendmail command, in order. The
# command often lives outside an ordinary user's PATH, in `/usr/sbin`, which is
# why the two traditional locations follow the PATH lookup.
declare -ga __DYBATPHO_NOTIFICATION_SENDMAILS=(sendmail /usr/sbin/sendmail /usr/lib/sendmail)

#######################################
# @description Post a JSON body for one of the HTTP notifiers, with the
#   module's delivery policy applied.
#   The request goes through `dybatpho::curl_json`, which already retries a
#   transport failure, a 5xx and a 408/425/429 with backoff. Two settings
#   adjust that for notifications alone, without touching the script's other
#   requests: `DYBATPHO_NOTIFY_MAX_RETRIES` replaces the retry budget, and
#   `DYBATPHO_NOTIFY_CIRCUIT` guards each provider with a circuit breaker, so
#   once an endpoint has failed `DYBATPHO_CIRCUIT_THRESHOLD` times in a row the
#   next calls fail at once with exit code `9` instead of waiting out their
#   retries, until `DYBATPHO_CIRCUIT_COOLDOWN` has passed.
#
#   A circuit is named after the provider, never the URL: a webhook URL is
#   often the credential itself, and the name appears in the warning the
#   breaker logs. The generic webhook gets one circuit per host.
#
#   The URL and the JSON body never reach `curl`'s command line, which every
#   account on the host can read: a webhook URL is the credential, a bot token
#   sits in Telegram's path, and the body is the message. Both go through the
#   network module's private config file and standard input instead.
# @arg $1 string Provider name, which names the circuit
# @arg $2 string URL
# @arg $3 string JSON body
# @arg $@ string Other arguments for curl
# @exitcode 9 The provider's circuit is open; nothing was sent
# @exitcode other The exit code of `dybatpho::curl_json`
# @internal
#######################################
function __dybatpho_notification_post {
  local provider url payload
  dybatpho::expect_args provider url payload -- "$@"
  shift 3
  # shellcheck disable=SC2034 # read by dybatpho::curl_do through dynamic scoping
  local DYBATPHO_CURL_SECRET_DATA="${payload}" DYBATPHO_CURL_SECRET_URL=true

  if [[ -n "${DYBATPHO_NOTIFY_MAX_RETRIES-}" ]]; then
    [[ "${DYBATPHO_NOTIFY_MAX_RETRIES}" =~ ^[0-9]+$ ]] \
      || dybatpho::die "DYBATPHO_NOTIFY_MAX_RETRIES must be a non-negative integer" # kcov(skip)
    # Dynamic scoping hands the budget to `dybatpho::curl_do` for this request
    # only, and the script's own value is back once this function returns.
    # shellcheck disable=SC2034 # read by dybatpho::curl_do
    local DYBATPHO_CURL_MAX_RETRIES="${DYBATPHO_NOTIFY_MAX_RETRIES}"
  fi

  if ! dybatpho::is true "${DYBATPHO_NOTIFY_CIRCUIT:-false}"; then
    dybatpho::curl_json "${url}" /dev/null "$@"
    return
  fi

  local key="notify:${provider}"
  if [[ "${provider}" == "webhook" ]]; then
    # The host alone: no scheme, no path or query, no `user:password@`.
    local host="${url#*://}"
    host="${host%%[/?#]*}"
    key+=":${host##*@}"
  fi
  local command
  printf -v command '%q ' dybatpho::curl_json "${url}" /dev/null "$@"
  dybatpho::circuit_breaker "${key}" "${command}"
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_slack {
  local message
  dybatpho::expect_args message -- "$@"
  dybatpho::expect_envs DYBATPHO_SLACK_WEBHOOK_URL

  local payload
  local notification_json_escape
  __dybatpho_log_json_escape_into notification_json_escape "${message}"
  payload=$(printf '{"text":"%s"}' "${notification_json_escape}")

  dybatpho::debug "Sending Slack notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  __dybatpho_notification_post slack "${DYBATPHO_SLACK_WEBHOOK_URL}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_telegram {
  local message
  dybatpho::expect_args message -- "$@"
  local parse_mode="${2:-}"
  dybatpho::expect_envs DYBATPHO_TELEGRAM_BOT_TOKEN DYBATPHO_TELEGRAM_CHAT_ID

  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  local url="https://api.telegram.org/bot${DYBATPHO_TELEGRAM_BOT_TOKEN}/sendMessage"
  local escaped_message escaped_chat_id
  __dybatpho_log_json_escape_into escaped_message "${message}"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  __dybatpho_log_json_escape_into escaped_chat_id "${DYBATPHO_TELEGRAM_CHAT_ID}"

  local payload
  if [[ -n "${parse_mode}" ]]; then
    local escaped_parse_mode
    __dybatpho_log_json_escape_into escaped_parse_mode "${parse_mode}"
    printf -v payload '{"chat_id":"%s","text":"%s","parse_mode":"%s"}' "${escaped_chat_id}" "${escaped_message}" \
      "${escaped_parse_mode}"
  else
    printf -v payload '{"chat_id":"%s","text":"%s"}' "${escaped_chat_id}" "${escaped_message}"
  fi

  dybatpho::debug "Sending Telegram notification"
  __dybatpho_notification_post telegram "${url}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_teams {
  local message
  dybatpho::expect_args message -- "$@"
  local title="${2:-}"
  dybatpho::expect_envs DYBATPHO_TEAMS_WEBHOOK_URL

  local escaped_message
  __dybatpho_log_json_escape_into escaped_message "${message}"

  local body_blocks
  if [[ -n "${title}" ]]; then
    local escaped_title
    __dybatpho_log_json_escape_into escaped_title "${title}"
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
  __dybatpho_notification_post teams "${DYBATPHO_TEAMS_WEBHOOK_URL}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_google_chat {
  local message
  dybatpho::expect_args message -- "$@"
  dybatpho::expect_envs DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL

  local payload
  local notification_json_escape
  __dybatpho_log_json_escape_into notification_json_escape "${message}"
  payload=$(printf '{"text":"%s"}' "${notification_json_escape}")

  dybatpho::debug "Sending Google Chat notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  __dybatpho_notification_post google_chat "${DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_discord {
  local message
  dybatpho::expect_args message -- "$@"
  local username="${2:-}"
  dybatpho::expect_envs DYBATPHO_DISCORD_WEBHOOK_URL

  local escaped_message
  __dybatpho_log_json_escape_into escaped_message "${message}"

  local payload
  if [[ -n "${username}" ]]; then
    local escaped_username
    __dybatpho_log_json_escape_into escaped_username "${username}"
    printf -v payload '{"content":"%s","username":"%s"}' "${escaped_message}" "${escaped_username}"
  else
    printf -v payload '{"content":"%s"}' "${escaped_message}"
  fi

  dybatpho::debug "Sending Discord notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  __dybatpho_notification_post discord "${DYBATPHO_DISCORD_WEBHOOK_URL}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
#######################################
function dybatpho::notify_webhook {
  local url payload
  dybatpho::expect_args url payload -- "$@"
  shift 2

  # The URL is often the credential itself, so only its host reaches the log.
  local shown_url
  __dybatpho_network_redact_url_into shown_url "${url}"
  dybatpho::debug "Sending webhook notification to ${shown_url}"
  __dybatpho_notification_post webhook "${url}" "${payload}" \
    --request POST \
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
    low | normal | critical) ;;                                                                     # kcov(skip)
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
# @exitcode 1 Missing arguments or environment variables, an invalid topic, server URL or priority, or tags
#   holding a line break
# @exitcode 4 HTTP 4xx from the server, such as a refused token
# @exitcode 5 HTTP 5xx from the server
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
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
  # Tags are split on commas from one line, so a line break would silently drop
  # every tag after it. The title and the message travel as JSON strings and
  # keep their line breaks.
  [[ "${tags}" != *[$'\r\n']* ]] \
    || dybatpho::die "${FUNCNAME[0]}: tags must not contain a line break" # kcov(skip)

  local payload escaped
  __dybatpho_log_json_escape_into escaped "${DYBATPHO_NTFY_TOPIC}"
  payload="{\"topic\":\"${escaped}\""
  __dybatpho_log_json_escape_into escaped "${message}"
  payload+=",\"message\":\"${escaped}\""
  if [[ -n "${title}" ]]; then
    __dybatpho_log_json_escape_into escaped "${title}"
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
      __dybatpho_log_json_escape_into escaped "${tag}"
      list+="${list:+,}\"${escaped}\""
    done
    [[ -n "${list}" ]] && payload+=",\"tags\":[${list}]"
  fi
  payload+="}"

  local authorization=""
  [[ -z "${token}" ]] || authorization="Authorization: Bearer ${token}"

  dybatpho::debug "Sending ntfy notification"
  __dybatpho_network_with_secret_headers "${authorization}" -- \
    __dybatpho_notification_post ntfy "${url}" "${payload}" \
    --request POST
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
# @exitcode 9 `DYBATPHO_NOTIFY_CIRCUIT` is on and this provider\'s circuit is open; nothing was sent
# @see dybatpho::curl_json
# @see dybatpho::circuit_breaker
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
  __dybatpho_log_json_escape_into escaped "${message}"
  payload="{\"message\":\"${escaped}\""
  if [[ -n "${title}" ]]; then
    __dybatpho_log_json_escape_into escaped "${title}"
    payload+=",\"title\":\"${escaped}\""
  fi
  [[ -n "${priority}" ]] && payload+=",\"priority\":${priority}"
  payload+="}"

  dybatpho::debug "Sending Gotify notification"
  # shellcheck disable=SC2154 # required by `dybatpho::expect_envs` above
  __dybatpho_network_with_secret_headers "X-Gotify-Key: ${DYBATPHO_GOTIFY_TOKEN}" -- \
    __dybatpho_notification_post gotify "${url}/message" "${payload}" \
    --request POST
}

#######################################
# @description Encode a header value for a mail message.
#   Printable ASCII is its own encoding. Anything else is written as RFC 2047
#   `Q` encoded words of UTF-8, each short enough for a header line and never
#   splitting a character between two words, so a subject in any language
#   arrives intact instead of as whatever the receiving MTA guesses.
# @arg $1 string Name of the variable receiving the encoded value
# @arg $2 string Header value, already checked to hold no line break
# @set The named variable
# @internal
#######################################
function __dybatpho_notification_mime_header {
  local __dybatpho_mh_name __dybatpho_mh_text
  dybatpho::expect_args __dybatpho_mh_name __dybatpho_mh_text -- "$@"
  local -n __dybatpho_mh_out="${__dybatpho_mh_name}"
  # Bytes, not characters, are what get encoded.
  local LC_ALL=C
  if [[ "${__dybatpho_mh_text}" =~ ^[[:print:]]*$ ]]; then
    __dybatpho_mh_out="${__dybatpho_mh_text}"
    return 0
  fi

  # Every local carries the prefix: the caller's variable may have any name,
  # and a local of the same name would capture the result.
  local __dybatpho_mh_all="" __dybatpho_mh_word=""
  local __dybatpho_mh_byte __dybatpho_mh_code __dybatpho_mh_token
  local __dybatpho_mh_i
  for ((__dybatpho_mh_i = 0; __dybatpho_mh_i < ${#__dybatpho_mh_text}; __dybatpho_mh_i++)); do
    __dybatpho_mh_byte="${__dybatpho_mh_text:__dybatpho_mh_i:1}"
    printf -v __dybatpho_mh_code '%d' "'${__dybatpho_mh_byte}"
    # Only the byte itself: glibc can report a high byte as negative, and
    # musl's C locale maps it to the codepoint `0xDF00` plus the byte.
    __dybatpho_mh_code=$((__dybatpho_mh_code & 0xFF))
    # A word closes only before the first byte of a character (a UTF-8
    # continuation byte is 0x80-0xBF), and early enough that the longest
    # character still fits inside the 75 columns an encoded word may use.
    #
    # kcov loses its trace once a raw non-ASCII byte has gone through it, so
    # the lines that only such a byte reaches carry `kcov(skip)`. They are run
    # by "splits a long subject without breaking a character" and "encodes a
    # subject that is not ASCII" in `test/notification.bats`.
    if ((${#__dybatpho_mh_word} > 50 && (__dybatpho_mh_code < 128 || __dybatpho_mh_code > 191))); then
      __dybatpho_mh_all+="${__dybatpho_mh_all:+$'\n' }"      # kcov(skip)
      __dybatpho_mh_all+="=?UTF-8?Q?${__dybatpho_mh_word}?=" # kcov(skip)
      __dybatpho_mh_word=""                                  # kcov(skip)
    fi
    if [[ "${__dybatpho_mh_byte}" == [A-Za-z0-9!*+/-] ]]; then
      __dybatpho_mh_token="${__dybatpho_mh_byte}"
    elif [[ "${__dybatpho_mh_byte}" == " " ]]; then
      __dybatpho_mh_token="_"
    else
      printf -v __dybatpho_mh_token '=%02X' "${__dybatpho_mh_code}" # kcov(skip)
    fi
    __dybatpho_mh_word+="${__dybatpho_mh_token}"
  done
  __dybatpho_mh_all+="${__dybatpho_mh_all:+$'\n' }"
  __dybatpho_mh_all+="=?UTF-8?Q?${__dybatpho_mh_word}?="
  __dybatpho_mh_out="${__dybatpho_mh_all}"
}

#######################################
# @description Return success when a value can be handed to `sendmail` as a
#   recipient or a sender: an email address, which also rules out a line break,
#   and one that cannot be read as an option.
# @arg $1 string Address
# @exitcode 0 The value is a usable address
# @exitcode 1 It is not
# @internal
#######################################
function __dybatpho_notification_is_address {
  local address
  dybatpho::expect_args address -- "$@"
  [[ "${address}" != -* ]] || return 1
  dybatpho::validate_is email "${address}"
}

#######################################
# @description Send a plain-text email through the local `sendmail`.
#   Any MTA that installs a `sendmail` command will do — Postfix, Exim, OpenSMTPD,
#   msmtp, nullmailer. The recipients are handed to it as arguments after `--`,
#   never read back from the headers, and every address, the sender and the
#   subject are checked for a line break first, so text from a variable cannot
#   add a header or a recipient. A subject that is not plain ASCII is encoded
#   for the header, and the body is sent as UTF-8; a line holding a single `.`
#   does not end the message early.
#
#   Addresses are checked by the `validate` module, which this one does not
#   load: the webhook notifiers have no address to check, so only a script that
#   sends email loads it.
# @tip Load `validate` as well to send email: `--modules notification validate`
# @example
#   dybatpho::notify_email ops@example.com "Backup failed" "$(tail -n 20 backup.log)"
#   dybatpho::notify_email "ops@example.com,lead@example.com" "Nightly report" "${report}" bot@example.com
#
# @arg $1 string Recipients, comma-separated
# @arg $2 string Subject
# @arg $3 string Body
# @arg $4 string Sender address, default is `DYBATPHO_EMAIL_FROM`, or the MTA's own default when neither is set
# @env DYBATPHO_EMAIL_FROM string Default sender address
# @env DYBATPHO_SENDMAIL string The sendmail command, default is `sendmail` on PATH, then `/usr/sbin/sendmail`
#   and `/usr/lib/sendmail`
# @env DRY_RUN string Print the sendmail command instead of sending anything
# @exitcode 0 The message was handed to the MTA
# @exitcode 1 Missing arguments, an invalid address, a line break in the subject, or the `validate` module not loaded
# @exitcode 127 No sendmail command was found
# @exitcode other The sendmail command's own exit code
#######################################
function dybatpho::notify_email {
  local recipients subject body
  dybatpho::expect_args recipients subject body -- "$@"
  # The guard names an internal helper: a child shell inherits the exported
  # `dybatpho::` functions without the internals `validate_is` calls. It is
  # exercised in a child shell, which kcov does not follow.
  __dybatpho_helpers_need_module validate __dybatpho_validate_match "${FUNCNAME[0]}"
  local from="${4:-${DYBATPHO_EMAIL_FROM-}}"

  # The `die` lines below are tested under `run`, which kcov cannot observe.
  # A line break would cut the list short when it is split, so it is refused
  # outright rather than dropping the recipients after it.
  [[ "${recipients}" != *[$'\r\n']* ]] \
    || dybatpho::die "${FUNCNAME[0]}: recipients must not contain a line break" # kcov(skip)
  local address
  local -a addresses=() list=()
  IFS=',' read -r -a list <<< "${recipients}"
  for address in ${list[@]+"${list[@]}"}; do
    address="$(dybatpho::trim "${address}")"
    [[ -n "${address}" ]] || continue
    __dybatpho_notification_is_address "${address}" \
      || dybatpho::die "${FUNCNAME[0]}: '${address}' is not an email address" # kcov(skip)
    addresses+=("${address}")
  done
  ((${#addresses[@]} > 0)) || dybatpho::die "${FUNCNAME[0]}: no recipient given" # kcov(skip)
  if [[ -n "${from}" ]]; then
    __dybatpho_notification_is_address "${from}" \
      || dybatpho::die "${FUNCNAME[0]}: sender '${from}' is not an email address" # kcov(skip)
  fi
  [[ "${subject}" != *[$'\r\n']* ]] \
    || dybatpho::die "${FUNCNAME[0]}: subject must not contain a line break" # kcov(skip)

  local sendmail="${DYBATPHO_SENDMAIL-}" candidate
  if [[ -z "${sendmail}" ]]; then
    for candidate in "${__DYBATPHO_NOTIFICATION_SENDMAILS[@]}"; do
      if dybatpho::is command "${candidate}"; then
        sendmail="${candidate}"
        break
      fi
    done
  fi
  local -a command=("${sendmail:-sendmail}" -i -- "${addresses[@]}")
  # shellcheck disable=SC2154 # declared by `src/process.sh`, a core module
  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run "${command[@]}"
    return 0
  fi
  local missing="No sendmail command found: install an MTA or set DYBATPHO_SENDMAIL"
  [[ -n "${sendmail}" ]] || dybatpho::die "${missing}" 127 # kcov(skip)
  dybatpho::require "${sendmail}"                          # kcov(skip)

  local encoded_subject to_header
  __dybatpho_notification_mime_header encoded_subject "${subject}"
  printf -v to_header '%s, ' "${addresses[@]}"
  local message=""
  [[ -n "${from}" ]] && message+="From: ${from}"$'\n'
  message+="To: ${to_header%, }"$'\n'
  message+="Subject: ${encoded_subject}"$'\n'
  message+="MIME-Version: 1.0"$'\n'
  message+="Content-Type: text/plain; charset=UTF-8"$'\n'
  message+="Content-Transfer-Encoding: 8bit"$'\n'
  message+=$'\n'"${body}"

  dybatpho::debug "Sending email to ${#addresses[@]} recipient(s) through ${sendmail}"
  "${command[@]}" <<< "${message}"
}
