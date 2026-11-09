# sign.sh

Utilities for signing files and checking signatures

> 🧭 Source: [src/sign.sh](../src/sign.sh)
>
> Jump to: [Overview](#overview) · [Usage](#usage) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>

## ✨ Overview

This module signs a file and checks a signature with `ssh-keygen -Y`,
`minisign` or `gpg`, behind one pair of calls. A signature is checked
against the keys the caller names and nothing else: never the user's
`allowed_signers`, keyring or `GNUPGHOME`.

Only an SSH signature is bound to a purpose, its namespace
(`DYBATPHO_SIGN_NAMESPACE`); minisign and gpg ignore it, so that a
signature made by the tool itself, such as a release's `.minisig`, still
verifies.

A tool asks for a passphrase only when stdin and stderr are both
terminals. Run without one, a key that needs a passphrase no agent holds
makes the call fail at once instead of waiting.

### 🌍 Environment

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_SIGN_NAMESPACE`** | string | no | `file` | Purpose an SSH signature is made and checked for |
| **`DYBATPHO_SIGN_TIMEOUT`** | number | no | `10` | Seconds a signing tool may run before the call fails |

### 🚀 Highlights

- [`dybatpho::sign_backends`](#dybatphosign_backends) — Print the backends that can sign, or verify, on this machine.
- [`dybatpho::sign_file`](#dybatphosign_file) — Sign a file with a key and print the signature's path.
- [`dybatpho::verify_file`](#dybatphoverify_file) — Check that a file was signed by one of the trusted keys. The backend is read from the signature; only the trusted keys of that backend count, and nothing else on the machine is consulted.

<a id="usage"></a>

## 🚀 Usage

### Sign a file and check it against a pinned key

```bash
DYBATPHO_SIGN_NAMESPACE="registry" dybatpho::sign_file ssh ~/.ssh/id_ed25519 accounts.yaml
DYBATPHO_SIGN_NAMESPACE="registry" \
  dybatpho::verify_file accounts.yaml accounts.yaml.sig "${pinned_key}" \
  || dybatpho::die "accounts.yaml is not signed by a trusted key"
```

### Check a release's minisign signature

```bash
dybatpho::verify_file tool.tar.gz tool.tar.gz.minisig "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3"
```

<a id="see-also"></a>

## 🔗 See also

- [example/sign_ops.sh](../example/sign_ops.sh)

<a id="tips"></a>

## 💡 Tips

**[`dybatpho::sign_backends`](#dybatphosign_backends)**

- `gpg` verifies with `gpgv` alone but signs with `gpg`, so it can be listed for one direction and not the other

**[`dybatpho::verify_file`](#dybatphoverify_file)**

- A broken call -- a missing file or key file, an unknown signature or key -- stops the script, so it is never mistaken for an untrusted signature

<a id="reference"></a>

## 📚 Reference

### `dybatpho::sign_backends`

Print the backends that can sign, or verify, on this machine.

**🧪 Example**

```bash
dybatpho::sign_backends sign

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | no | `verify` | `sign` or `verify` |

**📤 Output on stdout**

- One backend per line, in the order `ssh`, `minisign`, `gpg`

---

### `dybatpho::sign_file`

Sign a file with a key and print the signature's path.

**🧪 Examples**

```bash
dybatpho::sign_file ssh ~/.ssh/id_ed25519 accounts.yaml

```

```bash
DYBATPHO_SIGN_NAMESPACE="registry" dybatpho::sign_file ssh ~/.ssh/id_ed25519.pub accounts.yaml

```

**🧾 Arguments**

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `$1` | string | yes |  | Backend: `ssh`, `minisign` or `gpg` |
| `$2` | string | yes |  | Key: an SSH private key, or a public key whose private half `ssh-agent` holds; a minisign secret key; a GnuPG key id |
| `$3` | path | yes |  | File to sign |
| `$4` | path | no | `FILE.sig, FILE.minisig or FILE.asc` | Signature path, replaced when it exists |

**🌍 Environment variables**

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_SIGN_NAMESPACE`** | string | no | `file` | Purpose an SSH signature is made for |
| **`DYBATPHO_SIGN_TIMEOUT`** | number | no | `10` | Seconds the tool may run when there is no terminal |

**📤 Output on stdout**

- Path of the signature

**🚦 Exit codes**

- `0`: The file was signed
- `1`: Signing failed
- `124`: The tool ran out of time
- `127`: Stop script when the backend's tool is missing

---

### `dybatpho::verify_file`

Check that a file was signed by one of the trusted keys. The
backend is read from the signature; only the trusted keys of that backend
count, and nothing else on the machine is consulted.

**🧪 Example**

```bash
dybatpho::verify_file accounts.yaml accounts.yaml.sig "ssh-ed25519 AAAAC3Nza..." \
  || dybatpho::die "accounts.yaml is not signed by a trusted key"

```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | path | File |
| `$2` | path | Signature |
| `$@` | string | Trusted keys: an SSH `<type> <base64>`, a minisign public key, or a file holding keys -- for gpg, an exported public key |

**🌍 Environment variables**

| Variable | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| **`DYBATPHO_SIGN_NAMESPACE`** | string | no | `file` | Purpose an SSH signature must have been made for |
| **`DYBATPHO_SIGN_TIMEOUT`** | number | no | `10` | Seconds the tool may run when there is no terminal |

**🚦 Exit codes**

- `0`: A trusted key made the signature, and the file is unchanged
- `1`: It did not: another key, a changed file, or no trusted key of that kind
- `124`: The check ran out of time
- `127`: Stop script when the backend's tool is missing
