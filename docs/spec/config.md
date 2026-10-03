# Feature Specification: Configuration Loading and Precedence

**Feature Branch**: `[reverse-spec-config]`
**Status**: Implemented
**Input**: Existing source analysis: `src/config.sh`, `docs/config.md`, `test/config.bats`, and `example/config_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts need to combine dotenv, JSON, YAML, and TOML configuration
without sourcing untrusted shell code or hand-writing precedence and validation
logic. They also need a predictable way to overlay environment variables and
expose the resulting values to shell commands.

Reading is only half of it. A script that changes a setting has to write it
back, and a hand-rolled rewrite loses the comments, the ordering, and the
structure the file already had. Deployments also layer a per-environment file
on top of a shared one, where the overlay is frequently absent, so a loader
that treats every missing file as fatal cannot express that shape.

## Business Value *(mandatory)*

- Centralize configuration parsing and precedence rules.
- Keep configuration data separate from executable shell code.
- Make required settings and optional defaults easy to validate.
- Allow the same loaded configuration to be queried or exported for child
  processes.
- Persist changed settings without destroying the comments and layout a
  human maintains in the same file.
- Express the common base-plus-profile overlay in one call, including the case
  where the profile has no file of its own.

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

### User Story 5 - Validate typed configuration (Priority: P1)

As a maintainer, I want to declare schemas for configuration keys so that
merged values are type-checked and optional defaults are applied before the
application starts.

**Independent Test**: Declare string, integer, boolean, URL, and enum schemas,
then verify defaults, required keys, ranges, and choices.

**Acceptance Scenarios**:

1. **Given** a schema with `default:value`, **When** `config_validate` runs and
   the key is missing, **Then** the default is added to the configuration map
2. **Given** a required schema key is missing and has no default, **When**
   validation runs, **Then** it fails with a key-specific diagnostic
3. **Given** an integer, boolean, URL, or enum value violates its schema,
   **When** validation runs, **Then** it fails with the relevant type, range,
   or choice diagnostic
4. **Given** several keys violate their schemas, **When** validation runs,
   **Then** every violation is reported once, named by its key, in declaration
   order

### User Story 6 - Generate a configuration reference (Priority: P2)

As a maintainer, I want the declared schema rendered as documentation so that
the published configuration reference cannot drift from the validation rules.

**Independent Test**: Declare schemas with descriptions and render the
reference in each supported format.

**Acceptance Scenarios**:

1. **Given** declared schemas, **When** `config_doc` runs, **Then** it prints a
   Markdown table of keys, types, required flags, defaults, constraints, and
   descriptions in declaration order
2. **Given** the `text` or `json` format, **When** `config_doc` runs, **Then**
   it prints the same metadata in that format
3. **Given** an unsupported format, **When** `config_doc` runs, **Then** it
   fails with a diagnostic

### User Story 7 - Overlay a profile on a base file (Priority: P1)

As an operator, I want a base configuration file and an environment-specific
overlay beside it so that one call selects the right settings per deployment.

**Independent Test**: Load `config.env` with profile `prod` and verify the
values from `config.prod.env` win, then repeat with a profile that has no file
and verify the base values remain.

**Acceptance Scenarios**:

1. **Given** a base file and a sibling `<stem>.<profile>.<extension>` file,
   **When** `config_profile` runs, **Then** the overlay values replace the base
   values
2. **Given** the profile file does not exist, **When** `config_profile` runs,
   **Then** the base values load and no error is reported
3. **Given** no profile argument, **When** `DYBATPHO_CONFIG_PROFILE` is set,
   **Then** it names the profile, and without it the call fails
4. **Given** a list of files where some may be absent, **When**
   `config_load --optional` runs, **Then** the missing ones are skipped and the
   present ones still merge left to right

### User Story 8 - Write settings back to their file (Priority: P1)

As a script author, I want to change a value and save it to the file it came
from so that the file keeps the format, comments, and structure it already has.

**Independent Test**: Load a commented dotenv file, change one key, save it,
and verify the comments, blank lines, order, and untouched keys all survive.

**Acceptance Scenarios**:

1. **Given** a loaded configuration, **When** `config_set` runs, **Then** the
   value joins the shared map and is visible to lookup, validation, and saving
2. **Given** a dotenv file with comments and blank lines, **When**
   `config_save` writes some of its keys, **Then** every other line is
   preserved verbatim and keys the file lacks are appended
3. **Given** a JSON, YAML, or TOML file, **When** `config_save` writes some of
   its keys, **Then** the keys it does not name keep their values and the
   document's own comments and layout survive
4. **Given** a key declared as `int` or `bool`, **When** it is saved to a
   structured file, **Then** it is written as a number or a boolean rather than
   as a string
5. **Given** a value that a dotenv file cannot carry bare, **When** it is
   saved, **Then** it is quoted and escaped so that loading the file returns
   the same value
6. **Given** the destination does not exist, **When** `config_save` runs,
   **Then** the file is created in the format its extension names

### Example Workflow

```bash
# Layer files, then overlay the environment.
dybatpho::config_load defaults.env production.yaml
dybatpho::config_load --optional /etc/app.local.env
dybatpho::config_env APP_

