# Feature Specification: Configuration Loading and Precedence

**Feature Branch**: `[reverse-spec-config]`
**Status**: Implemented
**Input**: Existing source analysis: `src/config.sh`, `doc/config.md`, and `test/config.bats`

## Problem Statement *(mandatory)*

Shell scripts need to combine dotenv, JSON, and YAML configuration without
sourcing untrusted shell code or hand-writing precedence and validation logic.
They also need a predictable way to overlay environment variables and expose
the resulting values to shell commands.

## Business Value *(mandatory)*

- Centralize configuration parsing and precedence rules.
- Keep configuration data separate from executable shell code.
- Make required settings and optional defaults easy to validate.
- Allow the same loaded configuration to be queried or exported for child
  processes.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load layered configuration files (Priority: P1)

As a script author, I want to load dotenv, JSON, and YAML files in order so
that environment-specific files can override shared defaults.

**Independent Test**: Load multiple files with overlapping keys and verify the
last file wins.

**Acceptance Scenarios**:

1. **Given** dotenv, JSON, or YAML files, **When** `config_load` is called,
   **Then** their key/value pairs are stored in the shared configuration map
2. **Given** multiple files define the same key, **When** files are loaded
   left to right, **Then** the later value replaces the earlier value
3. **Given** a dotenv file contains comments, whitespace, quoted values, or
   escaped double-quoted values, **When** it is loaded, **Then** those values
   are parsed without executing shell code

### User Story 2 - Overlay environment configuration (Priority: P1)

As an operator, I want environment variables to override file values, with an
optional prefix to limit which variables are imported.

**Independent Test**: Load a file, set prefixed and unprefixed variables, and
verify only the selected environment values are applied.

**Acceptance Scenarios**:

1. **Given** a prefix such as `APP_`, **When** `config_env APP_` runs, **Then**
   matching variables are imported with the prefix removed
2. **Given** a value exists in a file and in the selected environment, **When**
   the environment overlay runs, **Then** the environment value wins
3. **Given** no prefix is supplied, **When** `config_env` runs, **Then**
   environment variables with valid configuration keys are imported as-is

### User Story 3 - Read and validate effective settings (Priority: P1)

As a script author, I want lookup, defaults, and required-key checks so that
missing configuration fails before work begins.

**Independent Test**: Query present and absent keys, use a lookup default, and
require both present and missing keys.

**Acceptance Scenarios**:

1. **Given** a loaded key, **When** `config_get` runs, **Then** it prints the
   stored value
2. **Given** a missing key and a fallback, **When** `config_get` runs, **Then**
   it prints the fallback without changing the configuration map
3. **Given** one or more required keys are absent, **When** `config_require`
   runs, **Then** it fails with a diagnostic naming the missing key

### User Story 4 - Export configuration for shell consumers (Priority: P2)

As a script author, I want loaded values exported as shell variables so that
child commands can consume the effective configuration.

**Independent Test**: Load valid shell-compatible keys, export them with and
without a prefix, and verify the variables are exported.

**Acceptance Scenarios**:

1. **Given** loaded keys that are valid shell identifiers, **When**
   `config_export` runs, **Then** corresponding variables are exported
2. **Given** a configuration key or prefix cannot be represented as a shell
   variable, **When** export is requested, **Then** it fails instead of
   creating an invalid assignment

### Example Workflow

```bash
dybatpho::config_load defaults.env production.yaml
dybatpho::config_env APP_
dybatpho::config_require HOST
host="$(dybatpho::config_get HOST)"
dybatpho::config_export
```

### User Story 5 - Validate typed configuration (Priority: P1)

As a maintainer, I want to declare schemas for configuration keys so that
merged values are type-checked and optional defaults are applied before the
application starts.

**Independent Test**: Declare string, integer, boolean, URL, and enum schemas,
then verify defaults, required keys, ranges, and choices.

**Acceptance Scenarios**:

1. **Given** a schema with `default:value`, **When** `config_validate` runs and
   the key is missing, **Then** the default is added to the configuration map
2. **Given** a required schema key is missing, **When** validation runs, **Then**
   it fails with a key-specific diagnostic
3. **Given** an integer, boolean, URL, or enum value violates its schema,
   **When** validation runs, **Then** it fails with the relevant type, range,
   or choice diagnostic

## Edge Cases

