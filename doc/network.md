# network.sh

Utilities for network

> 🧭 Source: [src/network.sh](../src/network.sh)
>
> Jump to: [Overview](#overview) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

This module contains functions to work with network connection, downloads,
JSON-oriented requests, and HEAD requests. It also provides multipart
uploads, resumable downloads with checksum verification, normalized
response parsing (status/headers/body), per-request timeouts, and an
in-memory circuit breaker.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CURL_MAX_RETRIES`** | number | Max number of retry attempts when `dybatpho::curl_do` retries a request |
| **`DYBATPHO_CURL_RETRY_BASE_DELAY`** | number | Initial retry delay in seconds (default `2`) |
| **`DYBATPHO_CURL_RETRY_MAX_DELAY`** | number | Maximum retry delay in seconds (default `30`) |
| **`DYBATPHO_CURL_RETRY_JITTER`** | bool | Add up to one base delay of random jitter |
| **`DYBATPHO_CURL_CONNECT_TIMEOUT`** | number | Optional curl connection timeout in seconds |
| **`DYBATPHO_CURL_TIMEOUT`** | number | Optional curl total timeout in seconds |
| **`DYBATPHO_CIRCUIT_THRESHOLD`** | number | Consecutive failures before `dybatpho::circuit_breaker` opens a circuit (default `5`) |
| **`DYBATPHO_CIRCUIT_COOLDOWN`** | number | Seconds an open circuit waits before allowing a trial request (default `30`) |

### 🚀 Highlights

- [`__get_http_code`](#__get_http_code) — Get description of HTTP status code
- [`dybatpho::curl_do`](#dybatphocurl_do) — Transferring data with URL by curl
- [`dybatpho::curl_download`](#dybatphocurl_download) — Download file
- [`dybatpho::curl_json`](#dybatphocurl_json) — Transfer JSON data with URL by curl.
- [`dybatpho::curl_head`](#dybatphocurl_head) — Fetch only HTTP headers for a URL by curl.
- [`dybatpho::curl_upload`](#dybatphocurl_upload) — Upload fields and files with curl using multipart/form-data.
- [`dybatpho::verify_checksum`](#dybatphoverify_checksum) — Verify a downloaded file against an expected checksum.
- [`dybatpho::curl_resume_download`](#dybatphocurl_resume_download) — Download a file with resume support and optional checksum verification.
- [`dybatpho::curl_parse_response`](#dybatphocurl_parse_response) — Parse a raw curl header dump (and optional body file) into normalized response state.
- [`dybatpho::curl_response_header`](#dybatphocurl_response_header) — Print a normalized response header captured by `dybatpho::curl_parse_response`.
- [`dybatpho::curl_request`](#dybatphocurl_request) — Perform a request via `dybatpho::curl_do` and parse its response into normalized status/header/body state.
- [`dybatpho::curl_timeout`](#dybatphocurl_timeout) — Perform a request via `dybatpho::curl_do` with connect/total timeouts scoped to this call only.
- [`dybatpho::circuit_state`](#dybatphocircuit_state) — Report whether a circuit breaker key is currently open, half-open, or closed.
- [`dybatpho::circuit_reset`](#dybatphocircuit_reset) — Reset a circuit breaker key back to the closed state.
- [`dybatpho::circuit_breaker`](#dybatphocircuit_breaker) — Run a shell command guarded by a circuit breaker keyed by name.

<a id="tips"></a>
## 💡 Tips

### `dybatpho::curl_do`

- The request body is written to the provided output file, or `/dev/null` when omitted

### `dybatpho::curl_download`

- The destination directory is created automatically before downloading

### `dybatpho::curl_upload`

- The request method defaults to `POST`; pass `--request PUT` (or similar) afterwards to override it

### `dybatpho::curl_resume_download`

- A partially downloaded destination file is resumed instead of restarted

### `dybatpho::curl_request`

- Response headers aren't captured while `DRY_RUN` is enabled

### `dybatpho::curl_timeout`

- Overrides apply only for the duration of this call; global `DYBATPHO_CURL_*` timeouts are unaffected

### `dybatpho::circuit_breaker`

- The command is executed with `eval`, so pass it as one shell command string

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


---

### `dybatpho::curl_upload`

Upload fields and files with curl using multipart/form-data.

**🧪 Example**

```bash
dybatpho::curl_upload https://example.com/upload /tmp/resp.json note="nightly run" report=@/tmp/report.csv
dybatpho::curl_upload https://example.com/upload /tmp/resp.json report=@/tmp/report.csv --request PUT

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$@` | string | Form fields as `name=value` or `name=@path` pairs, plus any other curl options/arguments |

**🚦 Exit codes**

- `2`: A `name=@path` field references a file that does not exist

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)


---

### `dybatpho::verify_checksum`

Verify a downloaded file against an expected checksum.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File to verify |
| `$2` | string | Expected checksum as `algorithm:hexdigest`, algorithm is one of `sha256`, `sha1`, or `md5` |

**🚦 Exit codes**

- `7`: Checksum mismatch
- `8`: Unsupported algorithm, invalid spec, or the checksum tool isn't installed


---

### `dybatpho::curl_resume_download`

Download a file with resume support and optional checksum verification.

**🧪 Example**

```bash
dybatpho::curl_resume_download https://example.com/big.iso /tmp/big.iso
dybatpho::curl_resume_download https://example.com/big.iso /tmp/big.iso sha256:3a7bd3e2360a3d...

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Destination of file to download |
| `$3` | string | Optional checksum as `algorithm:hexdigest` (sha256, sha1, or md5) |
| `$@` | string | Other options/arguments for curl |

**🚦 Exit codes**

- `6`: Can't create folder of destination file
- `7`: Checksum verification failed
- `8`: Unsupported checksum algorithm or missing checksum tool

**🔗 See also**

- [dybatpho::curl_download](#dybatphocurl_download)
- [dybatpho::verify_checksum](#dybatphoverify_checksum)


---

### `dybatpho::curl_parse_response`

Parse a raw curl header dump (and optional body file) into normalized response state.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Path to a header file captured via `curl -D` (may contain multiple header blocks from redirects; the last block wins) |
| `$2` | string | Optional path to the response body file to record |

**🧩 Variable sets**

- **`DYBATPHO_HTTP_STATUS`**: number Status code of the last received response block
- **`DYBATPHO_HTTP_HEADERS`**: map Lower-cased header name to value, from the last response block
- **`DYBATPHO_HTTP_BODY_FILE`**: string Path to the response body, or empty when omitted

**🚦 Exit codes**

- `1`: No status line was found in the header file


---

### `dybatpho::curl_response_header`

Print a normalized response header captured by `dybatpho::curl_parse_response`.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Header name, matched case-insensitively |
| `$2` | string | Optional default value |

**📤 Output on stdout**

- Header value

**🚦 Exit codes**

- `1`: Header is missing and no default was supplied


---

### `dybatpho::curl_request`

Perform a request via `dybatpho::curl_do` and parse its response into normalized status/header/body state.

**🧪 Example**

```bash
dybatpho::curl_request https://example.com/api /tmp/resp.json
echo "${DYBATPHO_HTTP_STATUS}"
dybatpho::curl_response_header content-type

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$@` | string | Other options/arguments for curl |

**🧩 Variable sets**

- **`DYBATPHO_HTTP_STATUS`**: number Status code of the last received response block
- **`DYBATPHO_HTTP_HEADERS`**: map Lower-cased header name to value, from the last response block
- **`DYBATPHO_HTTP_BODY_FILE`**: string Path holding the response body

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)
- [dybatpho::curl_parse_response](#dybatphocurl_parse_response)


---

### `dybatpho::curl_timeout`

Perform a request via `dybatpho::curl_do` with connect/total timeouts scoped to this call only.

**🧪 Example**

```bash
dybatpho::curl_timeout https://example.com /tmp/out 2 10
dybatpho::curl_timeout https://example.com /tmp/out "" 5 --header "X-Test: 1"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | URL |
| `$2` | string | Location of curl output, default is `/dev/null` |
| `$3` | number | Connect timeout in seconds for this request, empty keeps the global default |
| `$4` | number | Total timeout in seconds for this request, empty keeps the global default |
| `$@` | string | Other options/arguments for curl |

**🔗 See also**

- [dybatpho::curl_do](#dybatphocurl_do)


---

### `dybatpho::circuit_state`

Report whether a circuit breaker key is currently open, half-open, or closed.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Circuit key |

**📤 Output on stdout**

- `open`, `half-open`, or `closed`


---

### `dybatpho::circuit_reset`

Reset a circuit breaker key back to the closed state.

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Circuit key |


---

### `dybatpho::circuit_breaker`

Run a shell command guarded by a circuit breaker keyed by name.

**🧪 Example**

```bash
dybatpho::circuit_breaker api.example.com "dybatpho::curl_do https://api.example.com/health"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Circuit key, typically a host or service name |
| `$2` | string | Shell command string to run |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_CIRCUIT_THRESHOLD`** | number | Consecutive failures before the circuit opens (default `5`) |
| **`DYBATPHO_CIRCUIT_COOLDOWN`** | number | Seconds the circuit stays open before a trial request is allowed (default `30`) |

**📝 Notes**

- Circuit breaker state is in-memory and process-local; it does not persist across script invocations

**🚦 Exit codes**

- `0`: The command succeeded, or a trial request succeeded and closed the circuit
- `9`: The circuit is open; the command was not attempted
- `other`: The command's own exit code, while the circuit is closed or half-open

