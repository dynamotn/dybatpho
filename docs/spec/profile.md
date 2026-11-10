# Feature Specification: Profiling a Bash Script

**Feature Branch**: `[feature-profile]`
**Status**: Implemented
**Input**: Issue #36; `src/profile.sh`, `test/profile.bats`, `docs/profile.md`, `example/profile_ops.sh`

## Problem Statement *(mandatory)*

When a Bash script is slow, the question is which part. `dybatpho::benchmark` times a whole command and `metrics.sh` times named operations a caller already chose, but neither says where a script's own time goes. Today that means sprinkling `date +%s%N` around guesses -- a fork per reading, at whatever granularity the guess allowed, with nested blocks counted twice.

## Business Value *(mandatory)*

- Mark the blocks to time, and get each one's own time apart from the time of the blocks inside it.
- Time every function of a script without touching it, when the cost of doing so is acceptable for one run.
- Read the answer as one table sorted by where the time actually went.
- Pay nothing when profiling is off.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Time marked blocks (Priority: P1)

As a script author, I want to mark the start and end of the blocks I suspect, nested or not, and see how long each took on its own and with what it called.

**Independent Test**: Mark an outer block around two sleeps, one inside an inner block; the inner block's self time is its sleep, the outer one's self time excludes it, and its total includes it.

**Acceptance Scenarios**:

1. **Given** `profile_begin outer`, `profile_begin inner`, `profile_end inner`, `profile_end outer`, **When** the report is printed, **Then** `outer`'s total includes `inner`'s and its self time does not
2. **Given** a block marked three times, **When** the report is printed, **Then** it shows three calls and the summed times
3. **Given** `profile_end` names a block other than the innermost open one, **When** it runs, **Then** the script stops naming both
4. **Given** `profile_run name -- command`, **When** it runs, **Then** the command runs inside a block of that name and its exit code is returned

---

### User Story 2 - Time every function (Priority: P2)

As a script author, I want to turn on per-function timing for one run without editing the functions.

**Independent Test**: In a child script with `DYBATPHO_PROFILE=true`, call `profile_start`, run `f` which calls `g`, then `profile_stop`; the report lists `f` and `g`, `f`'s total covers `g`'s.

**Acceptance Scenarios**:

1. **Given** `DYBATPHO_PROFILE=true`, **When** `profile_start` runs, **Then** each function entered afterwards is timed as a block of its own name until `profile_stop`
2. **Given** `DYBATPHO_PROFILE` unset or false, **When** `profile_start` runs, **Then** nothing is installed and nothing slows down
3. **Given** a `DEBUG` trap the caller set with `functrace` on, as Bats does, **When** `profile_stop` runs, **Then** it is put back; one set without `functrace` is invisible to any function and is cleared
4. **Given** Bash older than 5.0, **When** `profile_start` runs with `DYBATPHO_PROFILE=true`, **Then** it warns that per-function timing needs `EPOCHREALTIME` and does nothing

---

### User Story 3 - Read the report (Priority: P1)

**Acceptance Scenarios**:

1. **Given** recorded blocks, **When** `profile_report` runs, **Then** it prints an aligned table of name, calls, total ms and self ms, sorted by self time, most first
2. **Given** `--tsv`, **When** it runs, **Then** it prints the same rows tab-separated with a header, for a script to read
3. **Given** `profile_reset`, **When** it runs, **Then** every record and open block is forgotten

### Example Workflow

```bash
. init.sh --modules profile

dybatpho::profile_begin "load config"
load_config
dybatpho::profile_end "load config"
dybatpho::profile_run "sync" -- sync_all

# Or, for one run, every function:
DYBATPHO_PROFILE=true ./my-script.sh   # the script calls profile_start / profile_stop

dybatpho::profile_report
```

## Edge Cases

