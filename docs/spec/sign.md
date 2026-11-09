# Feature Specification: Signing and Verifying Files

**Feature Branch**: `[feature-sign]`
**Status**: Implemented
**Input**: `src/sign.sh`, `test/sign.bats`, `docs/sign.md`, `example/sign_ops.sh`; designed from how `dyai` signs and checks its account registry with `ssh-keygen -Y` (`lib/dyai_store.sh`), `dybatpho::release_sign` in `src/release.sh`, and issue #10, closed because a module that only wraps one tool cannot be tested against the real thing

## Problem Statement *(mandatory)*

A script that hands a file to another machine, or reads one back, needs to know the file came from someone it trusts and was not changed on the way. The tools exist -- `ssh-keygen -Y`, `minisign`, `gpg` -- but each has its own flags, its own signature format and its own idea of who is trusted, and the safe way to call each one is not the obvious one:

- `ssh-keygen -Y verify` wants an `allowed_signers` file, so every caller writes a temporary one, and a caller that forgets `namespaces=` accepts a signature made for a different purpose.
- `ssh-keygen -Y sign` asks before overwriting an existing `.sig`, which hangs a script.
- `gpg --verify` trusts whatever is in the user's keyring, so a check that passes on the author's machine says nothing about the key the caller meant.
- None of them should wait on a prompt or a hung agent in a script that runs unattended.

`dyai` already does all of this by hand for one file. The next script would do it again.

## Business Value *(mandatory)*

- Sign a file and check a signature with two calls, whichever tool made it.
- Trust only the keys the caller names, never a keyring or `allowed_signers` file that happens to be on the machine.
- Keep an SSH signature made for one purpose from passing as one made for another.
- Add a signing tool later by writing two internal functions, without changing a caller.
- Test every backend against the real tool, as issue #10 asks of a module that runs one.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sign a file (Priority: P1)

As a script author, I want to sign a file with a key I already have -- an SSH key, a minisign key or a GnuPG key -- and get the signature's path back.

**Independent Test**: Generate a key of each kind in the test directory, sign a file with each, and find a signature file of the expected format.

**Acceptance Scenarios**:

1. **Given** an SSH private key, **When** `sign_file ssh KEY FILE` runs, **Then** `FILE.sig` holds an SSH signature in the namespace `DYBATPHO_SIGN_NAMESPACE`, and its path is printed
2. **Given** an SSH public key whose private half is loaded in `ssh-agent`, **When** `sign_file ssh KEY.pub FILE` runs, **Then** the agent signs it
3. **Given** a minisign secret key, **When** `sign_file minisign KEY FILE` runs, **Then** `FILE.minisig` holds a minisign signature
4. **Given** a GnuPG key id in the user's keyring, **When** `sign_file gpg KEYID FILE` runs, **Then** `FILE.asc` holds an armored detached signature
5. **Given** a signature path as the fourth argument, **When** the file is signed, **Then** the signature goes there instead, replacing a file already there without asking
6. **Given** a key with a passphrase, **When** `sign_file` runs at a terminal, **Then** the tool asks for it; **When** it runs without one, **Then** it fails at once unless an agent holds the key

---

### User Story 2 - Check a signature against the keys I trust (Priority: P1)

As a script author, I want to check that a file was signed by one of the keys I name, without saying which tool signed it.

**Independent Test**: Sign a file with each backend, verify it against the right key, and see it refused against another key, with the file changed, and with the wrong namespace.

**Acceptance Scenarios**:

1. **Given** a file, its signature and the signer's public key among the trusted keys, **When** `verify_file FILE SIG TRUSTED...` runs, **Then** it returns 0
2. **Given** the signer's key is not among the trusted keys, **When** it runs, **Then** it returns 1
3. **Given** the file changed after signing, **When** it runs, **Then** it returns 1
4. **Given** an SSH signature made in another namespace, **When** it runs, **Then** it returns 1
5. **Given** a GnuPG signature by a key that is in the user's own keyring but not among the trusted keys, **When** it runs, **Then** it returns 1
6. **Given** trusted keys of several kinds, **When** it runs, **Then** only the keys of the signature's kind are considered

---

### User Story 3 - Get the value to trust (Priority: P2)

