# Feature Specification: Bootstrap and Module Loading

**Feature Branch**: `[reverse-spec-init]`
**Status**: Implemented
**Input**: Existing source analysis: `init.sh`, `test/init.bats`, `docs/init.md`, `example/init_modules.sh`

## Problem Statement *(mandatory)*

Consumers need a safe, predictable way to bootstrap the dybatpho library. Manually sourcing individual modules would force every script to duplicate runtime checks, shell options, and load order concerns. At the same time, a script that only needs logging and Git should not have to pay for every module the library ships, so the bootstrap has to accept a module set and resolve the dependencies between modules on the consumer's behalf.

## Business Value *(mandatory)*

- Enable one-step adoption of the library in new scripts.
- Prevent invalid execution modes such as direct execution or unsupported Bash versions.
- Standardize module load order and the shell options a script starts from,
  while leaving the caller in control of its own shell and its child processes.
- Keep start-up cost proportional to what a script actually uses.
- Let a script state its dependencies explicitly instead of relying on whatever the library happens to load.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Source the library once (Priority: P1)

As a script author, I want one bootstrap file so that I can enable the entire library with a single source statement.

**Why this priority**: Every consuming script depends on reliable initialization before any helper can work.

**Independent Test**: Source `init.sh` and verify `DYBATPHO_DIR` and the core `dybatpho::` functions are available, and that a child process inherits none of them.

**Acceptance Scenarios**:

1. **Given** a Bash v4.3+ shell is running, **When** the script sources `init.sh`, **Then** the bootstrap exports the project root and loads the core modules in dependency order
2. **Given** a script that did not opt in, **When** it starts a `bash -c` child, **Then** the child sees no dybatpho function and the environment carries no function body
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
2. **Given** the shell version is below the supported minimum, **When** the file is sourced or executed, **Then** bootstrap reports that the Bash version is unsupported, returning 1 to a sourcing shell rather than ending it
3. **Given** a sourced bootstrap fails, **When** the caller checks the status of `.`, **Then** the caller is still running, can report the failure its own way, and its shell options are unchanged

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

### User Story 5 - Keep control of the calling shell (Priority: P1)

As a script author, I want the bootstrap to change only what I agreed to, so
that sourcing the library does not alter how my own globs, options, and child
processes behave.

**Why this priority**: The bootstrap runs in the caller's shell. Turning on
`nullglob` silently changed what every glob in the caller's script meant, and
exporting every function slowed every child process and could overflow the
environment of a `find -exec ... +`.

**Independent Test**: Source `init.sh` with and without `--no-strict`, compare
the shell options before and after, and start child processes with and without
opting in to exporting.

**Acceptance Scenarios**:

1. **Given** a script sources `init.sh` with no option, **When** it globs a
   pattern that matches nothing, **Then** the pattern stays literal, because
   `nullglob` and `globstar` are left alone while strict mode, `extglob`, and
   `inherit_errexit` are on
2. **Given** a script sources `init.sh --no-strict`, **When** the bootstrap
   finishes, **Then** every `set` and `shopt` option is as the script had it,
   and the core modules still work
3. **Given** a script sets `DYBATPHO_EXPORT_FUNCTIONS=true` or calls
   `dybatpho::export_functions`, **When** it starts a `bash -c` child, **Then**
   the child has the whole library with the same module set, internal helpers
   and module state included, and its own options untouched
4. **Given** a script opted in, **When** it later calls `dybatpho::load`,
   **Then** a child started afterwards has the added module too

---

### User Story 6 - Know which modules are stable (Priority: P2)

As a script author, I want to know which modules keep their contract across minor releases so that a long-lived script can stay on modules that will not change under it.

**Why this priority**: A script works without this knowledge, but upgrading the library is safe only when the author knows which parts may move.

**Independent Test**: List the modules of each tier, ask the tier of one module, and check that no stable module depends on an experimental one.

**Acceptance Scenarios**:

1. **Given** a script wants only modules with a stable contract, **When** it calls `dybatpho::module_list stable`, **Then** it gets every stable module, and `experimental` gives the rest
2. **Given** a script uses one module, **When** it calls `dybatpho::module_tier <module>`, **Then** it learns whether the module is `stable` or `experimental`
3. **Given** a stable module, **When** it is loaded, **Then** every module it loads up front is stable too

---

### User Story 7 - Load a rarely needed module only when a function needs it (Priority: P2)

As a script author, I want a module that only a few functions of another module need to arrive when one of those functions runs, so that I neither pay for it up front nor see my script stop asking me to load it.

**Why this priority**: Stopping with a "load it with" message is correct but turns an avoidable detail into a failed run.

**Independent Test**: Load `csv` alone, convert to JSON, and see `json` loaded on demand.

**Acceptance Scenarios**:

1. **Given** a script loaded `csv` alone, **When** it converts to JSON, **Then** `json` is loaded on demand and the conversion succeeds
2. **Given** the conversion runs inside `$(...)`, **When** the substitution ends, **Then** the module loaded there is gone with it, and the next call loads it again
3. **Given** the module needed cannot be loaded, **When** the function runs, **Then** it stops naming itself and the module

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
# Keep the shell options this script already chose, and hand the library to
# the child processes it starts.
. "path/to/dybatpho/init.sh" --no-strict --modules semver || exit 1
dybatpho::export_functions
find . -name '*.version' -exec bash -c 'dybatpho::semver_valid "$(cat "$1")"' _ {} \;
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
- A sourced bootstrap fails, and the caller has no `set -e` or checks the
  status of `.` itself.
- The caller relies on `nullglob`, `set +e`, or other options of its own, and
  sources with `--no-strict`.
- A child process of an exporting script is started with arguments of its own,
  such as `--modules`, which the bootstrap must not read as a module request.
- `BASH_ENV` already names a hook, such as a coverage tool's, before
  `dybatpho::export_functions` replaces it.
- The library lives under a path holding `$`, a backquote, or a backslash,
  which `BASH_ENV` would expand.
- A module is added to the registry but not to the module-to-file map.
- `init.sh` is sourced by a relative path while `CDPATH` names a directory holding a
  directory of the same name, or by a bare `init.sh` with no directory part.
- A soft dependency is loaded on demand inside a command substitution, where it
  lives only as long as that subshell.
- A soft dependency's file is missing, so loading it on demand fails.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The bootstrap MUST require Bash v4.3 or newer before loading library code, because the library returns values through nameref parameters and waits with `wait -n`, neither of which exists earlier. When sourced, it MUST return 1 rather than exit.
- **FR-002**: The bootstrap MUST refuse direct execution and require sourcing.
- **FR-003**: By default the bootstrap MUST turn on `set -euo pipefail` and `extglob`, and on Bash 4.4 or newer `inherit_errexit`, so that a failing command inside `$(...)` stops the substitution instead of being ignored. It MUST NOT turn on `nullglob` or `globstar`, and the library MUST guard each of its own globs so that an unmatched pattern, which stays literal, is never taken for a file.
- **FR-004**: The bootstrap MUST set and export `DYBATPHO_DIR` to the repository root path.
- **FR-005**: The bootstrap MUST load the core modules, and only the core
  modules, when no module set is requested, and MUST load every shipped module
  in a deterministic order when the `all` selection is requested.
- **FR-006**: The bootstrap MUST NOT export any function to child processes unless the consumer opts in with `DYBATPHO_EXPORT_FUNCTIONS=true` before sourcing or a call to `dybatpho::export_functions`.
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
  together with the known modules on stderr, and return 1 before loading any
  module or changing any shell option, instead of continuing with a partial
  module set. A sourced bootstrap MUST NOT `exit` the calling shell.
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
  `DYBATPHO_LOADED_MODULES` MUST NOT be exported or read from the environment;
  a child process gets the library only by sourcing it, itself or through the
  hook `dybatpho::export_functions` installs.
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
- **FR-020**: The core modules MUST include `array`, so the dependency-graph helpers `dybatpho::array_toposort` and `dybatpho::array_closure` are available in every module set, which is what lets `doctor` walk the module graph with them.
- **FR-021**: The module dependency map MUST stay global when `init.sh` is sourced from inside a function, so that `dybatpho::load` and `dybatpho::doctor` still resolve dependencies after that function returns.
- **FR-022**: `DYBATPHO_DIR` MUST be the directory `init.sh` was sourced from, resolved against the working directory alone: `CDPATH` MUST NOT redirect it or add output to it.
- **FR-023**: Once the consumer opted in, `dybatpho::load` MUST update the exported module set, so a child started afterwards loads the added modules too.
- **FR-024**: `dybatpho::export_functions` MUST make the complete library -- public functions, internal helpers, and module state -- available to every non-interactive Bash child by pointing `BASH_ENV` at the library with the current module set in `DYBATPHO_EXPORT_MODULES`. A child reached that way MUST load that module set, MUST ignore its own positional arguments and `DYBATPHO_MODULES`, MUST leave its `set` and `shopt` options untouched, and MUST source first the `BASH_ENV` that was in place before, kept in `DYBATPHO_EXPORT_BASH_ENV`.
- **FR-025**: `dybatpho::export_functions` MUST stop the script when the library path holds `$`, a backquote, or a backslash, which Bash would expand in `BASH_ENV`.
- **FR-026**: A leading `--no-strict` option, alone or together with `--modules` in either order, MUST leave every `set` and `shopt` option of the caller as it was, and the core modules MUST work in a shell without errexit, nounset, pipefail, `extglob`, or `nullglob`.

