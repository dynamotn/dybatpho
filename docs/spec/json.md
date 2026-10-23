# Feature Specification: JSON and YAML Utilities

**Feature Branch**: `[reverse-spec-json]`
**Status**: Implemented
**Input**: Existing source analysis: `src/json.sh`, `docs/json.md`, `test/json.bats`, and `example/json_ops.sh`

## Problem Statement *(mandatory)*

Shell scripts often need to query, validate, pretty-print, and convert JSON or YAML documents, but direct `jq` and `yq` usage quickly becomes repetitive and inconsistent across scripts. Worse, the two programs speak different filter languages: a helper that ran a caller's filter through whichever one was installed answered differently from one machine to the next (`keys` order, `1.0` versus `1`, large integers turned into floats) and rejected ordinary `jq` such as `add` and `?` on hosts that had `yq`.

## Business Value *(mandatory)*

- Give every caller-written filter one language, `jq`'s, and one engine, `jq`, so a script prints the same result on every machine.
- Use the Go `yq` v4 only where YAML is involved: to read YAML (or TOML) into JSON, to write YAML back, and to edit a YAML file in place without losing its comments.
- Keep shell scripts readable when querying JSON or YAML.
- Provide one module for both machine-friendly JSON and operator-friendly YAML tasks.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Query JSON data cleanly (Priority: P1)

As a script author, I want helpers that wrap `jq` for common JSON queries and checks so that structured-data lookups stay readable in shell scripts and answer the same everywhere.

**Why this priority**: JSON is a common interchange format in APIs and CLI tools.

**Independent Test**: Query a JSON document, check for a field with predicate semantics, and verify pretty-print output, with and without `yq` on `PATH`.

**Acceptance Scenarios**:

1. **Given** a JSON document and a `jq` filter, **When** the query helper runs, **Then** it prints the matching result as `jq` does, with extra arguments such as `--arg` forwarded to `jq`
2. **Given** a JSON document and existence filter, **When** the check helper runs, **Then** it returns success only when the filter's last output is neither `false` nor `null`, and 1 when it has none
3. **Given** a host with `yq` installed and one without, **When** the same helper runs with the same filter, **Then** both print the same output
4. **Given** a host without `jq`, **When** any JSON helper but `json_string` runs, **Then** it stops with exit code 127 and a message naming `jq`

---

### User Story 1b - Assemble a JSON document safely (Priority: P1)

As a script author, I want to build a JSON document from shell values without
thinking about escaping, so that a quotation mark in a log line or a newline in
a commit message cannot corrupt the payload I am about to send.

**Why this priority**: hand-built JSON is the most common way a shell script
silently produces invalid output.

**Independent Test**: Build an object from values containing quotes,
backslashes, and newlines, then read each value back and compare it with the
original.

**Acceptance Scenarios**:

1. **Given** values containing JSON-sensitive characters, **When** an object is
   built, **Then** every value round-trips unchanged
2. **Given** a name carrying the `:json` suffix, **When** an object is built,
   **Then** the value is nested as a document rather than quoted as a string
3. **Given** a document held in a variable, **When** a filter is evaluated,
   **Then** the result is available either as compact JSON or as a bare scalar
4. **Given** a host with or without `yq`, **When** the same helpers run,
   **Then** they produce the same result

---

### User Story 2 - Query YAML data cleanly (Priority: P1)

As a script author, I want to query YAML with the same `jq` filters I write for JSON, so that configuration-file lookups stay readable and I learn one language.

**Why this priority**: YAML is common in CI, deployment, and config workflows.

**Independent Test**: Query a YAML document with `jq` filters, check for a field, and verify pretty-print output; repeat without `yq`, and with a Python `yq` on `PATH`.

**Acceptance Scenarios**:

1. **Given** a YAML document and a `jq` filter, **When** the query helper runs, **Then** it prints every result as YAML, one scalar per line
2. **Given** a YAML document and existence filter, **When** the check helper runs, **Then** it returns success only when the filter succeeds
3. **Given** a host without `yq`, **When** a YAML helper runs, **Then** it stops with exit code 127 and a message naming the Go `yq` v4
4. **Given** the Python `yq` or a Go `yq` older than v4 on `PATH`, **When** a YAML helper runs, **Then** it stops with exit code 127 and names what it found

---

### User Story 3 - Convert between JSON and YAML (Priority: P2)

As a maintainer, I want conversion helpers between JSON and YAML so that scripts can bridge API payloads and config files without custom command lines.

