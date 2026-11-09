# shellcheck shell=bash
# @file sign.sh
# @brief Utilities for signing files and checking signatures
# @namespace dybatpho
# @description
#   This module signs a file and checks a signature with `ssh-keygen -Y`,
#   `minisign` or `gpg`, behind one pair of calls. A signature is checked
#   against the keys the caller names and nothing else: never the user's
#   `allowed_signers`, keyring or `GNUPGHOME`.
#
#   Only an SSH signature is bound to a purpose, its namespace
#   (`DYBATPHO_SIGN_NAMESPACE`); minisign and gpg ignore it, so that a
#   signature made by the tool itself, such as a release's `.minisig`, still
#   verifies.
#
#   A tool asks for a passphrase only when stdin and stderr are both
#   terminals. Run without one, a key that needs a passphrase no agent holds
#   makes the call fail at once instead of waiting.
# @usage
#   ### Sign a file and check it against a pinned key
#
#   ```bash
#   DYBATPHO_SIGN_NAMESPACE="registry" dybatpho::sign_file ssh ~/.ssh/id_ed25519 accounts.yaml
#   DYBATPHO_SIGN_NAMESPACE="registry" \
#     dybatpho::verify_file accounts.yaml accounts.yaml.sig "${pinned_key}" \
#     || dybatpho::die "accounts.yaml is not signed by a trusted key"
#   ```
#
#   ### Check a release's minisign signature
#
#   ```bash
#   dybatpho::verify_file tool.tar.gz tool.tar.gz.minisig "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
#   ```
# @see
#   - `example/sign_ops.sh`
: "${DYBATPHO_DIR:?DYBATPHO_DIR must be set. Please source dybatpho/init.sh before other scripts from dybatpho.}"

# @env DYBATPHO_SIGN_NAMESPACE string [default: file] Purpose an SSH signature is made and checked for
DYBATPHO_SIGN_NAMESPACE="${DYBATPHO_SIGN_NAMESPACE:-file}"
# @env DYBATPHO_SIGN_TIMEOUT number [default: 10] Seconds a signing tool may run before the call fails
DYBATPHO_SIGN_TIMEOUT="${DYBATPHO_SIGN_TIMEOUT:-10}"

# Backends, in the order every listing uses.
__DYBATPHO_SIGN_BACKENDS=(ssh minisign gpg)

#######################################
# @description Tell whether `ssh-keygen` can sign, which needs `-Y` from
#   OpenSSH 8.1. The tool is asked rather than its version parsed: one with
#   `-Y` complains about the missing namespace, an older one about the option.
# @noargs
# @exitcode 0 `ssh-keygen` is installed and supports `-Y`
# @exitcode 1 Otherwise
# @internal
#######################################
function __dybatpho_sign_has_y {
  command -v ssh-keygen > /dev/null || return 1
  local answer
  answer="$(ssh-keygen -Y sign < /dev/null 2>&1)" || true
  [[ "${answer}" == *namespace* ]]
}

#######################################
# @description Name the tool a backend needs for one direction, and the
#   package that provides it.
# @arg $1 string Backend
# @arg $2 string `sign` or `verify`
# @stdout The tool, a tab, then the package
# @exitcode 1 The backend is unknown
# @internal
#######################################
function __dybatpho_sign_tool {
  case "$1:$2" in
    ssh:*) printf 'ssh-keygen\topenssh\n' ;;
    minisign:*) printf 'minisign\tminisign\n' ;;
    gpg:sign) printf 'gpg\tgnupg\n' ;;
    gpg:verify) printf 'gpgv\tgnupg\n' ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Tell whether a backend can sign or verify on this machine.
# @arg $1 string Backend
# @arg $2 string `sign` or `verify`
# @exitcode 0 Its tool is installed, and for ssh supports `-Y`
# @exitcode 1 Otherwise
# @internal
#######################################
function __dybatpho_sign_available {
  local tool
  tool="$(__dybatpho_sign_tool "$1" "$2")" || return 1
  if [[ "$1" == ssh ]]; then
    __dybatpho_sign_has_y
  else
    command -v "${tool%%$'\t'*}" > /dev/null
  fi
}

