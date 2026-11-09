#!/usr/bin/env bash
# @file service_ops.sh
# @brief Example showing how to inspect and preview service management
# @description
#   Reports the machine's service manager and which scopes it can act in, then
#   previews -- without running -- what enabling and installing a service would
#   do. Nothing on the machine is changed: the install runs under
#   `DYBATPHO_DRY_RUN`, from a unit file in a temporary directory.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules service

dybatpho::register_common_handlers

# --- manager ------------------------------------------------------------------

# @description Run the `MANAGER` section of this example.
# @noargs
function _demo_manager {
  dybatpho::header "MANAGER"
  local manager=""
  manager="$(dybatpho::service_manager)" || true
  dybatpho::info "Service manager: ${manager:-none}"
  local scope
  for scope in system user; do
    local -a flag=()
    [[ "${scope}" != user ]] || flag=(--user)
    if dybatpho::service_manager_available ${flag[@]+"${flag[@]}"}; then
      dybatpho::info "It can act on the ${scope} scope"
    else
      dybatpho::warn "It cannot act on the ${scope} scope here"
    fi
  done
}

# --- preview ------------------------------------------------------------------

# @description Run the `PREVIEW` section of this example: the commands each
#   manager would run, printed and not run.
# @noargs
function _demo_preview {
  dybatpho::header "PREVIEW"
  local manager
  for manager in systemd openrc launchd; do
    dybatpho::info "${manager}: enabling sshd would run"
    DYBATPHO_SERVICE_MANAGER="${manager}" dybatpho::service_command enable sshd
  done
}

# --- install ------------------------------------------------------------------

# @description Run the `INSTALL` section of this example, on systemd or launchd:
#   a user unit installed under dry-run, so the commands are printed and
#   nothing is copied.
# @noargs
function _demo_install {
  dybatpho::header "INSTALL (dry run)"
  local manager=""
  manager="$(dybatpho::service_manager)" || true
  if [[ "${manager}" != systemd && "${manager}" != launchd ]]; then
    dybatpho::warn "${manager:-No manager} takes no unit file; skipping"
    return 0
  fi
  local work
  dybatpho::create_temp_dir work "service-example"
  printf '[Unit]\nDescription=Example\n\n[Service]\nExecStart=/bin/true\n' > "${work}/example.service"
  DYBATPHO_DRY_RUN=true dybatpho::service_install "${work}/example.service" --user
}

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_manager
  _demo_preview
  _demo_install
  dybatpho::success "Service demo complete; nothing was changed"
}

_main "$@"