# Or let a profile name the overlay: config.yaml, then config.prod.yaml.
dybatpho::config_profile ./config.yaml prod

# Declare the contract, then enforce it once.
dybatpho::config_schema HOST url required:true description:"API base URL"
dybatpho::config_schema PORT integer default:8080 min:1 max:65535
dybatpho::config_schema MODE enum choices:dev,prod default:dev
dybatpho::config_validate

# Consume the effective values and publish the reference.
host="$(dybatpho::config_get HOST)"
dybatpho::config_export
dybatpho::config_doc markdown "App settings" > CONFIGURATION.md

# Change a value and write it back, keeping the file's comments and layout.
dybatpho::config_set PORT 9090
dybatpho::config_save ./config.yaml PORT
```

## Edge Cases

- No configuration files or no required keys are supplied.
- A file is missing or has an unsupported extension.
- Dotenv contains an invalid assignment, inline comments, or quoted escapes.
- A structured file nests mappings, holds sequences or empty mappings, or carries a tab, line break, or backslash inside a value.
- JSON/YAML is malformed or its root is not an object/mapping.
- A structured backend emits a key containing characters that are not allowed
  by the configuration-key grammar.
- A prefixed environment variable would produce an invalid key.
- A missing key is queried without a default.
- A configuration key contains `.` or `-` and therefore cannot be exported as
  a shell variable.
- A schema uses an unsupported type, an unsupported rule, or a rule value that
  is not valid for that rule.
- An `enum` schema is declared without `choices`, or with empty `choices`.
- The same key is declared twice, so the later declaration must replace the
  earlier rules rather than merge them.
- A required value is missing, a default is defined, or an integer is outside
  its declared bounds.
- A non-integer value carries `min`/`max`, which bound its length instead of
  its numeric value.
- An enum value is not included in its comma-separated choices.
- Several keys fail at once and must all be reported.
- Documentation is requested for an empty schema or an unsupported format.
- An optional file is absent, so the merge must continue rather than fail.
- A file is named like an option, so `--` has to end the flag list.
- A profile is requested with no name, with a name that is not a bare word, or
  for a base file that has no extension.
- A profile overlay file does not exist beside its base file.
- A save is asked for a key that is not set, for a key a dotenv file cannot
  spell, or for a file whose extension names no supported format.
- A save names no keys at all, so every loaded key is written.
- A dotenv file assigns the same key twice, so every occurrence has to be
  rewritten rather than only the first.
- A saved value is empty, holds a `#`, whitespace, a backslash, a quote, or a
  newline, and must survive the round trip.
- A structured root is a sequence or a scalar rather than a mapping, which must
  be rejected instead of loaded under positional keys.
- `DRY_RUN` is set, so a save reports the write instead of performing it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST maintain a shared key/value configuration map.
- **FR-002**: `config_load` MUST require at least one file and support `.env`,
  `.dotenv`, `.json`, `.yaml`, `.yml`, and `.toml` files.
- **FR-003**: Configuration files MUST be applied from left to right, with
  later files taking precedence.
- **FR-004**: Dotenv loading MUST parse comments, whitespace, single quotes,
  double quotes, and escaped double-quoted values without sourcing the file.
- **FR-005**: JSON loading MUST use `jq`, require an object root, and reject
  malformed data or invalid keys.
- **FR-006**: YAML and TOML loading MUST use the supported `yq` interface,
  determine the root's tag before reading entries, require a mapping root, and
  reject malformed data or invalid keys.
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
- **FR-013**: `config_schema` MUST declare `string`, `int` (`integer`), `bool`
  (`boolean`), `url`, or `enum` types for valid configuration keys, and MUST
  record declaration order.
- **FR-014**: Schema rules MUST support `required`, `default`, `min`, `max`,
  `choices`, and `description`, and MUST reject unsupported rule names, types,
  and malformed rule values.
- **FR-015**: `config_validate` MUST apply declared defaults for missing keys
  and reject missing required keys that have no default.
- **FR-016**: Validation MUST enforce integer, boolean, URL, and enum values,
  apply `min`/`max` as numeric bounds for `int` and as length bounds otherwise.
- **FR-017**: Validation MUST report every violation, each naming its key, and
  MUST expose them through `DYBATPHO_CONFIG_ERRORS`.
- **FR-018**: Re-declaring a key MUST replace its previous rules, and
  `config_schema_reset` MUST forget every declared schema.
- **FR-019**: `config_doc` MUST render the declared schema in declaration order
  as `markdown`, `text`, or `json`, and MUST reject other formats.
- **FR-020**: `config_load` MUST accept a leading `--optional` that skips files
  that do not exist, and a `--` that ends the flag list.
- **FR-021**: `config_profile` MUST load a base file and then, optionally, the
  sibling file whose name inserts the profile before the base extension.
