# Feature Specification: File Preview and Temporary Resource Management

**Feature Branch**: `[reverse-spec-file]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/file.sh"

## Problem Statement *(mandatory)*

Shell automation often needs quick file inspection, path decomposition, path joining, path normalization, relative path calculation, extension inspection and rewriting, absolute-path checks, and temporary file or directory creation with reliable cleanup. Ad hoc implementations increase the chance of leaked paths, naming collisions, inconsistent file previews, and repeated path-splitting snippets.

## Business Value *(mandatory)*

- Make temporary resource handling safer and more reusable.
- Support quick inspection of files during debugging and operator workflows.
- Build on process-level cleanup guarantees without forcing callers to wire them manually.
- Keep common dirname and basename logic inside the existing file module.
- Support filename extension and stem handling without extra external commands or inline parameter expansion.
- Support safe path assembly without repeated slash-cleanup snippets in calling scripts.
- Support textual path cleanup for repeated separators and dot-segments without requiring filesystem access.
- Support lightweight path inspection and extension rewriting without external commands.

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

### Edge Cases

- The target variable name is empty or invalid.
- The caller requests a custom parent directory that does not exist.
- The extension includes unsafe slash content that must not survive into the created file suffix.
- The input path is the filesystem root, a relative path without separators, or a path with trailing slashes.
- The input path is a hidden file or a basename without an extension.
- Path joining receives empty fragments or repeated slashes between fragments.
- Path normalization receives empty input, absolute root traversals, or unresolved relative parent traversals.
- Relative-path calculation may compare absolute paths, relative paths, or mixed path styles.

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

## Integration Tests *(mandatory)*

- **IT-001**: Create a temp file with the default temp directory and verify it exists immediately after creation.
- **IT-002**: Create a temp directory under a custom existing parent and verify cleanup occurs on shell exit.
- **IT-003**: Validate dirname behavior for root and relative inputs.
- **IT-004**: Validate basename behavior, suffix stripping, and trailing-slash handling.
- **IT-005**: Validate extname and stem behavior for normal files, hidden files, and multi-dot basenames.
- **IT-006**: Validate path-join behavior for absolute, relative, and empty-fragment inputs.
- **IT-007**: Validate path-normalize behavior for absolute, relative, empty, and parent-traversal inputs.
- **IT-008**: Preview a file with and without `bat` available and verify numbered output still appears.

## Acceptance Criteria *(mandatory)*

1. The module makes ephemeral file workflows practical and safe in normal shell scripts.
2. Temporary resource creation integrates cleanly with the process cleanup contract.
3. Path decomposition, joining, normalization, extension lookup, and stem extraction are available directly inside the file module without separate external command calls.
