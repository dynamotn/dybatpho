# Feature Specification: Environment Diagnostics and Bundling

**Feature Branch**: `[feature-doctor]`
**Status**: Implemented
**Input**: Existing source analysis: `src/doctor.sh`, `init.sh`, `scripts/bundle.sh`, `docs/doctor.md`, `test/doctor.bats`, `test/bundle.bats`, `test/init.bats`, and `example/doctor_ops.sh`

## Problem Statement *(mandatory)*

A dybatpho module calls an external tool only when the caller reaches the function that needs it, so a missing `yq`, `curl`, or `tar` surfaces partway through a script instead of before the work starts. The user then fixes one tool, re-runs, and meets the next one. Nothing in the library answers "what does this script need, and what is missing here?" up front.

Two related questions have no answer either. A consumer cannot ask, at run time, which version of the library it loaded, so a bug report cannot state it and a script cannot guard against an old copy. And a project that wants dybatpho inside a container image or vendored into another repository has to copy `init.sh` plus the whole `src/` tree, in a layout the bootstrap can resolve, when a single file would be easier to copy, review, and check in.

## Business Value *(mandatory)*

- Cut debugging time by reporting every missing dependency at once, before the real work begins.
- Make dependency expectations explicit and reviewable instead of scattered across `dybatpho::require` calls.
- Let bug reports and scripts name the exact library version in use.
- Make vendoring and container packaging a one-file operation that reuses the existing module selection.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See everything the loaded modules need (Priority: P1)

As a script author, I want one report of the external commands the modules I loaded can call, so that I can install everything missing in one pass instead of discovering the tools one failure at a time.

**Why this priority**: This is the reason the module exists; every other capability supports it.

**Independent Test**: Load a module set, run the report with a `PATH` that holds only known fake commands, and verify each dependency is marked found or missing.

**Acceptance Scenarios**:

1. **Given** a shell that loaded modules with external dependencies, **When** the report runs without arguments, **Then** it lists every dependency of the loaded modules with its status
2. **Given** a required dependency is missing, **When** the report runs, **Then** it names the dependency and the run fails
3. **Given** only optional dependencies are missing, **When** the report runs, **Then** it names them as optional and the run succeeds
4. **Given** a dependency accepts alternatives, **When** any one of them is installed, **Then** the dependency counts as satisfied and the report shows the command that satisfied it

---

### User Story 2 - Check a module set before committing to it (Priority: P2)

As a script author, I want to check the environment for modules I have not loaded yet, so that I can choose a code path the machine can actually run.

**Why this priority**: Scripts routinely decide between an archive format, a JSON tool, or a network path depending on what is installed.

**Independent Test**: Ask for an explicit module list and for the whole registry, and verify the report covers exactly those modules.

**Acceptance Scenarios**:

1. **Given** an explicit module list, **When** the report runs with it, **Then** it covers those modules and nothing else
2. **Given** the whole registry is requested, **When** the report runs, **Then** it covers every registered module
3. **Given** a name that is not a module, **When** the report runs with it, **Then** the run stops with a message naming the unknown module

---

### User Story 3 - Gate a pipeline on the environment (Priority: P2)

As a CI author, I want the report to answer through its exit code and to emit machine-readable output, so that a pipeline step can fail early and a tool can consume the result.

**Why this priority**: An automated consumer needs a stable contract, not a table meant for a terminal.

**Independent Test**: Run the report in quiet mode and in JSON mode with and without the required dependencies installed, and verify both the exit code and the parsed output.

**Acceptance Scenarios**:

1. **Given** quiet mode, **When** the report runs, **Then** nothing is printed and the exit code states whether every required dependency is installed
2. **Given** JSON mode, **When** the report runs, **Then** one JSON object describes the version, the Bash version, the platform, the modules, every dependency, and the overall result
3. **Given** JSON mode, **When** no JSON tool is installed, **Then** the report is still produced

---

### User Story 4 - Ask which version of the library is loaded (Priority: P2)

As a consumer, I want the library to report its own version at run time, so that logs and bug reports can name it and a script can refuse an unsupported copy.

**Why this priority**: Version reporting is small, but without it no consumer can state what it ran.

**Independent Test**: Source the bootstrap and verify the reported version matches the stamped file, an environment override, and the fallback in a copy that has no stamp.

**Acceptance Scenarios**:

1. **Given** a copy with a stamped version file, **When** the version is requested, **Then** the stamped version is reported without a leading `v`
2. **Given** the copy is the root of its own Git working tree, **When** the version is requested, **Then** the short commit is appended as build metadata, marked when the tree has uncommitted changes
3. **Given** the copy is vendored inside another repository, **When** the version is requested, **Then** the stamped version is reported without that repository's commit
4. **Given** a checkout with no stamped version file, **When** the version is requested, **Then** the version is derived from the repository's tags
5. **Given** neither a stamp nor repository information, **When** the version is requested, **Then** the answer is `unknown` rather than empty