**Why this priority**: Conversion is a practical follow-up once both formats are supported in one module.

**Independent Test**: Convert JSON to YAML and YAML to JSON, then verify both stdout and output-file workflows.

**Acceptance Scenarios**:

1. **Given** a JSON document, **When** the conversion helper runs, **Then** it prints or writes YAML output
2. **Given** a YAML document, **When** the conversion helper runs, **Then** it prints or writes JSON output

---

### User Story 4 - Edit a document without hand-written filters (Priority: P1)

As a script author, I want to set, delete, and merge values in a JSON or YAML
file by path, so that bumping a version, toggling a flag, or layering an
override file never needs a filter assembled from shell variables, where one
quotation mark in a value would change what the filter does.

**Why this priority**: editing configuration in place is the most common write
a script makes to a structured document, and interpolating values into a
filter is the usual way that write goes wrong.

**Independent Test**: Set a nested string, a typed value, and a key containing
filter syntax; delete a key, an array element, and an absent path; merge two
objects; run each with and without `yq` on `PATH` and compare the results.

**Acceptance Scenarios**:

1. **Given** a path whose parents do not exist, **When** a value is set,
   **Then** the missing objects and arrays are created and the value is stored
   as a string
2. **Given** `--json`, **When** a value is set, **Then** it is parsed as JSON,
   so numbers, booleans, `null`, arrays, and objects keep their type
3. **Given** a value or a key containing quotes, newlines, or filter syntax,
   **When** it is set, **Then** it is stored verbatim and nothing else in the
   document changes
4. **Given** a path that runs through a scalar, or indexes the wrong kind of
   container, **When** a value is set, **Then** the call fails and an output
   file is left untouched
5. **Given** a path that does not exist, **When** it is deleted, **Then** the
   document is returned unchanged
6. **Given** two objects, **When** they are merged, **Then** nested objects are
   merged key by key and every other value comes from the overlay
7. **Given** a YAML document with comments, **When** it is edited, **Then** the
   comments are kept
8. **Given** an output file equal to the input, **When** an edit succeeds,
   **Then** the file is replaced atomically with the result

---

### Example Workflow

```bash
# Read a value, guard on a filter, and convert between formats.
version="$(dybatpho::json_query package.json '.version')"

if dybatpho::json_has package.json '.scripts.test'; then
  dybatpho::info "package.json ${version} defines a test script"
fi

dybatpho::json_to_yaml package.json package.yaml
dybatpho::yaml_query package.yaml '.name'
dybatpho::yaml_query compose.yaml '.services | keys[]'   # a jq filter, sorted keys
dybatpho::json_query data.json '.items[] | select(.name == $n)' --arg n api
curl -sSf https://api.example.test/status | dybatpho::json_pretty -

# Edit in place by path, and layer an override file.
dybatpho::json_set package.json version 2.0.0 package.json
dybatpho::json_set --json package.json private true package.json
dybatpho::yaml_del compose.yaml services.debug compose.yaml
dybatpho::yaml_merge values.yaml values-prod.yaml > rendered.yaml
```

## Edge Cases

- `jq` is not installed, though `yq` is.
- `yq` is not installed, or is the Python `yq`, or a Go `yq` older than v4.
- A filter written for `yq` (`strenv`, `tag`, `downcase`, `ireduce`, `eval`)
  reaches a helper: it fails as `jq` reports it.
- A filter ends in a `#` comment; the YAML query wraps it on its own lines so
  the comment cannot swallow what surrounds it.
- A YAML query has no result, or several: nothing is printed, or one YAML
  document per result without `---` separators.
