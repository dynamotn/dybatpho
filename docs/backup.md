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

`--incremental` takes a snapshot directory instead of an archive, in which
every file unchanged since the previous snapshot is a hard link to it, so a
long history of a large tree costs one copy plus what changed. Snapshots
are listed, verified, restored, compared and pruned like archives.

`dybatpho::backup_diff` answers what a restore would undo: it compares two
backups, or a backup and the live data, through `dybatpho::diff_dir`,
extracting each verified backup into a scratch directory first. That
comparison is the `diff` module's, which this one does not load: a script
that compares backups loads `diff` as well.

### 🌍 Environment

| Variable | Type | Description |
| --- | --- | --- |
| **`DYBATPHO_BACKUP_EXTENSION`** | string | Archive extension, default is `tar.gz`; `archive.sh` reads the format from it |
| **`DYBATPHO_BACKUP_CHECKSUM_ALGORITHM`** | string | Algorithm for the sidecar, default is `sha256` |
| **`DYBATPHO_BACKUP_EXTENSION`** | string | Extension every backup is written with, default is `tar.gz` |
| **`DYBATPHO_BACKUP_CHECKSUM_ALGORITHM`** | string | Checksum algorithm for the sidecar, default is `sha256` |

### 🚀 Highlights

- [`dybatpho::backup_create`](#dybatphobackup_create) — Take a timestamped backup of a file or directory. The archive is written under a temporary name in the destination and renamed into place, so nothing half-written is ever left looking complete. A checksum sidecar is written beside it. With `--incremental`, the backup is a directory named `<name>-<UTC timestamp>.snapshot` instead of an archive: a plain copy of the source in which every file unchanged since the newest earlier snapshot of the same name is a hard link to that snapshot's copy, so a nightly run costs only what changed. `rsync --link-dest` is used when installed, and a walk in Bash otherwise. Pruning a snapshot never touches another one: a hard-linked file lives on until the last snapshot naming it is removed. Files are shared, so a snapshot is read and restored, never edited in place. Special files are skipped, and the sidecar holds a fingerprint of the tree -- each entry's path, kind, and checksum or link target.
- [`dybatpho::backup_list`](#dybatphobackup_list) — List a directory's backups, newest first. Archives and incremental snapshots are listed together, in the order they were taken.
- [`dybatpho::backup_latest`](#dybatphobackup_latest) — Print the most recent backup in a directory.
- [`dybatpho::backup_verify`](#dybatphobackup_verify) — Check a backup against its checksum sidecar. A backup with no sidecar cannot be checked, which is reported rather than passed, because "nothing to compare" is not the same answer as "matches". An incremental snapshot is checked by recomputing the fingerprint of its tree, so a file changed, added, or removed inside it is caught.
- [`dybatpho::backup_restore`](#dybatphobackup_restore) — Restore a backup into a target directory. The checksum is verified first, and the extraction goes through `dybatpho::safe_extract`, so an archive whose entries would land outside the target is refused and an overwrite is confirmed. A snapshot is restored the same way: verified, then its one entry is copied into the target -- `<target>/<source name>`, as an archive extracts -- after confirming when that entry already exists there. The copy holds plain files, so editing it never reaches the snapshot.
- [`dybatpho::backup_prune`](#dybatphobackup_prune) — Delete the backups a retention policy does not keep. A backup survives when **any** policy keeps it, so asking for both `--keep-count` and `--keep-days` keeps more rather than less: a retention rule that deletes more than the operator expected is the expensive direction to be wrong in. `--keep-count` counts from the newest by name, which is the order the backups were taken. `--keep-days` reads how old the file on disk is, so a backup copied in from elsewhere is as old as the copy.
- [`dybatpho::backup_diff`](#dybatphobackup_diff) — Show what changed between two backups, or between a backup and the live data it was taken from. Each side is a backup archive, an incremental snapshot, or a live file or directory. A backup is checked against its sidecar before anything is read from it, and an archive is extracted into a temporary directory that is removed when the shell exits; nothing in the destination or the source is written. The two sides are then compared with `dybatpho::diff_dir`, so the records, the summary and the exit code are the ones it prints: `+` for what the second side added, `-` for what it no longer has, `~` for a rewritten file, `!` for a change of kind. A backup holds its source under the source's own name, and that name is not compared: a directory backup is compared from inside it, so the older backup of `/etc/nginx` lines up with the live `/etc/nginx` or with a copy restored somewhere else.

<a id="see-also"></a>
## 🔗 See also

- [example/backup_ops.sh](../example/backup_ops.sh)

<a id="tips"></a>
## 💡 Tips

- Load `diff` as well to compare backups: `--modules backup diff`
- Destinations are local paths; pushing a backup to object storage or a network share stays with the caller
- A snapshot shares its unchanged files with other snapshots, so read and restore it, never edit inside it

<a id="reference"></a>
## 📚 Reference

### `dybatpho::backup_create`

Take a timestamped backup of a file or directory.
The archive is written under a temporary name in the destination and
renamed into place, so nothing half-written is ever left looking complete.
A checksum sidecar is written beside it.

With `--incremental`, the backup is a directory named
`<name>-<UTC timestamp>.snapshot` instead of an archive: a plain copy of
the source in which every file unchanged since the newest earlier snapshot
of the same name is a hard link to that snapshot's copy, so a nightly run
costs only what changed. `rsync --link-dest` is used when installed, and a
walk in Bash otherwise. Pruning a snapshot never touches another one: a
hard-linked file lives on until the last snapshot naming it is removed.
Files are shared, so a snapshot is read and restored, never edited in
place. Special files are skipped, and the sidecar holds a fingerprint of
the tree -- each entry's path, kind, and checksum or link target.

**🧪 Example**

```bash
archive="$(dybatpho::backup_create /etc/nginx /var/backups)"
snapshot="$(dybatpho::backup_create --incremental /srv/www /var/backups www)"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--incremental`/`-i` to take a hard-linked snapshot directory |
| `$2` | string | File or directory to back up |
| `$3` | string | Destination directory, created when missing |
| `$4` | string | Optional name for the backup, default is the source's base name |

**📤 Output on stdout**

- Path of the archive or snapshot that was created

**🚦 Exit codes**

- `0`: The backup was taken
- `1`: The source does not exist, or the backup could not be written


---

### `dybatpho::backup_list`

List a directory's backups, newest first.
Archives and incremental snapshots are listed together, in the order they
were taken.

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

- One archive or snapshot path per line, newest first

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

- Path of the newest archive or snapshot

**🚦 Exit codes**

- `0`: A backup was found
- `1`: The directory holds no backup


---

### `dybatpho::backup_verify`

Check a backup against its checksum sidecar.
A backup with no sidecar cannot be checked, which is reported rather than
passed, because "nothing to compare" is not the same answer as "matches".
An incremental snapshot is checked by recomputing the fingerprint of its
tree, so a file changed, added, or removed inside it is caught.

**🧪 Example**

```bash
dybatpho::backup_verify "${archive}" || dybatpho::die "Corrupted backup"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Backup archive or snapshot path |

**🚦 Exit codes**

- `0`: The archive matches its sidecar
- `1`: The backup is missing, has no sidecar, or does not match it


---

### `dybatpho::backup_restore`

Restore a backup into a target directory.
The checksum is verified first, and the extraction goes through
`dybatpho::safe_extract`, so an archive whose entries would land outside
the target is refused and an overwrite is confirmed.

A snapshot is restored the same way: verified, then its one entry is
copied into the target -- `<target>/<source name>`, as an archive
extracts -- after confirming when that entry already exists there. The
copy holds plain files, so editing it never reaches the snapshot.

**🧪 Example**

```bash
dybatpho::backup_restore --force "${archive}" /etc/nginx
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Option `--force`/`-f` to skip the overwrite confirmation |
| `$2` | string | Backup archive or snapshot path |
| `$3` | string | Target directory, created when missing |

**🌍 Environment variables**

| Variable | Type | Description |
| --- | --- | --- |
| **`DRY_RUN`** | string | When true-like, report the extraction or copy instead of performing it |

**🚦 Exit codes**

- `0`: The backup was restored
- `1`: The backup fails its checksum, the overwrite is declined, or an entry escapes the target


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


---

### `dybatpho::backup_diff`

Show what changed between two backups, or between a backup and
the live data it was taken from.
Each side is a backup archive, an incremental snapshot, or a live file or
directory. A backup is checked against its sidecar before anything is read
from it, and an archive is extracted into a temporary directory that is
removed when the shell exits; nothing in the destination or the source is
written. The two sides are then
compared with `dybatpho::diff_dir`, so the records, the summary and the
exit code are the ones it prints: `+` for what the second side added, `-`
for what it no longer has, `~` for a rewritten file, `!` for a change of
kind.

A backup holds its source under the source's own name, and that name is
not compared: a directory backup is compared from inside it, so the older
backup of `/etc/nginx` lines up with the live `/etc/nginx` or with a copy
restored somewhere else.

**🧪 Example**

```bash
dybatpho::backup_diff "$(dybatpho::backup_latest /var/backups nginx)" /etc/nginx
mapfile -t backups < <(dybatpho::backup_list /var/backups nginx)
dybatpho::backup_diff --summary "${backups[1]}" "${backups[0]}"
```

**🧾 Arguments**

| Name | Type | Description |
| --- | --- | --- |
| `$1` | string | Options, then the older side |
| `$2` | string | The newer side |

**📤 Output on stdout**

- The records or the summary `dybatpho::diff_dir` prints

**🚦 Exit codes**

- `0`: The two sides hold the same entries with the same content
- `1`: They differ
- `2`: A side is missing, fails its checksum, or holds an entry that escapes
- `1`: Stop the script when the `diff` module is not loaded