---

### User Story 5 - Vendor the library as one file (Priority: P2)

As a maintainer of another project, I want the modules I use flattened into a single file, so that I can vendor dybatpho into a repository or a container image without carrying a directory layout.

**Why this priority**: Distribution friction keeps the library out of projects that cannot add a submodule.

**Independent Test**: Generate a bundle for a module selection, source it in a shell with no dybatpho functions and no `src/` directory in reach, and verify the bundled functions work.

**Acceptance Scenarios**:

1. **Given** a module selection, **When** the bundle is generated, **Then** it carries those modules and every module they depend on, in load order
2. **Given** a generated bundle, **When** it is sourced with no library directory beside it, **Then** the bundled functions work and the library version is reported
3. **Given** a generated bundle, **When** a module it does not carry is requested at run time, **Then** the failure names the command that would regenerate the bundle with that module
4. **Given** an existing output file, **When** the bundle is generated again without approval, **Then** the file is left untouched

---

### Example Workflow

```bash
. dybatpho/init.sh --modules doctor json archive

# Before the work starts: what is missing?
dybatpho::doctor || dybatpho::die "Install the tools listed above first"

dybatpho::info "Running under dybatpho $(dybatpho::version)"   # 2.0.0+af745ff

# In CI, answer through the exit code only.
dybatpho::doctor --modules "json,network" --quiet \
  || dybatpho::die "This runner can't run the release job"

# Vendor what a downstream project needs into one file.
scripts/bundle.sh --modules "logging git semver" --output dist/dybatpho.sh
```

## Edge Cases

- A module set that needs nothing external is reported as such rather than as an empty table.
- Every alternative of an any-of dependency is missing, which makes the dependency missing.
- A dependency is present but not on the narrowed `PATH` a subshell uses.
- The report runs on a Bash older than the supported minimum, which the bootstrap would already have refused.
- An output path already holds a bundle, or a bundle is requested for an unknown module.
- The version file is empty, ends without a newline, or carries a leading `v`.
- The copy is not a Git working tree, or is vendored inside another one, so no commit of its own can be named.
- A dependency's path, a version or the library directory holds a control character, such as an ANSI escape.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST declare, per module, the external commands that module can call, split into required and optional.
- **FR-002**: A dependency MUST be able to name alternatives, and MUST count as satisfied when any one of them is installed.
- **FR-003**: The report MUST cover the loaded modules by default, an explicit module list when given one, and the whole registry on request.
- **FR-002a**: A dependency MUST be able to name a version range, written in the range syntax of `dybatpho::semver_satisfies` without spaces, and an alternative carrying one MUST count as satisfied only when the installed version falls inside it.
- **FR-002b**: The module MUST ask a dependency for its version only when that dependency names a range, so that a report never executes a tool nothing has an opinion about.
- **FR-002c**: When no alternative of a dependency satisfies it, the report MUST name the most specific outcome available, preferring an alternative that is installed but outdated over one whose version could not be read, and either over nothing being installed.
- **FR-004**: The report MUST state, for every dependency, the module, the dependency, whether it is required or optional, and whether it was found, including the resolved path and, when a version was read, that version.
- **FR-004a**: The report MUST classify every dependency as `ok`, `missing`, `outdated`, or `unknown`, where `outdated` means installed but outside the declared range and `unknown` means installed with a version that could not be read.
- **FR-005**: The report MUST state the library version, the running Bash version, the supported Bash minimum, and the host platform.
- **FR-006**: The report MUST fail when a required dependency is missing or the running Bash is older than the supported minimum, and MUST succeed when only optional dependencies are missing.
- **FR-006a**: The report MUST fail when a required dependency is installed but outdated, and MUST NOT fail for an outdated optional dependency.
- **FR-006b**: The report MUST NOT fail for a dependency whose version could not be read, because a probe that could not tell has not shown that anything is wrong.
- **FR-007**: The report MUST offer a quiet mode that prints nothing and answers through the exit code.
- **FR-008**: The report MUST offer a JSON mode that emits one object, and MUST build it without depending on an external JSON tool.
- **FR-009**: The module MUST stop the script with a clear message for an unknown module name, an unknown dependency kind, or an unknown option.
- **FR-010**: The module MUST expose the declared dependencies of a single module for programmatic use.
- **FR-011**: The bootstrap MUST report the library version, read from the version file beside it, falling back to the repository tags and then to `unknown`, with any leading `v` removed.
- **FR-011a**: When the copy is the root of its own Git working tree, the reported version MUST name the commit it is at, appended as SemVer build metadata and marked when the tree has uncommitted changes, so the version identifies the code that ran and not only the last release. A copy vendored inside another project MUST NOT report that project's commit.
- **FR-012**: The reported version MUST be cached after the first call and MUST honor a value already set in the environment.
- **FR-013**: The bundler MUST resolve its module selection through the bootstrap itself, so the bundled set matches what the same selection loads.
- **FR-014**: A generated bundle MUST be a single file that carries the bootstrap guards, the module sources verbatim, and no dependency on a `src/` directory.
- **FR-015**: A generated bundle MUST report the version it was generated from, and MUST report only the modules it carries as its registry.
- **FR-016**: Inside a bundle, loading a carried module MUST succeed, and loading any other module MUST fail with the command that regenerates the bundle with it.
- **FR-017**: The bundler MUST refuse to overwrite an existing output file without approval, MUST honor `DRY_RUN`, and MUST verify that the file it wrote parses and can be sourced.
- **FR-018**: The JSON report MUST escape every control character in the strings it writes, so it parses whatever a path or version holds, and MUST do so without `jq`.
- **FR-019**: `scripts/bundle.sh` MUST read every bootstrap function it copies from `init.sh` before it opens the output, and MUST stop without writing a bundle when one cannot be found.