- **FR-022**: `config_profile` MUST take the profile from its second argument
  or from `DYBATPHO_CONFIG_PROFILE`, and MUST reject an empty profile, a
  profile that is not a bare word, and a base file with no extension.
- **FR-023**: `config_set` MUST store a validated key and value in the shared
  configuration map.
- **FR-024**: `config_save` MUST write the named keys, or every loaded key when
  none are named, to a file whose extension selects the format, MUST create the
  file when it is absent, MUST write atomically, and MUST honor `DRY_RUN`.
- **FR-025**: Saving to a dotenv file MUST rewrite every assignment of a named
  key in place, preserve every other line verbatim, append keys the file does
  not mention, and quote and escape values the loader could not otherwise read
  back unchanged.
- **FR-026**: Saving to a JSON, YAML, or TOML file MUST assign each key through
  `jq` or `yq` so that unnamed keys and the document's own comments and layout
  survive, and MUST pass values through the environment rather than the command
  line.
- **FR-027**: A saved value MUST be written as a number or a boolean when its
  schema declares `int` or `bool` and the value matches that type, and as a
  string otherwise.
- **FR-028**: `config_save` MUST reject a key that is not set, a key a dotenv
  file cannot spell, an unsupported format, and an empty key list.
- **FR-029**: Loading JSON, YAML, or TOML MUST store every value of a nested
  mapping under its dotted path (`server.port`), MUST store a sequence or an
  empty mapping under its own key as compact JSON without walking into it, and
  MUST keep tabs, line breaks, and backslashes in values; the `jq` and `yq`
  backends MUST produce the same keys and values.

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
  `DYBATPHO_CONFIG_SCHEMA`, ordered by `DYBATPHO_CONFIG_SCHEMA_KEYS`.
- **Validation Report**: The `DYBATPHO_CONFIG_ERRORS` array holding one
  key-specific message per violation from the last validation run.
- **Profile Overlay**: The sibling file whose name inserts a profile before the
  base file's extension, loaded after the base file and allowed to be absent.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A script can load layered dotenv/JSON/YAML configuration with one
  call per file set.
- **SC-002**: Environment overlays consistently take precedence over files.
- **SC-003**: Missing required settings fail before dependent work runs.
- **SC-004**: Shell-compatible settings can be exported without unsafe sourcing.
- **SC-005**: Merged configuration can be validated consistently before
  application startup, with defaults applied in one step.
- **SC-006**: A single validation run names every misconfigured key, so an
  operator does not need repeated runs to find all problems.
- **SC-007**: The published configuration reference is generated from the same
  schema that validation enforces, so the two cannot drift.
- **SC-008**: A per-environment overlay needs one call, and works unchanged on
  a machine that has no file for that environment.
- **SC-009**: A setting can be changed and written back without a hand-rolled
  rewrite, and the file a human maintains comes back with its comments,
  ordering, and structure intact.
- **SC-010**: A value written to a file is the value the next load returns.

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
- **IT-009**: Declare long type aliases, re-declare a key, and verify the later
  rules replace the earlier ones.
- **IT-010**: Fail several keys at once and verify each is reported by name.
- **IT-011**: Render the schema as Markdown, text, and JSON, and reject an
  unsupported format.
- **IT-012**: Set values through `config_set` and reject an invalid key.
- **IT-013**: Merge files with `--optional`, skipping the absent ones, and
  verify that the same file is still an error without the flag.
- **IT-014**: Overlay a profile file, fall back to the base when the profile
  has no file, read the profile from `DYBATPHO_CONFIG_PROFILE`, and reject a
  missing profile, an invalid name, and an extensionless base file.
- **IT-015**: Rewrite a commented dotenv file in place and verify the comments,
  the blank line, the order, the untouched keys, and both assignments of a
  repeated key.
- **IT-016**: Round-trip values holding whitespace, a `#`, a backslash, a
  quote, a tab, and a newline, and create a file that did not exist.
- **IT-017**: Save every loaded key when none are named, and verify `DRY_RUN`
  leaves the file untouched.
- **IT-018**: Reject an unset key, an invalid key, an unsupported format, and a
  key a dotenv file cannot spell.
- **IT-019**: Load a real TOML mapping and a real YAML mapping, and reject a
  sequence root and a malformed document.
- **IT-020**: Save to real YAML, JSON, and TOML files and verify the comments,
  the untouched keys, and the number and boolean scalars the schema selects.
- **IT-021**: Load the same nested document as JSON, YAML, and TOML and verify
  each dotted key, the sequence kept as JSON, the empty mapping, and a value
  holding a tab and a backslash; then verify a `config:server.port` binding
  reads the nested value.

## Acceptance Criteria *(mandatory)*

1. Configuration behavior is deterministic and does not execute configuration
   files as shell programs.
2. File, environment, lookup, validation, and export workflows use one shared
   precedence model.
3. Failures identify the invalid file, key, prefix, or missing requirement.
4. Writing a file preserves everything the call was not asked to change, and a
   value written is the value the next load returns.
