# Feature Specification: File Contents, Preview, and Temporary Resource Management

**Feature Branch**: `[reverse-spec-file]`
**Status**: Implemented
**Input**: Existing source analysis: `src/file.sh`, `docs/file.md`, `test/file.bats`, and `example/file_ops.sh`

## Problem Statement *(mandatory)*

Shell automation often needs quick file inspection, path decomposition, path joining, path normalization, relative path calculation, extension inspection and rewriting, absolute-path checks, and temporary file or directory creation with reliable cleanup. Ad hoc implementations increase the chance of leaked paths, naming collisions, inconsistent file previews, and repeated path-splitting snippets.

A script also has to decide where its own files live. Guessing `~/.myapp` ignores the XDG Base Directory specification that the rest of the system follows, and honoring it by hand means repeating the same fallback logic, including the rule that a relative value counts as unset.

Two more gaps sit next to these. Locating the root of the project a script was invoked inside means walking up the directory tree by hand, and creating a directory before writing into it means repeating a `mkdir -p` guard at every call site.

Rewriting the contents of a file is just as common and more dangerous. A script that redirects into a file truncates it before the new contents are written, so an interrupted run destroys the original; `sed -i` takes a different argument on GNU and BSD; appending a line to a dotfile duplicates it on the second run; and reading a size, checksum, or modification time means picking between incompatible `stat` and checksum tools per platform.

## Business Value *(mandatory)*

- Make temporary resource handling safer and more reusable.
- Support quick inspection of files during debugging and operator workflows.
- Build on process-level cleanup guarantees without forcing callers to wire them manually.
- Keep common dirname and basename logic inside the existing file module.
- Support filename extension and stem handling without extra external commands or inline parameter expansion.
- Support safe path assembly without repeated slash-cleanup snippets in calling scripts.
- Support textual path cleanup for repeated separators and dot-segments without requiring filesystem access.
- Support lightweight path inspection and extension rewriting without external commands.
- Make rewriting a file safe by default, so that an interrupted script cannot leave a truncated file behind.
- Let a script that maintains a dotfile run repeatedly without duplicating what it added.
- Read file metadata identically on GNU, BusyBox, and BSD systems.
- Edit a dotfile that is symlinked into a repository without detaching the link from it.
- Locate a project root from any directory inside it.
- Put a program's configuration, cache, data, and state where the system expects them.
- Answer how large a tree is, and whether a file is safe to run a text rewrite over.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview files during script execution (Priority: P2)

As an operator, I want to inspect files with line numbers so that debugging generated or downloaded content is easier.

**Why this priority**: Preview is secondary to temp management but still useful in real workflows.

**Independent Test**: Call the file-preview helper for a real file and verify line-numbered output appears on stderr.

**Acceptance Scenarios**:

1. **Given** the `bat` command is available, **When** the file-preview helper runs, **Then** the file is shown using the richer preview path
2. **Given** the `bat` command is unavailable, **When** the file-preview helper runs, **Then** the file is still shown with numbered fallback output

---

### User Story 2 - Create temporary resources safely (Priority: P1)

As a script author, I want a helper that creates temp files or directories and registers cleanup automatically so that I can use ephemeral workspaces without cleanup boilerplate.

**Why this priority**: Temporary resource safety is the module’s primary value and underpins many shell workflows.

**Independent Test**: Create temp files and directories under default and custom parents, then verify the returned paths exist and are cleaned up on shell exit.

**Acceptance Scenarios**:

1. **Given** the caller requests a temporary file, **When** the temp helper runs, **Then** a unique path is created and stored in the requested variable
2. **Given** the caller requests a temporary directory, **When** the temp helper runs with directory mode, **Then** a unique directory is created and registered for cleanup

---

### User Story 3 - Split paths inside scripts (Priority: P2)

As a script author, I want dirname and basename helpers so that file-path logic stays readable and consistent with the rest of the library.

**Why this priority**: Path decomposition often appears next to temp-file and download workflows and fits naturally in the file module.

**Independent Test**: Run the path helpers against absolute, relative, root, and suffixed paths and verify the printed components.

**Acceptance Scenarios**:

1. **Given** an absolute file path, **When** the dirname helper runs, **Then** it prints the directory component
2. **Given** a path and an optional suffix, **When** the basename helper runs, **Then** it prints the basename and strips the suffix when it matches

