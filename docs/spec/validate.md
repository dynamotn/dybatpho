# Feature Specification: Shared Value Validation

**Feature Branch**: `[reverse-spec-validate]`
**Status**: Implemented
**Input**: Existing source analysis: `src/validate.sh`, `docs/validate.md`, `test/validate.bats`, and `example/validate_ops.sh`, plus the call sites in `src/config.sh` and `src/cli.sh`

## Problem Statement *(mandatory)*

Every module that accepted a value from outside the script wrote its own check.
`config` matched an integer with one regular expression and a URL with another,
`cli` matched a shell variable name with a third, and each of them phrased its
rejection differently. A script that wanted something the library did not
already check — an email address, a port, an existing directory — had nowhere
to get it and wrote a fourth regular expression of its own.

Three costs followed. The expressions drifted, because a fix applied to one
copy never reached the others. The messages drifted with them, so the same
mistake read differently depending on which door the value came through. And
the set of checks stopped at whatever the two modules happened to need, which
left every consumer writing the rest by hand.

## Business Value *(mandatory)*

- One place to fix a validation rule, so a correction reaches every caller.
- One vocabulary of types, so a value is checked the same way whether it
  arrives on the command line, from a configuration file, or from a script's
  own logic.
- One phrasing of every rejection, so a user reads the same sentence wherever
  the value was refused.
- A check for the shapes scripts actually deal with — email, URL, IP, CIDR,
  host name, semantic version, UUID, MAC, date, duration, and existing paths —
  instead of a regular expression per script.
- A registration point, so a project's own types become first-class and work
  everywhere the built-in types do.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Check a value against a named type (Priority: P1)

As a script author, I want to ask whether a value is an email address, a port,
or an existing directory without writing the check myself.

**Independent Test**: Call `validate_is` with each built-in type over values
that should pass and values that should fail, and verify the exit code.

**Acceptance Scenarios**:

1. **Given** a registered type and a value of that type, **When**
   `validate_is TYPE VALUE` runs, **Then** it succeeds and prints nothing
2. **Given** a value that is not of the type, **When** `validate_is` runs,
   **Then** it fails and prints nothing
3. **Given** a type name nobody registered, **When** `validate_is` runs,
   **Then** it stops the script and names the unknown type
4. **Given** an alias such as `integer` or `boolean`, **When** `validate_is`
   runs, **Then** it behaves exactly as the canonical name would

### User Story 2 - Validate a value against declared rules (Priority: P1)

As a script author, I want to state a value's type and its constraints
together and be told everything that is wrong with it, not only the first
thing.

**Independent Test**: Validate a value that breaks several rules at once and
verify that every violation is reported.

**Acceptance Scenarios**:

1. **Given** a value satisfying every rule, **When** `validate_value` runs,
   **Then** it succeeds and records no reason
2. **Given** a value breaking several rules, **When** `validate_value` runs,
   **Then** it fails and records one reason per violation
3. **Given** a value that is not of its declared type, **When**
   `validate_value` runs, **Then** it records the type failure alone and does
   not go on to measure the value
4. **Given** a rule that is malformed, names an unsupported rule, or names an
   unregistered type, **When** `validate_value` runs, **Then** it stops the
   script and names what it could not accept

### User Story 3 - Stop the script on a bad value (Priority: P2)

As a script author, I want one call that validates a value and ends the run
with a usable diagnostic when it is rejected.

**Independent Test**: Call `validate_or_die` with an accepted and a rejected
value and verify that one is silent and the other names the value and every
reason.

**Acceptance Scenarios**:

1. **Given** a value that passes, **When** `validate_or_die` runs, **Then** it
   returns without output
2. **Given** a value that fails, **When** `validate_or_die` runs, **Then** it
   stops the script with `Invalid <label>: <reason>`, with several reasons
   joined by `; `

### User Story 4 - Register a type of your own (Priority: P2)

As a script author, I want my project's own notion of a valid value to work
everywhere a built-in type does.

**Independent Test**: Register a type, use it through `validate_is`,
`validate_value`, a `config` schema, and a `cli` option, then reset the
registry and verify the type is gone.

**Acceptance Scenarios**:

