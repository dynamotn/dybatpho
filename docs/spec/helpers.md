# Feature Specification: Validation, Predicates, Retry, and Breakpoint Helpers

**Feature Branch**: `[reverse-spec-helpers]`
**Status**: Implemented
**Input**: Existing source analysis: `src/helpers.sh`, `docs/helpers.md`, `test/helpers.bats`, and `example/helpers_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts frequently repeat argument checks, environment guards, command presence checks, generic predicates, fallback-value selection, env defaults, retry loops, assertions, and ad hoc interactive debugging hooks. Re-implementing these primitives in every script increases inconsistency and failure risk.

## Business Value *(mandatory)*

- Standardize fail-fast validation at script boundaries.
- Reduce duplication of shell condition checks and retry loops.
- Provide a simple escape hatch for interactive debugging in complex scripts.
- Make fallback configuration selection consistent across scripts.
- Cover more of the small guardrails that shell scripts usually re-implement locally.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fail fast on bad input (Priority: P1)

As a function author, I want reusable argument and environment validation so that scripts stop immediately when required inputs are missing.

**Why this priority**: Bad input validation is one of the most common shell failure points and should be solved centrally.

**Independent Test**: Use the expectation helpers with valid and invalid inputs and verify assignment, success, and failure behavior.

**Acceptance Scenarios**:

1. **Given** a reusable function expects named arguments, **When** the argument helper runs with complete input, **Then** the requested local variables are assigned in order
2. **Given** a required environment variable is empty or missing, **When** the environment helper runs, **Then** execution stops with a clear failure

---

### User Story 2 - Retry transient operations safely (Priority: P1)

As an operator, I want retry logic with progress messages so that flaky commands such as network requests can recover without custom loops in every script.

**Why this priority**: Retries are a cross-cutting operational concern and a frequent source of duplicated code.

**Independent Test**: Run a command that succeeds after one or more failures and verify retries, delay progression, and final outcomes.

**Acceptance Scenarios**:

1. **Given** a command fails initially but later succeeds, **When** the retry helper wraps it, **Then** the command is retried until it succeeds or retries are exhausted
2. **Given** a command never succeeds, **When** the retry budget is consumed, **Then** the helper returns the final failure and warns that retries are exhausted
3. **Given** a retry budget larger than the cap allows, **When** the delays are computed, **Then** they grow exponentially and stop at the cap rather than growing without bound
4. **Given** jitter is enabled, **When** the same attempt is computed repeatedly, **Then** the delay varies within one base delay and never exceeds the cap

---

### User Story 3 - Choose the first usable fallback value (Priority: P2)

As a script author, I want a coalesce helper so that environment variables, arguments, and defaults can be checked in priority order without hand-written branching.

**Why this priority**: Fallback selection is a small but common helper pattern across shell entrypoints.

**Independent Test**: Pass empty and non-empty values to the coalesce helper and verify it prints the first non-empty value or fails when none exist.

**Acceptance Scenarios**:

1. **Given** several candidate values and only one early value is non-empty, **When** the coalesce helper runs, **Then** it prints that first non-empty value
2. **Given** all candidate values are empty, **When** the coalesce helper runs, **Then** it fails without printing output
3. **Given** several command names, **When** the command-coalesce helper runs,
   **Then** it prints the first installed command or fails when none is found
4. **Given** an empty environment variable and a default, **When** the
   default-environment helper runs, **Then** it assigns, exports, and prints
   the default value

---

### User Story 4 - Express reusable guards and assertions (Priority: P1)

As a script author, I want common file, command, numeric, boolean, and
environment predicates plus assertions so that control flow stays readable.

**Independent Test**: Evaluate representative `is` conditions, check all/any
command and environment helpers, and assert both successful and failing shell
conditions.

**Acceptance Scenarios**:

1. **Given** a supported condition such as `file`, `dir`, `command`, `true`,
   `false`, `number`, or `int`, **When** `dybatpho::is` runs, **Then** it
   returns the documented result (and prints normalized numeric values for
   numeric conditions)
2. **Given** all listed commands or at least one listed environment variable
   is available, **When** the corresponding helper runs, **Then** it succeeds;
   otherwise it fails clearly
3. **Given** a false shell condition, **When** `assert` runs, **Then** it
   stops with the supplied or generated assertion message

---

### User Story 5 - Pause for interactive debugging (Priority: P3)

As a maintainer, I want an optional interactive breakpoint so that I can
inspect shell options, variables, arrays, and source context during local
debugging.

**Independent Test**: Invoke the breakpoint in an interactive session and
verify its documented inspection and quit controls.

---

### Example Workflow

```bash
function _deploy {
  local environment token
  dybatpho::expect_args environment token -- "$@"

  dybatpho::require curl
  dybatpho::expect_envs DEPLOY_HOST
  dybatpho::assert "[[ -n '${token}' ]]" "A deploy token is required"

  # Try three times, two seconds apart, before giving up.
  dybatpho::retry_until 3 2 "curl -sSf https://${DEPLOY_HOST}/health" "health check"
}

