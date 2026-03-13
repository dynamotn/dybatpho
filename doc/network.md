# network.sh

Utilities for network

> 🧭 Source: [src/network.sh](../src/network.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to work with network connection.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CURL_MAX_RETRIES`** | number | Max number of retry attempts when `dybatpho::curl_do` retries a request |

### 🚀 Highlights

- [`__get_http_code`](#__get_http_code) — Get description of HTTP status code
- [`dybatpho::curl_do`](#dybatphocurl_do) — Transferring data with URL by curl
- [`__request`](#__request) — Execute one curl request attempt and capture its HTTP status code.
- [`dybatpho::curl_download`](#dybatphocurl_download) — Download file

<a id="tips"></a>
## 💡 Tips

### `dybatpho::curl_do`

- The request body is written to the provided output file, or `/dev/null` when omitted

### `dybatpho::curl_download`

- The destination directory is created automatically before downloading

<a id="reference"></a>
## 📚 Reference

### `__get_http_code`

Get description of HTTP status code

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Status code |

**📤 Output on stdout**

- Description of status code


---

### `dybatpho::curl_do`

Transferring data with URL by curl

**🧪 Example**

```bash
dybatpho::curl_do https://example.com /tmp/1
dybatpho::curl_do https://example.com /tmp/1 --compressed

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$3` | string | Other options/arguments for curl |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CURL_MAX_RETRIES`** | number | Override the retry budget used around curl requests |

**📝 Notes**

- HTTP 4xx responses are treated as completed requests and returned to the caller as exit code `4`

**🚦 Exit codes**

- `0`: Transferred data
- `1`: Unknown error
- `3`: First digit of HTTP error code 3xx
- `4`: First digit of HTTP error code 4xx
- `5`: First digit of HTTP error code 5xx
- `127`: Curl isn't installed


---

### `__request`

Execute one curl request attempt and capture its HTTP status code.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$@` | string | Extra curl arguments forwarded from `dybatpho::curl_do` |

**🧩 Variable sets**

- **`code`**: string HTTP status code returned by curl

**🚦 Exit codes**

- `0`: Request completed with an accepted HTTP status (`2xx` or `4xx`)
- `1`: Curl failed or the response should be retried/treated as an error


---

### `dybatpho::curl_download`

Download file

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Destination of file to download |
| `$@` | string | Other options/arguments for curl |

**🚦 Exit codes**

- `6`: Can't create folder of destination file

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)

