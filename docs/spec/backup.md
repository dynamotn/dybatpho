# Feature Specification: Backup and Retention

**Feature Branch**: `[spec-backup]`
**Status**: Implemented
**Input**: Existing source analysis: `src/backup.sh`, `docs/backup.md`, `test/backup.bats`, and `example/backup_ops.sh`

## Problem Statement *(mandatory)*

`archive.sh` creates, extracts and lists archives, but knows nothing about a backup *policy*. Scripts that need "snapshot this, keep the last N, delete the rest" — log rotation, a config snapshot before a risky change, a local database dump — write the retention loop by hand every time, and get the same thing wrong: what exactly counts as "the last N". Two further failures go unnoticed until a restore: a run killed halfway leaves a truncated archive that the next listing counts as a good backup, and nothing checks that the bytes on disk are still the bytes that were written.

## Business Value *(mandatory)*

- One retention implementation, instead of an off-by-one in each script that needs one.
- A backup is either complete or absent, never half-written and mistaken for complete.
- A restore can tell a good archive from a corrupted one before it overwrites anything.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Snapshot something before changing it (Priority: P1)

As a script author, I want a timestamped archive written safely so that a snapshot taken before a risky change is either there in full or not there at all.

**Independent Test**: Take a backup of a directory and verify the archive, its checksum sidecar, and the timestamp in its name.

**Acceptance Scenarios**:

1. **Given** a source and a destination, **When** a backup is taken, **Then** a timestamped archive and a checksum sidecar are written and the archive path is printed
2. **Given** an archiver that fails, **When** a backup is attempted, **Then** nothing is left in the destination
3. **Given** a destination that does not exist, **When** a backup is taken, **Then** the directory is created
4. **Given** two backups of the same source within one second, **When** the second is taken, **Then** it gets its own name and the first survives
5. **Given** no name, **When** a backup is taken, **Then** it is named after the source's base name

---

### User Story 2 - Find the backup to restore (Priority: P1)

As an operator, I want the backups listed newest first and the most recent one resolved by name, so that a restore script can always reach for the last good one.

**Independent Test**: List a directory holding several backups and verify the order and the resolved latest.

**Acceptance Scenarios**:

1. **Given** several backups, **When** they are listed, **Then** they come back newest first
2. **Given** a name, **When** the listing is filtered, **Then** only that name's backups are returned
3. **Given** a half-written archive in the directory, **When** the backups are listed, **Then** it is not among them
4. **Given** a directory with no backups, **When** the latest is requested, **Then** the call reports that there is none

---

### User Story 3 - Restore what was backed up (Priority: P1)

As an operator, I want a restore to check the archive first and to refuse an archive that would write outside the target, so that a corrupted or hostile backup cannot damage the system it is restored onto.

**Independent Test**: Restore a good archive and verify the files, then attempt a corrupted one and verify nothing is written.

**Acceptance Scenarios**:

1. **Given** an intact archive, **When** it is restored, **Then** its files appear under the target
2. **Given** an archive that fails its checksum, **When** a restore is attempted, **Then** nothing is extracted and the mismatch is reported
3. **Given** an archive with no sidecar, **When** it is verified, **Then** it is reported rather than passed
4. **Given** an existing file under the target, **When** a restore is not forced, **Then** the overwrite is confirmed first

---

### User Story 4 - Keep the disk from filling up (Priority: P1)

As an operator, I want a retention policy applied to a backup directory so that old snapshots are removed on a rule rather than by hand.

**Independent Test**: Apply each policy to a planted set of backups and verify which survive.

**Acceptance Scenarios**:

1. **Given** `--keep-count N`, **When** the directory is pruned, **Then** the newest N backups survive
2. **Given** `--keep-days N`, **When** the directory is pruned, **Then** the backups younger than N days survive
3. **Given** both policies, **When** the directory is pruned, **Then** a backup survives when either policy keeps it
4. **Given** no policy, **When** a prune is attempted, **Then** it is refused and nothing is deleted
5. **Given** `DRY_RUN`, **When** the directory is pruned, **Then** what would be removed is reported and nothing is deleted
6. **Given** a pruned backup, **When** it is removed, **Then** its checksum sidecar goes with it

---

### User Story 5 - See what changed since a backup (Priority: P2)

As an operator, I want to compare two backups, or a backup with the live data, so that I know what a restore would undo or what changed between two snapshots before I act on either.