editor="$(dybatpho::coalesce "${VISUAL:-}" "${EDITOR:-}" "vi")"
timeout="$(dybatpho::default_env DEPLOY_TIMEOUT 30)"
dybatpho::is int "${timeout}" || dybatpho::die "DEPLOY_TIMEOUT must be an integer"

_deploy prod "${DEPLOY_TOKEN:-}"
```

## Edge Cases

- A variable name passed to the argument helper is invalid.
- A predicate is asked to evaluate an unsupported condition.
- `is number` or `is int` receives a non-numeric value.
- A command or environment list is empty.
- A required command is given as a path that is missing, is a directory, or is a file without the executable bit.
- Coalesce receives no candidate values or only empty values.
- Retry is used with a noisy shell command string that needs a shorter description.
- The retried command keeps state in a variable whose name matches one the retry loop uses, such as `count` or `delay`.
- The caller wants fixed-delay retries instead of escalating delays.
- An assertion condition contains shell syntax evaluated through `eval`.
- Breakpoint is invoked in unattended CI rather than an interactive terminal.
- `dybatpho::is int` or `dybatpho::is number` is given a quoted character such as `'a`, a hexadecimal `0x1F`, surrounding blanks, a decimal comma, or an integer with a leading zero.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST assign positional inputs into named variables through a reusable expectation helper.
- **FR-002**: The module MUST verify that required environment variables are set.
- **FR-003**: The module MUST verify that external commands are installed before work proceeds.
- **FR-003a**: The command check MUST accept an optional version range, written in the range syntax of `dybatpho::semver_satisfies`, and MUST stop the script when the installed version falls outside it.
- **FR-003b**: A range MUST be recognised only by its leading operator, one of `>`, `<`, `=`, `^`, or `~`, so that the same argument keeps its older meaning as an exit code and a bare number is never read as a range.
- **FR-003c**: The command check MUST verify that the command exists before it asks for a version, so the message names the real problem.
- **FR-003d**: When a range is given and the optional `semver` module is not loaded, the command check MUST stop the script with a message naming what to load, rather than let the range pass unchecked.
- **FR-003e**: When a range is given and the installed version cannot be read, the command check MUST stop the script, because a requirement that cannot be verified has not been met.
- **FR-003f**: The command check MUST normalize the reported version before matching it, so that a command answering `1.35` or `3.12-modified` is judged on the release it is.
- **FR-003g**: A command given as a path (a name holding `/`) MUST count as installed only when it is an existing executable file, not merely because the shell's command table accepts the name.
- **FR-004**: The module MUST provide `is` conditions for command, function,
  file, directory, link, existence, readable, writable, executable, set,
  empty, number, integer, true, and false values.
