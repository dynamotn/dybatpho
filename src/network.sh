#!/usr/bin/env bash
# @file network.sh
# @brief Utilities for network
# @description
#   This module contains functions to work with network connection.
#
# **DYBATPHO_CURL_MAX_RETRIES** (number): Max number of retries when using `curl` failed
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

DYBATPHO_CURL_MAX_RETRIES=${DYBATPHO_CURL_MAX_RETRIES:-5}

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
# @exitcode 0 Transferred data
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

  if dybatpho::is empty "${url}"; then
    return 1
  fi

  local output="/dev/null"
  if [ $# -ne 0 ]; then
    output="$1"
    shift
  fi

  local code
  # shellcheck disable=SC2329
  __request() {
    dybatpho::require curl
    # kcov(disabled)
    code=$(
      if ! command curl -fsSL "${url}" \
        -w '%{http_code}' \
        -o "${output}" \
        "$@"; then
        dybatpho::fatal "Error when access ${url}"
        return 1
      fi
    )
    # kcov(enabled)

    local code_description
    code_description=$(__get_http_code "${code}")
    dybatpho::debug "Received HTTP status: ${code_description}"

    if [[ "${code}" =~ '2'.* ]] || [[ "${code}" =~ '4'.* ]]; then
      return 0
    else
      return 1
    fi
  }

  dybatpho::retry "${DYBATPHO_CURL_MAX_RETRIES}" "__request ${*}" "curl ${url}"

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
