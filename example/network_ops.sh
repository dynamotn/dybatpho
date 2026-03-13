#!/usr/bin/env bash
# @file network_ops.sh
# @brief Example showing network utilities
# @description Demonstrates dybatpho::curl_do, curl_download, curl_json, and curl_head
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh"

dybatpho::register_common_handlers

function _demo_head_request {
  dybatpho::header "HEAD REQUEST"
  local headers_file
  dybatpho::create_temp headers_file ".txt"
  if dybatpho::curl_head "https://example.com" "${headers_file}"; then
    dybatpho::info "Saved response headers to ${headers_file}"
    dybatpho::show_file "${headers_file}"
  else
    dybatpho::warn "HEAD request failed"
  fi
}

function _demo_json_request {
  dybatpho::header "JSON REQUEST"
  local json_file
  dybatpho::create_temp json_file ".json"
  if dybatpho::curl_json "https://api.github.com/repos/dynamotn/dybatpho" "${json_file}"; then
    dybatpho::info "Fetched JSON response to ${json_file}"
    dybatpho::show_file "${json_file}"
  else
    dybatpho::warn "JSON request failed"
  fi
}

function _main {
  _demo_head_request
  _demo_json_request
  dybatpho::success "Network operations demo complete"
}

_main "$@"