- **FR-027**: Every registered module MUST carry a stability tier, `stable` or `experimental`. A stable module MUST keep its public contract across minor releases, deprecating a function for at least one minor release before removing it; an experimental module MAY change in any minor release. The core modules MUST be stable, and a stable module MUST NOT depend on an experimental one.
- **FR-028**: `dybatpho::module_list` MUST accept the `stable` and `experimental` selections, which together list the whole registry, and `dybatpho::module_tier` MUST print the tier of a module and stop the script for an unknown one.
- **FR-029**: The registry MUST record every soft dependency -- a module that another module loads on demand from only some of its functions -- and every module it names MUST be registered. Each call site that asks for a module on demand MUST be recorded, and each record MUST have a call site.
- **FR-030**: A function that needs a soft dependency MUST load it on demand through `dybatpho::load`, with its own dependencies, and MUST stop naming itself and the module only when the module cannot be loaded.
- **FR-031**: A module whose load failed MUST NOT be taken as loaded or as part of a dependency cycle by a later load: `dybatpho::load` of it MUST fail again, and a load on demand MUST try it afresh.

### Key Entities *(include if feature involves data)*

- **Bootstrap Session**: The runtime state created by sourcing `init.sh`.
- **Library Export**: The opt-in `BASH_ENV` hook through which a child Bash process sources the library with the parent's module set.
- **Module Registry**: The set of core and optional module names the bootstrap recognizes, published as `DYBATPHO_CORE_MODULES` and `DYBATPHO_OPTIONAL_MODULES`.
- **Module Set**: The modules requested for a session, recorded in load order in `DYBATPHO_LOADED_MODULES`.
- **Module Dependency**: An edge from one module to another module it calls, resolved before the dependent module is sourced.
- **Module Source Map**: The mapping from a module name to its file, derived from the name as `src/<name>.sh`.
- **Library Version**: The version of this copy of the library, stamped in `VERSION` and reported by `dybatpho::version`.
- **Stability Tier**: `stable` or `experimental`, recorded for every module and reported by `dybatpho::module_tier`.
- **Soft Dependency**: An edge from a module to another module it loads on demand rather than up front.

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
- **SC-007**: Sourcing the library adds no function body to the environment of
  a child process unless the consumer asks for it.
- **SC-008**: No failure of the bootstrap ends a shell that sourced it.

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
  the known modules and returns 1 with the caller still running and its options
  unchanged, while a caller under `set -e` stops; execute `init.sh` directly
  and verify it is refused.
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
- **IT-019**: Source `init.sh` with no module set and verify `dybatpho::array_toposort` and `dybatpho::array_closure` are defined.
- **IT-020**: Source `init.sh` from inside a function, call `dybatpho::load forge` after it returns, and verify `network`, `json` and `git` are loaded ahead of `forge`.
- **IT-021**: Source `lib/dybatpho/init.sh` with `CDPATH` naming a directory that also holds `lib/dybatpho`, and source a bare `init.sh` from the library directory; verify `DYBATPHO_DIR` is the real library each time.
- **IT-022**: Source `init.sh --modules all` and verify a `bash -c` child sees no dybatpho function, `BASH_ENV` stays unset, and the environment grows by less than 4 KiB.
- **IT-023**: Set `DYBATPHO_EXPORT_FUNCTIONS=true`, source with `semver` and `csv`, and verify a `bash -c` child runs `dybatpho::info`, `dybatpho::semver_compare`, and `dybatpho::csv_header` correctly.
- **IT-024**: Call `dybatpho::export_functions`, then `dybatpho::load semver`, and verify a child sees the internal helpers and the added module; verify a child keeps its own options and arguments, and that a `BASH_ENV` set before is still sourced first.
- **IT-025**: Copy the library under a path holding `$` and verify `dybatpho::export_functions` refuses it.
- **IT-026**: Verify that sourcing leaves `nullglob` and `globstar` off and an unmatched glob literal, that `--no-strict` in either position leaves every `set` and `shopt` option unchanged, and that a sample of every core module works with errexit, nounset, pipefail, `extglob`, and `nullglob` all off.

- **IT-027**: Verify every registered module has a tier, the core modules are stable, no stable module depends on an experimental one, `dybatpho::module_list stable` and `experimental` split the registry, and `dybatpho::module_tier` answers and rejects an unknown module.
- **IT-028**: Verify every soft dependency names a registered module, every call site asking for a module on demand is recorded, and every record has a call site.
- **IT-029**: For every soft dependency, load only the module that declares it in a child shell and see the soft dependency loaded on demand.
- **IT-030**: Convert to JSON inside `$(...)` in a shell that loaded `csv` alone, and see the result while `json` stays unloaded in the parent.

## Acceptance Criteria *(mandatory)*

1. `init.sh` is the single supported entrypoint for loading dybatpho.
2. Bootstrap behavior is explicit, deterministic, and fail-fast, and a failure
   returns to the caller instead of ending its shell.
3. Sourcing `init.sh` with no argument loads the core modules only. A consumer
   that needs more states it, through `--modules`, `DYBATPHO_MODULES`, or
   `dybatpho::load`.
4. A requested module set is complete on its own: its dependencies are resolved
   for the consumer, and a name that is not a module stops the bootstrap.
5. The caller's shell keeps its globbing, and with `--no-strict` all of its
   options; child processes inherit the library only on request.