#######################################
# @description Stop the script unless a backend is known and its tool is
#   installed for the direction asked.
# @arg $1 string Backend
# @arg $2 string `sign` or `verify`
# @exitcode 0 The backend can be used
# @exitcode 1 Stop script when the backend is unknown
# @exitcode 127 Stop script when its tool is missing, or `ssh-keygen` has no `-Y`
# @internal
#######################################
function __dybatpho_sign_require {
  local backend="$1" direction="$2" tool package
  tool="$(__dybatpho_sign_tool "${backend}" "${direction}")" \
    || dybatpho::die "${FUNCNAME[1]}: Unknown backend: ${backend}"
  package="${tool#*$'\t'}"
  tool="${tool%%$'\t'*}"
  command -v "${tool}" > /dev/null \
    || dybatpho::die "${FUNCNAME[1]}: ${tool} isn't installed; install ${package}" 127
  if [[ "${backend}" == ssh ]] && ! __dybatpho_sign_has_y; then
    dybatpho::die "${FUNCNAME[1]}: ssh-keygen cannot sign; install OpenSSH 8.1 or later" 127
  fi
}

#######################################
# @description Print the backends that can sign, or verify, on this machine.
# @example
#   dybatpho::sign_backends sign
#
# @arg $1 string [default: verify] `sign` or `verify`
# @stdout One backend per line, in the order `ssh`, `minisign`, `gpg`
# @tip `gpg` verifies with `gpgv` alone but signs with `gpg`, so it can be
#   listed for one direction and not the other
#######################################
# dyshellint disable=BSG050 # its one argument is optional, which expect_args cannot express
function dybatpho::sign_backends {
  local direction="${1:-verify}" backend
  [[ "${direction}" == sign || "${direction}" == verify ]] \
    || dybatpho::die "${FUNCNAME[0]}: Expected sign or verify, got: ${direction}"
  for backend in "${__DYBATPHO_SIGN_BACKENDS[@]}"; do
    if __dybatpho_sign_available "${backend}" "${direction}"; then
      printf '%s\n' "${backend}"
    fi
  done
}

#######################################
# @description Stop the script unless `DYBATPHO_SIGN_NAMESPACE` can be written
#   into an `allowed_signers` line: a quote or a space would end the
#   `namespaces="..."` option early.
# @noargs
# @exitcode 0 The namespace is usable
# @exitcode 1 Stop script when it is empty or holds anything else
# @internal
#######################################
function __dybatpho_sign_check_namespace {
  [[ "${DYBATPHO_SIGN_NAMESPACE}" =~ ^[A-Za-z0-9@._+-]+$ ]] || dybatpho::die \
    "${FUNCNAME[1]}: Invalid namespace '${DYBATPHO_SIGN_NAMESPACE}': use letters, digits and @._+-"
}

#######################################
# @description Run a signing tool under the prompt rule. At a terminal -- stdin
#   and stderr both -- it runs as it is and may ask for a passphrase. Anywhere
#   else it runs in a session of its own, so it has no terminal to ask on, with
#   `SSH_ASKPASS_REQUIRE=never` and a limit of `DYBATPHO_SIGN_TIMEOUT` seconds.
#   The tools read a passphrase from `/dev/tty`, so closing stdin would not do.
# @arg $@ string Tool and its arguments
# @exitcode 124 The tool ran out of time
# @exitcode other Exit code of the tool
# @internal
#######################################
function __dybatpho_sign_run {
  if dybatpho::is_tty stdin && dybatpho::is_tty stderr; then
    "$@"
    return
  fi
  local -a __dybatpho_sign_detach=()
  if command -v setsid > /dev/null; then
    __dybatpho_sign_detach=(setsid -w)
  elif command -v perl > /dev/null; then
    # macOS has no `setsid`; Perl's POSIX module does the same call.
    # shellcheck disable=SC2016 # Perl code, expanded by Perl
    __dybatpho_sign_detach=(perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec $ARGV[0]: $!\n"')
  fi
  SSH_ASKPASS_REQUIRE=never dybatpho::run_with_timeout "${DYBATPHO_SIGN_TIMEOUT}" \
    ${__dybatpho_sign_detach[@]+"${__dybatpho_sign_detach[@]}"} "$@"
}

#######################################
# @description Report the last line a tool wrote to its captured stderr.
# @arg $1 string What failed
# @arg $2 path File holding the tool's stderr
# @stderr The failure and the tool's last line
# @internal
#######################################
function __dybatpho_sign_report {
  local line="" last=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] || last="${line}"
  done < "$2"
  dybatpho::error "$1${last:+: ${last}}"
}

