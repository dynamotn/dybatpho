# Feature Specification: Bootstrap and Module Loading

**Feature Branch**: `[reverse-spec-init]`
**Status**: Implemented
**Input**: Existing source analysis: `init.sh`, `test/init.bats`, `docs/init.md`, `example/init_modules.sh`

## Problem Statement *(mandatory)*

Consumers need a safe, predictable way to bootstrap the dybatpho library. Manually sourcing individual modules would force every script to duplicate runtime checks, shell options, and load order concerns. At the same time, a script that only needs logging and Git should not have to pay for every module the library ships, so the bootstrap has to accept a module set and resolve the dependencies between modules on the consumer's behalf.

## Business Value *(mandatory)*

- Enable one-step adoption of the library in new scripts.
- Prevent invalid execution modes such as direct execution or unsupported Bash versions.
- Standardize module load order and exported runtime context.
- Keep start-up cost proportional to what a script actually uses.
- Let a script state its dependencies explicitly instead of relying on whatever the library happens to load.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Source the library once (Priority: P1)

As a script author, I want one bootstrap file so that I can enable the entire library with a single source statement.

**Why this priority**: Every consuming script depends on reliable initialization before any helper can work.

**Independent Test**: Source `init.sh` and verify `DYBATPHO_DIR` plus exported `dybatpho::` functions are available.

**Acceptance Scenarios**:

1. **Given** a Bash v4.3+ shell is running, **When** the script sources `init.sh`, **Then** the bootstrap exports the project root and loads the core modules in dependency order
2. **Given** the consumer expects child shells to reuse dybatpho functions, **When** a child shell inherits the environment, **Then** exported `dybatpho::` functions remain callable
3. **Given** the repository ships utility, notification, and SemVer modules,
   **When** the script asks for them by name or for `all`, **Then** those modules
   are available along with the core helpers

---

### User Story 2 - Reject unsupported startup modes (Priority: P1)

As a maintainer, I want invalid startup modes rejected so that downstream behavior is never undefined.

**Why this priority**: Fail-fast bootstrap errors prevent harder-to-debug runtime breakage later.

**Independent Test**: Attempt direct execution and unsupported Bash usage, then verify bootstrap stops with a clear failure.

**Acceptance Scenarios**:

1. **Given** the file is executed directly, **When** the shell runs `init.sh` as a program, **Then** bootstrap exits instead of pretending to work
2. **Given** the shell version is below the supported minimum, **When** the file is sourced or executed, **Then** bootstrap reports that the Bash version is unsupported

---

### User Story 3 - Load only the modules a script needs (Priority: P2)

As a script author, I want to name the modules my script uses so that the bootstrap stays proportional to the script instead of loading the whole library.

**Why this priority**: Full loading remains the default and stays correct, so this is an optimization and a clarity improvement rather than a prerequisite.

**Independent Test**: Source `init.sh` with a module set and verify that the requested modules and the core modules are loaded while the rest are not.

**Acceptance Scenarios**:

1. **Given** a script needs only part of the library, **When** it sources `init.sh --modules git semver`, **Then** the bootstrap loads those modules plus the core modules and nothing else
2. **Given** the module set is supplied as `DYBATPHO_MODULES` in the environment, **When** the script sources `init.sh` with no arguments, **Then** the same module set is loaded
3. **Given** both `DYBATPHO_MODULES` and a `--modules` argument are present, **When** the bootstrap resolves the module set, **Then** the command line wins
4. **Given** a requested module depends on another module, **When** the bootstrap loads it, **Then** the dependency is loaded first and without the consumer naming it
5. **Given** the requested name is not a dybatpho module, **When** the bootstrap resolves the module set, **Then** it reports the unknown name together with the known modules and stops

---

### User Story 4 - Widen the module set at run time (Priority: P2)

As a script author, I want to load an extra module after bootstrap so that a rarely taken branch does not force its dependency on every run.

**Why this priority**: Without it, a narrow module set would have to be widened defensively, which cancels the benefit of requesting one at all.

**Independent Test**: Bootstrap with a narrow module set, call `dybatpho::load` for another module, and verify that its functions become usable.

**Acceptance Scenarios**:

1. **Given** the shell bootstrapped with a narrow module set, **When** the script calls `dybatpho::load json`, **Then** the JSON helpers become available in the same shell
2. **Given** a module is already loaded, **When** the script loads it again, **Then** the module is not sourced twice and the loaded set does not gain a duplicate
3. **Given** the script needs to branch on what is loaded, **When** it calls `dybatpho::module_loaded` or `dybatpho::module_list`, **Then** it can read the current module set without inspecting internal state

---

