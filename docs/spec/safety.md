# Feature Specification: Guards for Destructive Operations

**Feature Branch**: `[reverse-spec-safety]`
**Status**: Implemented
**Input**: Existing source analysis: `src/safety.sh`, `src/archive.sh`, `docs/safety.md`, `test/safety.bats`, `test/archive.bats`, and `example/safety_ops.sh`

## Problem Statement *(mandatory)*

The operations that break a machine are the ones scripts run without thinking:
`rm -rf "${dir}"` where `dir` is empty, a redirect that silently replaces a
config file, `tar -x` on a release tarball whose entries escape the destination,
and a `systemctl` call nobody was asked about. Each one is a single line, each
one is irreversible, and Bash offers no guard rails. Authors either add ad-hoc
checks in every script, forget them, or rely on the operator noticing in time.

## Business Value *(mandatory)*

- Make irreversible operations explicit: they run unattended only when the
  author passes `--force`, and otherwise ask on a terminal.
- Stop a bad path (empty, `/`, `${HOME}`, a system directory) before it reaches
  `rm`, `cp`, or `mv`.
- Confine a whole script to a working directory with one environment variable.
- Refuse hostile archives that write outside the extraction directory.
- Give every guarded operation the same `DRY_RUN` rehearsal path.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove files without losing the machine (Priority: P1)

As a script author, I want deletions validated and confirmed so that a wrong
variable can't wipe a system directory or my home directory.

**Independent Test**: Call `safe_rm` with a protected path, with a directory and
no `--recursive`, and with a regular file, and verify only the last one is
removed after approval.

**Acceptance Scenarios**:

1. **Given** a non-interactive shell and no `--force`, **When** `safe_rm PATH`
   runs, **Then** it warns, removes nothing, and fails
2. **Given** `--force`, **When** `safe_rm PATH` runs, **Then** the path is
   removed without prompting
3. **Given** a directory target, **When** `safe_rm` runs without `--recursive`,
   **Then** the script stops with a diagnostic and the directory survives
4. **Given** a protected path such as `/` or `${HOME}`, **When** `safe_rm` runs
   with `--force`, **Then** the script still stops and nothing is removed

### User Story 2 - Replace a file on purpose (Priority: P1)

As a script author, I want to know when a write would destroy existing content,
and to keep a backup when it does.

**Independent Test**: Guard a write to a missing path, to an existing file
without approval, and to an existing file with `--force --backup`, and verify
the previous content survives as `.bak`.

**Acceptance Scenarios**:

1. **Given** the destination doesn't exist, **When** `safe_overwrite DEST` runs,
   **Then** it succeeds immediately and the caller may write
2. **Given** the destination exists and the run is unattended, **When**
   `safe_overwrite DEST` runs without `--force`, **Then** it warns and fails so
   the caller's write never happens
3. **Given** `--backup`, **When** the overwrite is approved, **Then** the current
   content is copied to `DEST.bak` before the caller writes
4. **Given** a destination directory, **When** `safe_copy SRC DIR` or
   `safe_move SRC DIR` runs, **Then** the guard applies to `DIR/<source name>`

### User Story 3 - Extract untrusted archives (Priority: P1)

As a release engineer, I want extraction to refuse archives whose entries escape
the destination, and to ask before replacing files that are already there.

**Independent Test**: Extract an archive containing `../victim.txt` and verify
nothing is written outside the destination, then extract a benign archive twice
and verify the second run needs approval.

**Acceptance Scenarios**:

1. **Given** an archive entry that is absolute, starts with `..`, or traverses
   through `/../`, **When** `safe_extract` runs, **Then** the script stops before
   any extractor runs
2. **Given** `strip-components` would still place an entry outside the
   destination, **When** `safe_extract` runs, **Then** it stops with the same
   diagnostic
3. **Given** entries that would replace existing files, **When** `safe_extract`
   runs without `--force` in a non-interactive shell, **Then** it warns, fails,
   and leaves the existing files untouched
4. **Given** a safe archive and a clean destination, **When** `safe_extract`
   runs, **Then** it extracts exactly like `archive_extract`

### User Story 4 - Change system state deliberately (Priority: P2)

As an operator, I want a described confirmation step before a script restarts a
service, installs a package, or edits machine state.

**Independent Test**: Run `safe_system` with and without `--force` and verify the
command runs only when approved, and only prints under `DRY_RUN`.

**Acceptance Scenarios**:

1. **Given** no `--force` in a non-interactive shell, **When** `safe_system
   DESCRIPTION -- COMMAND` runs, **Then** the command doesn't run and the skip is
   reported
2. **Given** `--force`, **When** it runs, **Then** the change is logged and the
   command runs with its exit code propagated
3. **Given** `DRY_RUN=true`, **When** it runs, **Then** the command is printed
   instead of executed

### User Story 5 - Confine a script to a working directory (Priority: P2)

As a script author, I want every guarded operation in my script restricted to a
scratch directory so a bad path can't reach the rest of the filesystem.

