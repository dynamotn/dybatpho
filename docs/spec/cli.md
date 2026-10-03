# Feature Specification: Declarative CLI Generation

**Feature Branch**: `[reverse-spec-cli]`
**Status**: Implemented
**Input**: Existing source analysis: `src/cli.sh`, `docs/cli.md`, `test/cli.bats`, `example/cli_basic.sh`, `example/cli_advanced.sh`, and `example/cli_ux.sh`

## Problem Statement *(mandatory)*

Building non-trivial Bash CLIs by hand requires repetitive parsing, help rendering, subcommand dispatch, validation, and error handling code. This makes advanced CLIs hard to maintain and easy to break.

## Business Value *(mandatory)*

- Allow shell CLIs to be declared from compact specs rather than hand-written parsers.
- Keep parsing, help output, and command behavior aligned from one source of truth.
- Bring Cobra-like ergonomics to Bash scripts without external parser code generation tools.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Define a command declaratively (Priority: P1)

As a CLI author, I want to describe flags, params, subcommands, and actions in shell spec functions so that the library can generate the parser for me.

**Why this priority**: Spec-driven parsing is the core differentiator of this module.

**Independent Test**: Define a root command and subcommands with `dybatpho::opts::*`, then verify parsing and action dispatch from the generated parser.

**Acceptance Scenarios**:

1. **Given** a spec defines options and a root action, **When** the generated parser receives valid input, **Then** variables are initialized, options are parsed, and the configured action runs
2. **Given** a spec defines nested subcommands, **When** the parser receives a subcommand path, **Then** dispatch transfers control to the matching child spec

---

### User Story 2 - Expose discoverable CLI help (Priority: P1)

As an end user, I want automatically generated help text so that I can understand commands, options, aliases, and required inputs without reading source code.

**Why this priority**: Help output is the user-facing contract of a CLI and must stay synchronized with parsing rules.

**Independent Test**: Generate help at the root and nested-command level and verify usage, descriptions, options, commands, aliases, hidden items, and required markers.

**Acceptance Scenarios**:

1. **Given** a command exposes visible options and subcommands, **When** help is requested, **Then** usage and readable sections are rendered from the spec
2. **Given** a spec marks items as hidden or deprecated, **When** help is requested, **Then** hidden items are omitted and deprecated items are annotated

---

### User Story 3 - Enforce richer command contracts (Priority: P2)

As a maintainer, I want positional argument validation, aliases, persistent options, hidden and deprecated items, and lifecycle hooks so that Bash CLIs can support more advanced usage patterns.

**Why this priority**: These richer contracts make the generated CLI practical for larger real-world scripts.

**Independent Test**: Use named and raw argument rules, aliases, persistent options, and pre/post-run hooks in a nested command tree and verify each behavior works from the generated parser.

**Acceptance Scenarios**:

1. **Given** a command declares argument-count rules, **When** the parser receives too few or too many positional arguments, **Then** a standardized argument-count failure is reported
2. **Given** a command declares `prerun`, `action`, and `postrun`, **When** parsing succeeds, **Then** the three lifecycle steps run in the configured order for the active command only

---

### User Story 4 - Provide interactive and shell-native UX (Priority: P1)

As a CLI author, I want missing values to be requested interactively and command
names/options to be discoverable through shell completion so that generated
CLIs are approachable for both interactive users and automation.

**Why this priority**: Prompting and completion reduce input errors without
requiring each CLI to implement shell-specific integration code.

**Independent Test**: Define prompted, constrained, and multi-value parameters,
generate completion scripts for Bash, Zsh, and Fish, and verify the generated
artifacts expose the declared options and commands.

**Acceptance Scenarios**:

1. **Given** a parameter declares a prompt and is not supplied, **When** the
   command runs interactively, **Then** the user is prompted and the entered
   value is passed to the action
2. **Given** a parameter declares `choices`, **When** the user enters an
   invalid value, **Then** the prompt rejects it and requests another value
