# Feature Specification: Safe Secret Handling

**Feature Branch**: `[feature-secret]`
**Status**: Implemented
**Input**: New module: `src/secret.sh`, `doc/secret.md`, `test/secret.bats`, and
`example/secret_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts routinely handle tokens, passwords, and keys. Without a shared
helper, each script re-invents how a secret is read, and the value ends up in
log lines, in error messages produced by `set -x` or diagnostics, in the shell
history file, or in a world-readable temporary file. Scripts also tend to trust
whatever permissions a credential file happens to have.

## Business Value *(mandatory)*

- Centralize reading secrets from files, environment variables, and stdin.
- Guarantee that registered secrets are redacted in every library log path,
  including fatal errors and JSON logs.
- Refuse to use credential files that other users can read.
- Offer a documented way to hand a secret to a file-based tool without writing
  it to disk.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a secret from a trusted source (Priority: P1)

As a script author, I want one call per source so that reading a token from a
file, from the environment, or interactively behaves the same way.

**Independent Test**: Read the same value through `secret_from_file`,
`secret_from_env`, and `secret_from_stdin`, then verify the destination
variable and the source cleanup.

**Acceptance Scenarios**:

1. **Given** a file with mode 600, **When** `secret_from_file` runs, **Then**
   the destination variable holds the content without trailing newlines
2. **Given** an environment variable holding a secret, **When**
   `secret_from_env` runs, **Then** the value is copied and the source variable
   is unset unless `keep` is requested
3. **Given** input that is not a terminal, **When** `secret_from_stdin` runs,
   **Then** the first line is consumed and no prompt or echo is written
4. **Given** a source specification such as `file:PATH`, `env:NAME`, or `-`,
   **When** `secret_read` runs, **Then** it dispatches to the matching reader
   and rejects any other specification

### User Story 2 - Keep secrets out of logs and command output (Priority: P1)

As an operator, I want every secret the script has read to be redacted
automatically so that a leak doesn't depend on remembering to mask.

**Independent Test**: Register a secret, then emit it through library logging,
JSON logging, explicit masking, and a wrapped command.

**Acceptance Scenarios**:

1. **Given** a registered secret, **When** any `dybatpho` log function emits
   text containing it, **Then** the placeholder replaces the value in text and
   JSON output
2. **Given** overlapping registered secrets, **When** masking runs, **Then**
   the longest value is replaced first so no fragment survives
3. **Given** a multiline secret, **When** it is registered, **Then** each of
   its lines is registered too so line-based streams stay masked
4. **Given** a command that prints a secret to stdout and stderr, **When**
   `secret_mask_run` executes it, **Then** the output is masked and the command
   exit code is preserved
5. **Given** a value shorter than `DYBATPHO_SECRET_MIN_LENGTH`, **When**
   registration is attempted, **Then** it is skipped with a warning so
   unrelated text isn't redacted

### User Story 3 - Refuse unsafe secret files (Priority: P1)

As a maintainer, I want credential files validated before use so that a
readable or foreign-owned file fails loudly.

**Independent Test**: Check files with mode 600 and 644, a directory, a
symbolic link, and a missing path.

**Acceptance Scenarios**:

1. **Given** a file more permissive than the allowed mode, **When**
   `secret_check_permission` runs, **Then** it fails with the actual and
   expected octal modes
2. **Given** `DYBATPHO_SECRET_STRICT_PERMS` is false-like, **When** the same
   file is checked, **Then** the problem is reported as a warning and the call
   succeeds
3. **Given** a file owned by another user while the caller is not root,
   **When** the file is checked, **Then** the ownership problem is reported
4. **Given** a symbolic link or a group-writable parent directory, **When** the
   file is checked, **Then** a warning explains which permissions apply

### User Story 4 - Store and dispose of secrets safely (Priority: P2)

As a script author, I want writing, sharing, and destroying a secret to avoid
history files, readable temporary files, and lingering variables.

**Independent Test**: Write a secret file, feed a secret to a file-based
command, then wipe the variable and shred the file.

**Acceptance Scenarios**:

1. **Given** a secret in a variable, **When** `secret_write_file` runs,
   **Then** the destination is created with mode 600 through a private staging
   file and moved into place
2. **Given** a command that requires a file path, **When**
   `secret_with_file` runs it, **Then** `{}` is replaced by a `/dev/fd` path and
   nothing is written to the filesystem on supported systems
3. **Given** history recording is active, **When** `secret_no_history` runs,
   **Then** the history file is disabled for the current shell and for
   `dybatpho::breakpoint`
4. **Given** variables and files that held secrets, **When** `secret_wipe` and
   `secret_shred` run, **Then** the variables are overwritten and unset and the
   files are overwritten and removed

### Example Workflow

```bash
dybatpho::secret_no_history
dybatpho::secret_read TOKEN "file:${HOME}/.config/app/token"
dybatpho::info "deploying with ${TOKEN}"        # logs `deploying with ***`
dybatpho::secret_mask_run curl -H "Authorization: Bearer ${TOKEN}" "${url}"
dybatpho::secret_wipe TOKEN
```

## Edge Cases

- A secret file is missing, empty, a directory, or unreadable.
- A secret file is a symbolic link, or its parent directory is writable by
  group or others.
- An environment source is unset or empty, or its name isn't a shell
  identifier.
- Stdin is closed or empty, or a multiline secret is supplied to a
  single-line reader.
- A destination variable name isn't a valid shell identifier.
- A registered value is shorter than the configured minimum length.
- Two registered secrets overlap, or one contains newlines.
- `/dev/fd` is unavailable, so a private temporary file must be used and then
  shredded.
- `shred` isn't installed, so the file content is overwritten before removal.
- Masking is requested from a child shell where the registry doesn't exist.
- A variable passed to `secret_wipe` is already unset.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `secret_from_file` MUST validate permissions before reading and
  MUST reject missing, non-regular, unreadable, or empty files.
- **FR-002**: `secret_from_env` MUST require a non-empty source variable and
  MUST unset it unless `keep` is requested.
- **FR-003**: `secret_from_stdin` MUST disable echo when stdin is a terminal,
  MUST write its optional prompt to stderr, and MUST fail on empty input.
- **FR-004**: `secret_read` MUST support `file:PATH`, `env:NAME`, `stdin`, and
  `-`, and MUST reject any other source.
- **FR-005**: Every reader MUST validate the destination variable name and MUST
  register the value for masking.
- **FR-006**: `secret_register` MUST keep the registry ordered from longest to
  shortest value, MUST deduplicate values, MUST also register the lines of a
  multiline secret, and MUST skip values shorter than
  `DYBATPHO_SECRET_MIN_LENGTH` with a warning.
- **FR-007**: All library logging paths, including text output, JSON output,
  and fatal errors raised by `dybatpho::die`, MUST redact registered secrets.
- **FR-008**: `secret_mask` MUST mask arguments or stdin, MUST process stdin
  line by line, and MUST pass text through unchanged when no secret is
  registered or the registry isn't reachable.
- **FR-009**: `secret_mask_run` MUST mask the output of a command and MUST
  return the command exit code.
- **FR-010**: `secret_hint` MUST reveal at most the requested number of
  trailing characters and MUST reveal nothing for short values.
- **FR-011**: `secret_check_permission` MUST compare the file mode against an
  octal maximum, MUST verify ownership, and MUST fail or warn according to
  `DYBATPHO_SECRET_STRICT_PERMS`.
- **FR-012**: Permission inspection MUST follow symbolic links and MUST work
  with GNU and BSD `stat`.
- **FR-013**: `secret_write_file` MUST create the destination with mode 600
  through a private staging file in the same directory and MUST move it into
  place atomically.
- **FR-014**: `secret_with_file` MUST expose the secret through `/dev/fd`,
  MUST substitute `{}` in the command arguments, and MUST fall back to a
  mode-600 temporary file that is shredded afterwards.
- **FR-015**: `secret_no_history` MUST disable the shell history file and MUST
  redirect `DYBATPHO_REPL_HISTORY_FILE` to `/dev/null`.
- **FR-016**: `secret_wipe` MUST overwrite and unset named variables and MUST
  ignore variables that are already unset.
- **FR-017**: `secret_shred` MUST overwrite file content, preferring `shred`
  and otherwise zeroing the file, before removing it.
- **FR-018**: Secret values and the masking registry MUST NOT be exported to
  child processes.

### Key Entities *(include if feature involves data)*

- **Secret Value**: A credential held in a shell variable named by the caller.
- **Masking Registry**: The process-local `DYBATPHO_SECRET_VALUES` array,
  ordered longest first, with `DYBATPHO_SECRET_COUNT` as its size.
- **Placeholder**: The `DYBATPHO_SECRET_PLACEHOLDER` text substituted for a
  registered secret.
- **Permission Policy**: `DYBATPHO_SECRET_MAX_MODE` and
  `DYBATPHO_SECRET_STRICT_PERMS`, which decide whether a file is acceptable.
- **Secret Source**: A `file:`, `env:`, or stdin specification accepted by
  `secret_read`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A secret can be read from a file, the environment, or stdin with
  one call and identical downstream behavior.
- **SC-002**: Once read, a secret never appears verbatim in library logs or in
  output produced through the module's masking helpers.
- **SC-003**: Credential files readable by other users are rejected before the
  secret is used.
- **SC-004**: A secret can be handed to a file-based tool without being written
  to the filesystem.
- **SC-005**: Secrets are removed from memory and from disk with explicit,
  documented calls.

## Integration Tests *(mandatory)*

- **IT-001**: Read a mode-600 file and verify the value and its masking in
  logs.
- **IT-002**: Reject missing, empty, non-regular files and invalid variable
  names.
- **IT-003**: Verify permission failures, warning mode, custom maximum modes,
  invalid modes, and symlink warnings.
- **IT-004**: Read from the environment with and without `keep`, and reject
  unset variables, invalid names, and unknown modes.
- **IT-005**: Read a single line from stdin and fail on empty input.
- **IT-006**: Dispatch every `secret_read` source and reject an unsupported
  one.
- **IT-007**: Mask arguments and streams with overlapping and multiline
  secrets, and pass text through when nothing is registered.
- **IT-008**: Verify `secret_mask_run` masks both streams and preserves a
  non-zero exit code.
- **IT-009**: Verify `secret_hint` output for long and short values and reject
  a non-numeric reveal count.
- **IT-010**: Write a secret file, assert mode 600, and read it back.
- **IT-011**: Run a command through `secret_with_file` and assert it receives a
  `/dev/fd` path.
- **IT-012**: Wipe variables, shred files with and without `shred`, and verify
  `secret_no_history` settings.
- **IT-013**: Verify JSON logging masks registered secrets.

## Acceptance Criteria *(mandatory)*

1. Reading, masking, permission checking, and disposal all work through one
   shared registry and policy.
2. Masking applies to every library log path without extra calls at the call
   site.
3. Failures identify the file, variable, source, or command that was rejected.
4. No public function exports a secret or leaves it in a shared temporary file.