1. **Given** a predicate function, **When** `validate_register` runs, **Then**
   the type is usable by name everywhere a built-in type is
2. **Given** a registered type, **When** `validate_describe` runs, **Then** it
   prints the description that was registered with it
3. **Given** a malformed name, a predicate that is not a function, or an empty
   description, **When** `validate_register` runs, **Then** it stops the script
4. **Given** custom types have been registered, **When** `validate_reset` runs,
   **Then** they are forgotten and the built-ins are restored

### User Story 5 - Configure a key by type (Priority: P1)

As an operator, I want a configuration schema to declare `email`, `port`, or
`dir` and to be told which key in my file is wrong and why.

**Independent Test**: Declare a schema using types `config` never implemented,
load a file that violates them, and verify every key is reported.

**Acceptance Scenarios**:

1. **Given** a schema declaring any registered type, **When**
   `config_validate` runs over a violating file, **Then** each key is reported
   with the description of the type it should have had
2. **Given** a schema declaring a numeric type with `min:`/`max:`, **When**
   validation runs, **Then** the bounds apply to the value; for any other type
   they apply to the character count
3. **Given** a schema declaring a type nobody registered, **When**
   `config_schema` runs, **Then** it stops the script

### User Story 6 - Constrain a command-line option by type (Priority: P1)

As a CLI author, I want `--port` to accept only a port and `--contact` only an
email address, without writing a validator function.

**Independent Test**: Declare options with `type:` and verify an accepted
value, a rejected value, the help annotation, and a spec naming an unknown
type.

**Acceptance Scenarios**:

1. **Given** an option declared `type:<name>`, **When** a matching value is
   passed, **Then** the parser accepts it
2. **Given** the same option, **When** a non-matching value is passed, **Then**
   the parser refuses it and names the shape the value should have had
3. **Given** a spec naming a type nobody registered, **When** the parser is
   generated, **Then** generation fails rather than the first parse
4. **Given** an option declared `type:<name>`, **When** help, the man page, or
   the JSON schema is generated, **Then** the declared type appears in each

### Example Workflow

```bash
. dybatpho/init.sh --modules validate

# One value, one type.
dybatpho::validate_is email "${contact}" || dybatpho::die "Not an address"

# One value, several rules, every violation reported.
if ! dybatpho::validate_value "${port}" type:int min:1 max:65535; then
  dybatpho::error "$(dybatpho::validate_errors)"
fi

# Or stop the script outright.
dybatpho::validate_or_die "--release" "${version}" type:semver

# A type of your own, usable everywhere the built-ins are.
function _is_service { [[ "$1" =~ ^[a-z]+-(api|worker)$ ]]; }
dybatpho::validate_register service _is_service "a service name"

# The same vocabulary from a config schema and a CLI option.
dybatpho::config_schema ADMIN_EMAIL email required:true
dybatpho::opts::param "Port" PORT --port type:port
```

## Edge Cases

- A type name arrives in a different case, or as one of the accepted aliases.
- A predicate is asked about the empty string, or about a value holding only
  whitespace.
- A numeric value is written with leading zeros, which shell arithmetic reads
  as octal, or as a fraction or an exponent, which shell arithmetic cannot read
  at all.
- A port or a prefix length is written with enough digits to overflow the
  comparison that would reject it.
- An IPv4 octet carries a leading zero, which `inet_aton` reads as octal.
- An IPv6 address abbreviates with `::` more than once, carries a dotted IPv4
  tail, or carries a zone index.
- A date names the 29th of February in a year that has no such day, or a day
  past the end of its month.
- A host name exceeds 253 characters, or one of its labels exceeds 63.
- A path type is asked about a file that has not been created yet, where what
  must exist is the directory it will land in.
- A regular expression supplied by a caller is malformed, which Bash answers
  with exit status 2 and a diagnostic of its own.
- `min:` and `max:` are declared on a type that is not numeric.
- A caller registers a type that already exists.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST depend only on the core modules, so that
  `config` and `cli` can load it unconditionally without dragging in a
  heavier module.
- **FR-002**: `validate_is` MUST return success when a value is of a named
  type, failure when it is not, and MUST stop the script when the type is not
  registered. It MUST print nothing in any of those cases.
