setup() {
  load test_helper
}

teardown() {
  # A gpg test starts an agent inside its GNUPGHOME; it must not outlive the test.
  [[ "${GNUPGHOME-}" != "${BATS_TEST_TMPDIR}"/* ]] || gpgconf --kill all &> /dev/null || true
}

# Skip where `ssh-keygen` cannot sign: missing, or older than OpenSSH 8.1. It
# probes the tool itself rather than through the module under test.
_need_ssh_y() {
  [[ "$(ssh-keygen -Y sign < /dev/null 2>&1)" == *namespace* ]] \
    || skip "ssh-keygen with -Y is not installed"
}

# A directory on `PATH` holding only links to the named commands, for a test
# that needs some tools present and the rest of a backend's missing.
_path_with_only() {
  local dir="${BATS_TEST_TMPDIR}/only-bin" tool
  mkdir -p "${dir}"
  for tool in "$@"; do
    ln -sf "$(command -v "${tool}")" "${dir}/${tool}"
  done
  printf '%s\n' "${dir}"
}

@test "dybatpho::sign_backends lists ssh when ssh-keygen supports -Y" {
  _need_ssh_y
  run_traced -0 dybatpho::sign_backends
  assert_line "ssh"
  run_traced -0 dybatpho::sign_backends sign
  assert_line "ssh"
}

@test "dybatpho::sign_backends sign leaves gpg out when only gpgv is on the PATH" {
  command -v gpgv > /dev/null || skip "gpgv is not installed"
  local only
  only="$(_path_with_only gpgv)"
  PATH="${only}" run_traced -0 dybatpho::sign_backends verify
  assert_output "gpg"
  PATH="${only}" run_traced -0 dybatpho::sign_backends sign
  assert_output ""
}

@test "dybatpho::sign_backends refuses a mode other than sign or verify" {
  run -1 --separate-stderr dybatpho::sign_backends both
  assert_stderr --partial "Expected sign or verify, got: both"
}

@test "dybatpho::sign_file stops with exit 127 and the package to install when the tool is missing" {
  PATH="$(path_without ssh-keygen)" run -127 --separate-stderr \
    dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/key" "${BATS_TEST_TMPDIR}/file"
  assert_stderr --partial "ssh-keygen isn't installed; install openssh"
}

@test "dybatpho::sign_file stops when the backend is unknown" {
  run -1 --separate-stderr dybatpho::sign_file cosign key file
  assert_stderr --partial "Unknown backend: cosign"
}

# An ed25519 key without a passphrase, in the test directory.
_ssh_key() {
  ssh-keygen -q -t ed25519 -N '' -C "test key" -f "${BATS_TEST_TMPDIR}/$1"
}

# The trusted value of a generated SSH key: its type and base64, no comment.
_ssh_pub() {
  cut -d' ' -f1,2 "${BATS_TEST_TMPDIR}/$1.pub"
}

_payload() {
  printf 'payload %s\n' "$1" > "${BATS_TEST_TMPDIR}/$1"
  printf '%s\n' "${BATS_TEST_TMPDIR}/$1"
}

@test "dybatpho::sign_file ssh writes FILE.sig and prints its path" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  run_traced -0 dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}"
  assert_output "${file}.sig"
  assert_equal "$(head -1 "${file}.sig")" "-----BEGIN SSH SIGNATURE-----"
}

@test "dybatpho::sign_file ssh replaces an existing signature without asking, and writes to a given path" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  printf 'stale\n' > "${file}.sig"
  run_traced -0 dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" < /dev/null
  assert_equal "$(head -1 "${file}.sig")" "-----BEGIN SSH SIGNATURE-----"
  run_traced -0 dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" "${BATS_TEST_TMPDIR}/elsewhere.sig"
  assert_output "${BATS_TEST_TMPDIR}/elsewhere.sig"
  assert_file_exists "${BATS_TEST_TMPDIR}/elsewhere.sig"
}

@test "dybatpho::verify_file accepts an ssh signature by a trusted key, given as a string or a .pub file" {
  _need_ssh_y
  _ssh_key alice
  _ssh_key bob
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub bob)" "$(_ssh_pub alice)"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "${BATS_TEST_TMPDIR}/alice.pub"
}

@test "dybatpho::verify_file returns 1 for another key, a changed file, or no ssh key among the trusted" {
  _need_ssh_y
  _ssh_key alice
  _ssh_key bob
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  run_traced -1 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub bob)"
  run_traced -1 dybatpho::verify_file "${file}" "${file}.sig" "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
  printf 'changed\n' >> "${file}"
  run_traced -1 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
}

@test "dybatpho::verify_file returns 1 for an ssh signature made in another namespace" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  DYBATPHO_SIGN_NAMESPACE=registry dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  DYBATPHO_SIGN_NAMESPACE=registry run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
  DYBATPHO_SIGN_NAMESPACE=deploy run_traced -1 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
}

@test "dybatpho::verify_file stops on a signature in no known format, an empty one and a missing one" {
  local file
  file="$(_payload doc.txt)"
  printf 'not a signature\n' > "${file}.sig"
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${file}.sig" key
  assert_stderr --partial "Unknown signature format: ${file}.sig"
  : > "${file}.sig"
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${file}.sig" key
  assert_stderr --partial "Unknown signature format"
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${BATS_TEST_TMPDIR}/absent.sig" key
  assert_stderr --partial "Cannot read ${BATS_TEST_TMPDIR}/absent.sig"
  run -1 --separate-stderr dybatpho::verify_file "${BATS_TEST_TMPDIR}/absent" "${file}.sig" key
  assert_stderr --partial "Cannot read ${BATS_TEST_TMPDIR}/absent"
}

@test "dybatpho::verify_file stops on a trusted key path that does not exist or a string no backend knows" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${file}.sig" "${BATS_TEST_TMPDIR}/missing.pub"
  assert_stderr --partial "Trusted key not found: ${BATS_TEST_TMPDIR}/missing.pub"
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${file}.sig" "not-a-key"
  assert_stderr --partial "Not a key any backend knows: not-a-key"
}

@test "dybatpho::verify_file reads a key file with comments and blank lines, and a CRLF signature" {
  _need_ssh_y
  _ssh_key alice
  local file keys="${BATS_TEST_TMPDIR}/keys"
  file="$(_payload doc.txt)"
  printf '# team keys\n\n%s alice@example\n' "$(_ssh_pub alice)" > "${keys}"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "${keys}"
  sed 's/$/\r/' "${file}.sig" > "${file}.crlf.sig"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.crlf.sig" "${keys}"
}

@test "dybatpho::sign_file and verify_file take a file whose name starts with a dash and holds a space" {
  _need_ssh_y
  _ssh_key alice
  local file="${BATS_TEST_TMPDIR}/-dash name.txt"
  printf 'payload\n' > "${file}"
  run_traced -0 dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
}

@test "dybatpho::sign_file refuses a namespace allowed_signers cannot carry, before writing" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  DYBATPHO_SIGN_NAMESPACE='a"b' run -1 --separate-stderr \
    dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}"
  assert_stderr --partial "Invalid namespace"
  assert_file_not_exists "${file}.sig"
  DYBATPHO_SIGN_NAMESPACE='' run -1 --separate-stderr \
    dybatpho::verify_file "${file}" "${file}" "$(_ssh_pub alice)"
}

@test "dybatpho::sign_file ssh signs through ssh-agent with a public key path" {
  _need_ssh_y
  _ssh_key alice
  local file sock="${BATS_TEST_TMPDIR}/agent.sock"
  file="$(_payload doc.txt)"
  eval "$(ssh-agent -a "${sock}" 2> /dev/null)" > /dev/null || skip "ssh-agent cannot start"
  if ! ssh-add -q "${BATS_TEST_TMPDIR}/alice" 2> /dev/null; then
    ssh-agent -k &> /dev/null || true
    skip "ssh-add cannot reach the agent"
  fi
  mv "${BATS_TEST_TMPDIR}/alice" "${BATS_TEST_TMPDIR}/alice.hidden"
  local status=0
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice.pub" "${file}" > /dev/null || status=$?
  ssh-agent -k > /dev/null
  assert_equal "${status}" 0
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
}

@test "dybatpho::verify_file leaves no temporary file behind" {
  _need_ssh_y
  _ssh_key alice
  local file before after
  local -a found=()
  file="$(_payload doc.txt)"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  found=("${BATS_TEST_TMPDIR}"/sign*)
  before="${#found[@]}"
  dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub alice)"
  _ssh_key bob
  dybatpho::verify_file "${file}" "${file}.sig" "$(_ssh_pub bob)" || true
  found=("${BATS_TEST_TMPDIR}"/sign*)
  after="${#found[@]}"
  assert_equal "${after}" "${before}"
}

_need_minisign() {
  command -v minisign > /dev/null || skip "minisign is not installed"
}

# A minisign key pair without a password: `<name>.key` and `<name>.pub`.
_minisign_key() {
  minisign -G -W -p "${BATS_TEST_TMPDIR}/$1.pub" -s "${BATS_TEST_TMPDIR}/$1.key" > /dev/null
}

# The trusted value of a generated minisign key: the second line of its .pub.
_minisign_pub() {
  sed -n 2p "${BATS_TEST_TMPDIR}/$1.pub"
}

@test "dybatpho::sign_file minisign writes FILE.minisig, which verifies against the key or its .pub file" {
  _need_minisign
  _minisign_key alice
  local file
  file="$(_payload doc.txt)"
  run_traced -0 dybatpho::sign_file minisign "${BATS_TEST_TMPDIR}/alice.key" "${file}"
  assert_output "${file}.minisig"
  assert_equal "$(head -c 18 "${file}.minisig")" "untrusted comment:"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.minisig" "$(_minisign_pub alice)"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.minisig" "${BATS_TEST_TMPDIR}/alice.pub"
}

@test "dybatpho::verify_file returns 1 for a minisign signature by another key or of a changed file" {
  _need_minisign
  _minisign_key alice
  _minisign_key bob
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file minisign "${BATS_TEST_TMPDIR}/alice.key" "${file}" > /dev/null
  run_traced -1 dybatpho::verify_file "${file}" "${file}.minisig" "$(_minisign_pub bob)"
  printf 'changed\n' >> "${file}"
  run_traced -1 dybatpho::verify_file "${file}" "${file}.minisig" "$(_minisign_pub alice)"
}

@test "dybatpho::verify_file ignores the namespace for minisign and reads a list mixing ssh and minisign keys" {
  _need_minisign
  _need_ssh_y
  _minisign_key alice
  _ssh_key carol
  local file
  file="$(_payload doc.txt)"
  DYBATPHO_SIGN_NAMESPACE=registry dybatpho::sign_file minisign "${BATS_TEST_TMPDIR}/alice.key" "${file}" > /dev/null
  DYBATPHO_SIGN_NAMESPACE=deploy run_traced -0 dybatpho::verify_file "${file}" "${file}.minisig" \
    "$(_ssh_pub carol)" "$(_minisign_pub alice)"
}

# A GNUPGHOME of the test's own, holding a passphrase-less signing key for each
# name given; skipped where no gpg-agent can start, as in a sandbox that refuses
# its socket.
_gpg_keys() {
  command -v gpg > /dev/null || skip "gpg is not installed"
  export GNUPGHOME="${BATS_TEST_TMPDIR}/gnupg"
  mkdir -p -m 700 "${GNUPGHOME}"
  local name
  for name in "$@"; do
    gpg --batch --passphrase '' --quick-gen-key "${name} <${name}@example.test>" ed25519 sign never \
      &> /dev/null || skip "gpg cannot generate a key here"
    gpg --armor --export "${name}@example.test" > "${BATS_TEST_TMPDIR}/${name}.asc"
    gpg --export "${name}@example.test" > "${BATS_TEST_TMPDIR}/${name}.gpg"
  done
}

@test "dybatpho::sign_file gpg writes an armored FILE.asc, which verifies against an armored or binary export" {
  _gpg_keys alice
  local file
  file="$(_payload doc.txt)"
  run_traced -0 dybatpho::sign_file gpg alice@example.test "${file}"
  assert_output "${file}.asc"
  assert_equal "$(head -1 "${file}.asc")" "-----BEGIN PGP SIGNATURE-----"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/alice.asc"
  run_traced -0 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/alice.gpg"
}

@test "dybatpho::verify_file returns 1 for a gpg signature by another key or of a changed file" {
  _gpg_keys alice bob
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file gpg alice@example.test "${file}" > /dev/null
  run_traced -1 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/bob.asc"
  printf 'changed\n' >> "${file}"
  run_traced -1 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/alice.asc"
}

@test "dybatpho::verify_file refuses a gpg signer the caller's own keyring trusts but the caller did not pass" {
  _gpg_keys alice bob
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_file gpg alice@example.test "${file}" > /dev/null
  # alice is in GNUPGHOME, and gpg --verify there would accept her.
  gpg --verify "${file}.asc" "${file}" &> /dev/null
  run_traced -1 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/bob.asc"
}

@test "dybatpho::verify_file stops on a gpg key file that holds no key" {
  _gpg_keys alice
  local file empty="${BATS_TEST_TMPDIR}/empty.asc"
  file="$(_payload doc.txt)"
  dybatpho::sign_file gpg alice@example.test "${file}" > /dev/null
  printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\n-----END PGP PUBLIC KEY BLOCK-----\n' > "${empty}"
  run -1 --separate-stderr dybatpho::verify_file "${file}" "${file}.asc" "${empty}"
  assert_stderr --partial "No public key in ${empty}"
}

@test "dybatpho::sign_file gpg stops with the gnupg hint when only gpgv is installed" {
  command -v gpgv > /dev/null || skip "gpgv is not installed"
  local file
  file="$(_payload doc.txt)"
  PATH="$(path_without gpg)" run -127 --separate-stderr dybatpho::sign_file gpg someone "${file}"
  assert_stderr --partial "gpg isn't installed; install gnupg"
}

# Run a library call in a fresh shell with no controlling terminal and stdin
# from /dev/null, bounded so a call that waits on a prompt fails the test
# rather than hanging the suite.
_without_terminal() {
  command -v setsid > /dev/null || skip "setsid is not installed"
  local script="${BATS_TEST_TMPDIR}/no-tty.sh"
  # shellcheck disable=SC2154 # DYBATPHO_DIR is set by test_helper
  printf '%s\n' ". '${DYBATPHO_DIR}/init.sh' --modules sign" "$*" > "${script}"
  timeout 20 setsid -w bash "${script}" < /dev/null
}

@test "dybatpho::sign_public_key ssh prints the type and base64 of a private key, which verifies its signature" {
  _need_ssh_y
  _ssh_key alice
  local file
  file="$(_payload doc.txt)"
  run_traced -0 dybatpho::sign_public_key ssh "${BATS_TEST_TMPDIR}/alice"
  assert_output "$(_ssh_pub alice)"
  dybatpho::sign_file ssh "${BATS_TEST_TMPDIR}/alice" "${file}" > /dev/null
  run_traced -0 dybatpho::verify_file "${file}" "${file}.sig" "$(dybatpho::sign_public_key ssh "${BATS_TEST_TMPDIR}/alice")"
}

@test "dybatpho::sign_public_key minisign prints the public key of a secret key" {
  _need_minisign
  _minisign_key alice
  run_traced -0 dybatpho::sign_public_key minisign "${BATS_TEST_TMPDIR}/alice.key"
  assert_output "$(_minisign_pub alice)"
}

@test "dybatpho::sign_public_key gpg prints an armored export that verifies the key's signature" {
  _gpg_keys alice
  local file
  file="$(_payload doc.txt)"
  dybatpho::sign_public_key gpg alice@example.test > "${BATS_TEST_TMPDIR}/exported.asc"
  assert_equal "$(head -1 "${BATS_TEST_TMPDIR}/exported.asc")" "-----BEGIN PGP PUBLIC KEY BLOCK-----"
  dybatpho::sign_file gpg alice@example.test "${file}" > /dev/null
  run_traced -0 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/exported.asc"
  run -1 --separate-stderr dybatpho::sign_public_key gpg nobody@example.test
  assert_stderr --partial "No public key for nobody@example.test"
}

@test "an ssh key with a passphrase fails at once without a terminal, from sign_file and sign_public_key" {
  _need_ssh_y
  ssh-keygen -q -t ed25519 -N 'a passphrase' -f "${BATS_TEST_TMPDIR}/locked"
  local file
  file="$(_payload doc.txt)"
  run -1 _without_terminal dybatpho::sign_file ssh "'${BATS_TEST_TMPDIR}/locked'" "'${file}'"
  assert_file_not_exists "${file}.sig"
  run -1 _without_terminal dybatpho::sign_public_key ssh "'${BATS_TEST_TMPDIR}/locked'"
}

@test "a gpg key with a passphrase fails at once without a terminal" {
  _gpg_keys
  gpg --batch --pinentry-mode loopback --passphrase 'a passphrase' \
    --quick-gen-key "locked <locked@example.test>" ed25519 sign never &> /dev/null \
    || skip "gpg cannot generate a key here"
  # The agent caches the passphrase from key generation; forget it.
  gpgconf --kill gpg-agent
  local file
  file="$(_payload doc.txt)"
  run -1 _without_terminal dybatpho::sign_file gpg locked@example.test "'${file}'"
  assert_file_not_exists "${file}.asc"
}

@test "dybatpho::verify_file refuses a gpg 'signature' that carries signed data of its own" {
  _gpg_keys alice
  local file other="${BATS_TEST_TMPDIR}/other.txt" forged="${BATS_TEST_TMPDIR}/forged.asc"
  file="$(_payload doc.txt)"
  printf 'something alice did sign\n' > "${other}"
  # A signed message, relabelled as a detached signature: gpgv would check the
  # data inside it and never look at the file named beside it.
  gpg --batch --armor --local-user alice@example.test --output - --sign -- "${other}" \
    | sed 's/PGP MESSAGE/PGP SIGNATURE/' > "${forged}"
  run_traced -1 dybatpho::verify_file "${file}" "${forged}" "${BATS_TEST_TMPDIR}/alice.asc"
}

@test "dybatpho::verify_file refuses a gpg signature by a key that has since been revoked" {
  _gpg_keys alice
  local file fpr revocation
  file="$(_payload doc.txt)"
  dybatpho::sign_file gpg alice@example.test "${file}" > /dev/null
  fpr="$(gpg --with-colons --list-keys alice@example.test | awk -F: '$1 == "fpr" { print $10; exit }')"
  revocation="${GNUPGHOME}/openpgp-revocs.d/${fpr}.rev"
  # gpg stores the certificate defused with a leading colon; restore it.
  sed 's/^:-----BEGIN/-----BEGIN/' "${revocation}" | gpg --batch --import &> /dev/null
  gpg --armor --export alice@example.test > "${BATS_TEST_TMPDIR}/alice-revoked.asc"
  run_traced -1 dybatpho::verify_file "${file}" "${file}.asc" "${BATS_TEST_TMPDIR}/alice-revoked.asc"
}