**Independent Test**: Take a backup, change the source, take another, and compare the two backups and each with the live source.

**Acceptance Scenarios**:

1. **Given** two backups of a directory, **When** they are compared, **Then** each added, removed, rewritten and retyped entry is reported as the tree comparison reports it, and the call reports a difference
2. **Given** a backup and the unchanged live source, **When** they are compared, **Then** nothing is printed and the call succeeds
3. **Given** a backup and a copy of its source restored under another name, **When** they are compared, **Then** the source's name is not counted as a difference
4. **Given** a backup of a single file, **When** it is compared with the live file, **Then** a change to the file is reported under its name
5. **Given** `--summary` or `--null`, **When** two sides are compared, **Then** the option reaches the tree comparison
6. **Given** a backup that fails its checksum, has no sidecar, or holds an entry escaping the scratch directory, or a side that does not exist, **When** a comparison is asked for, **Then** it stops with exit code 2 without reading the backup

---

### User Story 6 - Keep many snapshots for the price of one (Priority: P2)

As an operator, I want nightly snapshots that store only what changed since the last one, so that a long history of a large tree fits on the disk and each snapshot can still be read, compared and restored on its own.

**Independent Test**: Take two incremental snapshots of a tree with one file changed in between, with and without `rsync`, and verify the unchanged files are hard links to the earlier snapshot while each snapshot verifies, compares, restores and prunes independently.

**Acceptance Scenarios**:

1. **Given** `--incremental`, **When** a backup is taken, **Then** a `<name>-<UTC timestamp>.snapshot` directory holding a copy of the source is written atomically, with a sidecar beside it
2. **Given** an earlier snapshot of the same name, **When** another is taken, **Then** every file whose content and mode are unchanged is a hard link to the earlier copy, and every other file is a new copy
3. **Given** `rsync` is not installed, **When** a snapshot is taken, **Then** the source is walked in Bash with the same result, keeping links, file modes and directory modes and skipping special files
4. **Given** a snapshot, **When** a file inside it is added, removed or changed, **Then** verification reports it
5. **Given** a directory holding archives and snapshots, **When** it is listed, **Then** both appear together, newest first
6. **Given** a snapshot, **When** it is restored, **Then** its entry is copied into the target as plain files, after confirming an overwrite unless forced, and `DRY_RUN` reports the copy
7. **Given** two snapshots sharing files, **When** one is pruned, **Then** the other still verifies and holds every file
8. **Given** a file that cannot be read, **When** a snapshot is taken, **Then** the script stops and nothing is left in the destination

### Example Workflow

```bash
. dybatpho/init.sh --modules backup

archive="$(dybatpho::backup_create /etc/nginx /var/backups nginx)"
dybatpho::backup_verify "${archive}" || dybatpho::die "The backup is not readable"

# Before a risky change, and after it, keep a week of history.
dybatpho::backup_prune --keep-count 7 --name nginx --force /var/backups

# What a restore would undo, before running it.
dybatpho::backup_diff "$(dybatpho::backup_latest /var/backups nginx)" /etc/nginx || true

# A nightly history of a large tree, each night costing only what changed.
dybatpho::backup_create --incremental /srv/www /var/backups www

# Roll back to the last good snapshot.
dybatpho::backup_restore --force "$(dybatpho::backup_latest /var/backups nginx)" /etc
```

## Edge Cases