### Key Entities *(include if feature involves data)*

- **Dependency declaration**: A module name mapped to the external commands it can call, as a required set and an optional set.
- **Dependency spec**: One command name, or several alternatives any one of which satisfies it.
- **Report row**: The module, dependency, kind, status, and resolved path of one checked dependency.
- **Bundle**: A generated single file carrying the bootstrap and a resolved module set.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user learns every missing dependency of a script in one run instead of one failure per tool.
- **SC-001a**: A user learns that an installed tool is the wrong version before the script reaches the function that needs it, rather than from that function's error.
- **SC-002**: An automated consumer can decide on the exit code alone, without parsing the text report.
- **SC-003**: Any consumer can name the exact library version it is running.
- **SC-004**: A project can adopt the library by copying one generated file.
- **SC-005**: The bundled module set never diverges from what the same `--modules` selection loads from the repository.

## Integration Tests *(mandatory)*

- **IT-001**: Verify the declared required and optional dependencies of a module are reported, and that a module with none reports nothing.
- **IT-002**: Verify an unknown module name and an unknown dependency kind stop the script.
- **IT-003**: Verify an installed dependency is reported with its resolved path on a narrowed `PATH`.
- **IT-004**: Verify a missing required dependency fails the report and is named in the summary.
- **IT-005**: Verify a missing optional dependency is reported without failing the run.
- **IT-006**: Verify an any-of dependency is satisfied by any alternative and missing only when every alternative is.
- **IT-006a**: Verify a dependency naming a range is reported `ok` with its version when the installed version satisfies it.
- **IT-006b**: Verify a required dependency that is installed but outside its range is reported `outdated`, named in the summary, and fails the run.
- **IT-006c**: Verify a dependency whose version cannot be read is reported `unknown`, named in the summary, and does not fail the run.
- **IT-006d**: Verify an outdated optional dependency is named in the summary without failing the run.
- **IT-006e**: Verify an any-of dependency prefers an alternative inside its range, and reports `outdated` rather than `missing` when only an out-of-range alternative is installed.
- **IT-006f**: Verify a dependency that names no range is never executed by the report.
- **IT-007**: Verify the default scope, an explicit list, a comma separated list, and the whole registry.
- **IT-008**: Verify quiet mode prints nothing and reports through the exit code in both directions.
- **IT-009**: Verify JSON mode emits one parseable object containing the version, Bash details, modules, dependencies, and overall result.
- **IT-009a**: Verify JSON mode carries the detected version of a dependency and reports an outdated required dependency as not ok.
- **IT-010**: Verify an unknown option and a `--modules` without a value stop the script.
- **IT-011**: Verify the version comes from the version file, drops a leading `v`, is cached, honors an environment override, and falls back when no file exists.
- **IT-011a**: Verify the version names the current short commit, marks a dirty working tree, and reports the stamped version alone when the library is vendored inside another repository.
- **IT-012**: Verify a bundle carries the resolved dependency closure of its selection, in load order.
- **IT-013**: Verify a bundle works when sourced with no library directory in reach, and refuses direct execution.
- **IT-014**: Verify loading a carried module inside a bundle succeeds and loading an absent one names the regeneration command.
- **IT-015**: Verify the bundler refuses to overwrite without approval, overwrites when forced, and writes nothing under `DRY_RUN`.
- **IT-016**: Verify the bundler rejects an unknown module and keeps the module source verbatim apart from the shebang.
- **IT-017**: Verify a dependency found under a directory whose name holds an ANSI escape and a `\x01` is reported with `\u001b` and `\u0001`, and that the report parses.
- **IT-018**: Bundle from a copy of the library whose `init.sh` misspells a bootstrap function header, and fail with no output file.

## Acceptance Criteria *(mandatory)*

1. A user can learn what an environment is missing before running the real script, in one command.
2. Optional dependencies are information and required dependencies are failures, in both the text and the exit code.
3. The library can state its own version wherever it is installed, including inside a bundle.
4. A generated bundle behaves like the library it was generated from, for the modules it carries.
