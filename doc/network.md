# network.sh

Utilities for network

> 🧭 Source: [src/network.sh](../src/network.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to work with network connection, downloads,
JSON-oriented requests, and HEAD requests.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CURL_MAX_RETRIES`** | number | Max number of retry attempts when `dybatpho::curl_do` retries a request |
| **`DYBATPHO_CURL_RETRY_BASE_DELAY`** | number | Initial retry delay in seconds (default `2`) |
| **`DYBATPHO_CURL_RETRY_MAX_DELAY`** | number | Maximum retry delay in seconds (default `30`) |
| **`DYBATPHO_CURL_RETRY_JITTER`** | bool | Add up to one base delay of random jitter |
| **`DYBATPHO_CURL_CONNECT_TIMEOUT`** | number | Optional curl connection timeout in seconds |
| **`DYBATPHO_CURL_TIMEOUT`** | number | Optional curl total timeout in seconds |

### 🚀 Highlights

- [`__get_http_code`](#__get_http_code) — Get description of HTTP status code
- [`dybatpho::curl_do`](#dybatphocurl_do) — Transferring data with URL by curl
- [`dybatpho::curl_download`](#dybatphocurl_download) — Download file
- [`dybatpho::curl_json`](#dybatphocurl_json) — Transfer JSON data with URL by curl.
- [`dybatpho::curl_head`](#dybatphocurl_head) — Fetch only HTTP headers for a URL by curl.

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


---

### `dybatpho::curl_json`

Transfer JSON data with URL by curl.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$@` | string | Other options/arguments for curl |

**🚦 Exit codes**

- `0`: Transferred data

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)


---

### `dybatpho::curl_head`

Fetch only HTTP headers for a URL by curl.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$@` | string | Other options/arguments for curl |

**🚦 Exit codes**

- `0`: Transferred headers

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)