---

### User Story 4 - Inspect extensions and stems (Priority: P2)

As a script author, I want helpers for final extensions and stems so that file-type and naming logic can stay inside the same file module.

**Why this priority**: Extension and stem handling are direct follow-ups to basename logic and are common in scripting workflows.

**Independent Test**: Run the extension and stem helpers against normal files, multi-dot names, and hidden files.

**Acceptance Scenarios**:

1. **Given** a path with a final extension, **When** the extname helper runs, **Then** it prints the final extension with the leading dot
2. **Given** a path with multiple dots, **When** the stem helper runs, **Then** it removes only the final extension and keeps the rest of the basename

---

### User Story 5 - Join path segments predictably (Priority: P2)

As a script author, I want a helper that joins path fragments with single separators so that I can build paths from variables without hand-written slash cleanup.

**Why this priority**: Path composition is a direct companion to dirname, basename, extname, and stem helpers.

**Independent Test**: Join absolute and relative path fragments with empty segments and repeated slashes, then verify the resulting path uses single separators.

**Acceptance Scenarios**:

1. **Given** multiple path fragments with mixed leading and trailing slashes, **When** the join helper runs, **Then** the result contains single `/` separators between fragments
2. **Given** empty fragments around an absolute root, **When** the join helper runs, **Then** empty segments are ignored and the root is preserved

---

### User Story 6 - Normalize paths textually (Priority: P2)

As a script author, I want a helper that cleans repeated separators plus `.` and `..` path segments so that path strings can be stabilized without touching the filesystem.

**Why this priority**: Path normalization naturally complements join, dirname, basename, extname, and stem helpers.

**Independent Test**: Normalize absolute and relative paths with repeated separators and dot-segments, then verify relative `..` segments are preserved when they cannot be reduced further.

**Acceptance Scenarios**:

1. **Given** a path with repeated separators plus `.` and `..` segments, **When** the normalize helper runs, **Then** the result is a cleaned textual path
2. **Given** a relative path that begins with unresolved `..` segments, **When** the normalize helper runs, **Then** those parent traversals are preserved

---

### User Story 7 - Rewrite a file without risking its contents (Priority: P1)

As a script author, I want to replace what a file contains in one step so that a reader never sees a half-written file and an interrupted run leaves the original intact.

**Why this priority**: A truncated configuration file breaks the system the script was meant to configure, and the failure surfaces long after the script exits.

**Independent Test**: Write new contents over an existing file, then verify the contents, that the file's mode survived, and that no staging file is left behind.

**Acceptance Scenarios**:

1. **Given** an existing file with mode 640, **When** the atomic-write helper replaces its contents, **Then** the new contents are in place and the mode is still 640
2. **Given** a rewrite helper fails part way, **When** the failure is reported, **Then** the original file still holds its previous contents and no staging file remains
3. **Given** a pattern to substitute, **When** the replace helper runs on GNU or BSD, **Then** the substitution is applied the same way without an `-i` argument

---

### User Story 8 - Keep a line in a dotfile exactly once (Priority: P1)

As a dotfiles author, I want to guarantee a line is present or absent so that running my bootstrap script twice leaves the same result as running it once.

**Why this priority**: Bootstrap scripts are re-run by design; a helper that appends unconditionally corrupts the file it maintains.

**Independent Test**: Call the ensure-line helper twice with the same line and verify the line appears exactly once, then call the remove-line helper twice and verify it is gone and no error is raised.

**Acceptance Scenarios**:

1. **Given** a file that already contains the exact line, **When** the ensure-line helper runs again, **Then** the file is unchanged
2. **Given** a file whose last line has no trailing newline, **When** the ensure-line helper appends, **Then** the new line is a separate line
3. **Given** a file that does not contain the line, **When** the remove-line helper runs, **Then** it reports success and changes nothing

---

### User Story 9 - Read file metadata portably (Priority: P2)

As a script author, I want size, checksum, and age of a file from one helper each so that my script behaves the same on GNU, BusyBox, and BSD.

**Why this priority**: These reads are simple individually, but each one needs a different tool per platform, which is exactly the duplication the library exists to remove.

