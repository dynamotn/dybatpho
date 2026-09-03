# Feature Specification: Semantic Version Utilities

**Feature Branch**: `[reverse-spec-semver]`
**Status**: Implemented
**Input**: Existing source analysis: `src/semver.sh`, `doc/semver.md`, and `test/semver.bats`

## Problem Statement *(mandatory)*

Release scripts need to validate, inspect, compare, and increment
Semantic-Version-like values. Reimplementing precedence rules and version
parsing in Bash is error-prone, especially for pre-release and build metadata.
This module follows SemVer 2.0.0 precedence while accepting the syntax defined
by its current validation regex.

## Business Value *(mandatory)*

- Centralize SemVer 2.0.0 behavior for release automation.
- Make version comparisons and bumps predictable across scripts.
- Provide structured components for changelog and artifact workflows.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate and parse versions (Priority: P1)

As a release script author, I want to validate SemVer strings and extract
their components so that invalid releases fail early and metadata is reusable.

**Independent Test**: Validate canonical, `v`-prefixed, pre-release, build,
and invalid strings, then inspect parsed components.

**Acceptance Scenarios**:

1. **Given** a valid SemVer 2.0.0 string with an optional leading `v`, **When**
   validation runs, **Then** it succeeds
2. **Given** an invalid version, **When** validation or parsing runs, **Then**
   it fails with no misleading parsed result
3. **Given** a valid version, **When** parsing runs, **Then** major, minor,
   patch, pre-release, and build metadata are printed on separate lines

### User Story 2 - Compare versions correctly (Priority: P1)

As a maintainer, I want precedence-aware comparison so that release gates and
dependency checks handle numeric and alphanumeric pre-release identifiers.

**Independent Test**: Compare numeric core changes, release vs pre-release,
numeric vs alphanumeric identifiers, and equal versions with differing build
metadata.

**Acceptance Scenarios**:

1. **Given** two valid versions, **When** comparison runs, **Then** it prints
   `-1`, `0`, or `1` according to SemVer precedence
2. **Given** versions differ only in build metadata, **When** comparison runs,
   **Then** it reports equality because build metadata does not affect
   precedence

### User Story 3 - Bump and classify releases (Priority: P1)

As a release engineer, I want to bump major/minor/patch values and classify
the change between two versions so that release automation can select the
right workflow.

**Independent Test**: Bump each supported part with optional metadata and
classify core, pre-release, build-only, and equal changes.

**Acceptance Scenarios**:

1. **Given** a valid version and `major`, `minor`, or `patch`, **When** bump
   runs, **Then** the selected component increments and lower components reset
   as required
2. **Given** optional pre-release or build values, **When** bump runs, **Then**
   those values are attached to the new version
3. **Given** two valid versions, **When** release type runs, **Then** it prints
   `major`, `minor`, `patch`, `pre-release`, `build`, or `equal`

## Edge Cases

- A version has a leading `v`.
- Numeric components or metadata use syntax accepted by the current validation
  regex, including forms that a stricter SemVer parser might reject.
- Pre-release identifiers are mixed numeric and alphanumeric segments.
- Build metadata differs while precedence remains equal.
- A version is missing, malformed, or has invalid components.
- An unsupported bump part is supplied.
- Bumping drops source pre-release/build metadata unless replacements are given.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST validate versions against its supported SemVer
  grammar with an optional leading `v`.
- **FR-002**: `semver_parse` MUST print major, minor, patch, pre-release, and
  build metadata as five lines.
- **FR-003**: Invalid versions MUST fail validation and parsing clearly.
- **FR-004**: `semver_compare` MUST implement SemVer 2.0.0 precedence,
  including numeric core and pre-release identifier ordering.
- **FR-005**: Build metadata MUST be ignored by precedence comparison.
- **FR-006**: `semver_bump` MUST support only `major`, `minor`, and `patch`.
- **FR-007**: Major bumps MUST reset minor and patch; minor bumps MUST reset
  patch; patch bumps MUST preserve major and minor.
- **FR-008**: Bumps MUST remove source pre-release/build metadata and optionally
  append caller-provided replacements.
- **FR-009**: `semver_release_type` MUST classify major, minor, patch,
  pre-release, build-only, and equal changes.
- **FR-010**: Release classification MUST reject invalid input versions.
- **FR-011**: The module MUST expose `DYBATPHO_SEMVER_REGEX` for the active
  validation grammar.

### Key Entities *(include if feature involves data)*

- **SemVer**: A `major.minor.patch` version with optional pre-release and build
  metadata.
- **Pre-release Identifier**: Dot-separated numeric or alphanumeric identifier
  compared with SemVer precedence rules.
- **Build Metadata**: Optional `+` metadata ignored for precedence but
  distinguishable by release classification.
- **Release Type**: The category emitted for a version transition.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Release scripts can validate and compare versions without custom
  parsing logic.
- **SC-002**: Version bumps preserve SemVer reset rules and requested metadata.
- **SC-003**: Release classification distinguishes precedence changes,
  pre-release changes, build-only changes, and equality.

## Integration Tests *(mandatory)*

- **IT-001**: Validate canonical, `v`-prefixed, pre-release, build, and invalid
  versions.
- **IT-002**: Parse all five SemVer components and verify empty optional lines.
- **IT-003**: Compare core and pre-release precedence plus build-only changes.
- **IT-004**: Bump major, minor, and patch versions with optional metadata.
- **IT-005**: Classify major, minor, patch, pre-release, build, and equal pairs.
- **IT-006**: Reject invalid versions and unsupported bump parts.

## Acceptance Criteria *(mandatory)*

1. SemVer behavior follows the documented SemVer 2.0.0 precedence contract.
2. Output helpers are suitable for command substitution and release scripts.
3. Invalid inputs fail rather than producing a partially interpreted version.
