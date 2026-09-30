#!/usr/bin/env bash
# @file backup_ops.sh
# @brief Example snapshotting a config directory and applying a retention policy
# @description Demonstrates dybatpho::backup_create, backup_list, backup_latest,
#   backup_verify, backup_restore, and backup_prune
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules backup

dybatpho::register_common_handlers

# @description Build the working directories this example uses.
# @arg $1 string Name of the variable receiving the workspace path
# @set The named variable
function _make_workspace {
  local target
  dybatpho::expect_args target -- "$@"
  dybatpho::expect_ref "${target}"
  local -n workspace_ref="${target}"

  dybatpho::create_temp workspace_ref "/" "backup-demo"
  dybatpho::ensure_dir "${workspace_ref}/config" > /dev/null
  dybatpho::ensure_dir "${workspace_ref}/backups" > /dev/null
  printf 'listen 8080\n' > "${workspace_ref}/config/server.conf"
  printf 'level = info\n' > "${workspace_ref}/config/logging.conf"
}

# @description Take a snapshot before a risky change, and show what it wrote.
# @arg $1 string Workspace path
# @stdout The archive path, for the sections that follow
function _demo_create {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "CREATE"
  local archive
  archive="$(dybatpho::backup_create "${workspace}/config" "${workspace}/backups" config)"
  dybatpho::info "Wrote $(dybatpho::path_basename "${archive}")"
  # The sidecar is what a later restore checks the archive against.
  dybatpho::info "Beside it: $(dybatpho::path_basename "${archive}").sha256"
  printf '%s\n' "${archive}"
}

# @description Plant older snapshots, so the retention policy has something to
#   work on without the example having to wait between runs.
# @arg $1 string Workspace path
function _plant_history {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  local stamp
  for stamp in 20260101T000000Z 20260201T000000Z 20260301T000000Z; do
    printf 'an older snapshot\n' > "${workspace}/backups/config-${stamp}.tar.gz"
    printf 'deadbeef  config-%s.tar.gz\n' "${stamp}" \
      > "${workspace}/backups/config-${stamp}.tar.gz.sha256"
  done
}

# @description List what is there, newest first, and name the latest.
# @arg $1 string Workspace path
function _demo_list {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "LIST"
  local path
  while read -r path; do
    printf '%s\n' "$(dybatpho::path_basename "${path}")"
  done < <(dybatpho::backup_list "${workspace}/backups" config)

  dybatpho::info "Latest: $(dybatpho::path_basename "$(dybatpho::backup_latest "${workspace}/backups" config)")"
}

# @description Verify a good archive, then a damaged one.
# @arg $1 string Archive path
function _demo_verify {
  local archive
  dybatpho::expect_args archive -- "$@"

  dybatpho::header "VERIFY"
  if dybatpho::backup_verify "${archive}"; then
    dybatpho::success "The archive matches its sidecar"
  fi

  # A truncated or corrupted backup is what the sidecar is there to catch.
  local damaged="${archive}.damaged.tar.gz"
  cp "${archive}" "${damaged}"
  cp "${archive}.sha256" "${damaged}.sha256"
  printf 'corruption' >> "${damaged}"
  if ! dybatpho::backup_verify "${damaged}" 2> /dev/null; then
    dybatpho::warn "The damaged copy was rejected, as it should be"
  fi
  rm -f "${damaged}" "${damaged}.sha256"
}

# @description Restore the snapshot into a fresh directory.
# @arg $1 string Workspace path
# @arg $2 string Archive path
function _demo_restore {
  local workspace archive
  dybatpho::expect_args workspace archive -- "$@"

  dybatpho::header "RESTORE"
  dybatpho::backup_restore --force "${archive}" "${workspace}/restored"
  local file
  while read -r file; do
    printf '%s\n' "${file#"${workspace}/restored/"}"
  done < <(find "${workspace}/restored" -type f | sort)
}

# @description Show the retention policy, first as a dry run, then for real.
# @arg $1 string Workspace path
function _demo_prune {
  local workspace
  dybatpho::expect_args workspace -- "$@"

  dybatpho::header "PRUNE"
  # Nothing is deleted while DRY_RUN is set, which is how a retention policy
  # gets reviewed before it runs unattended.
  DRY_RUN=true dybatpho::backup_prune --keep-count 2 --name config --force "${workspace}/backups"

  dybatpho::backup_prune --keep-count 2 --name config --force "${workspace}/backups"
  dybatpho::info "Kept:"
  local path
  while read -r path; do
    printf '%s\n' "$(dybatpho::path_basename "${path}")"
  done < <(dybatpho::backup_list "${workspace}/backups" config)
}

# @description Run every section of this example, in order.
# @noargs
function _main {
  local workspace archive
  _make_workspace workspace
  archive="$(_demo_create "${workspace}" | tail -n 1)"
  _plant_history "${workspace}"
  _demo_list "${workspace}"
  _demo_verify "${archive}"
  _demo_restore "${workspace}" "${archive}"
  _demo_prune "${workspace}"
  dybatpho::success "Backup operations demo complete"
}

_main "$@"