- A YAML file holds an integer beyond 64 bits: `yq` refuses to convert it.
- The input document path is `-` for stdin.
- A `.toml` or `.json` file given to a YAML reader is parsed by its extension.
- The caller wants output on stdout or in a destination file.
- An editing path is empty, has an empty segment, ends in a lone `\`, or names
  an index too long to be a number.
- A key contains a `.`, a backslash, or consists of digits only, which the path
  writes as `\.`, `\\`, and `\0` respectively.
- A path indexes past the end of an array: setting pads with `null`, deleting
  changes nothing.
- A `--json` value is `null` or `false`, which is a valid value to store.
- A document checked with `json_valid` is `null`, `false`, or blank.
- A merge input is an array, a scalar, `null`, or empty.
- `yq`, which edits YAML in place, would otherwise ignore an assignment
  through a scalar and pad an array when deleting a missing index; the YAML
  editors make it behave as the JSON editors do.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The module MUST provide a JSON query helper that runs a `jq` filter through `jq`, forwarding extra arguments to `jq`.
- **FR-002**: The module MUST provide a JSON predicate helper with `jq -e` semantics, returning 1 when the last output is `false` or `null` or there is none, and `jq`'s own status for an error.
- **FR-003**: The module MUST provide a JSON pretty-print helper built on `jq`.
- **FR-004**: The module MUST provide a JSON-to-YAML conversion helper built on `yq`.
- **FR-005**: The module MUST provide a YAML query helper that reads the document into JSON with `yq`, runs a `jq` filter through `jq`, and prints every result back as YAML.
- **FR-006**: The module MUST provide a YAML predicate helper with the same semantics as the JSON one, over the document read into JSON.
- **FR-007**: The module MUST provide a YAML pretty-print helper.
- **FR-008**: The module MUST provide a YAML-to-JSON conversion helper whose JSON is laid out by `jq`.
- **FR-009**: The output-oriented helpers MUST support stdout output and optional destination files where applicable.
- **FR-010**: The module MUST provide a helper that encodes an arbitrary string
  as a JSON string value, escaping quotes, backslashes, and control characters.
- **FR-011**: The module MUST provide a helper that builds a JSON object from
  name and value pairs, escaping every value, and MUST insert a value as-is when
  its name carries the `:json` suffix.
- **FR-012**: The object helper MUST reject an odd number of arguments.
- **FR-013**: The module MUST provide helpers that evaluate a filter against a
  document held in a shell variable, one returning compact JSON and one
  returning a bare scalar.
- **FR-014**: The module MUST provide a predicate that reports whether a string
  held in a shell variable is valid JSON.
- **FR-015**: The in-memory helpers MUST behave identically whether or not
  `yq` is installed.
- **FR-016**: The module MUST provide `json_set` and `yaml_set`, which store a
  value at a path, creating missing objects and arrays, and store the value as
  a string unless `--json` asks for it to be parsed as JSON.
- **FR-017**: A path MUST be a `.`-separated list of segments, with one optional
  leading `.`; a segment of digits only MUST address an array element, and a
  backslash MUST make the next character literal, so `\.`, `\\`, and `\0`
  name a key containing a dot, a backslash, and the key `0`.
- **FR-018**: A malformed path, a `--json` value that is not JSON, and a wrong
  argument count MUST be rejected with a message before `jq` or `yq` runs.
- **FR-019**: Setting a value through a scalar, an object key on an array, or
  an array index on an object MUST fail in JSON and in YAML with the same message.
- **FR-020**: The module MUST provide `json_del` and `yaml_del`, which remove
  the value at a path and MUST leave the document unchanged when the path does
  not exist.
- **FR-021**: The module MUST provide `json_merge` and `yaml_merge`, which
  deep-merge two objects with the overlay winning and MUST refuse a document
  that is not an object.
- **FR-022**: Paths and values MUST reach `jq` or `yq` as arguments or
  environment variables, never as part of the expression text.
- **FR-023**: The editing helpers MUST print the result when no output file is
  given, and MUST otherwise write the output file atomically, only after the
  command succeeded, so the output may be the input and a failure leaves it
  untouched.
- **FR-024**: The JSON editing helpers MUST run through `jq` and produce the
  same document whether or not `yq` is installed; the YAML editing helpers
  MUST edit the file with `yq` itself, keeping its comments, and MUST NOT
  need `jq`.
- **FR-025**: `json_valid` MUST accept any JSON value, `null` and `false`
  included, and MUST refuse blank text.
- **FR-026**: Every filter a caller passes MUST run through `jq`, whatever else is installed; no helper MAY choose its filter engine by what it finds on `PATH`.
- **FR-027**: Every helper but `json_string` MUST stop with exit code 127 and a message naming `jq` when `jq` is not installed.
- **FR-028**: Every helper that reads or writes YAML MUST stop with exit code 127 when `yq` is missing, and MUST refuse the Python `yq` and a Go `yq` older than v4 by name; the check MUST run once for as long as `PATH` is unchanged.
- **FR-029**: The module MUST declare `jq` 1.7 or newer to `dybatpho::doctor`, because `jq` 1.6 reads every number as a binary double and so does not keep a number as written; with `jq` 1.6 the helpers MUST still work.

### Key Entities *(include if feature involves data)*

- **Filter**: A caller-provided `jq` filter used to query or validate JSON or
  YAML input; it is the module's one filter language.
- **Structured Document**: An input JSON or YAML file path, or `-` for stdin.
- **In-Memory Document**: A JSON string a script is still assembling, held in a
  shell variable rather than written to a file.
- **Document Path**: A `.`-separated list of object keys and array indices,
  such as `spec.ports.0.name`, naming one value in a document for editing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Scripts can express common JSON and YAML queries without repeating raw `yq` and `jq` command lines.
- **SC-006**: The same filter over the same document prints the same bytes on every supported platform, with or without `yq` installed.
- **SC-002**: Predicate-style helpers are easy to use in shell control flow.
- **SC-003**: Conversion between JSON and YAML is available through a small reusable API.
- **SC-004**: A script can assemble a JSON document containing arbitrary text
  without thinking about escaping.
- **SC-005**: A script can set, delete, and merge values in a JSON or YAML file
  without writing a filter, and no value it stores can change the edit itself.

## Integration Tests *(mandatory)*

- **IT-001**: Query a JSON document with `jq` filters (`--arg`, sorted `keys`,
  `add`, `?`, `def`) and verify the expected value is printed.
- **IT-002**: Check JSON existence semantics: success, 1 for `null`, `false`
  and no output, another status for an invalid filter.
- **IT-003**: Query a YAML document with `jq` filters, from a file, stdin and a
  TOML file, and verify each result prints as YAML, one scalar per line.
- **IT-004**: Check YAML existence semantics and verify success/failure behavior.
- **IT-005**: Convert JSON to YAML and YAML to JSON with both stdout and
  output-file workflows; the JSON matches `jq`'s layout.
- **IT-006**: Encode strings containing quotes, backslashes, newlines, and
  nothing at all, and verify the result is a valid JSON string value.
- **IT-007**: Build objects with escaped values, nested `:json` documents, and
  awkward names, and verify an odd argument count is rejected.
- **IT-008**: Evaluate filters against in-memory documents and verify compact
  JSON, bare scalars, and the alternative operator.
- **IT-009**: Verify the JSON predicate separates documents from prose and from
  truncated input.
- **IT-010**: Verify the in-memory helpers produce the same results with and
  without `yq` on `PATH`.
- **IT-011**: Set nested values, creating missing objects and arrays, and
  compare the result with and without `yq` on `PATH`.
- **IT-012**: Set values with and without `--json`, including `null`, `true`,
  numbers, and nested documents.
- **IT-013**: Set a value and a key containing quotes, newlines, and filter
  syntax, and verify nothing else in the document changes.
- **IT-014**: Read `\.`, `\\`, `\0`, and a key with spaces from a path.
- **IT-015**: Refuse a path through a scalar or the wrong kind of container
  with and without `yq` on `PATH`, with the same message.
- **IT-016**: Reject malformed paths, a non-JSON `--json` value, and a wrong
  argument count.
- **IT-017**: Write an edit in place, and leave the file untouched when the
  edit fails; read a document from stdin.
- **IT-018**: Delete keys and array elements, and leave the document unchanged
  for absent paths, out-of-range indices, and paths through scalars.
- **IT-019**: Deep-merge two objects, from files, from stdin, and in place, and
  refuse arrays, scalars, and `null` with and without `yq` on `PATH`.
- **IT-020**: Propagate a malformed document or filter, and fail with exit code
  127 when `jq` is missing for a JSON edit or `yq` for a YAML edit.
- **IT-021**: Edit, delete from, and merge YAML documents, keeping comments.
- **IT-022**: Accept `null`, `false`, `0`, a string and an object, and refuse blank
  text, a truncated object and prose.
- **IT-023**: Run the JSON query, `json_get`, `json_eval` and `json_object`
  with `yq` on `PATH` and hidden, and verify identical output.
- **IT-024**: Stop with 127 and a message naming `jq` when `jq` is missing but
  `yq` is installed.
- **IT-025**: Stop the YAML helpers with 127 when `yq` is missing while the JSON
  ones keep working, and name the Python `yq`, a pre-v4 Go `yq` and an
  unidentifiable one.
- **IT-026**: Ask `yq --version` once across several YAML calls under one `PATH`.

## Acceptance Criteria *(mandatory)*

1. Every caller filter is a `jq` filter run by `jq`; `yq` is used only to read and write YAML, and the module says which tool is missing or wrong.
2. Structured-data helpers remain composable in command substitution and shell conditionals.
3. JSON and YAML workflows are documented consistently with the rest of the project.
4. A JSON or YAML document can be edited by path and merged without the caller
   writing a filter, with the same result whether or not `yq` is installed.