**Independent Test**: Read the size, checksum, and age of a known file and compare against independently computed values.

**Acceptance Scenarios**:

1. **Given** a file of known contents, **When** the hash helper runs, **Then** the checksum matches the reference value for the requested algorithm
2. **Given** a file modified in the past, **When** the age helper runs, **Then** it reports the elapsed seconds since its modification time
3. **Given** a file about to be edited, **When** the backup helper runs, **Then** it copies the file under a new name and prints that path

---

### User Story 10 - Edit a dotfile that is a symlink (Priority: P1)

As a dotfiles author, I want to edit a path that is a symlink into my repository and have the repository file change, so that my edit is tracked rather than silently detached.

**Why this priority**: Replacing the symlink looks like success. The damage only surfaces later, when the repository turns out not to contain the change and the next deployment reverts it.

**Independent Test**: Point a symlink at a file in another directory, rewrite the symlink's path, then verify the path is still a symlink and the file it points at holds the new contents.

**Acceptance Scenarios**:

1. **Given** a path that is a symlink, **When** any writing helper runs on it, **Then** the link is preserved and the file it points at is the one rewritten
2. **Given** a chain of symlinks or a relative symlink, **When** a writing helper runs, **Then** the file at the end of the chain is rewritten
3. **Given** a symlink loop, **When** a writing helper runs, **Then** the helper reports the loop instead of following it forever
4. **Given** a caller that wants the old behavior, **When** symlink following is disabled, **Then** the helper replaces the symlink with a regular file

---

### User Story 11 - Find the project root from anywhere inside it (Priority: P1)

As a tool author, I want to search upward for a marker such as `.git` so that my script behaves the same whichever subdirectory it was invoked from.

**Why this priority**: Nearly every repository-aware script needs this, and each one otherwise reimplements the same upward walk.

**Independent Test**: Search for a marker from a nested directory and verify the marker's path is printed, then search for a name that does not exist and verify failure without output.

**Acceptance Scenarios**:

1. **Given** a marker in an ancestor directory, **When** the search helper runs from a nested directory, **Then** it prints the absolute path of the marker
2. **Given** a marker that is a directory rather than a file, **When** the search helper runs, **Then** it is found just the same
3. **Given** no matching entry up to the filesystem root, **When** the search helper runs, **Then** it reports failure and prints nothing

---

### User Story 12 - Create a directory before writing into it (Priority: P2)

As a script author, I want one helper that creates a directory tree and reports its path so that I do not repeat a `mkdir -p` guard before every write.

**Why this priority**: Small individually, but it appears before nearly every write, and pairs with the atomic writers, which require the destination directory to exist.

**Independent Test**: Create a nested directory with a mode, call the helper again, and verify the directory, its mode, and the printed path are unchanged.

**Acceptance Scenarios**:

1. **Given** a nested path that does not exist, **When** the helper runs, **Then** every missing parent is created and the path is printed
2. **Given** a directory that already exists, **When** the helper runs again with a mode, **Then** the mode is applied and nothing else changes
3. **Given** a path that exists as a file, **When** the helper runs, **Then** it reports the conflict instead of failing obscurely later

---

### User Story 13 - Put a program's files where they belong (Priority: P2)

As a tool author, I want the directories the XDG Base Directory specification defines so that my configuration, cache, data, and state land where the rest of the system expects, and where a user's backup and cleanup tools already look.

**Why this priority**: Getting this wrong is not fatal, but it scatters files a user cannot find and a backup does not cover.

**Independent Test**: Read each directory with and without the environment variables set, and verify the specification's defaults and the scoping to an application name.

**Acceptance Scenarios**:

1. **Given** no XDG variables are set, **When** a directory is read, **Then** the specification's default under the home directory is returned
2. **Given** a variable holds an absolute path, **When** the directory is read, **Then** that path is used
3. **Given** a variable holds a relative path, **When** the directory is read, **Then** it is ignored and the default is used, as the specification requires
4. **Given** an application name, **When** a directory is read, **Then** the name is appended
5. **Given** the directory does not exist, **When** it is read, **Then** nothing is created, because building a path and creating one are separate decisions

---

### User Story 14 - Measure and classify what is on disk (Priority: P2)