- **FR-003**: A type name MUST be matched without regard to case, and the
  aliases `integer`, `unsigned`, `boolean`, `uri`, `host`, `directory`, `link`,
  `writeable`, `varname`, and `notempty` MUST resolve to their canonical types.
- **FR-004**: The built-in types MUST cover `string`, `nonempty`, `int`,
  `uint`, `number`, `bool`, `port`, `email`, `url`, `hostname`, `ipv4`, `ipv6`,
  `ip`, `cidr`, `mac`, `semver`, `uuid`, `hex`, `alpha`, `alnum`, `slug`,
  `identifier`, `date`, `time`, `duration`, `path`, `file`, `dir`, `symlink`,
  `readable`, `writable`, `executable`, `abspath`, and `parent_dir`.
- **FR-005**: `ipv4` and `ipv6` MUST accept and reject exactly what
  `dybatpho::is_ipv4` and `dybatpho::is_ipv6` accept and reject, and `semver`
  MUST agree with `dybatpho::semver_valid`.
- **FR-006**: `port` MUST accept 1 through 65535 and MUST reject 0 and any
  value long enough to overflow the comparison.
- **FR-007**: `date` MUST check the day against the length of its month,
  including February in a leap year.
- **FR-008**: `hostname` MUST limit the whole name to 253 characters and each
  label to 63, MUST refuse a label starting or ending with a hyphen, and MUST
  accept a single trailing dot.
- **FR-009**: The path types MUST ask the filesystem, and `abspath` MUST ask
  only about the shape of the path so that it answers for a file that does not
  exist yet.
- **FR-010**: `validate_matches` MUST apply an extended regular expression and
  MUST turn a malformed expression into the library's own fatal error rather
  than reporting it as a failed match.
- **FR-011**: `validate_value` MUST support the rules `type:`, `pattern:`,
  `choices:`, `min:`, `max:`, `minlen:`, and `maxlen:`, and MUST default the
  type to `string`.
- **FR-012**: `validate_value` MUST record every violation it finds, and MUST
  stop after a type failure rather than measuring a value that is not of its
  type.
- **FR-013**: `min:` and `max:` MUST bound the value itself for a numeric type
  and the character count for every other type, while `minlen:` and `maxlen:`
  MUST always bound the character count.
- **FR-014**: Numeric comparison MUST handle a value written with leading
  zeros, a fraction, or an exponent, none of which shell arithmetic reads
  correctly, and MUST not depend on the host's locale for the radix character.
- **FR-015**: `validate_value` MUST stop the script when a rule is not in
  `name:value` form, names an unsupported rule, carries a non-numeric bound, an
  empty choice list, or an unregistered type.
- **FR-016**: `validate_errors` MUST print the reasons recorded by the last
  `validate_value` call, one per line, and nothing when it succeeded.
- **FR-017**: `validate_or_die` MUST stop the script with
  `Invalid <label>: <reason>`, joining several reasons with `; `.
- **FR-018**: `validate_register` MUST bind a type to a predicate and a
  description, MUST accept an optional `numeric` marker, MUST replace a type
  that already exists, and MUST stop the script on a malformed name, a
  predicate that is not a function, or an empty description.
- **FR-019**: `validate_describe` MUST print the description registered for a
  type, resolving aliases, and MUST stop the script for an unregistered type.
- **FR-020**: `validate_types` MUST print the canonical type names, one per
  line, in alphabetical order, and MUST NOT print aliases.
- **FR-021**: `validate_reset` MUST forget every registered custom type and
  restore the built-ins to their original predicates.
- **FR-022**: `config_schema` MUST accept any registered type, plus `enum`,
  and `config_validate` MUST report a rejected value using the description the
  validator holds for that type.
- **FR-023**: `dybatpho::opts::flag` and `dybatpho::opts::param` MUST accept
  `type:<name>`, MUST fail while generating the parser when the type is not
  registered, and MUST report a rejected value as
  `Expected <description>: <value>`.
- **FR-024**: A declared `type:` MUST appear in generated help and man output
  as `[type: <name>]` and in the generated JSON schema as `valueType`.

### Key Entities *(include if feature involves data)*

- **Type**: A name bound to a predicate function and to the description a
  message uses for it.
