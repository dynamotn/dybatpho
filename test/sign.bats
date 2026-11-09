setup() {
  load test_helper
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
