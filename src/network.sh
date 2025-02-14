#!/usr/bin/env bash
# @file network.sh
# @brief Utilities for network
# @description
#   This module contains functions to work with network connection.
#
# **DYBATPHO_CURL_MAX_RETRIES** (number): Max number of retries when using `curl` failed
#
# **DYBATPHO_CURL_DISABLED_RETRY** (string): Flag to disable retrying after using `curl` failed
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init before other scripts from dybatpho.}"
DYBATPHO_CURL_MAX_RETRIES=${DYBATPHO_CURL_MAX_RETRIES:-5}
DYBATPHO_CURL_DISABLED_RETRY=${DYBATPHO_CURL_DISABLED_RETRY:-"false"}

#######################################
# @description Get description of HTTP status code
# @arg $1 string Status code
# @stdout Description of status code
#######################################
__get_http_code() {
  local code
  dybatpho::expect_args code -- "$@"

  case "$code" in
    '100') echo '100 (continue)' ;;
    '101') echo '101 (switching protocols)' ;;
    '200') echo 'done' ;;
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
    '403') echo '403 (forbidden)' ;;
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
  esac
}

#######################################
# @description Transfering data with URL by curl
# @example
#   dybatpho::curl_do <url> --output /tmp/1
#
# @arg $1 string URL
# @arg $2 string Location of curl output, default is `/dev/null`
# @arg $3 string Other options/arguments for curl
# @exitcode 0 Transfered data
# @exitcode 1 Unknown error
# @exitcode 3 First digit of HTTP error code 3xx
# @exitcode 4 First digit of HTTP error code 4xx
# @exitcode 5 First digit of HTTP error code 5xx
# @exitcode 127 Curl isn't installed
#######################################
function dybatpho::curl_do {
  local url
  dybatpho::expect_args url -- "$@"
  shift
  local output="/dev/null"
  if [ $# -ne 0 ]; then
    output="${1}"
    shift
  fi

  local retries code
  retries="$DYBATPHO_CURL_MAX_RETRIES"
  code=
  while ((retries)); do
    code=$(
      /usr/bin/curl -fsSL "$url" \
        -w '%{http_code}' \
        -o "$output" \
        "$@" \
        2> /dev/null
    ) || true

    local code_description
    code_description=$(__get_http_code "$code")
    dybatpho::debug "Received HTTP status: $code_description"

    if [[ "$code" =~ '2'.* ]]; then
      break
    fi
    if [[ "$code" =~ '4'.* ]] && dybatpho::is true "$DYBATPHO_CURL_DISABLED_RETRY"; then
      break
    fi

    # Delay for next retry
    retries=$((retries - 1))
    if ((retries)); then
      local retry delay
      retry=$((DYBATPHO_CURL_MAX_RETRIES - retries))
      delay=$((2 ** retry))

      dybatpho::progress "Retrying in ${delay} seconds (${retry}/${max_retries})..."
      sleep "$delay" || true
    fi
  done

  # Return exit code based on HTTP status code
  case "$code" in
    '2'*) return 0 ;;
    '3'*) return 3 ;;
    '4'*) return 4 ;;
    '5'*) return 5 ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Download file
# @arg $1 URL
# @arg $2 Destination of file to download
# @see dybatpho::curl_do
# @exitcode 2 Can't create folder of destination file
#######################################
function dybatpho::curl_download {
  local url dst_file
  dybatpho::expect_args url dst_file -- "$@"
  dybatpho::progress "Downloading ${url}"

  # Create destination folder
  local dst_dir
  dst_dir=$(dirname "$dst_file") || return 2
  mkdir -p "$dst_dir" || return 2

  dybatpho::curl_do "$url" "$dst_file" || return
}