**Independent Test**: Set `DYBATPHO_SAFE_ROOTS` to a temporary directory and
verify a path inside it is accepted while a sibling path is rejected.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_SAFE_ROOTS` is set, **When** a guarded path resolves
   inside one of the roots, **Then** the operation proceeds
2. **Given** `DYBATPHO_SAFE_ROOTS` is set, **When** a guarded path resolves
   outside every root, **Then** the script stops naming the root list
3. **Given** `DYBATPHO_PROTECTED_PATHS` lists a directory, **When** it is used as
   a target, **Then** it is rejected like a built-in protected path

### Example Workflow

```bash
export DYBATPHO_SAFE_ROOTS="${workdir}"

# Ask before deleting, unless the caller passed --force.
dybatpho::safe_rm --recursive "${workdir}/cache"

# Keep the previous config as .bak, then write the new one.
dybatpho::safe_overwrite --force --backup "${config}"
printf '%s\n' "${rendered}" > "${config}"

# Reject a hostile release tarball instead of unpacking it.
dybatpho::safe_extract --force "${tarball}" "${workdir}/unpacked" 1

# Confirm a system change, with an explicit description.
dybatpho::safe_system "Restart nginx" -- systemctl restart nginx
```

## Edge Cases

- The target path is empty or only whitespace.
- The target path is `/`, a first-level system directory, or `${HOME}`.
- The target path is relative, or contains `.`/`..` segments that must be
  resolved before it is compared with the protected list.
- The target path doesn't exist, so a removal has nothing to do.
- The target is a dangling symlink, which must be removable without following
  it.
- The target is a directory and the caller didn't pass `--recursive`.
- A path begins with `-` and must be passed after a `--` separator.
- The destination of a copy or move is an existing directory, or its parent
  directories don't exist yet.
- An archive entry is absolute, is `..`, traverses through `/../`, uses
  backslash separators, or carries a Windows drive letter.
- `strip-components` is larger than the depth of an entry, so the entry expands
  to nothing.
- Symlink targets stored inside an archive aren't inspected, so untrusted
  archives should be extracted into a scratch directory.
- The shell has no terminal, so a confirmation can't be asked.
- `DRY_RUN` is enabled, so no operation may change the filesystem.
- `safe_extract` is called while the `archive` module it lists and extracts
  through is not loaded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `is_interactive` MUST detect a terminal on stdin, and MUST honor
  `DYBATPHO_INTERACTIVE` when it is set to a true or false value instead of
  `auto`.
- **FR-002**: `confirm` MUST return success without prompting when
  `DYBATPHO_FORCE` is enabled, MUST warn and fail in a non-interactive shell, and
  MUST otherwise accept only `y`/`yes` as approval.
- **FR-003**: `confirm` MUST apply its default answer, `no` unless given, to an
  empty reply, and MUST write the question to stderr.
- **FR-004**: `assert_safe_path` MUST reject an empty or whitespace-only path,
  MUST print the target as a normalized absolute path, and MUST resolve the path
  before any comparison.
- **FR-005**: `assert_safe_path` MUST reject `/`, the first-level system
  directories, `${HOME}`, and every entry of `DYBATPHO_PROTECTED_PATHS`.
- **FR-006**: When `DYBATPHO_SAFE_ROOTS` is set, `assert_safe_path` MUST reject
  any path that doesn't resolve inside one of its colon-separated roots.
- **FR-007**: Every guarded operation MUST validate its target through
  `assert_safe_path` before touching the filesystem.
- **FR-008**: `safe_rm` MUST accept `--force`/`-f`, `--recursive`/`-r`, and a
  `--` separator, MUST require at least one path, and MUST reject unknown
  options.
- **FR-009**: `safe_rm` MUST skip missing paths without failing, MUST remove a
  dangling symlink, and MUST refuse a directory unless `--recursive` is given.
- **FR-010**: `safe_rm` MUST confirm once for the whole set of resolved paths,
  and MUST remove nothing when the confirmation is declined.
- **FR-011**: `safe_overwrite` MUST succeed without prompting when the
  destination doesn't exist, MUST refuse a directory destination, and MUST
  require exactly one destination.
- **FR-012**: `safe_overwrite` MUST confirm before an existing file is replaced,
  and with `--backup` MUST copy the current content to `<destination>.bak`
  before returning success.
- **FR-013**: `safe_copy` and `safe_move` MUST require an existing source, MUST
  expand a directory destination to `<directory>/<source name>`, MUST apply the
  `safe_overwrite` guard to the resolved destination, and MUST create missing
  parent directories.
- **FR-014**: `safe_extract` MUST reuse the archive module's entry-safety
  validation rather than re-implementing it, so both modules agree on what
  counts as an escaping entry.
- **FR-015**: `safe_extract` MUST stop before extracting when any entry is
  unsafe, and MUST also stop when an entry, after `strip-components`, resolves
  outside the destination directory.
- **FR-016**: `safe_extract` MUST confirm when extraction would replace existing
  files, MUST leave them untouched when the confirmation is declined, and MUST
  otherwise delegate to `archive_extract`.
- **FR-017**: `safe_extract` MUST require an existing archive and a
  non-negative integer `strip-components`.
- **FR-018**: `safe_system` MUST require exactly one description and a command
  after a `--` separator, MUST confirm the change before running it, and MUST
  report a skipped change.
- **FR-019**: Every guarded operation MUST run its filesystem or system command
  through `dybatpho::dry_run`, so `DRY_RUN` prints the command instead of
  executing it.
- **FR-020**: `DYBATPHO_FORCE` MUST default to `false`, `DYBATPHO_INTERACTIVE`
  to `auto`, and `DYBATPHO_SAFE_ROOTS` and `DYBATPHO_PROTECTED_PATHS` to empty.
- **FR-021**: Every guarded operation MUST accept the short forms of its
  options (`-f`, `-r`, `-b`) and MUST treat every argument after `--` as a
  path, so a file whose name begins with a dash can still be operated on.
- **FR-022**: `safe_copy` and `safe_move` MUST forward `--backup` to the
  overwrite guard, and MUST reject unknown options like the other wrappers.
- **FR-023**: Loading `safety` MUST NOT load `archive`; `safe_extract` MUST
  stop with a message naming the `archive` module and how to load it when that
  module is not loaded, before it inspects the archive or the destination.

### Key Entities *(include if feature involves data)*

- **Guarded Path**: A target path, normalized to an absolute path and checked
  against the protected list and the safe roots.
- **Protected Path**: A path that guarded operations must never touch: `/`, the
  first-level system directories, `${HOME}`, and `DYBATPHO_PROTECTED_PATHS`.
- **Safe Root**: A directory listed in `DYBATPHO_SAFE_ROOTS` that guarded paths
  must stay inside.
- **Approval**: The outcome of `--force`, `DYBATPHO_FORCE`, or an interactive
  confirmation.
- **Unsafe Archive Entry**: An archive member whose name would write outside the
  extraction directory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A destructive operation can't run unattended unless the author
  passed `--force` or set `DYBATPHO_FORCE`.
- **SC-002**: No guarded operation touches `/`, a first-level system directory,
  or `${HOME}`, regardless of the flags used.
- **SC-003**: An archive with a traversal entry is rejected before any extractor
  writes to disk.
- **SC-004**: Setting `DYBATPHO_SAFE_ROOTS` confines every guarded operation in
  a script to those roots.
- **SC-005**: `DRY_RUN=true` produces a full rehearsal with no filesystem or
  system changes.

## Integration Tests *(mandatory)*

- **IT-001**: Verify `is_interactive` and `confirm` for forced, declined,
  default, and non-interactive answers.
- **IT-002**: Verify `assert_safe_path` normalizes relative paths and rejects
  empty, protected, and out-of-root paths.
- **IT-003**: Verify `safe_rm` removes an approved path, keeps a declined one,
  refuses a directory without `--recursive`, skips missing paths, and removes a
  dangling symlink.
- **IT-004**: Verify `safe_rm` rejects unknown options, requires a path, and
  accepts a `--` separator.
- **IT-005**: Verify `safe_overwrite` allows a missing destination, guards an
  existing one, writes a `.bak` copy, and refuses a directory.
- **IT-006**: Verify `safe_copy` copies into a directory and guards the second
  copy, and that `safe_move` creates missing parents and reports a missing
  source.
- **IT-007**: Verify the short option forms (`-f`, `-r`, `-b`), that `--backup`
  is forwarded from `safe_copy`/`safe_move` to the overwrite guard, that
  `safe_copy`/`safe_move` reject unknown options, and that everything after `--`
  is treated as a path.
- **IT-008**: Verify `safe_extract` extracts a safe archive, supports
  `strip-components`, and rejects a traversal archive without writing outside
  the destination.
- **IT-009**: Verify `safe_extract` confirms before replacing existing files and
  validates its archive, strip-components, and option arguments.
- **IT-010**: Verify `safe_system` runs an approved command, skips a declined
  one, honors `DRY_RUN`, and validates its description, separator, and options.
- **IT-011**: Verify `safe_rm` under `DRY_RUN` prints the `rm` command and keeps
  the file.
- **IT-012**: In a child shell that loaded only `safety`, verify `safe_extract`
  stops with the message naming `archive` before looking at the archive, and
  extracts once `archive` is loaded.

## Acceptance Criteria *(mandatory)*

1. Guarded operations are composable in conditionals: they return a non-zero
   status when declined instead of terminating the caller.
2. Invalid usage and protected paths fail through the library's diagnostic path
   before any filesystem change.
3. The module's defaults are safe: unattended runs refuse, directories need
   `--recursive`, and archives are validated before extraction.
4. `DRY_RUN` never changes the filesystem or system state.
