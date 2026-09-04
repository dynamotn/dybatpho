#!/usr/bin/env bash
# @file network.sh
# @brief Utilities for network
# @description
#   This module contains functions to work with network connection, downloads,
#   JSON-oriented requests, and HEAD requests. It also provides multipart
#   uploads, resumable downloads with checksum verification, normalized
#   response parsing (status/headers/body), per-request timeouts, and an
#   in-memory circuit breaker.
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_CURL_MAX_RETRIES number Max number of retry attempts when `dybatpho::curl_do` retries a request
# @env DYBATPHO_CURL_RETRY_BASE_DELAY number Initial retry delay in seconds (default `2`)
# @env DYBATPHO_CURL_RETRY_MAX_DELAY number Maximum retry delay in seconds (default `30`)
# @env DYBATPHO_CURL_RETRY_JITTER bool Add up to one base delay of random jitter
# @env DYBATPHO_CURL_CONNECT_TIMEOUT number Optional curl connection timeout in seconds
# @env DYBATPHO_CURL_TIMEOUT number Optional curl total timeout in seconds
# @env DYBATPHO_CIRCUIT_THRESHOLD number Consecutive failures before `dybatpho::circuit_breaker` opens a circuit (default `5`)
# @env DYBATPHO_CIRCUIT_COOLDOWN number Seconds an open circuit waits before allowing a trial request (default `30`)
DYBATPHO_CURL_MAX_RETRIES=${DYBATPHO_CURL_MAX_RETRIES:-5}
DYBATPHO_CURL_RETRY_BASE_DELAY=${DYBATPHO_CURL_RETRY_BASE_DELAY:-2}
DYBATPHO_CURL_RETRY_MAX_DELAY=${DYBATPHO_CURL_RETRY_MAX_DELAY:-30}
DYBATPHO_CURL_RETRY_JITTER=${DYBATPHO_CURL_RETRY_JITTER:-false}
DYBATPHO_CURL_CONNECT_TIMEOUT=${DYBATPHO_CURL_CONNECT_TIMEOUT:-}
DYBATPHO_CURL_TIMEOUT=${DYBATPHO_CURL_TIMEOUT:-}
DYBATPHO_CIRCUIT_THRESHOLD=${DYBATPHO_CIRCUIT_THRESHOLD:-5}
DYBATPHO_CIRCUIT_COOLDOWN=${DYBATPHO_CIRCUIT_COOLDOWN:-30}

# Normalized state populated by `dybatpho::curl_parse_response`/`dybatpho::curl_request`.
declare -gA DYBATPHO_HTTP_HEADERS=()
DYBATPHO_HTTP_STATUS=""
DYBATPHO_HTTP_BODY_FILE=""

# Per-key in-memory state used by `dybatpho::circuit_breaker`.
declare -gA DYBATPHO_CIRCUIT_FAILURES=()
declare -gA DYBATPHO_CIRCUIT_OPENED_AT=()

