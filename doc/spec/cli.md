# Feature Specification: Declarative CLI Generation

**Feature Branch**: `[reverse-spec-cli]`
**Created**: 2026-03-13
**Status**: Draft
**Input**: Existing source analysis: "src/cli.sh and example/cli_advanced.sh"

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

### Edge Cases

- A user passes an unrecognized option, a forbidden argument, or an invalid subcommand.
- A parameter is required but omitted.
- A spec uses aliases, hidden items, deprecated items, persistent parent options, and nested command paths simultaneously.

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

### Key Entities *(include if feature involves data)*

- **CLI Spec**: A shell function that describes one command level through `dybatpho::opts::*` calls.
- **Generated Parser**: The runtime shell logic emitted from a CLI spec to parse and dispatch user input.
- **Help Row**: A rendered option or command entry derived from spec metadata.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A CLI author can express advanced command trees without maintaining a separate manual parser.
- **SC-002**: Help output stays synchronized with command behavior because both derive from the same spec.
- **SC-003**: Nested command trees support advanced metadata such as aliases, persistence, deprecation, and hooks without custom parsing code.

## Integration Tests *(mandatory)*

- **IT-001**: Generate a parser from a nested root spec and verify valid command paths dispatch to the expected actions.
- **IT-002**: Request help at the root and child-command levels and verify usage, options, commands, aliases, and visibility rules.
- **IT-003**: Exercise named argument validators, persistent options, deprecated items, and lifecycle hooks in one CLI tree and verify the resulting behavior.

## Acceptance Criteria *(mandatory)*

1. The CLI module provides a credible declarative alternative to hand-written Bash argument parsing.
2. Advanced features remain accessible through the same `dybatpho::opts::*` DSL instead of requiring separate extension APIs.