3. **Given** a parameter declares `multiple:true`, **When** the user selects
   multiple values using comma-separated values or a numeric range such as
   `1-3`, **Then** the action receives the selected values in order
4. **Given** a CLI spec contains options and subcommands, **When** completion is
   generated for Bash, Zsh, or Fish, **Then** the output contains the visible
   switches and command names for that shell
5. **Given** an application needs a standalone prompt or selection list,
   **When** `dybatpho::prompt` or `dybatpho::select` runs, **Then** it reads
   interactive input and returns the selected value according to its choices
   and default behavior

---

### User Story 5 - Reuse option metadata outside parsing (Priority: P2)

As a CLI maintainer, I want environment-variable defaults and generated schema
and man pages to come from the same spec so that runtime behavior and external
documentation cannot drift apart.

**Why this priority**: Shared metadata makes CLIs easier to deploy, document,
and integrate with tooling.

**Independent Test**: Define an option with `env`, `required`, aliases, and
description metadata, then verify environment fallback, JSON schema output, and
roff man-page output.

**Acceptance Scenarios**:

1. **Given** an option declares `env:NAME` and no command-line value is
   provided, **When** parsing starts, **Then** the option variable is initialized
   from `NAME`
2. **Given** both an environment value and a command-line value are present,
   **When** parsing starts, **Then** the explicit command-line value takes
   precedence
3. **Given** a CLI spec is passed to schema generation, **When** JSON is
   generated, **Then** it includes command descriptions, options, switches,
   environment names, choices, prompts, and required/hidden metadata
4. **Given** a CLI spec is passed to man-page generation, **When** roff is
   generated, **Then** it documents visible options, required markers,
   environment variables, and subcommands

---

### Example Workflow

```bash
function _run_deploy {
  dybatpho::info "Deploying ${COMPONENT} to ${ENVIRONMENT}"
}

function _spec {
  dybatpho::opts::setup "Deployment tool" ARGS action:"_run_deploy"
  dybatpho::opts::param "Target environment" ENVIRONMENT -e --env \
    choices:dev,staging,prod required:true
  dybatpho::opts::param "Component to deploy" COMPONENT --component \
    env:DEPLOY_COMPONENT init:="api"
  dybatpho::opts::flag "Verbose output" VERBOSE -v --verbose
  dybatpho::opts::disp "Show help" --help action:"dybatpho::generate_help _spec"
}

# One spec drives parsing, help, completions, schema, and the man page.
dybatpho::generate_from_spec _spec "$@"
dybatpho::generate_completion _spec bash mytool
dybatpho::generate_schema _spec mytool
dybatpho::generate_man _spec mytool
```

## Edge Cases

- A user passes an unrecognized option, a forbidden argument, or an invalid subcommand.
- A parameter is required but omitted.
- An option or a positional argument is declared with an empty description.
- A description holds a control character, such as a bell or an ANSI colour code.
- A spec uses aliases, hidden items, deprecated items, persistent parent options, and nested command paths simultaneously.
- A prompt receives EOF or an empty value without a default.
- A choice list contains multiple values and the user enters a mixture of names
  and numeric selections.
- A multi-value prompt receives an invalid, descending, or out-of-range numeric
  range.
- An environment variable is configured with an invalid shell identifier.
- An option is bound with `config:<key>` while the `config` module is not
  loaded, including a dotted key such as `server.port`.
- Completion generation is requested for an unsupported shell.
- Schema or man-page metadata contains quotes, backslashes, or newlines.
- A standalone prompt or selection helper receives EOF or an invalid choice.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST allow command specs to declare setup behavior, flags, params, display options, and subcommands using shell functions.
- **FR-002**: The generated parser MUST initialize variables, parse options, validate input, and dispatch to the correct action or subcommand.
- **FR-003**: The module MUST generate human-readable help output from the same spec data used for parsing.
- **FR-004**: The module MUST support positional argument validation using raw and Cobra-style rule names.
- **FR-005**: The module MUST support aliases, persistent options, hidden items, deprecated items, custom labels, and required parameters.
- **FR-006**: The module MUST support command lifecycle hooks that run before and after the main action when parsing succeeds.
- **FR-007**: The module MUST emit standardized error messages for invalid command-line input.
- **FR-008**: The module MUST allow debug inspection of generated parser output through the documented debug toggle.
- **FR-009**: The module MUST support interactive prompts for missing parameter values, including optional defaults.
- **FR-010**: The module MUST support constrained choices and multi-value
  selection for parameters and provide standalone prompt and choice-selection
  helpers, including validation of named or numbered choices.