As a script author, I want the size of a tree, the modification time of a file, and whether a file is binary so that I can decide what to clean up and what is safe to rewrite.

**Why this priority**: Each is small, but each otherwise means a per-platform branch, and the binary check prevents a text rewrite from destroying a file.

**Independent Test**: Measure a tree of known contents, read a known modification time, and classify a text file and a file containing a NUL byte.

**Acceptance Scenarios**:

1. **Given** a directory tree, **When** its size is read, **Then** the total is the sum of the regular files it contains
2. **Given** a symbolic link inside the tree, **When** the size is read, **Then** it is not counted, so its target cannot be counted twice
3. **Given** a file, **When** its modification time is read, **Then** it is returned as a Unix timestamp, following a symlink to its target
4. **Given** a file containing a NUL byte in its first block, **When** it is classified, **Then** it is reported as binary
5. **Given** an empty file, **When** it is classified, **Then** it is reported as text

---

### Example Workflow

```bash
# Build a report in a temporary file that is cleaned up on exit.
dybatpho::create_temp report_file ".csv" "build-report"
dybatpho::cleanup_file_on_exit "${report_file}"

# Derive sibling paths without shelling out to dirname/basename.
config="$(dybatpho::path_join "$(dybatpho::path_dirname "${report_file}")" "report.json")"
dybatpho::info "stem=$(dybatpho::path_stem "${report_file}")"
dybatpho::info "json=$(dybatpho::path_change_ext "${report_file}" json)"

dybatpho::path_is_abs "${config}" || dybatpho::die "Expected an absolute path"
dybatpho::show_file "${report_file}"
```

## Edge Cases