### Example Workflow

```bash
#!/usr/bin/env bash
# Source the entrypoint once; the core modules become available.
. "path/to/dybatpho/init.sh"

dybatpho::register_common_handlers
dybatpho::info "Running on $(dybatpho::goos)/$(dybatpho::goarch)"
```

```bash
#!/usr/bin/env bash
# Or name the modules this script uses, and widen the set only when needed.
. "path/to/dybatpho/init.sh" --modules git semver

dybatpho::info "next release: $(dybatpho::semver_bump "1.4.2" minor)"
if [[ -n "${WEBHOOK_URL:-}" ]]; then
  dybatpho::load notification # pulls in network as well
  dybatpho::notify_webhook "${WEBHOOK_URL}" '{"text":"release prepared"}'
fi
```

## Edge Cases

- The current shell is older than Bash v4.3, including the Bash 3.2 that macOS ships.
- The consumer runs the file directly instead of sourcing it.
- Bootstrap runs under strict mode and must still load every requested module safely.
- A module is sourced more than once in the same shell.
- A module set names the same module twice, or separates names with commas instead of spaces.
- A module set is empty, or names the `core` or `all` selection instead of a module.
- A script uses a function from a module it never requested, because the default module set no longer covers it.
- Two modules depend on each other, so dependency resolution has to terminate rather than recurse.
- A child shell sources `init.sh` again after the parent already loaded modules.
- The bootstrap is sourced from a `bash -c` shell, where `BASH_SOURCE` is empty,
  so anything that expands it under the strict mode `init.sh` enables fails.
- A module is added to the registry but not to the module-to-file map.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bootstrap MUST require Bash v4.3 or newer before loading library code, because the library returns values through nameref parameters and waits with `wait -n`, neither of which exists earlier.
- **FR-002**: The bootstrap MUST refuse direct execution and require sourcing.
- **FR-003**: The bootstrap MUST enable the default strict and globbing shell options expected by the library, and on Bash 4.4 or newer MUST turn on `inherit_errexit`, so that a failing command inside `$(...)` stops the substitution instead of being ignored.
- **FR-004**: The bootstrap MUST set and export `DYBATPHO_DIR` to the repository root path.
- **FR-005**: The bootstrap MUST load the core modules, and only the core
  modules, when no module set is requested, and MUST load every shipped module
  in a deterministic order when the `all` selection is requested.
- **FR-006**: The bootstrap MUST re-export the public `dybatpho::` functions for downstream shells.
- **FR-007**: Re-sourcing a module with a load guard MUST not duplicate its
  initialization or change its public behavior.
- **FR-008**: The bootstrap MUST accept a module set through a leading
  `--modules` argument or the `DYBATPHO_MODULES` environment variable, and the
  argument MUST take precedence over the environment variable.
- **FR-009**: A module set MUST accept names separated by spaces or commas, MUST
  tolerate repeated names, and MUST support the `core` and `all` selections.
- **FR-010**: The bootstrap MUST always load the core modules, whichever module
  set is requested.
- **FR-011**: The bootstrap MUST load the dependencies of every requested module
  before the module itself, without the consumer naming them.
- **FR-012**: Dependency resolution MUST terminate when two modules depend on
  each other, and MUST source each module exactly once.
- **FR-013**: The bootstrap MUST reject an unknown module name, report it
  together with the known modules on stderr, and stop instead of continuing with
  a partial module set.
- **FR-014**: `dybatpho::load` MUST load further modules and their dependencies
  into the current shell after bootstrap, and MUST stop the script when it is
  given no argument or an unknown module.
- **FR-015**: `dybatpho::module_loaded` and `dybatpho::module_list` MUST expose
  the current module set, and `dybatpho::module_list` MUST reject an unknown
  selection.
- **FR-016**: The bootstrap MUST fail with a clear message when a registered
  module has no entry in the module-to-file map, rather than reporting the
  module as loaded without sourcing it.
- **FR-017**: The loaded module set MUST describe the current shell only, and
  MUST NOT be exported or read from the environment, because the internal
  helpers that public functions call do not cross a process boundary.
- **FR-018**: The bootstrap MUST expose the version of the library through
  `dybatpho::version`, resolved from the `VERSION` file beside `init.sh`, then
  from the repository tags, and finally as `unknown`, with any leading `v`
  removed, cached in `DYBATPHO_VERSION`, and overridable by setting that
  variable before sourcing. When the copy is the root of its own Git working
  tree the reported version MUST also name the commit it is at, as SemVer build
  metadata, marked when the tree has uncommitted changes; a copy vendored inside
  another repository MUST NOT report that repository's commit. See `docs/spec/doctor.md` for the diagnostics and
  the bundle that build on it.