- **FR-011**: The module MUST generate completion scripts for Bash, Zsh, and Fish from the CLI spec.
- **FR-012**: The module MUST allow options to declare an environment variable fallback using `env:NAME`.
- **FR-013**: Explicit command-line values MUST take precedence over environment-variable fallbacks.
- **FR-014**: The module MUST generate a machine-readable JSON schema from the same CLI spec.
- **FR-015**: The module MUST generate a roff man page from the same CLI spec.
- **FR-016**: Generated schema and man-page output MUST preserve relevant option and command metadata, including descriptions, aliases, visibility, required state, choices, prompts, and environment names.
- **FR-017**: The CLI spec documentation MUST describe the `env:`, `prompt:`, `choices:`, and `multiple:` option attributes and their supported scope.
- **FR-018**: The option DSL MUST support setup, flag, parameter, display, and
  child-command declarations through `dybatpho::opts::*`.
- **FR-019**: `opts::validate_choice` MUST accept only declared choice names
  and reject values outside the declared set; `select` MUST additionally
  support numeric selections and ascending ranges in multi-select mode.
- **FR-020**: An unrecognized option or invalid command MUST be reported with
  the closest accepted switch or command name when one is near enough by
  Levenshtein distance, comparing with leading dashes ignored.
- **FR-021**: A command that declares at least one switch MUST reject an
  unmatched `-x` or `--xy` instead of collecting it as a positional argument;
  `--` MUST remain the way to pass dashed values through, and a command that
  declares no switches MUST keep collecting them.
- **FR-022**: `negatable:true` MUST generate a `--no-<name>` switch for every
  long switch and alias of a flag, and MUST default the off value to `false`
  when no `off:` is declared.
- **FR-023**: `count:true` MUST record how many times a flag appeared rather
  than a value, starting from `0`, so that repeated and clustered forms such as
  `-v -v` and `-vv` both yield `2`.
- **FR-024**: `config:<key>` MUST bind an option to a configuration key loaded
  by `src/config.sh`, and the resolved precedence MUST be
  flag > `env:` > `config:` > `init:`.
- **FR-025**: `dybatpho::opts::arg` MUST document positional arguments for the
  usage line, help, schema, and man page, and MUST derive the `args:<rule>`
  count check when the spec declares no explicit rule.
- **FR-026**: Generated help MUST follow conventional command-line layout: a
  usage line naming `COMMAND` only when subcommands exist, then `Arguments`,
  `Commands`, and `Options` sections aligned to one shared column, with
  per-option `env`, `config`, `choices`, `default`, and repeatability
  annotations and the automatic `-h, --help` row.
- **FR-027**: `dybatpho::generate_completion` MUST cache its output keyed by a
  hash of the script declaring the spec, and MUST bypass the cache when
  `DYBATPHO_CLI_CACHE` is false or the declaring script cannot be read.
- **FR-028**: Loading `cli` MUST NOT load `config`. A `config:<key>` binding
  MUST fall through to `init:` without error when the `config` module is not
  loaded, whatever characters the key contains.
- **FR-029**: Option, command, and argument metadata MUST keep every field in place when one of them is empty, so an empty description never shifts the switches, environment name, or any later field in the schema, man page, completions, or help.
- **FR-030**: The JSON schema MUST escape every control character in a string value, the way the library's JSON string escaper does, so any description yields valid JSON.

### Key Entities *(include if feature involves data)*

