# backup.sh

Utilities for taking backups and applying a retention policy

> 🧭 Source: [src/backup.sh](../src/backup.sh)
>
> Jump to: [Overview](#overview) · [See also](#see-also) · [Tips](#tips) · [Reference](#reference)

<a id="overview"></a>
## ✨ Overview

`archive.sh` creates and extracts archives; this module adds the policy
around them. It takes a timestamped snapshot, keeps the ones a retention
rule says to keep, and deletes the rest -- the loop that log rotation,
pre-change config snapshots and local database dumps each reimplement, and
each gets wrong in the same place: what exactly counts as "the last N".

A backup is written under a temporary name in the destination directory and
renamed into place, so a run that is killed halfway leaves no half-written
file that later looks like a good backup. A checksum sidecar is written
beside it, and `dybatpho::backup_verify` is what a restore checks before
trusting the archive.

Backups are named `<name>-<UTC timestamp>.<extension>`, which is why
sorting them by name is the same as sorting them by age, with no dependence
on a modification time that copying a directory can change.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_BACKUP_EXTENSION`** | string | Archive extension, default is `tar.gz`; `archive.sh` reads the format from it |
| **`DYBATPHO_BACKUP_CHECKSUM_ALGORITHM`** | string | Algorithm for the sidecar, default is `sha256` |
| **`DYBATPHO_BACKUP_EXTENSION`** | string | Extension every backup is written with, default is `tar.gz` |
| **`DYBATPHO_BACKUP_CHECKSUM_ALGORITHM`** | string | Checksum algorithm for the sidecar, default is `sha256` |

### 🚀 Highlights

- [`dybatpho::backup_create`](#dybatphobackup_create) — Take a timestamped backup of a file or directory. The archive is written under a temporary name in the destination and renamed into place, so nothing half-written is ever left looking complete. A checksum sidecar is written beside it.
- [`dybatpho::backup_list`](#dybatphobackup_list) — List a directory's backups, newest first.
- [`dybatpho::backup_latest`](#dybatphobackup_latest) — Print the most recent backup in a directory.
- [`dybatpho::backup_verify`](#dybatphobackup_verify) — Check a backup against its checksum sidecar. A backup with no sidecar cannot be checked, which is reported rather than passed, because "nothing to compare" is not the same answer as "matches".
- [`dybatpho::backup_restore`](#dybatphobackup_restore) — Restore a backup into a target directory. The checksum is verified first, and the extraction goes through `dybatpho::safe_extract`, so an archive whose entries would land outside the target is refused and an overwrite is confirmed.
- [`dybatpho::backup_prune`](#dybatphobackup_prune) — Delete the backups a retention policy does not keep. A backup survives when **any** policy keeps it, so asking for both `--keep-count` and `--keep-days` keeps more rather than less: a retention rule that deletes more than the operator expected is the expensive direction to be wrong in. `--keep-count` counts from the newest by name, which is the order the backups were taken. `--keep-days` reads how old the file on disk is, so a backup copied in from elsewhere is as old as the copy.

<a id="see-also"></a>
## 🔗 See also

- [example/backup_ops.sh](../example/backup_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Destinations are local paths; pushing a backup to object storage or a network share stays with the caller

<a id="reference"></a>
## 📚 Reference

### `dybatpho::backup_create`

Take a timestamped backup of a file or directory.
The archive is written under a temporary name in the destination and
renamed into place, so nothing half-written is ever left looking complete.
A checksum sidecar is written beside it.

**🧪 Example**

```bash
archive="$(dybatpho::backup_create /etc/nginx /var/backups)"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | File or directory to back up |
| `$2` | string | Destination directory, created when missing |
| `$3` | string | Optional name for the backup, default is the source's base name |

**📤 Output on stdout**

- Path of the archive that was created

**🚦 Exit codes**

- `0`: The backup was taken
- `1`: The source does not exist, or the archive could not be written


---

### `dybatpho::backup_list`

List a directory's backups, newest first.

**🧪 Example**

```bash
dybatpho::backup_list /var/backups nginx
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Directory holding the backups |
| `$2` | string | Optional backup name to match, default is every name |

**📤 Output on stdout**

- One archive path per line, newest first

**🚦 Exit codes**

- `0`: The listing was printed, empty when there is nothing to list


---

### `dybatpho::backup_latest`

Print the most recent backup in a directory.

**🧪 Example**

```bash
dybatpho::backup_restore "$(dybatpho::backup_latest /var/backups nginx)" /etc
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Directory holding the backups |
| `$2` | string | Optional backup name to match, default is every name |

**📤 Output on stdout**

- Path of the newest archive

**🚦 Exit codes**

- `0`: A backup was found
- `1`: The directory holds no backup


---

### `dybatpho::backup_verify`

Check a backup against its checksum sidecar.
A backup with no sidecar cannot be checked, which is reported rather than
passed, because "nothing to compare" is not the same answer as "matches".

**🧪 Example**

```bash
dybatpho::backup_verify "${archive}" || dybatpho::die "Corrupted backup"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backup archive path |

**🚦 Exit codes**

- `0`: The archive matches its sidecar
- `1`: The archive is missing, has no sidecar, or does not match it


---

### `dybatpho::backup_restore`

Restore a backup into a target directory.
The checksum is verified first, and the extraction goes through
`dybatpho::safe_extract`, so an archive whose entries would land outside
the target is refused and an overwrite is confirmed.

**🧪 Example**

```bash
dybatpho::backup_restore --force "${archive}" /etc/nginx
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip the overwrite confirmation |
| `$2` | string | Backup archive path |
| `$3` | string | Target directory, created when missing |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, `safe_extract` reports instead of extracting |

**🚦 Exit codes**

- `0`: The backup was restored
- `1`: The archive fails its checksum, the overwrite is declined, or an entry escapes the target


---

### `dybatpho::backup_prune`

Delete the backups a retention policy does not keep.
A backup survives when **any** policy keeps it, so asking for both
`--keep-count` and `--keep-days` keeps more rather than less: a retention
rule that deletes more than the operator expected is the expensive
direction to be wrong in.

`--keep-count` counts from the newest by name, which is the order the
backups were taken. `--keep-days` reads how old the file on disk is, so a
backup copied in from elsewhere is as old as the copy.

**🧪 Example**

```bash
dybatpho::backup_prune --keep-count 7 --name nginx /var/backups
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Options, in any order |
| `$@` | string | Directory holding the backups, after the options |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report what would be removed instead of removing it |

**📤 Output on stdout**

- Nothing; the paths it would remove are reported by `safe_rm` under `DRY_RUN`

**🚦 Exit codes**

- `0`: The pruning finished, or nothing needed removing
- `1`: No retention policy was given, an option is malformed, or the removal was declined