- **FR-019**: Sourcing `init.sh` again in a shell that already loaded the library, or loading an already-loaded module, MUST NOT fail on a constant a module declares read-only.

### Key Entities *(include if feature involves data)*

- **Bootstrap Session**: The runtime state created by sourcing `init.sh`.
- **Public Function Export**: A `dybatpho::` function made available to subshells after bootstrap.
- **Module Registry**: The set of core and optional module names the bootstrap recognizes, published as `DYBATPHO_CORE_MODULES` and `DYBATPHO_OPTIONAL_MODULES`.
- **Module Set**: The modules requested for a session, recorded in load order in `DYBATPHO_LOADED_MODULES`.
- **Module Dependency**: An edge from one module to another module it calls, resolved before the dependent module is sourced.
- **Module Source Map**: The mapping from a module name to its file, derived from the name as `src/<name>.sh`.
- **Library Version**: The version of this copy of the library, stamped in `VERSION` and reported by `dybatpho::version`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Consumers can enable the toolkit with one source statement, and
  reach the full library by adding `--modules all` to it.
- **SC-002**: Unsupported execution modes fail before any partial initialization leaks into the session.
- **SC-003**: All public modules, including archive, Git, notification, and
  SemVer helpers, are available immediately after a bootstrap that requests
  them.
- **SC-004**: A script that names a module set loads that set plus the core
  modules, and no other module.
- **SC-005**: A consumer never has to name a dependency of a module it already
  requested.
- **SC-006**: A wrong module name is reported at bootstrap rather than as a
  missing-function error later in the run.

## Integration Tests *(mandatory)*

- **IT-001**: Source `init.sh --modules all` and call one representative
  function from each shipped module, including archive, config, Git, lock,
  notification, secret, and SemVer helpers.
- **IT-002**: Execute `init.sh` directly and verify the session is rejected.
- **IT-003**: Run under Bash v4.3+ strict mode and verify bootstrap completes without manual overrides.
- **IT-004**: Source `init.sh --modules semver` and verify the loaded set is the
  core modules plus `semver`, and that an unrequested module's functions are absent.
- **IT-005**: Request the module set through `DYBATPHO_MODULES`, then through
  both the environment and `--modules`, and verify the argument wins.
- **IT-006**: Request a module set with commas and a repeated name, and verify
  each module is loaded once.
- **IT-007**: Request `core` and verify it matches the default module set, and
  request `all` and verify every registered module is loaded.
- **IT-008**: Request `text`, `notification`, and `testing` and verify each
  dependency appears ahead of the module that pulled it in.
- **IT-009**: Request `safety` and `archive`, which depend on each other, and
  verify resolution terminates with each module loaded once.
- **IT-010**: Request an unknown module and verify the bootstrap reports it with
  the known modules and stops before running the rest of the script.
- **IT-011**: Bootstrap with `core`, call `dybatpho::load` for one and several
  modules, and verify the functions work and repeat loads add no duplicate.
- **IT-012**: Call `dybatpho::load` with no argument and with an unknown module
  and verify both stop the script.
- **IT-013**: Verify `dybatpho::module_loaded` answers for a loaded and an
  unloaded module, and that `dybatpho::module_list` prints each selection and
  rejects an unknown one.
- **IT-014**: Load every module in the registry in one shell and verify the
  loaded set has an entry for each, so the registry and the module-to-file map
  cannot drift apart unnoticed.
- **IT-015**: Register a module that has no entry in the map and verify the load
  stops with a message naming it.
- **IT-016**: Export the loaded set from a parent shell, source `init.sh` again
  in a child shell, and verify the child loads its own modules and its public
  functions still work.
- **IT-017**: Verify `dybatpho::version` reports the stamped version without a
  leading `v`, names the current short commit, marks a dirty working tree,
  ignores the commits of a project it is vendored into,
  caches the answer in `DYBATPHO_VERSION`, honors a value already set in the
  environment, and still answers in a copy that has no `VERSION` file.
- **IT-018**: Source `init.sh` twice with `--modules all` from one script, then load four modules again, and see no `readonly variable` error.

## Acceptance Criteria *(mandatory)*

1. `init.sh` is the single supported entrypoint for loading dybatpho.
2. Bootstrap behavior is explicit, deterministic, and fail-fast.
3. Sourcing `init.sh` with no argument loads the core modules only. A consumer
   that needs more states it, through `--modules`, `DYBATPHO_MODULES`, or
   `dybatpho::load`.
4. A requested module set is complete on its own: its dependencies are resolved
   for the consumer, and a name that is not a module stops the bootstrap.