#######################################
# @description Get description of HTTP status code
# @arg $1 string Status code
# @stdout Description of status code
#######################################
function __get_http_code {
  local code
  dybatpho::expect_args code -- "$@"

  case "${code}" in
    # kcov(disabled)
    '100') echo '100 (continue)' ;;
    '101') echo '101 (switching protocols)' ;;
    # kcov(enabled)
    '200') echo 'done' ;;
    # kcov(disabled)
    '201') echo '201 (created)' ;;
    '202') echo '202 (accepted)' ;;
    '203') echo '203 (non-authoritative information)' ;;
    '204') echo '204 (no content)' ;;
    '205') echo '205 (reset content)' ;;
    '206') echo '206 (partial content)' ;;
    '300') echo '300 (multiple choices)' ;;
    '301') echo '301 (moved permanently)' ;;
    '302') echo '302 (found)' ;;
    '303') echo '303 (see other)' ;;
    '304') echo '304 (not modified)' ;;
    '305') echo '305 (use proxy)' ;;
    '306') echo '306 (switch proxy)' ;;
    '307') echo '307 (temporary redirect)' ;;
    '400') echo '400 (bad request)' ;;
    '401') echo '401 (unauthorized)' ;;
    '402') echo '402 (payment required)' ;;
    # kcov(enabled)
    '403') echo '403 (forbidden)' ;;
    # kcov(disabled)
    '404') echo '404 (not found)' ;;
    '405') echo '405 (method not allowed)' ;;
    '406') echo '406 (not acceptable)' ;;
    '407') echo '407 (proxy authentication required)' ;;
    '408') echo '408 (request timeout)' ;;
    '409') echo '409 (conflict)' ;;
    '410') echo '410 (gone)' ;;
    '411') echo '411 (length required)' ;;
    '412') echo '412 (precondition failed)' ;;
    '413') echo '413 (request entity too large)' ;;
    '414') echo '414 (request URI too long)' ;;
    '415') echo '415 (unsupported media type)' ;;
    '416') echo '416 (requested range)' ;;
    '417') echo '417 (expectation failed)' ;;
    '418') echo "418 (I'm a teapot)" ;;
    '419') echo '419 (authentication timeout)' ;;
    '420') echo '420 (enhance your calm)' ;;
    '426') echo '426 (upgrade required)' ;;
    '428') echo '428 (precondition required)' ;;
    '429') echo '429 (too many requests)' ;;
    '431') echo '431 (request header fields too large)' ;;
    '451') echo '451 (unavailable for legal reasons)' ;;
    '500') echo '500 (internal server error)' ;;
    '501') echo '501 (not implemented)' ;;
    '502') echo '502 (bad gateway)' ;;
    '503') echo '503 (service unavailable)' ;;
    '504') echo '504 (gateway timeout)' ;;
    '505') echo '505 (HTTP version not supported)' ;;
    '506') echo '506 (variant also negotiates)' ;;
    '510') echo '510 (not extended)' ;;
    '511') echo '511 (network authentication required)' ;;
    *) echo "${code} (unknown)" ;;
      # kcov(enabled)
  esac
}