#######################################
# @description Tell which backend made a signature, from its first non-blank line.
# @arg $1 string Name of the variable receiving the backend
# @arg $2 path Signature file
# @set The named variable
# @exitcode 1 Stop script when the format is not one any backend writes
# @internal
#######################################
function __dybatpho_sign_detect_into {
  local -n __dybatpho_sign_detected="$1"
  local line=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] || break
  done < "$2"
  case "${line}" in
    "-----BEGIN SSH SIGNATURE-----") __dybatpho_sign_detected=ssh ;;
    "untrusted comment:"*) __dybatpho_sign_detected=minisign ;;
    "-----BEGIN PGP SIGNATURE-----") __dybatpho_sign_detected=gpg ;;
    *) dybatpho::die "${FUNCNAME[1]}: Unknown signature format: $2" ;;
  esac
}

#######################################
# @description Tell which backend a single key line belongs to.
# @arg $1 string Key line, without its comment-only and blank lines
# @stdout `ssh <type> <base64>`, `minisign <key>`, or nothing
# @internal
#######################################
function __dybatpho_sign_classify {
  local ssh_types='ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521'
  ssh_types+='|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com'
  if [[ "$1" =~ ^(${ssh_types})[[:space:]]+([A-Za-z0-9+/]+=*)([[:space:]]|$) ]]; then
    printf 'ssh %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$1" =~ ^RW[A-Za-z0-9+/]{54}$ ]]; then
    printf 'minisign %s\n' "$1"
  fi
}