- **CLI Spec**: A shell function that describes one command level through `dybatpho::opts::*` calls.
- **Generated Parser**: The runtime shell logic emitted from a CLI spec to parse and dispatch user input.
- **Help Row**: A rendered option or command entry derived from spec metadata.
- **Option Metadata**: The shared description of a flag or parameter, including switches, aliases, environment fallback, choices, prompt behavior, visibility, and required state.
- **Completion Artifact**: A shell-specific Bash, Zsh, or Fish script generated from command and option metadata.
- **CLI Schema**: A JSON representation of the command tree and option metadata.
- **Man Page**: A roff reference document generated from the command tree and visible option metadata.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A CLI author can express advanced command trees without maintaining a separate manual parser.
- **SC-002**: Help output stays synchronized with command behavior because both derive from the same spec.
- **SC-003**: Nested command trees support advanced metadata such as aliases, persistence, deprecation, and hooks without custom parsing code.
- **SC-004**: A single spec can produce usable Bash, Zsh, and Fish completion artifacts without manually duplicating option names.
- **SC-005**: Deployments can configure options through declared environment variables while preserving explicit CLI overrides.
- **SC-006**: The same spec can produce valid JSON schema and roff man-page artifacts that describe the exposed CLI.
- **SC-007**: A mistyped switch or command is answered with the correction instead of a bare rejection, so the user does not have to re-read the help to find the name they meant.
- **SC-008**: One precedence chain — flag, environment, configuration file, default — covers every bound option, so a CLI no longer wires configuration into options by hand.
- **SC-009**: Generated help reads like a conventional command-line tool, with the accepted arguments and the source of every option value visible without consulting the source.

## Integration Tests *(mandatory)*

- **IT-001**: Generate a parser from a nested root spec and verify valid command paths dispatch to the expected actions.
- **IT-002**: Request help at the root and child-command levels and verify usage, options, commands, aliases, and visibility rules.
- **IT-003**: Exercise named argument validators, persistent options, deprecated items, and lifecycle hooks in one CLI tree and verify the resulting behavior.
- **IT-004**: Generate Bash, Zsh, and Fish completion for a spec and verify visible options, aliases, and subcommands are present.
- **IT-005**: Run a spec with `env:NAME`, a prompted parameter, choices, and `multiple:true`; verify environment fallback, prompt selection, and explicit option precedence.
- **IT-006**: Generate schema and man-page artifacts from one spec and verify valid JSON plus documented options, environment names, and subcommands.
- **IT-007**: Pass a mistyped switch and a mistyped command to a spec that declares both, and verify each error names the closest accepted alternative and stays silent when nothing is close.
- **IT-008**: Declare a `negatable:true` flag and a `count:true` flag, and verify `--no-` turns the flag off while repeated and clustered short forms accumulate.
- **IT-009**: Bind an option with both `env:` and `config:`, and verify the resolved value follows flag > environment > configuration > default.
- **IT-010**: Declare positional arguments and verify the usage line, the `Arguments` section, the derived count rule, and the schema and man-page entries all describe them.
- **IT-011**: Generate completion twice for one spec and verify the second run reuses the cached artifact, and that disabling the cache writes nothing.
- **IT-012**: In a child shell that loaded only `cli`, verify plain and dotted `config:` bindings fall through to their defaults, and that the plain one reads the loaded file once `config` is loaded.
- **IT-013**: Declare a parameter, a flag, and an argument with empty descriptions, and verify the schema stays valid JSON with every field in place, the man page names the switch and its environment variable, and help keeps the annotation on its own line.
- **IT-014**: Generate the schema for a command and a flag whose descriptions hold a bell, ANSI colour codes and a form feed, and read both descriptions back intact with `jq`.

## Acceptance Criteria *(mandatory)*

1. The CLI module provides a credible declarative alternative to hand-written Bash argument parsing.
2. Advanced features remain accessible through the same `dybatpho::opts::*` DSL instead of requiring separate extension APIs.
3. Completion, interactive input, environment configuration, schema, and man-page output are all derived from the same CLI spec.