As a script author, I want to print the public half of a key in the form `verify_file` takes, so I can pin it in configuration.

**Independent Test**: Print the trusted value of each generated key and verify a signature against it.

**Acceptance Scenarios**:

1. **Given** an SSH private key without a passphrase, **When** `sign_public_key ssh KEY` runs, **Then** it prints `<type> <base64>` without the comment
2. **Given** an SSH private key with a passphrase and a script running without a terminal, **When** it runs, **Then** it fails without prompting
3. **Given** a minisign key, **When** it runs, **Then** it prints the public key line
4. **Given** a GnuPG key id, **When** it runs, **Then** it prints the armored public key

---

### User Story 4 - Know which backends work here (Priority: P3)

As a script author, I want to list the backends whose tool is installed, so I can pick one or report what is missing.

**Acceptance Scenarios**:

1. **Given** `ssh-keygen` with `-Y` support and `gpgv` but no `minisign`, **When** `sign_backends` runs, **Then** it prints `ssh` and `gpg`, one per line
2. **Given** `gpgv` but no `gpg`, **When** `sign_backends sign` runs, **Then** `gpg` is not listed

### Example Workflow

```bash
. init.sh --modules sign

# Sign a registry file with the machine's SSH key.
DYBATPHO_SIGN_NAMESPACE="dyai-registry" \
  dybatpho::sign_file ssh ~/.ssh/id_ed25519 accounts.yaml

# Accept it only from the keys pinned in configuration.
DYBATPHO_SIGN_NAMESPACE="dyai-registry" \
  dybatpho::verify_file accounts.yaml accounts.yaml.sig "${pinned_keys[@]}" \
  || dybatpho::die "accounts.yaml is not signed by a trusted key"

# Check a release downloaded with its minisign signature.
dybatpho::verify_file tool.tar.gz tool.tar.gz.minisig "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
```

## Edge Cases