- The target variable name is empty or invalid.
- The caller requests a custom parent directory that does not exist.
- The extension includes unsafe slash content that must not survive into the created file suffix.
- The input path is the filesystem root, a relative path without separators, or a path with trailing slashes.
- The input path is a hidden file or a basename without an extension.
- Path joining receives empty fragments or repeated slashes between fragments.
- Path normalization receives empty input, absolute root traversals, or unresolved relative parent traversals.
- Relative-path calculation may compare absolute paths, relative paths, or mixed path styles.
- Someone able to write to the destination's directory plants a symbolic link at the name a rewrite would stage under.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST show file content with line numbers on stderr.
- **FR-002**: The preview helper MUST prefer richer output when a suitable viewer is available and fall back otherwise.
- **FR-003**: The module MUST provide a dirname helper that prints the directory component of a path.
- **FR-004**: The module MUST provide a basename helper that prints the basename component of a path.
- **FR-005**: The basename helper MUST support optional exact suffix stripping.
- **FR-006**: The module MUST provide an extname helper that returns the final extension of a basename including the leading dot.
- **FR-007**: The module MUST provide a stem helper that removes only the final extension from the basename.
- **FR-008**: Hidden files without a second dot MUST be treated as having no extension.
- **FR-009**: The module MUST provide a path-join helper that combines path fragments with single `/` separators.
- **FR-010**: The path-join helper MUST ignore empty fragments and preserve a leading root when the first meaningful fragment is absolute.
- **FR-011**: The module MUST provide a path-normalize helper that resolves repeated separators and textual `.` / `..` segments.
- **FR-012**: The path-normalize helper MUST preserve unresolved leading `..` segments for relative paths and clamp absolute traversals at root.
- **FR-013**: The module MUST create unique temporary files or directories and assign the resulting path into a caller-provided variable.
- **FR-014**: The temp helper MUST support default and custom parent directories.
- **FR-015**: The temp helper MUST register created resources for cleanup on shell exit.
- **FR-016**: The temp helper MUST sanitize the requested suffix so path traversal or nested path injection is not introduced through the extension argument.
- **FR-017**: The module MUST provide a helper that returns success when a path is absolute.
- **FR-018**: The module MUST provide a helper that detects any final extension or compares the final extension to an expected value.
- **FR-019**: The module MUST provide a helper that rewrites or removes the final extension of a path.
- **FR-020**: The module MUST provide a helper that returns the relative path from a base path to a target path without filesystem access.
- **FR-021**: Every helper that changes a file MUST write through a staging file in the destination's directory and rename it into place, so that the destination is never observed partially written.
- **FR-022**: A rewrite that fails MUST leave the destination unchanged and MUST NOT leave a staging file behind.
- **FR-023**: A rewrite MUST preserve the destination's mode, and MUST preserve its owner when the process has the privilege to set it.
- **FR-024**: The module MUST provide a substitution helper that applies a basic regular expression in place without depending on the `sed -i` argument, which differs between GNU and BSD.
- **FR-025**: The module MUST provide ensure-line and remove-line helpers that compare whole lines exactly and whose repeated application produces the same result as a single application.
- **FR-026**: The ensure-line helper MUST create the file when it is missing, and MUST NOT join its line onto a final line that has no trailing newline.
- **FR-027**: The remove-line helper MUST report success when the file or the line does not exist, because the requested end state already holds.
- **FR-028**: The module MUST report the size, modification age in seconds, and checksum of a file, selecting an available tool per platform.
- **FR-029**: The checksum helper MUST support `md5`, `sha1`, `sha256`, and `sha512`, default to `sha256`, and reject any other algorithm.
- **FR-030**: The backup helper MUST copy a file under a timestamped name, MUST NOT overwrite an existing backup, and MUST print the path it created.
- **FR-031**: Every helper that changes a file MUST honor `DRY_RUN` by reporting the intended change and leaving the filesystem untouched.
- **FR-032**: Every helper that changes a file MUST resolve a symlink destination to the file it points at, so that the link is preserved rather than replaced, and MUST follow chains and relative links.
- **FR-033**: Symlink resolution MUST stop with an error on a loop rather than following it indefinitely, and MUST be disableable so that a caller can replace the link instead.
- **FR-034**: Metadata helpers MUST report the file a symlink points at rather than the link itself.
- **FR-035**: The module MUST provide a helper that searches a directory and its ancestors for a named entry, matching files and directories alike, printing the absolute path of the first match and reporting failure without output when the filesystem root is reached.
- **FR-036**: The module MUST provide a helper that creates a directory and its missing parents, applies an optional mode whether or not the directory already existed, prints the resulting path, and rejects a path that exists as something other than a directory.
- **FR-037**: The module MUST provide the configuration, cache, data, and state directories of the XDG Base Directory specification, honoring the matching environment variable when it holds an absolute path and falling back to the specification's default otherwise, including when the variable holds a relative path.
- **FR-038**: An XDG helper MUST accept an application name to scope the directory to, MUST build a path only, and MUST fail when neither its variable nor `HOME` is usable.
- **FR-039**: The module MUST report a file's modification time as a Unix timestamp, describing the file a symlink points at rather than the link.
- **FR-040**: The module MUST report the total size of the regular files in a directory tree, excluding symbolic links so that a target inside the tree cannot be counted twice.
- **FR-041**: The module MUST report whether a file is binary, by looking for a NUL byte in its first block, and MUST treat an empty file as text.
- **FR-042**: The module MUST provide a helper that creates a temporary directory registered for cleanup, without the caller having to express "directory" as an extension argument.
- **FR-043**: A rewrite MUST stage in a file it created exclusively under an unpredictable name in the destination's directory, and MUST NOT write through a link or any other file that already held that name.

### Key Entities *(include if feature involves data)*

- **Temporary Resource**: A file or directory created for short-lived script use and scheduled for cleanup.
- **Preview Target**: A user-specified file path whose content is displayed for inspection.
- **Input Path**: A path string whose directory or basename component is requested by the caller.
- **Final Extension**: The last dot-prefixed suffix of a basename when one exists.
- **Path Fragment**: One caller-provided segment that contributes to a joined path.
- **Normalized Path**: A textual path with repeated separators and reducible dot-segments removed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Consumers can create temporary files or directories with one helper call.
- **SC-002**: Temporary resources are removed automatically when the owning shell exits.
- **SC-003**: Consumers can decompose paths without external `dirname` and `basename` calls.
- **SC-004**: Consumers can derive final extensions and stems without extra parameter-expansion snippets.
- **SC-005**: Consumers can compose paths with one helper call instead of hand-written slash normalization.
- **SC-006**: Consumers can normalize path strings without touching the filesystem or writing custom dot-segment cleanup logic.
- **SC-007**: File previews remain available whether or not optional viewer tooling is installed.
- **SC-008**: A script interrupted mid-rewrite leaves the target file with its previous contents, never empty or partial.
- **SC-009**: A dotfiles script that adds lines can be re-run any number of times without changing the result of the first run.
- **SC-010**: Consumers read size, checksum, and age without writing per-platform branches.
- **SC-011**: Editing a symlinked dotfile changes the file in the repository it points at, so the edit is tracked.
- **SC-012**: A script locates its project root from any directory inside it with one helper call.
- **SC-013**: A script can create a directory before writing without guarding the call.
- **SC-014**: A tool's files land where the user's other tools, backups, and cleanup scripts already look.
- **SC-015**: A script can decide what to rewrite without risking a binary file.