- **FR-005**: The module MUST provide a coalesce helper that prints the first non-empty value from a prioritized list of candidates.
- **FR-006**: The coalesce helper MUST fail when no candidate values are provided or all candidates are empty.
- **FR-007**: The module MUST provide a retry helper that retries shell command strings with delays and user-visible progress messages.
- **FR-007a**: Retry delays MUST grow exponentially from `DYBATPHO_RETRY_BASE_DELAY`, MUST never exceed `DYBATPHO_RETRY_MAX_DELAY`, and MUST add up to one base delay of random jitter when `DYBATPHO_RETRY_JITTER` is enabled. This is the policy `network.sh` already applies to HTTP retries; the generic helper grew its delay linearly and without a bound, so the same library answered the same question two different ways.
- **FR-008**: The module MUST provide an interactive breakpoint helper suitable for optional debugging workflows.
- **FR-009**: The module MUST provide a helper that verifies all listed commands exist.
- **FR-010**: The module MUST provide a helper that prints the first available command from a prioritized list.
- **FR-011**: The module MUST provide a helper that assigns and exports default values for empty environment variables.
- **FR-012**: The module MUST provide a helper that succeeds when any listed environment variable is set.
- **FR-013**: The module MUST provide an assertion helper that fails loudly when a shell condition is false.
- **FR-014**: The module MUST provide a fixed-delay retry helper in addition to the escalating retry helper.
- **FR-015**: The module MUST provide an argument-progress helper that reports
  whether more positional arguments remain.
- **FR-016**: The module MUST provide an interactive breakpoint with controls
  for runtime options, variables, arrays, source display, and quitting.
- **FR-017**: The module MUST provide a check that a caller-supplied variable
  name is safe to bind to a nameref, and MUST stop the script when it is not.
- **FR-017a**: That check MUST reject a name that is not a shell identifier.
- **FR-017b**: That check MUST reject any name in the `__dybatpho` namespace,
  which is reserved for the locals of functions that take a variable name. A
  name in that namespace binds the nameref to the library's own variable rather
  than to the caller's, which Bash reports as a `circular name reference` only
  when the collision is with the nameref itself and not at all otherwise.
- **FR-017c**: Every public function that binds a caller-supplied name MUST
  apply the check before binding, and MUST name its own locals inside the
  reserved namespace so that the check covers them.

- **FR-021**: The module MUST report which module defines a loaded function, accepting the name with or without the `dybatpho::` prefix, and MUST report `init` for a function the bootstrap defines.
- **FR-016a**: The lookup MUST use what Bash knows about the running shell rather than the contents of a directory, so the answer describes the code that is actually loaded.
- **FR-016b**: The lookup MUST switch `extdebug` on only for the one call it needs and MUST restore the option exactly as it found it, because that option also changes how `DEBUG` and `RETURN` traps behave.
- **FR-016c**: The module MUST also be able to report the file and line a function was defined at, and that line MUST be the line holding the definition.
- **FR-016d**: A function whose defining file is not a module source MUST NOT be attributed to a module. A bundle holds every module in one file, and naming that file as the module would be a wrong answer rather than a missing one.
- **FR-022**: The module MUST print the documentation comment of a loaded function, read out of the source the shell loaded, so it is available whether or not the generated documentation was ever produced or shipped.
- **FR-017a**: Rendering MUST drop the banner rules and any `shellcheck` directive standing between the comment and the definition, MUST remove one comment marker and the space after it from each line, and MUST remove the `@description` marker from the prose it introduces, leaving every other tag as written.
- **FR-017b**: The output MUST open with a heading naming the function and where it came from, including the module when one can be named.
- **FR-018**: The module MUST list the public functions the shell has loaded, in order, excluding the internal helpers, and MUST be able to limit that list to one module.
- **FR-019**: `dybatpho::is number` MUST accept exactly what `validate_is number` accepts, and `dybatpho::is int` MUST accept only optionally signed decimal integers without a leading zero, a subset of what `validate_is int` accepts; neither MUST depend on `printf` or `LC_NUMERIC`.
- **FR-020**: `dybatpho::retry` and `dybatpho::retry_until` MUST NOT shadow the caller's variables in the command they evaluate: their own bookkeeping uses names in the `__dybatpho_` namespace.
- **FR-018a**: Listing MUST NOT depend on an external command, since its purpose is to answer when nothing else is at hand.
- **FR-018b**: Listing for a module MUST stop the script when that module is not loaded, and when no function can be attributed to a module at all, rather than returning an empty list that would read as "this module exports nothing".