- `profile_end` with no open block, or naming a block that is not the innermost.
- A block still open when the report is printed: it is not counted until it ends.
- The same name nested inside itself (recursion).
- A function that calls `exit` while blocks are open.
- Bash 4.3 or 4.4, without `EPOCHREALTIME`.
- A caller with its own `DEBUG` trap, such as Bats.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `profile_begin NAME` and `profile_end NAME` MUST time the block between them, MUST nest, and MUST record per name the number of calls, the total time, and the self time -- the total less the total of blocks ended inside it.
- **FR-002**: `profile_end` MUST stop the script when no block is open or NAME is not the innermost open block.
- **FR-003**: `profile_run NAME -- COMMAND` MUST run COMMAND inside a block named NAME and return its exit code, ending the block whatever the command returns.
- **FR-004**: Times MUST be read from `EPOCHREALTIME` in microseconds where Bash has it, and from the library's millisecond clock otherwise, with no process started per reading on Bash 5.
- **FR-005**: `profile_start` MUST, when `DYBATPHO_PROFILE` is true-like and Bash has `EPOCHREALTIME`, install a `DEBUG` trap with `functrace` that times each function as a block of its name; MUST otherwise do nothing (warning only when `DYBATPHO_PROFILE` asked for it); `profile_stop` MUST end every block the trap opened, put back the `functrace` setting the caller had, and put back the caller's `DEBUG` trap when `profile_start` could see it -- when the caller had `functrace` on, since Bash hides the caller's `DEBUG` trap from a function otherwise.
- **FR-006**: The profiler's own functions and the library's internals MUST NOT appear as functions in the report.
- **FR-007**: `profile_report` MUST print name, calls, total ms and self ms per name, sorted by self time descending, aligned through `table_align`, or tab-separated with a header under `--tsv`; milliseconds MUST carry three decimals.
- **FR-008**: `profile_reset` MUST forget every record and every open block.
- **FR-009**: A block name MUST be used only as data: never inside arithmetic, where an older Bash would run a subscript such as `x$(cmd)` as a command.

### Key Entities

- **Block**: A named, timed span; by hand between `profile_begin` and `profile_end`, or a function call under `profile_start`.
- **Self time**: A block's time less the time of the blocks that ended inside it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script finds its slowest block from one report, without editing its functions.
- **SC-002**: A script with profiling off runs no slower than without the module's marks being reached.

## Integration Tests *(mandatory)*

- **IT-001**: Nest two blocks around sleeps and check calls, total and self per name.
- **IT-002**: Stop on an unmatched or unopened `profile_end`.
- **IT-003**: `profile_run` returns its command's exit code and records the block when the command fails.
- **IT-004**: In a child Bash 5 script with `DYBATPHO_PROFILE=true`, profile `f` calling `g`; both appear, `f`'s total covers `g`'s, and no profiler or library internal appears.
- **IT-005**: Without `DYBATPHO_PROFILE`, `profile_start` installs no trap; a caller's `DEBUG` trap set under `set -T` is back after a profiled run.
- **IT-006**: `--tsv` prints a header and rows sorted by self time; `profile_reset` empties the report.
- **IT-007**: Report a block named `x$(touch file)` and find no file, on every Bash the suite runs.

## Acceptance Criteria *(mandatory)*

1. A nested block's time is never counted twice in self time.
2. Profiling off costs nothing beyond a function call per mark.
3. The caller's own `DEBUG` trap survives a profiled run whenever a function can see it.

## Design Notes *(not part of the contract)*

- Decided with the owner: manual marks by default; per-function timing only under `DYBATPHO_PROFILE=true`, through a `DEBUG` trap; self and total time rather than a full call tree.
- Decided by the designer: the switch is `DYBATPHO_PROFILE=true`, not `=1` as the issue wrote it, because the library reads `1` as false (`dybatpho::is true` follows exit codes). Per-function timing needs Bash 5's `EPOCHREALTIME` -- reading the clock through `date` in a trap that fires per command would make the profile measure itself. Storage is the module's own arrays rather than `metrics.sh`, whose counters and histograms do not express self time; `metrics` remains the place for production timing.