## Integration Tests *(mandatory)*

- **IT-001**: Create a temp file with the default temp directory and verify it exists immediately after creation.
- **IT-002**: Create a temp directory under a custom existing parent and verify cleanup occurs on shell exit.
- **IT-003**: Validate dirname behavior for root and relative inputs.
- **IT-004**: Validate basename behavior, suffix stripping, and trailing-slash handling.
- **IT-005**: Validate extname and stem behavior for normal files, hidden files, and multi-dot basenames.
- **IT-006**: Validate path-join behavior for absolute, relative, and empty-fragment inputs.
- **IT-007**: Validate path-normalize behavior for absolute, relative, empty, and parent-traversal inputs.
- **IT-008**: Preview a file with and without `bat` available and verify numbered output still appears.
- **IT-009**: Rewrite an existing file with the atomic-write helper and verify the contents, the preserved mode, and that the file was replaced by rename rather than truncation.
- **IT-010**: Run the substitution helper with patterns that contain `/`, with a back reference, and with an invalid expression, verifying the failure leaves the original intact and removes the staging file.
- **IT-011**: Call the ensure-line helper twice and verify one occurrence, including on a file whose last line has no trailing newline and on a file that does not exist yet.
- **IT-012**: Call the remove-line helper twice, on a file it empties, and on a missing file, verifying success every time.
- **IT-013**: Compare hash output against reference checksums for each supported algorithm, and reject an unknown algorithm.
- **IT-014**: Verify size and age for known files, including an empty file and a modification time in the future.
- **IT-015**: Back up a file twice and verify both copies exist under distinct names with the original mode.
- **IT-016**: Run every writing helper under `DRY_RUN` and verify the file, its backups, and the staging directory are untouched.
- **IT-017**: Rewrite through a symlink, a chain of symlinks, and a relative symlink, verifying the link survives and the target changes.
- **IT-018**: Rewrite a symlink with following disabled and verify the link is replaced by a regular file while its former target is untouched.
- **IT-019**: Run a writing helper on a symlink loop and verify it reports the loop.
- **IT-020**: Read size and age through a symlink and verify they match the target rather than the link.
- **IT-021**: Search upward for a marker from a nested directory, for a directory marker, from the default starting directory, and for a name that does not exist.
- **IT-022**: Create a nested directory with a mode, call again with a different mode, and attempt the helper on a path that exists as a file.
- **IT-023**: Read each XDG directory with no variables set and verify the specification's defaults, with variables set and verify they are honored, and with a relative value and verify it is ignored.
- **IT-024**: Read an XDG directory with an application name, verify nothing is created, and verify the failure when neither the variable nor `HOME` is set.
- **IT-025**: Read a known modification time, cross-check it against the age helper, and verify a symlink reports its target's time.
- **IT-026**: Total a tree of known contents, an empty directory, and a tree containing a symlink, and reject a missing directory.
- **IT-027**: Classify a text file, a file containing a NUL byte, an empty file, and a file whose only NUL is past the sampled block.
- **IT-028**: Create a temporary directory with a prefix and a custom parent, and verify it is removed when the shell exits.
- **IT-029**: Plant links at the staging names the old process-id scheme would have used, run every writer, and verify the link target is untouched, the destination is a regular file with the new contents, and no staging file is left over.

## Acceptance Criteria *(mandatory)*

1. The module makes ephemeral file workflows practical and safe in normal shell scripts.
2. Temporary resource creation integrates cleanly with the process cleanup contract.
3. Path decomposition, joining, normalization, extension lookup, and stem extraction are available directly inside the file module without separate external command calls.
