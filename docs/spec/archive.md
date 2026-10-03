# Feature Specification: Archive Utilities

**Feature Branch**: `[reverse-spec-archive]`
**Status**: Implemented
**Input**: Existing source analysis: `src/archive.sh`, `docs/archive.md`, `test/archive.bats`, and `example/archive_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts regularly need to package files, inspect archive contents, and extract artifacts from build or release workflows, but repeating raw `tar`, `zip`, `unzip`, `xz`, `bzip2`, and `zstd` command lines makes scripts noisy and inconsistent.

## Business Value *(mandatory)*

- Centralize common archive workflows behind reusable helpers.
- Keep automation scripts readable when they package or unpack artifacts.
- Reduce repetitive flag selection across supported archive formats.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create archives from files or directories (Priority: P1)

As a script author, I want to create tar-based, zip, and single-file compressed archives from a path so that packaging steps stay readable.

**Independent Test**: Create archives for supported output extensions and verify the helper dispatches to the correct backend command.

**Acceptance Scenarios**:

1. **Given** a source directory and a `.tar.gz` output path, **When** the create helper runs, **Then** it invokes `tar` with gzip flags
2. **Given** a source directory and a `.zip` output path, **When** the create helper runs, **Then** it invokes `zip` with recursive quiet flags
3. **Given** a source file and a `.xz`, `.bz2`, or `.zst` output path, **When** the create helper runs, **Then** it invokes the matching single-file compressor

---

### User Story 2 - Extract archives consistently (Priority: P1)

As a maintainer, I want one helper for extraction so that automation can unpack supported archive formats without repeating backend-specific flags, including optional path stripping for nested archives.

**Independent Test**: Extract tar and zip archives into a target directory and verify the helper selects the correct command.

**Acceptance Scenarios**:

1. **Given** a `.tar.gz` archive, **When** the extract helper runs, **Then** it extracts through `tar -xzf`
2. **Given** a `.zip` archive, **When** the extract helper runs, **Then** it extracts through `unzip -q`
3. **Given** a strip-components value for a tar or zip archive, **When** the extract helper runs, **Then** leading path segments are removed from extracted entries

---

### User Story 3 - Inspect archive contents (Priority: P2)

As a script author, I want to list archive contents before extraction so that validation and debugging steps stay lightweight, even for single-file compressed outputs.

**Independent Test**: List tar and zip archives and verify the helper returns one entry per line.

**Acceptance Scenarios**:

1. **Given** a `.tar` archive, **When** the list helper runs, **Then** it prints the output from `tar -tf`
2. **Given** a `.zip` archive, **When** the list helper runs, **Then** it prints the output from `unzip -Z1`
3. **Given** a single-file compressed archive, **When** the list helper runs, **Then** it prints the decompressed output file name inferred from the archive name

### Example Workflow

```bash
# Pack a build directory, inspect it, then restore it elsewhere.
dybatpho::archive_create dist/ release.tar.gz
dybatpho::archive_list release.tar.gz

mkdir -p /srv/app
dybatpho::archive_extract release.tar.gz /srv/app 1
```

## Edge Cases

- The source path does not exist or a single-file compressor receives a
  directory.
- The output or input extension is unsupported.
- The extraction destination does not exist.
- A non-negative strip-components count is supplied for tar or zip content.
- A non-zero strip-components count is supplied for a single-file compressed
  archive, which is rejected.
- An archive contains entries that become empty after path stripping.
- A script loads `archive` alone, without the `safety` module that offers the
  guarded `safe_extract`.
- An archive cannot be listed: it is corrupt or truncated, or it is a zip and
  `unzip` is not installed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a helper that creates supported archives from a file or directory.
- **FR-002**: The create helper MUST support `.tar`, `.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tbz2`, `.tbz`, `.tar.zst`, `.zip`, `.gz`, `.xz`, `.bz2`, and `.zst` output names.
- **FR-003**: The module MUST provide a helper that extracts supported archives into a target directory.
- **FR-004**: The extract helper MUST create the target directory when needed.
- **FR-005**: The module MUST provide a helper that lists archive contents without extracting them.
- **FR-006**: The extract helper MUST support a strip-components count for tar-based archives and zip archives.
- **FR-007**: Single-file compressed outputs MUST only accept file sources for archive creation.
- **FR-008**: The module MUST fail clearly for unsupported archive extensions.
- **FR-009**: The module MUST expose an inspection helper
  (`archive_unsafe_entries`) that lists archive entries which would escape the
  extraction directory, and a predicate (`archive_is_safe`) that fails when an
  archive contains at least one of them. An entry is unsafe when
  it is absolute, equal to `..`, prefixed by `../`, traverses through `/../`,
  uses backslash separators around a traversal, or carries a Windows drive
  letter. Guarded extraction lives in `safety.md`.
- **FR-010**: Loading `archive` MUST NOT load `safety`; every archive helper
  MUST work with the core modules alone.
- **FR-011**: `archive_unsafe_entries` and `archive_is_safe` MUST fail, with an
  error on stderr and a non-zero status other than `0`, when the archive cannot
  be listed; an unlistable archive MUST NOT be reported as safe.

### Key Entities *(include if feature involves data)*

- **Archive Path**: A file path whose extension determines the archive backend and flags.
- **Source Path**: The file or directory packaged into an archive.
- **Destination Directory**: The directory receiving extracted archive contents.
- **Unsafe Entry**: An archive member whose name would be written outside the
  destination directory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can package, inspect, and extract common archive formats without embedding backend-specific flags.
- **SC-002**: Archive workflows stay readable across build, backup, and release automation.
- **SC-003**: An archive can be checked for path-traversal entries before it is
  extracted.

## Integration Tests *(mandatory)*

- **IT-001**: Create a `.tar.gz` archive from a source directory.
- **IT-002**: Create a `.tar.xz` or `.tar.zst` archive from a source directory.
- **IT-003**: Create `.gz`, `.xz`, `.bz2`, and `.zst` outputs from a single source file.
- **IT-004**: Extract a tar archive into a destination directory with optional strip-components.
- **IT-005**: Extract a zip archive into a destination directory with optional strip-components.
- **IT-006**: Extract a single-file compressed archive into a destination directory.
- **IT-007**: List supported tar, zip, and single-file compressed archives.
- **IT-008**: Reject unsupported archive extensions and invalid strip behavior.
- **IT-009**: Report the traversal entries of a hostile archive with
  `archive_unsafe_entries`, and confirm `archive_is_safe` accepts a benign one.
- **IT-010**: In a child shell that loaded only `archive`, create, check, and
  extract an archive while `safety` stays unloaded.
- **IT-011**: Refuse a corrupt archive in both `archive_unsafe_entries` and
  `archive_is_safe`, with an error naming it.

## Acceptance Criteria *(mandatory)*

1. Output-oriented helpers are suitable for command substitution and shell control flow.
2. Format detection is driven by archive file extension to keep the API small and predictable.