- The tool a backend needs is not installed, or `ssh-keygen` is older than OpenSSH 8.1 and has no `-Y`.
- The signature file already exists.
- The file name holds spaces, or starts with `-`.
- The signature is in a format no backend recognises, is empty, or is a binary GnuPG signature.
- A trusted key is given as a string and another as a path to a file holding one or more keys.
- A trusted list holds no key of the signature's kind.
- An SSH key has a passphrase and no agent holds it; a minisign key is encrypted.
- `ssh-agent` or `gpg-agent` hangs, or a verification never returns.
- The caller's `GNUPGHOME`, `~/.ssh/allowed_signers` or `~/.gnupg` would change the answer if they were read.
- The script is interrupted while a temporary keyring or `allowed_signers` file exists.
- `DYBATPHO_SIGN_NAMESPACE` is empty or holds a quote.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST expose one signing call, `sign_file BACKEND KEY FILE [SIGNATURE]`, and one checking call, `verify_file FILE SIGNATURE TRUSTED...`, whatever the backend.
- **FR-002**: The backends MUST be `ssh` (`ssh-keygen -Y`), `minisign` and `gpg`. Each MUST be a pair of internal functions, `__dybatpho_sign_<backend>_sign` and `__dybatpho_sign_<backend>_verify`, plus one recognition rule, so that adding a backend touches nothing else.
- **FR-003**: `sign_file` MUST write the signature to `FILE.sig` (ssh), `FILE.minisig` (minisign) or `FILE.asc` (gpg) unless given a path, MUST replace a file already there without prompting, and MUST print the signature's path.
- **FR-004**: `verify_file` MUST tell the backend from the signature itself: `-----BEGIN SSH SIGNATURE-----` is ssh, a first line starting `untrusted comment:` is minisign, `-----BEGIN PGP SIGNATURE-----` is gpg. Anything else MUST stop the script with a message naming the signature file.
- **FR-005**: `verify_file` MUST return 0 only when the signature is valid for the file and was made by one of the trusted keys of that backend, and 1 when it is not: a bad or foreign signature, a changed file, or no trusted key of that backend. A check that runs out of time MUST return 124. A broken call MUST stop the script instead, so it never reads as an untrusted signature: a missing or unreadable FILE or SIGNATURE, a trusted key path that does not exist, a trusted key string no backend recognises, and a gpg key file holding no key.
- **FR-006**: A trusted key MUST be accepted as a string -- `<type> <base64> [comment]` for ssh, the base64 public key for minisign -- or as a path to a file holding one or more of them; a gpg trusted key MUST be a path to an exported public key, armored or binary. Keys of another backend MUST be ignored.
- **FR-007**: Verification MUST consult only the trusted keys given: ssh through a temporary `allowed_signers` file, gpg through `gpgv` and a temporary keyring, never the user's `allowed_signers`, keyring or `GNUPGHOME`.
- **FR-008**: The ssh backend MUST sign and verify in the namespace `DYBATPHO_SIGN_NAMESPACE`, default `file`, MUST pin that namespace on every trusted key, and MUST refuse a namespace that is empty or holds a character `allowed_signers` cannot carry. The minisign and gpg backends MUST ignore it, so that a signature made by the tool itself, such as a release's `.minisig`, still verifies; the module documentation MUST say that only ssh binds a signature to a purpose.
- **FR-009**: `sign_file ssh` MUST accept a private key, or a public key whose private half `ssh-agent` holds.
- **FR-010**: A call MAY ask for a passphrase only when stdin and stderr are both terminals. Otherwise it MUST keep every tool from reaching the terminal -- the tools read `/dev/tty`, so closing stdin is not enough -- and a key that needs a passphrase no agent can supply MUST make the call fail.
- **FR-011**: Each call to a signing tool MUST be bounded by `DYBATPHO_SIGN_TIMEOUT` seconds, default 10, and a call that runs out MUST fail.
- **FR-012**: A missing tool, or an `ssh-keygen` without `-Y`, MUST stop the script with exit code 127 and the package to install.
- **FR-013**: Temporary files MUST be created readable by the current user only and removed when the call returns, fails or is interrupted.
- **FR-014**: `sign_public_key BACKEND KEY` MUST print the value `verify_file` accepts for that key, following the same rule as FR-010 for passphrases.
- **FR-015**: `sign_backends [sign|verify]` MUST print each backend that can do that here, one per line, in the order `ssh`, `minisign`, `gpg`, checking verification by default: `gpg` verifies with `gpgv` and signs with `gpg`, so it can be listed for one and not the other. `sign_file gpg` and `sign_public_key gpg` without `gpg` MUST stop with the `gnupg` install hint.
- **FR-016**: No call MUST print key material other than public keys, or a passphrase, to stdout, stderr or the log.
- **FR-017**: gpg verification MUST read `gpgv`'s status and accept only a `VALIDSIG` with no `BADSIG`, `ERRSIG`, `EXPSIG`, `EXPKEYSIG`, `REVKEYSIG`, `KEYREVOKED`, `KEYEXPIRED`, `NO_PUBKEY`, `PLAINTEXT`, `BADARMOR` or `NODATA` beside it: `gpgv` exits 0 for a signature by a revoked key.
- **FR-018**: `sign_public_key gpg` MUST resolve the user id to exactly one key and export that key alone, minimal, and MUST fail when it matches none or several: a user id matches by substring.

### Key Entities *(include if feature involves data)*

- **Backend**: A signing tool and the two functions that drive it.
- **Trusted Key**: The public half of a key the caller accepts signatures from, as a string or a file.
- **Namespace**: The purpose an SSH signature was made for; a signature from one namespace never verifies in another.
- **Signature File**: The detached signature beside the file, in the backend's own format.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script signs and checks a file in two calls, for every backend.
- **SC-002**: No signature is accepted from a key the caller did not name, whatever the machine's keyrings hold.
- **SC-003**: No call hangs on a prompt in an unattended script.
- **SC-004**: Every backend is tested against its real tool wherever that tool is installed, CI included.

## Integration Tests *(mandatory)*

