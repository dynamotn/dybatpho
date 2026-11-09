#!/usr/bin/env bash
# @file sign_ops.sh
# @brief Example showing how to sign files and check signatures
# @description
#   Signs a file with a throwaway SSH key, checks it against that key only, and
#   shows a changed file and another namespace being refused. The minisign and
#   gpg sections run where those tools are installed. Keys, files and the gpg
#   home all live in a temporary directory removed on exit; the user's own keys
#   and keyring are never touched.
SCRIPTDIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=init.sh
. "${SCRIPTDIR}/../init.sh" --modules sign

dybatpho::register_common_handlers

WORK=""
dybatpho::create_temp_dir WORK "sign-example"
DOC="${WORK}/release-notes.txt"
# The backends that can sign here, one per line between newlines, so a section
# can test for its own with a pattern.
SIGNERS=$'\n'"$(dybatpho::sign_backends sign)"$'\n'
printf 'Version 1.2.0: faster tests.\n' > "${DOC}"

# --- backends ---------------------------------------------------------------

# @description Run the `BACKENDS` section of this example.
# @noargs
function _demo_backends {
  dybatpho::header "BACKENDS"
  local backends
  backends="$(dybatpho::sign_backends sign | tr '\n' ' ')"
  dybatpho::info "Can sign here with: ${backends:-nothing}"
}

# --- ssh ----------------------------------------------------------------------

# @description Run the `SSH` section of this example: sign, verify, and see a
#   changed file and another namespace refused.
# @noargs
function _demo_ssh {
  dybatpho::header "SSH"
  if [[ "${SIGNERS}" != *$'\n'ssh$'\n'* ]]; then
    dybatpho::warn "ssh-keygen with -Y isn't installed; skipping"
    return 0
  fi
  ssh-keygen -q -t ed25519 -N '' -C "example" -f "${WORK}/id_ed25519"
  local trusted signature
  trusted="$(dybatpho::sign_public_key ssh "${WORK}/id_ed25519")"
  signature="$(DYBATPHO_SIGN_NAMESPACE=release dybatpho::sign_file ssh "${WORK}/id_ed25519" "${DOC}")"
  dybatpho::info "Signed: ${signature##*/}"

  if DYBATPHO_SIGN_NAMESPACE=release dybatpho::verify_file "${DOC}" "${signature}" "${trusted}"; then
    dybatpho::success "The signature checks out against the pinned key"
  fi
  if ! DYBATPHO_SIGN_NAMESPACE=deploy dybatpho::verify_file "${DOC}" "${signature}" "${trusted}"; then
    dybatpho::warn "Refused in another namespace (expected)"
  fi
  printf 'Version 6.6.6: tampered.\n' > "${WORK}/tampered.txt"
  if ! DYBATPHO_SIGN_NAMESPACE=release dybatpho::verify_file "${WORK}/tampered.txt" "${signature}" "${trusted}"; then
    dybatpho::warn "Refused for a changed file (expected)"
  fi
}

# --- minisign -------------------------------------------------------------------

# @description Run the `MINISIGN` section of this example, where minisign is installed.
# @noargs
function _demo_minisign {
  dybatpho::header "MINISIGN"
  if [[ "${SIGNERS}" != *$'\n'minisign$'\n'* ]]; then
    dybatpho::warn "minisign isn't installed; skipping"
    return 0
  fi
  minisign -G -W -p "${WORK}/minisign.pub" -s "${WORK}/minisign.key" > /dev/null
  local signature
  signature="$(dybatpho::sign_file minisign "${WORK}/minisign.key" "${DOC}")"
  if dybatpho::verify_file "${DOC}" "${signature}" "${WORK}/minisign.pub"; then
    dybatpho::success "The minisign signature checks out against its .pub file"
  fi
}

# --- gpg ------------------------------------------------------------------------

# @description Run the `GPG` section of this example, in a GnuPG home of its
#   own, where gpg is installed and can start its agent.
# @noargs
function _demo_gpg {
  dybatpho::header "GPG"
  if [[ "${SIGNERS}" != *$'\n'gpg$'\n'* ]]; then
    dybatpho::warn "gpg isn't installed; skipping"
    return 0
  fi
  export GNUPGHOME="${WORK}/gnupg"
  mkdir -m 700 "${GNUPGHOME}"
  if ! gpg --batch --passphrase '' --quick-gen-key "Example <example@example.test>" ed25519 sign never \
    &> /dev/null; then
    dybatpho::warn "gpg cannot generate a key here; skipping"
    return 0
  fi
  dybatpho::sign_public_key gpg example@example.test > "${WORK}/example.asc"
  local signature
  signature="$(dybatpho::sign_file gpg example@example.test "${DOC}")"
  if dybatpho::verify_file "${DOC}" "${signature}" "${WORK}/example.asc"; then
    dybatpho::success "The gpg signature checks out against the exported key"
  fi
  gpgconf --kill all &> /dev/null || true
}

# --- main -----------------------------------------------------------------

# @description Run every section of this example, in order.
# @noargs
function _main {
  _demo_backends
  _demo_ssh
  _demo_minisign
  _demo_gpg
  dybatpho::success "Signing demo complete"
}

_main "$@"