- The source does not exist, or the destination has to be created.
- Two backups are taken within the same second.
- Ten or more backups are taken within the same second, so a suffix of `-10` sits beside `-2`, and the caller's collation orders `-1.` before or after `.`.
- The archiver fails partway through.
- A backup has no checksum sidecar, or does not match the one it has.
- The directory holds no backups, or holds backups of several names.
- A retention option is missing its value or is not a number.
- The directory is given after an end-of-options marker.
- A comparison side is a backup, a live directory, a live file, or a path that does not exist.
- A backup to compare fails its checksum, has no sidecar, or holds an entry that escapes.
- A live copy of the source sits under a different name from the one the backup recorded.
- An incremental snapshot is taken with or without `rsync`, of a directory or of a single file, with no earlier snapshot, or twice in one second.
- A source holds a symbolic link, a FIFO, a read-only directory, or a file that cannot be read.
- A file's content is unchanged but its mode is not.
- A snapshot is tampered with after it was taken, or holds more than one entry.
- A file with the snapshot suffix, or a link to a snapshot, sits among the backups.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A backup MUST be written under a temporary name in the destination and renamed into place, so an interrupted run leaves nothing that a listing counts as a backup.
- **FR-002**: The temporary name MUST be hidden and MUST carry the configured extension, so listings skip it and the archiver can still read the format.
- **FR-003**: A failed archive creation MUST leave no file behind and MUST stop the script.
- **FR-004**: A backup MUST be named `<name>-<UTC timestamp>.<extension>`, defaulting the name to the source's base name.
- **FR-005**: The timestamp MUST be UTC, so sorting names is sorting by age across a daylight-saving change.
- **FR-006**: A name already taken MUST NOT be overwritten; the new backup MUST take a distinct name.
- **FR-007**: A checksum sidecar MUST be written beside every backup.
- **FR-008**: Verification MUST compare the archive against its sidecar, and MUST report rather than pass when the archive or the sidecar is missing.
- **FR-009**: Listing MUST return backups newest first, MUST filter by name when one is given, and MUST exclude a half-written archive.
- **FR-010**: Resolving the latest backup MUST return a non-zero status when there is none.
- **FR-011**: A restore MUST verify the archive before extracting, and MUST extract through the guard that refuses an entry escaping the target.
- **FR-012**: A restore MUST confirm an overwrite unless it is forced.
- **FR-013**: Pruning MUST support `--keep-count`, `--keep-days`, `--name` and `--force`, and MUST reject an unknown option or a non-numeric count.
- **FR-014**: Pruning MUST refuse to run when no retention policy is given.
- **FR-015**: A backup MUST survive pruning when any given policy keeps it.
- **FR-016**: `--keep-count` MUST count from the newest by name; `--keep-days` MUST read the age of the file on disk.
- **FR-017**: Pruning MUST remove a pruned backup's sidecar with it.
- **FR-018**: Pruning MUST honor `DRY_RUN` and MUST delete through the guarded removal helper.
- **FR-019**: The archive extension and the checksum algorithm MUST be configurable.
- **FR-020**: A comparison MUST accept a backup, a live directory or a live file on either side, treating a path that ends in the backup extension as a backup.
- **FR-021**: A backup MUST be verified against its sidecar, and checked for entries that escape, before it is extracted for a comparison, and a failure MUST stop with exit code 2.
- **FR-022**: A comparison MUST extract into a temporary directory removed on exit and MUST NOT write to the destination or the source.
- **FR-023**: A directory backup MUST be compared from inside the entry it recorded, so the source's own name is not a difference; a single-file backup and a live file MUST line up by file name.
- **FR-024**: A comparison MUST report through `dybatpho::diff_dir`, passing `--summary` and `--null` through and returning its exit code.
- **FR-025**: `--incremental` MUST write a directory named `<name>-<UTC timestamp>.snapshot` under a hidden temporary name and rename it into place, MUST take a distinct name when one is taken, and MUST stop the script leaving nothing behind when the copy fails.
- **FR-026**: A snapshot MUST hard-link each regular file whose content and mode match the newest earlier snapshot of the same name, MUST copy every other file with its mode and times, MUST recreate symbolic links, MUST give directories the source's mode, and MUST skip special files.
- **FR-027**: A snapshot MUST use `rsync --link-dest` when it is installed and MUST produce the same tree without it.
- **FR-028**: A snapshot's sidecar MUST record a checksum over every entry's path, kind, and content checksum or link target, and verification MUST recompute it.
- **FR-029**: Listing, resolving the latest backup, and pruning MUST treat archives and snapshot directories alike, in the order they were taken, and MUST NOT count a file or a link that carries the snapshot suffix.
- **FR-030**: Restoring a snapshot MUST verify it, MUST copy its one entry into the target as plain files, MUST confirm an overwrite unless forced, MUST honor `DRY_RUN`, and MUST stop when the snapshot does not hold exactly one entry.
- **FR-031**: Pruning a snapshot MUST remove its directory and sidecar without affecting a file another snapshot links.
- **FR-032**: A comparison MUST accept a snapshot on either side, verified before it is read.
- **FR-033**: Listing, resolving the latest and pruning MUST order backups by name, then UTC stamp, then same-second suffix compared as a number, archives and snapshots together, independently of the caller's collation.

### Key Entities *(include if feature involves data)*

