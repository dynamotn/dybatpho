# notification.sh

Utilities for sending messages to chat and notification providers

> 🧭 Source: [src/notification.sh](../src/notification.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to send messages to popular messaging and
notification platforms through their webhook or bot APIs:

- **Slack** – Incoming Webhooks
- **Telegram** – Bot API `sendMessage`
- **Microsoft Teams** – Incoming Webhook (Adaptive Card)
- **Google Chat** – Incoming Webhook
- **Discord** – Incoming Webhook
- **Generic** – Any webhook that accepts a raw JSON POST body
- **ntfy** – Publish to a topic on ntfy.sh or a self-hosted server
- **Desktop** – `notify-send` on Linux and the BSDs, `osascript` on macOS

### 🚀 Highlights

- [`dybatpho::notify_slack`](#dybatphonotify_slack) — Send a message to a Slack channel via Incoming Webhook.
- [`dybatpho::notify_telegram`](#dybatphonotify_telegram) — Send a message to a Telegram chat via Bot API.
- [`dybatpho::notify_teams`](#dybatphonotify_teams) — Send a message to a Microsoft Teams channel via Incoming Webhook. Uses the Adaptive Card format required by the current Teams webhook API.
- [`dybatpho::notify_google_chat`](#dybatphonotify_google_chat) — Send a message to a Google Chat space via Incoming Webhook.
- [`dybatpho::notify_discord`](#dybatphonotify_discord) — Send a message to a Discord channel via Incoming Webhook.
- [`dybatpho::notify_webhook`](#dybatphonotify_webhook) — Send a raw JSON payload to an arbitrary webhook URL via HTTP POST.
- [`dybatpho::notify_desktop`](#dybatphonotify_desktop) — Show a notification on the local desktop. `notify-send` (libnotify, on Linux and the BSDs) is used when it is installed, and `osascript` (macOS) otherwise. The title and the body reach either one as separate arguments, never spliced into a command or a script, so quotes, a leading `-` or AppleScript syntax in them are shown as written. macOS has no urgency for a notification, so it is accepted there and has no effect.
- [`dybatpho::notify_ntfy`](#dybatphonotify_ntfy) — Publish a message to an [ntfy](https://ntfy.sh) topic, on ntfy.sh or a server of your own. The message is published as JSON to the server root, so the title, the priority and the tags travel in the body and keep any character they hold. An access token is sent as a bearer header through the network module's out-of-band channel, so it never appears on curl's command line.

<a id="usage"></a>
## 🚀 Usage

### When to use this module

Use `notification.sh` when you want to:

- notify a team channel about CI/CD events
- alert on-call engineers from a cron job or monitoring script
- post deployment summaries from a release pipeline
- broadcast build results to a shared chat room

### Common patterns

#### Send a Slack message

```bash
export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
dybatpho::notify_slack "Deployment *v1.2.3* succeeded :rocket:"
```

#### Send a Telegram message

```bash
export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
dybatpho::notify_telegram "Build #42 passed"
# With Markdown formatting:
dybatpho::notify_telegram "Build #42 passed" "Markdown"
```

#### Send a Teams message with a title

```bash
export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/..."
dybatpho::notify_teams "All checks passed" "Deploy complete"
```

#### Publish to an ntfy topic

```bash
export DYBATPHO_NTFY_TOPIC="backups-7f3a"
dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent "warning"
```

#### Show a desktop notification

```bash
dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
dybatpho::notify_desktop "Disk almost full" "/var is at 97%" critical
```

#### Send to any webhook

```bash
dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
```

<a id="see-also"></a>
## 🔗 See also

- [example/notification_ops.sh](../example/notification_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Most providers require a webhook URL or API token set via environment variables. The functions validate these before making requests.

<a id="reference"></a>
## 📚 Reference

### `dybatpho::notify_slack`

Send a message to a Slack channel via Incoming Webhook.

**🧪 Example**

```bash
export DYBATPHO_SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T.../B.../xxx"
dybatpho::notify_slack "Hello from dybatpho"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message text (supports Slack mrkdwn formatting) |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_SLACK_WEBHOOK_URL`** | string | Slack Incoming Webhook URL |

**🚦 Exit codes**

- `0`: Message sent successfully
- `1`: Missing arguments or environment variables
- `4`: HTTP 4xx from Slack
- `5`: HTTP 5xx from Slack

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_telegram`

Send a message to a Telegram chat via Bot API.

**🧪 Example**

```bash
export DYBATPHO_TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."
export DYBATPHO_TELEGRAM_CHAT_ID="-100123456789"
dybatpho::notify_telegram "Build passed"
dybatpho::notify_telegram "*Build* passed" "Markdown"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message text (supports HTML or Markdown when parse mode is set) |
| `$2` | string | Parse mode: `HTML`, `Markdown`, or `MarkdownV2`. Default is empty (plain text) |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TELEGRAM_BOT_TOKEN`** | string | Telegram Bot API token |
| **`DYBATPHO_TELEGRAM_CHAT_ID`** | string | Target chat, group, or channel ID |

**🚦 Exit codes**

- `0`: Message sent successfully
- `1`: Missing arguments or environment variables
- `4`: HTTP 4xx from Telegram
- `5`: HTTP 5xx from Telegram

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_teams`

Send a message to a Microsoft Teams channel via Incoming Webhook.
Uses the Adaptive Card format required by the current Teams webhook API.

**🧪 Example**

```bash
export DYBATPHO_TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/..."
dybatpho::notify_teams "Deployment complete"
dybatpho::notify_teams "All checks passed" "Deploy v2.0"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message body text |
| `$2` | string | Optional card title shown above the message body |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_TEAMS_WEBHOOK_URL`** | string | Microsoft Teams Incoming Webhook URL |

**🚦 Exit codes**

- `0`: Message sent successfully
- `1`: Missing arguments or environment variables
- `4`: HTTP 4xx from Teams
- `5`: HTTP 5xx from Teams

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_google_chat`

Send a message to a Google Chat space via Incoming Webhook.

**🧪 Example**

```bash
export DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/.../messages?key=...&token=..."
dybatpho::notify_google_chat "Release v2.0 is live"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message text (supports Google Chat formatting with asterisks and underscores) |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_GOOGLE_CHAT_WEBHOOK_URL`** | string | Google Chat Incoming Webhook URL |

**🚦 Exit codes**

- `0`: Message sent successfully
- `1`: Missing arguments or environment variables
- `4`: HTTP 4xx from Google Chat
- `5`: HTTP 5xx from Google Chat

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_discord`

Send a message to a Discord channel via Incoming Webhook.

**🧪 Example**

```bash
export DYBATPHO_DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
dybatpho::notify_discord "Build #99 succeeded"
dybatpho::notify_discord "Deploy done" "CI Bot"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message content (supports Discord Markdown) |
| `$2` | string | Optional display name override for the webhook bot |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_DISCORD_WEBHOOK_URL`** | string | Discord Incoming Webhook URL |

**🚦 Exit codes**

- `0`: Message sent successfully
- `1`: Missing arguments or environment variables
- `4`: HTTP 4xx from Discord
- `5`: HTTP 5xx from Discord

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_webhook`

Send a raw JSON payload to an arbitrary webhook URL via HTTP POST.

**🧪 Example**

```bash
dybatpho::notify_webhook "https://my.service/hook" '{"event":"deploy","status":"ok"}'
# With extra curl flags:
dybatpho::notify_webhook "https://my.service/hook" '{"text":"hi"}' \
  --header "Authorization: Bearer ${TOKEN}"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Webhook URL |
| `$2` | string | JSON payload body |
| `$@` | string | Extra arguments forwarded to curl |

**🚦 Exit codes**

- `0`: Webhook accepted the payload
- `1`: Missing arguments
- `4`: HTTP 4xx from webhook
- `5`: HTTP 5xx from webhook

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)


---

### `dybatpho::notify_desktop`

Show a notification on the local desktop.
`notify-send` (libnotify, on Linux and the BSDs) is used when it is
installed, and `osascript` (macOS) otherwise. The title and the body reach
either one as separate arguments, never spliced into a command or a script,
so quotes, a leading `-` or AppleScript syntax in them are shown as written.
macOS has no urgency for a notification, so it is accepted there and has no
effect.

**🧪 Example**

```bash
dybatpho::notify_desktop "Backup finished" "42 files, 3.1 GiB"
dybatpho::notify_desktop "Disk almost full" "/var is at 97%" critical

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Title |
| `$2` | string | Body, default is empty |
| `$3` | string | Urgency: `low`, `normal` or `critical`, default is `normal` |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | Print the command instead of showing the notification; with no backend installed, the `notify-send` form is printed |

**🚦 Exit codes**

- `0`: The notification was handed to the desktop
- `1`: Missing or empty title, or an unknown urgency
- `127`: Neither `notify-send` nor `osascript` is installed
- `other`: The backend's own exit code, such as `notify-send` finding no desktop session


---

### `dybatpho::notify_ntfy`

Publish a message to an [ntfy](https://ntfy.sh) topic, on
ntfy.sh or a server of your own.
The message is published as JSON to the server root, so the title, the
priority and the tags travel in the body and keep any character they hold.
An access token is sent as a bearer header through the network module's
out-of-band channel, so it never appears on curl's command line.

**🧪 Example**

```bash
export DYBATPHO_NTFY_TOPIC="backups-7f3a"
dybatpho::notify_ntfy "Backup finished"
dybatpho::notify_ntfy "Disk /var at 97%" "Disk almost full" urgent "warning,floppy_disk"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Message text |
| `$2` | string | Optional title |
| `$3` | string | Optional priority: `1`-`5`, or `min`, `low`, `default`, `high`, `max` or `urgent` |
| `$4` | string | Optional comma-separated tags; a tag that names an emoji is shown as one |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_NTFY_TOPIC`** | string | Topic to publish to: letters, digits, `-` and `_`, at most 64 characters |
| **`DYBATPHO_NTFY_URL`** | string | Server URL, default is `https://ntfy.sh` |
| **`DYBATPHO_NTFY_TOKEN`** | string | Optional access token for a protected topic |

**🚦 Exit codes**

- `0`: Message published
- `1`: Missing arguments or environment variables, or an invalid topic, server URL or priority
- `4`: HTTP 4xx from the server, such as a refused token
- `5`: HTTP 5xx from the server

**🔗 See also**

- [dybatpho::curl_json](#dybatphocurl_json)
