#!/usr/bin/env bash
# @file diff_ops.sh
# @brief Example showing a config change before it is applied
# @description Demonstrates dybatpho::diff_text, diff_summary, diff_json, diff_yaml, and diff_dir
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules diff json

dybatpho::register_common_handlers

# Colour is decided rather than detected, so the example reads the same when
# its output is piped into a file or a log.
export DYBATPHO_DIFF_COLOR=false

# @description Build the pair of files this example compares.
# @arg $1 string Name of the variable receiving the workspace path
# @set The named variable
function _make_workspace {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  local -n workspace_ref="${target}"

  dybatpho::create_temp workspace_ref "/" "diff-demo"

  cat > "${workspace_ref}/current.conf" << 'CONF'
listen 8080
workers 4
log_level info
CONF
  cat > "${workspace_ref}/proposed.conf" << 'CONF'
listen 8080
workers 8
log_level debug
keepalive 30
CONF

  printf '{"replicas":2,"image":"api:1.4","labels":{"app":"api"},"debug":null}\n' \
    > "${workspace_ref}/current.json"
  printf '{"labels":{"app":"api","tier":"web"},"image":"api:1.5","replicas":2}\n' \
    > "${workspace_ref}/proposed.json"

  cat > "${workspace_ref}/current.yaml" << 'YAML'
replicas: 2
image: api:1.4
labels:
  app: api
YAML
  cat > "${workspace_ref}/proposed.yaml" << 'YAML'
labels:
  app: api
  tier: web
image: 'api:1.5'
replicas: 2
YAML
}

# @description Show what a config change does, line by line.
# @arg $1 string Workspace path
function _demo_text {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "TEXT"
  # The exit code is `diff`'s own, so the call reads as a question: a script
  # that only acts when something changed can gate on it.
  if dybatpho::diff_text "${workspace}/current.conf" "${workspace}/proposed.conf" \
    current proposed; then
    dybatpho::info "Nothing would change"
  fi
}

# @description Reduce the same change to one line, for a log or a PR comment.
# @arg $1 string Workspace path
function _demo_summary {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "SUMMARY"
  local summary
  summary="$(dybatpho::diff_summary "${workspace}/current.conf" "${workspace}/proposed.conf")" \
    || true
  dybatpho::info "Config change: ${summary}"
}

# @description Compare two JSON states by key rather than by line.
# @arg $1 string Workspace path
function _demo_json {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "JSON"
  # The proposed document lists its keys in another order and drops a key
  # whose value was null. A line diff would call all of that a rewrite.
  dybatpho::diff_json "${workspace}/current.json" "${workspace}/proposed.json" || true
}

# @description Compare two YAML documents, where quoting style differs.
# @arg $1 string Workspace path
function _demo_yaml {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "YAML"
  # `api:1.5` is quoted on one side and not the other; that is not a change.
  dybatpho::diff_yaml "${workspace}/current.yaml" "${workspace}/proposed.yaml" || true
}

# @description Compare two release trees entry by entry.
# @arg $1 string Workspace path
function _demo_dir {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "DIRECTORY"
  local old="${workspace}/release-1.2" new="${workspace}/release-1.3"
  mkdir -p "${old}/etc" "${new}/etc" "${new}/bin"
  cp "${workspace}/current.conf" "${old}/etc/app.conf"
  cp "${workspace}/proposed.conf" "${new}/etc/app.conf"
  printf 'unchanged\n' > "${old}/README"
  printf 'unchanged\n' > "${new}/README"
  printf 'legacy\n' > "${old}/legacy.sh"
  printf '#!/bin/sh\n' > "${new}/bin/tool"

  # README holds the same content on both sides, so it is not reported even
  # though the two files were written at different times.
  dybatpho::diff_dir "${old}" "${new}" || true
  local summary
  summary="$(dybatpho::diff_dir --summary "${old}" "${new}")" || true
  dybatpho::info "Release change: ${summary}"
}

# @description Show that comparing something with itself reports nothing.
# @arg $1 string Workspace path
function _demo_unchanged {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "UNCHANGED"
  if dybatpho::diff_json "${workspace}/current.json" "${workspace}/current.json"; then
    dybatpho::success "The two documents hold the same values"
  fi
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  local workspace
  _make_workspace workspace
  _demo_text "${workspace}"
  _demo_summary "${workspace}"
  _demo_json "${workspace}"
  _demo_yaml "${workspace}"
  _demo_dir "${workspace}"
  _demo_unchanged "${workspace}"
  dybatpho::success "Diff operations demo complete"
}

_main "$@"