### Key Entities *(include if feature involves data)*

- **Expectation Contract**: The named-variable input contract declared by a reusable shell function.
- **Predicate Condition**: A supported condition type evaluated by the generic `dybatpho::is` helper.
- **Fallback Candidate**: One possible value considered by the coalesce helper in priority order.
- **Retry Policy**: A retry count plus either escalating or fixed delay.
- **Breakpoint Session**: An interactive inspection loop entered by the caller.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Reusable functions can validate their inputs with one call instead of hand-written parsing.
- **SC-002**: Callers can select the first usable configuration value with one helper call instead of hand-written branching.
- **SC-003**: Transient command retries become consistent across network and process workflows.
- **SC-004**: Callers can express common shell predicates with readable code instead of low-level test syntax.
- **SC-005**: Callers can validate all/any command and environment dependencies
  without duplicating loops.
- **SC-006**: Callers can select commands and assign exported defaults without
  repeating lookup or assignment boilerplate.

## Integration Tests *(mandatory)*

- **IT-001**: Use the argument helper to populate locals in a function and verify failure on missing values.
- **IT-002**: Evaluate representative predicate types such as `file`, `dir`, `command`, `true`, and `int` to verify behavior.
- **IT-003**: Pass empty and non-empty fallback candidates to coalesce and verify first-match and no-match behavior.
- **IT-004**: Run retry around a flaky command and verify escalating delays and final success.
- **IT-004a**: Verify the command check accepts a command inside its range and rejects one outside it, naming the version it found, with the default and a custom exit code.
- **IT-004b**: Verify a version that is not full SemVer, and one carrying a distribution's build marker, are judged on the release they are.
- **IT-004c**: Verify a bare second argument still means an exit code, that a missing command is reported before any version is asked for, and that an unreadable version stops the script.
- **IT-005a**: Verify the module reporter names the right module for a module function, a core function, one of its own, and a bootstrap function, with and without the name prefix, and fails for a function that is not defined.
- **IT-005b**: Verify the path reporter names the file and a line that really holds the definition.
- **IT-005c**: Verify `extdebug` is left off when it was off and on when it was on.
- **IT-005d**: Verify the describer prints the prose and the tags, strips the comment markers and the `@description` marker, and steps over a `shellcheck` directive standing above the function.
- **IT-005e**: Verify the function list is in order, excludes the internal helpers, and that limiting it to a module yields only functions that report that module.
- **IT-005f**: Verify listing an unloaded module stops the script.
- **IT-005g**: Inside a generated bundle, verify the describer still prints the comment, the path reporter still names the line, the module reporter fails rather than naming the bundle file, and listing a module stops the script with an explanation.
- **IT-005**: Verify command coalescing, default environment assignment, any/all
  environment checks, assertions, and fixed-delay retry behavior.
- **IT-017**: Verify the reference check accepts an ordinary name, rejects a
  non-identifier, and rejects a reserved `__dybatpho` name; and verify
  `array_sort` refuses a reserved name rather than silently sorting nothing,
  while still sorting an ordinary one.
- **IT-018**: Verify the command check accepts an executable given by path, and
  refuses a missing path, a file without the executable bit, and a directory.
- **IT-019**: Refuse `'a`, `0x1F`, blanks, `1,5`, `inf`, `010` and `08` as ints and the non-numbers among them as numbers, and verify over a sample set that `is number` agrees with `validate_is number` and that every value `is int` accepts, `validate_is int` accepts too.
- **IT-020**: Retry a command that counts its own attempts in a global `count` with both `retry` and `retry_until`, and verify every failure is retried and slept on in order.

## Acceptance Criteria *(mandatory)*

1. The module centralizes the defensive-programming patterns required by the rest of the library.
2. The helper contracts are easy to compose at the top of reusable shell functions and scripts.
3. Fallback value selection is available without open-coded `if`/`elif` chains in callers.