- **Alias**: A second name resolving to a canonical type, so two spellings
  cannot drift apart.
- **Numeric Type**: A type whose `min:`/`max:` bound the value rather than its
  character count.
- **Rule**: One `name:value` constraint applied by `validate_value`.
- **Reason**: One recorded violation, phrased to follow the name of whatever
  was validated.
- **`DYBATPHO_VALIDATE_ERRORS`**: The reasons recorded by the last
  `validate_value` call.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A validation rule exists in exactly one place in the library, so
  a correction to it reaches `config`, `cli`, and every script at once.
- **SC-002**: The same bad value produces the same sentence whether it arrived
  on the command line or from a configuration file.
- **SC-003**: A configuration schema can declare any of the shapes scripts
  deal with, without `config` implementing a single further check.
- **SC-004**: A command-line option can be constrained to a shape without the
  author writing a validator function or a glob.
- **SC-005**: A broken configuration file reports every violating key in one
  run rather than one per run.
- **SC-006**: A project's own type is usable everywhere a built-in type is,
  after one registration call.

## Integration Tests *(mandatory)*

- **IT-001**: Accept and reject values for each numeric, boolean, and port
  type, including the overflow and leading-zero cases.
- **IT-002**: Accept practical email addresses and URLs, and reject the near
  misses: a missing scheme, a missing domain dot, a leading hyphen.
- **IT-003**: Check host names label by label, including the length limits.
- **IT-004**: Accept and reject IPv4, IPv6, IP, and CIDR values, including a
  leading-zero octet, a doubled `::`, a zone index, and an out-of-range prefix.
- **IT-005**: Verify `ipv4`, `ipv6`, and `semver` answer exactly as
  `dybatpho::is_ipv4`, `dybatpho::is_ipv6`, and `dybatpho::semver_valid` do.
- **IT-006**: Accept and reject UUID, MAC, hex, alpha, alnum, slug, identifier,
  and nonempty values.
- **IT-007**: Check a date against the length of its month and reject an
  impossible time.
- **IT-008**: Accept a duration with and without units.
- **IT-009**: Verify each path type against a real temporary file, directory,
  symlink, and absent path, including `parent_dir` and `executable`.
- **IT-010**: Resolve long-form and differently cased type names.
- **IT-011**: Verify an unregistered type stops the script from `validate_is`,
  `validate_describe`, and `validate_value`.
- **IT-012**: Apply and fail a regular expression, and verify a malformed one
  becomes a fatal error.
- **IT-013**: Verify `min:`/`max:` bound a numeric type by value and any other
  type by length, and that `minlen:`/`maxlen:` always bound the length.
- **IT-014**: Verify numbers with leading zeros, fractions, and negative
  bounds compare correctly.
- **IT-015**: Verify `choices:` and `pattern:` rules, and that several
  violations are all reported while a type failure is reported alone.
- **IT-016**: Verify every malformed rule stops the script.
- **IT-017**: Verify `validate_or_die` is silent on success and names the label
  and every reason on failure.
- **IT-018**: Verify `validate_describe` and `validate_types`, including that
  aliases are not listed.
- **IT-019**: Register a type, use it through `validate_is` and
  `validate_value`, replace a built-in, reject malformed registrations, and
  verify `validate_reset` restores the built-ins.
- **IT-020**: Declare a `config` schema using types `config` never implemented,
  including a custom one, and verify each violating key is reported.
- **IT-021**: Verify a `config` schema bounds a port by value and a string by
  length.
- **IT-022**: Verify a `cli` option declared with `type:` accepts, rejects,
  fails at generation on an unknown type, and appears in help, the man page,
  and the JSON schema.
- **IT-023**: Verify `validate` is loaded ahead of `config` and reachable from
  a script that asked only for `cli`.

## Acceptance Criteria *(mandatory)*

1. No module in `src/` implements a check that `validate` already owns.
2. Every rejection anywhere in the library is worded from the same
   description, so the same mistake reads the same way.
3. A caller can add a type in one call and use it everywhere the built-ins
   work, including in a configuration schema and on a command-line option.
4. A value written the way real files write it — leading zeros, fractions,
   trailing dots, abbreviated addresses — is judged rather than mishandled.
