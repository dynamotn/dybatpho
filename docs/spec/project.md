# Feature Specification: dybatpho Bash Utility Library

**Feature Branch**: `[reverse-spec-project]`
**Status**: Implemented
**Input**: Repository-wide analysis of `init.sh`, `src/*.sh`, `docs/`, `docs/spec/`, `example/`, and `test/`

## Problem Statement *(mandatory)*

Script authors need a reusable Bash toolkit for common concerns such as argument validation, logging, process cleanup, HTTP requests, file management, string and array manipulation, OS normalization, and declarative CLI generation. Without a unified library, teams duplicate fragile shell snippets and struggle to keep scripting behavior consistent across projects.

## Business Value *(mandatory)*

- Reduce repeated shell boilerplate across scripts and repositories.
- Improve reliability by centralizing validated, test-backed script primitives.
- Make Bash automation easier to adopt through examples, generated docs, and stable module entry points.
- Provide a composable foundation for both small helper scripts and larger command-line tools.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Source one entrypoint and gain the full toolkit (Priority: P1)

As a script author, I want to source one initialization file and immediately use the library so that I can build scripts quickly without manually wiring module dependencies.

**Why this priority**: Bootstrap simplicity is the first requirement for any reusable shell library; if loading is fragile, every downstream workflow is affected.

**Independent Test**: Source `init.sh` from a Bash v4.3+ shell and verify that representative functions from each module are callable in the current shell and exported to child shells where intended.

**Acceptance Scenarios**:

1. **Given** a Bash v4.3+ shell is in a project using dybatpho, **When** the script sources `init.sh`, **Then** the shared environment and module functions become available for use
2. **Given** a script uses child shell execution after sourcing dybatpho, **When** a child shell is started, **Then** named `dybatpho::` functions remain available where the library promises export support
3. **Given** a consumer needs archive, Git, notification, or SemVer behavior,
   **When** the bootstrap completes, **Then** those modules are available through
   the same entrypoint

---

### User Story 2 - Compose multiple modules in one automation flow (Priority: P1)

As a maintainer, I want the modules to work together coherently so that one script can validate input, log progress, create temporary files, call remote endpoints, and clean up safely.

**Why this priority**: The library creates most value when modules can be combined into real automation flows instead of used in isolation.

**Independent Test**: Run an example-style script that uses helpers, logging, file, process, and network functionality together and verify each contract remains consistent across the flow.

**Acceptance Scenarios**:

1. **Given** a script validates configuration and dependencies before work starts, **When** it performs file, process, and network operations using dybatpho helpers, **Then** errors and cleanup are handled consistently
2. **Given** a script emits user-facing progress and diagnostic logs, **When** it runs under normal and dry-run conditions, **Then** output stays structured and side effects match the active mode

---

### User Story 3 - Generate richer CLIs without external parser code (Priority: P2)

As a CLI author, I want to declare command specs in shell functions so that I can generate parsing, help, aliases, validations, and subcommand dispatch from one source of truth.

**Why this priority**: The CLI system is a distinguishing capability of the library but depends on the rest of the toolkit for error handling, logging, and script ergonomics.

**Independent Test**: Define nested command specs and verify generated parsing, help, positional validation, persistent options, aliases, and lifecycle hooks from the same shell definitions.

**Acceptance Scenarios**:

1. **Given** a root command defines flags, params, and subcommands, **When** the CLI is invoked with valid and invalid combinations, **Then** the generated parser dispatches valid paths and reports standardized errors for invalid ones
2. **Given** a command exposes `--help` and subcommand help, **When** the user requests help from different command depths, **Then** usage, descriptions, options, commands, and visibility rules are rendered correctly

---

### Example Workflow

```bash
#!/usr/bin/env bash
# One source line, then compose modules across a single automation flow.
. "path/to/dybatpho/init.sh"

dybatpho::register_common_handlers
dybatpho::lock_acquire "release" 30 || dybatpho::die "Another release is running"

dybatpho::config_load defaults.env production.yaml
dybatpho::config_schema VERSION string required:true
dybatpho::config_validate

version="$(dybatpho::config_get VERSION)"
dybatpho::semver_valid "${version}" || dybatpho::die "Invalid version: ${version}"

dybatpho::git_is_clean . || dybatpho::die "Dirty worktree"
dybatpho::curl_download "https://dl.example.test/${version}.tgz" /tmp/app.tgz
dybatpho::archive_extract /tmp/app.tgz /srv/app

dybatpho::notify_slack "Released ${version}"
dybatpho::lock_release "release"
```

## Edge Cases

- Sourcing is attempted from a shell that is not Bash v4.3 or newer.
- A consumer executes `init.sh` directly instead of sourcing it.
- Multiple modules are used in subshells, traps, or strict-mode scripts where environment and export behavior must remain predictable.
- Optional external tools such as `curl`, `jq`, `yq`, archivers, or `python3`
  are unavailable.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST provide a single bootstrap file that validates the runtime shell and loads all shipped modules in a stable order.
- **FR-002**: The library MUST expose reusable shell functions for strings,
  arrays, text, tables, logging, helpers, process handling, networking, date
  and structured data, configuration, file and archive operations, process
  locking, Git, notifications, secret handling, SemVer, CLI generation, and
  OS normalization.
- **FR-003**: The library MUST support strict-mode-friendly usage in scripts that run with fail-fast shell settings.
- **FR-004**: The library MUST ship examples and generated documentation that map to the available modules and primary workflows.
- **FR-005**: The library MUST keep user-visible behavior covered by the existing automated test suite.
- **FR-006**: The library MUST support composition across modules without requiring consumers to manage hidden cross-module dependencies manually.
- **FR-007**: The library MUST document optional external-command dependencies
  and the failure behavior when they are unavailable.

### Key Entities *(include if feature involves data)*

- **Module**: A cohesive group of exported shell functions under `src/*.sh` that addresses one scripting concern.
- **Bootstrap Session**: The sourced runtime context created by `init.sh`, including shell options, exported variables, and loaded functions.
- **Generated CLI Spec**: A shell-defined command contract that can be converted into parser and help behavior by the CLI module.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new consumer can source one file and access the full library without additional bootstrap steps.
- **SC-002**: Every top-level module in `src/` has a corresponding documented
  behavioral contract in `docs/spec/` and generated docs under `docs/`, including
  `archive`, `notification`, `secret`, and `semver`.
- **SC-003**: Core workflows remain verifiable through the project test suite without ad hoc manual setup.
- **SC-004**: Scripts using multiple dybatpho modules can complete common automation tasks with consistent logging, validation, and cleanup behavior.

## Integration Tests *(mandatory)*

- **IT-001**: End-to-end bootstrap: source `init.sh` in a Bash v4.3+ shell and
  verify representative functions from all modules are available, including
  archive, config, Git, lock, notification, secret, and SemVer.
- **IT-002**: Composite automation: validate inputs, create temp files, perform a network request, log progress, and clean up on shell exit using dybatpho utilities.
- **IT-003**: CLI generation: define a nested spec and verify parsing, help, aliases, hooks, and standardized failures without separate parser code.

## Acceptance Criteria *(mandatory)*

1. The codebase presents a coherent Bash utility product rather than unrelated helper snippets.
2. Each shipped module has a stable functional role that is discoverable in docs, examples, and specs.
3. The library can be adopted incrementally or as a full toolkit by sourcing the bootstrap entrypoint.
4. The `docs/spec/` directory captures the current product behavior of the existing source tree in GitHub Spec Kit format.