- No configuration files or no required keys are supplied.
- A file is missing or has an unsupported extension.
- Dotenv contains an invalid assignment, inline comments, or quoted escapes.
- JSON/YAML is malformed or its root is not an object/mapping.
- A structured backend emits a key containing characters that are not allowed
  by the configuration-key grammar.
- A prefixed environment variable would produce an invalid key.
- A missing key is queried without a default.
- A configuration key contains `.` or `-` and therefore cannot be exported as
  a shell variable.
- A schema uses an unsupported type or rule.
- A required value is missing, a default is defined, or an integer is outside
  its declared bounds.
- An enum value is not included in its comma-separated choices.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST maintain a shared key/value configuration map.
- **FR-002**: `config_load` MUST require at least one file and support `.env`,
  `.dotenv`, `.json`, `.yaml`, and `.yml` files.
- **FR-003**: Configuration files MUST be applied from left to right, with
  later files taking precedence.
- **FR-004**: Dotenv loading MUST parse comments, whitespace, single quotes,
  double quotes, and escaped double-quoted values without sourcing the file.
- **FR-005**: JSON loading MUST use `jq`, require an object root, and reject
  malformed data or invalid keys.
- **FR-006**: YAML loading MUST use the supported `yq` interface, require a
  mapping root, and reject malformed data or invalid keys.
- **FR-007**: Configuration keys MUST match
  `[a-zA-Z_][a-zA-Z0-9_.-]*`.
- **FR-008**: `config_env` MUST import all variables matching an optional
  prefix and apply them after file values.
- **FR-009**: `config_get` MUST print a stored value, print an optional default
  for a missing key, and fail when neither exists.
- **FR-010**: `config_require` MUST fail when any named key is absent.
- **FR-011**: `config_export` MUST export loaded shell-compatible keys with an
  optional valid shell-identifier prefix.
- **FR-012**: Invalid files, keys, prefixes, or required settings MUST fail
  through the library's diagnostic path.
- **FR-013**: `config_schema` MUST declare `string`, `int`, `bool`, `url`, or
  `enum` types for valid configuration keys.
- **FR-014**: Schema rules MUST support `required`, `default`, `min`, `max`, and
  `choices`, and MUST reject unsupported rule names or types.
- **FR-015**: `config_validate` MUST apply declared defaults for missing optional
  keys and reject missing required keys.
- **FR-016**: Validation MUST enforce integer, boolean, URL, and enum values,
  plus numeric minimum and maximum bounds where declared.

### Key Entities *(include if feature involves data)*

- **Configuration Map**: The process-global `DYBATPHO_CONFIG` associative
  array containing effective values.
- **Configuration File**: A dotenv, JSON, or YAML input loaded in precedence
  order.
- **Configuration Key**: A validated key used for lookup and requirement checks.
- **Environment Overlay**: Values imported from variables, optionally after a
  prefix is removed.
- **Exported Variable**: A shell variable derived from a configuration key
  during `config_export`.
- **Configuration Schema**: A set of type and validation rules stored in
  `DYBATPHO_CONFIG_SCHEMA`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script can load layered dotenv/JSON/YAML configuration with one
  call per file set.
- **SC-002**: Environment overlays consistently take precedence over files.
- **SC-003**: Missing required settings fail before dependent work runs.
- **SC-004**: Shell-compatible settings can be exported without unsafe sourcing.
- **SC-005**: Merged configuration can be validated consistently before
  application startup, with defaults applied in one step.

## Integration Tests *(mandatory)*

- **IT-001**: Load dotenv files with comments, quoting, escapes, and precedence.
- **IT-002**: Load JSON and YAML mappings and verify later values override
  earlier values.
- **IT-003**: Apply a prefixed environment overlay and verify unrelated
  variables are ignored.
- **IT-004**: Query existing and missing keys with and without defaults.
- **IT-005**: Require present and missing keys and verify clear failures.
- **IT-006**: Export valid keys and reject invalid prefixes or non-shell keys.
- **IT-007**: Reject missing files, unsupported formats, malformed structured
  data, and invalid keys.
- **IT-008**: Declare schemas for all supported types, apply defaults, enforce
  integer ranges and URLs, validate enum choices, and reject invalid schema
  declarations.

## Acceptance Criteria *(mandatory)*

1. Configuration behavior is deterministic and does not execute configuration
   files as shell programs.
2. File, environment, lookup, validation, and export workflows use one shared
   precedence model.
3. Failures identify the invalid file, key, prefix, or missing requirement.