- **Backup**: A timestamped archive of one source, in a destination directory.
- **Sidecar**: The checksum file written beside a backup, named after its algorithm.
- **Snapshot**: A timestamped directory copy of one source whose unchanged files are hard links shared with earlier snapshots.
- **Retention Policy**: `--keep-count`, `--keep-days`, or both, deciding which backups survive.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script keeps a bounded history of snapshots without writing a retention loop.
- **SC-002**: An interrupted backup run never leaves a file that a later restore would trust.
- **SC-003**: A corrupted archive is caught before it overwrites anything.
- **SC-004**: A retention policy can be reviewed with `DRY_RUN` before it runs unattended.
- **SC-005**: A history of snapshots of a tree costs the disk one copy plus what changed between them.

## Integration Tests *(mandatory)*

- **IT-001**: Take a backup and verify the archive, the sidecar and the name.
- **IT-002**: Default the name to the source's base name, and create a missing destination.
- **IT-003**: Refuse a source that is not there.
- **IT-004**: Leave nothing behind when the archiver fails.
- **IT-005**: Take two backups under a frozen clock and verify both survive under distinct names.
- **IT-006**: Verify an intact backup, and report a corrupted one.
- **IT-007**: Report a backup with no sidecar, and one that is not there.
- **IT-008**: List backups newest first, filtered by name, excluding a half-written archive.
- **IT-009**: Resolve the latest backup, and report an empty directory.
- **IT-010**: Restore an archive, and refuse a corrupted one without writing.
- **IT-011**: Confirm an overwrite on an unforced restore.
- **IT-012**: Prune by `--keep-count`, by `--keep-days`, and by both together.
- **IT-013**: Remove a pruned backup's sidecar with it.
- **IT-014**: Report under `DRY_RUN` without deleting.
- **IT-015**: Refuse a prune with no policy, a malformed option, and a missing directory.
- **IT-016**: Accept the directory after an end-of-options marker.
- **IT-017**: Prune a directory with nothing to remove.
- **IT-018**: Configure the extension and the checksum algorithm.
- **IT-019**: Compare two backups record by record and as a summary.
- **IT-020**: Compare a backup with the unchanged and the changed live source, and with a copy under another name.
- **IT-021**: Compare a single-file backup with the live file.
- **IT-022**: Pass `--null` through to the tree comparison.
- **IT-023**: Stop with exit code 2 for a backup that fails its checksum, one without a sidecar, and a missing side.
- **IT-024**: Stop with exit code 2 for a backup holding an entry that escapes.
- **IT-025**: Write a snapshot directory and its sidecar, leaving nothing half-written.
- **IT-026**: Hard-link unchanged files and copy changed ones, with `rsync`.
- **IT-027**: Do the same without `rsync`, keeping links, skipping a FIFO, filling a read-only directory, and copying a file whose mode changed.
- **IT-028**: Keep a read-only directory's mode without `rsync`.
- **IT-029**: Snapshot a single file and link it the next time.
- **IT-030**: Stop and leave nothing behind when a file cannot be read.
- **IT-031**: Verify a snapshot's tree, and report a file added, a file changed, and a missing sidecar.
- **IT-032**: List archives and snapshots together, ignoring a file and a link with the suffix, and resolve the latest.
- **IT-033**: Restore a snapshot as plain files, refuse an unconfirmed overwrite, and overwrite when forced.
- **IT-034**: Restore a single-file snapshot, and report it under `DRY_RUN`.
- **IT-035**: Refuse a tampered snapshot, and one holding more than one entry.
- **IT-036**: Prune a snapshot while the one sharing its files still verifies.
- **IT-037**: Compare snapshots with each other, with the live source and with an archive, and refuse a tampered one or one without a sidecar.
- **IT-038**: Take two snapshots in the same second under distinct names.
- **IT-039**: List archives and a snapshot taken in the same second newest first by suffix, `-10` before `-2` and `-1` before the unsuffixed name, under C collation and the session's own.

## Acceptance Criteria *(mandatory)*

1. Destinations are local paths; pushing a backup elsewhere stays with the caller.
2. Every deletion goes through the guarded removal helper, so confirmation and `DRY_RUN` behave as they do everywhere else in the library.
3. Integrity is checked with a checksum sidecar rather than a test extraction, which would double the disk and time a large backup costs; the atomic rename is what rules out the half-written file the test extraction would be looking for.
4. A comparison never extracts a backup it has not verified, and never extracts outside a scratch directory of its own.
5. A snapshot is a plain directory tree, readable without this library; the hard links are what make it cheap, and nothing but the sidecar is needed to trust it.