#######################################
# @description Expand the caller's trusted keys into the keys of one backend.
#   A key is a string, or a file holding one key per line (blank lines and
#   `#` comments skipped, a minisign `.pub` file's comment line too); a gpg
#   key is a file holding an exported public key. Keys of other backends are
#   dropped, so one list can hold every kind.
# @arg $1 string Name of the array receiving the keys: `<type> <base64>` for
#   ssh, the base64 key for minisign, a file path for gpg
# @arg $2 string Backend the signature belongs to
# @arg $@ string Trusted keys
# @set The named array
# @exitcode 1 Stop script on a key file that does not exist, or a string no
#   backend recognises
# @internal
#######################################
function __dybatpho_sign_trusted_into {
  local -n __dybatpho_sign_keys="$1"
  local backend="$2" trusted line kind
  shift 2
  __dybatpho_sign_keys=()
  for trusted in "$@"; do
    kind="$(__dybatpho_sign_classify "${trusted}")"
    if [[ -z "${kind}" && ! -e "${trusted}" ]]; then
      [[ "${trusted}" != */* ]] || dybatpho::die "${FUNCNAME[1]}: Trusted key not found: ${trusted}"
      dybatpho::die "${FUNCNAME[1]}: Not a key any backend knows: ${trusted}"
    fi
    if [[ -n "${kind}" ]]; then
      [[ "${kind%% *}" != "${backend}" ]] || __dybatpho_sign_keys+=("${kind#* }")
      continue
    fi
    [[ -f "${trusted}" && -r "${trusted}" ]] || dybatpho::die "${FUNCNAME[1]}: Cannot read ${trusted}"
    if __dybatpho_sign_is_gpg_key "${trusted}"; then
      [[ "${backend}" != gpg ]] || __dybatpho_sign_keys+=("${trusted}")
      continue
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      [[ -n "${line//[[:space:]]/}" && "${line}" != \#* && "${line}" != "untrusted comment:"* ]] || continue
      kind="$(__dybatpho_sign_classify "${line}")"
      [[ -n "${kind}" ]] || dybatpho::die "${FUNCNAME[1]}: Not a key any backend knows, in ${trusted}: ${line}"
      [[ "${kind%% *}" != "${backend}" ]] || __dybatpho_sign_keys+=("${kind#* }")
    done < "${trusted}"
  done
}

#######################################
# @description Tell whether a file holds an exported OpenPGP public key, armored
#   or binary. A binary export starts with a public-key packet tag.
# @arg $1 path File
# @exitcode 0 It does
# @exitcode 1 It does not
# @internal
#######################################
function __dybatpho_sign_is_gpg_key {
  local first=""
  IFS= read -r first < "$1" || true
  [[ "${first%$'\r'}" == "-----BEGIN PGP PUBLIC KEY BLOCK-----" ]] && return 0
  local byte
  byte="$(od -An -tx1 -N1 -- "$1" 2> /dev/null)"
  byte="${byte//[[:space:]]/}"
  # Old-format tag 6 (0x98, 0x99) and new-format tag 6 (0xc6).
  [[ "${byte}" == 98 || "${byte}" == 99 || "${byte}" == c6 ]]
}

#######################################
# @description Default signature path for a backend.
# @arg $1 string Backend
# @stdout `.sig`, `.minisig` or `.asc`
# @internal
#######################################
function __dybatpho_sign_extension {
  case "$1" in
    ssh) printf '.sig' ;;
    minisign) printf '.minisig' ;;
    gpg) printf '.asc' ;;
    *) return 1 ;;
  esac
}

#######################################
# @description Sign with `ssh-keygen -Y`. The data goes in on stdin and the
#   signature comes out on stdout, so `ssh-keygen` never finds a `.sig` to ask
#   about overwriting.
# @arg $1 string Private key, or public key whose private half the agent holds
# @arg $2 path File to sign
# @arg $3 path Signature to write
# @arg $4 path Working directory
# @internal
#######################################
function __dybatpho_sign_ssh_sign {
  __dybatpho_sign_run ssh-keygen -Y sign -n "${DYBATPHO_SIGN_NAMESPACE}" -f "$1" \
    < "$2" > "$3" 2> "$4/err" || {
    local status=$?
    __dybatpho_sign_report "ssh-keygen could not sign $2" "$4/err"
    return "${status}"
  }
}

#######################################
# @description Verify with `ssh-keygen -Y`, against an `allowed_signers` file
#   naming only the trusted keys, each pinned to the namespace.
# @arg $1 path File
# @arg $2 path Signature
# @arg $3 path Working directory
# @arg $@ string Trusted keys, `<type> <base64>`
# @internal
#######################################
function __dybatpho_sign_ssh_verify {
  local file="$1" signature="$2" work="$3" key
  shift 3
  for key in "$@"; do
    printf 'dybatpho namespaces="%s" %s\n' "${DYBATPHO_SIGN_NAMESPACE}" "${key}"
  done > "${work}/allowed_signers"
  __dybatpho_sign_run ssh-keygen -Y verify -n "${DYBATPHO_SIGN_NAMESPACE}" -I dybatpho \
    -f "${work}/allowed_signers" -s "${signature}" < "${file}" > /dev/null 2> "${work}/err"
}

#######################################
# @description Sign with `minisign`. Away from a terminal its stdin is
#   `/dev/null`, so a password it might read from there is empty and an
#   encrypted key fails instead of taking whatever the caller piped in.
# @arg $1 path Secret key
# @arg $2 path File to sign
# @arg $3 path Signature to write
# @arg $4 path Working directory
# @internal
#######################################
function __dybatpho_sign_minisign_sign {
  local input=/dev/stdin
  dybatpho::is_tty stdin && dybatpho::is_tty stderr || input=/dev/null
  __dybatpho_sign_run minisign -S -s "$1" -m "$2" -x "$3" < "${input}" > /dev/null 2> "$4/err" || {
    local status=$?
    __dybatpho_sign_report "minisign could not sign $2" "$4/err"
    return "${status}"
  }
}

#######################################
# @description Verify with `minisign`, trying each trusted key in turn.
# @arg $1 path File
# @arg $2 path Signature
# @arg $3 path Working directory
# @arg $@ string Trusted base64 public keys
# @exitcode 0 One of the keys made the signature
# @exitcode 1 None did
# @exitcode 124 A check ran out of time
# @internal
#######################################
function __dybatpho_sign_minisign_verify {
  local file="$1" signature="$2" work="$3" key status=1
  shift 3
  for key in "$@"; do
    __dybatpho_sign_run minisign -V -q -P "${key}" -m "${file}" -x "${signature}" \
      < /dev/null > /dev/null 2> "${work}/err" && return 0
    status=$?
    ((status != 124)) || return 124
  done
  return 1
}

#######################################
# @description Sign with `gpg`, as an armored detached signature. Away from a
#   terminal the agent is told to fail rather than start a pinentry.
# @arg $1 string Key id, fingerprint or user id in the user's keyring
# @arg $2 path File to sign
# @arg $3 path Signature to write
# @arg $4 path Working directory
# @internal
#######################################
function __dybatpho_sign_gpg_sign {
  local -a mode=()
  dybatpho::is_tty stdin && dybatpho::is_tty stderr || mode=(--pinentry-mode error)
  __dybatpho_sign_run gpg --batch --yes ${mode[@]+"${mode[@]}"} --armor --detach-sign \
    --local-user "$1" --output "$3" -- "$2" < /dev/null > /dev/null 2> "$4/err" || {
    local status=$?
    __dybatpho_sign_report "gpg could not sign $2" "$4/err"
    return "${status}"
  }
}

#######################################
# @description Append the OpenPGP packets of an exported public key to a
#   keyring file: a binary export as it is, an armored one decoded from its
#   base64 body, so `gpgv` needs no `gpg --dearmor`.
# @arg $1 path Exported public key
# @arg $2 path Keyring to append to
# @exitcode 1 Stop script when the file holds no key
# @internal
#######################################
function __dybatpho_sign_gpg_keyring_add {
  local key="$1" keyring="$2" line in_body=0 body="" before after first=""
  before="$(wc -c < "${keyring}")"
  IFS= read -r first < "${key}" || true
  if [[ "${first%$'\r'}" != "-----BEGIN PGP PUBLIC KEY BLOCK-----" ]]; then
    cat -- "${key}" >> "${keyring}"
  else
    # The body starts after the blank line ending the armor headers and stops at
    # the checksum line (`=xxxx`) or the END line.
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      case "${line}" in
        "-----BEGIN PGP PUBLIC KEY BLOCK-----") in_body=1 body="" ;;
        "-----END PGP PUBLIC KEY BLOCK-----" | =*)
          if ((in_body)) && [[ -n "${body}" ]]; then
            printf '%s' "${body}" | base64 -d >> "${keyring}" 2> /dev/null \
              || dybatpho::die "${FUNCNAME[1]}: Cannot decode the key in ${key}"
          fi
          in_body=0 body=""
          ;;
        "") ((in_body)) && in_body=2 ;;
        *) ((in_body != 2)) || body+="${line}" ;;
      esac
    done < "${key}"
  fi
  after="$(wc -c < "${keyring}")"
  ((after > before)) || dybatpho::die "${FUNCNAME[1]}: No public key in ${key}"
}

#######################################
# @description Verify with `gpgv`, against a keyring holding only the trusted
#   keys, in a home directory of its own: neither the user's keyring nor their
#   `GNUPGHOME` is read, and no agent starts.
# @arg $1 path File
# @arg $2 path Signature
# @arg $3 path Working directory
# @arg $@ path Trusted exported public keys
# @internal
#######################################
function __dybatpho_sign_gpg_verify {
  local file="$1" signature="$2" work="$3" key
  shift 3
  mkdir -m 700 -- "${work}/gnupg"
  : > "${work}/trusted.gpg"
  for key in "$@"; do
    __dybatpho_sign_gpg_keyring_add "${key}" "${work}/trusted.gpg"
  done
  __dybatpho_sign_run gpgv --homedir "${work}/gnupg" --keyring "${work}/trusted.gpg" \
    -- "${signature}" "${file}" < /dev/null > /dev/null 2> "${work}/err"
}

#######################################
# @description Sign a file with a key and print the signature's path.
# @example
#   dybatpho::sign_file ssh ~/.ssh/id_ed25519 accounts.yaml
#
# @example
#   DYBATPHO_SIGN_NAMESPACE="registry" dybatpho::sign_file ssh ~/.ssh/id_ed25519.pub accounts.yaml
#
# @arg $1 string Backend: `ssh`, `minisign` or `gpg`
# @arg $2 string Key: an SSH private key, or a public key whose private half
#   `ssh-agent` holds; a minisign secret key; a GnuPG key id
# @arg $3 path File to sign
# @arg $4 path [default: FILE.sig, FILE.minisig or FILE.asc] Signature path,
#   replaced when it exists
# @env DYBATPHO_SIGN_NAMESPACE string [default: file] Purpose an SSH signature is made for
# @env DYBATPHO_SIGN_TIMEOUT number [default: 10] Seconds the tool may run when there is no terminal
# @stdout Path of the signature
# @exitcode 0 The file was signed
# @exitcode 1 Signing failed
# @exitcode 124 The tool ran out of time
# @exitcode 127 Stop script when the backend's tool is missing
#######################################
function dybatpho::sign_file {
  local backend key file
  dybatpho::expect_args backend key file -- "$@"
  local signature="${4-}"
  __dybatpho_sign_require "${backend}" sign
  [[ -f "${file}" && -r "${file}" ]] || dybatpho::die "${FUNCNAME[0]}: Cannot read ${file}"
  [[ "${backend}" != ssh ]] || __dybatpho_sign_check_namespace
  [[ -n "${signature}" ]] || signature="${file}$(__dybatpho_sign_extension "${backend}")"

  local work status=0
  dybatpho::create_temp_dir work "sign"
  "__dybatpho_sign_${backend}_sign" "${key}" "${file}" "${work}/signature" "${work}" || status=$?
  ((status)) || mv -f -- "${work}/signature" "${signature}" || status=$?
  [[ -z "${work}" ]] || rm -rf -- "${work}"
  ((status == 0)) || return "${status}"
  printf '%s\n' "${signature}"
}

#######################################
# @description Check that a file was signed by one of the trusted keys. The
#   backend is read from the signature; only the trusted keys of that backend
#   count, and nothing else on the machine is consulted.
# @example
#   dybatpho::verify_file accounts.yaml accounts.yaml.sig "ssh-ed25519 AAAAC3Nza..." \
#     || dybatpho::die "accounts.yaml is not signed by a trusted key"
#
# @arg $1 path File
# @arg $2 path Signature
# @arg $@ string Trusted keys: an SSH `<type> <base64>`, a minisign public key,
#   or a file holding keys -- for gpg, an exported public key
# @env DYBATPHO_SIGN_NAMESPACE string [default: file] Purpose an SSH signature must have been made for
# @env DYBATPHO_SIGN_TIMEOUT number [default: 10] Seconds the tool may run when there is no terminal
# @exitcode 0 A trusted key made the signature, and the file is unchanged
# @exitcode 1 It did not: another key, a changed file, or no trusted key of that kind
# @exitcode 124 The check ran out of time
# @exitcode 127 Stop script when the backend's tool is missing
# @tip A broken call -- a missing file or key file, an unknown signature or key
#   -- stops the script, so it is never mistaken for an untrusted signature
#######################################
function dybatpho::verify_file {
  local file signature
  dybatpho::expect_args file signature -- "$@"
  shift 2
  local path
  for path in "${file}" "${signature}"; do
    [[ -f "${path}" && -r "${path}" ]] || dybatpho::die "${FUNCNAME[0]}: Cannot read ${path}"
  done
  local backend
  __dybatpho_sign_detect_into backend "${signature}"
  __dybatpho_sign_require "${backend}" verify
  [[ "${backend}" != ssh ]] || __dybatpho_sign_check_namespace
  local -a keys=()
  __dybatpho_sign_trusted_into keys "${backend}" "$@"
  ((${#keys[@]})) || return 1

  local work status=0
  dybatpho::create_temp_dir work "sign"
  # A signature that crossed a Windows machine carries CRLF, which the tools refuse.
  tr -d '\r' < "${signature}" > "${work}/signature"
  "__dybatpho_sign_${backend}_verify" "${file}" "${work}/signature" "${work}" ${keys[@]+"${keys[@]}"} || status=$?
  [[ -z "${work}" ]] || rm -rf -- "${work}"
  ((status == 0 || status == 124)) || status=1
  return "${status}"
}