- **IT-001**: For each backend whose tool is installed, sign a file with a key generated in the test directory and verify it against that key.
- **IT-002**: For each backend, refuse a signature against another key, after the file changed, and with no trusted key of its kind.
- **IT-003**: Refuse an ssh signature checked in another namespace.
- **IT-004**: Refuse a gpg signature whose key is in `GNUPGHOME` but not among the trusted keys.
- **IT-005**: Replace an existing signature file without prompting, and write to a given path.
- **IT-006**: Sign through `ssh-agent` with a public key path.
- **IT-007**: Without a controlling terminal, not only with stdin closed, fail at once on an ssh key with a passphrase and no agent, on an encrypted minisign key, and on a gpg key with a passphrase and no cached one.
- **IT-008**: Stop on a signature in no known format, and on an empty one.
- **IT-009**: Stop with exit code 127 and an install hint when the tool is not on the `PATH`.
- **IT-010**: Accept trusted keys as strings and as files, mixed across backends.
- **IT-011**: Print the trusted value of each key and verify against it.
- **IT-012**: List only the backends whose tool is on the `PATH`, and leave `gpg` out of the signing list when only `gpgv` is there.
- **IT-013**: Leave no temporary file behind after a verification succeeds, fails, or is interrupted.
- **IT-014**: Sign and verify a file whose name holds a space and starts with `-`.
- **IT-015**: Stop on a missing file, a missing signature, a trusted key path that does not exist and an unrecognised key string; return 124 when a check runs out of time.
- **IT-016**: Refuse a gpg signature by a key revoked after signing, and a signed message relabelled as a detached signature.
- **IT-017**: Refuse to print the public key for a gpg user id matching two keys, and print one key for an exact one.

## Acceptance Criteria *(mandatory)*

1. A signature verifies only against the keys the caller named, and an SSH one only in the namespace it was made for.
2. A caller never needs to know which backend made a signature to check it.
3. A new backend is two internal functions and one recognition rule.
4. No call run without a terminal waits on a prompt, and no call waits on a hung agent.

## Design Notes *(not part of the contract)*

These record what was decided while designing the module and why.

**Decided with the owner**

- Backends are `ssh`, `minisign` and `gpg`, behind one interface designed for more.
- `cosign` is out: its keyless mode needs the network and an OIDC login, cannot be tested in this repository, trusts an identity rather than a key, and writes the signer's identity to a public log; its key mode adds little over minisign.
- A missing tool stops the script with an install hint, as the `flock` locks do.
- Only ssh binds a signature to a purpose. Binding minisign and gpg signatures too, through the trusted comment and a notation, was weighed and declined: it would refuse every signature made outside this module, such as a release's `.minisig`.
- A passphrase may be asked for at a terminal, so a person can sign with an encrypted key, minisign included; an unattended script never waits on one.

**Decided by the designer**

- The module is called `sign`, not `ssh`, so it is not read as reopening issue #10, and so a backend that is not SSH fits it.
- The ssh namespace comes from `DYBATPHO_SIGN_NAMESPACE` rather than an argument, which keeps `sign_file` and `verify_file` the same shape for every backend.
- Trusted keys of other backends are ignored rather than refused, so one pinned list can hold keys of every kind.
- gpg trusts exported public key files, not fingerprints: a fingerprint cannot be checked without key material, and fetching it would mean the user's keyring or the network.
- Only armored gpg signatures are recognised; a binary one stops the script as an unknown format.
- The module starts `experimental`, like every new module.
- CI installs the tools so every backend runs there for real: `openssh-keygen`, `gnupg` and `minisign` on Alpine, `openssh-client`, `gnupg` and `minisign` in the kcov container. The macOS smoke job runs the ssh backend only.
- The `doctor` registry lists `[sign]="ssh-keygen|minisign|gpgv"`.
- A broken call stops the script and a timeout returns 124, so a typo in a pinned key path is never mistaken for an untrusted signature.
- `sign_backends` takes `sign` or `verify`, default `verify`, because `gpg` verifies with `gpgv` alone.

**Left to the builder**

- How `ssh-keygen` is probed for `-Y`.
- How each tool is kept off the terminal when no prompt is allowed -- for instance `setsid`, `SSH_ASKPASS_REQUIRE=never`, `--pinentry-mode error`, `--batch` -- and how the test detaches from its controlling terminal.
- The temporary `GNUPGHOME` path, which must stay short: `gpg-agent` puts a socket in it, and a socket path has a length limit.
- The module's optional dependencies, found from the calls it ends up making.

**Out of scope**

- Changing `dybatpho::release_sign`, which keeps signing with `gpg` by default.
- `cosign`, `signify`, X.509 and S/MIME signatures, HMAC, and git commit signing.
- Changing `dyai` to use this module.