#######################################
# @description Transferring data with URL by curl
# @example
#   dybatpho::curl_do https://example.com /tmp/1
#   dybatpho::curl_do https://example.com /tmp/1 --compressed
#
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $3 string Other options/arguments for curl
# @env DYBATPHO_CURL_MAX_RETRIES number Override the retry budget used around curl requests
# @exitcode 0 Transferred data
# @exitcode 1 Unknown error
# @exitcode 3 First digit of HTTP error code 3xx
# @exitcode 4 First digit of HTTP error code 4xx
# @exitcode 5 First digit of HTTP error code 5xx
# @exitcode 127 Curl isn't installed
# @tip The request body is written to the provided output file, or `/dev/null` when omitted
# @note HTTP 4xx responses are treated as completed requests and returned to the caller as exit code `4`
#######################################
function dybatpho::curl_do {
  local url
  dybatpho::expect_args url -- "$@"
  shift

  if dybatpho::is empty "${url}"; then
    return 1
  fi

  local output="/dev/null"
  if [ $# -ne 0 ]; then
    output="$1"
    shift
  fi

  if dybatpho::is true "${DRY_RUN}"; then
    dybatpho::dry_run curl -fsSL "${url}" -o "${output}" "$@"
    return 0
  fi

  dybatpho::require curl
  [[ "${DYBATPHO_CURL_MAX_RETRIES}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "DYBATPHO_CURL_MAX_RETRIES must be a non-negative integer"
  [[ "${DYBATPHO_CURL_RETRY_BASE_DELAY}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "DYBATPHO_CURL_RETRY_BASE_DELAY must be a non-negative integer"
  [[ "${DYBATPHO_CURL_RETRY_MAX_DELAY}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "DYBATPHO_CURL_RETRY_MAX_DELAY must be a non-negative integer"

  local code="" retry_after delay attempt=0
  local header_file
  header_file=$(mktemp) || dybatpho::die "Unable to create temporary HTTP header file"
  # Keep the body path owned by the caller; only response headers are temporary.
  while :; do
    local curl_args=(-fsSL -D "${header_file}" -w '%{http_code}' -o "${output}")
    [[ -n "${DYBATPHO_CURL_CONNECT_TIMEOUT}" ]] && curl_args+=(--connect-timeout "${DYBATPHO_CURL_CONNECT_TIMEOUT}")
    [[ -n "${DYBATPHO_CURL_TIMEOUT}" ]] && curl_args+=(--max-time "${DYBATPHO_CURL_TIMEOUT}")
    curl_args+=("$@")

    : > "${header_file}"
    if code=$(command curl "${curl_args[@]}" "${url}"); then
      :
    else
      code="000"
      dybatpho::error "Error when access ${url}"
    fi

    local code_description
    code_description=$(__get_http_code "${code}")
    dybatpho::debug "Received HTTP status: ${code_description}"
    if [[ "${code}" =~ ^2[0-9][0-9]$ ]]; then
      rm -f "${header_file}"
      break
    elif [[ "${code}" =~ ^4[0-9][0-9]$ ]]; then
      case "${code}" in
        408 | 425 | 429) ;; # kcov(skip)
        *)
          rm -f "${header_file}"
          break
          ;;
      esac
    fi
    if ((attempt >= DYBATPHO_CURL_MAX_RETRIES)); then
      dybatpho::warn "No more retries left to run curl ${url}."
      rm -f "${header_file}"
      break
    fi

    attempt=$((attempt + 1))
    delay=$((DYBATPHO_CURL_RETRY_BASE_DELAY * (2 ** (attempt - 1))))
    ((delay > DYBATPHO_CURL_RETRY_MAX_DELAY)) && delay="${DYBATPHO_CURL_RETRY_MAX_DELAY}"
    retry_after=$(awk 'tolower($1) == "retry-after:" { gsub("\r", "", $2); if ($2 ~ /^[0-9]+$/) print $2; exit }' "${header_file}")
    [[ -n "${retry_after}" ]] && delay="${retry_after}"
    ((delay > DYBATPHO_CURL_RETRY_MAX_DELAY)) && delay="${DYBATPHO_CURL_RETRY_MAX_DELAY}"
    if dybatpho::is true "${DYBATPHO_CURL_RETRY_JITTER}"; then
      ((delay += RANDOM % (DYBATPHO_CURL_RETRY_BASE_DELAY + 1)))
      ((delay > DYBATPHO_CURL_RETRY_MAX_DELAY)) && delay="${DYBATPHO_CURL_RETRY_MAX_DELAY}"
    fi
    dybatpho::progress "Retrying in ${delay} seconds (${attempt}/${DYBATPHO_CURL_MAX_RETRIES})..."
    sleep "${delay}" || true
  done

  # Return exit code based on HTTP status code
  case "${code}" in
    '2'*) return 0 ;;
    '3'*) return 3 ;;
    '4'*) return 4 ;;
    '5'*) return 5 ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Download file
# @arg $1 string URL
# @arg $2 string Destination of file to download
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_do
# @exitcode 6 Can't create folder of destination file
# @tip The destination directory is created automatically before downloading
#######################################
function dybatpho::curl_download {
  local url dst_file
  dybatpho::expect_args url dst_file -- "$@"
  shift 2
  dybatpho::progress "Downloading ${url}"

  # Create destination folder
  local dst_dir
  dst_dir=$(dirname "${dst_file}") || return 6
  mkdir -p "${dst_dir}" || return 6

  dybatpho::curl_do "${url}" "${dst_file}" -# --no-silent "$@"
}

#######################################
# @description Transfer JSON data with URL by curl.
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_do
# @exitcode 0 Transferred data
#######################################
function dybatpho::curl_json {
  local url
  dybatpho::expect_args url -- "$@"
  local output="/dev/null"
  shift
  if (($# > 0)); then
    output="$1"
    shift
  fi
  dybatpho::curl_do "${url}" "${output}" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    "$@"
}

#######################################
# @description Fetch only HTTP headers for a URL by curl.
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_do
# @exitcode 0 Transferred headers
#######################################
function dybatpho::curl_head {
  local url
  dybatpho::expect_args url -- "$@"
  local output="/dev/null"
  shift
  if (($# > 0)); then
    output="$1"
    shift
  fi
  dybatpho::curl_do "${url}" "${output}" -I "$@"
}

#######################################
# @description Upload fields and files with curl using multipart/form-data.
# @example
#   dybatpho::curl_upload https://example.com/upload /tmp/resp.json note="nightly run" report=@/tmp/report.csv
#   dybatpho::curl_upload https://example.com/upload /tmp/resp.json report=@/tmp/report.csv --request PUT
#
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $@ string Form fields as `name=value` or `name=@path` pairs, plus any other curl options/arguments
# @see dybatpho::curl_do
# @exitcode 2 A `name=@path` field references a file that does not exist
# @tip The request method defaults to `POST`; pass `--request PUT` (or similar) afterwards to override it
#######################################
function dybatpho::curl_upload {
  local url
  dybatpho::expect_args url -- "$@"
  shift
  local output="/dev/null"
  if (($# > 0)); then
    output="$1"
    shift
  fi

  local curl_args=() field path
  while (($#)); do
    field="$1"
    shift
    if [[ "${field}" =~ ^[^=]+=@(.+)$ ]]; then
      path="${BASH_REMATCH[1]}"
      dybatpho::is file "${path}" || dybatpho::die "Upload file not found: ${path}" 2
      curl_args+=(-F "${field}")
    elif [[ "${field}" == *=* ]]; then
      curl_args+=(-F "${field}")
    else
      curl_args+=("${field}")
    fi
  done

  dybatpho::curl_do "${url}" "${output}" --request POST "${curl_args[@]}"
}

#######################################
# @description Verify a downloaded file against an expected checksum.
# @arg $1 string File to verify
# @arg $2 string Expected checksum as `algorithm:hexdigest`, algorithm is one of `sha256`, `sha1`, or `md5`
# @exitcode 7 Checksum mismatch
# @exitcode 8 Unsupported algorithm, invalid spec, or the checksum tool isn't installed
#######################################
function dybatpho::verify_checksum {
  local file checksum
  dybatpho::expect_args file checksum -- "$@"

  [[ "${checksum}" =~ ^(sha256|sha1|md5):([0-9a-fA-F]+)$ ]] \
    || dybatpho::die "Invalid checksum spec: ${checksum}" 8
  local algorithm="${BASH_REMATCH[1]}" expected="${BASH_REMATCH[2],,}"
  local tool
  case "${algorithm}" in
    sha256) tool="sha256sum" ;;
    sha1) tool="sha1sum" ;;
    md5) tool="md5sum" ;;
  esac
  dybatpho::is command "${tool}" || dybatpho::die "${tool} isn't installed" 8

  local actual
  actual=$("${tool}" "${file}" | awk '{print $1}') || dybatpho::die "Unable to compute ${algorithm} checksum for ${file}" 8
  if [[ "${actual,,}" != "${expected}" ]]; then
    dybatpho::error "Checksum mismatch for ${file}: expected ${expected}, got ${actual}"
    return 7
  fi
  dybatpho::debug "Checksum verified for ${file} (${algorithm})"
}

#######################################
# @description Download a file with resume support and optional checksum verification.
# @example
#   dybatpho::curl_resume_download https://example.com/big.iso /tmp/big.iso
#   dybatpho::curl_resume_download https://example.com/big.iso /tmp/big.iso sha256:3a7bd3e2360a3d...
#
# @arg $1 string URL
# @arg $2 string Destination of file to download
# @arg $3 string Optional checksum as `algorithm:hexdigest` (sha256, sha1, or md5)
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_download
# @see dybatpho::verify_checksum
# @exitcode 6 Can't create folder of destination file
# @exitcode 7 Checksum verification failed
# @exitcode 8 Unsupported checksum algorithm or missing checksum tool
# @tip A partially downloaded destination file is resumed instead of restarted
#######################################
function dybatpho::curl_resume_download {
  local url dst_file
  dybatpho::expect_args url dst_file -- "$@"
  shift 2

  local checksum=""
  if (($# > 0)) && [[ "$1" =~ ^(sha256|sha1|md5):[0-9a-fA-F]+$ ]]; then
    checksum="$1"
    shift
  fi

  local dst_dir
  dst_dir=$(dirname "${dst_file}") || return 6
  mkdir -p "${dst_dir}" || return 6

  dybatpho::progress "Downloading ${url} (resume enabled)"
  dybatpho::curl_do "${url}" "${dst_file}" -# --no-silent -C - "$@" || return $?

  if [[ -n "${checksum}" ]]; then
    dybatpho::verify_checksum "${dst_file}" "${checksum}" || return $?
  fi
}

#######################################
# @description Parse a raw curl header dump (and optional body file) into normalized response state.
# @arg $1 string Path to a header file captured via `curl -D` (may contain multiple header blocks from redirects; the last block wins)
# @arg $2 string Optional path to the response body file to record
# @set DYBATPHO_HTTP_STATUS number Status code of the last received response block
# @set DYBATPHO_HTTP_HEADERS map Lower-cased header name to value, from the last response block
# @set DYBATPHO_HTTP_BODY_FILE string Path to the response body, or empty when omitted
# @exitcode 1 No status line was found in the header file
#######################################
function dybatpho::curl_parse_response {
  local header_file
  dybatpho::expect_args header_file -- "$@"
  shift
  local body_file="${1:-}"
  (($# > 0)) && shift

  dybatpho::is file "${header_file}" || dybatpho::die "Header file not found: ${header_file}"

  DYBATPHO_HTTP_STATUS=""
  DYBATPHO_HTTP_HEADERS=()
  DYBATPHO_HTTP_BODY_FILE="${body_file}"

  local line key value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    if [[ "${line}" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]{3}) ]]; then
      DYBATPHO_HTTP_STATUS="${BASH_REMATCH[1]}"
      DYBATPHO_HTTP_HEADERS=() # A new status line starts a new block, e.g. after a redirect.
      continue
    fi
    [[ -z "${line}" ]] && continue
    if [[ "${line}" =~ ^([^:]+):[[:space:]]?(.*)$ ]]; then
      key="${BASH_REMATCH[1],,}"
      value="${BASH_REMATCH[2]}"
      DYBATPHO_HTTP_HEADERS["${key}"]="${value}"
    fi
  done < "${header_file}"

  [[ -n "${DYBATPHO_HTTP_STATUS}" ]]
}

#######################################
# @description Print a normalized response header captured by `dybatpho::curl_parse_response`.
# @arg $1 string Header name, matched case-insensitively
# @arg $2 string Optional default value
# @stdout Header value
# @exitcode 1 Header is missing and no default was supplied
#######################################
function dybatpho::curl_response_header {
  local name
  dybatpho::expect_args name -- "$@"
  local name_lower="${name,,}"
  if [[ -v "DYBATPHO_HTTP_HEADERS[${name_lower}]" ]]; then
    printf '%s\n' "${DYBATPHO_HTTP_HEADERS[${name_lower}]}"
  elif (($# > 1)); then
    printf '%s\n' "$2"
  else
    return 1
  fi
}

#######################################
# @description Perform a request via `dybatpho::curl_do` and parse its response into normalized status/header/body state.
# @example
#   dybatpho::curl_request https://example.com/api /tmp/resp.json
#   echo "${DYBATPHO_HTTP_STATUS}"
#   dybatpho::curl_response_header content-type
#
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_do
# @see dybatpho::curl_parse_response
# @set DYBATPHO_HTTP_STATUS number Status code of the last received response block
# @set DYBATPHO_HTTP_HEADERS map Lower-cased header name to value, from the last response block
# @set DYBATPHO_HTTP_BODY_FILE string Path holding the response body
# @tip Response headers aren't captured while `DRY_RUN` is enabled
#######################################
function dybatpho::curl_request {
  local url
  dybatpho::expect_args url -- "$@"
  shift
  local output="/dev/null"
  if (($# > 0)); then
    output="$1"
    shift
  fi

  local header_file
  dybatpho::create_temp header_file ".headers"
  local exit_code=0
  dybatpho::curl_do "${url}" "${output}" "$@" -D "${header_file}" || exit_code=$?

  if ! dybatpho::is true "${DRY_RUN}"; then
    dybatpho::curl_parse_response "${header_file}" "${output}"
  fi
  return "${exit_code}"
}

#######################################
# @description Perform a request via `dybatpho::curl_do` with connect/total timeouts scoped to this call only.
# @example
#   dybatpho::curl_timeout https://example.com /tmp/out 2 10
#   dybatpho::curl_timeout https://example.com /tmp/out "" 5 --header "X-Test: 1"
#
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $3 number Connect timeout in seconds for this request, empty keeps the global default
# @arg $4 number Total timeout in seconds for this request, empty keeps the global default
# @arg $@ string Other options/arguments for curl
# @see dybatpho::curl_do
# @tip Overrides apply only for the duration of this call; global `DYBATPHO_CURL_*` timeouts are unaffected
#######################################
function dybatpho::curl_timeout {
  local url
  dybatpho::expect_args url -- "$@"
  shift
  local output="/dev/null"
  if (($# > 0)); then
    output="$1"
    shift
  fi

  local connect_timeout="" total_timeout=""
  if (($# > 0)); then
    connect_timeout="$1"
    shift
  fi
  if (($# > 0)); then
    total_timeout="$1"
    shift
  fi
  [[ -z "${connect_timeout}" || "${connect_timeout}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "Connect timeout must be a non-negative integer"
  [[ -z "${total_timeout}" || "${total_timeout}" =~ ^[0-9]+$ ]] \
    || dybatpho::die "Total timeout must be a non-negative integer"

  (
    [[ -n "${connect_timeout}" ]] && DYBATPHO_CURL_CONNECT_TIMEOUT="${connect_timeout}"
    [[ -n "${total_timeout}" ]] && DYBATPHO_CURL_TIMEOUT="${total_timeout}"
    dybatpho::curl_do "${url}" "${output}" "$@"
  )
}

#######################################
# @description Report whether a circuit breaker key is currently open, half-open, or closed.
# @arg $1 string Circuit key
# @stdout `open`, `half-open`, or `closed`
#######################################
function dybatpho::circuit_state {
  local key
  dybatpho::expect_args key -- "$@"
  local opened_at="${DYBATPHO_CIRCUIT_OPENED_AT[${key}]:-0}"
  if ((opened_at == 0)); then
    echo closed
    return 0
  fi
  local now elapsed
  now=$(date +%s)
  elapsed=$((now - opened_at))
  if ((elapsed < DYBATPHO_CIRCUIT_COOLDOWN)); then
    echo open
  else
    echo half-open
  fi
}

#######################################
# @description Reset a circuit breaker key back to the closed state.
# @arg $1 string Circuit key
#######################################
function dybatpho::circuit_reset {
  local key
  dybatpho::expect_args key -- "$@"
  DYBATPHO_CIRCUIT_FAILURES["${key}"]=0
  DYBATPHO_CIRCUIT_OPENED_AT["${key}"]=0
}

#######################################
# @description Run a shell command guarded by a circuit breaker keyed by name.
# @example
#   dybatpho::circuit_breaker api.example.com "dybatpho::curl_do https://api.example.com/health"
#
# @arg $1 string Circuit key, typically a host or service name
# @arg $2 string Shell command string to run
# @env DYBATPHO_CIRCUIT_THRESHOLD number Consecutive failures before the circuit opens (default `5`)
# @env DYBATPHO_CIRCUIT_COOLDOWN number Seconds the circuit stays open before a trial request is allowed (default `30`)
# @exitcode 0 The command succeeded, or a trial request succeeded and closed the circuit
# @exitcode 9 The circuit is open; the command was not attempted
# @exitcode other The command's own exit code, while the circuit is closed or half-open
# @tip The command is executed with `eval`, so pass it as one shell command string
# @note Circuit breaker state is in-memory and process-local; it does not persist across script invocations
#######################################
function dybatpho::circuit_breaker {
  local key command
  dybatpho::expect_args key command -- "$@"
  shift 2

  local failures="${DYBATPHO_CIRCUIT_FAILURES[${key}]:-0}"
  local opened_at="${DYBATPHO_CIRCUIT_OPENED_AT[${key}]:-0}"
  local now
  now=$(date +%s)

  if ((opened_at > 0)); then
    local elapsed=$((now - opened_at))
    if ((elapsed < DYBATPHO_CIRCUIT_COOLDOWN)); then
      dybatpho::warn "Circuit '${key}' is open; skipping request (retry in $((DYBATPHO_CIRCUIT_COOLDOWN - elapsed))s)"
      return 9
    fi
    dybatpho::debug "Circuit '${key}' cooldown elapsed; allowing a trial request"
  fi

  local exit_code=0
  eval "${command}" || exit_code=$?

  if ((exit_code == 0)); then
    DYBATPHO_CIRCUIT_FAILURES["${key}"]=0
    DYBATPHO_CIRCUIT_OPENED_AT["${key}"]=0
  else
    failures=$((failures + 1))
    DYBATPHO_CIRCUIT_FAILURES["${key}"]="${failures}"
    if ((failures >= DYBATPHO_CIRCUIT_THRESHOLD)); then
      DYBATPHO_CIRCUIT_OPENED_AT["${key}"]="${now}"
      dybatpho::warn "Circuit '${key}' opened after ${failures} consecutive failures"
    fi
  fi
  return "${exit_code}"
}
